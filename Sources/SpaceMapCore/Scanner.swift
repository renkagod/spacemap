import Darwin
import Foundation

public struct ScanStats: Sendable {
    public var files: Int64 = 0
    public var directories: Int64 = 0
    public var allocated: Int64 = 0
    public var logical: Int64 = 0
    public var inaccessible = 0
    public var inaccessibleSamples: [String] = []
    public var currentPath = ""
    public var startedAt = Date()
    public var finishedAt: Date?
    public var cancelled = false

    public init() {}

    public var elapsed: TimeInterval { (finishedAt ?? Date()).timeIntervalSince(startedAt) }
}

/// Walks a directory tree on several threads with readdir/lstat and builds a `FileNode` tree.
///
/// The tree grows while the scan runs; every change to it happens under `treeLock`, so the UI
/// can lay out a live, partial tree. Sizes match `du`: allocated blocks, hard links counted once,
/// symlinks not followed, other volumes not entered.
public final class Scanner {
    public let root: FileNode
    public let rootPath: String
    public let treeLock: NSLock

    private var _stats = ScanStats()
    private let condition = NSCondition()
    private var pending: [(FileNode, String)] = []
    private var active = 0
    private var cancelled = false
    private let allowedDevices: Set<dev_t>
    private let excludedPaths: Set<String>
    private let inodeLock = NSLock()
    private var seenInodes = Set<InodeKey>()
    private let threadCount: Int

    private struct InodeKey: Hashable {
        let device: dev_t
        let inode: ino_t
    }

    /// - Parameters:
    ///   - rootName: name of the root node; defaults to the absolute path. Pass the folder name
    ///     when the result will be grafted into an existing tree.
    public init(path: String, treeLock: NSLock, rootName: String? = nil, threads: Int? = nil) {
        var resolved = path
        var buffer = [CChar](repeating: 0, count: Int(PATH_MAX) + 1)
        if realpath(path, &buffer) != nil { resolved = String(cString: buffer) }
        rootPath = resolved
        self.treeLock = treeLock
        threadCount = threads ?? min(16, max(4, ProcessInfo.processInfo.activeProcessorCount * 2))

        let lastComponent = (resolved as NSString).lastPathComponent
        let packageCategory = FileCategory.packageCategory(forDirectoryName: lastComponent)
        root = FileNode(name: rootName ?? resolved, parent: nil,
                        kind: packageCategory == nil ? .directory : .package,
                        category: packageCategory ?? .folder)

        var devices = Set<dev_t>()
        var info = stat()
        if stat(resolved, &info) == 0 {
            devices.insert(info.st_dev)
            root.allocated = Int64(info.st_blocks) * 512
        }
        // The startup disk is two APFS volumes (sealed system + data) stitched together with
        // firmlinks; treat them as one so /Applications, /Users and friends are not skipped.
        var system = stat(), data = stat()
        if lstat("/", &system) == 0, lstat("/System/Volumes/Data", &data) == 0,
           devices.contains(system.st_dev) || devices.contains(data.st_dev) {
            devices.insert(system.st_dev)
            devices.insert(data.st_dev)
        }
        allowedDevices = devices
        // /System/Volumes/Data repeats everything reachable through the firmlinks; the rest are
        // virtual or automount trees.
        excludedPaths = resolved == "/" ? ["/System/Volumes", "/Volumes", "/dev", "/net", "/home"] : []
    }

    /// Current progress; do not call while holding `treeLock`.
    public var stats: ScanStats {
        treeLock.lock()
        defer { treeLock.unlock() }
        return _stats
    }

    public func start(completionQueue: DispatchQueue = .main, completion: @escaping (ScanStats) -> Void) {
        treeLock.lock()
        _stats = ScanStats()
        treeLock.unlock()
        condition.lock()
        pending = [(root, rootPath)]
        condition.unlock()

        let group = DispatchGroup()
        for index in 0..<threadCount {
            group.enter()
            let thread = Thread { [self] in
                work()
                group.leave()
            }
            thread.name = "SpaceMap scan \(index)"
            thread.qualityOfService = .userInitiated
            thread.start()
        }
        group.notify(queue: completionQueue) { [self] in
            let wasCancelled = isCancelled
            treeLock.lock()
            _stats.finishedAt = Date()
            _stats.cancelled = wasCancelled
            let result = _stats
            treeLock.unlock()
            completion(result)
        }
    }

