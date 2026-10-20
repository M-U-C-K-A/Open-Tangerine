import CoreImage
import CoreImage.CIFilterBuiltins
import CoreMedia
import CoreVideo
import Foundation
import VideoToolbox

/// Makes pictures bigger, two ways: *Enlarge* resamples smoothly (Lanczos), *Enhance*
/// rebuilds detail with the Mac's machine-learning super resolution, on this Mac.
enum Upscale {
    enum Method: String, CaseIterable, Identifiable {
        case enlarge, enhance
        var id: String { rawValue }
        var title: String { self == .enlarge ? "Enlarge" : "Enhance details" }
    }

    /// The largest result, to keep memory reasonable: 16,384 pixels a side, 160 megapixels.
    static let maxSide = 16_384
    static let maxPixels = 160_000_000

    static var enhanceAvailable: Bool { VTLowLatencySuperResolutionScalerConfiguration.isSupported }

    static func checkSize(width: Int, height: Int, factor: Int) throws {
        let w = width * factor, h = height * factor
        guard w <= maxSide, h <= maxSide, w * h <= maxPixels else {
            throw OpenTangerineError.invalidInput("×\(factor) would make \(w) × \(h) pixels, more than this Mac should hold at once. Try ×2, or crop first.")
        }
    }

    static func upscale(_ image: CGImage, factor: Int, method: Method) async throws -> CGImage {
        try checkSize(width: image.width, height: image.height, factor: factor)
        switch method {
        case .enlarge:
            return try enlarge(image, factor: Double(factor))
        case .enhance:
            guard enhanceAvailable else { return try enlarge(image, factor: Double(factor), sharpen: true) }
            var result = image
            var reached = 1
            while reached < factor {
                result = try await superResolvePadded(result)
                reached *= 2
            }
            return result
        }
    }

    /// The picture at exactly `size`: shrunk smoothly, or grown, with *Enhance* rebuilding
    /// detail ×2 at a time until it is at least that big, then settling on the size.
    static func resize(_ image: CGImage, to size: CGSize, method: Method) async throws -> CGImage {
        let w = Int(size.width.rounded()), h = Int(size.height.rounded())
        guard w > 0, h > 0 else { throw OpenTangerineError.invalidInput("Choose a size of at least one pixel.") }
        guard w != image.width || h != image.height else { return image }
        guard w <= maxSide, h <= maxSide, w * h <= maxPixels else {
            throw OpenTangerineError.invalidInput("\(w) × \(h) pixels is more than this Mac should hold at once. Choose a smaller size, or crop first.")
        }
        guard w > image.width || h > image.height else { return ImageIOBridge.scaled(image, to: size) }
        var source = image
        if method == .enhance, enhanceAvailable {
            while source.width < w || source.height < h, source.width * 2 <= maxSide, source.height * 2 <= maxSide, source.width * source.height * 4 <= maxPixels {
                source = try await superResolvePadded(source)
            }
        }
        if source.width == w, source.height == h { return source }
        if source.width >= w, source.height >= h { return ImageIOBridge.scaled(source, to: size) }
        let sx = Double(w) / Double(source.width), sy = Double(h) / Double(source.height)
        return try enlarge(source, scaleX: sx, scaleY: sy, sharpen: method == .enhance && !enhanceAvailable)
    }

    static func enlarge(_ image: CGImage, factor: Double, sharpen: Bool = false) throws -> CGImage {
        try enlarge(image, scaleX: factor, scaleY: factor, sharpen: sharpen)
    }

    /// Smooth resampling, optionally with a light sharpen where enhancement is not available.
    static func enlarge(_ image: CGImage, scaleX: Double, scaleY: Double, sharpen: Bool = false) throws -> CGImage {
        let factor = max(scaleX, scaleY)
        let lanczos = CIFilter.lanczosScaleTransform()
        lanczos.inputImage = CIImage(cgImage: image)
        lanczos.scale = Float(scaleY)
        lanczos.aspectRatio = Float(scaleX / scaleY)
        guard var output = lanczos.outputImage else { throw OpenTangerineError.encodeFailed("the enlarged image") }
        if sharpen {
            let filter = CIFilter.sharpenLuminance()
            filter.inputImage = output
            filter.sharpness = 0.5
            filter.radius = Float(1.2 * factor)
            output = filter.outputImage ?? output
        }
        let extent = CGRect(x: 0, y: 0, width: (Double(image.width) * scaleX).rounded(), height: (Double(image.height) * scaleY).rounded())
        guard let rendered = ImageOps.render(output.cropped(to: extent), extent: extent) else { throw OpenTangerineError.encodeFailed("the enlarged image") }
        return rendered
    }

