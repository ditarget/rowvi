import Foundation
import CoreGraphics

@main
struct LayoutChecks {
    static func main() throws {
        checkWindowMembership()
        let narrow = PanelMetrics(width: 340, height: 170, count: 6)
        let medium = PanelMetrics(width: 760, height: 220, count: 6)
        let wide = PanelMetrics(width: 1240, height: 360, count: 6)
        precondition(narrow.tileWidth < medium.tileWidth && medium.tileWidth < wide.tileWidth)
        precondition(narrow.previewHeight < medium.previewHeight && medium.previewHeight < wide.previewHeight)
        precondition(narrow.labelSize < wide.labelSize && narrow.actionSize < wide.actionSize)
        for width: CGFloat in [340, 390, 760, 1080, 1240] {
            for count in [0, 1, 6, 10, 16, 24, 48] {
                let metrics = PanelMetrics(width: width, height: 220, count: count)
                precondition(metrics.contentWidth <= width + 0.01, "Row overflow: \(width) pt, \(count) spaces")
                precondition(metrics.iconSize <= min(metrics.tileWidth, metrics.previewHeight))
            }
        }
        let dense = PanelMetrics(width: 1240, height: 360, count: 16)
        precondition(dense.tileWidth < wide.tileWidth && !dense.showsLabels)
        precondition(dense.actionSize == wide.actionSize && dense.interfaceFontSize == wide.interfaceFontSize)
        precondition(PanelMetrics(width: 760, height: 360, count: 6).previewHeight > medium.previewHeight)
        var layout = Layout.initial
        precondition(layout.spaces.map(\.title) == ["Telegram", "Яндекс Браузер", "Codex", "Рабочий стол 1", "Яндекс Музыка"])
        let second = layout.addDesktop()
        let third = layout.addDesktop()
        precondition(layout.spaces.suffix(2).map(\.title) == ["Рабочий стол 2", "Рабочий стол 3"])
        layout.move([second], before: layout.spaces[0].id)
        precondition(layout.spaces.first?.id == second)
        layout.remove(third)
        let replacement = layout.addDesktop()
        precondition(layout.spaces.last?.id == replacement && layout.spaces.last?.desktop == 3)
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appending(path: "layout.json")
        try layout.write(to: file)
        let restored = try Layout.read(from: file)
        precondition(restored == layout)
        try checkProfiles(in: directory, legacy: file)
        print("Layout checks passed")
    }

    private static func checkProfiles(in directory: URL, legacy: URL) throws {
        let file = directory.appending(path: "profiles.json")
        let oldLayout = try Layout.read(from: legacy)
        let legacyData = try Data(contentsOf: legacy)
        var oldJSON = try JSONSerialization.jsonObject(with: legacyData) as? [String: Any] ?? [:]
        oldJSON["applyAtLogin"] = false
        try JSONSerialization.data(withJSONObject: oldJSON).write(to: legacy)
        var library = try ProfileLibrary.load(from: file, legacy: legacy)
        let originalID = library.selectedID
        precondition(library.selected.layout == oldLayout)
        let copy = try library.create(named: "  Работа  ", layout: oldLayout)
        precondition(library.selectedID == originalID && copy.name == "Работа")
        precondition(library.select(copy.id))
        var changed = library.selected.layout
        _ = changed.addDesktop()
        library.updateSelectedLayout(changed)
        try library.rename(copy.id, to: "Вечер")
        precondition(library.profiles.first?.layout == oldLayout)
        try library.write(to: file)
        let restored = try ProfileLibrary.load(from: file, legacy: legacy)
        precondition(restored.selectedID == copy.id && restored.selected.name == "Вечер")
        precondition(restored.selected.layout == changed)

        try checkLaunchProfile(in: file, legacy: legacy, library: restored, otherID: originalID)

        precondition(library.remove(copy.id))
        precondition(library.selectedID == originalID)
        precondition(!library.remove(originalID))
        precondition(!library.select(copy.id))
        do {
            _ = try library.create(named: "   ", layout: changed)
            preconditionFailure("Blank profile names must be rejected")
        } catch ProfileLibraryError.blankName {}
        do {
            _ = try library.create(named: "ОСНОВНОЙ", layout: changed)
            preconditionFailure("Duplicate profile names must be rejected")
        } catch ProfileLibraryError.duplicateName {}

        try Data("invalid".utf8).write(to: file)
        do {
            _ = try ProfileLibrary.load(from: file, legacy: legacy)
            preconditionFailure("A damaged profile file must surface the error")
        } catch is DecodingError {}
    }

    private static func checkLaunchProfile(in file: URL, legacy: URL, library: ProfileLibrary, otherID: UUID) throws {
        var library = library
        let launchID = library.selectedID
        precondition(library.launchProfile == nil)
        library.setLaunchProfile(launchID)
        precondition(library.select(otherID))
        try library.rename(launchID, to: "На старте")
        try library.write(to: file)
        let restored = try ProfileLibrary.load(from: file, legacy: legacy)
        precondition(restored.selectedID == otherID)
        precondition(restored.launchProfile?.id == launchID && restored.launchProfile?.name == "На старте")

        library.setLaunchProfile(nil)
        try library.write(to: file)
        let withoutLaunch = try ProfileLibrary.load(from: file, legacy: legacy)
        precondition(withoutLaunch.launchProfile == nil && withoutLaunch.selectedID == otherID)

        library.setLaunchProfile(launchID)
        precondition(library.remove(launchID) && library.launchProfile == nil)
    }

    private static func checkWindowMembership() {
        func row(_ id: UInt32, owner: Int32 = 51, layer: Int32 = 0, alpha: Double = 1) -> [String: Any] {
            [
                kCGWindowNumber as String: NSNumber(value: id),
                kCGWindowOwnerPID as String: NSNumber(value: owner),
                kCGWindowLayer as String: NSNumber(value: layer),
                kCGWindowAlpha as String: NSNumber(value: alpha),
                kCGWindowBounds as String: ["X": 93, "Y": 37, "Width": 1280, "Height": 768]
            ]
        }
        let windows = [row(10), row(11, owner: 77), row(12, layer: 3), row(13, alpha: 0)]
        let spaces: [CGWindowID: [UInt64]] = [10: [7], 11: [8], 12: [8], 13: [8]]
        precondition(WindowInventory.containsWindow(in: windows, ownedBy: 51, on: 7) { spaces[$0] ?? [] })
        precondition(!WindowInventory.containsWindow(in: windows, ownedBy: 51, on: 8) { spaces[$0] ?? [] })
        precondition(!WindowInventory.containsWindow(in: [row(10)], ownedBy: 51, on: 7) { _ in [7, 8] })
        precondition(!WindowInventory.containsWindow(in: [row(10)], ownedBy: 51, on: 7) { _ in [] })
    }
}
