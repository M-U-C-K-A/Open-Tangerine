import AVFoundation
import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation

/// Videos reframed for a network: the crop follows what draws the eye, gliding rather than
/// jumping, or the whole frame sits on a blurred copy of itself. Sound is kept as it is.
enum SocialVideo {
    struct Options: Equatable, Sendable {
        var format: SocialFormat = .instagramStory
        /// Cropped around the subject; off, fitted whole on blurred sides.
        var fill = true
        /// Keep only the start, this many seconds.
        var seconds: Double?
        var hevc = false
    }

    /// Where the subject is over time, as fractions of the upright frame (origin top-left).
    struct FocusTrack: Equatable, Sendable {
        var times: [Double]
        var points: [CGPoint]

        static let center = FocusTrack(times: [0], points: [CGPoint(x: 0.5, y: 0.5)])

        func point(at seconds: Double) -> CGPoint {
            guard let first = times.first, let last = times.last, times.count == points.count, times.count > 1 else { return points.first ?? CGPoint(x: 0.5, y: 0.5) }
            if seconds <= first { return points[0] }
            if seconds >= last { return points[points.count - 1] }
            let next = times.firstIndex { $0 >= seconds } ?? times.count - 1
            let previous = max(0, next - 1)
            let span = times[next] - times[previous]
            let t = span > 0 ? (seconds - times[previous]) / span : 0
            return CGPoint(x: points[previous].x + (points[next].x - points[previous].x) * t, y: points[previous].y + (points[next].y - points[previous].y) * t)
        }

        /// Each point averaged with its neighbours within about a second and a half, so a crop
        /// that follows it pans smoothly.
        func smoothed(over seconds: Double = 0.75) -> FocusTrack {
            guard points.count > 2, let first = times.first, let last = times.last else { return self }
            let smoothed = times.indices.map { index -> CGPoint in
                // The window stays centred: near the start or the end it narrows instead of
                // leaning on one side, so the crop doesn't run ahead of the subject or lag behind.
                let reach = min(seconds * 3, times[index] - first, last - times[index])
                let sigma = max(reach / 3, 0.001)
                var x = 0.0, y = 0.0, weights = 0.0
                for other in times.indices {
                    let distance = times[other] - times[index]
                    guard abs(distance) <= reach + 0.0001 else { continue }
                    let weight = exp(-(distance * distance) / (2 * sigma * sigma))
                    x += weight * points[other].x
                    y += weight * points[other].y
                    weights += weight
                }
                return CGPoint(x: x / weights, y: y / weights)
            }
            return FocusTrack(times: times, points: smoothed)
        }
    }

