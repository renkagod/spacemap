import Foundation
import XCTest
@testable import SpaceMapCore

/// The translations in the repository, the same files the app bundle gets.
let translationsDirectory = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .appendingPathComponent("../../Resources/Translations")
    .standardizedFileURL

final class FormatTests: XCTestCase {
    override func setUp() {
        Localization.setSearchDirectories([translationsDirectory])
    }

    override func tearDown() {
        Localization.select("en")
    }

    func testEnglish() {
        Localization.select("en")
        XCTAssertEqual(Format.bytes(0), "0 B")
        XCTAssertEqual(Format.bytes(999), "999 B")
        XCTAssertEqual(Format.bytes(1_500), "1.50 KB")
        XCTAssertEqual(Format.bytes(12_345_678), "12.3 MB")
        XCTAssertEqual(Format.bytes(512_000_000_000), "512 GB")
        XCTAssertEqual(Format.bytes(999_999_999), "1.00 GB")
        XCTAssertEqual(Format.files(1), "1 file")
        XCTAssertEqual(Format.files(2), "2 files")
        XCTAssertEqual(Format.files(0), "0 files")
        XCTAssertEqual(Format.files(1234), "1,234 files")
        XCTAssertEqual(Format.folders(1), "1 folder")
        XCTAssertEqual(Localization.current.plural("hover.smallItems", 3), "3 more small items")
        XCTAssertEqual(Format.percent(0.123), "12%")
        XCTAssertEqual(Format.percent(0.0123), "1.2%")
        XCTAssertEqual(Format.percent(0.0001), "<0.1%")
        XCTAssertEqual(Format.duration(4.5), "4.5 s")
        XCTAssertEqual(Format.duration(75), "1 min 15 s")
        XCTAssertEqual(FileCategory.video.title, "Video")
        XCTAssertEqual(SizeMode.logical.title, "File Sizes")
        XCTAssertEqual(tr("status.done", "3 files", "1.0 s"), "3 files in 1.0 s")
    }

    func testRussian() {
        Localization.select("ru")
        XCTAssertEqual(Format.bytes(0), "0 Б")
        XCTAssertEqual(Format.bytes(999), "999 Б")
        XCTAssertEqual(Format.bytes(1_500), "1,50 КБ")
        XCTAssertEqual(Format.bytes(12_345_678), "12,3 МБ")
        XCTAssertEqual(Format.bytes(512_000_000_000), "512 ГБ")
        XCTAssertEqual(Format.bytes(999_999_999), "1,00 ГБ")
        XCTAssertEqual(Format.percent(0.123), "12\u{00A0}%")
        XCTAssertEqual(Format.percent(0.0123), "1,2\u{00A0}%")
        XCTAssertEqual(Format.duration(4.5), "4,5 с")
        XCTAssertEqual(Format.duration(75), "1 мин 15 с")
        XCTAssertEqual(FileCategory.video.title, "Видео")
        XCTAssertEqual(FileCategory.image.shortTitle, "Фото")
        XCTAssertEqual(SizeMode.allocated.title, "На диске")
    }

    func testRussianPlurals() {
        Localization.select("ru")
        XCTAssertEqual(Format.files(1), "1 файл")
        XCTAssertEqual(Format.files(3), "3 файла")
        XCTAssertEqual(Format.files(5), "5 файлов")
        XCTAssertEqual(Format.files(11), "11 файлов")
        XCTAssertEqual(Format.files(21), "21 файл")
        XCTAssertEqual(Format.files(1234), "1\u{00A0}234 файла")
        XCTAssertEqual(Format.folders(2), "2 папки")
        XCTAssertEqual(Format.folders(14), "14 папок")
        XCTAssertEqual(Format.items(101), "101 объект")
        XCTAssertEqual(Localization.current.plural("hover.smallItems", 7), "Ещё 7 объектов помельче")
    }

    func testCategories() {
        XCTAssertEqual(FileCategory.forFileName("Movie.MKV"), .video)
        XCTAssertEqual(FileCategory.forFileName("archive.tar.gz"), .archive)
        XCTAssertEqual(FileCategory.forFileName(".zshrc"), .other)
        XCTAssertEqual(FileCategory.forFileName("noext"), .other)
        XCTAssertEqual(FileCategory.packageCategory(forDirectoryName: "Photos Library.photoslibrary"), .image)
        XCTAssertNil(FileCategory.packageCategory(forDirectoryName: "Documents"))
    }
}

