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
                // Rebuilds every view, so all text switches to the new language at once.
                .id(model.language)
        }
        .defaultSize(width: 1280, height: 800)
        .commands {
            CommandGroup(replacing: .appSettings) {
                LanguageMenu(model: model)
            }
            CommandGroup(replacing: .newItem) {
                Button(tr("menu.openFolder")) { AppModel.shared.chooseFolder() }
                    .keyboardShortcut("o")
                Button(tr("menu.newScan")) { AppModel.shared.closeScan() }
                    .keyboardShortcut("n")
            }
            CommandMenu(tr("menu.navigation")) {
                Button(tr("menu.up")) { AppModel.shared.goUp() }
                    .keyboardShortcut(.upArrow, modifiers: .command)
                Button(tr("menu.top")) { AppModel.shared.goToRoot() }
                    .keyboardShortcut(.upArrow, modifiers: [.command, .shift])
                Divider()
                Button(tr("menu.rescanFolder")) { AppModel.shared.rescanCurrent() }
                    .keyboardShortcut("r")
                Button(tr("menu.stopScan")) { AppModel.shared.stopScan() }
                    .keyboardShortcut(".")
                Divider()
                Button(tr("menu.clearHighlight")) { AppModel.shared.focusCategory = nil }
                    .keyboardShortcut(.escape, modifiers: .option)
            }
        }
    }
}

/// SpaceMap → Language: follow the system, one of the installed translations, or add a new one.
private struct LanguageMenu: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Menu(tr("menu.language")) {
            Picker(tr("menu.language"), selection: $model.languageChoice) {
                Text(tr("menu.language.system")).tag("")
                ForEach(model.languages) { language in
                    Text(language.name).tag(language.code)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
            Divider()
            Button(tr("menu.language.openFolder")) { model.openTranslationsFolder() }
            Button(tr("menu.language.help")) { model.openTranslationGuide() }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = false
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.activate(ignoringOtherApps: true)
        LaunchOptions.apply(to: AppModel.shared)
    }

    /// Picks up translations dropped into the translations folder while SpaceMap was in the background.
    func applicationDidBecomeActive(_ notification: Notification) {
        AppModel.shared.refreshLanguages()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    /// A folder dropped on the Dock icon or opened with SpaceMap from Finder.
    func application(_ application: NSApplication, open urls: [URL]) {
        guard let url = urls.first(where: isDirectory) else { return }
        AppModel.shared.startScan(url: url)
    }
}

func isDirectory(_ url: URL) -> Bool {
    var isDirectory: ObjCBool = false
    return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
}

/// Command line: `SpaceMap --scan <folder>` scans the folder right away. AppKit reads arguments as
/// `-key value` pairs, so flags without a value go last.
/// `--snapshot file.png --delay N` saves a picture of the window after N seconds and quits (used by CI);
/// `--hover`, `--focus <category>`, `--tab <contents|largest|types>` and `--logical` set up the picture.
/// `--record <folder> --delay N` records the frames of a short walk through the map instead (see `DemoRecorder`).
/// `-Language <code>` (a user default) picks the interface language for one launch.
enum LaunchOptions {
    static func apply(to model: AppModel) {
        var scanPath: String?
        var snapshotPath: String?
        var recordPath: String?
        var delay: Double = 10
        var hover = false
        var focus: FileCategory?
        var logical = false
        var tab: SidebarTab?
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
            case "--record":
                recordPath = value
                index += 2
            case "--delay":
                delay = value.flatMap(Double.init) ?? delay
                index += 2
            case "--hover":
                hover = true
                index += 1
            case "--logical":
                logical = true
                index += 1
            case "--tab":
                tab = value.flatMap(SidebarTab.init(rawValue:))
                index += 2
            case "--focus":
                focus = FileCategory.allCases.first { "\($0)" == value }
                index += 2
            default:
                if argument.hasPrefix("-psn") {
                    index += 1
                } else if argument.hasPrefix("-") {
                    index += 2 // NSUserDefaults-style "-Key value"
                } else {
                    index += 1
                }
            }
        }

        // Applied after launch finishes, once the window exists.
        DispatchQueue.main.async {
            if logical { model.sizeMode = .logical }
            if let tab { model.sidebarTab = tab }
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
        if let recordPath {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                DemoRecorder(model: model, directory: recordPath).run()
            }
        }
    }

    /// The main window as it looks right now, title bar included.
    static func windowImage() -> NSBitmapImageRep? {
        let candidates = NSApp.windows.filter { $0.contentView != nil && $0.frame.width > 300 }
        guard let window = candidates.first(where: { $0.isVisible }) ?? candidates.first,
              let view = window.contentView?.superview ?? window.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
        view.cacheDisplay(in: view.bounds, to: rep)
        return rep
    }

    private static func saveSnapshot(to path: String) {
        let summary = NSApp.windows.map { "\($0.className) visible=\($0.isVisible) \(Int($0.frame.width))x\(Int($0.frame.height))" }
        print("snapshot: windows " + summary.joined(separator: ", "))
        guard let rep = windowImage() else {
            print("snapshot: no window")
            return
        }
        if let data = rep.representation(using: .png, properties: [:]) {
            try? data.write(to: URL(fileURLWithPath: path))
            print("snapshot: saved \(path)")
        }
    }
}
