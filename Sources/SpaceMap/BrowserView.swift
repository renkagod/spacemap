import SpaceMapCore
import SwiftUI

struct BrowserView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 270, ideal: 310, max: 440)
        } detail: {
            VStack(spacing: 0) {
                PathBar()
                Divider()
                TreemapArea()
                Divider()
                StatusBar(hover: model.hover)
            }
            .navigationTitle(model.currentTitle)
            .navigationSubtitle(Format.bytes(model.currentSize))
        }
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button { model.goUp() } label: {
                    Label("Наверх", systemImage: "chevron.up")
                }
                .help("Наверх (⌘↑, Esc)")
                .disabled(!model.canGoUp)
                Button { model.goToRoot() } label: {
                    Label("К началу", systemImage: "arrow.up.to.line")
                }
                .help("К началу (⇧⌘↑)")
                .disabled(model.isAtRoot)
            }
            ToolbarItem(placement: .principal) {
                ScanStatus(progress: model.progress) { model.stopScan() }
            }
            ToolbarItemGroup(placement: .primaryAction) {
                RescanButton(progress: model.progress) { model.rescanCurrent() }
                Button { model.closeScan() } label: {
                    Label("Новое сканирование", systemImage: "plus.magnifyingglass")
                }
                .help("Выбрать другой диск или папку (⌘N)")
            }
        }
    }
}

private struct RescanButton: View {
    @ObservedObject var progress: ProgressState
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label("Пересканировать", systemImage: "arrow.clockwise")
        }
        .help("Пересканировать эту папку (⌘R)")
        .disabled(progress.running)
    }
}

private struct ScanStatus: View {
    @ObservedObject var progress: ProgressState
    let stop: () -> Void

    var body: some View {
        HStack(spacing: 9) {
            if progress.running {
                ProgressView()
                    .controlSize(.small)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Сканирую «\(progress.target)»")
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                    Text("\(Format.files(progress.stats.files)) · \(Format.bytes(progress.stats.allocated)) · \(Format.duration(progress.stats.elapsed))")
                        .font(.system(size: 11))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Button(action: stop) {
                    Image(systemName: "stop.circle.fill")
                        .font(.system(size: 16))
                }
                .buttonStyle(.borderless)
                .help("Остановить (⌘.)")
            } else if let result = progress.lastResult {
                Image(systemName: result.cancelled ? "pause.circle.fill" : "checkmark.circle.fill")
                    .foregroundStyle(result.cancelled ? Color.orange : Color.green)
                Text(result.cancelled
                     ? "Остановлено: \(Format.files(result.files))"
                     : "\(Format.files(result.files)) за \(Format.duration(result.elapsed))")
                    .font(.system(size: 12))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(minWidth: 220)
    }
}

// MARK: - Path bar

private struct PathBar: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack(spacing: 8) {
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 1) {
                        ForEach(Array(model.crumbs.enumerated()), id: \.element.id) { index, crumb in
                            if index > 0 {
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(.tertiary)
                            }
                            CrumbButton(crumb: crumb, isFirst: index == 0,
                                        isLast: index == model.crumbs.count - 1) {
                                model.navigate(to: crumb.node)
                            }
                            .id(crumb.id)
                        }
                    }
                    .padding(.horizontal, 8)
                }
                .onChange(of: model.crumbs.last?.id) { id in
                    if let id { withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(id, anchor: .trailing) } }
                }
            }
            if let focus = model.focusCategory {
                Button { model.focusCategory = nil } label: {
                    HStack(spacing: 5) {
                        Circle().fill(focus.color).frame(width: 8, height: 8)
                        Text("Подсвечено: \(focus.title)")
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .font(.system(size: 11.5, weight: .medium))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(focus.color.opacity(0.16), in: Capsule())
                }
                .buttonStyle(.plain)
                .help("Убрать подсветку (⌥Esc)")
            }
            Picker("Размер", selection: $model.sizeMode) {
                ForEach(SizeMode.allCases, id: \.self) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.small)
            .fixedSize()
            .help("«На диске» — сколько места реально занято. «Длина файлов» — сумма размеров, как в Finder.")
            .padding(.trailing, 10)
        }
        .frame(height: 34)
        .background(.bar)
    }
}

