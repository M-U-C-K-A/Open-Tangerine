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
    }

    /// Face boxes in the image's own pixel coordinates (origin bottom-left, like Core Image).
    static func faces(in image: CIImage) throws -> [CGRect] {
        let request = VNDetectFaceRectanglesRequest()
        let handler = VNImageRequestHandler(ciImage: image, options: [:])
        do {
            try handler.perform([request])
        } catch {
            throw OpenTangerineError.toolFailed("Face detection", error.localizedDescription)
        }
        let extent = image.extent
        return (request.results ?? []).map { face in
            VNImageRectForNormalizedRect(face.boundingBox, Int(extent.width), Int(extent.height)).offsetBy(dx: extent.minX, dy: extent.minY)
        }
    }

    /// Grows a face box on every side, then keeps it inside the picture.
    static func covered(_ face: CGRect, padding: Double, in extent: CGRect) -> CGRect {
        face.insetBy(dx: -face.width * padding, dy: -face.height * padding).intersection(extent)
    }

    static func hide(_ image: CIImage, faces: [CGRect], options: Options) -> CIImage {
        let redactions = faces.map { Redaction(rect: covered($0, padding: options.padding, in: image.extent), style: options.style) }
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
        let composition = try await VideoOps.videoComposition(for: asset, crop: nil, outputSize: nil) { frame, _ in
            guard let found = try? faces(in: frame), !found.isEmpty else { return frame }
            return hide(frame, faces: found, options: options)
        }
        try await AVExporter.export(asset: asset, to: destination, format: .mp4, preset: AVAssetExportPresetHighestQuality, videoComposition: composition, progress: progress)
    }
}
