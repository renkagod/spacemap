import AppKit
import Combine
import SpaceMapCore
import SwiftUI

struct HoverInfo: Equatable {
    var title: String
    var path: String
    var size: Int64
    var fraction: Double
    var symbol: String
    var category: FileCategory
    var isContainer: Bool
    var fileCount: Int64
    var isAggregate: Bool
}

/// Hovered item, kept apart from `AppModel` so mouse moves only redraw the status bar.
final class HoverState: ObservableObject {
    @Published var info: HoverInfo?
}

/// Scan progress, kept apart from `AppModel` so ticks only redraw the toolbar status.
final class ProgressState: ObservableObject {
    @Published var running = false
    @Published var stats = ScanStats()
    @Published var target = ""
    @Published var lastResult: ScanStats?
}

struct Row: Identifiable, Equatable {
    let node: FileNode
    let name: String
    let subtitle: String?
    let size: Int64
    let fraction: Double
    let symbol: String
    let category: FileCategory
    let inaccessible: Bool

    var id: ObjectIdentifier { ObjectIdentifier(node) }

    static func == (lhs: Row, rhs: Row) -> Bool {
        lhs.node === rhs.node && lhs.size == rhs.size && lhs.fraction == rhs.fraction
            && lhs.subtitle == rhs.subtitle
    }
}

struct CategoryTotal: Identifiable, Equatable {
    let category: FileCategory
    let size: Int64
    let count: Int64
    let fraction: Double
    var id: UInt8 { category.rawValue }
}

struct Crumb: Identifiable {
    let node: FileNode
    let title: String
    var id: ObjectIdentifier { ObjectIdentifier(node) }
}

struct VolumeInfo: Identifiable, Equatable {
    let url: URL
    let name: String
    let total: Int64
    let available: Int64
    let isInternal: Bool
    let isRoot: Bool

    var id: String { url.path }
    var used: Int64 { max(0, total - available) }
    var usedFraction: Double { total > 0 ? Double(used) / Double(total) : 0 }

    private static let keys: [URLResourceKey] = [
        .volumeNameKey, .volumeLocalizedNameKey, .volumeTotalCapacityKey,
        .volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey,
        .volumeIsInternalKey, .volumeIsRootFileSystemKey, .volumeIsBrowsableKey, .volumeURLKey,
    ]

    init?(volumeURL url: URL) {
        guard let values = try? url.resourceValues(forKeys: Set(Self.keys)),
              let total = values.volumeTotalCapacity, total > 0 else { return nil }
        self.url = url
        name = values.volumeLocalizedName ?? values.volumeName ?? url.lastPathComponent
        self.total = Int64(total)
        let important = values.volumeAvailableCapacityForImportantUsage ?? 0
        let plain = Int64(values.volumeAvailableCapacity ?? 0)
        available = max(important, plain)
        isRoot = values.volumeIsRootFileSystem ?? (url.path == "/")
        isInternal = values.volumeIsInternal ?? isRoot
    }

    static func mounted() -> [VolumeInfo] {
        let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys,
                                                         options: [.skipHiddenVolumes]) ?? []
        return urls.compactMap { url -> VolumeInfo? in
            let values = try? url.resourceValues(forKeys: [.volumeIsBrowsableKey])
            guard values?.volumeIsBrowsable ?? true else { return nil }
            return VolumeInfo(volumeURL: url)
        }
        .sorted { ($0.isRoot ? 0 : 1, $0.name) < ($1.isRoot ? 0 : 1, $1.name) }
    }

    /// The volume holding `path`.
    static func containing(_ path: String) -> VolumeInfo? {
        let url = URL(fileURLWithPath: path)
        guard let volumeURL = (try? url.resourceValues(forKeys: [.volumeURLKey]))?.volume else { return nil }
        return VolumeInfo(volumeURL: volumeURL)
    }
}

final class AppModel: ObservableObject {
    static let shared = AppModel()

    let treeLock = NSLock()
    let hover = HoverState()
    let progress = ProgressState()

    @Published private(set) var root: FileNode?
    @Published private(set) var current: FileNode?
    @Published private(set) var crumbs: [Crumb] = []
    @Published private(set) var rows: [Row] = []
    @Published private(set) var largest: [Row] = []
    @Published private(set) var categories: [CategoryTotal] = []
    @Published private(set) var currentSize: Int64 = 0
    @Published private(set) var currentFiles: Int64 = 0
    @Published private(set) var rootSize: Int64 = 0
    @Published private(set) var volume: VolumeInfo?
    @Published private(set) var inaccessibleCount = 0
    @Published var accessBannerDismissed = false
    @Published var selectedID: ObjectIdentifier? {
        didSet {
            guard selectedID != oldValue, selectedID != selectedNode.map({ ObjectIdentifier($0) }) else { return }
            selectedNode = selectedID.flatMap(node(for:))
            treemapView?.selectedNode = selectedNode
        }
    }
    @Published var sizeMode: SizeMode = .allocated {
        didSet { if sizeMode != oldValue { refreshAll(.fade) } }
    }
    @Published var focusCategory: FileCategory? {
        didSet { if focusCategory != oldValue { requestRender(.fade) } }
    }

