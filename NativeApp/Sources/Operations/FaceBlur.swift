import AVFoundation
import CoreImage
import Foundation
import Vision

/// Finds faces with Apple Vision and hides them: in photos once, in videos frame by
/// frame, so a face that moves stays covered. On this Mac.
enum FaceBlur {
    struct Options: Equatable {
        var style: RedactionStyle = .blur
        /// How much room around each face is covered, as a fraction of the face: hair, ears, chin.
        var padding: Double = 0.3
        var strength: Double = Redaction.defaultStrength
    }

    static let context = CIContext(options: [.cacheIntermediates: false])

    /// Face boxes in the image's own pixel coordinates (origin bottom-left, like Core Image).
    /// The search runs on a copy at most `maxSide` pixels long, which finds the same faces
    /// in a fraction of the time and memory.
    static func faces(in image: CIImage, maxSide: CGFloat = 1600) throws -> [CGRect] {
        let extent = image.extent
        guard extent.width >= 1, extent.height >= 1 else { return [] }
        let scale = min(1, maxSide / max(extent.width, extent.height))
        let small = image.transformed(by: CGAffineTransform(translationX: -extent.minX, y: -extent.minY).scaledBy(x: scale, y: scale))
        guard let pixels = context.createCGImage(small, from: CGRect(x: 0, y: 0, width: (extent.width * scale).rounded(.down), height: (extent.height * scale).rounded(.down))) else { return [] }
        let request = VNDetectFaceRectanglesRequest()
        let handler = VNImageRequestHandler(cgImage: pixels, options: [:])
        do {
            try handler.perform([request])
        } catch {
            throw OpenTangerineError.toolFailed("Face detection", error.localizedDescription)
        }
        return (request.results ?? []).map { face in
            VNImageRectForNormalizedRect(face.boundingBox, Int(extent.width), Int(extent.height)).offsetBy(dx: extent.minX, dy: extent.minY)
        }
    }

    /// Faces in video frames: searched at most `rate` times a second on a small copy of the
    /// frame, the last answer reused in between. Frames can arrive on several threads.
    final class Tracker: @unchecked Sendable {
        private let lock = NSLock()
        private var lastTime = -Double.infinity
        private var lastFaces: [CGRect] = []
        private let interval: Double

        init(rate: Double = 15) { interval = 1 / rate }

        func faces(in frame: CIImage, at seconds: Double) -> [CGRect] {
            lock.lock()
            if abs(seconds - lastTime) < interval {
                defer { lock.unlock() }
                return lastFaces
            }
            lock.unlock()
            let found = (try? FaceBlur.faces(in: frame, maxSide: 1280)) ?? []
            lock.lock()
            lastTime = seconds
            lastFaces = found
            lock.unlock()
            return found
        }
    }

    /// Grows a face box on every side, then keeps it inside the picture.
    static func covered(_ face: CGRect, padding: Double, in extent: CGRect) -> CGRect {
        face.insetBy(dx: -face.width * padding, dy: -face.height * padding).intersection(extent)
    }

    static func hide(_ image: CIImage, faces: [CGRect], options: Options) -> CIImage {
        let redactions = faces.map { Redaction(rect: covered($0, padding: options.padding, in: image.extent), style: options.style, strength: options.strength) }
        return ImageOps.redact(image, redactions: redactions, flipped: false)
    }

    /// The picture with every face hidden, and how many there were.
    static func apply(_ image: CGImage, options: Options) throws -> (image: CGImage, count: Int) {
        let input = CIImage(cgImage: image)
        let found = try faces(in: input)
        guard !found.isEmpty else { throw OpenTangerineError.invalidInput("No faces found in this picture.") }
        guard let output = ImageOps.render(hide(input, faces: found, options: options), extent: input.extent) else {
            throw OpenTangerineError.encodeFailed("the picture with faces hidden")
        }
        return (output, found.count)
    }

    /// Every frame is searched for faces and each one is hidden; sound is kept as it is.
    static func applyVideo(_ url: URL, options: Options, to destination: URL, progress: @escaping (Double) -> Void) async throws {
        guard await MediaInfo.isNativelyReadable(url) else {
            throw OpenTangerineError.invalidInput("Faces can be hidden in MP4 and MOV videos. Convert this one to MP4 first.")
        }
        let asset = AVURLAsset(url: url)
        let tracker = Tracker()
        let composition = try await VideoOps.videoComposition(for: asset, crop: nil, outputSize: nil) { frame, time in
            let found = tracker.faces(in: frame, at: CMTimeGetSeconds(time))
            return found.isEmpty ? frame : hide(frame, faces: found, options: options)
        }
        try await AVExporter.export(asset: asset, to: destination, format: .mp4, preset: AVAssetExportPresetHighestQuality, videoComposition: composition, progress: progress)
    }
}
