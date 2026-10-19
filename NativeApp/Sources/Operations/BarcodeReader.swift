import CoreGraphics
import Foundation
import PDFKit
import Vision

/// QR codes and barcodes in pictures and PDF pages, read with Apple Vision on this Mac.
enum BarcodeReader {
    struct Code: Identifiable, Equatable {
        let id = UUID()
        let payload: String
        let kind: String
        let file: String
        /// Where it sits in its picture, normalised with the origin top-left.
        let box: CGRect

        /// Web, mail and phone links open; anything else is text to copy.
        var link: URL? {
            guard let url = URL(string: payload.trimmingCharacters(in: .whitespacesAndNewlines)),
                  let scheme = url.scheme?.lowercased(), ["http", "https", "mailto", "tel"].contains(scheme) else { return nil }
            return url
        }

        static func == (lhs: Code, rhs: Code) -> Bool { lhs.payload == rhs.payload && lhs.kind == rhs.kind && lhs.file == rhs.file && lhs.box == rhs.box }
    }

    static func codes(in image: CGImage, file: String) throws -> [Code] {
        let request = VNDetectBarcodesRequest()
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try handler.perform([request])
        } catch {
            throw OpenTangerineError.toolFailed("Code reading", error.localizedDescription)
        }
        var seen = Set<String>()
        return (request.results ?? []).compactMap { observation in
            guard let payload = observation.payloadStringValue, seen.insert(payload).inserted else { return nil }
            let box = observation.boundingBox
            return Code(payload: payload, kind: name(observation.symbology), file: file,
                        box: CGRect(x: box.minX, y: 1 - box.maxY, width: box.width, height: box.height))
        }
    }

    static func codes(in urls: [URL]) throws -> [Code] {
        var found: [Code] = []
        for url in urls {
            if FileFormat.detect(url) == .pdf {
                let document = try PDFOps.document(url)
                for index in 0..<document.pageCount {
                    if let page = document.page(at: index), let image = PDFRenderer.render(page: page, dpi: 200) {
                        found += try codes(in: image, file: "\(url.lastPathComponent), page \(index + 1)")
                    }
                }
            } else {
                found += try codes(in: try ImageIOBridge.load(url), file: url.lastPathComponent)
            }
        }
        return found
    }

    static func name(_ symbology: VNBarcodeSymbology) -> String {
        switch symbology {
        case .qr, .microQR: return "QR code"
        case .aztec: return "Aztec"
        case .dataMatrix: return "Data Matrix"
        case .pdf417, .microPDF417: return "PDF417"
        case .ean13, .ean8: return "EAN"
        case .upce: return "UPC"
        default: return "Barcode"
        }
    }
}