    /// The subject's place, sampled twice a second (at most 120 times) on small frames.
    static func track(_ url: URL, duration: Double) async -> FocusTrack {
        guard duration > 0 else { return .center }
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 512, height: 512)
        generator.requestedTimeToleranceBefore = CMTime(value: 1, timescale: 4)
        generator.requestedTimeToleranceAfter = CMTime(value: 1, timescale: 4)
        let count = min(120, max(2, Int(duration * 2)))
        var times: [Double] = [], points: [CGPoint] = []
        for index in 0..<count {
            let seconds = duration * (Double(index) + 0.5) / Double(count)
            guard let frame = try? await generator.image(at: CMTime(seconds: seconds, preferredTimescale: 600)).image else { continue }
            times.append(seconds)
            points.append(SocialFrame.focus(frame))
        }
        return times.isEmpty ? .center : FocusTrack(times: times, points: points).smoothed()
    }

    /// One upright frame (origin at zero) at the network's size.
    static func reframe(_ image: CIImage, focus: CGPoint, options: Options) -> CIImage {
        let w = image.extent.width, h = image.extent.height
        let target = options.format.size
        let output = CGRect(origin: .zero, size: target)
        guard w > 0, h > 0 else { return image }
        func scaled(_ input: CIImage, x: CGFloat, y: CGFloat) -> CIImage {
            let lanczos = CIFilter.lanczosScaleTransform()
            lanczos.inputImage = input
            lanczos.scale = Float(y)
            lanczos.aspectRatio = Float(x / y)
            return lanczos.outputImage ?? input.transformed(by: CGAffineTransform(scaleX: x, y: y))
        }
        if options.fill {
            let ratio = target.width / target.height
            let cropW = min(w, h * ratio), cropH = min(h, w / ratio)
            let x = min(max(0, focus.x * w - cropW / 2), w - cropW)
            let top = min(max(0, focus.y * h - cropH / 2), h - cropH)
            let crop = CGRect(x: x, y: h - top - cropH, width: cropW, height: cropH)
            let moved = image.cropped(to: crop).transformed(by: CGAffineTransform(translationX: -crop.minX, y: -crop.minY))
            return scaled(moved, x: target.width / cropW, y: target.height / cropH).cropped(to: output)
        }
        let cover = max(target.width / w, target.height / h)
        let back = image.transformed(by: CGAffineTransform(scaleX: cover, y: cover))
            .transformed(by: CGAffineTransform(translationX: (target.width - w * cover) / 2, y: (target.height - h * cover) / 2))
        let blur = CIFilter.gaussianBlur(); blur.inputImage = back.clampedToExtent(); blur.radius = Float(max(target.width, target.height) / 30)
        let dim = CIFilter.colorControls(); dim.inputImage = blur.outputImage; dim.brightness = -0.12; dim.saturation = 1.1
        let fit = min(target.width / w, target.height / h)
        let front = scaled(image, x: fit, y: fit)
            .transformed(by: CGAffineTransform(translationX: (target.width - w * fit) / 2, y: (target.height - h * fit) / 2))
        return front.composited(over: (dim.outputImage ?? back).cropped(to: output)).cropped(to: output)
    }

    /// The end of the copy's name, after the network and shape.
    static func suffix(_ format: SocialFormat) -> String {
        switch format {
        case .instagramStory: return "reel"
        case .tiktok: return "tiktok"
        case .youtubeShort: return "short"
        case .instagramPost: return "instagram"
        case .instagramSquare: return "square"
        case .youtubeVideo, .youtubeThumbnail: return "youtube"
        case .xPost: return "x"
        case .linkedinPost: return "linkedin"
        case .facebookPost: return "facebook"
        case .pinterestPin: return "pinterest"
        }
    }

    static func apply(_ url: URL, options: Options, track known: FocusTrack? = nil, to destination: URL, progress: @escaping (Double) -> Void) async throws {
        guard await MediaInfo.isNativelyReadable(url) else {
            try await applyWithFFmpeg(url, options: options, to: destination, progress: progress)
            return
        }
        let (_, _, source) = try await VideoPipeline.source(url)
        var track = FocusTrack.center
        if options.fill {
            if let known { track = known } else { track = await self.track(url, duration: source.duration) }
        }
        progress(0.02)
        let found = track
        try await VideoPipeline.run(url, upright: true, codec: options.hevc ? .hevc : .h264, seconds: options.seconds, size: { _, _ in options.format.size }, bitrate: { source, output in
            Double(output.width * output.height) * Double(max(source.frameRate, 24)) * (options.hevc ? 0.07 : 0.11)
        }, to: destination, progress: { progress(0.02 + 0.98 * $0) }) { frame, time in
            reframe(frame, focus: found.point(at: CMTimeGetSeconds(time)), options: options)
        }
    }

    /// Formats macOS doesn't read: FFmpeg crops from the middle, or fits on blurred sides.
    static func applyWithFFmpeg(_ url: URL, options: Options, to destination: URL, progress: @escaping (Double) -> Void) async throws {
        guard FFmpeg.isAvailable else { throw OpenTangerineError.ffmpegMissing("Reframing \(url.pathExtension.uppercased()) videos") }
        let w = Int(options.format.size.width), h = Int(options.format.size.height)
        let graph = options.fill
            ? "scale=\(w):\(h):force_original_aspect_ratio=increase,crop=\(w):\(h),setsar=1"
            : "split[a][b];[a]scale=\(w):\(h):force_original_aspect_ratio=increase,crop=\(w):\(h),boxblur=24:2,eq=brightness=-0.08[bg];[b]scale=\(w):\(h):force_original_aspect_ratio=decrease[fg];[bg][fg]overlay=(W-w)/2:(H-h)/2,setsar=1"
        var args = ["-i", url.path]
        if let seconds = options.seconds { args += ["-t", String(format: "%.3f", seconds)] }
        args += ["-vf", graph]
        var codec = VideoEngine.codecArguments(for: .mp4)
        if options.hevc, let index = codec.firstIndex(of: "libx264") { codec[index] = "libx265"; codec += ["-tag:v", "hvc1"] }
        args += codec + [destination.path]
        let duration = min(await FFmpeg.probeDuration(url) ?? 0, options.seconds ?? .infinity)
        try await FFmpeg.run(args, purpose: "Reframing for \(options.format.network)", duration: duration > 0 ? duration : nil, progress: progress)
    }
}
