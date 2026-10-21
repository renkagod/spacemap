import Foundation

public enum NodeKind: UInt8, Sendable {
    case file, directory, package, symlink, other
}

/// One entry of the scanned tree. Directory sizes are the totals of their subtree.
///
/// `children` and the sizes are written by the scanner threads under the tree lock;
/// `name`, `kind` and `category` never change.
public final class FileNode {
    public let name: String
    public internal(set) weak var parent: FileNode?
    public let kind: NodeKind
    public let category: FileCategory
    public internal(set) var allocated: Int64 = 0
    public internal(set) var logical: Int64 = 0
    /// Number of files in the subtree; 1 for a file.
    public internal(set) var fileCount: Int64 = 0
    public internal(set) var children: [FileNode] = []
    public internal(set) var inaccessible = false
    /// Overrides `name` in the UI; set on scan roots ("Macintosh HD" instead of "/").
    public var displayName: String?

    public init(name: String, parent: FileNode?, kind: NodeKind, category: FileCategory) {
        self.name = name
        self.parent = parent
        self.kind = kind
        self.category = category
    }

    public var isContainer: Bool { kind == .directory || kind == .package }

    public var title: String { displayName ?? name }

    public func size(_ mode: SizeMode) -> Int64 {
        mode == .allocated ? allocated : logical
    }

    /// Absolute path. The root node's name holds the absolute path of the scan root.
    public var path: String {
        var parts: [String] = []
        var node: FileNode? = self
        while let current = node {
            parts.append(current.name)
            node = current.parent
        }
        var result = parts.removeLast()
        for part in parts.reversed() {
            if !result.hasSuffix("/") { result += "/" }
            result += part
        }
        return result
    }

    public var url: URL { URL(fileURLWithPath: path, isDirectory: isContainer) }

    /// Nodes from the tree root down to this node, inclusive.
    public var lineage: [FileNode] {
        var chain: [FileNode] = []
        var node: FileNode? = self
        while let current = node {
            chain.append(current)
            node = current.parent
        }
        return chain.reversed()
    }

    public func isDescendant(of ancestor: FileNode) -> Bool {
        var node: FileNode? = self
        while let current = node {
            if current === ancestor { return true }
            node = current.parent
        }
        return false
    }

    /// Path of this node relative to `ancestor`, without the node's own name.
    public func relativeDirectory(from ancestor: FileNode) -> String {
        var parts: [String] = []
        var node = parent
        while let current = node, current !== ancestor {
            parts.append(current.name)
            node = current.parent
        }
        return parts.reversed().joined(separator: "/")
    }
}

/// Edits of a scanned tree after files were changed on disk. Callers hold the tree lock.
public enum TreeEditor {
    public static func remove(_ node: FileNode) {
        guard let parent = node.parent else { return }
        if let index = parent.children.firstIndex(where: { $0 === node }) {
            parent.children.remove(at: index)
        }
        adjust(from: parent, allocated: -node.allocated, logical: -node.logical, files: -node.fileCount)
        node.parent = nil
    }

    public static func replace(_ old: FileNode, with new: FileNode) {
        guard let parent = old.parent,
              let index = parent.children.firstIndex(where: { $0 === old }) else { return }
        parent.children[index] = new
        new.parent = parent
        old.parent = nil
        adjust(from: parent,
               allocated: new.allocated - old.allocated,
               logical: new.logical - old.logical,
               files: new.fileCount - old.fileCount)
    }

    private static func adjust(from start: FileNode, allocated: Int64, logical: Int64, files: Int64) {
        var node: FileNode? = start
        while let current = node {
            current.allocated += allocated
            current.logical += logical
            current.fileCount += files
            node = current.parent
        }
    }
}
