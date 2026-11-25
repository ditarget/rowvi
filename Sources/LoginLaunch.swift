import AppKit
import CoreServices
import ServiceManagement

@MainActor
enum LoginLaunch {
    static var status: SMAppService.Status { SMAppService.mainApp.status }

    static var enabled: Bool {
        status == .enabled || status == .requiresApproval
    }

    static func setEnabled(_ enabled: Bool) throws {
        if enabled == self.enabled { return }
        if enabled { try SMAppService.mainApp.register() }
        else { try SMAppService.mainApp.unregister() }
    }
}

@MainActor
final class LayoutAppDelegate: NSObject, NSApplicationDelegate {
    let model = RowviModel()

    func applicationWillFinishLaunching(_ notification: Notification) {
        _ = NSApp.setActivationPolicy(DockVisibility.shown ? .regular : .accessory)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard model.library.launchProfile != nil else { return }
        let event = NSAppleEventManager.shared().currentAppleEvent
        let launchedAtLogin = event?.eventID == kAEOpenApplication
            && event?.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
        Task { @MainActor in
            if launchedAtLogin {
                try? await Task.sleep(for: .seconds(5))
                guard LoginLaunch.status == .enabled else { return }
            }
            model.applyLaunchProfile()
        }
    }
}