final class LocalizationTests: XCTestCase {
    private var userDirectory: URL!

    override func setUpWithError() throws {
        userDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SpaceMapTranslations-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: userDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: userDirectory)
        Localization.setSearchDirectories([translationsDirectory])
        Localization.select("en")
    }

    func testBuiltInLanguages() {
        Localization.setSearchDirectories([translationsDirectory])
        let languages = Localization.availableLanguages()
        XCTAssertEqual(languages.map(\.code), ["en", "ru"])
        XCTAssertEqual(languages.map(\.name), ["English", "Русский"])
        XCTAssertEqual(Localization.select("xx").code, Localization.select(nil).code, "unknown code follows the system")
    }

    /// A partial translation dropped into the user folder: its keys win, the rest falls back to English.
    func testUserTranslationWithFallback() throws {
        let german = userDirectory.appendingPathComponent("de.lproj", isDirectory: true)
        try FileManager.default.createDirectory(at: german, withIntermediateDirectories: true)
        try "\"menu.up\" = \"Nach oben\";\n".write(to: german.appendingPathComponent("Localizable.strings"),
                                                   atomically: true, encoding: .utf8)
        Localization.setSearchDirectories([userDirectory, translationsDirectory])
        XCTAssertEqual(Localization.availableLanguages().map(\.code), ["de", "en", "ru"])

        XCTAssertEqual(Localization.select("de").code, "de")
        XCTAssertEqual(tr("menu.up"), "Nach oben")
        XCTAssertEqual(tr("menu.top"), "Go to Top")
        XCTAssertEqual(Format.bytes(1_500), "1,50 KB")
        XCTAssertEqual(tr("no.such.key"), "no.such.key")
    }

    /// Every translation in the repository parses, has every English key and keeps the same placeholders.
    func testTranslationsMatchEnglish() throws {
        let english = try strings(for: "en")
        XCTAssertFalse(english.isEmpty)
        let codes = try FileManager.default.contentsOfDirectory(atPath: translationsDirectory.path)
            .filter { $0.hasSuffix(".lproj") }
            .map { String($0.dropLast(".lproj".count)) }
        XCTAssertTrue(codes.contains("ru"))
        for code in codes where code != "en" {
            let translated = try strings(for: code)
            let missing = Set(english.keys).subtracting(translated.keys).sorted()
            let unknown = Set(translated.keys).subtracting(english.keys).sorted()
            XCTAssertTrue(missing.isEmpty, "\(code): missing \(missing)")
            XCTAssertTrue(unknown.isEmpty, "\(code): keys English does not have \(unknown)")
            for (key, value) in translated {
                guard let original = english[key] else { continue }
                XCTAssertEqual(placeholders(value), placeholders(original), "\(code): placeholders of \(key)")
            }
        }
    }

    /// Localizable.strings plus the format line of each Localizable.stringsdict entry.
    private func strings(for code: String) throws -> [String: String] {
        let folder = translationsDirectory.appendingPathComponent("\(code).lproj")
        let text = try String(contentsOf: folder.appendingPathComponent("Localizable.strings"), encoding: .utf8)
        var result = try XCTUnwrap((text as NSString).propertyListFromStringsFileFormat() as? [String: String],
                                   "\(code).lproj/Localizable.strings does not parse")
        let pluralsURL = folder.appendingPathComponent("Localizable.stringsdict")
        let plurals = try XCTUnwrap(NSDictionary(contentsOf: pluralsURL) as? [String: [String: Any]],
                                    "\(code).lproj/Localizable.stringsdict does not parse")
        for (key, entry) in plurals {
            result[key] = entry["NSStringLocalizedFormatKey"] as? String
        }
        let infoPlist = try String(contentsOf: folder.appendingPathComponent("InfoPlist.strings"), encoding: .utf8)
        XCTAssertNotNil((infoPlist as NSString).propertyListFromStringsFileFormat(),
                        "\(code).lproj/InfoPlist.strings does not parse")
        return result
    }

    private func placeholders(_ text: String) -> [String] {
        let pattern = try! NSRegularExpression(pattern: "%(?:\\d+\\$)?(?:#@\\w+@|ll?d|@|%)")
        let range = NSRange(text.startIndex..., in: text)
        return pattern.matches(in: text, range: range)
            .map { (text as NSString).substring(with: $0.range) }
            .sorted()
    }
}
