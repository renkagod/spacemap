import Foundation
import XCTest
@testable import SpaceMapCore

final class SquarifyTests: XCTestCase {
    func testRectsFillAreaWithoutOverlap() {
        var generator = SystemRandomNumberGenerator()
        for _ in 0..<50 {
            let count = Int.random(in: 1...60, using: &generator)
            let values = (0..<count).map { _ in Double.random(in: 1...1_000_000, using: &generator) }
                .sorted(by: >)
            let bounds = CGRect(x: 10, y: 20, width: Double.random(in: 50...1500), height: Double.random(in: 50...900))
            let rects = TreemapLayout.squarify(values, in: bounds)
            XCTAssertEqual(rects.count, values.count)

            let total = values.reduce(0, +)
            for (rect, value) in zip(rects, values) {
                let expected = value / total * Double(bounds.width * bounds.height)
                XCTAssertEqual(Double(rect.width * rect.height), expected, accuracy: expected * 1e-6 + 1e-6)
                XCTAssertTrue(bounds.insetBy(dx: -0.001, dy: -0.001).contains(rect), "\(rect) outside \(bounds)")
            }
            for i in 0..<rects.count {
                for j in (i + 1)..<rects.count {
                    let overlap = rects[i].intersection(rects[j])
                    XCTAssertLessThan(overlap.isNull ? 0 : overlap.width * overlap.height, 0.01)
                }
            }
        }
    }

    func testAspectRatiosStayReasonable() {
        let values = Array(repeating: 1.0, count: 100)
        let rects = TreemapLayout.squarify(values, in: CGRect(x: 0, y: 0, width: 1000, height: 600))
        let worst = rects.map { max($0.width / $0.height, $0.height / $0.width) }.max() ?? 0
        XCTAssertLessThan(worst, 3)
    }
}

