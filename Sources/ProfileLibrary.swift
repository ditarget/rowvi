import Foundation

struct LayoutProfile: Codable, Identifiable {
    let id: UUID
    var name: String
    var layout: Layout
    var cleanupOnApply = false

    init(name: String, layout: Layout) {
        self.id = UUID()
        self.name = name
        self.layout = layout
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, layout, cleanupOnApply
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        name = try values.decode(String.self, forKey: .name)
        layout = try values.decode(Layout.self, forKey: .layout)
        cleanupOnApply = try values.decodeIfPresent(Bool.self, forKey: .cleanupOnApply) ?? false
    }
}

enum ProfileLibraryError: LocalizedError {
    case blankName, duplicateName, invalidLibrary

    var errorDescription: String? {
        switch self {
        case .blankName: localized("Enter a profile name.")
        case .duplicateName: localized("A profile with this name already exists.")
        case .invalidLibrary: localized("Could not read the profile list.")
        }
    }
}

struct ProfileLibrary: Codable {
    private(set) var profiles: [LayoutProfile]
    private(set) var selectedID: UUID
    private var launchProfileID: UUID?

    init(layout: Layout) {
        let profile = LayoutProfile(name: localized("Main"), layout: layout)
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

    mutating func updateSelectedCleanup(_ enabled: Bool) {
        guard let index = profiles.firstIndex(where: { $0.id == selectedID }) else { return }
        profiles[index].cleanupOnApply = enabled
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
