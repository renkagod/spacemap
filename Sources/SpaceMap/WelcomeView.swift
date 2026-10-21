import SpaceMapCore
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @State private var dropTargeted = false

    var body: some View {
        Group {
            if model.root == nil {
                WelcomeView()
            } else {
                BrowserView()
            }
        }
        .frame(minWidth: 900, minHeight: 560)
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first(where: isDirectory) else { return false }
            model.startScan(url: url)
            return true
        } isTargeted: { dropTargeted = $0 }
        .overlay {
            if dropTargeted {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 3, dash: [10, 7]))
                    .background(Color.accentColor.opacity(0.06), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .padding(10)
                    .allowsHitTesting(false)
            }
        }
    }
}

struct WelcomeView: View {
    @EnvironmentObject private var model: AppModel
    @State private var volumes: [VolumeInfo] = []

    private var homePath: String { FileManager.default.homeDirectoryForCurrentUser.path }

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color.accentColor.opacity(0.10), .clear],
                           startPoint: .top, endPoint: .center)
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 34) {
                    header
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 250, maximum: 300), spacing: 16)], spacing: 16) {
                        ForEach(volumes) { volume in
                            LocationCard(title: volume.name,
                                         subtitle: "Занято \(Format.bytes(volume.used)) из \(Format.bytes(volume.total))",
                                         symbol: volume.isInternal ? "internaldrive.fill" : "externaldrive.fill",
                                         tint: volume.isInternal ? .blue : .orange,
                                         fraction: volume.usedFraction) {
                                model.startScan(url: volume.url)
                            }
                        }
                        LocationCard(title: "Домашняя папка",
                                     subtitle: (homePath as NSString).abbreviatingWithTildeInPath,
                                     symbol: "house.fill", tint: .green, fraction: nil) {
                            model.startScan(url: URL(fileURLWithPath: homePath))
                        }
                        LocationCard(title: "Выбрать папку…",
                                     subtitle: "или перетащи её в это окно",
                                     symbol: "folder.fill.badge.plus", tint: .purple, fraction: nil) {
                            model.chooseFolder()
                        }
                    }
                    .frame(maxWidth: 960)

                    accessHint
                }
                .padding(.horizontal, 40)
                .padding(.vertical, 48)
                .frame(maxWidth: .infinity)
            }
        }
        .onAppear { volumes = VolumeInfo.mounted() }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didMountNotification)) { _ in
            volumes = VolumeInfo.mounted()
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didUnmountNotification)) { _ in
            volumes = VolumeInfo.mounted()
        }
    }

    private var header: some View {
        VStack(spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 112, height: 112)
                .shadow(color: .black.opacity(0.18), radius: 12, y: 6)
            Text("SpaceMap")
                .font(.system(size: 38, weight: .bold, design: .rounded))
            Text("Покажу, что съело место на диске — наглядно, большими блоками.")
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private var accessHint: some View {
        HStack(spacing: 10) {
            Image(systemName: "lock.shield")
                .font(.title3)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text("Часть папок macOS прячет от программ: почту, «Сообщения», системные данные.")
                Text("Чтобы учесть и их, дай SpaceMap «Полный доступ к диску».")
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            Button("Открыть настройки") { model.openFullDiskAccessSettings() }
                .buttonStyle(.link)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

struct LocationCard: View {
    let title: String
    let subtitle: String
    let symbol: String
    let tint: Color
    let fraction: Double?
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    Image(systemName: symbol)
                        .font(.system(size: 26, weight: .medium))
                        .foregroundStyle(tint.gradient)
                        .frame(width: 44, height: 44)
                        .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                    Spacer()
                    Image(systemName: "arrow.right.circle.fill")
                        .font(.title2)
                        .foregroundStyle(hovering ? tint : Color.secondary.opacity(0.35))
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                if let fraction {
                    CapacityBar(fraction: fraction, tint: tint)
                } else {
                    Color.clear.frame(height: 6)
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(hovering ? tint.opacity(0.6) : Color.primary.opacity(0.08), lineWidth: hovering ? 1.5 : 1)
            }
            .shadow(color: .black.opacity(hovering ? 0.14 : 0.06), radius: hovering ? 14 : 6, y: hovering ? 6 : 2)
            .scaleEffect(hovering ? 1.015 : 1)
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { inside in
            withAnimation(.spring(response: 0.28, dampingFraction: 0.75)) { hovering = inside }
        }
    }
}

struct CapacityBar: View {
    let fraction: Double
    let tint: Color

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule()
                    .fill(LinearGradient(colors: [tint.opacity(0.75), fraction > 0.9 ? .red : tint],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(6, geometry.size.width * min(1, fraction)))
            }
        }
        .frame(height: 6)
    }
}