    private(set) var selectedNode: FileNode?
    private weak var treemapView: TreemapView?
    private var scanner: Scanner?
    private var rescanTarget: FileNode?
    private var tickTimer: Timer?
    private var tickCount = 0
    private var resizeWork: DispatchWorkItem?

    private let renderQueue = DispatchQueue(label: "SpaceMap.render", qos: .userInitiated)
    private let summaryQueue = DispatchQueue(label: "SpaceMap.summary", qos: .utility)
    private let generationLock = NSLock()
    private var renderGeneration = 0
    private var summaryGeneration = 0

    // MARK: - Derived state

    var currentTitle: String { current?.title ?? "SpaceMap" }
    var canGoUp: Bool { current?.parent != nil }
    var isAtRoot: Bool { current === root }
    var isCurrentEmpty: Bool { rows.isEmpty }
    var currentIsInaccessible: Bool { current?.inaccessible ?? false }

    func node(for id: ObjectIdentifier) -> FileNode? {
        if let node = selectedNode, ObjectIdentifier(node) == id { return node }
        return rows.first { $0.id == id }?.node ?? largest.first { $0.id == id }?.node
    }

    // MARK: - Scanning

    func startScan(url: URL) {
        stopTimer()
        scanner?.cancel()
        scanner = nil
        rescanTarget = nil

        let scanner = Scanner(path: url.path, treeLock: treeLock)
        let fileManager = FileManager.default
        if scanner.rootPath == "/" {
            scanner.root.displayName = VolumeInfo.containing("/")?.name ?? "Macintosh HD"
        } else if scanner.rootPath == fileManager.homeDirectoryForCurrentUser.path {
            scanner.root.displayName = "Домашняя папка"
        } else {
            scanner.root.displayName = fileManager.displayName(atPath: scanner.rootPath)
        }
        self.scanner = scanner
        root = scanner.root
        current = scanner.root
        selectNode(nil)
        hover.info = nil
        volume = VolumeInfo.containing(scanner.rootPath)
        inaccessibleCount = 0
        accessBannerDismissed = false
        focusCategory = nil
        progress.target = scanner.root.title
        progress.stats = ScanStats()
        progress.running = true
        refreshAll(.none)

        startTimer()
        scanner.start { [weak self, weak scanner] stats in
            guard let self, let scanner, scanner === self.scanner else { return }
            self.scanFinished(stats)
        }
    }

    /// Scans `node` again and grafts the fresh result into the tree.
    func rescan(_ node: FileNode) {
        guard !progress.running, node.isContainer else { return }
        guard node !== root, node.parent != nil else {
            if let root { startScan(url: URL(fileURLWithPath: root.path)) }
            return
        }
        let scanner = Scanner(path: node.path, treeLock: treeLock, rootName: node.name)
        self.scanner = scanner
        rescanTarget = node
        progress.target = node.title
        progress.stats = ScanStats()
        progress.running = true
        startTimer()
        scanner.start { [weak self, weak scanner] stats in
            guard let self, let scanner, scanner === self.scanner else { return }
            self.treeLock.lock()
            TreeEditor.replace(node, with: scanner.root)
            self.treeLock.unlock()
            if let current = self.current, current.isDescendant(of: node) {
                self.current = scanner.root
            }
            if let selected = self.selectedNode, selected.isDescendant(of: node) {
                self.selectNode(nil)
            }
            self.scanFinished(stats)
        }
    }

    func stopScan() {
        scanner?.cancel()
    }

    func rescanCurrent() {
        if let current { rescan(current) }
    }

    func closeScan() {
        stopTimer()
        scanner?.cancel()
        scanner = nil
        root = nil
        current = nil
        rows = []
        largest = []
        categories = []
        crumbs = []
        selectNode(nil)
        hover.info = nil
        progress.running = false
        progress.lastResult = nil
    }

    private func scanFinished(_ stats: ScanStats) {
        stopTimer()
        scanner = nil
        rescanTarget = nil
        progress.running = false
        progress.stats = stats
        progress.lastResult = stats
        if let root {
            inaccessibleCount = countInaccessible(under: root)
        }
        refreshAll(.none)
        if !NSApp.isActive { NSApp.requestUserAttention(.informationalRequest) }
    }

