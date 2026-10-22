import Foundation

/// UI text in `<language>.lproj` folders (`Localizable.strings` and `Localizable.stringsdict`), read at
/// run time: the folders built into the app and the ones dropped into
/// `~/Library/Application Support/SpaceMap/Translations`, which win. Missing keys fall back to English.
public enum Localization {
    public struct Language: Hashable, Identifiable, Sendable {
        public let code: String
        public let name: String
        public var id: String { code }
    }

    /// User default with the chosen language code; absent means "follow the system".
    /// `SpaceMap -Language ru` overrides it for one launch.
    public static let defaultsKey = "Language"
    public static let fallbackCode = "en"

    public static var userDirectory: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return support.appendingPathComponent("SpaceMap/Translations", isDirectory: true)
    }

    private static let lock = NSLock()
    private static var directories = defaultDirectories()
    private static var active: Translation?

    /// The language in use. Safe to read from any thread.
    public static var current: Translation {
        lock.lock()
        defer { lock.unlock() }
        if let active { return active }
        let translation = Translation(code: resolve(nil, in: directories), directories: directories)
        active = translation
        return translation
    }

    /// Switches to `code`, or to the best match for the system languages when it is nil or not installed.
    @discardableResult
    public static func select(_ code: String?) -> Translation {
        lock.lock()
        defer { lock.unlock() }
        let translation = Translation(code: resolve(code, in: directories), directories: directories)
        active = translation
        return translation
    }

    /// Folders holding `.lproj` translations, highest priority first.
    public static func setSearchDirectories(_ urls: [URL]) {
        lock.lock()
        directories = urls
        active = nil
        lock.unlock()
    }

    public static func availableLanguages() -> [Language] {
        lock.lock()
        let directories = directories
        lock.unlock()
        return codes(in: directories).map { code in
            let name = Locale(identifier: code).localizedString(forIdentifier: code) ?? code
            return Language(code: code, name: name.prefix(1).uppercased() + name.dropFirst())
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// The system's language list, ignoring the per-app override SpaceMap sets for its own menus.
    public static func systemLanguages() -> [String] {
        let global = UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain)
        return global?["AppleLanguages"] as? [String] ?? Locale.preferredLanguages
    }

    private static func defaultDirectories() -> [URL] {
        var urls = [userDirectory]
        if let resources = Bundle.main.resourceURL { urls.append(resources) }
        #if DEBUG
        // `swift run` has no app bundle: use the translations from the source tree.
        urls.append(URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../Resources/Translations").standardizedFileURL)
        #endif
        return urls
    }

    private static func codes(in directories: [URL]) -> [String] {
        var found = Set<String>()
        for directory in directories {
            let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
            for name in names where name.hasSuffix(".lproj") && name != "Base.lproj" {
                let strings = directory.appendingPathComponent(name).appendingPathComponent("Localizable.strings")
                if FileManager.default.fileExists(atPath: strings.path) {
                    found.insert(String(name.dropLast(".lproj".count)))
                }
            }
        }
        return Array(found)
    }

    private static func resolve(_ code: String?, in directories: [URL]) -> String {
        let available = codes(in: directories)
        if let code, available.contains(code) { return code }
        // English first: it is what Foundation falls back to when nothing matches.
        let candidates = available.sorted { ($0 == fallbackCode ? 0 : 1, $0) < ($1 == fallbackCode ? 0 : 1, $1) }
        return Bundle.preferredLocalizations(from: candidates, forPreferences: systemLanguages()).first
            ?? fallbackCode
    }
}

/// One language's strings plus number formatting for it.
public final class Translation: @unchecked Sendable {
    public let code: String
    public let locale: Locale
    private let tables: [Bundle]
    private let decimals: [NumberFormatter]
    private let integers: NumberFormatter
    private static let missing = "\u{0}missing"

    init(code: String, directories: [URL]) {
        self.code = code
        locale = Locale(identifier: code)
        // "pt-BR" falls back to "pt", then to English.
        var chain = [code]
        let base = String(code.prefix { $0 != "-" && $0 != "_" })
        if base != code { chain.append(base) }
        if !chain.contains(Localization.fallbackCode) { chain.append(Localization.fallbackCode) }
        tables = chain.flatMap { language in
            directories.compactMap { directory in
                let url = directory.appendingPathComponent("\(language).lproj", isDirectory: true)
                var isDirectory: ObjCBool = false
                guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
                      isDirectory.boolValue else { return nil }
                return Bundle(url: url)
            }
        }
        decimals = (0...2).map { digits in
            let formatter = NumberFormatter()
            formatter.locale = Locale(identifier: code)
            formatter.numberStyle = .decimal
            formatter.minimumFractionDigits = digits
            formatter.maximumFractionDigits = digits
            return formatter
        }
        integers = NumberFormatter()
        integers.locale = locale
        integers.numberStyle = .decimal
        integers.maximumFractionDigits = 0
    }

    public func string(_ key: String) -> String {
        for table in tables {
            let value = table.localizedString(forKey: key, value: Self.missing, table: nil)
            if value != Self.missing { return value }
        }
        return key
    }

    public func format(_ key: String, _ arguments: [CVarArg]) -> String {
        String(format: string(key), locale: locale, arguments: arguments)
    }

    /// A `Localizable.stringsdict` entry: argument 1 picks the plural form, argument 2 is the number as text.
    public func plural(_ key: String, _ count: Int64) -> String {
        format(key, [count, integer(count)])
    }

    public func integer(_ value: Int64) -> String {
        integers.string(from: NSNumber(value: value)) ?? String(value)
    }

    public func decimal(_ value: Double, digits: Int) -> String {
        decimals[min(max(digits, 0), 2)].string(from: NSNumber(value: value)) ?? String(value)
    }
}

/// Text for `key` in the current language, with `arguments` put in like `String(format:)`.
public func tr(_ key: String, _ arguments: CVarArg...) -> String {
    let translation = Localization.current
    return arguments.isEmpty ? translation.string(key) : translation.format(key, arguments)
}
