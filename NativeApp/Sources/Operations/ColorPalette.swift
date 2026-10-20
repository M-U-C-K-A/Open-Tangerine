import AppKit
import CoreGraphics
import Foundation

/// A color as people copy it: HEX, RGB, HSL, or a SwiftUI literal.
struct PaletteColor: Hashable, Identifiable, Sendable {
    var red: Double
    var green: Double
    var blue: Double
    /// The part of the picture this color covers, from 0 to 1 (0 for picked colors).
    var share: Double = 0

    var id: String { hex }

    enum Notation: String, CaseIterable, Identifiable {
        case hex, rgb, hsl, swiftUI
        var id: String { rawValue }
        var title: String {
            switch self {
            case .hex: return "HEX"
            case .rgb: return "RGB"
            case .hsl: return "HSL"
            case .swiftUI: return "SwiftUI"
            }
        }
    }

    private var bytes: (Int, Int, Int) {
        (Int((red * 255).rounded()), Int((green * 255).rounded()), Int((blue * 255).rounded()))
    }

    var hex: String {
        let (r, g, b) = bytes
        return String(format: "#%02X%02X%02X", r, g, b)
    }

    var hsl: (h: Int, s: Int, l: Int) {
        let maximum = max(red, green, blue), minimum = min(red, green, blue)
        let lightness = (maximum + minimum) / 2
        let delta = maximum - minimum
        guard delta > 0.0001 else { return (0, 0, Int((lightness * 100).rounded())) }
        let saturation = delta / (1 - abs(2 * lightness - 1))
        var hue: Double
        switch maximum {
        case red: hue = ((green - blue) / delta).truncatingRemainder(dividingBy: 6)
        case green: hue = (blue - red) / delta + 2
        default: hue = (red - green) / delta + 4
        }
        hue *= 60
        if hue < 0 { hue += 360 }
        return (Int(hue.rounded()) % 360, Int((saturation * 100).rounded()), Int((lightness * 100).rounded()))
    }

    func text(_ notation: Notation) -> String {
        switch notation {
        case .hex: return hex
        case .rgb:
            let (r, g, b) = bytes
            return "rgb(\(r), \(g), \(b))"
        case .hsl:
            let (h, s, l) = hsl
            return "hsl(\(h), \(s)%, \(l)%)"
        case .swiftUI:
            return String(format: "Color(red: %.3f, green: %.3f, blue: %.3f)", red, green, blue)
        }
    }

    var nsColor: NSColor { NSColor(srgbRed: red, green: green, blue: blue, alpha: 1) }

    /// Black or white, whichever reads better on this color.
    var readsDark: Bool { 0.2126 * red + 0.7152 * green + 0.0722 * blue > 0.6 }

    init(red: Double, green: Double, blue: Double, share: Double = 0) {
        self.red = red; self.green = green; self.blue = blue; self.share = share
    }

    init?(_ color: NSColor) {
        guard let srgb = color.usingColorSpace(.sRGB) else { return nil }
        self.init(red: Double(srgb.redComponent), green: Double(srgb.greenComponent), blue: Double(srgb.blueComponent))
    }
}

/// The picture's pixels in sRGB, kept for the eyedropper and for finding the palette.
struct PixelGrid: Sendable {
    let width: Int
    let height: Int
    private let data: [UInt8]

    init?(_ image: CGImage, maxSide: Int = 1600) {
        let scale = min(1, Double(maxSide) / Double(max(image.width, image.height)))
        let width = max(1, Int(Double(image.width) * scale)), height = max(1, Int(Double(image.height) * scale))
        var data = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = data.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        self.width = width
        self.height = height
        self.data = data
    }

    /// The color at a point given as fractions of the picture, origin top-left; nil where it's see-through.
    func color(atX x: Double, y: Double) -> PaletteColor? {
        let px = min(width - 1, max(0, Int(x * Double(width)))), py = min(height - 1, max(0, Int(y * Double(height))))
        return color(px, py)
    }

    func color(_ px: Int, _ py: Int) -> PaletteColor? {
        let index = (py * width + px) * 4
        let alpha = Double(data[index + 3]) / 255
        guard alpha > 0.04 else { return nil }
        // Undo the premultiplication.
        return PaletteColor(red: Double(data[index]) / 255 / alpha, green: Double(data[index + 1]) / 255 / alpha, blue: Double(data[index + 2]) / 255 / alpha)
    }

