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
    private let removeDesktopAction = "AXRemoveDesktop"

    var displayUUID: String? {
        guard let uuid = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue() else { return nil }
        return CFUUIDCreateString(nil, uuid) as String?
    }

    func snapshot() throws -> (display: String, spaces: [ManagedSpace], active: UInt64?) {
        let displays = WLCopyDisplays() ?? []
        let target = displays.first { ($0["Display Identifier"] as? String)?.caseInsensitiveCompare(displayUUID ?? "") == .orderedSame }
            ?? displays.first { ($0["Display Identifier"] as? String) == "Main" }
            ?? (displays.count == 1 ? displays.first : nil)
        guard let target, let identifier = target["Display Identifier"] as? String,
              let entries = target["Spaces"] as? [[String: Any]], !entries.isEmpty else {
            throw LayoutFailure("macOS не вернула список пространств основного дисплея.")
        }
        let spaces: [ManagedSpace] = entries.compactMap { entry in
            guard let id = spaceID(entry), let type = entry["type"] as? NSNumber else { return nil }
            return ManagedSpace(id: id, isDesktop: type.intValue == 0, owner: (entry["pid"] as? NSNumber)?.int32Value)
        }
        guard spaces.count == entries.count else { throw LayoutFailure("Формат пространств Mission Control изменился.") }
        return (identifier, spaces, (target["Current Space"] as? [String: Any]).flatMap(spaceID))
    }

    private func spaceID(_ entry: [String: Any]) -> UInt64? {
        (entry["id64"] as? NSNumber)?.uint64Value
            ?? (entry["ManagedSpaceID"] as? NSNumber)?.uint64Value
            ?? (entry["ManagedSpaceID"] as? String).flatMap(UInt64.init)
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

    func removeDesktop(_ id: UInt64, keeping retained: Set<UInt64>, fallback: UInt64) async throws {
        let current = try snapshot()
        guard current.spaces.contains(where: { $0.id == id }) else { return }
        guard !retained.contains(id), current.spaces.contains(where: { $0.id == id && $0.isDesktop }),
              current.spaces.contains(where: { $0.id == fallback && $0.isDesktop }),
              retained.isSubset(of: Set(current.spaces.map(\.id))) else {
            throw LayoutFailure("Список рабочих столов изменился во время очистки.")
        }
        if current.active == id {
            try await switchToDesktop(fallback)
            try await Task.sleep(for: .milliseconds(350))
        }
        try await performDesktopRemoval(id, keeping: retained, fallback: fallback)
        try await Task.sleep(for: .milliseconds(350))
    }

    func prepareDesktopRemoval(_ ids: Set<UInt64>, fallback: UInt64) async throws {
        let current = try snapshot()
        guard let active = current.active, !ids.contains(fallback),
              ids.union([fallback]).isSubset(of: Set(current.spaces.filter(\.isDesktop).map(\.id))) else {
            throw LayoutFailure("Список рабочих столов изменился перед очисткой.")
        }
        if ids.contains(active) {
            try await switchToDesktop(fallback)
            try await Task.sleep(for: .milliseconds(350))
        }
        try await verifyDesktopRemovalActions(ids)
        try await Task.sleep(for: .milliseconds(350))
    }

    private func verifyDesktopRemovalActions(_ ids: Set<UInt64>) async throws {
        defer { close() }
        let buttons = try await spaceButtons()
        for id in ids {
            var actions: CFArray?
            guard let button = buttons[id],
                  AXUIElementCopyActionNames(button, &actions) == .success,
                  (actions as? [String])?.contains(removeDesktopAction) == true else {
                throw LayoutFailure("Mission Control не предоставила действие для удаления рабочего стола.")
            }
        }
    }

    private func switchToDesktop(_ id: UInt64) async throws {
        defer { close() }
        let button = try await spaceButton(id)
        guard button.press(), try await wait(attempts: 18, for: {
            try snapshot().active == id ? true : nil
        }) != nil else {
            throw LayoutFailure("Не удалось переключиться на рабочий стол, который остаётся после очистки.")
        }
    }

    private func performDesktopRemoval(_ id: UInt64, keeping retained: Set<UInt64>, fallback: UInt64) async throws {
        defer { close() }
        let button = try await spaceButton(id)
        let live = try snapshot()
        guard live.active != id, live.spaces.contains(where: { $0.id == fallback && $0.isDesktop }),
              retained.isSubset(of: Set(live.spaces.map(\.id))) else {
            throw LayoutFailure("Список рабочих столов изменился перед удалением.")
        }
        let result = AXUIElementPerformAction(button, removeDesktopAction as CFString)
        guard result == .success || result == .cannotComplete else {
            throw LayoutFailure("Mission Control не позволила удалить рабочий стол.")
        }
        guard try await wait(attempts: 18, for: {
            try snapshot().spaces.contains(where: { $0.id == id }) ? nil : true
        }) != nil else {
            throw LayoutFailure("Mission Control не подтвердила удаление рабочего стола.")
        }
    }

    private func spaceButton(_ id: UInt64) async throws -> AXUIElement {
        guard let button = try await spaceButtons()[id] else {
            throw LayoutFailure("Не удалось найти рабочий стол в Mission Control.")
        }
        return button
    }

    private func spaceButtons() async throws -> [UInt64: AXUIElement] {
        _ = try await open()
        if let buttons = try await wait(attempts: 12, for: { () throws -> [UInt64: AXUIElement]? in
            let ids = try snapshot().spaces.map(\.id)
            guard let buttons = displayControls()?.children.first(where: { $0.identifier == "mc.spaces.list" })?.children,
                  buttons.count == ids.count, Set(ids).count == ids.count,
                  ids == (try snapshot().spaces.map(\.id)) else { return nil }
            return Dictionary(uniqueKeysWithValues: zip(ids, buttons))
        }) { return buttons }
        throw LayoutFailure("Не удалось сопоставить рабочие столы с миниатюрами Mission Control.")
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