    public func cancel() {
        condition.lock()
        cancelled = true
        condition.broadcast()
        condition.unlock()
    }

    public var isCancelled: Bool {
        condition.lock()
        defer { condition.unlock() }
        return cancelled
    }

    private func work() {
        while true {
            condition.lock()
            while pending.isEmpty && active > 0 && !cancelled {
                condition.wait()
            }
            if cancelled || (pending.isEmpty && active == 0) {
                condition.broadcast()
                condition.unlock()
                return
            }
            // LIFO keeps the queue short (depth-first) on huge trees.
            let (node, path) = pending.removeLast()
            active += 1
            condition.unlock()

            let subdirectories = scanDirectory(node, path: path)

            condition.lock()
            pending.append(contentsOf: subdirectories)
            active -= 1
            condition.broadcast()
            condition.unlock()
        }
    }

    private func scanDirectory(_ directory: FileNode, path: String) -> [(FileNode, String)] {
        guard let dir = opendir(path) else {
            treeLock.lock()
            directory.inaccessible = true
            _stats.inaccessible += 1
            if _stats.inaccessibleSamples.count < 50 { _stats.inaccessibleSamples.append(path) }
            treeLock.unlock()
            return []
        }
        defer { closedir(dir) }
        let fd = dirfd(dir)
        let prefix = path.hasSuffix("/") ? path : path + "/"

        var children: [FileNode] = []
        var subdirectories: [(FileNode, String)] = []
        var allocated: Int64 = 0
        var logical: Int64 = 0
        var files: Int64 = 0
        var info = stat()

        while let entry = readdir(dir) {
            let length = Int(entry.pointee.d_namlen)
            let name: String? = withUnsafePointer(to: &entry.pointee.d_name) { tuple in
                tuple.withMemoryRebound(to: CChar.self, capacity: length + 1) { cName -> String? in
                    if length == 1 && cName[0] == 46 { return nil }
                    if length == 2 && cName[0] == 46 && cName[1] == 46 { return nil }
                    guard fstatat(fd, cName, &info, AT_SYMLINK_NOFOLLOW) == 0 else { return nil }
                    return String(cString: cName)
                }
            }
            guard let name else { continue }

            let type = info.st_mode & S_IFMT
            let blocks = Int64(info.st_blocks) * 512
            if type == S_IFDIR {
                let childPath = prefix + name
                if !allowedDevices.contains(info.st_dev) || excludedPaths.contains(childPath) { continue }
                let packageCategory = FileCategory.packageCategory(forDirectoryName: name)
                let node = FileNode(name: name, parent: directory,
                                    kind: packageCategory == nil ? .directory : .package,
                                    category: packageCategory ?? .folder)
                node.allocated = blocks
                allocated += blocks
                children.append(node)
                subdirectories.append((node, childPath))
            } else {
                var fileAllocated = blocks
                var fileLogical = Int64(info.st_size)
                if type == S_IFREG && info.st_nlink > 1 {
                    let key = InodeKey(device: info.st_dev, inode: info.st_ino)
                    inodeLock.lock()
                    let isFirstLink = seenInodes.insert(key).inserted
                    inodeLock.unlock()
                    if !isFirstLink {
                        fileAllocated = 0
                        fileLogical = 0
                    }
                }
                let kind: NodeKind = type == S_IFREG ? .file : (type == S_IFLNK ? .symlink : .other)
                let node = FileNode(name: name, parent: directory, kind: kind,
                                    category: kind == .file ? FileCategory.forFileName(name) : .system)
                node.allocated = fileAllocated
                node.logical = fileLogical
                node.fileCount = 1
                allocated += fileAllocated
                logical += fileLogical
                files += 1
                children.append(node)
            }
        }

        treeLock.lock()
        directory.children.append(contentsOf: children)
        var node: FileNode? = directory
        while let current = node {
            current.allocated += allocated
            current.logical += logical
            current.fileCount += files
            node = current.parent
        }
        _stats.files += files
        _stats.directories += 1
        _stats.allocated += allocated
        _stats.logical += logical
        _stats.currentPath = path
        treeLock.unlock()

        return isCancelled ? [] : subdirectories
    }
}
