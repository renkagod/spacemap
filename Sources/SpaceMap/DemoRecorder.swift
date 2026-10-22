import AppKit
import QuartzCore
import SpaceMapCore

/// Records the window while it walks through the scanned folder, for the README animation made by
/// `--record <folder>`: zooms into the largest folder twice, back out, then highlights videos.
/// Frames go to numbered PNGs and `frames.txt` lists each one with how long it stays on screen;
/// `scripts/make_gif.py` turns them into a GIF.
final class DemoRecorder {
    private let model: AppModel
    private let directory: URL
    private let writer = DispatchQueue(label: "DemoRecorder.writer")
    private var timer: Timer?
    private var start: CFTimeInterval = 0
    private var frames: [(name: String, time: CFTimeInterval)] = []

    init(model: AppModel, directory: String) {
        self.model = model
        self.directory = URL(fileURLWithPath: directory, isDirectory: true)
    }

    func run() {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        start = CACurrentMediaTime()
        capture()
        let timer = Timer(timeInterval: 1.0 / 15, repeats: true) { [weak self] _ in self?.capture() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer

        let steps: [(at: Double, action: () -> Void)] = [
            (0.0, { self.model.simulateHoverOnLargest() }),
            (1.6, { self.zoomIntoLargest() }),
            (2.2, { self.model.simulateHoverOnLargest() }),
            (3.6, { self.zoomIntoLargest() }),
            (4.2, { self.model.simulateHoverOnLargest() }),
            (5.6, { self.model.goUp() }),
            (6.6, { self.model.goUp() }),
            (7.4, { self.model.focusCategory = .video }),
            (9.4, { self.model.focusCategory = nil }),
            (10.4, { self.finish() }),
        ]
        for step in steps {
            DispatchQueue.main.asyncAfter(deadline: .now() + step.at, execute: step.action)
        }
    }

    private func zoomIntoLargest() {
        let mode = model.sizeMode
        guard let current = model.current,
              let folder = current.children.filter(\.isContainer).max(by: { $0.size(mode) < $1.size(mode) })
        else { return }
        model.selectNode(nil)
        model.activate(folder)
    }

    private func capture() {
        guard let rep = LaunchOptions.windowImage() else { return }
        let name = String(format: "frame%04d.png", frames.count)
        frames.append((name, CACurrentMediaTime() - start))
        let url = directory.appendingPathComponent(name)
        writer.async {
            try? rep.representation(using: .png, properties: [:])?.write(to: url)
        }
    }

    private func finish() {
        timer?.invalidate()
        capture()
        var lines: [String] = []
        for (index, frame) in frames.enumerated() {
            let next = index + 1 < frames.count ? frames[index + 1].time : frame.time + 1.5
            lines.append("\(frame.name) \(Int(((next - frame.time) * 1000).rounded()))")
        }
        let list = directory.appendingPathComponent("frames.txt")
        writer.sync {
            try? (lines.joined(separator: "\n") + "\n").write(to: list, atomically: true, encoding: .utf8)
        }
        print("record: saved \(frames.count) frames to \(directory.path)")
        fflush(stdout)
        NSApp.terminate(nil)
    }
}
