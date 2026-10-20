import Foundation

/// Web pages (and Markdown, through HTML) as Word documents: headings with Word's heading
/// styles, real numbered and bulleted lists, links, emphasis, code, quotes, tables and pictures.
enum HTMLToDocx {
    static func write(html: String, base: URL?, to destination: URL) async throws {
        let fm = FileManager.default
        let staging = fm.temporaryDirectory.appendingPathComponent("opentangerine-docx-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: staging) }
        for folder in ["_rels", "word/_rels", "word/media"] {
            try fm.createDirectory(at: staging.appendingPathComponent(folder), withIntermediateDirectories: true)
        }
        var builder = Builder(base: base, media: staging.appendingPathComponent("word/media"))
        let root = HTMLToMarkdown.parse(html)
        let body = builder.blocks(contentRoot(root), list: nil)
        let relationships = "<Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles\" Target=\"styles.xml\"/>" + builder.relationships
        var types = ""
        for ext in Set(builder.mediaNames.map { ($0 as NSString).pathExtension.lowercased() }) {
            types += "<Default Extension=\"\(ext)\" ContentType=\"\(ext == "jpg" || ext == "jpeg" ? "image/jpeg" : "image/\(ext)")\"/>"
        }
        try await DocxWriter.package(body: body.isEmpty ? "<w:p/>" : body, relationships: relationships, contentTypesExtra: types, numbering: builder.numbering, staging: staging, media: builder.mediaNames.map { "word/media/\($0)" }, to: destination)
    }

    private static func contentRoot(_ root: HTMLToMarkdown.Node) -> HTMLToMarkdown.Node {
        func find(_ node: HTMLToMarkdown.Node) -> HTMLToMarkdown.Node? {
            if node.tag == "body" { return node }
            for child in node.children { if let found = find(child) { return found } }
            return nil
        }
        return find(root) ?? root
    }

    private struct Style {
        var bold = false, italic = false, strike = false, code = false, link: String?
        /// In half points; set on headings so readers that skip Word's styles still see them.
        var size: Int?
    }

    private static let headingSizes = [40, 32, 27, 25, 23, 22]

    private struct ListContext {
        let num: Int
        let level: Int
    }

    private struct Builder {
        let base: URL?
        let media: URL
        var relationships = ""
        var mediaNames: [String] = []
        private var nextRelationship = 10
        private var nextPicture = 1
        private var lists: [(num: Int, ordered: Bool, start: Int)] = []

        init(base: URL?, media: URL) {
            self.base = base
            self.media = media
        }

        private static let blockTags: Set<String> = ["p", "div", "h1", "h2", "h3", "h4", "h5", "h6", "ul", "ol", "pre", "blockquote", "hr", "table", "section", "article", "header", "footer", "nav", "main", "figure", "figcaption", "dl", "dt", "dd", "address", "aside", "details", "summary", "li", "body", "html"]
        private static let skipped: Set<String> = ["head", "script", "style", "title", "meta", "link", "noscript", "template", "button", "select", "svg", "iframe"]

        /// Two abstract lists (bullets, numbers), and one numbering per list so each restarts.
        var numbering: String? {
            guard !lists.isEmpty else { return nil }
            func levels(ordered: Bool) -> String {
                (0..<6).map { level in
                    let indent = 720 * (level + 1)
                    let format = ordered ? ["decimal", "lowerLetter", "lowerRoman"][level % 3] : "bullet"
                    let text = ordered ? "%\(level + 1)." : ["•", "◦", "▪"][level % 3]
                    return "<w:lvl w:ilvl=\"\(level)\"><w:start w:val=\"1\"/><w:numFmt w:val=\"\(format)\"/><w:lvlText w:val=\"\(text)\"/><w:lvlJc w:val=\"left\"/><w:pPr><w:ind w:left=\"\(indent)\" w:hanging=\"360\"/></w:pPr></w:lvl>"
                }.joined()
            }
            var xml = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><w:numbering xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\">"
            xml += "<w:abstractNum w:abstractNumId=\"0\"><w:multiLevelType w:val=\"hybridMultilevel\"/>\(levels(ordered: false))</w:abstractNum>"
            xml += "<w:abstractNum w:abstractNumId=\"1\"><w:multiLevelType w:val=\"hybridMultilevel\"/>\(levels(ordered: true))</w:abstractNum>"
            for list in lists {
                xml += "<w:num w:numId=\"\(list.num)\"><w:abstractNumId w:val=\"\(list.ordered ? 1 : 0)\"/>"
                if list.ordered { xml += "<w:lvlOverride w:ilvl=\"0\"><w:startOverride w:val=\"\(list.start)\"/></w:lvlOverride>" }
                xml += "</w:num>"
            }
            return xml + "</w:numbering>"
        }

        mutating func blocks(_ node: HTMLToMarkdown.Node, list: ListContext?) -> String {
            var out = ""
            var run: [HTMLToMarkdown.Node] = []
            func flush(_ builder: inout Builder) {
                let runs = builder.runs(run, style: Style())
                if !runs.isEmpty { out += builder.paragraph(runs, style: nil, list: list) }
                run.removeAll()
            }
            for child in node.children {
                if Self.skipped.contains(child.tag) { continue }
                if !child.isText, Self.blockTags.contains(child.tag) {
                    flush(&self)
                    out += block(child, list: list)
                } else {
                    run.append(child)
                }
            }
            flush(&self)
            return out
        }

        private mutating func block(_ node: HTMLToMarkdown.Node, list: ListContext?) -> String {
            switch node.tag {
            case "h1", "h2", "h3", "h4", "h5", "h6":
                let level = Int(node.tag.dropFirst()) ?? 1
                return paragraph(runs(node.children, style: Style(bold: true, size: HTMLToDocx.headingSizes[level - 1])), style: "Heading\(level)", list: nil)
            case "p", "dt", "dd", "figcaption", "summary", "address":
                return paragraph(runs(node.children, style: Style()), style: nil, list: list)
            case "hr":
                return "<w:p><w:pPr><w:pBdr><w:bottom w:val=\"single\" w:sz=\"6\" w:space=\"1\" w:color=\"BBBBBB\"/></w:pBdr></w:pPr></w:p>"
            case "pre":
                let text = HTMLToMarkdown.Writer.rawText(node).trimmingCharacters(in: .newlines)
                return text.components(separatedBy: "\n").map { line in
                    "<w:p><w:pPr><w:pStyle w:val=\"Code\"/></w:pPr><w:r><w:rPr><w:rFonts w:ascii=\"Menlo\" w:hAnsi=\"Menlo\"/><w:sz w:val=\"19\"/></w:rPr><w:t xml:space=\"preserve\">\(DocxWriter.escape(line))</w:t></w:r></w:p>"
                }.joined()
            case "blockquote":
                return blocks(node, list: nil)
                    .replacingOccurrences(of: #"<w:p><w:pPr>(?!<w:pStyle)"#, with: "<w:p><w:pPr><w:pStyle w:val=\"Quote\"/>", options: .regularExpression)
                    .replacingOccurrences(of: "<w:p><w:r>", with: "<w:p><w:pPr><w:pStyle w:val=\"Quote\"/><w:ind w:left=\"360\"/></w:pPr><w:r>")
                    .replacingOccurrences(of: "<w:p><w:hyperlink", with: "<w:p><w:pPr><w:pStyle w:val=\"Quote\"/><w:ind w:left=\"360\"/></w:pPr><w:hyperlink")
            case "ul", "ol":
                let ordered = node.tag == "ol"
                let level = list.map { $0.level + 1 } ?? 0
                let num = lists.count + 1
                lists.append((num, ordered, Int(node.attributes["start"] ?? "") ?? 1))
                var out = ""
                for item in node.children where item.tag == "li" {
                    out += blocks(item, list: ListContext(num: num, level: min(level, 5)))
                }
                return out
            case "table":
                return table(node)
            case "li":
                return blocks(node, list: list)
            default:
                return blocks(node, list: list)
            }
        }

        private func paragraph(_ runs: String, style: String?, list: ListContext?) -> String {
            guard !runs.isEmpty else { return "" }
            var properties = ""
            if let style { properties += "<w:pStyle w:val=\"\(style)\"/>" }
            if let list {
                if style == nil { properties += "<w:pStyle w:val=\"ListParagraph\"/>" }
                properties += "<w:numPr><w:ilvl w:val=\"\(list.level)\"/><w:numId w:val=\"\(list.num)\"/></w:numPr>"
            }
            return "<w:p>" + (properties.isEmpty ? "" : "<w:pPr>\(properties)</w:pPr>") + runs + "</w:p>"
        }

        private mutating func table(_ node: HTMLToMarkdown.Node) -> String {
            var rows: [(cells: [HTMLToMarkdown.Node], header: Bool)] = []
            func collect(_ n: HTMLToMarkdown.Node, head: Bool) {
                for child in n.children {
                    switch child.tag {
                    case "thead": collect(child, head: true)
                    case "tbody", "tfoot": collect(child, head: false)
                    case "tr": rows.append((child.children.filter { $0.tag == "td" || $0.tag == "th" }, head))
                    default: collect(child, head: head)
                    }
                }
            }
            collect(node, head: false)
            let columns = rows.map(\.cells.count).max() ?? 0
            guard columns > 0 else { return "" }
            var out = "<w:tbl><w:tblPr><w:tblStyle w:val=\"TableGrid\"/><w:tblW w:w=\"0\" w:type=\"auto\"/></w:tblPr><w:tblGrid>"
            out += String(repeating: "<w:gridCol w:w=\"\(9360 / columns)\"/>", count: columns) + "</w:tblGrid>"
            for row in rows {
                out += "<w:tr>"
                for index in 0..<columns {
                    var cellRuns = ""
                    var align = ""
                    if index < row.cells.count {
                        let cell = row.cells[index]
                        var style = Style()
                        style.bold = row.header || cell.tag == "th"
                        cellRuns = runs(cell.children, style: style)
                        let css = (cell.attributes["style"] ?? "").replacingOccurrences(of: " ", with: "")
                        if css.contains("text-align:right") || cell.attributes["align"] == "right" { align = "<w:jc w:val=\"right\"/>" }
                        if css.contains("text-align:center") || cell.attributes["align"] == "center" { align = "<w:jc w:val=\"center\"/>" }
                    }
                    out += "<w:tc><w:tcPr><w:tcW w:w=\"\(9360 / columns)\" w:type=\"dxa\"/></w:tcPr><w:p>" + (align.isEmpty ? "" : "<w:pPr>\(align)</w:pPr>") + cellRuns + "</w:p></w:tc>"
                }
                out += "</w:tr>"
            }
            return out + "</w:tbl><w:p/>"
        }

        /// Inline content as Word runs, styles nested as in the page.
        private mutating func runs(_ nodes: [HTMLToMarkdown.Node], style: Style) -> String {
            var out = ""
            var pendingSpace = false
            for (index, node) in nodes.enumerated() {
                if node.isText {
                    var text = node.text.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                    if index == 0 { text = String(text.drop(while: { $0 == " " })) }
                    if index == nodes.count - 1 { text = String(text.reversed().drop(while: { $0 == " " }).reversed()) }
                    if pendingSpace, text.hasPrefix(" ") { text.removeFirst() }
                    guard !text.isEmpty else { continue }
                    out += run(text, style: style)
                    pendingSpace = text.hasSuffix(" ")
                    continue
                }
                defer { pendingSpace = false }
                if Self.skipped.contains(node.tag) { continue }
                var inner = style
                switch node.tag {
                case "br": out += "<w:r><w:br/></w:r>"; continue
                case "strong", "b": inner.bold = true
                case "em", "i", "cite": inner.italic = true
                case "del", "s", "strike": inner.strike = true
                case "code", "kbd", "samp":
                    inner.code = true
                    out += run(HTMLToMarkdown.Writer.rawText(node), style: inner)
                    continue
                case "img":
                    out += picture(node)
                    continue
                case "input":
                    if node.attributes["type"] == "checkbox" { out += run(node.attributes["checked"] != nil ? "☑" : "☐", style: style) }
                    continue
                case "a":
                    if let href = node.attributes["href"], !href.isEmpty, !href.hasPrefix("javascript:") {
                        let id = "rId\(nextRelationship)"
                        nextRelationship += 1
                        relationships += "<Relationship Id=\"\(id)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/hyperlink\" Target=\"\(DocxWriter.escape(href))\" TargetMode=\"External\"/>"
                        inner.link = id
                        out += "<w:hyperlink r:id=\"\(id)\">" + runs(node.children, style: inner) + "</w:hyperlink>"
                        continue
                    }
                default: break
                }
                out += runs(node.children, style: inner)
            }
            return out
        }

        private func run(_ text: String, style: Style) -> String {
            var properties = ""
            if style.link != nil { properties += "<w:rStyle w:val=\"Hyperlink\"/>" } else if style.code { properties += "<w:rStyle w:val=\"InlineCode\"/>" }
            if style.code { properties += "<w:rFonts w:ascii=\"Menlo\" w:hAnsi=\"Menlo\"/>" }
            if style.bold { properties += "<w:b/>" }
            if style.italic { properties += "<w:i/>" }
            if style.strike { properties += "<w:strike/>" }
            if style.link != nil { properties += "<w:color w:val=\"0563C1\"/><w:u w:val=\"single\"/>" }
            if let size = style.size { properties += "<w:sz w:val=\"\(size)\"/>" } else if style.code { properties += "<w:sz w:val=\"19\"/>" }
            return "<w:r>" + (properties.isEmpty ? "" : "<w:rPr>\(properties)</w:rPr>") + "<w:t xml:space=\"preserve\">\(DocxWriter.escape(text))</w:t></w:r>"
        }

        /// A picture next to the page (or a web address): embedded when it can be read here.
        private mutating func picture(_ node: HTMLToMarkdown.Node) -> String {
            let alt = node.attributes["alt"] ?? ""
            guard let src = node.attributes["src"]?.removingPercentEncoding, !src.isEmpty,
                  let file = src.hasPrefix("/") ? URL(fileURLWithPath: src) : (src.contains("://") ? URL(string: src).flatMap { $0.isFileURL ? $0 : nil } : base?.appendingPathComponent(src)),
                  FileManager.default.fileExists(atPath: file.path) else {
                return alt.isEmpty ? "" : run("[\(alt)]", style: Style())
            }
            let ext = file.pathExtension.lowercased()
            guard ["png", "jpg", "jpeg", "gif"].contains(ext) else { return alt.isEmpty ? "" : run("[\(alt)]", style: Style()) }
            let name = "image\(nextPicture).\(ext)"
            guard (try? FileManager.default.copyItem(at: file, to: media.appendingPathComponent(name))) != nil else { return "" }
            let id = "rId\(nextRelationship)"
            nextRelationship += 1
            relationships += "<Relationship Id=\"\(id)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/image\" Target=\"media/\(name)\"/>"
            mediaNames.append(name)
            let size = ImageIOBridge.pixelSize(file)
            var cx = max(size.width, 1) * 9525, cy = max(size.height, 1) * 9525
            let scale = min(5_943_600 / cx, 8_229_600 / cy, 1)
            cx *= scale; cy *= scale
            let number = nextPicture
            nextPicture += 1
            // The drawing markup is a whole paragraph; keep only its run here.
            let drawing = DocxWriter.drawing(rid: id, id: number, name: name, cx: Int(cx), cy: Int(cy))
            return drawing.replacingOccurrences(of: "<w:p>", with: "").replacingOccurrences(of: "</w:p>", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
}
