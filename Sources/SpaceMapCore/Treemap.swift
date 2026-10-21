import CoreGraphics
import Foundation

public struct TreemapItem {
    public enum Kind: UInt8 {
        /// A folder drawn as a frame with a title strip and its contents inside.
        case directory
        /// A file, or a folder too small to open up.
        case leaf
        /// Many small entries of `owner` merged into one block.
        case aggregate
    }

    public let rect: CGRect
    public let kind: Kind
    /// nil for aggregates.
    public let node: FileNode?
    /// The node itself, or the folder whose small entries an aggregate holds.
    public let owner: FileNode
    public let size: Int64
    public let depth: Int
    public let headerHeight: CGFloat
    public let aggregateCount: Int
    public let category: FileCategory
}

public struct TreemapOptions {
    public var sizeMode: SizeMode = .allocated
    public var headerHeight: CGFloat = 17
    public var padding: CGFloat = 3
    /// Entries that would get less area than this (in points²) are merged into one aggregate block.
    public var minLeafArea: CGFloat = 12
    public var minContainerSize = CGSize(width: 34, height: 28)
    public var maxItems = 60_000
    /// Draw .app bundles and other packages as solid blocks instead of opening them up.
    public var collapsePackages = true

    public init() {}
}

public enum TreemapLayout {
    /// Nested squarified layout of `root`'s contents. Items come out in depth-first order,
    /// parents before their contents.
    ///
    /// - Parameter lock: tree lock to hold while reading child lists of a tree that is still
    ///   being scanned.
    public static func layout(root: FileNode, in bounds: CGRect, options: TreemapOptions,
                              lock: NSLock? = nil) -> [TreemapItem] {
        var builder = Builder(options: options, lock: lock)
        guard bounds.width >= 1, bounds.height >= 1 else { return [] }
        builder.layoutChildren(of: root, in: bounds, depth: 0)
        return builder.items
    }

    private struct Builder {
        let options: TreemapOptions
        let lock: NSLock?
        var items: [TreemapItem] = []

        init(options: TreemapOptions, lock: NSLock?) {
            self.options = options
            self.lock = lock
            items.reserveCapacity(4096)
        }

        func children(of node: FileNode) -> [FileNode] {
            lock?.lock()
            defer { lock?.unlock() }
            return node.children
        }

        mutating func place(_ node: FileNode, size: Int64, in rect: CGRect, depth: Int) {
            let opens = node.isContainer
                && !(options.collapsePackages && node.kind == .package)
                && rect.width >= options.minContainerSize.width
                && rect.height >= options.minContainerSize.height
                && items.count < options.maxItems
            guard opens else {
                items.append(TreemapItem(rect: rect, kind: .leaf, node: node, owner: node, size: size,
                                         depth: depth, headerHeight: 0, aggregateCount: 0,
                                         category: node.category))
                return
            }
            let padding = options.padding
            let header = rect.height >= options.headerHeight + 16 && rect.width >= 44
                ? options.headerHeight : padding
            items.append(TreemapItem(rect: rect, kind: .directory, node: node, owner: node, size: size,
                                     depth: depth, headerHeight: header, aggregateCount: 0,
                                     category: node.category))
            let inner = CGRect(x: rect.minX + padding, y: rect.minY + header,
                               width: rect.width - 2 * padding, height: rect.height - header - padding)
            if inner.width >= 2 && inner.height >= 2 {
                layoutChildren(of: node, in: inner, depth: depth + 1)
            }
        }

