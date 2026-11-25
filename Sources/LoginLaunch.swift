import AppKit
import CoreServices
import ServiceManagement
import Sparkle
import SwiftUI

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
    var openWindow: OpenWindowAction?
    private var statusItem: NSStatusItem?
    let updates: SPUStandardUpdaterController? = {
        guard Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") is String,
              Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") is String else { return nil }
        return SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)
    }()

    func applicationWillFinishLaunching(_ notification: Notification) {
        _ = NSApp.setActivationPolicy(DockVisibility.shown ? .regular : .accessory)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        updates?.startUpdater()
        installStatusMenu()
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

    private func installStatusMenu() {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.autosaveName = "Rowvi"
        statusItem.button?.image = NSImage(systemSymbolName: "rectangle.3.group", accessibilityDescription: "Rowvi")
        statusItem.button?.toolTip = "Rowvi"
        statusItem.menu = NSHostingMenu(rootView: RowviMenu(model: model, updates: updates) { [weak self] id in
            self?.openWindow?(id: id)
            NSApp.activate()
        })
        self.statusItem = statusItem
    }
}
