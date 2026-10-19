import AppKit
import Foundation
import PDFKit

struct PDFPageRef: Identifiable, Equatable {
    let id = UUID()
    let sourceIndex: Int
    var rotation: Int
    var sourceURL: URL

    static func == (lhs: PDFPageRef, rhs: PDFPageRef) -> Bool {
        lhs.id == rhs.id && lhs.rotation == rhs.rotation
    }
}

enum PDFOps {
    static func document(_ url: URL) throws -> PDFDocument {
        guard let document = PDFDocument(url: url) else { throw OpenTangerineError.unreadable(url) }
        if document.isLocked { throw OpenTangerineError.invalidInput("\(url.lastPathComponent) is password protected.") }
        guard document.pageCount > 0 else { throw OpenTangerineError.invalidInput("The PDF has no pages.") }
        return document
    }

    /// A copy that asks for `password` to open. The owner password (for printing and
    /// editing rights) is the same unless another is given.
    static func protect(_ url: URL, password: String, ownerPassword: String? = nil, to destination: URL) throws {
        guard !password.isEmpty else { throw OpenTangerineError.invalidInput("Choose a password.") }
        let source = try document(url)
        let owner = ownerPassword.flatMap { $0.isEmpty ? nil : $0 } ?? password
        guard source.write(to: destination, withOptions: [.userPasswordOption: password, .ownerPasswordOption: owner]) else {
            throw OpenTangerineError.encodeFailed(destination.lastPathComponent)
        }
    }

    /// A copy without the password, for someone who knows it.
    static func unlock(_ url: URL, password: String, to destination: URL) throws {
        guard let source = PDFDocument(url: url) else { throw OpenTangerineError.unreadable(url) }
        if source.isLocked, !source.unlock(withPassword: password) {
            throw OpenTangerineError.invalidInput("That password doesn't open \(url.lastPathComponent).")
        }
        // Copy the pages into a fresh document, which is written without encryption.
        let open = PDFDocument()
        for index in 0..<source.pageCount {
            if let page = source.page(at: index)?.copy() as? PDFPage { open.insert(page, at: open.pageCount) }
        }
        open.documentAttributes = source.documentAttributes
        guard open.pageCount > 0, open.write(to: destination) else { throw OpenTangerineError.encodeFailed(destination.lastPathComponent) }
    }

    static func merge(_ urls: [URL], to destination: URL) throws {
        guard !urls.isEmpty else { throw OpenTangerineError.invalidInput("Choose at least one PDF to merge.") }
        let output = PDFDocument()
        for url in urls {
            let source = try document(url)
            for index in 0..<source.pageCount {
                guard let page = source.page(at: index) else { continue }
                output.insert(page, at: output.pageCount)
            }
        }
        guard output.write(to: destination) else { throw OpenTangerineError.encodeFailed(destination.lastPathComponent) }
    }

    static func assemble(pages: [PDFPageRef], to destination: URL) throws {
        var cache: [URL: PDFDocument] = [:]
        let output = PDFDocument()
        for ref in pages {
            let source: PDFDocument
            if let cached = cache[ref.sourceURL] {
                source = cached
            } else {
                source = try document(ref.sourceURL)
                cache[ref.sourceURL] = source
            }
            guard let page = source.page(at: ref.sourceIndex), let copy = page.copy() as? PDFPage else { throw OpenTangerineError.invalidInput("A selected PDF page is unavailable.") }
            copy.rotation = ref.rotation
            output.insert(copy, at: output.pageCount)
        }
        guard output.pageCount > 0 else { throw OpenTangerineError.invalidInput("The document would have no pages.") }
        guard output.write(to: destination) else { throw OpenTangerineError.encodeFailed(destination.lastPathComponent) }
    }

    enum SplitMode: String, CaseIterable, Identifiable {
        case everyPage, everyN, ranges
        var id: String { rawValue }
        var title: String {
            switch self {
            case .everyPage: return "One file per page"
            case .everyN: return "Every N pages"
            case .ranges: return "Custom page ranges"
            }
        }
    }

