import AppKit
import CoreText

/// A text or logo mark drawn on images. Sizes are fractions of the picture's short
/// side, so a batch of different sizes looks the same and the preview matches.
enum Watermark {
    enum Position: String, CaseIterable, Identifiable {
        case topLeft, top, topRight, left, center, right, bottomLeft, bottom, bottomRight, tiled
        var id: String { rawValue }

        /// Where the mark sits in the free space, from the top-left (0, 0) to the bottom-right (1, 1).
        var anchor: CGPoint {
            switch self {
            case .topLeft: return CGPoint(x: 0, y: 0)
            case .top: return CGPoint(x: 0.5, y: 0)
            case .topRight: return CGPoint(x: 1, y: 0)
            case .left: return CGPoint(x: 0, y: 0.5)
            case .center, .tiled: return CGPoint(x: 0.5, y: 0.5)
            case .right: return CGPoint(x: 1, y: 0.5)
            case .bottomLeft: return CGPoint(x: 0, y: 1)
            case .bottom: return CGPoint(x: 0.5, y: 1)
            case .bottomRight: return CGPoint(x: 1, y: 1)
            }
        }

        var symbol: String {
            switch self {
            case .topLeft: return "arrow.up.left"
            case .top: return "arrow.up"
            case .topRight: return "arrow.up.right"
            case .left: return "arrow.left"
            case .center: return "circle.fill"
            case .right: return "arrow.right"
            case .bottomLeft: return "arrow.down.left"
            case .bottom: return "arrow.down"
            case .bottomRight: return "arrow.down.right"
            case .tiled: return "square.grid.3x3"
            }
        }
    }

    enum Ink: String, CaseIterable, Identifiable {
        case white, black
        var id: String { rawValue }
        var color: CGColor { self == .white ? CGColor(gray: 1, alpha: 1) : CGColor(gray: 0, alpha: 1) }
        var halo: CGColor { self == .white ? CGColor(gray: 0, alpha: 0.35) : CGColor(gray: 1, alpha: 0.35) }
    }

    struct Options: Equatable {
        var text = "© Open Tangerine"
        var position: Position = .bottomRight
        /// Text height, or a quarter of the logo's width, as a fraction of the short side.
        var size: Double = 0.05
        var opacity: Double = 0.6
        var ink: Ink = .white
        var margin: Double = 0.03
    }

    static func apply(_ image: CGImage, options: Options, logo: CGImage? = nil) throws -> CGImage {
        let width = image.width, height = image.height
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw OpenTangerineError.encodeFailed("the watermarked image")
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let short = Double(min(width, height))
        let mark: (size: CGSize, draw: (CGContext, CGPoint) -> Void)
        if let logo {
            let logoWidth = min(options.size * 4 * short, Double(width) * 0.8)
            let size = CGSize(width: logoWidth, height: logoWidth * Double(logo.height) / Double(max(logo.width, 1)))
            mark = (size, { context, origin in context.draw(logo, in: CGRect(origin: origin, size: size)) })
        } else {
            let text = options.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return image }
            let font = NSFont.systemFont(ofSize: max(4, options.size * short), weight: .semibold)
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: NSColor(cgColor: options.ink.color) ?? .white]))
            var ascent: CGFloat = 0, descent: CGFloat = 0, leading: CGFloat = 0
            let lineWidth = CTLineGetTypographicBounds(line, &ascent, &descent, &leading)
            let size = CGSize(width: lineWidth, height: ascent + descent)
            mark = (size, { context, origin in
                context.textPosition = CGPoint(x: origin.x, y: origin.y + descent)
                CTLineDraw(line, context)
            })
        }

        context.setAlpha(max(0, min(1, options.opacity)))
        if logo == nil {
            context.setShadow(offset: .zero, blur: max(1, options.size * short * 0.12), color: options.ink.halo)
        }
        let margin = options.margin * short
        if options.position == .tiled {
            // Repeated on a slant across the whole picture.
            context.saveGState()
            context.translateBy(x: Double(width) / 2, y: Double(height) / 2)
            context.rotate(by: .pi / 6)
            let stepX = mark.size.width + max(mark.size.height * 3, short * 0.08)
            let stepY = mark.size.height * 4
            let reach = hypot(Double(width), Double(height))
            var row = 0
            var y = -reach / 2
            while y < reach / 2 {
                var x = -reach / 2 + (row.isMultiple(of: 2) ? 0 : stepX / 2)
                while x < reach / 2 {
                    mark.draw(context, CGPoint(x: x, y: y))
                    x += stepX
                }
                y += stepY
                row += 1
            }
            context.restoreGState()
        } else {
            let anchor = options.position.anchor
            let x = margin + anchor.x * max(0, Double(width) - 2 * margin - mark.size.width)
            let top = margin + anchor.y * max(0, Double(height) - 2 * margin - mark.size.height)
            mark.draw(context, CGPoint(x: x, y: Double(height) - top - mark.size.height))
        }
        guard let output = context.makeImage() else { throw OpenTangerineError.encodeFailed("the watermarked image") }
        return output
    }
}