final class ScannerTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SpaceMapTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func write(_ relativePath: String, bytes: Int) throws {
        let url = directory.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 0x5A, count: bytes).write(to: url)
    }

    private func scan(_ path: String) -> (Scanner, ScanStats) {
        let scanner = Scanner(path: path, treeLock: NSLock(), threads: 4)
        let done = expectation(description: "scan")
        var result = ScanStats()
        scanner.start(completionQueue: DispatchQueue.global()) { stats in
            result = stats
            done.fulfill()
        }
        wait(for: [done], timeout: 30)
        return (scanner, result)
    }

    func testCountsFilesSizesAndStructure() throws {
        try write("a.mp4", bytes: 300_000)
        try write("photos/b.jpg", bytes: 120_000)
        try write("photos/raw/c.cr2", bytes: 50_000)
        try write("docs/d.pdf", bytes: 7_000)
        try write("Tool.app/Contents/MacOS/Tool", bytes: 20_000)
        try FileManager.default.createDirectory(at: directory.appendingPathComponent("empty"), withIntermediateDirectories: true)
        // Hard link: same data twice, must be counted once.
        try FileManager.default.linkItem(at: directory.appendingPathComponent("a.mp4"),
                                         to: directory.appendingPathComponent("photos/a-link.mp4"))
        // Symlink to a big file must not be followed.
        try FileManager.default.createSymbolicLink(at: directory.appendingPathComponent("link"),
                                                   withDestinationURL: directory.appendingPathComponent("a.mp4"))

        let (scanner, stats) = scan(directory.path)
        let root = scanner.root

        XCTAssertEqual(stats.files, 7)
        XCTAssertEqual(root.fileCount, 7)
        XCTAssertEqual(root.logical, 300_000 + 120_000 + 50_000 + 7_000 + 20_000 + Int64(symlinkLength()))
        XCTAssertEqual(stats.inaccessible, 0)
        XCTAssertFalse(stats.cancelled)

        let names = Set(root.children.map(\.name))
        XCTAssertEqual(names, ["a.mp4", "photos", "docs", "Tool.app", "empty", "link"])

        let photos = try XCTUnwrap(root.children.first { $0.name == "photos" })
        XCTAssertEqual(photos.kind, .directory)
        XCTAssertEqual(photos.fileCount, 3)
        XCTAssertTrue(photos.isDescendant(of: root))

        let app = try XCTUnwrap(root.children.first { $0.name == "Tool.app" })
        XCTAssertEqual(app.kind, .package)
        XCTAssertEqual(app.category, .application)
        XCTAssertEqual(app.logical, 20_000)

        let video = try XCTUnwrap(root.children.first { $0.name == "a.mp4" })
        XCTAssertEqual(video.category, .video)
        XCTAssertEqual(video.path, scanner.rootPath + "/a.mp4")

        // Allocated sizes add up the tree, like du.
        func check(_ node: FileNode) {
            guard node.isContainer else { return }
            let childSum = node.children.reduce(Int64(0)) { $0 + $1.allocated }
            XCTAssertGreaterThanOrEqual(node.allocated, childSum)
            let childLogical = node.children.reduce(Int64(0)) { $0 + $1.logical }
            XCTAssertEqual(node.logical, childLogical)
            node.children.forEach(check)
        }
        check(root)
    }

    private func symlinkLength() -> Int {
        // lstat size of a symlink is the length of its target path.
        var info = stat()
        lstat(directory.appendingPathComponent("link").path, &info)
        return Int(info.st_size)
    }

    func testTreeEditorKeepsTotalsInSync() throws {
        try write("x/one.bin", bytes: 10_000)
        try write("x/two.bin", bytes: 20_000)
        try write("y/three.bin", bytes: 40_000)
        let (scanner, _) = scan(directory.path)
        let root = scanner.root
        let x = try XCTUnwrap(root.children.first { $0.name == "x" })
        let two = try XCTUnwrap(x.children.first { $0.name == "two.bin" })

        TreeEditor.remove(two)
        XCTAssertEqual(x.logical, 10_000)
        XCTAssertEqual(root.logical, 50_000)
        XCTAssertEqual(root.fileCount, 2)
        XCTAssertNil(two.parent)

        try write("y/four.bin", bytes: 5_000)
        let y = try XCTUnwrap(root.children.first { $0.name == "y" })
        let rescanner = Scanner(path: y.path, treeLock: NSLock(), rootName: "y", threads: 2)
        let done = expectation(description: "rescan")
        rescanner.start(completionQueue: DispatchQueue.global()) { _ in done.fulfill() }
        wait(for: [done], timeout: 30)
        TreeEditor.replace(y, with: rescanner.root)
        XCTAssertEqual(root.logical, 55_000)
        XCTAssertEqual(root.fileCount, 3)
        XCTAssertTrue(rescanner.root.parent === root)
    }

    func testLayoutCoversEverythingVisible() throws {
        for index in 0..<40 {
            try write("dir\(index % 4)/file\(index).dat", bytes: 1_000 * (index + 1))
        }
        try write("tiny/a", bytes: 1)
        let (scanner, _) = scan(directory.path)
        var options = TreemapOptions()
        options.sizeMode = .logical
        let bounds = CGRect(x: 0, y: 0, width: 800, height: 500)
        let items = TreemapLayout.layout(root: scanner.root, in: bounds, options: options)

        XCTAssertFalse(items.isEmpty)
        let topLevel = items.filter { $0.depth == 0 }
        let topArea = topLevel.reduce(0.0) { $0 + Double($1.rect.width * $1.rect.height) }
        XCTAssertEqual(topArea, Double(bounds.width * bounds.height), accuracy: 1)
        for item in items {
            XCTAssertTrue(bounds.insetBy(dx: -0.01, dy: -0.01).contains(item.rect))
        }
        // "tiny" holds one byte: far too small to draw, so it ends up in an aggregate block.
        XCTAssertEqual(items.filter { $0.kind == .directory }.count, 4)
        XCTAssertEqual(items.filter { $0.kind == .aggregate }.count, 1)
    }

    func testCancelStopsQuickly() throws {
        for index in 0..<200 {
            try write("d\(index)/f.bin", bytes: 10)
        }
        let scanner = Scanner(path: directory.path, treeLock: NSLock(), threads: 2)
        let done = expectation(description: "cancelled")
        scanner.start(completionQueue: DispatchQueue.global()) { stats in
            XCTAssertTrue(stats.cancelled)
            done.fulfill()
        }
        scanner.cancel()
        wait(for: [done], timeout: 10)
    }
}

final class FormatTests: XCTestCase {
    func testBytes() {
        XCTAssertEqual(Format.bytes(0), "0 Б")
        XCTAssertEqual(Format.bytes(999), "999 Б")
        XCTAssertEqual(Format.bytes(1_500), "1,50 КБ")
        XCTAssertEqual(Format.bytes(12_345_678), "12,3 МБ")
        XCTAssertEqual(Format.bytes(512_000_000_000), "512 ГБ")
        XCTAssertEqual(Format.bytes(999_999_999), "1,00 ГБ")
    }

    func testPlurals() {
        XCTAssertEqual(Format.files(1), "1 файл")
        XCTAssertEqual(Format.files(3), "3 файла")
        XCTAssertEqual(Format.files(11), "11 файлов")
        XCTAssertEqual(Format.files(21), "21 файл")
        XCTAssertEqual(Format.files(1234), "1\u{202F}234 файла")
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
