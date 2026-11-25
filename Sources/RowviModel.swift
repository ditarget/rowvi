import AppKit
import Combine

@MainActor
final class RowviModel: ObservableObject {
    @Published private(set) var library = ProfileLibrary(layout: .initial)
    @Published private(set) var applying = false
    @Published private(set) var storageError: String?
    private var applicationRequested = false

    init() {
        do {
            library = try ProfileLibrary.load(from: LayoutStore.profilesFile, legacy: LayoutStore.legacyFile)
        } catch {
            storageError = "Не удалось загрузить профили. \(error.localizedDescription)"
        }
    }

    func updateLayout(_ layout: Layout) {
        guard !applying else { return }
        var updated = library
        updated.updateSelectedLayout(layout)
        do { try save(updated) }
        catch { showError(error) }
    }

    func updateCleanup(_ enabled: Bool) {
        guard !applying else { return }
        var updated = library
        updated.updateSelectedCleanup(enabled)
        do { try save(updated) }
        catch { showError(error) }
    }

    func createProfile(named name: String, copying source: LayoutProfile? = nil) throws {
        var updated = library
        let layout = source?.layout ?? Layout(spaces: [SpaceRule(desktop: 1)])
        let profile = try updated.create(named: name, layout: layout)
        updated.select(profile.id)
        try save(updated)
    }

    func renameProfile(_ id: UUID, to name: String) throws {
        var updated = library
        try updated.rename(id, to: name)
        try save(updated)
    }

    func removeProfile(_ id: UUID) {
        guard !applying else { return }
        var updated = library
        guard updated.remove(id) else { return }
        do { try save(updated) }
        catch { showError(error) }
    }

    func setLaunchProfile(_ id: UUID?) throws {
        var updated = library
        updated.setLaunchProfile(id)
        try save(updated)
    }

    func applyLaunchProfile() {
        guard !applicationRequested, let profile = library.launchProfile else { return }
        selectProfile(profile.id, prompt: false)
    }

    func selectProfile(_ id: UUID, prompt: Bool = true) {
        guard !applying else { return }
        var updated = library
        guard updated.select(id) else { return }
        do {
            if id != library.selectedID { try save(updated) }
            applySelected(prompt: prompt)
        } catch {
            showError(error)
        }
    }

    func applySelected(prompt: Bool = true) {
        guard !applying, storageError == nil else { return }
        applicationRequested = true
        let profile = library.selected
        guard !profile.layout.spaces.isEmpty else { return }
        applying = true
        Task { @MainActor in
            defer { applying = false }
            do { try await LayoutStore.apply(profile, prompt: prompt) }
            catch { showError(error, title: "Не удалось полностью применить профиль «\(profile.name)»") }
        }
    }

    private func save(_ updated: ProfileLibrary) throws {
        if let storageError { throw LayoutFailure(storageError) }
        guard !applying else { throw LayoutFailure("Дождитесь завершения расстановки окон.") }
        try updated.write(to: LayoutStore.profilesFile)
        library = updated
    }

    private func showError(_ error: Error, title: String = "Rowvi") {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = error.localizedDescription
        NSApp.activate()
        alert.runModal()
    }
}
