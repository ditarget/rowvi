import AppKit
import ApplicationServices
import ServiceManagement
import Sparkle
import SwiftUI

@MainActor
enum DockVisibility {
    private static let key = "showsDockIcon"

    static var shown: Bool {
        UserDefaults.standard.object(forKey: key) as? Bool ?? true
    }

    static func setShown(_ shown: Bool) -> Bool {
        guard NSApp.setActivationPolicy(shown ? .regular : .accessory) else { return false }
        UserDefaults.standard.set(shown, forKey: key)
        if shown { NSApp.activate() }
        return true
    }
}

@MainActor
enum AccessibilityPermission {
    static var granted: Bool { AXIsProcessTrusted() }

    static func request() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    static func openSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}

struct PreferencesView: View {
    @ObservedObject var model: RowviModel
    let updates: SPUStandardUpdaterController?
    @ViewState private var showsDockIcon = DockVisibility.shown
    @ViewState private var launchesAtLogin = LoginLaunch.enabled
    @ViewState private var loginStatus = LoginLaunch.status
    @ViewState private var accessibilityGranted = AccessibilityPermission.granted
    @ViewState private var errorMessage: String?

    var body: some View {
        Form {
            Section(model.language.text("App")) {
                Picker(model.language.text("Language"), selection: Binding(
                    get: { model.language },
                    set: { model.setLanguage($0) }
                )) {
                    Text(model.language.text("System Language")).tag(AppLanguage.system)
                    Text(verbatim: "English").tag(AppLanguage.english)
                    Text(verbatim: "Русский").tag(AppLanguage.russian)
                }
                .pickerStyle(.menu)
                Toggle(model.language.text("Show Dock icon"), isOn: Binding(
                    get: { showsDockIcon },
                    set: {
                        if DockVisibility.setShown($0) { showsDockIcon = $0 }
                        else { errorMessage = model.language.text("macOS did not allow Rowvi to change Dock icon visibility.") }
                    }
                ))
                Toggle(model.language.text("Launch at login"), isOn: Binding(
                    get: { launchesAtLogin },
                    set: setLoginLaunch
                ))
                if loginStatus == .requiresApproval {
                    Button(model.language.text("Approve launch at login in System Settings")) {
                        SMAppService.openSystemSettingsLoginItems()
                    }
                }
                Picker(model.language.text("Profile at launch"), selection: Binding(
                    get: { model.library.launchProfile?.id },
                    set: setLaunchProfile
                )) {
                    Text(model.language.text("Do not apply a profile")).tag(nil as UUID?)
                    ForEach(model.library.profiles) { profile in
                        Text(profile.name).tag(Optional(profile.id))
                    }
                }
                .disabled(model.applying || model.storageError != nil)
                if let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String {
                    LabeledContent(model.language.text("Version"), value: version)
                }
                if let updates {
                    CheckForUpdatesButton(updates: updates, language: model.language)
                }
            }
            Section(model.language.text("Permissions")) {
                LabeledContent(model.language.text("Accessibility")) {
                    Label(
                        accessibilityGranted ? model.language.text("Granted") : model.language.text("Required"),
                        systemImage: accessibilityGranted ? "checkmark.circle" : "exclamationmark.circle"
                    )
                    .foregroundStyle(accessibilityGranted ? Color.green : Color.orange)
                }
                Text(model.language.text("Rowvi uses this permission to move and resize windows."))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                HStack {
                    if !accessibilityGranted {
                        Button(model.language.text("Request Access")) { AccessibilityPermission.request() }
                    }
                    Button(model.language.text("Open System Settings")) { AccessibilityPermission.openSettings() }
                }
            }
        }
        .navigationTitle(model.language.text("Rowvi Settings"))
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear(perform: refresh)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refresh()
        }
        .alert("Rowvi", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func setLoginLaunch(_ enabled: Bool) {
        do { try LoginLaunch.setEnabled(enabled) }
        catch { errorMessage = error.localizedDescription }
        refresh()
    }

    private func setLaunchProfile(_ id: UUID?) {
        do { try model.setLaunchProfile(id) }
        catch { errorMessage = error.localizedDescription }
    }

    private func refresh() {
        showsDockIcon = DockVisibility.shown
        launchesAtLogin = LoginLaunch.enabled
        loginStatus = LoginLaunch.status
        accessibilityGranted = AccessibilityPermission.granted
    }
}
