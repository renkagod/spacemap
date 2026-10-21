import AppKit
import QuartzCore
import SpaceMapCore

/// Shows a rendered treemap bitmap and handles hover, clicks, menus and zoom animations.
/// Layout and painting happen elsewhere (see `AppModel.requestRender`).
final class TreemapView: NSView {
    enum Transition {
        case none
        case fade
        /// Zooming into the item that occupied this rect in the previous layout.
        case zoomIn(CGRect)
        /// Zooming out of this node, which is a child in the new layout.
        case zoomOut(FileNode)
    }

    var onHover: ((TreemapItem?) -> Void)?
    var onClick: ((TreemapItem?) -> Void)?
    var onDoubleClick: ((TreemapItem) -> Void)?
    var onMenu: ((TreemapItem) -> NSMenu?)?
    var onBack: (() -> Void)?
    var onResize: (() -> Void)?

    private(set) var items: [TreemapItem] = []
    private(set) var hasImage = false
    private var image: NSImage?
    private var imageSize: CGSize = .zero
    private var hoverIndex: Int?
    private var selectedIndex: Int?
    private var magnification: CGFloat = 0

    var selectedNode: FileNode? {
        didSet {
            selectedIndex = index(of: selectedNode)
            needsDisplay = true
        }
    }

    private struct Animation {
        enum Kind { case zoomIn, zoomOut, fade }
        let kind: Kind
        let rect: CGRect
        let oldImage: NSImage?
        let start: CFTimeInterval
        let duration: CFTimeInterval

        var progress: CGFloat { CGFloat(min(1, max(0, (CACurrentMediaTime() - start) / duration))) }
        var eased: CGFloat { 1 - pow(1 - progress, 3) }
    }

    private var animation: Animation?
    private var animationTimer: Timer?
    private var trackingArea: NSTrackingArea?

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override var isOpaque: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    // MARK: - Content

    func show(items newItems: [TreemapItem], image cgImage: CGImage?, size: CGSize, transition: Transition) {
        let oldImage = image
        items = newItems
        imageSize = size
        image = cgImage.map { NSImage(cgImage: $0, size: size) }
        hasImage = image != nil
        selectedIndex = index(of: selectedNode)

        switch transition {
        case .none:
            break
        case .fade:
            if oldImage != nil { animate(.fade, rect: .zero, oldImage: oldImage, duration: 0.2) }
        case .zoomIn(let rect):
            animate(.zoomIn, rect: rect, oldImage: oldImage, duration: 0.34)
        case .zoomOut(let child):
            if let index = index(of: child) {
                animate(.zoomOut, rect: items[index].rect, oldImage: oldImage, duration: 0.34)
            } else if oldImage != nil {
                animate(.fade, rect: .zero, oldImage: oldImage, duration: 0.2)
            }
        }
        refreshHover()
        needsDisplay = true
    }

    func index(of node: FileNode?) -> Int? {
        guard let node else { return nil }
        return items.firstIndex { $0.node === node }
    }

    func rect(for node: FileNode) -> CGRect? {
        index(of: node).map { toView(items[$0].rect) }
    }

    func item(at point: CGPoint) -> TreemapItem? {
        itemIndex(at: point).map { items[$0] }
    }

    // MARK: - Geometry

    private var layoutScale: CGSize {
        CGSize(width: imageSize.width > 0 ? bounds.width / imageSize.width : 1,
               height: imageSize.height > 0 ? bounds.height / imageSize.height : 1)
    }

    private func toView(_ rect: CGRect) -> CGRect {
        let s = layoutScale
        return CGRect(x: rect.minX * s.width, y: rect.minY * s.height,
                      width: rect.width * s.width, height: rect.height * s.height)
    }

