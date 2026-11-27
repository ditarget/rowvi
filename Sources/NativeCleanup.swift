import AppKit
import ApplicationServices
import CoreGraphics

@MainActor
struct NativeCleanup {
    let mission: MissionControl

    func run(retaining profileSpaces: Set<UInt64>, profileBundles: Set<String>) async throws {
        let snapshot = try mission.snapshot()
        guard profileSpaces.isSubset(of: Set(snapshot.spaces.map(\.id))) else {
            throw LayoutFailure(localized("The profile's Spaces changed before cleanup."))
        }
        let desktops = snapshot.spaces.filter(\.isDesktop).map(\.id)
        guard let fallback = desktops.first(where: profileSpaces.contains)
                ?? desktops.first(where: { $0 == snapshot.active })
                ?? desktops.first else { return }
        let retained = profileSpaces.union([fallback])
        let removalOrder = desktops.reversed().filter { !retained.contains($0) }
        guard !removalOrder.isEmpty else { return }
        guard NSScreen.screens.count <= 1 || NSScreen.screensHaveSeparateSpaces else {
            throw LayoutFailure(localized("Enable “Displays have separate Spaces” to clean up desktops on the primary display."))
        }

        let removable = Set(removalOrder)
        try await mission.prepareDesktopRemoval(removable, fallback: fallback)
        let ready = try mission.snapshot().spaces
        guard retained.isSubset(of: Set(ready.map(\.id))),
              removable.isSubset(of: Set(ready.filter(\.isDesktop).map(\.id))) else {
            throw LayoutFailure(localized("The desktop list changed before Rowvi could quit apps."))
        }
        let pending = try requestQuit(on: removable, excluding: profileBundles)
        if !pending.isEmpty {
            _ = try await wait(attempts: 25, for: { pending.allSatisfy(\.isTerminated) ? true : nil })
        }

        for desktop in removalOrder {
            try Task.checkCancellation()
            try await mission.removeDesktop(desktop, keeping: retained, fallback: fallback)
        }

        let running = pending.filter { !$0.isTerminated }.compactMap { $0.localizedName ?? $0.bundleIdentifier }
        if !running.isEmpty {
            throw LayoutFailure(AppLanguage.load().text("These apps remained open after Rowvi asked them to quit: %@.", running.joined(separator: ", ")))
        }
    }

    private func requestQuit(on desktops: Set<UInt64>, excluding profileBundles: Set<String>) throws -> [NSRunningApplication] {
        let protectedBundles = profileBundles.union(["com.apple.finder"])
        var pending: [NSRunningApplication] = []
        for app in NSWorkspace.shared.runningApplications {
            try Task.checkCancellation()
            guard app.activationPolicy == .regular, app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
                  let bundle = app.bundleIdentifier?.lowercased(), !protectedBundles.contains(bundle),
                  windowsAreConfined(for: app, to: desktops) else { continue }
            _ = app.terminate()
            pending.append(app)
        }
        return pending
    }

    private func windowsAreConfined(for app: NSRunningApplication, to desktops: Set<UInt64>) -> Bool {
        guard let windows = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] else { return false }
        let windowIDs = Set(windows.compactMap { row -> CGWindowID? in
            guard (row[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == app.processIdentifier,
                  (row[kCGWindowLayer as String] as? NSNumber)?.int32Value == CGWindowLevelForKey(.normalWindow) else { return nil }
            return (row[kCGWindowNumber as String] as? NSNumber)?.uint32Value
        })
        func spaces(for id: CGWindowID) -> [UInt64]? {
            WLCopyWindowSpaces(id)?.map(\.uint64Value)
        }
        guard WindowInventory.windowsAreConfined(windowIDs, to: desktops, spacesForWindow: spaces) else { return false }
        let application = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(application, 0.5)
        guard let accessibilityWindows: [AXUIElement] = application.read(kAXWindowsAttribute) else { return false }
        return WindowInventory.windowsAreConfined(windowIDs.union(accessibilityWindows.map(WLWindowID)),
                                                   to: desktops, spacesForWindow: spaces)
    }
}
