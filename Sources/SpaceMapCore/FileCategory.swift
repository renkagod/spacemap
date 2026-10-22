import Foundation

/// Rough file kind used for treemap colors and the per-type breakdown.
public enum FileCategory: UInt8, CaseIterable, Sendable {
    case video, image, audio, archive, application, document, code, system, other, folder

    public static let fileCategories: [FileCategory] = [
        .video, .image, .audio, .archive, .application, .document, .code, .system, .other,
    ]

    /// Name in the Types tab and highlight labels: key `category.<case>`.
    public var title: String { tr("category.\(self)") }

    /// Name in the legend under the map: key `category.<case>.short`.
    public var shortTitle: String { tr("category.\(self).short") }

    private static let byExtension: [String: FileCategory] = {
        var map: [String: FileCategory] = [:]
        func add(_ category: FileCategory, _ list: String) {
            for ext in list.split(separator: " ") { map[String(ext)] = category }
        }
        add(.video, "mp4 m4v mov avi mkv wmv flv webm mpg mpeg m2ts mts ts 3gp vob braw r3d mxf hevc")
        add(.image, "jpg jpeg png gif heic heif tif tiff bmp webp raw cr2 cr3 nef arw dng orf rw2 raf psd psb ai svg ico icns exr hdr tga sketch fig xcf kra afphoto afdesign")
        add(.audio, "mp3 m4a aac wav aif aiff flac alac ogg opus wma mid midi caf m4r m4b aup3 als")
        add(.archive, "zip rar 7z tar gz tgz bz2 xz zst lz4 iso dmg img sparseimage pkg mpkg cab jar war xip whl vdi vmdk qcow2 vhd vhdx ova ipa apk asahi")
        add(.application, "app dylib so framework bundle plugin kext appex exe dll msi bin")
        add(.document, "pdf doc docx xls xlsx ppt pptx key pages numbers txt rtf md odt ods odp epub mobi fb2 djvu csv tex")
        add(.code, "swift c h cpp hpp cc m mm py js ts tsx jsx rs go java kt rb php cs json xml yml yaml toml html css scss sh zsh lua dart vue sql ipynb o a pyc class wasm map lock swiftmodule pcm")
        add(.system, "log cache db sqlite sqlite3 db-wal db-shm wal shm plist tmp temp bak dat idx pack vmem sav nib car tracev3 heapsnapshot asset")
        return map
    }()

    private static let byPackageExtension: [String: FileCategory] = [
        "app": .application, "framework": .application, "bundle": .application, "plugin": .application,
        "kext": .application, "appex": .application, "xpc": .application, "prefpane": .application,
        "photoslibrary": .image, "photolibrary": .image, "aplibrary": .image,
        "fcpbundle": .video, "imovielibrary": .video, "tvlibrary": .video,
        "musiclibrary": .audio, "logicx": .audio, "band": .audio,
        "sparsebundle": .archive, "pkg": .archive, "mpkg": .archive, "utm": .archive, "pvm": .archive,
        "xcarchive": .code, "xcodeproj": .code, "xcworkspace": .code, "playground": .code,
        "dsym": .code, "docarchive": .code,
        "rtfd": .document, "pages": .document, "key": .document, "numbers": .document,
    ]

    private static func lowercasedExtension(_ name: String) -> String? {
        let utf8 = name.utf8
        guard let dot = utf8.lastIndex(of: UInt8(ascii: ".")), dot != utf8.startIndex else { return nil }
        let ext = utf8[utf8.index(after: dot)...]
        guard !ext.isEmpty, ext.count <= 16 else { return nil }
        return String(decoding: ext, as: UTF8.self).lowercased()
    }

    public static func forFileName(_ name: String) -> FileCategory {
        guard let ext = lowercasedExtension(name) else { return .other }
        return byExtension[ext] ?? .other
    }

    /// Category of a macOS package (a directory Finder shows as a single file), or nil for a plain folder.
    public static func packageCategory(forDirectoryName name: String) -> FileCategory? {
        guard let ext = lowercasedExtension(name) else { return nil }
        return byPackageExtension[ext]
    }
}

public enum SizeMode: String, CaseIterable, Sendable {
    /// Space actually taken on disk (like `du`).
    case allocated
    /// Sum of file lengths (like Finder's "size").
    case logical

    public var title: String { tr("size.\(rawValue)") }
}
