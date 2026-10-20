import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins
import CoreText
import Foundation
import ImageIO
import PDFKit
import Vision

/// Writes PDFs whose pages carry the words they show as invisible text, at their places:
/// the page looks the same, and the text can be searched, selected and copied.
final class SearchablePDFWriter {
    private let context: CGContext

    init(url: URL) throws {
        var box = CGRect(x: 0, y: 0, width: 612, height: 792)
        guard let consumer = CGDataConsumer(url: url as CFURL), let context = CGContext(consumer: consumer, mediaBox: &box, nil) else {
            throw OpenTangerineError.encodeFailed(url.lastPathComponent)
        }
        self.context = context
    }

    /// One page of `size` points: `draw` paints it, then the recognised words go on top, invisibly.
    /// `textRect` is where the picture the words were read from sits on the page.
    func addPage(size: CGSize, textRect: CGRect? = nil, fragments: [TextRecognition.Fragment] = [], draw: (CGContext) -> Void) {
        var media = CGRect(origin: .zero, size: size)
        let info = [kCGPDFContextMediaBox as String: Data(bytes: &media, count: MemoryLayout<CGRect>.size)] as CFDictionary
        context.beginPDFPage(info)
        context.saveGState()
        draw(context)
        context.restoreGState()
        Self.drawInvisible(fragments, in: textRect ?? media, context: context)
        context.endPDFPage()
    }

    func close() {
        context.closePDF()
    }

    static func drawInvisible(_ fragments: [TextRecognition.Fragment], in rect: CGRect, context: CGContext) {
        guard !fragments.isEmpty else { return }
        context.saveGState()
        context.setTextDrawingMode(.invisible)
        for fragment in fragments where !fragment.text.isEmpty {
            // Vision's boxes are fractions of the picture, origin bottom-left, as PDF pages are.
            let box = CGRect(x: rect.minX + fragment.box.minX * rect.width, y: rect.minY + fragment.box.minY * rect.height, width: fragment.box.width * rect.width, height: fragment.box.height * rect.height)
            guard box.width > 1, box.height > 1 else { continue }
            let font = CTFontCreateWithName("Helvetica" as CFString, box.height * 0.8, nil)
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: fragment.text, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font]))
            let width = CTLineGetTypographicBounds(line, nil, nil, nil)
            // Stretched to the width the words take on the page, so a selection lines up with them.
            context.textMatrix = CGAffineTransform(scaleX: width > 0 ? box.width / CGFloat(width) : 1, y: 1)
            context.textPosition = CGPoint(x: box.minX, y: box.minY + box.height * 0.18)
            CTLineDraw(line, context)
        }
        context.restoreGState()
    }
}

enum SearchablePDF {
    /// A copy of the PDF where every scanned page (a picture, no text of its own) carries its
    /// recognised words. Pages that already have text are kept as they are. Returns how many
    /// pages were read.
    @discardableResult
    static func make(_ url: URL, to destination: URL, progress: @escaping (Double) -> Void) throws -> Int {
        let document = try PDFOps.document(url)
        let writer = try SearchablePDFWriter(url: destination)
        var read = 0
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index) else { continue }
            let bounds = page.bounds(for: .mediaBox)
            let quarter = ((page.rotation % 360) + 360) % 360
            let size = quarter == 90 || quarter == 270 ? CGSize(width: bounds.height, height: bounds.width) : bounds.size
            let own = page.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            var fragments: [TextRecognition.Fragment] = []
            if own.isEmpty, let image = PDFRenderer.render(page: page, dpi: 300) {
                fragments = try TextRecognition.fragments(in: image)
                read += 1
            }
            writer.addPage(size: size, fragments: fragments) { context in
                page.draw(with: .mediaBox, to: context)
            }
            progress(Double(index + 1) / Double(document.pageCount))
        }
        writer.close()
        return read
    }
}

/// Photos of pages made into a flat, clean scan: the page found and straightened, the
/// lighting evened out, as a PDF that can be searchable.
enum DocumentScan {
    /// The page's corners as fractions of the photo, origin top-left.
    struct Quad: Equatable, Sendable {
        var topLeft: CGPoint
        var topRight: CGPoint
        var bottomRight: CGPoint
        var bottomLeft: CGPoint

        static let whole = Quad(topLeft: CGPoint(x: 0, y: 0), topRight: CGPoint(x: 1, y: 0), bottomRight: CGPoint(x: 1, y: 1), bottomLeft: CGPoint(x: 0, y: 1))

        var corners: [CGPoint] {
            get { [topLeft, topRight, bottomRight, bottomLeft] }
            set { topLeft = newValue[0]; topRight = newValue[1]; bottomRight = newValue[2]; bottomLeft = newValue[3] }
        }
    }

    enum Look: String, CaseIterable, Identifiable {
        case color, gray, blackWhite
        var id: String { rawValue }
        var title: String {
            switch self {
            case .color: return "Color"
            case .gray: return "Gray"
            case .blackWhite: return "Black & white"
            }
        }
    }

    enum PageSize: String, CaseIterable, Identifiable {
        case fit, a4, letter
        var id: String { rawValue }
        var title: String {
            switch self {
            case .fit: return "Fit"
            case .a4: return "A4"
            case .letter: return "Letter"
            }
        }
    }

    static let context = CIContext(options: [.cacheIntermediates: false])

