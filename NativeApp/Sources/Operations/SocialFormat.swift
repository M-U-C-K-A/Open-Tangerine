import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import Vision

/// The picture sizes social networks show best, with how they show them.
enum SocialFormat: String, CaseIterable, Identifiable, Sendable {
    case instagramPost, instagramSquare, instagramStory, tiktok, youtubeThumbnail, xPost, linkedinPost, facebookPost, pinterestPin
    case youtubeShort, youtubeVideo

    var id: String { rawValue }

    /// The sizes offered for pictures, and for videos.
    static let imageFormats: [SocialFormat] = [.instagramPost, .instagramSquare, .instagramStory, .tiktok, .youtubeThumbnail, .xPost, .linkedinPost, .facebookPost, .pinterestPin]
    static let videoFormats: [SocialFormat] = [.instagramStory, .tiktok, .youtubeShort, .instagramPost, .instagramSquare, .youtubeVideo, .xPost, .linkedinPost]

    var network: String {
        switch self {
        case .instagramPost, .instagramSquare, .instagramStory: return "Instagram"
        case .tiktok: return "TikTok"
        case .youtubeThumbnail, .youtubeShort, .youtubeVideo: return "YouTube"
        case .xPost: return "X"
        case .linkedinPost: return "LinkedIn"
        case .facebookPost: return "Facebook"
        case .pinterestPin: return "Pinterest"
        }
    }

    var title: String {
        switch self {
        case .instagramPost: return "Instagram post · 4:5"
        case .instagramSquare: return "Instagram square · 1:1"
        case .instagramStory: return "Instagram story or reel · 9:16"
        case .tiktok: return "TikTok · 9:16"
        case .youtubeThumbnail: return "YouTube thumbnail · 16:9"
        case .xPost: return "X post · 16:9"
        case .linkedinPost: return "LinkedIn post · 1.91:1"
        case .facebookPost: return "Facebook post · 1.91:1"
        case .pinterestPin: return "Pinterest pin · 2:3"
        case .youtubeShort: return "YouTube Short · 9:16"
        case .youtubeVideo: return "YouTube video · 16:9"
        }
    }

    var size: CGSize {
        switch self {
        case .instagramPost: return CGSize(width: 1080, height: 1350)
        case .instagramSquare: return CGSize(width: 1080, height: 1080)
        case .instagramStory, .tiktok, .youtubeShort: return CGSize(width: 1080, height: 1920)
        case .youtubeVideo: return CGSize(width: 1920, height: 1080)
        case .youtubeThumbnail: return CGSize(width: 1280, height: 720)
        case .xPost: return CGSize(width: 1600, height: 900)
        case .linkedinPost, .facebookPost: return CGSize(width: 1200, height: 628)
        case .pinterestPin: return CGSize(width: 1000, height: 1500)
        }
    }

    enum Layout { case feed, story, video, card }

    /// How the network presents it, for the preview.
    var layout: Layout {
        switch self {
        case .instagramPost, .instagramSquare: return .feed
        case .instagramStory, .tiktok, .youtubeShort: return .story
        case .youtubeThumbnail, .youtubeVideo: return .video
        case .xPost, .linkedinPost, .facebookPost, .pinterestPin: return .card
        }
    }

    /// Parts of a full-screen picture the app's buttons and captions cover, as fractions of its height.
    var coveredTop: CGFloat { layout == .story ? 0.14 : 0 }
    var coveredBottom: CGFloat { layout == .story ? 0.2 : 0 }
}

/// Brings a picture to a network's shape: filled (cropped around what draws the eye) or
/// fitted whole on a blurred copy of itself.
enum SocialFrame {
    static let context = CIContext(options: [.cacheIntermediates: false])

    /// The middle of the main subject, as fractions of the picture (origin top-left). Objects
    /// first, as they are found tightly; where there are none, where the eye goes, which
    /// leans to the middle.
    static func focus(_ image: CGImage) -> CGPoint {
        let small = ImageIOBridge.resized(image, longEdge: 768)
        let objects = VNGenerateObjectnessBasedSaliencyImageRequest()
        let attention = VNGenerateAttentionBasedSaliencyImageRequest()
        try? VNImageRequestHandler(cgImage: small, options: [:]).perform([objects, attention])
        let found = objects.results?.first?.salientObjects ?? []
        if let main = found.max(by: { ($0.confidence, $0.boundingBox.width * $0.boundingBox.height) < ($1.confidence, $1.boundingBox.width * $1.boundingBox.height) }) {
            return CGPoint(x: main.boundingBox.midX, y: 1 - main.boundingBox.midY)
        }
        let boxes = attention.results?.first?.salientObjects?.map(\.boundingBox) ?? []
        guard let first = boxes.first else { return CGPoint(x: 0.5, y: 0.5) }
        let union = boxes.dropFirst().reduce(first) { $0.union($1) }
        return CGPoint(x: union.midX, y: 1 - union.midY)
    }

    static func framed(_ image: CGImage, aspect: CGSize, fill: Bool, focus: CGPoint) -> CGImage {
        let w = CGFloat(image.width), h = CGFloat(image.height)
        let ratio = aspect.width / aspect.height
        guard abs(w / h - ratio) > 0.002 else { return image }
        if fill {
            // The largest crop of this shape, placed over the focus, kept inside the picture.
            let cropW = min(w, h * ratio), cropH = min(h, w / ratio)
            let x = min(max(0, focus.x * w - cropW / 2), w - cropW)
            let y = min(max(0, focus.y * h - cropH / 2), h - cropH)
            return image.cropping(to: CGRect(x: x, y: y, width: cropW, height: cropH).integral) ?? image
        }
        // Fitted whole, on a blurred and dimmed copy that fills the shape.
        let canvasW = max(w, h * ratio), canvasH = max(h, w / ratio)
        let canvas = CGRect(x: 0, y: 0, width: canvasW.rounded(), height: canvasH.rounded())
        let input = CIImage(cgImage: image)
        let cover = max(canvasW / w, canvasH / h)
        let back = input.transformed(by: CGAffineTransform(scaleX: cover, y: cover))
            .transformed(by: CGAffineTransform(translationX: (canvasW - w * cover) / 2, y: (canvasH - h * cover) / 2))
        let blur = CIFilter.gaussianBlur(); blur.inputImage = back.clampedToExtent(); blur.radius = Float(max(canvasW, canvasH) / 30)
        let dim = CIFilter.colorControls(); dim.inputImage = blur.outputImage; dim.brightness = -0.12; dim.saturation = 1.1
        let front = input.transformed(by: CGAffineTransform(translationX: (canvasW - w) / 2, y: (canvasH - h) / 2))
        let composed = front.composited(over: (dim.outputImage ?? back).cropped(to: canvas))
        return context.createCGImage(composed, from: canvas, format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)) ?? image
    }
}