    private func startTimer() {
        tickTimer?.invalidate()
        tickCount = 0
        let timer = Timer(timeInterval: 0.4, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer, forMode: .common)
        tickTimer = timer
    }

    private func stopTimer() {
        tickTimer?.invalidate()
        tickTimer = nil
    }

    private func tick() {
        guard let scanner else { return }
        progress.stats = scanner.stats
        tickCount += 1
        // A rescan builds a detached tree; the visible one only changes when it is grafted in.
        guard rescanTarget == nil else { return }
        inaccessibleCount = progress.stats.inaccessible
        updateSidebar()
        requestRender(.none)
        if tickCount % 5 == 0 { requestSummary() }
    }

    private func countInaccessible(under node: FileNode) -> Int {
        var count = 0
        var stack = [node]
        treeLock.lock()
        while let next = stack.popLast() {
            if next.inaccessible { count += 1 }
            for child in next.children where child.isContainer { stack.append(child) }
        }
        treeLock.unlock()
        return count
    }

    // MARK: - Navigation

    func zoom(into node: FileNode, from rect: CGRect? = nil) {
        guard node.isContainer, node !== current else { return }
        current = node
        refreshAll(rect.map { TreemapView.Transition.zoomIn($0) } ?? .fade)
    }

    func goUp() {
        guard let current, let parent = current.parent else { return }
        self.current = parent
        refreshAll(.zoomOut(current))
    }

    func goToRoot() {
        guard let root else { return }
        navigate(to: root)
    }

    func navigate(to node: FileNode) {
        guard let previous = current, node !== previous else { return }
        current = node
        if previous.isDescendant(of: node) {
            // The child of `node` on the way down to where we were.
            var child = previous
            while let parent = child.parent, parent !== node { child = parent }
            refreshAll(.zoomOut(child))
        } else {
            refreshAll(.fade)
        }
    }

    /// Double click / Return on a treemap item.
    func activate(_ item: TreemapItem) {
        switch item.kind {
        case .directory, .leaf:
            guard let node = item.node else { return }
            if node.isContainer {
                zoom(into: node, from: item.rect)
            } else if let parent = node.parent, parent !== current {
                zoom(into: parent, from: treemapView?.rect(for: parent))
            } else {
                selectNode(node)
            }
        case .aggregate:
            if item.owner !== current { zoom(into: item.owner, from: treemapView?.rect(for: item.owner)) }
        }
    }

    /// Double click / Return on a sidebar row.
    func activate(_ node: FileNode) {
        if node.isContainer, node.parent === current {
            zoom(into: node, from: treemapView?.rect(for: node))
        } else if let parent = node.parent, parent !== current {
            navigate(to: parent)
            selectNode(node)
        } else {
            reveal(node)
        }
    }

    func selectNode(_ node: FileNode?) {
        selectedNode = node
        treemapView?.selectedNode = node
        let id = node.map { ObjectIdentifier($0) }
        if selectedID != id { selectedID = id }
    }

    // MARK: - Treemap view

    func attach(_ view: TreemapView) {
        treemapView = view
        view.selectedNode = selectedNode
        view.onHover = { [weak self] item in self?.updateHover(item) }
        view.onClick = { [weak self] item in self?.selectNode(item?.node) }
        view.onDoubleClick = { [weak self] item in self?.activate(item) }
        view.onMenu = { [weak self] item in self?.menu(for: item) }
        view.onBack = { [weak self] in self?.goUp() }
        view.onResize = { [weak self, weak view] in
            guard let self, let view else { return }
            if view.hasImage {
                self.scheduleResizeRender()
            } else {
                self.requestRender(.none)
            }
        }
        requestRender(.none)
    }

