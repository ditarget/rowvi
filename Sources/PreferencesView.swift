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
            Section("Приложение") {
                Toggle("Показывать иконку в Dock", isOn: Binding(
                    get: { showsDockIcon },
                    set: {
                        if DockVisibility.setShown($0) { showsDockIcon = $0 }
                        else { errorMessage = "macOS не позволила изменить видимость иконки Dock." }
                    }
                ))
                Toggle("Запускать при входе в macOS", isOn: Binding(
                    get: { launchesAtLogin },
                    set: setLoginLaunch
                ))
                if loginStatus == .requiresApproval {
                    Button("Подтвердить автозапуск в настройках macOS") {
                        SMAppService.openSystemSettingsLoginItems()
                    }
                }
                Picker("Профиль при запуске Rowvi", selection: Binding(
                    get: { model.library.launchProfile?.id },
                    set: setLaunchProfile
                )) {
                    Text("Не применять профиль").tag(nil as UUID?)
                    ForEach(model.library.profiles) { profile in
                        Text(profile.name).tag(Optional(profile.id))
                    }
                }
                .disabled(model.applying || model.storageError != nil)
                if let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String {
                    LabeledContent("Версия", value: version)
                }
                if let updates {
                    CheckForUpdatesButton(updates: updates)
                }
            }
            Section("Разрешения") {
                LabeledContent("Универсальный доступ") {
                    Label(
                        accessibilityGranted ? "Разрешён" : "Требуется",
                        systemImage: accessibilityGranted ? "checkmark.circle" : "exclamationmark.circle"
                    )
                    .foregroundStyle(accessibilityGranted ? Color.green : Color.orange)
                }
                Text("Rowvi использует это разрешение для перемещения и изменения размеров окон.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                HStack {
                    if !accessibilityGranted {
                        Button("Запросить доступ") { AccessibilityPermission.request() }
                    }
                    Button("Открыть системные настройки") { AccessibilityPermission.openSettings() }
                }
            }
        }
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
