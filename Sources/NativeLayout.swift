import AppKit
import ApplicationServices
import CoreGraphics

@MainActor
struct NativeLayout {
    private let mission = MissionControl()
    private let workspace = NSWorkspace.shared
    private static var normalFrames: [WindowIdentity: CGRect] = [:]

    private struct WindowIdentity: Hashable {
        let pid: pid_t
        let windowID: CGWindowID
        let launchDate: Date?
    }

    func apply(_ layout: Layout, cleanupOnApply: Bool) async throws {
        let running = Set(workspace.runningApplications.map(\.processIdentifier))
        Self.normalFrames = Self.normalFrames.filter { running.contains($0.key.pid) }
        let initialDesktops = try mission.snapshot().spaces.filter(\.isDesktop).map(\.id)
        let defaults = UserDefaults.standard
        let preference = "desktops-\(mission.displayUUID ?? "primary")"
        var saved = defaults.dictionary(forKey: preference) as? [String: String] ?? [:]
        var targets: [UUID: UInt64] = [:]
        var claimed = Set<UInt64>()
        var problems = [String]()
        var deferredFullscreen: [(UUID, WindowRule)] = []
        let desktops = layout.spaces.filter { !$0.isFullscreen }.sorted { ($0.desktop ?? 1) < ($1.desktop ?? 1) }
        for rule in desktops {
            let number = rule.desktop ?? 1
            let stored = saved[String(number)].flatMap(UInt64.init)
            let indexed = initialDesktops.indices.contains(number - 1) ? initialDesktops[number - 1] : nil
            do {
                let id: UInt64
                if let existing = [stored, indexed].compactMap({ $0 }).first(where: { initialDesktops.contains($0) && !claimed.contains($0) }) {
                    id = existing
                } else {
                    id = try await mission.createDesktop()
                }
                targets[rule.id] = id
                claimed.insert(id)
                saved[String(number)] = String(id)
                defaults.set(saved, forKey: preference)
            } catch {
                problems.append("\(rule.title): \(error.localizedDescription)")
            }
        }
        let applications = layout.spaces.flatMap { space in
            space.windows.filter { $0.mode == .fullscreen || targets[space.id] != nil }
        }
        let launches = ApplicationLaunches(applications)
        for space in layout.spaces {
            for rule in space.windows {
                if rule.mode == .fullscreen {
                    if let target = try? await fullscreen(rule, launches: launches) {
                        targets[space.id] = target
                    } else {
                        deferredFullscreen.append((space.id, rule))
                    }
                    continue
                }
                do {
                    if let target = targets[space.id] {
                        try await place(rule, on: target, launches: launches)
                    }
                } catch {
                    problems.append("\(rule.name): \(error.localizedDescription)")
                }
            }
        }
        for (id, rule) in deferredFullscreen {
            do { targets[id] = try await fullscreen(rule, launches: launches) }
            catch { problems.append("\(rule.name): \(error.localizedDescription)") }
        }
        let ordered = layout.spaces.compactMap { targets[$0.id] }
        if ordered.count == layout.spaces.count {
            do { try await mission.reorder(ordered) }
            catch { problems.append(error.localizedDescription) }
        }
        if !problems.isEmpty { throw LayoutFailure(problems.joined(separator: "\n")) }
        if cleanupOnApply, ordered.count == layout.spaces.count {
            let bundles = Set(layout.spaces.flatMap(\.windows).map { $0.bundleID.lowercased() })
            try await NativeCleanup(mission: mission).run(retaining: Set(ordered), profileBundles: bundles)
            try await mission.reorder(ordered)
        }
    }

    private func window(in app: NSRunningApplication) async throws -> AXUIElement {
        let application = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(application, 1)
        if let window: AXUIElement = try await wait(attempts: 60, for: {
            let focused: AXUIElement? = application.read(kAXFocusedWindowAttribute)
            let main: AXUIElement? = application.read(kAXMainWindowAttribute)
            let windows: [AXUIElement] = application.read(kAXWindowsAttribute) ?? []
            return ([focused, main].compactMap { $0 } + windows).first {
                $0.read(kAXSubroleAttribute, as: String.self) == kAXStandardWindowSubrole
            }
        }) {
            if window.read(kAXMinimizedAttribute, as: Bool.self) == true {
                _ = window.set(kAXMinimizedAttribute, to: kCFBooleanFalse)
            }
            return window
        }
        throw LayoutFailure("Обычное окно приложения не появилось.")
    }