    private func scheduleResizeRender() {
        resizeWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.requestRender(.none) }
        resizeWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: work)
    }

    private func nextRenderGeneration() -> Int {
        generationLock.lock()
        defer { generationLock.unlock() }
        renderGeneration += 1
        return renderGeneration
    }

    private func nextSummaryGeneration() -> Int {
        generationLock.lock()
        defer { generationLock.unlock() }
        summaryGeneration += 1
        return summaryGeneration
    }

    private func isLatestRender(_ generation: Int) -> Bool {
        generationLock.lock()
        defer { generationLock.unlock() }
        return generation == renderGeneration
    }

    private func isLatestSummary(_ generation: Int) -> Bool {
        generationLock.lock()
        defer { generationLock.unlock() }
        return generation == summaryGeneration
    }

    func requestRender(_ transition: TreemapView.Transition) {
        guard let view = treemapView else { return }
        guard let current else {
            view.show(items: [], image: nil, size: .zero, transition: .none)
            return
        }
        let size = view.bounds.size
        guard size.width >= 2, size.height >= 2 else { return }
        let scale = view.window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        var options = TreemapOptions()
        options.sizeMode = sizeMode
        let focus = focusCategory
        let lock = treeLock
        let generation = nextRenderGeneration()

        renderQueue.async { [weak self] in
            guard let self, self.isLatestRender(generation) else { return }
            let items = TreemapLayout.layout(root: current, in: CGRect(origin: .zero, size: size),
                                             options: options, lock: lock)
            guard self.isLatestRender(generation) else { return }
            let image = TreemapRenderer.render(items: items, size: size, scale: scale, focus: focus)
            DispatchQueue.main.async {
                guard self.isLatestRender(generation), let view = self.treemapView else { return }
                view.show(items: items, image: image, size: size, transition: transition)
            }
        }
    }

    private func updateHover(_ item: TreemapItem?) {
        guard let item else {
            if hover.info != nil { hover.info = nil }
            return
        }
        let total = max(1, currentSize)
        let node = item.node ?? item.owner
        let info: HoverInfo
        if item.kind == .aggregate {
            info = HoverInfo(title: "Ещё \(Format.items(Int64(item.aggregateCount))) помельче",
                             path: node.path + "/…", size: item.size,
                             fraction: Double(item.size) / Double(total), symbol: "square.grid.3x3.fill",
                             category: .other, isContainer: false, fileCount: 0, isAggregate: true)
        } else {
            info = HoverInfo(title: node.title, path: node.path, size: item.size,
                             fraction: Double(item.size) / Double(total), symbol: node.symbol,
                             category: node.category, isContainer: node.isContainer,
                             fileCount: node.fileCount, isAggregate: false)
        }
        if hover.info != info { hover.info = info }
    }

    // MARK: - Sidebar data

    func refreshAll(_ transition: TreemapView.Transition) {
        updateSidebar()
        requestRender(transition)
        requestSummary()
    }

    private func updateSidebar() {
        guard let current, let root else {
            rows = []
            crumbs = []
            return
        }
        let mode = sizeMode
        treeLock.lock()
        let children = current.children
        let total = current.size(mode)
        let files = current.fileCount
        let rootTotal = root.size(mode)
        treeLock.unlock()

        let sorted = children.map { ($0, $0.size(mode)) }.sorted { $0.1 > $1.1 }.prefix(400)
        rows = sorted.map { node, size in
            Row(node: node, name: node.title, subtitle: nil, size: size,
                fraction: total > 0 ? Double(size) / Double(total) : 0, symbol: node.symbol,
                category: node.category, inaccessible: node.inaccessible)
        }
        currentSize = total
        currentFiles = files
        rootSize = rootTotal
        crumbs = current.lineage.map { Crumb(node: $0, title: $0.title) }
    }

    /// Largest files and per-type totals of the current folder, computed in the background.
    private func requestSummary() {
        guard let current else {
            largest = []
            categories = []
            return
        }
        let mode = sizeMode
        let lock = treeLock
        let generation = nextSummaryGeneration()
        summaryQueue.async { [weak self] in
            guard let self, self.isLatestSummary(generation) else { return }
            var totals = [Int64](repeating: 0, count: FileCategory.allCases.count)
            var counts = [Int64](repeating: 0, count: FileCategory.allCases.count)
            var top: [(FileNode, Int64)] = []
            var topMinimum: Int64 = 0
            let topLimit = 150
            var stack = [current]
            while let directory = stack.popLast() {
                lock.lock()
                let children = directory.children
                lock.unlock()
                for child in children {
                    if child.kind == .directory {
                        stack.append(child)
                        continue
                    }
                    // Packages (.app, photo libraries) count as one item, like in Finder.
                    let size = child.size(mode)
                    let index = Int(child.category.rawValue)
                    totals[index] += size
                    counts[index] += child.kind == .package ? 1 : child.fileCount
                    if top.count < topLimit {
                        top.append((child, size))
                        if top.count == topLimit { topMinimum = top.map(\.1).min() ?? 0 }
                    } else if size > topMinimum, let minIndex = top.indices.min(by: { top[$0].1 < top[$1].1 }) {
                        top[minIndex] = (child, size)
                        topMinimum = top.map(\.1).min() ?? 0
                    }
                }
            }
            top.sort { $0.1 > $1.1 }
            let total = totals.reduce(0, +)
            let largest = top.map { node, size in
                Row(node: node, name: node.title, subtitle: node.relativeDirectory(from: current),
                    size: size, fraction: total > 0 ? Double(size) / Double(total) : 0,
                    symbol: node.symbol, category: node.category, inaccessible: false)
            }
            let categories = FileCategory.allCases.compactMap { category -> CategoryTotal? in
                let size = totals[Int(category.rawValue)]
                guard size > 0 else { return nil }
                return CategoryTotal(category: category, size: size, count: counts[Int(category.rawValue)],
                                     fraction: total > 0 ? Double(size) / Double(total) : 0)
            }
            .sorted { $0.size > $1.size }

            DispatchQueue.main.async {
                guard self.isLatestSummary(generation) else { return }
                self.largest = largest
                self.categories = categories
            }
        }
    }

    // MARK: - Actions

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.treatsFilePackagesAsDirectories = true
        panel.prompt = "Сканировать"
        panel.message = "Выбери папку или диск, который нужно разобрать"
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser
        if panel.runModal() == .OK, let url = panel.url {
            startScan(url: url)
        }
    }

    func reveal(_ node: FileNode) {
        NSWorkspace.shared.activateFileViewerSelecting([node.url])
    }

    func open(_ node: FileNode) {
        NSWorkspace.shared.open(node.url)
    }

    func copyPath(_ node: FileNode) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(node.path, forType: .string)
    }

    func openFullDiskAccessSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }

    func toggleFocus(_ category: FileCategory) {
        focusCategory = focusCategory == category ? nil : category
    }

    func moveToTrash(_ node: FileNode) {
        guard node !== root, node.parent != nil else { return }
        let size = node.size(sizeMode)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Переместить «\(node.title)» в Корзину?"
        var details = node.isContainer ? "Папка, \(Format.files(node.fileCount)), \(Format.bytes(size))."
                                       : "Файл, \(Format.bytes(size))."
        details += " Место освободится, когда очистишь Корзину."
        alert.informativeText = details
        alert.addButton(withTitle: "В Корзину")
        alert.addButton(withTitle: "Отмена")
        alert.buttons.first?.hasDestructiveAction = true
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        do {
            try FileManager.default.trashItem(at: node.url, resultingItemURL: nil)
        } catch {
            let failure = NSAlert(error: error)
            failure.messageText = "Не получилось переместить «\(node.title)» в Корзину"
            failure.runModal()
            return
        }
        let parent = node.parent
        let currentGone = current.map { $0.isDescendant(of: node) } ?? false
        treeLock.lock()
        TreeEditor.remove(node)
        treeLock.unlock()
        if currentGone { current = parent }
        if let selected = selectedNode, selected === node || selected.parent == nil || selected.isDescendant(of: node) {
            selectNode(nil)
        }
        refreshAll(.fade)
    }

    // MARK: - Menus

    private func menu(for item: TreemapItem) -> NSMenu? {
        let node = item.node ?? item.owner
        let menu = NSMenu()
        menu.autoenablesItems = false
        let header = NSMenuItem(title: "\(node.title) — \(Format.bytes(item.node == nil ? item.size : node.size(sizeMode)))",
                                action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())
        if node.isContainer && node !== current {
            menu.addItem(ActionMenuItem("Открыть на карте", symbol: "arrow.down.right.and.arrow.up.left") { [weak self] in
                self?.zoom(into: node, from: self?.treemapView?.rect(for: node))
            })
        }
        menu.addItem(ActionMenuItem("Открыть", symbol: "arrow.up.forward.app") { [weak self] in self?.open(node) })
        menu.addItem(ActionMenuItem("Показать в Finder", symbol: "folder") { [weak self] in self?.reveal(node) })
        menu.addItem(ActionMenuItem("Скопировать путь", symbol: "doc.on.doc") { [weak self] in self?.copyPath(node) })
        if node.isContainer {
            menu.addItem(.separator())
            menu.addItem(ActionMenuItem("Пересканировать", symbol: "arrow.clockwise", enabled: !progress.running) { [weak self] in
                self?.rescan(node)
            })
        }
        if node !== root {
            menu.addItem(.separator())
            menu.addItem(ActionMenuItem("Переместить в Корзину…", symbol: "trash") { [weak self] in
                self?.moveToTrash(node)
            })
        }
        return menu
    }

    // MARK: - Debug / automation

    /// Hovers the biggest item, for screenshots made by `--snapshot`.
    func simulateHoverOnLargest() {
        guard let view = treemapView else { return }
        if let item = view.items.first(where: { $0.kind == .leaf }) {
            updateHover(item)
            selectNode(item.node)
        }
    }
}
