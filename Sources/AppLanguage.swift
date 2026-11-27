import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case english = "en"
    case russian = "ru"

    private static let defaultsKey = "appLanguage"
    private static let russianBundle = Bundle.main.resourceURL
        .flatMap { Bundle(url: $0.appendingPathComponent("ru.lproj", isDirectory: true)) }

    var id: Self { self }

    static func load(from defaults: UserDefaults = .standard) -> Self {
        defaults.string(forKey: defaultsKey).flatMap(Self.init(rawValue:)) ?? .system
    }

    func save(to defaults: UserDefaults = .standard) {
        defaults.set(rawValue, forKey: Self.defaultsKey)
    }

    func resolved(preferredLanguages: [String] = Locale.preferredLanguages) -> Self {
        guard self == .system else { return self }
        let language = Bundle.preferredLocalizations(
            from: [Self.english.rawValue, Self.russian.rawValue],
            forPreferences: preferredLanguages
        ).first
        return language == Self.russian.rawValue ? .russian : .english
    }

    func text(_ key: String, _ arguments: CVarArg...) -> String {
        let language = resolved()
        let format = language == .russian
            ? Self.russianBundle?.localizedString(forKey: key, value: key, table: nil) ?? key
            : key
        return arguments.isEmpty ? format : String(format: format, arguments: arguments)
    }
}

func localized(_ key: String) -> String {
    AppLanguage.load().text(key)
}
