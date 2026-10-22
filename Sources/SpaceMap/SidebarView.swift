import AppKit
import SpaceMapCore
import SwiftUI

enum SidebarTab: String, Hashable {
    case contents, largest, types
}

struct SidebarView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            SummaryCard()
                .padding(.horizontal, 12)
                .padding(.top, 6)
            Picker(tr("sidebar.view"), selection: $model.sidebarTab) {
                Text(tr("sidebar.contents")).tag(SidebarTab.contents)
                Text(tr("sidebar.largest")).tag(SidebarTab.largest)
                Text(tr("sidebar.types")).tag(SidebarTab.types)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            switch model.sidebarTab {
            case .contents:
                NodeList(rows: model.rows, emptyText: tr("sidebar.empty.contents"))
            case .largest:
                NodeList(rows: model.largest, emptyText: tr("sidebar.empty.largest"))
            case .types:
                TypesList()
            }
        }
    }
}

private struct SummaryCard: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: model.isAtRoot && model.current?.path == "/" ? "internaldrive.fill" : "folder.fill")
                    .foregroundStyle(Color.accentColor)
                Text(model.currentTitle)
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Text(Format.bytes(model.currentSize))
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .monospacedDigit()
            Text(detailText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            if let volume = model.volume {
                VolumeBar(volume: volume, scanned: model.currentSize, scannedTitle: model.currentTitle)
                    .padding(.top, 4)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var detailText: String {
        var text = Format.files(model.currentFiles)
        if !model.isAtRoot, model.rootSize > 0, let root = model.root {
            let share = Format.percent(Double(model.currentSize) / Double(model.rootSize))
            text += " · " + tr("sidebar.shareOfRoot", share, root.title)
        }
        return text
    }
}

private struct VolumeBar: View {
    let volume: VolumeInfo
    let scanned: Int64
    let scannedTitle: String

    var body: some View {
        let total = max(1, Double(volume.total))
        let used = Double(volume.used)
        let mine = min(Double(scanned), used)
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geometry in
                HStack(spacing: 1.5) {
                    Rectangle()
                        .fill(Color.accentColor.gradient)
                        .frame(width: max(2, geometry.size.width * mine / total))
                    Rectangle()
                        .fill(Color.secondary.opacity(0.45))
                        .frame(width: max(0, geometry.size.width * (used - mine) / total))
                    Rectangle()
                        .fill(Color.secondary.opacity(0.14))
                }
                .clipShape(Capsule())
            }
            .frame(height: 8)
            HStack(spacing: 10) {
                LegendDot(color: .accentColor, text: tr("volume.thisFolder"))
                LegendDot(color: .secondary.opacity(0.6), text: tr("volume.rest"))
                LegendDot(color: .secondary.opacity(0.2), text: tr("volume.free", Format.bytes(volume.available)))
            }
            .font(.system(size: 10.5))
            .foregroundStyle(.secondary)
            Text(tr("volume.disk", volume.name, Format.bytes(volume.total)))
                .font(.system(size: 10.5))
                .foregroundStyle(.tertiary)
        }
    }
}

private struct LegendDot: View {
    let color: Color
    let text: String

    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(text).lineLimit(1)
        }
    }
}

private struct NodeList: View {
    @EnvironmentObject private var model: AppModel
    let rows: [Row]
    let emptyText: String

    var body: some View {
        if rows.isEmpty {
            VStack {
                Spacer()
                Text(model.progress.running ? tr("sidebar.collecting") : emptyText)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .frame(maxWidth: .infinity)
        } else {
            List(selection: $model.selectedID) {
                ForEach(rows) { row in
                    NodeRow(row: row)
                }
            }
            .listStyle(.sidebar)
            .contextMenu(forSelectionType: ObjectIdentifier.self) { ids in
                if let id = ids.first, let node = model.node(for: id) {
                    NodeMenu(node: node)
                }
            } primaryAction: { ids in
                if let id = ids.first, let node = model.node(for: id) {
                    model.activate(node)
                }
            }
        }
    }
}

private struct NodeMenu: View {
    @EnvironmentObject private var model: AppModel
    let node: FileNode

    var body: some View {
        if node.isContainer {
            Button(tr("action.openOnMap")) { model.activate(node) }
        }
        Button(tr("action.open")) { model.open(node) }
        Button(tr("action.reveal")) { model.reveal(node) }
        Button(tr("action.copyPath")) { model.copyPath(node) }
        if node.isContainer {
            Divider()
            Button(tr("action.rescan")) { model.rescan(node) }
        }
        Divider()
        Button(tr("action.trash"), role: .destructive) { model.moveToTrash(node) }
    }
}

private struct NodeRow: View {
    let row: Row

    var body: some View {
        HStack(spacing: 9) {
            Group {
                if row.inaccessible {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                } else {
                    Image(nsImage: IconCache.icon(for: row.path))
                        .resizable()
                        .interpolation(.high)
                }
            }
            .frame(width: 20, height: 20)
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(row.name)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 4)
                    Text(Format.bytes(row.size))
                        .font(.system(size: 11.5, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                if let subtitle = row.subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.head)
                }
                ShareBar(fraction: row.fraction, color: row.category.color)
            }
        }
        .padding(.vertical, 3)
        .help(row.subtitle.map { "\($0)/\(row.name)" } ?? row.name)
    }
}

private struct ShareBar: View {
    let fraction: Double
    let color: Color

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.07))
                Capsule()
                    .fill(color.opacity(0.85))
                    .frame(width: max(2, geometry.size.width * min(1, fraction)))
            }
        }
        .frame(height: 3)
    }
}

private struct TypesList: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        if model.categories.isEmpty {
            VStack {
                Spacer()
                Text(model.progress.running ? tr("sidebar.collecting") : tr("sidebar.empty.types"))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .frame(maxWidth: .infinity)
        } else {
            List {
                Section {
                    ForEach(model.categories) { total in
                        TypeRow(total: total, focused: model.focusCategory == total.category,
                                dimmed: model.focusCategory != nil && model.focusCategory != total.category) {
                            model.toggleFocus(total.category)
                        }
                    }
                } footer: {
                    Text(tr("sidebar.types.footer"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 6)
                }
            }
            .listStyle(.sidebar)
        }
    }
}

private struct TypeRow: View {
    let total: CategoryTotal
    let focused: Bool
    let dimmed: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: total.category.symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 26, height: 26)
                    .background(total.category.color.gradient, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(total.category.title)
                            .fontWeight(focused ? .semibold : .regular)
                        Spacer()
                        Text(Format.bytes(total.size))
                            .font(.system(size: 11.5, weight: .medium))
                            .monospacedDigit()
                    }
                    HStack(spacing: 6) {
                        ShareBar(fraction: total.fraction, color: total.category.color)
                        Text(Format.percent(total.fraction))
                            .font(.system(size: 10.5))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 44, alignment: .trailing)
                    }
                }
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 4)
            .background(focused ? total.category.color.opacity(0.16) : .clear,
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .opacity(dimmed ? 0.45 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Finder icons for sidebar rows.
enum IconCache {
    private static let cache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 2000
        return cache
    }()

    static func icon(for path: String) -> NSImage {
        if let cached = cache.object(forKey: path as NSString) { return cached }
        let image = NSWorkspace.shared.icon(forFile: path)
        image.size = NSSize(width: 32, height: 32)
        cache.setObject(image, forKey: path as NSString)
        return image
    }
}
