import Foundation

/// Notch deliberately ships one interface language, independent of macOS preferences.
enum L10n {
    static let locale = Locale(identifier: "en")

    static func app(_ key: String, fallback: String? = nil) -> String {
        let bundle = Bundle.main.path(forResource: "en", ofType: "lproj")
            .flatMap(Bundle.init(path:)) ?? .main
        return bundle.localizedString(forKey: key, value: fallback ?? key, table: nil)
    }

    static func notch(_ key: String, fallback: String? = nil) -> String {
        app(key, fallback: fallback)
    }

    static func string(_ key: String, locale: Locale, fallback: String? = nil) -> String {
        app(key, fallback: fallback)
    }

    static func format(_ key: String, locale: Locale, fallback: String? = nil, _ arguments: CVarArg...) -> String {
        String(format: app(key, fallback: fallback), locale: self.locale, arguments: arguments)
    }
}

extension Locale {
    func dn(_ key: String, fallback: String? = nil) -> String {
        L10n.app(key, fallback: fallback)
    }

    func dnFormat(_ key: String, fallback: String? = nil, _ arguments: CVarArg...) -> String {
        String(format: L10n.app(key, fallback: fallback), locale: L10n.locale, arguments: arguments)
    }
}