    static let context = CIContext(options: [.cacheIntermediates: false])

    /// Super resolution rings at the picture's own border: give it a few repeated edge
    /// pixels to work on, then trim them off.
    static func superResolvePadded(_ image: CGImage, pad: Int = 8) async throws -> CGImage {
        let extent = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        let grown = extent.insetBy(dx: CGFloat(-pad), dy: CGFloat(-pad))
        let padded = CIImage(cgImage: image).clampedToExtent().cropped(to: grown).transformed(by: CGAffineTransform(translationX: CGFloat(pad), y: CGFloat(pad)))
        let paddedExtent = CGRect(x: 0, y: 0, width: grown.width, height: grown.height)
        guard let source = ImageOps.render(padded, extent: paddedExtent) else { throw OpenTangerineError.encodeFailed("the enhanced image") }
        var result = try await superResolve(source)
        if let trimmed = result.cropping(to: CGRect(x: pad * 2, y: pad * 2, width: image.width * 2, height: image.height * 2)) { result = trimmed }
        if ![.none, .noneSkipLast, .noneSkipFirst].contains(image.alphaInfo) {
            // Padding repeats edge alpha too; take transparency from the unpadded picture.
            let alpha = try enlarge(image, factor: 2)
            let blend = CIFilter.blendWithAlphaMask()
            blend.inputImage = CIImage(cgImage: result)
            blend.backgroundImage = CIImage.empty()
            blend.maskImage = CIImage(cgImage: alpha)
            let outExtent = CGRect(x: 0, y: 0, width: image.width * 2, height: image.height * 2)
            if let masked = blend.outputImage.flatMap({ ImageOps.render($0.cropped(to: outExtent), extent: outExtent) }) { result = masked }
        }
        return result
    }

    /// Twice the size with VideoToolbox's low-latency super resolution, which takes at most
    /// 960 pixels a side: the picture goes through in overlapping tiles, stitched without seams.
    static func superResolve(_ image: CGImage) async throws -> CGImage {
        guard let resolver = try SuperResolver(width: image.width, height: image.height) else {
            return try enlarge(image, factor: 2, sharpen: true)
        }
        var result = try await resolver.process(CIImage(cgImage: image))
        if ![.none, .noneSkipLast, .noneSkipFirst].contains(image.alphaInfo) {
            // Super resolution works on colour only: carry transparency over, smoothly enlarged.
            let alpha = try enlarge(image, factor: 2)
            let blend = CIFilter.blendWithAlphaMask()
            blend.inputImage = CIImage(cgImage: result)
            blend.backgroundImage = CIImage.empty()
            blend.maskImage = CIImage(cgImage: alpha)
            let extent = CGRect(x: 0, y: 0, width: image.width * 2, height: image.height * 2)
            if let masked = blend.outputImage.flatMap({ ImageOps.render($0.cropped(to: extent), extent: extent) }) { result = masked }
        }
        return result
    }

    /// Tile origins along one side: steps of `tile - overlap`, the last one flush with the end.
    static func origins(length: Int, tile: Int, overlap: Int) -> [Int] {
        guard length > tile else { return [0] }
        var result: [Int] = []
        var position = 0
        while position + tile < length {
            result.append(position)
            position += tile - overlap
        }
        result.append(length - tile)
        return result
    }

    static func pixelBuffer(attributes: [String: Any], width: Int, height: Int) throws -> CVPixelBuffer {
        var attributes = attributes
        attributes[kCVPixelBufferWidthKey as String] = width
        attributes[kCVPixelBufferHeightKey as String] = height
        let format = (attributes[kCVPixelBufferPixelFormatTypeKey as String] as? NSNumber)?.uint32Value
            ?? (attributes[kCVPixelBufferPixelFormatTypeKey as String] as? [NSNumber])?.first?.uint32Value
            ?? kCVPixelFormatType_32BGRA
        var buffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(kCFAllocatorDefault, width, height, format, attributes as CFDictionary, &buffer)
        guard status == kCVReturnSuccess, let buffer else { throw OpenTangerineError.encodeFailed("a \(width) × \(height) frame buffer") }
        return buffer
    }
}