    /// A square of pixels around a point, for the magnifier: `radius` pixels each way.
    func neighborhood(atX x: Double, y: Double, radius: Int) -> CGImage? {
        let cx = Int(x * Double(width)), cy = Int(y * Double(height))
        let side = radius * 2 + 1
        var patch = [UInt8](repeating: 0, count: side * side * 4)
        for dy in -radius...radius {
            for dx in -radius...radius {
                let px = cx + dx, py = cy + dy
                guard px >= 0, py >= 0, px < width, py < height else { continue }
                let from = (py * width + px) * 4, to = ((dy + radius) * side + dx + radius) * 4
                for channel in 0..<4 { patch[to + channel] = data[from + channel] }
            }
        }
        return patch.withUnsafeMutableBytes { buffer in
            CGContext(data: buffer.baseAddress, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)?.makeImage()
        }
    }

    /// The picture's main colors, the most present first: k-means on a sample of pixels,
    /// started the same way every time, so the same picture gives the same palette.
    func palette(count: Int) -> [PaletteColor] {
        let step = max(1, Int((Double(width * height) / 12_000).squareRoot()))
        var samples: [SIMD3<Double>] = []
        for py in stride(from: 0, to: height, by: step) {
            for px in stride(from: 0, to: width, by: step) {
                if let color = color(px, py) { samples.append(SIMD3(color.red, color.green, color.blue)) }
            }
        }
        guard !samples.isEmpty else { return [] }
        let k = min(count, samples.count)
        // k-means++ seeding with a fixed walk: the next centre is the sample farthest from those chosen.
        var centres = [samples[samples.count / 2]]
        var distances = samples.map { simdDistance($0, centres[0]) }
        while centres.count < k {
            guard let far = distances.indices.max(by: { distances[$0] < distances[$1] }), distances[far] > 0.0004 else { break }
            centres.append(samples[far])
            for index in samples.indices { distances[index] = min(distances[index], simdDistance(samples[index], samples[far])) }
        }
        var members = [Int](repeating: 0, count: samples.count)
        for _ in 0..<12 {
            var sums = [SIMD3<Double>](repeating: .zero, count: centres.count)
            var counts = [Int](repeating: 0, count: centres.count)
            for (index, sample) in samples.enumerated() {
                var best = 0, bestDistance = Double.infinity
                for (c, centre) in centres.enumerated() {
                    let d = simdDistance(sample, centre)
                    if d < bestDistance { bestDistance = d; best = c }
                }
                members[index] = best
                sums[best] += sample
                counts[best] += 1
            }
            var moved = 0.0
            for c in centres.indices where counts[c] > 0 {
                let next = sums[c] / Double(counts[c])
                moved = max(moved, simdDistance(next, centres[c]))
                centres[c] = next
            }
            if moved < 1e-6 { break }
        }
        var counts = [Int](repeating: 0, count: centres.count)
        for member in members { counts[member] += 1 }
        return centres.indices
            .filter { counts[$0] > 0 }
            .sorted { counts[$0] > counts[$1] }
            .map { PaletteColor(red: centres[$0].x, green: centres[$0].y, blue: centres[$0].z, share: Double(counts[$0]) / Double(samples.count)) }
    }

    private func simdDistance(_ a: SIMD3<Double>, _ b: SIMD3<Double>) -> Double {
        let d = a - b
        // Weighted RGB distance: closer to how different colors look than plain RGB.
        return 0.3 * d.x * d.x + 0.59 * d.y * d.y + 0.11 * d.z * d.z
    }
}

enum ColorPalette {
    /// A strip of swatches with their HEX codes, to keep or share.
    static func image(_ colors: [PaletteColor], notation: PaletteColor.Notation) -> CGImage? {
        guard !colors.isEmpty else { return nil }
        let swatch = 240, height = 300
        let width = swatch * colors.count
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        for (index, color) in colors.enumerated() {
            let rect = CGRect(x: index * swatch, y: 0, width: swatch, height: height)
            context.setFillColor(color.nsColor.cgColor)
            context.fill(rect)
            let label = NSAttributedString(string: color.text(notation), attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: notation == .hex ? 26 : 16, weight: .semibold),
                .foregroundColor: color.readsDark ? NSColor.black.withAlphaComponent(0.8) : NSColor.white.withAlphaComponent(0.92),
            ])
            label.draw(at: NSPoint(x: rect.minX + 18, y: 20))
        }
        NSGraphicsContext.restoreGraphicsState()
        return context.makeImage()
    }

    /// Every color as one line of text, in the notation chosen; CSS variables for HEX.
    static func text(_ colors: [PaletteColor], notation: PaletteColor.Notation, css: Bool = false) -> String {
        guard css else { return colors.map { $0.text(notation) }.joined(separator: "\n") }
        let lines = colors.enumerated().map { "  --color-\($0.offset + 1): \($0.element.text(notation == .swiftUI ? .hex : notation));" }
        return ":root {\n" + lines.joined(separator: "\n") + "\n}"
    }
}
