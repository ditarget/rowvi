import Foundation

struct LayoutProfile: Codable, Identifiable {
    let id: UUID
    var name: String
    var layout: Layout

    init(name: String, layout: Layout) {
        self.id = UUID()
        self.name = name
        self.layout = layout
    }
}

enum ProfileLibraryError: LocalizedError {
    case blankName, duplicateName, invalidLibrary

    var errorDescription: String? {
        switch self {
        case .blankName: "Введите имя профиля."
        case .duplicateName: "Профиль с таким именем уже есть."
        case .invalidLibrary: "Не удалось прочитать список профилей."
        }
    }
}

struct ProfileLibrary: Codable {
    private(set) var profiles: [LayoutProfile]
    private(set) var selectedID: UUID
    private var launchProfileID: UUID?

    init(layout: Layout) {
        let profile = LayoutProfile(name: "Основной", layout: layout)
        profiles = [profile]
        selectedID = profile.id
    }

    var selected: LayoutProfile {
        profiles.first { $0.id == selectedID } ?? profiles[0]
    }

    var launchProfile: LayoutProfile? {
        guard let launchProfileID else { return nil }
        return profiles.first { $0.id == launchProfileID }
    }

    mutating func setLaunchProfile(_ id: UUID?) {
        launchProfileID = profiles.first { $0.id == id }?.id
    }

    mutating func create(named name: String, layout: Layout) throws -> LayoutProfile {
        let profile = LayoutProfile(name: try validatedName(name), layout: layout)
        profiles.append(profile)
        return profile
    }

    mutating func rename(_ id: UUID, to name: String) throws {
        guard let index = profiles.firstIndex(where: { $0.id == id }) else { return }
        let name = try validatedName(name, excluding: id)
        profiles[index].name = name
    }

    @discardableResult
    mutating func select(_ id: UUID) -> Bool {
        guard profiles.contains(where: { $0.id == id }) else { return false }
        selectedID = id
        return true
    }

    @discardableResult
    mutating func remove(_ id: UUID) -> Bool {
        guard profiles.count > 1, let index = profiles.firstIndex(where: { $0.id == id }) else { return false }
        profiles.remove(at: index)
        if selectedID == id { selectedID = profiles[min(index, profiles.count - 1)].id }
        if launchProfileID == id { launchProfileID = nil }
        return true
    }

    mutating func updateSelectedLayout(_ layout: Layout) {
        guard let index = profiles.firstIndex(where: { $0.id == selectedID }) else { return }
        profiles[index].layout = layout
    }

    private func validatedName(_ name: String, excluding id: UUID? = nil) throws -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ProfileLibraryError.blankName }
        guard !profiles.contains(where: { $0.id != id && $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) else {
            throw ProfileLibraryError.duplicateName
        }
        return trimmed
    }

    static func load(from file: URL, legacy: URL) throws -> ProfileLibrary {
        let data: Data
        do {
            data = try Data(contentsOf: file)
        } catch CocoaError.fileReadNoSuchFile {
            do {
                return ProfileLibrary(layout: try Layout.read(from: legacy))
            } catch CocoaError.fileReadNoSuchFile {
                return ProfileLibrary(layout: .initial)
            }
        }
        let library = try JSONDecoder().decode(Self.self, from: data)
        let ids = Set(library.profiles.map(\.id))
        guard ids.count == library.profiles.count, ids.contains(library.selectedID) else {
            throw ProfileLibraryError.invalidLibrary
        }
        return library
    }

    func write(to file: URL) throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(self).write(to: file, options: .atomic)
    }
}