        mutating func layoutChildren(of node: FileNode, in rect: CGRect, depth: Int) {
            let mode = options.sizeMode
            // Sizes are read once: the scanner may grow them while we work.
            var entries: [(node: FileNode, size: Int64)] = []
            for child in children(of: node) {
                let size = child.size(mode)
                if size > 0 { entries.append((child, size)) }
            }
            guard !entries.isEmpty else { return }
            entries.sort { $0.size > $1.size }

            let total = entries.reduce(0.0) { $0 + Double($1.size) }
            let area = Double(rect.width * rect.height)
            guard total > 0, area > 0 else { return }
            let scale = area / total

            var cut = entries.count
            for (index, entry) in entries.enumerated() where Double(entry.size) * scale < Double(options.minLeafArea) {
                cut = index
                break
            }
            cut = min(cut, max(0, options.maxItems - items.count))

            var values = entries[..<cut].map { Double($0.size) }
            var restSize: Int64 = 0
            if cut < entries.count {
                restSize = entries[cut...].reduce(0) { $0 + $1.size }
                values.append(Double(restSize))
            }
            let rects = TreemapLayout.squarify(values, in: rect)
            for index in 0..<cut {
                place(entries[index].node, size: entries[index].size, in: rects[index], depth: depth)
            }
            if cut < entries.count {
                items.append(TreemapItem(rect: rects[cut], kind: .aggregate, node: nil, owner: node,
                                         size: restSize, depth: depth, headerHeight: 0,
                                         aggregateCount: entries.count - cut, category: .other))
            }
        }
    }

    /// Squarified treemap (Bruls, Huizing, van Wijk). Values should be sorted descending for the
    /// best aspect ratios; the result has one rect per value, in the same order.
    public static func squarify(_ values: [Double], in rect: CGRect) -> [CGRect] {
        var result = [CGRect](repeating: .zero, count: values.count)
        let total = values.reduce(0, +)
        guard total > 0, rect.width > 0, rect.height > 0 else { return result }
        let scale = Double(rect.width * rect.height) / total
        let areas = values.map { max(0, $0) * scale }

        var remaining = rect
        var start = 0
        while start < areas.count {
            let side = Double(min(remaining.width, remaining.height))
            if side <= 0 {
                for index in start..<areas.count {
                    result[index] = CGRect(x: remaining.minX, y: remaining.minY, width: 0, height: 0)
                }
                break
            }

            var end = start
            var rowSum = 0.0
            var rowMin = Double.infinity
            var rowMax = 0.0
            var bestWorst = Double.infinity
            while end < areas.count {
                let area = areas[end]
                let sum = rowSum + area
                let newMin = min(rowMin, area)
                let newMax = max(rowMax, area)
                let worst = worstRatio(sum: sum, min: newMin, max: newMax, side: side)
                if end > start && worst > bestWorst { break }
                rowSum = sum
                rowMin = newMin
                rowMax = newMax
                bestWorst = worst
                end += 1
            }

            let thickness = rowSum > 0 ? rowSum / side : 0
            if remaining.width >= remaining.height {
                // Column along the left edge.
                var y = Double(remaining.minY)
                for index in start..<end {
                    let height = thickness > 0 ? areas[index] / thickness : 0
                    result[index] = CGRect(x: Double(remaining.minX), y: y, width: thickness, height: height)
                    y += height
                }
                let width = max(0, Double(remaining.width) - thickness)
                remaining = CGRect(x: Double(remaining.minX) + thickness, y: Double(remaining.minY),
                                   width: width, height: Double(remaining.height))
            } else {
                // Row along the top edge.
                var x = Double(remaining.minX)
                for index in start..<end {
                    let width = thickness > 0 ? areas[index] / thickness : 0
                    result[index] = CGRect(x: x, y: Double(remaining.minY), width: width, height: thickness)
                    x += width
                }
                let height = max(0, Double(remaining.height) - thickness)
                remaining = CGRect(x: Double(remaining.minX), y: Double(remaining.minY) + thickness,
                                   width: Double(remaining.width), height: height)
            }
            start = end
        }
        return result
    }

    private static func worstRatio(sum: Double, min: Double, max: Double, side: Double) -> Double {
        guard sum > 0, min > 0 else { return .infinity }
        let sideSquared = side * side
        let sumSquared = sum * sum
        return Swift.max(sideSquared * max / sumSquared, sumSquared / (sideSquared * min))
    }
}
