import AppKit
import SpaceMapCore
import SwiftUI

extension FileCategory {
    var rgb: (r: CGFloat, g: CGFloat, b: CGFloat) {
        switch self {
        case .video: return (0.58, 0.41, 0.97)
        case .image: return (0.19, 0.71, 0.52)
        case .audio: return (0.94, 0.37, 0.56)
        case .archive: return (0.97, 0.59, 0.22)
        case .application: return (0.26, 0.55, 0.97)
        case .document: return (0.93, 0.77, 0.26)
        case .code: return (0.18, 0.74, 0.81)
        case .system: return (0.45, 0.52, 0.66)
        case .other: return (0.63, 0.63, 0.67)
        case .folder: return (0.38, 0.45, 0.58)
        }
    }

    var color: Color { Color(red: rgb.r, green: rgb.g, blue: rgb.b) }

    var symbol: String {
        switch self {
        case .video: return "film"
        case .image: return "photo"
        case .audio: return "music.note"
        case .archive: return "archivebox"
        case .application: return "app.dashed"
        case .document: return "doc.text"
        case .code: return "chevron.left.forwardslash.chevron.right"
        case .system: return "gearshape"
        case .other: return "doc"
        case .folder: return "folder.fill"
        }
    }
}

extension FileNode {
    var symbol: String {
        if kind == .directory { return "folder.fill" }
        if kind == .symlink { return "arrowshape.turn.up.right" }
        return category.symbol
    }
}
