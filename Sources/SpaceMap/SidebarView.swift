import SpaceMapCore
import SwiftUI

private enum SidebarTab: Hashable {
    case contents, largest, types
}

struct SidebarView: View {
    @EnvironmentObject private var model: AppModel
    @State private var tab: SidebarTab = .contents

    var body: some View {
        VStack(spacing: 0) {
            SummaryCard()
                .padding(.horizontal, 12)
                .padding(.top, 6)
            Picker("Вид", selection: $tab) {
                Text("Содержимое").tag(SidebarTab.contents)
                Text("Крупные").tag(SidebarTab.largest)
                Text("Типы").tag(SidebarTab.types)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            switch tab {
            case .contents:
                NodeList(rows: model.rows, emptyText: "Здесь пусто")
            case .largest:
                NodeList(rows: model.largest, emptyText: "Файлов пока нет")
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
            text += " · \(Format.percent(Double(model.currentSize) / Double(model.rootSize))) от «\(root.title)»"
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
                LegendDot(color: .accentColor, text: "Эта папка")
                LegendDot(color: .secondary.opacity(0.6), text: "Остальное")
                LegendDot(color: .secondary.opacity(0.2), text: "Свободно \(Format.bytes(volume.available))")
            }
            .font(.system(size: 10.5))
            .foregroundStyle(.secondary)
            Text("Диск «\(volume.name)»: \(Format.bytes(volume.total))")
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
                Text(model.progress.running ? "Собираю данные…" : emptyText)
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
            Button("Открыть на карте") { model.activate(node) }
        }
        Button("Открыть") { model.open(node) }
        Button("Показать в Finder") { model.reveal(node) }
        Button("Скопировать путь") { model.copyPath(node) }
        if node.isContainer {
            Divider()
            Button("Пересканировать") { model.rescan(node) }
        }
        Divider()
        Button("Переместить в Корзину…", role: .destructive) { model.moveToTrash(node) }
    }
}

private struct NodeRow: View {
    let row: Row

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: row.inaccessible ? "lock.fill" : row.symbol)
                .font(.system(size: 13))
                .foregroundStyle(row.inaccessible ? Color.secondary : row.category.color)
                .frame(width: 18)
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
                Text(model.progress.running ? "Собираю данные…" : "Нет файлов")
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
                    Text("Нажми на тип, чтобы подсветить его на карте. Приложения и медиатеки считаются целиком.")
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
