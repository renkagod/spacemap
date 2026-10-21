import AppKit
import CoreServices
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
    func applicationWillFinishLaunching(_ notification: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = false
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.activate(ignoringOtherApps: true)
        LaunchOptions.apply(to: AppModel.shared)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    /// A folder dropped on the Dock icon or opened with SpaceMap from Finder.
    func application(_ application: NSApplication, open urls: [URL]) {
        guard let url = urls.first(where: isDirectory) else { return }
        print("open: \(url.path)")
        AppModel.shared.startScan(url: url)
        ensureWindow()
    }

    /// When the app is launched to open a folder, SwiftUI skips the initial window. Ask it to
    /// reopen one, as a click on the Dock icon would.
    private func ensureWindow(attempt: Int = 0) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            guard !NSApp.windows.contains(where: { $0.isVisible && $0.frame.width > 300 }) else { return }
            switch attempt {
            case 0:
                _ = NSApp.delegate?.applicationShouldHandleReopen?(NSApp, hasVisibleWindows: false)
            case 1:
                let target = NSAppleEventDescriptor(processIdentifier: ProcessInfo.processInfo.processIdentifier)
                let event = NSAppleEventDescriptor(eventClass: AEEventClass(kCoreEventClass),
                                                   eventID: AEEventID(kAEReopenApplication),
                                                   targetDescriptor: target,
                                                   returnID: AEReturnID(kAutoGenerateReturnID),
                                                   transactionID: AETransactionID(kAnyTransactionID))
                _ = try? event.sendEvent(options: [.noReply], timeout: 1)
            default:
                print("ensureWindow: no window after \(attempt) attempts")
                return
            }
            print("ensureWindow: attempt \(attempt)")
            self.ensureWindow(attempt: attempt + 1)
        }
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
enum LaunchOptions {
    static func apply(to model: AppModel) {
        var scanPath: String?
        var snapshotPath: String?
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
                    // AppKit opens bare paths itself, through application(_:open:).
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
    }

    private static func saveSnapshot(to path: String) {
        let candidates = NSApp.windows.filter { $0.contentView != nil && $0.frame.width > 300 }
        let summary = NSApp.windows.map { "\($0.className) visible=\($0.isVisible) \(Int($0.frame.width))x\(Int($0.frame.height))" }
        print("snapshot: windows " + summary.joined(separator: ", "))
        guard let window = candidates.first(where: { $0.isVisible }) ?? candidates.first,
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
