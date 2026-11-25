import AppKit
import ApplicationServices
import CoreGraphics

struct LayoutFailure: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

struct ManagedSpace {
    let id: UInt64
    let isDesktop: Bool
    let owner: pid_t?
}

@MainActor
struct MissionControl {
    let displayID = CGMainDisplayID()

    var displayUUID: String? {
        guard let uuid = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue() else { return nil }
        return CFUUIDCreateString(nil, uuid) as String?
    }

    func snapshot() throws -> (display: String, spaces: [ManagedSpace]) {
        let displays = WLCopyDisplays() ?? []
        let target = displays.first { ($0["Display Identifier"] as? String)?.caseInsensitiveCompare(displayUUID ?? "") == .orderedSame }
            ?? displays.first { ($0["Display Identifier"] as? String) == "Main" }
            ?? (displays.count == 1 ? displays.first : nil)
        guard let target, let identifier = target["Display Identifier"] as? String,
              let entries = target["Spaces"] as? [[String: Any]], !entries.isEmpty else {
            throw LayoutFailure("macOS не вернула список пространств основного дисплея.")
        }
        let spaces: [ManagedSpace] = entries.compactMap { entry in
            let id = (entry["id64"] as? NSNumber)?.uint64Value
                ?? (entry["ManagedSpaceID"] as? NSNumber)?.uint64Value
                ?? (entry["ManagedSpaceID"] as? String).flatMap(UInt64.init)
            guard let id, let type = entry["type"] as? NSNumber else { return nil }
            return ManagedSpace(id: id, isDesktop: type.intValue == 0, owner: (entry["pid"] as? NSNumber)?.int32Value)
        }
        guard spaces.count == entries.count else { throw LayoutFailure("Формат пространств Mission Control изменился.") }
        return (identifier, spaces)
    }

    private func displayControls() -> AXUIElement? {
        let processes = ["com.apple.WindowManager", "com.apple.dock"]
        let bounds = CGDisplayBounds(displayID)
        for bundle in processes {
            guard let pid = NSRunningApplication.runningApplications(withBundleIdentifier: bundle).first?.processIdentifier else { continue }
            let application = AXUIElementCreateApplication(pid)
            let root = application.children
            let candidates = root + root.filter { $0.identifier == "mc" || $0.identifier == "mc.displays" }.flatMap(\.children)
            for display in candidates where display.identifier == "mc.display" {
                guard let frame = display.frame, abs(frame.minX - bounds.minX) < 3, abs(frame.minY - bounds.minY) < 3 else { continue }
                if let controls = display.children.first(where: { $0.identifier == "mc.spaces" }) { return controls }
            }
        }
        return nil
    }

    private func open() async throws -> AXUIElement {
        if let controls = displayControls() { return controls }
        if !WLToggleMissionControl() {
            let url = URL(filePath: "/System/Applications/Mission Control.app", directoryHint: .isDirectory)
            _ = try await NSWorkspace.shared.openApplication(at: url, configuration: .init())
        }
        if let controls = try await wait(attempts: 24, for: displayControls) { return controls }
        close()
        throw LayoutFailure("Не удалось открыть панель Mission Control.")
    }

    private func close() {
        guard displayControls() != nil else { return }
        if WLToggleMissionControl() { return }
        CGEvent(keyboardEventSource: nil, virtualKey: 53, keyDown: true)?.post(tap: .cghidEventTap)
        CGEvent(keyboardEventSource: nil, virtualKey: 53, keyDown: false)?.post(tap: .cghidEventTap)
    }

    func createDesktop() async throws -> UInt64 {
        let previous = Set(try snapshot().spaces.map(\.id))
        let controls = try await open()
        var needsClose = true
        defer { if needsClose { close() } }
        guard let add = controls.children.first(where: { $0.identifier == "mc.spaces.add" })
                ?? controls.children.flatMap(\.children).first(where: { $0.identifier == "mc.spaces.add" }),
              add.press() else { throw LayoutFailure("Mission Control не позволила создать рабочий стол.") }
        if let desktop = try await wait(attempts: 24, for: {
            try snapshot().spaces.first { $0.isDesktop && !previous.contains($0.id) }
        }) {
            close()
            needsClose = false
            try await Task.sleep(for: .milliseconds(350))
            return desktop.id
        }
        throw LayoutFailure("Новый рабочий стол не появился в Mission Control.")
    }

    func reorder(_ ids: [UInt64]) async throws {
        for (target, id) in ids.enumerated() {
            let current = try snapshot()
            guard current.spaces.indices.contains(target) else { throw LayoutFailure("В Mission Control не хватает пространств.") }
            if current.spaces[target].id == id { continue }
            if WLMoveSpace(id, current.display, UInt64(target)),
               try await wait(attempts: 6, for: { try atIndex(id, target) ? true : nil }) != nil { continue }
            try await dragSpace(id, to: target)
        }
        guard Array(try snapshot().spaces.prefix(ids.count).map(\.id)) == ids else {
            throw LayoutFailure("Mission Control не подтвердила порядок пространств.")
        }
    }

    private func atIndex(_ id: UInt64, _ index: Int) throws -> Bool {
        let spaces = try snapshot().spaces
        return spaces.indices.contains(index) && spaces[index].id == id
    }

    private func dragSpace(_ id: UInt64, to index: Int) async throws {
        _ = try await open()
        var needsClose = true
        defer { if needsClose { close() } }
        let current = try snapshot().spaces
        guard current.indices.contains(index) else { throw LayoutFailure("Пространство исчезло во время расстановки.") }
        if current[index].id == id { return }
        guard let source = current.firstIndex(where: { $0.id == id }),
              let row = try await wait(attempts: 12, for: {
                  let children = displayControls()?.children.first { $0.identifier == "mc.spaces.list" }?.children
                  return children?.count == current.count ? children : nil
              }),
              let origin = row[source].frame, let destination = row[index].frame else {
            throw LayoutFailure("Не удалось прочитать расположение миниатюр Mission Control.")
        }
        let start = CGPoint(x: origin.midX, y: origin.midY)
        let direction: CGFloat = source > index ? -1 : 1
        let end = CGPoint(x: destination.midX + direction * destination.width / 4, y: destination.midY)
        try await drag(from: start, to: end)
        guard try await wait(attempts: 18, for: { try atIndex(id, index) ? true : nil }) != nil else {
            throw LayoutFailure("Эта версия macOS не подтвердила перенос пространства на позицию \(index + 1).")
        }
        close()
        needsClose = false
        try await Task.sleep(for: .milliseconds(350))
    }

    private func drag(from start: CGPoint, to end: CGPoint) async throws {
        let previous = CGEvent(source: nil)?.location
        var cursor = start
        func post(_ type: CGEventType, _ point: CGPoint) {
            CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
        }
        post(.mouseMoved, start)
        try await Task.sleep(for: .milliseconds(200))
        post(.leftMouseDown, start)
        defer {
            post(.leftMouseUp, cursor)
            if let previous { CGWarpMouseCursorPosition(previous) }
        }
        for step in 1...18 {
            try await Task.sleep(for: .milliseconds(35))
            let fraction = CGFloat(step) / 18
            cursor = CGPoint(x: start.x + (end.x - start.x) * fraction, y: start.y + (end.y - start.y) * fraction)
            post(.leftMouseDragged, cursor)
        }
        try await Task.sleep(for: .milliseconds(150))
    }
}

@MainActor
func wait<T>(attempts: Int, for probe: () throws -> T?) async throws -> T? {
    for _ in 0..<attempts {
        if let result = try probe() { return result }
        try await Task.sleep(for: .milliseconds(200))
    }
    return nil
}