    private func itemIndex(at point: CGPoint) -> Int? {
        let s = layoutScale
        let p = CGPoint(x: point.x / s.width, y: point.y / s.height)
        // Items are in depth-first order and siblings never overlap, so the last hit is the deepest.
        var index = items.count - 1
        while index >= 0 {
            if items[index].rect.contains(p) { return index }
            index -= 1
        }
        return nil
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        onResize?()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        onResize?()
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        NSColor(cgColor: TreemapRenderer.background)?.setFill()
        dirtyRect.fill()
        let full = bounds

        if let animation {
            let p = animation.eased
            switch animation.kind {
            case .zoomIn:
                let target = lerp(animation.rect, full, p)
                animation.oldImage?.draw(in: mapped(full, from: animation.rect, to: target),
                                         from: .zero, operation: .sourceOver, fraction: 1,
                                         respectFlipped: true, hints: nil)
                image?.draw(in: target, from: .zero, operation: .sourceOver, fraction: min(1, p * 1.6),
                            respectFlipped: true, hints: nil)
            case .zoomOut:
                let target = lerp(full, animation.rect, p)
                image?.draw(in: mapped(full, from: animation.rect, to: target), from: .zero,
                            operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
                animation.oldImage?.draw(in: target, from: .zero, operation: .sourceOver,
                                         fraction: 1 - p, respectFlipped: true, hints: nil)
            case .fade:
                image?.draw(in: full, from: .zero, operation: .sourceOver, fraction: 1,
                            respectFlipped: true, hints: nil)
                animation.oldImage?.draw(in: full, from: .zero, operation: .sourceOver, fraction: 1 - p,
                                         respectFlipped: true, hints: nil)
            }
            return
        }

        image?.draw(in: full, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)

        if let index = selectedIndex, index < items.count {
            let rect = toView(items[index].rect).insetBy(dx: 1, dy: 1)
            let path = NSBezierPath(rect: rect)
            NSColor.controlAccentColor.withAlphaComponent(0.18).setFill()
            path.fill()
            NSColor.controlAccentColor.setStroke()
            path.lineWidth = 2
            path.stroke()
        }
        if let index = hoverIndex, index < items.count {
            let rect = toView(items[index].rect).insetBy(dx: 0.75, dy: 0.75)
            let path = NSBezierPath(rect: rect)
            NSColor.white.withAlphaComponent(0.13).setFill()
            path.fill()
            NSColor.white.withAlphaComponent(0.9).setStroke()
            path.lineWidth = 1.5
            path.stroke()
        }
    }

    private func lerp(_ a: CGRect, _ b: CGRect, _ t: CGFloat) -> CGRect {
        CGRect(x: a.minX + (b.minX - a.minX) * t, y: a.minY + (b.minY - a.minY) * t,
               width: a.width + (b.width - a.width) * t, height: a.height + (b.height - a.height) * t)
    }

    /// Where a full-size image goes so that its `from` region lands exactly on `to`.
    private func mapped(_ full: CGRect, from: CGRect, to: CGRect) -> CGRect {
        guard from.width > 0, from.height > 0 else { return to }
        let sx = to.width / from.width
        let sy = to.height / from.height
        return CGRect(x: to.minX - from.minX * sx, y: to.minY - from.minY * sy,
                      width: full.width * sx, height: full.height * sy)
    }

    private func animate(_ kind: Animation.Kind, rect: CGRect, oldImage: NSImage?, duration: CFTimeInterval) {
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let effectiveKind: Animation.Kind = reduceMotion ? .fade : kind
        animation = Animation(kind: effectiveKind, rect: rect, oldImage: oldImage,
                              start: CACurrentMediaTime(), duration: reduceMotion ? 0.15 : duration)
        animationTimer?.invalidate()
        let timer = Timer(timeInterval: 1.0 / 120.0, repeats: true) { [weak self] timer in
            guard let self, let animation = self.animation else {
                timer.invalidate()
                return
            }
            if animation.progress >= 1 {
                self.animation = nil
                timer.invalidate()
                self.refreshHover()
            }
            self.needsDisplay = true
        }
        RunLoop.main.add(timer, forMode: .common)
        animationTimer = timer
    }

    // MARK: - Mouse and keyboard

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: .zero,
                                  options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    private func setHover(_ index: Int?, force: Bool = false) {
        guard force || index != hoverIndex else { return }
        if let old = hoverIndex, old < items.count { setNeedsDisplay(toView(items[old].rect).insetBy(dx: -3, dy: -3)) }
        hoverIndex = index
        if let index { setNeedsDisplay(toView(items[index].rect).insetBy(dx: -3, dy: -3)) }
        onHover?(index.map { items[$0] })
    }

    private func refreshHover() {
        guard let window else { return }
        let point = convert(window.mouseLocationOutsideOfEventStream, from: nil)
        if bounds.contains(point) {
            setHover(itemIndex(at: point), force: true)
        } else if hoverIndex != nil {
            setHover(nil)
        }
    }

    override func mouseMoved(with event: NSEvent) {
        guard animation == nil else { return }
        setHover(itemIndex(at: convert(event.locationInWindow, from: nil)))
    }

    override func mouseExited(with event: NSEvent) {
        setHover(nil)
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let item = item(at: convert(event.locationInWindow, from: nil))
        if event.clickCount >= 2, let item {
            onDoubleClick?(item)
        } else if event.clickCount == 1 {
            onClick?(item)
        }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        guard let item = item(at: convert(event.locationInWindow, from: nil)) else { return nil }
        onClick?(item)
        return onMenu?(item)
    }

    override func otherMouseDown(with event: NSEvent) {
        // The "back" side button on most mice.
        if event.buttonNumber == 3 {
            onBack?()
        } else {
            super.otherMouseDown(with: event)
        }
    }

    override func swipe(with event: NSEvent) {
        if event.deltaX > 0 { onBack?() }
    }

    override func magnify(with event: NSEvent) {
        if event.phase == .began { magnification = 0 }
        magnification += event.magnification
        if magnification > 0.35 {
            magnification = -10
            if let item = item(at: convert(event.locationInWindow, from: nil)) { onDoubleClick?(item) }
        } else if magnification < -0.35 && magnification > -5 {
            magnification = -10
            onBack?()
        }
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53, 51: // Esc, Delete
            onBack?()
        case 36, 76: // Return, Enter
            if let index = selectedIndex, index < items.count { onDoubleClick?(items[index]) }
        default:
            super.keyDown(with: event)
        }
    }
}

/// NSMenuItem that runs a closure.
final class ActionMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(_ title: String, symbol: String? = nil, enabled: Bool = true, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: "")
        target = self
        isEnabled = enabled
        if let symbol { image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) }
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    @objc private func run() {
        handler()
    }
}
