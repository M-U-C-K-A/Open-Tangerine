import CoreGraphics
import Foundation
import PDFKit
import Vision

/// Text from pictures and scanned pages with Apple Vision, on this Mac. Nothing is uploaded.
enum TextRecognition {
    /// A recognised run of text and where it sits, in Vision's normalised coordinates (origin bottom-left).
    struct Fragment: Equatable {
        let box: CGRect
        let text: String
    }

    static func fragments(in image: CGImage) throws -> [Fragment] {
        try ImageIOBridge.validateDimensions(width: image.width, height: image.height)
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = true
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try handler.perform([request])
        } catch {
            throw OpenTangerineError.toolFailed("Text recognition", error.localizedDescription)
        }
        return (request.results ?? []).compactMap { observation in
            observation.topCandidates(1).first.map { Fragment(box: observation.boundingBox, text: $0.string) }
        }
    }

    static func text(in image: CGImage) throws -> String {
        lines(from: try fragments(in: image))
    }

    /// Reading order: rows from top to bottom, each left to right. Fragments whose
    /// vertical centres sit within half a line of each other share a row.
    static func lines(from fragments: [Fragment]) -> String {
        let sorted = fragments.filter { !$0.text.isEmpty }.sorted { $0.box.midY > $1.box.midY }
        var rows: [[Fragment]] = []
        for fragment in sorted {
            if let last = rows.last?.last, abs(last.box.midY - fragment.box.midY) < max(last.box.height, fragment.box.height) * 0.5 {
                rows[rows.count - 1].append(fragment)
            } else {
                rows.append([fragment])
            }
        }
        return rows.map { row in row.sorted { $0.box.minX < $1.box.minX }.map(\.text).joined(separator: " ") }.joined(separator: "\n")
    }

    /// Each page's own text when it has some, recognised text when it is a scan.
    static func text(inPDF url: URL, progress: (Double) -> Void = { _ in }) throws -> String {
        let document = try PDFOps.document(url)
        var pages: [String] = []
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index) else { continue }
            let own = page.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !own.isEmpty {
                pages.append(own)
            } else if let image = PDFRenderer.render(page: page, dpi: 200) {
                pages.append(try text(in: image))
            }
            progress(Double(index + 1) / Double(max(document.pageCount, 1)))
        }
        return pages.filter { !$0.isEmpty }.joined(separator: "\n\n")
    }

    /// The text of images, PDFs and text files, one after another.
    static func text(in urls: [URL], progress: (Double) -> Void = { _ in }) throws -> String {
        var parts: [String] = []
        for (index, url) in urls.enumerated() {
            let part: String
            switch FileFormat.detect(url) {
            case .pdf?: part = try text(inPDF: url)
            case .txt?: part = try String(contentsOf: url, encoding: .utf8)
            case let format? where format.category == .image: part = try text(in: try ImageIOBridge.load(url))
            default: throw OpenTangerineError.invalidInput("\(url.lastPathComponent) has no text to read.")
            }
            parts.append(part.trimmingCharacters(in: .whitespacesAndNewlines))
            progress(Double(index + 1) / Double(urls.count))
        }
        let text = parts.filter { !$0.isEmpty }.joined(separator: "\n\n")
        guard !text.isEmpty else { throw OpenTangerineError.invalidInput("No text found.") }
        return text
    }
}