/// A super resolution session kept open for pictures of one size, so video frames go through
/// one after another without starting VideoToolbox again for each.
final class SuperResolver {
    let width: Int
    let height: Int
    private let tileW: Int
    private let tileH: Int
    private let configuration: VTLowLatencySuperResolutionScalerConfiguration
    private let processor = VTFrameProcessor()
    private static let overlap = 24

    /// Nil when this Mac can't double pictures of this size.
    init?(width: Int, height: Int) throws {
        let maxTile = Int(VTLowLatencySuperResolutionScalerConfiguration.maximumDimensions?.width ?? 960)
        let tileW = min(width, maxTile), tileH = min(height, maxTile)
        guard Upscale.enhanceAvailable, VTLowLatencySuperResolutionScalerConfiguration.supportedScaleFactors(frameWidth: tileW, frameHeight: tileH).contains(2) else { return nil }
        self.width = width
        self.height = height
        self.tileW = tileW
        self.tileH = tileH
        configuration = VTLowLatencySuperResolutionScalerConfiguration(frameWidth: tileW, frameHeight: tileH, scaleFactor: 2)
        do {
            try processor.startSession(configuration: configuration)
        } catch {
            throw OpenTangerineError.toolFailed("Super resolution", error.localizedDescription)
        }
    }

    deinit { processor.endSession() }

    /// `source` is `width` × `height` with its origin at zero; the result is twice that, opaque.
    func process(_ source: CIImage) async throws -> CGImage {
        guard let canvas = CGContext(data: nil, width: width * 2, height: height * 2, bitsPerComponent: 8, bytesPerRow: 0,
                                     space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw OpenTangerineError.encodeFailed("the enhanced image")
        }
        let overlap = Self.overlap
        for y in Upscale.origins(length: height, tile: tileH, overlap: overlap) {
            for x in Upscale.origins(length: width, tile: tileW, overlap: overlap) {
                try Task.checkCancellation()
                let tile = CGRect(x: x, y: y, width: tileW, height: tileH)
                let input = try Upscale.pixelBuffer(attributes: configuration.sourcePixelBufferAttributes, width: tileW, height: tileH)
                let output = try Upscale.pixelBuffer(attributes: configuration.destinationPixelBufferAttributes, width: tileW * 2, height: tileH * 2)
                Upscale.context.render(source.cropped(to: tile).transformed(by: CGAffineTransform(translationX: -tile.minX, y: -tile.minY)), to: input)
                guard let sourceFrame = VTFrameProcessorFrame(buffer: input, presentationTimeStamp: .zero),
                      let destinationFrame = VTFrameProcessorFrame(buffer: output, presentationTimeStamp: .zero) else {
                    throw OpenTangerineError.encodeFailed("a super resolution frame")
                }
                do {
                    try await processor.process(parameters: VTLowLatencySuperResolutionScalerParameters(sourceFrame: sourceFrame, destinationFrame: destinationFrame))
                } catch {
                    throw OpenTangerineError.toolFailed("Super resolution", error.localizedDescription)
                }
                // Keep each tile's middle; edges that meet a neighbour lose half the overlap.
                let keepLeft = x == 0 ? 0 : overlap / 2, keepBottom = y == 0 ? 0 : overlap / 2
                let keepRight = x + tileW >= width ? 0 : overlap / 2, keepTop = y + tileH >= height ? 0 : overlap / 2
                let inner = CGRect(x: keepLeft * 2, y: keepBottom * 2, width: (tileW - keepLeft - keepRight) * 2, height: (tileH - keepBottom - keepTop) * 2)
                guard let piece = Upscale.context.createCGImage(CIImage(cvPixelBuffer: output), from: inner) else {
                    throw OpenTangerineError.encodeFailed("an enhanced tile")
                }
                canvas.draw(piece, in: CGRect(x: (x + keepLeft) * 2, y: (y + keepBottom) * 2, width: Int(inner.width), height: Int(inner.height)))
            }
        }
        guard let result = canvas.makeImage() else { throw OpenTangerineError.encodeFailed("the enhanced image") }
        return result
    }
}