    static func parseRanges(_ text: String, pageCount: Int) -> [ClosedRange<Int>] {
        text.split(separator: ",").compactMap { token in
            let part = token.trimmingCharacters(in: .whitespaces)
            if let dash = part.range(of: "-") {
                let a = Int(part[..<dash.lowerBound].trimmingCharacters(in: .whitespaces)) ?? 1
                let b = Int(part[dash.upperBound...].trimmingCharacters(in: .whitespaces)) ?? pageCount
                let lower = max(1, min(a, b)), upper = min(pageCount, max(a, b))
                return lower <= upper ? lower...upper : nil
            }
            if let single = Int(part), single >= 1, single <= pageCount { return single...single }
            return nil
        }
    }

    static func split(_ url: URL, mode: SplitMode, every: Int, ranges: String, into folder: URL) throws -> [URL] {
        let source = try document(url)
        let count = source.pageCount
        let base = ConversionMatrix.strippedBaseName(url.lastPathComponent)
        var groups: [ClosedRange<Int>] = []
        switch mode {
        case .everyPage:
            groups = (1...max(1, count)).map { $0...$0 }
        case .everyN:
            let n = max(1, every)
            var start = 1
            while start <= count {
                groups.append(start...min(count, start + n - 1))
                start += n
            }
        case .ranges:
            groups = parseRanges(ranges, pageCount: count)
        }
        guard !groups.isEmpty else { throw OpenTangerineError.invalidInput("No valid page ranges.") }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var outputs: [URL] = []
        for (index, group) in groups.enumerated() {
            let part = PDFDocument()
            for pageNumber in group {
                guard let page = source.page(at: pageNumber - 1) else { continue }
                part.insert(page, at: part.pageCount)
            }
            let name = group.count == 1 ? "\(base) page \(group.lowerBound).pdf" : "\(base) pages \(group.lowerBound)-\(group.upperBound).pdf"
            let output = folder.appendingPathComponent(name.isEmpty ? "\(base) part \(index + 1).pdf" : name)
            guard part.write(to: output) else { throw OpenTangerineError.encodeFailed(output.lastPathComponent) }
            outputs.append(output)
        }
        return outputs
    }

    static func compress(_ url: URL, strong: Bool, to destination: URL) throws {
        let source = try document(url)
        var options: [PDFDocumentWriteOption: Any] = [:]
        if #available(macOS 13.4, *) {
            options[.saveImagesAsJPEGOption] = true
            options[.optimizeImagesForScreenOption] = true
        }
        if strong {
            let rendered = PDFDocument()
            for index in 0..<source.pageCount {
                guard let page = source.page(at: index), let image = PDFRenderer.render(page: page, dpi: 110) else { throw OpenTangerineError.encodeFailed("PDF page \(index + 1)") }
                let temp = FileManager.default.temporaryDirectory.appendingPathComponent("opentangerine-pdfpage-\(UUID().uuidString).jpg")
                try ImageIOBridge.write(image, to: temp, format: .jpg, quality: 0.6)
                defer { try? FileManager.default.removeItem(at: temp) }
                if let nsImage = NSImage(contentsOf: temp), let newPage = PDFPage(image: nsImage) {
                    rendered.insert(newPage, at: rendered.pageCount)
                }
            }
            guard rendered.write(to: destination, withOptions: options) else { throw OpenTangerineError.encodeFailed(destination.lastPathComponent) }
            return
        }
        guard source.write(to: destination, withOptions: options) else { throw OpenTangerineError.encodeFailed(destination.lastPathComponent) }
    }

    static func fromImages(_ urls: [URL], to destination: URL, progress: @escaping (Double) -> Void) throws {
        let output = PDFDocument()
        for (index, url) in urls.enumerated() {
            let image = try ImageIOBridge.load(url)
            let nsImage = ImageOps.nsImage(image)
            if let page = PDFPage(image: nsImage) {
                output.insert(page, at: output.pageCount)
            }
            progress(Double(index + 1) / Double(urls.count))
        }
        guard output.pageCount > 0 else { throw OpenTangerineError.invalidInput("No images could be read.") }
        guard output.write(to: destination) else { throw OpenTangerineError.encodeFailed(destination.lastPathComponent) }
    }
}