private struct CrumbButton: View {
    let crumb: Crumb
    let isFirst: Bool
    let isLast: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if isFirst {
                    Image(systemName: crumb.node.path == "/" ? "internaldrive" : "folder")
                        .font(.system(size: 11))
                }
                Text(crumb.title)
                    .font(.system(size: 12, weight: isLast ? .semibold : .regular))
                    .lineLimit(1)
            }
            .foregroundStyle(isLast ? .primary : .secondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(hovering && !isLast ? Color.primary.opacity(0.08) : .clear,
                        in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

// MARK: - Treemap area

private struct TreemapArea: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ZStack(alignment: .bottom) {
            TreemapRepresentable(model: model)
            if model.isCurrentEmpty {
                EmptyFolderView()
            }
            if model.inaccessibleCount > 0 && !model.accessBannerDismissed {
                AccessBanner()
                    .padding(14)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: model.inaccessibleCount > 0)
    }
}

private struct TreemapRepresentable: NSViewRepresentable {
    let model: AppModel

    func makeNSView(context: Context) -> TreemapView {
        let view = TreemapView(frame: .zero)
        model.attach(view)
        return view
    }

    func updateNSView(_ nsView: TreemapView, context: Context) {}
}

private struct EmptyFolderView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 12) {
            if model.currentIsInaccessible {
                Image(systemName: "lock.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(.secondary)
                Text("macOS не пускает в эту папку")
                    .font(.title3.weight(.semibold))
                Text("Дай SpaceMap «Полный доступ к диску» и пересканируй.")
                    .foregroundStyle(.secondary)
                Button("Открыть настройки доступа") { model.openFullDiskAccessSettings() }
            } else if model.progress.running {
                ProgressView()
                Text("Читаю содержимое…")
                    .foregroundStyle(.secondary)
            } else {
                Image(systemName: "folder")
                    .font(.system(size: 40))
                    .foregroundStyle(.secondary)
                Text("Папка пуста")
                    .font(.title3.weight(.semibold))
            }
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .environment(\.colorScheme, .dark)
    }
}

private struct AccessBanner: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.lock.fill")
                .font(.title2)
                .foregroundStyle(.yellow)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(Format.folders(Int64(model.inaccessibleCount))) без доступа")
                    .font(.system(size: 13, weight: .semibold))
                Text("macOS защищает их. С «Полным доступом к диску» карта будет точнее.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Button("Дать доступ") { model.openFullDiskAccessSettings() }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            Button {
                model.accessBannerDismissed = true
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Скрыть")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.white.opacity(0.08))
        }
        .shadow(color: .black.opacity(0.35), radius: 16, y: 6)
        .environment(\.colorScheme, .dark)
    }
}

// MARK: - Status bar

private struct StatusBar: View {
    @ObservedObject var hover: HoverState
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack(spacing: 10) {
            if let info = hover.info {
                Image(systemName: info.symbol)
                    .foregroundStyle(info.isAggregate ? Color.secondary : info.category.color)
                    .frame(width: 16)
                Text(info.title)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                    .layoutPriority(1)
                Text((info.path as NSString).abbreviatingWithTildeInPath)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 12)
                if info.isContainer {
                    Text(Format.files(info.fileCount))
                        .foregroundStyle(.secondary)
                }
                Text(Format.percent(info.fraction))
                    .foregroundStyle(.secondary)
                Text(Format.bytes(info.size))
                    .fontWeight(.semibold)
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 14) {
                        Legend()
                        Spacer(minLength: 10)
                        Text("Двойной клик — внутрь · Esc — назад · правый клик — действия")
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                    HStack {
                        Legend()
                        Spacer(minLength: 0)
                    }
                    Text("Двойной клик — внутрь · Esc — назад")
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .font(.system(size: 11.5))
        .monospacedDigit()
        .padding(.horizontal, 12)
        .frame(height: 28)
        .background(.bar)
    }
}

private struct Legend: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack(spacing: 11) {
            ForEach(FileCategory.fileCategories, id: \.self) { category in
                Button { model.toggleFocus(category) } label: {
                    HStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                            .fill(category.color)
                            .frame(width: 9, height: 9)
                        Text(category.shortTitle)
                            .foregroundStyle(.secondary)
                    }
                    .opacity(model.focusCategory == nil || model.focusCategory == category ? 1 : 0.4)
                }
                .buttonStyle(.plain)
                .help("Подсветить: \(category.title)")
            }
        }
        .fixedSize()
    }
}
