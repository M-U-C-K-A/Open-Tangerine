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

    static let noSubjectMessage = "No subject found. Background removal needs a person, animal or object that stands out from the background."

    /// Soft mask of all foreground instances at the image's own size: 1 keeps the pixel, 0 clears it.
    /// With `wholeIfNoSubject`, a picture without a clear subject is kept whole, for the wand and
    /// brush to clear by hand, instead of failing.
    static func mask(for image: CGImage, wholeIfNoSubject: Bool = false) throws -> CIImage {
        if let found = try foregroundMask(for: image) { return found }
        guard wholeIfNoSubject else { throw OpenTangerineError.invalidInput(noSubjectMessage) }
        return wholeMask(width: image.width, height: image.height)
    }

    /// A mask that keeps every pixel.
    static func wholeMask(width: Int, height: Int) -> CIImage {
        CIImage(color: CIColor(red: 1, green: 1, blue: 1)).cropped(to: CGRect(x: 0, y: 0, width: width, height: height))
    }

    /// Nil when Vision sees nothing that stands out.
    static func foregroundMask(for image: CGImage) throws -> CIImage? {
        try ImageIOBridge.validateDimensions(width: image.width, height: image.height)
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try handler.perform([request])
        } catch {
            throw OpenTangerineError.toolFailed("Background removal", error.localizedDescription)
        }
        guard let observation = request.results?.first, !observation.allInstances.isEmpty else { return nil }
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

    static func remove(_ image: CGImage, options: Options = Options(), refinements: [Refinement] = [], wholeIfNoSubject: Bool = false) throws -> CGImage {
        var mask = try mask(for: image, wholeIfNoSubject: wholeIfNoSubject)
        if !refinements.isEmpty, let pixels = Pixels(image), var buffer = MaskBuffer(mask, width: image.width, height: image.height) {
            refine(&buffer, with: refinements, pixels: pixels)
            mask = buffer.ciImage()
        }
        return try cutout(CIImage(cgImage: image), mask: mask, options: options)
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

    // MARK: - Refining by hand: the magic wand and the brush

    /// A correction painted over the Vision mask, either clearing more (`keep == false`)
    /// or bringing pixels back. Points are normalised to the image (0...1, top-left
    /// origin) so edits made on the preview replay exactly on the full-size image.
    enum Refinement: Equatable {
        /// Every pixel connected to `point` whose color is within `tolerance` (0...1) of it.
        case wand(point: CGPoint, tolerance: Double, keep: Bool)
        /// A round brush along `path`; `radius` is a fraction of the image's short side.
        case brush(path: [CGPoint], radius: Double, keep: Bool)
    }

    /// An image's RGBA bytes, top row first.
    struct Pixels {
        let width: Int
        let height: Int
        let rgba: [UInt8]

        init?(_ image: CGImage) {
            let width = image.width, height = image.height
            var bytes = [UInt8](repeating: 0, count: width * height * 4)
            let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
                guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                              space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
                context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
                return true
            }
            guard drawn else { return nil }
            self.width = width
            self.height = height
            rgba = bytes
        }
    }

    /// A mask as one byte per pixel (255 keeps, 0 clears), top row first, like `Pixels`.
    struct MaskBuffer: Equatable {
        let width: Int
        let height: Int
        var values: [UInt8]

        init(width: Int, height: Int, values: [UInt8]) {
            self.width = width
            self.height = height
            self.values = values
        }

        /// Reads a mask such as Vision's, with no color management on the way.
        init?(_ mask: CIImage, width: Int, height: Int) {
            let rect = CGRect(x: 0, y: 0, width: width, height: height)
            guard let image = BackgroundRemoval.maskContext.createCGImage(mask, from: rect, format: .L8, colorSpace: CGColorSpaceCreateDeviceGray()) else { return nil }
            var bytes = [UInt8](repeating: 0, count: width * height)
            let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
                guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
                                              space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
                context.draw(image, in: rect)
                return true
            }
            guard drawn else { return nil }
            self.init(width: width, height: height, values: bytes)
        }

        func ciImage() -> CIImage {
            let data = Data(values) as CFData
            guard let provider = CGDataProvider(data: data),
                  let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: width,
                                      space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                                      provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent) else {
                return CIImage.empty()
            }
            return CIImage(cgImage: image, options: [.colorSpace: NSNull()])
        }
    }

    static let maskContext = CIContext(options: [.workingColorSpace: NSNull(), .outputColorSpace: NSNull()])

    static func refine(_ mask: inout MaskBuffer, with refinements: [Refinement], pixels: Pixels) {
        for refinement in refinements { apply(refinement, to: &mask, pixels: pixels) }
    }

    static func apply(_ refinement: Refinement, to mask: inout MaskBuffer, pixels: Pixels) {
        guard mask.width == pixels.width, mask.height == pixels.height else { return }
        switch refinement {
        case let .wand(point, tolerance, keep):
            let seed = (x: min(mask.width - 1, Int(point.x * Double(mask.width))), y: min(mask.height - 1, Int(point.y * Double(mask.height))))
            let value: UInt8 = keep ? 255 : 0
            mask.values.withUnsafeMutableBufferPointer { values in
                flood(pixels, from: seed, tolerance: tolerance) { values[$0] = value }
            }
        case let .brush(path, radius, keep):
            paint(&mask, path: path, radius: radius, value: keep ? 255 : 0)
        }
    }

    /// Visits every pixel 4-connected to `seed` whose color is within `tolerance` of the seed's,
    /// the way a magic wand selects: one contiguous region of similar color.
    static func flood(_ pixels: Pixels, from seed: (x: Int, y: Int), tolerance: Double, _ visit: (Int) -> Void) {
        let width = pixels.width, height = pixels.height
        guard seed.x >= 0, seed.x < width, seed.y >= 0, seed.y < height else { return }
        let reach = max(0, min(1, tolerance)) * 255
        let limit = Int(reach * reach * 3)
        pixels.rgba.withUnsafeBufferPointer { rgba in
            let start = seed.y * width + seed.x
            let r0 = Int(rgba[start * 4]), g0 = Int(rgba[start * 4 + 1]), b0 = Int(rgba[start * 4 + 2])
            var seen = [Bool](repeating: false, count: width * height)
            var stack = [start]
            seen[start] = true
            @inline(__always) func consider(_ index: Int) {
                guard !seen[index] else { return }
                seen[index] = true
                let p = index * 4
                let dr = Int(rgba[p]) - r0, dg = Int(rgba[p + 1]) - g0, db = Int(rgba[p + 2]) - b0
                if dr * dr + dg * dg + db * db <= limit { stack.append(index) }
            }
            while let index = stack.popLast() {
                visit(index)
                let x = index % width
                if x > 0 { consider(index - 1) }
                if x < width - 1 { consider(index + 1) }
                if index >= width { consider(index - width) }
                if index < width * (height - 1) { consider(index + width) }
            }
        }
    }

    /// A round brush stamped along the path, closely enough to leave no gaps.
    static func paint(_ mask: inout MaskBuffer, path: [CGPoint], radius: Double, value: UInt8) {
        let width = mask.width, height = mask.height
        let r = max(1, radius * Double(min(width, height)))
        let points = path.map { (x: $0.x * Double(width), y: $0.y * Double(height)) }
        guard let first = points.first else { return }
        mask.values.withUnsafeMutableBufferPointer { values in
            func stamp(_ cx: Double, _ cy: Double) {
                let y0 = max(0, Int((cy - r).rounded(.down))), y1 = min(height - 1, Int((cy + r).rounded(.up)))
                guard y0 <= y1 else { return }
                for y in y0...y1 {
                    let dy = Double(y) + 0.5 - cy
                    let span = r * r - dy * dy
                    guard span >= 0 else { continue }
                    let dx = span.squareRoot()
                    let x0 = max(0, Int((cx - dx).rounded())), x1 = min(width - 1, Int((cx + dx).rounded()) - 1)
                    guard x0 <= x1 else { continue }
                    for x in x0...x1 { values[y * width + x] = value }
                }
            }
            stamp(first.x, first.y)
            for (a, b) in zip(points, points.dropFirst()) {
                let distance = hypot(b.x - a.x, b.y - a.y)
                let steps = max(1, Int((distance / (r / 3)).rounded(.up)))
                for step in 1...steps {
                    let t = Double(step) / Double(steps)
                    stamp(a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t)
                }
            }
        }
    }
}
