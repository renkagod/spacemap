import AppKit
import SpaceMapCore
import SwiftUI

@main
struct SpaceMapApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel.shared

    var body: some Scene {
        Window("SpaceMap", id: "main") {
            ContentView()
                .environmentObject(model)
        }
        .defaultSize(width: 1280, height: 800)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Открыть папку…") { AppModel.shared.chooseFolder() }
                    .keyboardShortcut("o")
                Button("Новое сканирование") { AppModel.shared.closeScan() }
                    .keyboardShortcut("n")
            }
            CommandMenu("Навигация") {
                Button("Наверх") { AppModel.shared.goUp() }
                    .keyboardShortcut(.upArrow, modifiers: .command)
                Button("К началу") { AppModel.shared.goToRoot() }
                    .keyboardShortcut(.upArrow, modifiers: [.command, .shift])
                Divider()
                Button("Пересканировать папку") { AppModel.shared.rescanCurrent() }
                    .keyboardShortcut("r")
                Button("Остановить сканирование") { AppModel.shared.stopScan() }
                    .keyboardShortcut(".")
                Divider()
                Button("Сбросить подсветку типа") { AppModel.shared.focusCategory = nil }
                    .keyboardShortcut(.escape, modifiers: .option)
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.activate(ignoringOtherApps: true)
        LaunchOptions.apply(to: AppModel.shared)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    /// A folder dropped on the Dock icon.
    func application(_ application: NSApplication, open urls: [URL]) {
        guard let url = urls.first(where: { $0.hasDirectoryPath || isDirectory($0) }) else { return }
        AppModel.shared.startScan(url: url)
    }
}

func isDirectory(_ url: URL) -> Bool {
    var isDirectory: ObjCBool = false
    return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
}

/// Command line: `SpaceMap [folder]` scans the folder right away.
/// `--snapshot file.png --delay N` saves a picture of the window after N seconds and quits (used by CI);
/// `--hover` and `--focus <category>` set up the picture.
enum LaunchOptions {
    static func apply(to model: AppModel) {
        var scanPath: String?
        var snapshotPath: String?
        var delay: Double = 10
        var hover = false
        var focus: FileCategory?
        let arguments = Array(CommandLine.arguments.dropFirst())
        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            let value = index + 1 < arguments.count ? arguments[index + 1] : nil
            switch argument {
            case "--scan":
                scanPath = value
                index += 2
            case "--snapshot":
                snapshotPath = value
                index += 2
            case "--delay":
                delay = value.flatMap(Double.init) ?? delay
                index += 2
            case "--hover":
                hover = true
                index += 1
            case "--focus":
                focus = FileCategory.allCases.first { "\($0)" == value }
                index += 2
            default:
                if argument.hasPrefix("-psn") {
                    index += 1
                } else if argument.hasPrefix("-") {
                    index += 2 // NSUserDefaults-style "-Key value"
                } else {
                    if isDirectory(URL(fileURLWithPath: argument)) { scanPath = argument }
                    index += 1
                }
            }
        }

        if let scanPath {
            DispatchQueue.main.async {
                model.startScan(url: URL(fileURLWithPath: (scanPath as NSString).expandingTildeInPath))
            }
        }
        if let snapshotPath {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                if hover { model.simulateHoverOnLargest() }
                if let focus { model.focusCategory = focus }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    saveSnapshot(to: snapshotPath)
                    let stats = model.progress.lastResult ?? model.progress.stats
                    print("files=\(stats.files) dirs=\(stats.directories) allocated=\(stats.allocated) "
                        + "logical=\(stats.logical) inaccessible=\(stats.inaccessible) "
                        + "elapsed=\(String(format: "%.2f", stats.elapsed)) running=\(model.progress.running)")
                    fflush(stdout)
                    NSApp.terminate(nil)
                }
            }
        }
    }

    private static func saveSnapshot(to path: String) {
        guard let window = NSApp.windows.first(where: { $0.isVisible && $0.contentView != nil }),
              let view = window.contentView?.superview ?? window.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            print("snapshot: no window")
            return
        }
        view.cacheDisplay(in: view.bounds, to: rep)
        if let data = rep.representation(using: .png, properties: [:]) {
            try? data.write(to: URL(fileURLWithPath: path))
            print("snapshot: saved \(path)")
        }
    }
}
