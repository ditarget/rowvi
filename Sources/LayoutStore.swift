import AppKit
import ApplicationServices
import Foundation

@MainActor
enum LayoutStore {
    static let directory = URL.applicationSupportDirectory.appending(path: "WindowLayout", directoryHint: .isDirectory)
    static let legacyFile = directory.appending(path: "layout.json")
    static let profilesFile = directory.appending(path: "profiles.json")

    static func apply(_ profile: LayoutProfile, prompt: Bool = true) async throws {
        guard !profile.layout.spaces.isEmpty else { return }
        if !AXIsProcessTrusted() {
            if prompt { AccessibilityPermission.request() }
            throw LayoutFailure("Разрешите Rowvi доступ в настройках приложения, затем снова нажмите «Применить».")
        }
        try await NativeLayout().apply(profile.layout, cleanupOnApply: profile.cleanupOnApply)
    }
}
