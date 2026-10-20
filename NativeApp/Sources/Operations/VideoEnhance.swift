import AVFoundation
import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation

/// Cleans up and sharpens videos frame by frame, optionally at twice the resolution with the
/// Mac's super resolution. Sound is copied as it is.
enum VideoEnhance {
    struct Options: Equatable, Sendable {
        enum Denoise: String, CaseIterable, Identifiable, Sendable {
            case off, light, strong
            var id: String { rawValue }
            var title: String { rawValue.capitalized }
        }

        var denoise: Denoise = .light
        var sharpen = true
        /// Light and color corrected once from a frame in the middle, then the same for every frame.
        var autoLight = false
        var double = false
        var method: Upscale.Method = Upscale.enhanceAvailable ? .enhance : .enlarge

        var changesSomething: Bool { denoise != .off || sharpen || autoLight || double }
    }

    /// Light and color corrections worked out from one frame, to apply to all of them.
    struct Look: @unchecked Sendable {
        let filters: [CIFilter]

        static func from(_ frame: CIImage) -> Look {
            Look(filters: frame.autoAdjustmentFilters(options: [.redEye: false]))
        }
    }

    /// One frame through the chosen steps. Doubling with super resolution goes through `resolver`.
    static func process(_ frame: CIImage, options: Options, look: Look?, resolver: SuperResolver?) async throws -> CIImage {
        let extent = frame.extent
        var image = frame
        if options.denoise != .off {
            let filter = CIFilter.noiseReduction()
            filter.inputImage = image
            filter.noiseLevel = options.denoise == .light ? 0.02 : 0.05
            filter.sharpness = options.sharpen ? 0.6 : 0.3
            image = (filter.outputImage ?? image).cropped(to: extent)
        }
        if let look {
            for filter in look.filters {
                filter.setValue(image, forKey: kCIInputImageKey)
                image = (filter.outputImage ?? image).cropped(to: extent)
            }
        }
        var outExtent = extent
        if options.double {
            outExtent = CGRect(x: 0, y: 0, width: extent.width * 2, height: extent.height * 2)
            if options.method == .enhance, let resolver {
                image = CIImage(cgImage: try await resolver.process(image))
            } else {
                let lanczos = CIFilter.lanczosScaleTransform()
                lanczos.inputImage = image
                lanczos.scale = 2
                lanczos.aspectRatio = 1
                image = (lanczos.outputImage ?? image).cropped(to: outExtent)
            }
        }
        if options.sharpen {
            let filter = CIFilter.sharpenLuminance()
            filter.inputImage = image
            filter.sharpness = 0.45
            filter.radius = options.double ? 2.4 : 1.4
            image = (filter.outputImage ?? image).cropped(to: outExtent)
        }
        return image.cropped(to: outExtent)
    }

    static func apply(_ url: URL, options: Options, to destination: URL, progress: @escaping (Double) -> Void) async throws {
        guard await MediaInfo.isNativelyReadable(url) else {
            try await applyWithFFmpeg(url, options: options, to: destination, progress: progress)
            return
        }
        let (_, _, source) = try await VideoPipeline.source(url)
        let width = Int(source.natural.width), height = Int(source.natural.height)
        let resolver = options.double && options.method == .enhance ? try SuperResolver(width: width, height: height) : nil
        var look: Look?
        if options.autoLight, let middle = try? await VideoOps.snapshot(url, at: source.duration / 2) {
            look = Look.from(CIImage(cgImage: middle))
        }
        let chosen = look
        try await VideoPipeline.run(url, upright: false, size: { _, frame in
            options.double ? CGSize(width: frame.width * 2, height: frame.height * 2) : frame
        }, bitrate: { source, output in
            // HEVC keeps the extra detail at a sensible size; the bitrate follows the source's.
            max(Double(source.dataRate) * (options.double ? 2.5 : 1.2), Double(output.width * output.height) * Double(max(source.frameRate, 24)) * 0.08)
        }, to: destination, progress: progress) { frame, _ in
            try await process(frame, options: options, look: chosen, resolver: resolver)
        }
    }

    /// Formats macOS doesn't read: FFmpeg's denoiser, sharpening and Lanczos doubling.
    static func applyWithFFmpeg(_ url: URL, options: Options, to destination: URL, progress: @escaping (Double) -> Void) async throws {
        guard FFmpeg.isAvailable else { throw OpenTangerineError.ffmpegMissing("Enhancing \(url.pathExtension.uppercased()) videos") }
        var filters: [String] = []
        switch options.denoise {
        case .off: break
        case .light: filters.append("hqdn3d=1.5:1.5:6:6")
        case .strong: filters.append("hqdn3d=4:3:9:7")
        }
        if options.autoLight { filters.append("eq=contrast=1.05:saturation=1.08") }
        if options.double { filters.append("scale=iw*2:ih*2:flags=lanczos") }
        if options.sharpen { filters.append("unsharp=5:5:0.6:5:5:0.0") }
        try await VideoEngine.ffmpegConvert(source: url, destination: destination, target: .mp4, videoFilters: filters, progress: progress)
    }
}
