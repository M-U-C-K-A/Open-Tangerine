import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import Vision

/// Lifts every foreground subject off a photo with Apple Vision and leaves the rest transparent. Runs on-device.
enum BackgroundRemoval {
    struct Options: Equatable {
        /// Edge feather as a fraction of the short side (0...1), so a batch looks the same at any resolution.
        var softness: Double = 0
        /// Trim the transparent margin around the subjects.
        var cropToSubject = false
    }

    /// Soft mask of all foreground instances at the image's own size: 1 keeps the pixel, 0 clears it.
    static func mask(for image: CGImage) throws -> CIImage {
        try ImageIOBridge.validateDimensions(width: image.width, height: image.height)
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try handler.perform([request])
        } catch {
            throw OpenTangerineError.toolFailed("Background removal", error.localizedDescription)
        }
        guard let observation = request.results?.first, !observation.allInstances.isEmpty else {
            throw OpenTangerineError.invalidInput("No subject found. Background removal needs a person, animal or object that stands out from the background.")
        }
        let buffer: CVPixelBuffer
        do {
            buffer = try observation.generateScaledMaskForImage(forInstances: observation.allInstances, from: handler)
        } catch {
            throw OpenTangerineError.toolFailed("Background removal", error.localizedDescription)
        }
        // The mask is coverage, not color: keep its values out of color management.
        return CIImage(cvPixelBuffer: buffer, options: [.colorSpace: NSNull()])
    }

    static func feathered(_ mask: CIImage, softness: Double) -> CIImage {
        let extent = mask.extent
        let radius = max(0, softness) * 0.02 * min(extent.width, extent.height)
        guard radius >= 0.5 else { return mask }
        let blur = CIFilter.gaussianBlur()
        blur.inputImage = mask.clampedToExtent()
        blur.radius = Float(radius)
        return (blur.outputImage ?? mask).cropped(to: extent)
    }

    static func composite(_ image: CIImage, mask: CIImage, softness: Double) -> CIImage {
        let blend = CIFilter.blendWithMask()
        blend.inputImage = image
        blend.backgroundImage = CIImage.empty()
        blend.maskImage = feathered(mask, softness: softness)
        return (blend.outputImage ?? image).cropped(to: image.extent)
    }

    static func remove(_ image: CGImage, options: Options = Options()) throws -> CGImage {
        try cutout(CIImage(cgImage: image), mask: mask(for: image), options: options)
    }

    /// Applies a mask from `mask(for:)`; the preview reuses one mask while the options change.
    static func cutout(_ image: CIImage, mask: CIImage, options: Options) throws -> CGImage {
        guard var result = ImageOps.render(composite(image, mask: mask, softness: options.softness)) else {
            throw OpenTangerineError.encodeFailed("the cut-out image")
        }
        if options.cropToSubject, let bounds = opaqueBounds(result), let cropped = result.cropping(to: bounds) {
            result = cropped
        }
        return result
    }

    static let suffix = "(no background)"

    /// One PNG per source, next to it; two sources sharing a base name in one folder never share an output.
    static func outputURLs(for files: [URL], directory: (URL) -> URL) -> [URL] {
        var reserved = Set<String>()
        return files.map { url in
            let folder = directory(url)
            let base = ConversionMatrix.strippedBaseName(url.lastPathComponent)
            var candidate = ConversionMatrix.uniqueURL(directory: folder, baseName: base, suffix: suffix, ext: "png")
            var counter = 2
            while reserved.contains(candidate.standardizedFileURL.path) {
                candidate = ConversionMatrix.uniqueURL(directory: folder, baseName: base, suffix: "\(suffix) \(counter)", ext: "png")
                counter += 1
            }
            reserved.insert(candidate.standardizedFileURL.path)
            return candidate
        }
    }

    /// Smallest rectangle (top-left origin, as `CGImage.cropping` expects) holding every pixel above `threshold` alpha.
    static func opaqueBounds(_ image: CGImage, threshold: UInt8 = 8) -> CGRect? {
        let width = image.width, height = image.height
        var alpha = [UInt8](repeating: 0, count: width * height)
        let drawn = alpha.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
                                          space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        var minX = width, minY = height, maxX = -1, maxY = -1
        for y in 0..<height {
            let row = y * width
            for x in 0..<width where alpha[row + x] > threshold {
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX >= minX, maxY >= minY else { return nil }
        return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }
}