    /// Where the page is in the photo, if Vision can tell.
    static func detect(_ image: CGImage) -> Quad? {
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        let segmentation = VNDetectDocumentSegmentationRequest()
        let rectangles = VNDetectRectanglesRequest()
        rectangles.maximumObservations = 1
        rectangles.minimumSize = 0.25
        rectangles.minimumConfidence = 0.6
        rectangles.quadratureTolerance = 30
        try? handler.perform([segmentation, rectangles])
        let found = (segmentation.results?.first as VNRectangleObservation?) ?? rectangles.results?.first
        guard let found, found.confidence > 0.3 else { return nil }
        func flip(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x, y: 1 - p.y) }
        return Quad(topLeft: flip(found.topLeft), topRight: flip(found.topRight), bottomRight: flip(found.bottomRight), bottomLeft: flip(found.bottomLeft))
    }

    /// The page straightened to a rectangle, its lighting evened out in the look chosen.
    static func flatten(_ image: CGImage, quad: Quad, look: Look) -> CGImage? {
        let input = CIImage(cgImage: image)
        let w = CGFloat(image.width), h = CGFloat(image.height)
        func point(_ p: CGPoint) -> CGPoint { CGPoint(x: min(1, max(0, p.x)) * w, y: (1 - min(1, max(0, p.y))) * h) }
        var page = input
        if quad != .whole {
            let filter = CIFilter.perspectiveCorrection()
            filter.inputImage = input
            filter.topLeft = point(quad.topLeft)
            filter.topRight = point(quad.topRight)
            filter.bottomRight = point(quad.bottomRight)
            filter.bottomLeft = point(quad.bottomLeft)
            guard let corrected = filter.outputImage else { return nil }
            page = corrected.transformed(by: CGAffineTransform(translationX: -corrected.extent.minX, y: -corrected.extent.minY))
        }
        let extent = page.extent.integral
        let cleaned = clean(page, look: look, extent: extent)
        return context.createCGImage(cleaned, from: extent, format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
    }

    /// Paper made white and ink kept: each pixel divided by a heavy blur of its surroundings
    /// (the lighting), then toned for the look.
    static func clean(_ page: CIImage, look: Look, extent: CGRect) -> CIImage {
        var base = page
        if look != .color {
            let gray = CIFilter.colorControls(); gray.inputImage = page; gray.saturation = 0; gray.contrast = 1
            base = gray.outputImage ?? page
        }
        let blur = CIFilter.gaussianBlur()
        blur.inputImage = base.clampedToExtent()
        blur.radius = Float(max(extent.width, extent.height) / 40)
        let lighting = (blur.outputImage ?? base).cropped(to: extent)
        let divide = CIFilter.divideBlendMode()
        divide.inputImage = lighting
        divide.backgroundImage = base
        var even = (divide.outputImage ?? base).cropped(to: extent)
        switch look {
        case .color:
            let tone = CIFilter.colorControls(); tone.inputImage = even; tone.saturation = 1.15; tone.contrast = 1.1
            even = tone.outputImage ?? even
        case .gray:
            let tone = CIFilter.colorControls(); tone.inputImage = even; tone.contrast = 1.35; tone.brightness = 0.02
            even = tone.outputImage ?? even
        case .blackWhite:
            let threshold = CIFilter.colorThreshold(); threshold.inputImage = even; threshold.threshold = 0.82
            even = threshold.outputImage ?? even
        }
        return even.cropped(to: extent)
    }

    static func jpegBacked(_ image: CGImage, quality: Double) -> CGImage? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, "public.jpeg" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(destination), let provider = CGDataProvider(data: data) else { return nil }
        return CGImage(jpegDataProviderSource: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }

    /// The pages into one PDF, each picture fitted to the page size chosen, and readable
    /// text added when `searchable`.
    static func makePDF(_ pages: [CGImage], size pageSize: PageSize, searchable: Bool, to destination: URL, progress: @escaping (Double) -> Void) throws {
        guard !pages.isEmpty else { throw OpenTangerineError.invalidInput("No pages to save.") }
        let writer = try SearchablePDFWriter(url: destination)
        for (index, image) in pages.enumerated() {
            let picture = CGSize(width: image.width, height: image.height)
            let landscape = picture.width > picture.height
            var size: CGSize
            switch pageSize {
            case .fit: size = CGSize(width: picture.width * 72 / 200, height: picture.height * 72 / 200)
            case .a4: size = CGSize(width: 595.28, height: 841.89)
            case .letter: size = CGSize(width: 612, height: 792)
            }
            if pageSize != .fit, landscape { size = CGSize(width: size.height, height: size.width) }
            let scale = min(size.width / picture.width, size.height / picture.height)
            let rect = CGRect(x: (size.width - picture.width * scale) / 2, y: (size.height - picture.height * scale) / 2, width: picture.width * scale, height: picture.height * scale)
            let fragments = searchable ? ((try? TextRecognition.fragments(in: image)) ?? []) : []
            // A JPEG-backed picture goes into the PDF as JPEG, not as raw pixels.
            let embedded = jpegBacked(image, quality: 0.82) ?? image
            writer.addPage(size: size, textRect: rect, fragments: fragments) { context in
                context.interpolationQuality = .high
                context.draw(embedded, in: rect)
            }
            progress(Double(index + 1) / Double(pages.count))
        }
        writer.close()
    }
}
