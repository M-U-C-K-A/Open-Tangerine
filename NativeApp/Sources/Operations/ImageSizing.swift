import CoreGraphics
import Foundation

/// Resize & compress in one pass: a new size (smaller, or bigger with rebuilt detail),
/// then a lighter file if asked.
struct ImageSizing: Equatable {
    enum Mode: String, CaseIterable, Identifiable {
        case original, longEdge, percent, exact
        var id: String { rawValue }
        var title: String {
            switch self {
            case .original: return "Same"
            case .longEdge: return "Long edge"
            case .percent: return "Percent"
            case .exact: return "Exact"
            }
        }
    }

    var mode: Mode = .longEdge
    var longEdge = 1920
    /// The long edge only shrinks pictures unless this is on.
    var enlargeToLongEdge = false
    var percent = 50
    var width = 0
    var height = 0
    /// Fit inside width × height; off, the picture is stretched to it.
    var keepAspect = true

    func target(for size: CGSize) -> CGSize {
        guard size.width > 0, size.height > 0 else { return size }
        let scale: CGFloat
        switch mode {
        case .original:
            return size
        case .longEdge:
            let fit = CGFloat(max(1, longEdge)) / max(size.width, size.height)
            scale = enlargeToLongEdge ? fit : min(1, fit)
        case .percent:
            scale = CGFloat(max(1, percent)) / 100
        case .exact:
            let w = CGFloat(max(1, width)), h = CGFloat(max(1, height))
            guard keepAspect else { return CGSize(width: w, height: h) }
            scale = min(w / size.width, h / size.height)
        }
        return CGSize(width: max(1, (size.width * scale).rounded()), height: max(1, (size.height * scale).rounded()))
    }

    func enlarges(_ size: CGSize) -> Bool {
        let target = target(for: size)
        return target.width > size.width || target.height > size.height
    }
}

enum ImageResizer {
    /// The format of the copy: the original's, or a lighter one when compressing
    /// (a PNG without transparency becomes a JPEG).
    static func outputFormat(for url: URL, compressing: Bool) -> FileFormat {
        compressing ? Compressor.outputFormat(for: url) : ImageToolSupport.outputFormat(for: url)
    }

    /// The suffix of the copy's name, from what was done.
    static func suffix(sizing: ImageSizing, size: CGSize, compressing: Bool) -> String {
        let target = sizing.target(for: size)
        if target == size { return compressing ? "compressed" : "copy" }
        if sizing.enlarges(size) { return "enlarged" }
        return "resized"
    }

    static func process(_ url: URL, sizing: ImageSizing, method: Upscale.Method, preset: CompressionPreset?, targetBytes: Int64?, quality: Double, to destination: URL, progress: @escaping (Double) -> Void) async throws {
        let image = try ImageIOBridge.load(url)
        progress(0.1)
        let target = sizing.target(for: CGSize(width: image.width, height: image.height))
        let sized = try await Upscale.resize(image, to: target, method: method)
        progress(0.6)
        if let preset {
            try await Compressor.writeLighter(sized, from: url, preset: preset, targetBytes: targetBytes, to: destination) { progress(0.6 + 0.4 * $0) }
        } else {
            try await ImageIOBridge.writeAnyFormat(sized, to: destination, format: outputFormat(for: url, compressing: false), quality: quality)
        }
        progress(1)
    }
}
