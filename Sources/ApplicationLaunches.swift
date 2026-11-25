import AppKit

@MainActor
final class ApplicationLaunches {
    private let workspace = NSWorkspace.shared
    private var pending: [String: Task<NSRunningApplication, Error>] = [:]

    init(_ rules: [WindowRule]) {
        for rule in rules {
            let bundle = rule.bundleID.lowercased()
            guard pending[bundle] == nil, running(rule) == nil else { continue }
            pending[bundle] = Task { [workspace] in
                try await Self.open(rule, using: workspace, activates: false)
            }
        }
    }

    func running(_ rule: WindowRule) -> NSRunningApplication? {
        NSRunningApplication.runningApplications(withBundleIdentifier: rule.bundleID).first { !$0.isTerminated }
    }

    func activate(_ rule: WindowRule) async throws -> NSRunningApplication {
        let started = try await pending.removeValue(forKey: rule.bundleID.lowercased())?.value
        let app: NSRunningApplication
        if let started, !started.isTerminated {
            app = started
        } else if let running = running(rule) {
            app = running
        } else {
            app = try await Self.open(rule, using: workspace, activates: true)
        }
        app.unhide()
        app.activate()
        return app
    }

    private static func open(_ rule: WindowRule, using workspace: NSWorkspace, activates: Bool) async throws -> NSRunningApplication {
        guard let url = workspace.urlForApplication(withBundleIdentifier: rule.bundleID) else {
            throw LayoutFailure("Приложение не установлено.")
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = activates
        return try await workspace.openApplication(at: url, configuration: configuration)
    }
}
