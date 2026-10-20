import AppKit
import CoreText
import Foundation

/// Styled documents: web pages and Word files read as styled text, written as PDF or Word,
/// and Word files told back as Markdown, their headings, lists and emphasis included.
enum RichDocument {
    /// HTML to styled text. WebKit does the reading, so this runs on the main thread.
    @MainActor
    static func attributed(html: String, base: URL?) throws -> NSAttributedString {
        var options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
            .documentType: NSAttributedString.DocumentType.html,
            .characterEncoding: String.Encoding.utf8.rawValue,
        ]
        if let base { options[.baseURL] = base }
        do {
            return try NSAttributedString(data: Data(html.utf8), options: options, documentAttributes: nil)
        } catch {
            throw OpenTangerineError.toolFailed("Reading the page", error.localizedDescription)
        }
    }

    static func attributed(docx url: URL) throws -> NSAttributedString {
        do {
            return try NSAttributedString(url: url, options: [.documentType: NSAttributedString.DocumentType.officeOpenXML], documentAttributes: nil)
        } catch {
            throw OpenTangerineError.unreadable(url)
        }
    }

    static func writeDOCX(_ text: NSAttributedString, to url: URL) throws {
        do {
            let data = try text.data(from: NSRange(location: 0, length: text.length), documentAttributes: [.documentType: NSAttributedString.DocumentType.officeOpenXML])
            try data.write(to: url, options: .atomic)
        } catch {
            throw OpenTangerineError.encodeFailed(url.lastPathComponent)
        }
    }

    /// Letter pages with the text typeset across them, styles kept.
    static func writePDF(_ text: NSAttributedString, to url: URL) throws {
        let page = TextRenderer.pageSize, margin = TextRenderer.margin
        guard let consumer = CGDataConsumer(url: url as CFURL) else { throw OpenTangerineError.encodeFailed(url.lastPathComponent) }
        var media = CGRect(origin: .zero, size: page)
        guard let context = CGContext(consumer: consumer, mediaBox: &media, nil) else { throw OpenTangerineError.encodeFailed(url.lastPathComponent) }
        let framesetter = CTFramesetterCreateWithAttributedString(text)
        let box = CGRect(x: margin, y: margin, width: page.width - margin * 2, height: page.height - margin * 2)
        var start = 0
        repeat {
            context.beginPDFPage(nil)
            let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: start, length: 0), CGPath(rect: box, transform: nil), nil)
            context.textMatrix = .identity
            CTFrameDraw(frame, context)
            context.endPDFPage()
            let visible = CTFrameGetVisibleStringRange(frame)
            guard visible.length > 0 else { break }
            start = visible.location + visible.length
        } while start < text.length
        context.closePDF()
    }

    // MARK: Word to Markdown

    /// Headings are told by size (from the size most of the text has), lists by their list
    /// style, emphasis and links by their attributes.
    static func markdown(from text: NSAttributedString) -> String {
        guard text.length > 0 else { return "" }
        var sizes: [CGFloat: Int] = [:]
        text.enumerateAttribute(.font, in: NSRange(location: 0, length: text.length)) { value, range, _ in
            if let font = value as? NSFont { sizes[font.pointSize.rounded(), default: 0] += range.length }
        }
        let body = sizes.max { $0.value < $1.value }?.key ?? 12
        let string = text.string as NSString
        var blocks: [(text: String, isList: Bool)] = []
        var code: [String] = []
        func flushCode() {
            guard !code.isEmpty else { return }
            blocks.append(("```\n" + code.joined(separator: "\n") + "\n```", false))
            code.removeAll()
        }
        string.enumerateSubstrings(in: NSRange(location: 0, length: string.length), options: [.byParagraphs, .substringNotRequired]) { _, range, _, _ in
            guard range.length > 0 else { return }
            let paragraph = text.attributedSubstring(from: range)
            let raw = paragraph.string
            guard !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            let style = paragraph.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
            // Whole paragraphs in a fixed-width font are code, kept line for line.
            var monospaced = true
            paragraph.enumerateAttribute(.font, in: NSRange(location: 0, length: paragraph.length)) { value, _, stop in
                if (value as? NSFont)?.isFixedPitch != true { monospaced = false; stop.pointee = true }
            }
            if monospaced {
                code.append(raw)
                return
            }
            flushCode()
            let marked = raw.range(of: #"^\t([^\t]{1,8})\t"#, options: .regularExpression)
            let indentLevel = max(0, Int(((style?.headIndent ?? 0) / 36).rounded()) - 1)
            if let lists = style?.textLists, lists.isEmpty, let marked, (style?.headIndent ?? 0) > 0 {
                // Lists written as text: a marker between tabs, the depth in the indent.
                let found = raw[marked].trimmingCharacters(in: .whitespaces)
                let marker = found.range(of: #"^\d+[.)]?$"#, options: .regularExpression) != nil ? (found.hasSuffix(".") || found.hasSuffix(")") ? found : found + ".") : "-"
                let offset = raw.distance(from: raw.startIndex, to: marked.upperBound)
                let content = paragraph.attributedSubstring(from: NSRange(location: offset, length: paragraph.length - offset))
                blocks.append((String(repeating: "   ", count: indentLevel) + marker + " " + inline(content), true))
                return
            }
            if let lists = style?.textLists, !lists.isEmpty {
                // The list marker comes as text, between tabs: "\t•\t" or "\t1.\t".
                var content = paragraph
                let numbered: [NSTextList.MarkerFormat] = [.decimal, .decimal, .lowercaseAlpha, .uppercaseAlpha, .lowercaseRoman, .uppercaseRoman, .lowercaseLatin, .uppercaseLatin, .octal]
                var marker = lists.last.map { numbered.contains($0.markerFormat) } == true ? "1." : "-"
                if let match = raw.range(of: #"^\t?([^\t]{1,8})\t"#, options: .regularExpression) {
                    let found = raw[match].trimmingCharacters(in: .whitespaces)
                    if found.range(of: #"^\d+[.)]$"#, options: .regularExpression) != nil { marker = found }
                    content = paragraph.attributedSubstring(from: NSRange(location: raw.distance(from: raw.startIndex, to: match.upperBound), length: paragraph.length - raw.distance(from: raw.startIndex, to: match.upperBound)))
                }
                let indent = String(repeating: "   ", count: lists.count - 1)
                blocks.append((indent + marker + " " + inline(content), true))
                return
            }
            if (style?.headIndent ?? 0) >= 18 || (style?.firstLineHeadIndent ?? 0) >= 18 {
                // An indented paragraph that isn't a list: a quote.
                blocks.append(("> " + inline(paragraph), false))
                return
            }
            let font = paragraph.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
            let size = font?.pointSize ?? body
            let plainText = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            let level: Int? = size >= body * 1.6 ? 1 : size >= body * 1.3 ? 2 : size >= body * 1.1 ? 3 : nil
            if let level {
                blocks.append((String(repeating: "#", count: level) + " " + escape(plainText), false))
            } else {
                blocks.append((inline(paragraph), false))
            }
        }
        flushCode()
        var out = ""
        for (index, block) in blocks.enumerated() {
            if index > 0 { out += block.isList && blocks[index - 1].isList ? "\n" : "\n\n" }
            out += block.text
        }
        return out + "\n"
    }

    private static func inline(_ text: NSAttributedString) -> String {
        var out = ""
        text.enumerateAttributes(in: NSRange(location: 0, length: text.length)) { attributes, range, _ in
            // Word's line breaks arrive as line separators: Markdown writes them as two spaces and a newline.
            var piece = escape((text.string as NSString).substring(with: range).replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "\u{2028}", with: "\u{E002}"))
            let trimmed = piece.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { out += piece; return }
            let leading = piece.hasPrefix(" ") ? " " : "", trailing = piece.hasSuffix(" ") ? " " : ""
            piece = trimmed
            if let font = attributes[.font] as? NSFont {
                let traits = NSFontManager.shared.traits(of: font)
                if font.isFixedPitch { piece = "`\(piece)`" }
                if traits.contains(.italicFontMask) { piece = "*\(piece)*" }
                if traits.contains(.boldFontMask) { piece = "**\(piece)**" }
            }
            if let strike = attributes[.strikethroughStyle] as? Int, strike != 0 { piece = "~~\(piece)~~" }
            if let link = attributes[.link] {
                let target = (link as? URL)?.absoluteString ?? (link as? String) ?? ""
                if !target.isEmpty { piece = "[\(piece)](\(target))" }
            }
            out += leading + piece + trailing
        }
        // Neighbouring runs with the same style meet as "****": join them.
        return out.replacingOccurrences(of: "****", with: "").replacingOccurrences(of: "~~~~", with: "").trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: " *\u{E002} *", with: "  \n", options: .regularExpression)
            .replacingOccurrences(of: #"^☑\s*"#, with: "[x] ", options: .regularExpression)
            .replacingOccurrences(of: #"^☐\s*"#, with: "[ ] ", options: .regularExpression)
    }

    private static func escape(_ text: String) -> String {
        var out = ""
        for character in text {
            if "*_`\\".contains(character) { out.append("\\") }
            out.append(character)
        }
        return out
    }
}