    private func fullscreen(_ rule: WindowRule, launches: ApplicationLaunches) async throws -> UInt64 {
        if let app = launches.running(rule), let id = try fullscreenSpace(for: app.processIdentifier) { return id }
        let app = try await launches.activate(rule)
        _ = try await wait(attempts: 25, for: { app.isFinishedLaunching ? true : nil })
        app.activate()
        let window = try await window(in: app)
        _ = AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        _ = try await wait(attempts: 12, for: { app.isActive ? true : nil })
        func currentSpace() throws -> UInt64? {
            try fullscreenSpace(for: app.processIdentifier, window: WLWindowID(window))
        }
        if let id = try currentSpace() { return id }
        if window.read("AXFullScreen", as: Bool.self) != true,
           let button: AXUIElement = window.read("AXFullScreenButton"), button.press(),
           let id = try await wait(attempts: 23, for: currentSpace) { return id }
        if window.read("AXFullScreen", as: Bool.self) != true {
            guard window.set("AXFullScreen", to: kCFBooleanTrue) else {
                throw LayoutFailure("Приложение не разрешило включить полноэкранный режим.")
            }
        }
        if let id = try await wait(attempts: 38, for: currentSpace) { return id }
        throw LayoutFailure("Полноэкранное пространство на основном дисплее не появилось.")
    }

    private func fullscreenSpace(for pid: pid_t, window: CGWindowID = 0) throws -> UInt64? {
        let membership = window == 0 ? [] : (WLCopyWindowSpaces(window) ?? []).map(\.uint64Value)
        return try mission.snapshot().spaces.first { !$0.isDesktop && ($0.owner == pid || membership.contains($0.id)) }?.id
    }

    private func place(_ rule: WindowRule, on desktop: UInt64, launches: ApplicationLaunches) async throws {
        if rule.mode == .normal, let app = launches.running(rule), !app.isHidden,
           !Self.normalFrames.keys.contains(where: { $0.pid == app.processIdentifier }),
           hasWindow(for: app, on: desktop) { return }
        let app = try await launches.activate(rule)
        let window: AXUIElement
        do {
            window = try await self.window(in: app)
        } catch let failure as LayoutFailure {
            if rule.mode == .normal, hasWindow(for: app, on: desktop) { return }
            throw failure
        }
        if window.read("AXFullScreen", as: Bool.self) == true {
            guard window.set("AXFullScreen", to: kCFBooleanFalse),
                  try await wait(attempts: 25, for: {
                      window.read("AXFullScreen", as: Bool.self) == false ? true : nil
                  }) != nil else { throw LayoutFailure("Не удалось выйти из полноэкранного режима.") }
        }
        let windowID = WLWindowID(window)
        guard windowID != 0 else { throw LayoutFailure("macOS не вернула идентификатор окна.") }
        let identity = WindowIdentity(pid: app.processIdentifier, windowID: windowID, launchDate: app.launchDate)
        func isInDesktop() -> Bool {
            WLCopyWindowSpaces(windowID)?.contains(NSNumber(value: desktop)) == true
        }
        if !isInDesktop() {
            guard WLMoveWindow(windowID, desktop),
                  try await wait(attempts: 25, for: { isInDesktop() ? true : nil }) != nil else {
                throw LayoutFailure("macOS не подтвердила перенос окна на рабочий стол.")
            }
        }
        if rule.mode == .maximized {
            guard let primary = NSScreen.screens.first, let screen = NSScreen.screens.first(where: {
                ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == mission.displayID
            }) else { throw LayoutFailure("Не удалось определить размеры основного дисплея.") }
            let frame = screen.visibleFrame
            let bounds = CGRect(x: frame.minX, y: primary.frame.maxY - frame.maxY, width: frame.width, height: frame.height)
            if let current = window.frame, current != bounds, Self.normalFrames[identity] == nil {
                Self.normalFrames[identity] = current
            }
            guard window.resize(to: bounds) else { throw LayoutFailure("Приложение не разрешило изменить размер окна.") }
        } else if let original = Self.normalFrames[identity] {
            guard window.resize(to: original) else { throw LayoutFailure("Приложение не разрешило восстановить размер окна.") }
            Self.normalFrames.removeValue(forKey: identity)
        }
    }

    private func hasWindow(for app: NSRunningApplication, on desktop: UInt64) -> Bool {
        let windows = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] ?? []
        return WindowInventory.containsWindow(in: windows, ownedBy: app.processIdentifier, on: desktop) {
            WLCopyWindowSpaces($0)?.map(\.uint64Value) ?? []
        }
    }
}
