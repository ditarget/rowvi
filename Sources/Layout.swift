import Foundation

enum WindowMode: String, Codable, CaseIterable, Identifiable {
    case normal, maximized, fullscreen

    var id: Self { self }
    func title(in language: AppLanguage) -> String {
        switch self {
        case .normal: language.text("Normal Window")
        case .maximized: language.text("Fill Desktop")
        case .fullscreen: language.text("Full-Screen Space")
        }
    }
}

struct WindowRule: Codable, Equatable {
    var bundleID: String
    var name: String
    var mode: WindowMode
}

struct SpaceRule: Identifiable, Codable, Equatable {
    var id = UUID()
    var desktop: Int?
    var windows: [WindowRule] = []

    var isFullscreen: Bool { windows.first?.mode == .fullscreen }
    func title(in language: AppLanguage) -> String {
        isFullscreen ? windows[0].name : language.text("Desktop %ld", desktop ?? 1)
    }
}

struct Layout: Codable, Equatable {
    var spaces: [SpaceRule]

    static var initial: Layout {
        let applications = [
            ("com.tdesktop.Telegram", "Telegram"),
            ("ru.yandex.desktop.yandex-browser", "Яндекс Браузер"),
            ("com.openai.codex", "Codex"),
            ("ru.yandex.desktop.music", "Яндекс Музыка")
        ]
        var spaces = applications.map {
            SpaceRule(windows: [WindowRule(bundleID: $0.0, name: $0.1, mode: .fullscreen)])
        }
        spaces.insert(SpaceRule(desktop: 1), at: 3)
        return Layout(spaces: spaces)
    }

    var nextDesktop: Int {
        let used = Set(spaces.compactMap(\.desktop))
        return (2...(used.count + 2)).first { !used.contains($0) }!
    }

    mutating func addDesktop() -> UUID {
        let space = SpaceRule(desktop: nextDesktop)
        spaces.append(space)
        return space.id
    }

    mutating func move(_ ids: [UUID], before target: UUID?) {
        let moving = Set(ids)
        guard !moving.isEmpty, target.map({ !moving.contains($0) }) ?? true else { return }
        let moved = spaces.filter { moving.contains($0.id) }
        spaces.removeAll { moving.contains($0.id) }
        let destination = target.flatMap { target in spaces.firstIndex { $0.id == target } } ?? spaces.endIndex
        spaces.insert(contentsOf: moved, at: destination)
    }

    mutating func remove(_ id: UUID) {
        spaces.removeAll { $0.id == id }
    }

    static func read(from file: URL) throws -> Layout {
        try JSONDecoder().decode(Layout.self, from: Data(contentsOf: file))
    }

    func write(to file: URL) throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(self).write(to: file, options: .atomic)
    }
}
