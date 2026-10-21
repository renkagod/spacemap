import AppKit
import CoreText
import SpaceMapCore

/// Paints a laid-out treemap into a bitmap. Runs off the main thread.
enum TreemapRenderer {
    static let background = CGColor(srgbRed: 0.071, green: 0.078, blue: 0.098, alpha: 1)

    static func render(items: [TreemapItem], size: CGSize, scale: CGFloat, focus: FileCategory?) -> CGImage? {
        let width = Int((size.width * scale).rounded())
        let height = Int((size.height * scale).rounded())
        guard width > 0, height > 0,
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                                          | CGBitmapInfo.byteOrder32Little.rawValue)
        else { return nil }

        context.scaleBy(x: scale, y: scale)
        // Top-left origin, like the layout and the flipped view.
        context.translateBy(x: 0, y: size.height)
        context.scaleBy(x: 1, y: -1)
        context.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        context.setFillColor(background)
        context.fill(CGRect(origin: .zero, size: size))

        var painter = Painter(context: context, scale: scale, focus: focus)
        for item in items {
            painter.draw(item)
        }
        return context.makeImage()
    }

    private struct Painter {
        let context: CGContext
        let scale: CGFloat
        let focus: FileCategory?
        var gradients: [Int: CGGradient] = [:]

        let headerFont = NSFont.systemFont(ofSize: 11, weight: .semibold) as CTFont
        let headerDetailFont = NSFont.monospacedDigitSystemFont(ofSize: 10.5, weight: .regular) as CTFont
        let labelFont = NSFont.systemFont(ofSize: 11, weight: .medium) as CTFont
        let detailFont = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular) as CTFont

        init(context: CGContext, scale: CGFloat, focus: FileCategory?) {
            self.context = context
            self.scale = scale
            self.focus = focus
        }

        mutating func draw(_ item: TreemapItem) {
            switch item.kind {
            case .directory: drawDirectory(item)
            case .leaf: drawLeaf(item)
            case .aggregate: drawAggregate(item)
            }
        }

        private func snap(_ rect: CGRect) -> CGRect {
            let minX = (rect.minX * scale).rounded() / scale
            let minY = (rect.minY * scale).rounded() / scale
            let maxX = (rect.maxX * scale).rounded() / scale
            let maxY = (rect.maxY * scale).rounded() / scale
            return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        }

        private func dimmed(_ category: FileCategory) -> Bool {
            guard let focus else { return false }
            return category != focus
        }

        private func color(_ category: FileCategory, dim: Bool, shift: CGFloat = 0) -> CGColor {
            var (r, g, b) = category.rgb
            if dim {
                let gray = (r + g + b) / 3
                r = gray * 0.28 + 0.1
                g = gray * 0.28 + 0.105
                b = gray * 0.28 + 0.12
            }
            return CGColor(srgbRed: adjust(r, shift), green: adjust(g, shift), blue: adjust(b, shift), alpha: 1)
        }

        private func adjust(_ component: CGFloat, _ shift: CGFloat) -> CGFloat {
            shift >= 0 ? component + (1 - component) * shift : component * (1 + shift)
        }

        private mutating func gradient(_ category: FileCategory, dim: Bool) -> CGGradient? {
            let key = Int(category.rawValue) * 2 + (dim ? 1 : 0)
            if let cached = gradients[key] { return cached }
            let colors = [
                color(category, dim: dim, shift: 0.24),
                color(category, dim: dim, shift: 0),
                color(category, dim: dim, shift: -0.28),
            ] as CFArray
            let made = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors,
                                  locations: [0, 0.45, 1])
            gradients[key] = made
            return made
        }

        private func drawDirectory(_ item: TreemapItem) {
            let rect = snap(item.rect)
            guard rect.width >= 1, rect.height >= 1 else { return }
            let depth = CGFloat(min(item.depth, 7))
            let shade = 0.15 + depth * 0.022
            context.setFillColor(CGColor(srgbRed: shade, green: shade + 0.012, blue: shade + 0.04, alpha: 1))
            context.fill(rect)
            context.setStrokeColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.55))
            context.setLineWidth(1)
            context.stroke(rect.insetBy(dx: 0.5, dy: 0.5))

            guard item.headerHeight >= 12, rect.width >= 30, let node = item.node else { return }
            let textColor = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.92)
            let detailColor = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.5)
            let baseline = rect.minY + item.headerHeight - 4.5
            let available = rect.width - 10
            let sizeLine = makeLine(Format.bytes(item.size), font: headerDetailFont, color: detailColor)
            let sizeWidth = CGFloat(CTLineGetTypographicBounds(sizeLine, nil, nil, nil))
            if available > sizeWidth + 40 {
                if let name = fitted(node.title, width: available - sizeWidth - 8, font: headerFont, color: textColor) {
                    drawLine(name, x: rect.minX + 5, baseline: baseline)
                }
                drawLine(sizeLine, x: rect.maxX - 5 - sizeWidth, baseline: baseline)
            } else if let name = fitted(node.title, width: available, font: headerFont, color: textColor) {
                drawLine(name, x: rect.minX + 5, baseline: baseline)
            }
        }

        private mutating func drawLeaf(_ item: TreemapItem) {
            let rect = snap(item.rect).insetBy(dx: 0.5, dy: 0.5)
            guard rect.width > 0.2, rect.height > 0.2 else { return }
            let dim = dimmed(item.category)
            if rect.width * rect.height >= 90, let gradient = gradient(item.category, dim: dim) {
                context.saveGState()
                context.clip(to: rect)
                context.drawLinearGradient(gradient, start: CGPoint(x: rect.minX, y: rect.minY),
                                           end: CGPoint(x: rect.minX, y: rect.maxY),
                                           options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
                context.restoreGState()
                context.setStrokeColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: dim ? 0.04 : 0.16))
                context.setLineWidth(1)
                context.stroke(rect.insetBy(dx: 0.5, dy: 0.5))
            } else {
                context.setFillColor(color(item.category, dim: dim))
                context.fill(rect)
            }

            guard rect.width >= 44, rect.height >= 20, let node = item.node else { return }
            let (r, g, b) = item.category.rgb
            let bright = !dim && (0.299 * r + 0.587 * g + 0.114 * b) > 0.6
            let main = bright ? CGColor(srgbRed: 0.06, green: 0.06, blue: 0.08, alpha: 0.9)
                              : CGColor(srgbRed: 1, green: 1, blue: 1, alpha: dim ? 0.45 : 0.95)
            let detail = bright ? CGColor(srgbRed: 0.06, green: 0.06, blue: 0.08, alpha: 0.6)
                                : CGColor(srgbRed: 1, green: 1, blue: 1, alpha: dim ? 0.3 : 0.7)
            drawCenteredLabel(title: node.title, detail: Format.bytes(item.size), in: rect,
                              titleColor: main, detailColor: detail, shadow: !bright && !dim)
        }

        private func drawAggregate(_ item: TreemapItem) {
            let rect = snap(item.rect).insetBy(dx: 0.5, dy: 0.5)
            guard rect.width > 0.2, rect.height > 0.2 else { return }
            context.setFillColor(CGColor(srgbRed: 0.22, green: 0.235, blue: 0.27, alpha: 1))
            context.fill(rect)
            if rect.width * rect.height >= 200 {
                context.saveGState()
                context.clip(to: rect)
                context.setStrokeColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.05))
                context.setLineWidth(1)
                var x = rect.minX - rect.height
                while x < rect.maxX {
                    context.move(to: CGPoint(x: x, y: rect.maxY))
                    context.addLine(to: CGPoint(x: x + rect.height, y: rect.minY))
                    x += 6
                }
                context.strokePath()
                context.restoreGState()
            }
            guard rect.width >= 52, rect.height >= 20 else { return }
            drawCenteredLabel(title: "ещё \(Format.count(Int64(item.aggregateCount)))",
                              detail: Format.bytes(item.size), in: rect,
                              titleColor: CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.6),
                              detailColor: CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.4), shadow: false)
        }

        private func drawCenteredLabel(title: String, detail: String, in rect: CGRect,
                                       titleColor: CGColor, detailColor: CGColor, shadow: Bool) {
            let width = rect.width - 8
            guard let titleLine = fitted(title, width: width, font: labelFont, color: titleColor) else { return }
            let showDetail = rect.height >= 34
            let detailLine = showDetail ? fitted(detail, width: width, font: detailFont, color: detailColor) : nil
            let blockHeight: CGFloat = detailLine == nil ? 13 : 26
            let top = rect.midY - blockHeight / 2

            context.saveGState()
            if shadow {
                context.setShadow(offset: CGSize(width: 0, height: -1), blur: 2,
                                  color: CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.45))
            }
            let titleWidth = CGFloat(CTLineGetTypographicBounds(titleLine, nil, nil, nil))
            drawLine(titleLine, x: rect.midX - titleWidth / 2, baseline: top + 10.5)
            if let detailLine {
                let detailWidth = CGFloat(CTLineGetTypographicBounds(detailLine, nil, nil, nil))
                drawLine(detailLine, x: rect.midX - detailWidth / 2, baseline: top + 23.5)
            }
            context.restoreGState()
        }

        private func makeLine(_ text: String, font: CTFont, color: CGColor) -> CTLine {
            let attributes: [NSAttributedString.Key: Any] = [
                NSAttributedString.Key(kCTFontAttributeName as String): font,
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): color,
            ]
            return CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
        }

        private func fitted(_ text: String, width: CGFloat, font: CTFont, color: CGColor) -> CTLine? {
            guard width > 12 else { return nil }
            let line = makeLine(text, font: font, color: color)
            if CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil)) <= width { return line }
            let token = makeLine("…", font: font, color: color)
            return CTLineCreateTruncatedLine(line, Double(width), .end, token)
        }

        private func drawLine(_ line: CTLine, x: CGFloat, baseline: CGFloat) {
            context.textPosition = CGPoint(x: x, y: baseline)
            CTLineDraw(line, context)
        }
    }
}
