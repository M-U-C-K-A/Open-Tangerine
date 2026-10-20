import Foundation

/// Markdown to HTML: headings, paragraphs, emphasis, links, images, lists (nested, numbered,
/// task lists), quotes, code (inline, fenced, indented), rules and tables, as GitHub writes them.
enum Markdown {
    /// A whole page, readable as it is, titled after the first heading.
    static func document(_ markdown: String, title fallback: String) -> String {
        let body = html(markdown)
        let title = firstHeading(markdown) ?? fallback
        return """
        <!doctype html>
        <html lang="en">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>\(escape(title))</title>
        <style>
        body { font: 16px/1.6 -apple-system, BlinkMacSystemFont, "Segoe UI", Helvetica, Arial, sans-serif; max-width: 46rem; margin: 2rem auto; padding: 0 1rem; color: #1d1d1f; }
        h1, h2, h3 { line-height: 1.25; }
        pre { background: #f5f5f7; padding: .8rem 1rem; border-radius: 8px; overflow: auto; }
        code { font-family: ui-monospace, SFMono-Regular, Menlo, monospace; font-size: .9em; }
        :not(pre) > code { background: #f2f2f4; padding: .1em .3em; border-radius: 4px; }
        blockquote { margin: 0; padding-left: 1rem; border-left: 3px solid #ddd; color: #555; }
        table { border-collapse: collapse; }
        th, td { border: 1px solid #ddd; padding: .35rem .6rem; }
        img { max-width: 100%; }
        </style>
        </head>
        <body>
        \(body)</body>
        </html>

        """
    }

    static func firstHeading(_ markdown: String) -> String? {
        for line in markdown.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("# ") { return String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces) }
        }
        return nil
    }

    /// The body: one HTML element per block.
    static func html(_ markdown: String) -> String {
        let lines = markdown.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\t", with: "    ")
            .components(separatedBy: "\n")
        return blocks(lines)
    }

    // MARK: Blocks

    private static func blocks(_ lines: [String]) -> String {
        var out = ""
        var i = 0
        while i < lines.count {
            let line = lines[i]
            if isBlank(line) { i += 1; continue }

            if let fence = fenceOpening(line) {
                var code: [String] = []
                i += 1
                while i < lines.count, !isFenceClosing(lines[i], fence: fence.marker) {
                    code.append(removeIndent(lines[i], upTo: fence.indent))
                    i += 1
                }
                i += 1
                let language = fence.language.isEmpty ? "" : " class=\"language-\(escape(fence.language))\""
                out += "<pre><code\(language)>\(escape(code.joined(separator: "\n")))\(code.isEmpty ? "" : "\n")</code></pre>\n"
                continue
            }
            if let heading = atxHeading(line) {
                out += "<h\(heading.level)>\(inline(heading.text))</h\(heading.level)>\n"
                i += 1
                continue
            }
            if isRule(line) {
                out += "<hr>\n"
                i += 1
                continue
            }
            if leadingSpaces(line) >= 4 {
                var code: [String] = []
                while i < lines.count, isBlank(lines[i]) || leadingSpaces(lines[i]) >= 4 {
                    code.append(removeIndent(lines[i], upTo: 4))
                    i += 1
                }
                while code.last.map(isBlank) == true { code.removeLast() }
                out += "<pre><code>\(escape(code.joined(separator: "\n")))\n</code></pre>\n"
                continue
            }
            if quoteContent(line) != nil {
                var inner: [String] = []
                while i < lines.count {
                    if let content = quoteContent(lines[i]) {
                        inner.append(content)
                    } else if !isBlank(lines[i]), let last = inner.last, !isBlank(last), !startsBlock(lines[i]) {
                        inner.append(lines[i]) // A lazy continuation of the quoted paragraph.
                    } else {
                        break
                    }
                    i += 1
                }
                out += "<blockquote>\n\(blocks(inner))</blockquote>\n"
                continue
            }
            if let marker = listMarker(line) {
                let (html, next) = list(lines, from: i, first: marker)
                out += html
                i = next
                continue
            }
            if i + 1 < lines.count, line.contains("|"), let alignments = tableDelimiter(lines[i + 1]) {
                let header = cells(line)
                if header.count == alignments.count {
                    var rows: [[String]] = []
                    i += 2
                    while i < lines.count, !isBlank(lines[i]), lines[i].contains("|") {
                        rows.append(cells(lines[i]))
                        i += 1
                    }
                    out += table(header: header, alignments: alignments, rows: rows)
                    continue
                }
            }
            if isHTMLBlock(line) {
                var raw: [String] = []
                while i < lines.count, !isBlank(lines[i]) {
                    raw.append(lines[i])
                    i += 1
                }
                out += raw.joined(separator: "\n") + "\n"
                continue
            }

            // A paragraph, until a blank line or another block; === or --- under it makes a heading.
            var paragraph: [String] = [line]
            i += 1
            var setext = 0
            while i < lines.count, !isBlank(lines[i]) {
                let next = lines[i]
                let trimmed = next.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty, trimmed.allSatisfy({ $0 == "=" }) { setext = 1; i += 1; break }
                if !trimmed.isEmpty, trimmed.allSatisfy({ $0 == "-" }), leadingSpaces(next) < 4 { setext = 2; i += 1; break }
                if startsBlock(next) { break }
                paragraph.append(next)
                i += 1
            }
            let text = paragraph.map { String($0.drop(while: { $0 == " " })) }.joined(separator: "\n")
            if setext > 0 {
                out += "<h\(setext)>\(inline(text))</h\(setext)>\n"
            } else {
                out += "<p>\(inline(text))</p>\n"
            }
        }
        return out
    }

    private struct ListMarker {
        let ordered: Bool
        let start: Int
        let bullet: Character
        let indent: Int
        /// Where the item's text starts: what its continuation lines are indented to.
        let contentIndent: Int
        let rest: String
    }

    private static func listMarker(_ line: String) -> ListMarker? {
        let indent = leadingSpaces(line)
        guard indent < 4 else { return nil }
        let body = line.dropFirst(indent)
        if let first = body.first, "-*+".contains(first) {
            let after = body.dropFirst()
            guard after.isEmpty || after.first == " " else { return nil }
            let spaces = min(4, after.prefix(while: { $0 == " " }).count)
            return ListMarker(ordered: false, start: 1, bullet: first, indent: indent, contentIndent: indent + 1 + max(1, spaces), rest: String(after.dropFirst(spaces)))
        }
        let digits = body.prefix(while: \.isNumber)
        guard !digits.isEmpty, digits.count <= 9 else { return nil }
        let after = body.dropFirst(digits.count)
        guard let delimiter = after.first, delimiter == "." || delimiter == ")" else { return nil }
        let tail = after.dropFirst()
        guard tail.isEmpty || tail.first == " " else { return nil }
        let spaces = min(4, tail.prefix(while: { $0 == " " }).count)
        return ListMarker(ordered: true, start: Int(digits) ?? 1, bullet: delimiter, indent: indent, contentIndent: indent + digits.count + 1 + max(1, spaces), rest: String(tail.dropFirst(spaces)))
    }

    private static func list(_ lines: [String], from start: Int, first: ListMarker) -> (String, Int) {
        var items: [[String]] = []
        var loose = false
        var i = start
        var marker: ListMarker? = first
        while let current = marker {
            var item = [current.rest]
            i += 1
            var sawBlank = false
            while i < lines.count {
                let line = lines[i]
                if isBlank(line) { sawBlank = true; item.append(""); i += 1; continue }
                if leadingSpaces(line) >= current.contentIndent {
                    if sawBlank { loose = true }
                    sawBlank = false
                    item.append(removeIndent(line, upTo: current.contentIndent))
                    i += 1
                    continue
                }
                if !sawBlank, listMarker(line) == nil, !startsBlock(line) {
                    item.append(line.trimmingCharacters(in: .whitespaces)) // Lazy continuation.
                    i += 1
                    continue
                }
                break
            }
            while item.last.map(isBlank) == true { item.removeLast() }
            items.append(item)
            marker = nil
            if i < lines.count, let next = listMarker(lines[i]), next.ordered == first.ordered, next.indent < first.contentIndent, (first.ordered || next.bullet == first.bullet) {
                if sawBlank { loose = true }
                marker = next
            }
        }
        let tag = first.ordered ? "ol" : "ul"
        let startAttribute = first.ordered && first.start != 1 ? " start=\"\(first.start)\"" : ""
        var out = "<\(tag)\(startAttribute)>\n"
        for item in items {
            var content = item
            var checkbox = ""
            if let head = content.first, let task = taskBox(head) {
                checkbox = "<input type=\"checkbox\" disabled\(task.checked ? " checked" : "")> "
                content[0] = task.rest
            }
            var inner = blocks(content)
            if !loose {
                // Tight lists keep their text bare, without paragraphs.
                inner = inner.replacingOccurrences(of: #"<p>([\s\S]*?)</p>\n"#, with: "$1\n", options: .regularExpression)
            }
            inner = inner.trimmingCharacters(in: .newlines)
            out += "<li>\(checkbox)\(inner)</li>\n"
        }
        return (out + "</\(tag)>\n", i)
    }

    private static func taskBox(_ text: String) -> (checked: Bool, rest: String)? {
        for (prefix, checked) in [("[ ] ", false), ("[x] ", true), ("[X] ", true)] where text.hasPrefix(prefix) {
            return (checked, String(text.dropFirst(prefix.count)))
        }
        return nil
    }

    private static func table(header: [String], alignments: [String?], rows: [[String]]) -> String {
        func cell(_ tag: String, _ text: String, _ column: Int) -> String {
            let align = column < alignments.count ? alignments[column].map { " style=\"text-align: \($0)\"" } ?? "" : ""
            return "<\(tag)\(align)>\(inline(text))</\(tag)>"
        }
        var out = "<table>\n<thead>\n<tr>" + header.enumerated().map { cell("th", $0.element, $0.offset) }.joined() + "</tr>\n</thead>\n"
        if !rows.isEmpty {
            out += "<tbody>\n"
            for row in rows {
                let padded = (0..<header.count).map { $0 < row.count ? row[$0] : "" }
                out += "<tr>" + padded.enumerated().map { cell("td", $0.element, $0.offset) }.joined() + "</tr>\n"
            }
            out += "</tbody>\n"
        }
        return out + "</table>\n"
    }

    private static func cells(_ line: String) -> [String] {
        var text = line.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("|") { text.removeFirst() }
        if text.hasSuffix("|"), !text.hasSuffix("\\|") { text.removeLast() }
        var result: [String] = [], current = ""
        var previous: Character = " "
        for character in text {
            if character == "|", previous != "\\" {
                result.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
            } else {
                current.append(character)
            }
            previous = character
        }
        result.append(current.trimmingCharacters(in: .whitespaces))
        return result.map { $0.replacingOccurrences(of: "\\|", with: "|") }
    }

    private static func tableDelimiter(_ line: String) -> [String?]? {
        let parts = cells(line)
        guard !parts.isEmpty else { return nil }
        var alignments: [String?] = []
        for part in parts {
            guard !part.isEmpty, part.allSatisfy({ "-:".contains($0) }), part.contains("-") else { return nil }
            switch (part.hasPrefix(":"), part.hasSuffix(":")) {
            case (true, true): alignments.append("center")
            case (false, true): alignments.append("right")
            case (true, false): alignments.append("left")
            default: alignments.append(nil)
            }
        }
        return alignments
    }

    private static func startsBlock(_ line: String) -> Bool {
        atxHeading(line) != nil || fenceOpening(line) != nil || quoteContent(line) != nil || isRule(line) || isHTMLBlock(line)
            || (listMarker(line).map { !$0.rest.isEmpty } ?? false)
    }

    private static func atxHeading(_ line: String) -> (level: Int, text: String)? {
        let indent = leadingSpaces(line)
        guard indent < 4 else { return nil }
        let body = line.dropFirst(indent)
        let hashes = body.prefix(while: { $0 == "#" }).count
        guard (1...6).contains(hashes) else { return nil }
        let rest = body.dropFirst(hashes)
        guard rest.isEmpty || rest.first == " " else { return nil }
        var text = rest.trimmingCharacters(in: .whitespaces)
        // A closing run of #s is decoration.
        if let range = text.range(of: #"\s+#+$"#, options: .regularExpression) { text.removeSubrange(range) } else if text.allSatisfy({ $0 == "#" }) { text = "" }
        return (hashes, text)
    }

    private static func isRule(_ line: String) -> Bool {
        guard leadingSpaces(line) < 4 else { return false }
        let compact = line.filter { $0 != " " }
        guard compact.count >= 3, let first = compact.first, "-*_".contains(first) else { return false }
        return compact.allSatisfy { $0 == first }
    }

    private static func fenceOpening(_ line: String) -> (marker: String, language: String, indent: Int)? {
        let indent = leadingSpaces(line)
        guard indent < 4 else { return nil }
        let body = line.dropFirst(indent)
        guard let first = body.first, first == "`" || first == "~" else { return nil }
        let count = body.prefix(while: { $0 == first }).count
        guard count >= 3 else { return nil }
        let info = body.dropFirst(count).trimmingCharacters(in: .whitespaces)
        if first == "`", info.contains("`") { return nil }
        return (String(repeating: first, count: count), String(info.split(separator: " ").first ?? ""), indent)
    }

    private static func isFenceClosing(_ line: String, fence: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard let first = fence.first, trimmed.hasPrefix(fence) else { return false }
        return trimmed.allSatisfy { $0 == first }
    }

    private static func quoteContent(_ line: String) -> String? {
        let indent = leadingSpaces(line)
        guard indent < 4 else { return nil }
        let body = line.dropFirst(indent)
        guard body.first == ">" else { return nil }
        let rest = body.dropFirst()
        return String(rest.first == " " ? rest.dropFirst() : rest)
    }

    private static let blockTags: Set<String> = ["div", "table", "pre", "p", "section", "article", "aside", "header", "footer", "nav", "figure", "details", "ul", "ol", "dl", "blockquote", "h1", "h2", "h3", "h4", "h5", "h6", "hr", "form", "iframe", "video", "audio", "!--"]

    private static func isHTMLBlock(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("<") else { return false }
        if trimmed.hasPrefix("<!--") { return true }
        let name = trimmed.dropFirst().drop(while: { $0 == "/" }).prefix(while: { $0.isLetter || $0.isNumber }).lowercased()
        return blockTags.contains(name)
    }

    private static func isBlank(_ line: String) -> Bool { line.allSatisfy { $0 == " " } }

    private static func leadingSpaces(_ line: String) -> Int { line.prefix(while: { $0 == " " }).count }

    private static func removeIndent(_ line: String, upTo count: Int) -> String {
        String(line.dropFirst(min(count, leadingSpaces(line))))
    }

    // MARK: Inline

    /// Emphasis, links, images, code and breaks within a block's text.
    static func inline(_ text: String) -> String {
        var tokens: [String] = []
        func hold(_ html: String) -> String {
            tokens.append(html)
            return "\u{E000}\(tokens.count - 1)\u{E001}"
        }
        func replace(_ pattern: String, in source: String, _ make: ([String]) -> String) -> String {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return source }
            var result = ""
            var last = source.startIndex
            for match in regex.matches(in: source, range: NSRange(source.startIndex..., in: source)) {
                guard let range = Range(match.range, in: source) else { continue }
                result += source[last..<range.lowerBound]
                let groups = (0..<match.numberOfRanges).map { index -> String in
                    Range(match.range(at: index), in: source).map { String(source[$0]) } ?? ""
                }
                result += make(groups)
                last = range.upperBound
            }
            return result + source[last...]
        }

        var s = text
        // Code spans first: nothing inside them is Markdown.
        s = replace(#"(`+)(?!`)([\s\S]*?[^`])\1(?!`)"#, in: s) { groups in
            var code = groups[2].replacingOccurrences(of: "\n", with: " ")
            if code.hasPrefix(" "), code.hasSuffix(" "), code.count > 2 { code = String(code.dropFirst().dropLast()) }
            return hold("<code>\(escape(code))</code>")
        }
        // Hard breaks: two spaces or a backslash at the end of a line.
        s = replace(#"(?: {2,}|\\)\n"#, in: s) { _ in hold("<br>\n") }
        s = replace(##"\\([!"#$%&'()*+,\-./:;<=>?@\[\\\]^_`{|}~])"##, in: s) { groups in hold(escape(groups[1])) }
        s = replace(#"<((?:https?|ftp|mailto):[^\s>]+|[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,})>"#, in: s) { groups in
            let target = groups[1].contains("@") && !groups[1].contains(":") ? "mailto:\(groups[1])" : groups[1]
            return hold("<a href=\"\(escape(target))\">\(escape(groups[1]))</a>")
        }
        s = replace(#"</?[A-Za-z][A-Za-z0-9-]*(?:\s+[^<>]*)?/?>"#, in: s) { groups in hold(groups[0]) }
        s = replace(#"!\[([^\]]*)\]\(\s*<?([^)\s>]*)>?(?:\s+"([^"]*)")?\s*\)"#, in: s) { groups in
            let title = groups[3].isEmpty ? "" : " title=\"\(escape(groups[3]))\""
            return hold("<img src=\"\(escape(groups[2]))\" alt=\"\(escape(groups[1]))\"\(title)>")
        }
        s = replace(#"\[((?:[^\[\]]|\[[^\]]*\])+)\]\(\s*<?([^)\s>]*)>?(?:\s+"([^"]*)")?\s*\)"#, in: s) { groups in
            let title = groups[3].isEmpty ? "" : " title=\"\(escape(groups[3]))\""
            return hold("<a href=\"\(escape(groups[2]))\"\(title)>\(inline(groups[1]))</a>")
        }
        // Bare web addresses become links too, as on GitHub.
        s = replace(#"(?<![\w"=/])(https?://[^\s<]+[^\s<.,:;"')\]])"#, in: s) { groups in
            hold("<a href=\"\(escape(groups[1]))\">\(escape(groups[1]))</a>")
        }
        s = escape(s)
        s = replace(#"\*\*\*(?=\S)([\s\S]+?)(?<=\S)\*\*\*"#, in: s) { "<strong><em>\($0[1])</em></strong>" }
        s = replace(#"\*\*(?=\S)([\s\S]+?)(?<=\S)\*\*"#, in: s) { "<strong>\($0[1])</strong>" }
        s = replace(#"(?<![\w_])__(?=\S)([\s\S]+?)(?<=\S)__(?![\w_])"#, in: s) { "<strong>\($0[1])</strong>" }
        s = replace(#"\*(?=[^\s*])([\s\S]+?)(?<=[^\s*])\*"#, in: s) { "<em>\($0[1])</em>" }
        s = replace(#"(?<![\w_])_(?=[^\s_])([\s\S]+?)(?<=[^\s_])_(?![\w_])"#, in: s) { "<em>\($0[1])</em>" }
        s = replace(#"~~(?=\S)([\s\S]+?)(?<=\S)~~"#, in: s) { "<del>\($0[1])</del>" }
        // Put back what was held, innermost last.
        while s.contains("\u{E000}") {
            s = replace("\u{E000}(\\d+)\u{E001}", in: s) { groups in tokens[Int(groups[1]) ?? 0] }
        }
        return s
    }

    static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}

/// HTML to Markdown, or to plain text: the page is read into a tree first (forgiving, as
/// browsers are), then written back block by block.
enum HTMLToMarkdown {
    final class Node {
        let tag: String
        var attributes: [String: String]
        var children: [Node] = []
        var text: String
        weak var parent: Node?

        init(tag: String, attributes: [String: String] = [:], text: String = "") {
            self.tag = tag
            self.attributes = attributes
            self.text = text
        }

        var isText: Bool { tag == "#text" }
    }

    static func markdown(_ html: String) -> String {
        let root = parse(html)
        return tidy(Writer(plain: false).blocks(contentRoot(root)))
    }

    static func text(_ html: String) -> String {
        let root = parse(html)
        return tidy(Writer(plain: true).blocks(contentRoot(root)))
    }

    /// The page's title, if it has one.
    static func title(_ html: String) -> String? {
        func find(_ node: Node) -> Node? {
            if node.tag == "title" { return node }
            for child in node.children { if let found = find(child) { return found } }
            return nil
        }
        return find(parse(html)).map { Writer.rawText($0).trimmingCharacters(in: .whitespacesAndNewlines) }.flatMap { $0.isEmpty ? nil : $0 }
    }

    private static func contentRoot(_ root: Node) -> Node {
        func find(_ node: Node, _ tag: String) -> Node? {
            if node.tag == tag { return node }
            for child in node.children { if let found = find(child, tag) { return found } }
            return nil
        }
        return find(root, "body") ?? root
    }

    private static func tidy(_ text: String) -> String {
        let collapsed = text.replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
        let lines = collapsed.components(separatedBy: "\n").map { line -> String in
            // Keep Markdown's hard breaks; drop other trailing spaces.
            line.hasSuffix("  ") && !line.trimmingCharacters(in: .whitespaces).isEmpty ? line : line.replacingOccurrences(of: #"\s+$"#, with: "", options: .regularExpression)
        }
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
    }

    // MARK: Parsing

    private static let voids: Set<String> = ["br", "hr", "img", "input", "meta", "link", "source", "col", "area", "base", "wbr", "embed", "param", "track"]
    private static let rawText: Set<String> = ["script", "style", "textarea", "title"]
    private static let closesParagraph: Set<String> = ["p", "div", "ul", "ol", "table", "h1", "h2", "h3", "h4", "h5", "h6", "pre", "blockquote", "hr", "section", "article", "header", "footer", "nav", "figure", "dl", "form", "aside", "details", "main", "address"]

    static func parse(_ html: String) -> Node {
        let root = Node(tag: "#root")
        var current = root
        let s = Array(html.unicodeScalars)
        var i = 0
        var text = ""

        func flushText() {
            guard !text.isEmpty else { return }
            let node = Node(tag: "#text", text: decode(text))
            node.parent = current
            current.children.append(node)
            text = ""
        }
        func isOpen(_ tag: String) -> Bool {
            var node: Node? = current
            while let n = node, n.tag != "#root" {
                if n.tag == tag { return true }
                node = n.parent
            }
            return false
        }
        func close(_ tag: String) {
            guard isOpen(tag) else { return }
            while current.tag != tag, let parent = current.parent { current = parent }
            if let parent = current.parent { current = parent }
        }
        func matches(_ string: String, at index: Int) -> Bool {
            let pattern = Array(string.unicodeScalars)
            guard index + pattern.count <= s.count else { return false }
            for (offset, scalar) in pattern.enumerated() where String(s[index + offset]).lowercased() != String(scalar) { return false }
            return true
        }

        while i < s.count {
            if s[i] == "<" {
                if matches("<!--", at: i) {
                    flushText()
                    var j = i + 4
                    while j < s.count, !matches("-->", at: j) { j += 1 }
                    i = min(s.count, j + 3)
                    continue
                }
                if i + 1 < s.count, s[i + 1] == "!" || s[i + 1] == "?" {
                    flushText()
                    while i < s.count, s[i] != ">" { i += 1 }
                    i += 1
                    continue
                }
                let closing = i + 1 < s.count && s[i + 1] == "/"
                var j = i + (closing ? 2 : 1)
                var name = ""
                while j < s.count, CharacterSet.alphanumerics.contains(s[j]) || s[j] == "-" { name.unicodeScalars.append(s[j]); j += 1 }
                guard !name.isEmpty else {
                    text.unicodeScalars.append(s[i])
                    i += 1
                    continue
                }
                name = name.lowercased()
                // The rest of the tag, quotes respected.
                var quote: Unicode.Scalar?
                var attributeText = ""
                while j < s.count {
                    let c = s[j]
                    if let q = quote { if c == q { quote = nil } } else if c == "\"" || c == "'" { quote = c } else if c == ">" { break }
                    attributeText.unicodeScalars.append(c)
                    j += 1
                }
                i = j + 1
                flushText()
                if closing {
                    if name == "p", !isOpen("p") {
                        let node = Node(tag: "p"); node.parent = current; current.children.append(node) // A stray </p> is an empty paragraph.
                    } else {
                        close(name)
                    }
                    continue
                }
                if closesParagraph.contains(name), isOpen("p") { close("p") }
                if name == "li" {
                    // A new item ends the previous one in the same list.
                    var node: Node? = current
                    while let n = node, n.tag != "ul", n.tag != "ol", n.tag != "#root" {
                        if n.tag == "li" { close("li"); break }
                        node = n.parent
                    }
                }
                if ["td", "th"].contains(name), current.tag == "td" || current.tag == "th" { close(current.tag) }
                if name == "tr", isOpen("tr"), current.tag != "table", current.tag != "tbody", current.tag != "thead" { close("tr") }
                let selfClosing = attributeText.hasSuffix("/")
                let node = Node(tag: name, attributes: attributes(attributeText))
                node.parent = current
                current.children.append(node)
                if rawText.contains(name) {
                    var k = i
                    while k < s.count, !matches("</\(name)", at: k) { k += 1 }
                    var raw = ""
                    for index in i..<k { raw.unicodeScalars.append(s[index]) }
                    let inner = Node(tag: "#text", text: name == "title" || name == "textarea" ? decode(raw) : raw)
                    inner.parent = node
                    node.children.append(inner)
                    while k < s.count, s[k] != ">" { k += 1 }
                    i = k + 1
                    continue
                }
                if !voids.contains(name), !selfClosing { current = node }
                continue
            }
            text.unicodeScalars.append(s[i])
            i += 1
        }
        flushText()
        return root
    }

    private static func attributes(_ text: String) -> [String: String] {
        var result: [String: String] = [:]
        guard let regex = try? NSRegularExpression(pattern: #"([A-Za-z_:][-A-Za-z0-9_:.]*)(?:\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'=<>`]+)))?"#) else { return result }
        for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let nameRange = Range(match.range(at: 1), in: text) else { continue }
            let value = [2, 3, 4].lazy.compactMap { Range(match.range(at: $0), in: text).map { String(text[$0]) } }.first ?? ""
            result[text[nameRange].lowercased()] = decode(value)
        }
        return result
    }

    private static let entities: [String: String] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": "\u{00A0}", "copy": "©", "reg": "®", "trade": "™",
        "hellip": "…", "mdash": "—", "ndash": "–", "lsquo": "‘", "rsquo": "’", "ldquo": "“", "rdquo": "”", "laquo": "«", "raquo": "»",
        "eacute": "é", "egrave": "è", "ecirc": "ê", "agrave": "à", "aacute": "á", "acirc": "â", "ccedil": "ç", "ocirc": "ô", "ouml": "ö",
        "uuml": "ü", "auml": "ä", "szlig": "ß", "euro": "€", "deg": "°", "times": "×", "middot": "·", "bull": "•", "rarr": "→", "larr": "←",
    ]

    static func decode(_ text: String) -> String {
        guard text.contains("&") else { return text }
        guard let regex = try? NSRegularExpression(pattern: #"&(#[0-9]+|#[xX][0-9A-Fa-f]+|[A-Za-z]+);"#) else { return text }
        var result = ""
        var last = text.startIndex
        for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let range = Range(match.range, in: text), let bodyRange = Range(match.range(at: 1), in: text) else { continue }
            result += text[last..<range.lowerBound]
            let body = String(text[bodyRange])
            if body.hasPrefix("#x") || body.hasPrefix("#X"), let code = UInt32(body.dropFirst(2), radix: 16), let scalar = Unicode.Scalar(code) {
                result.unicodeScalars.append(scalar)
            } else if body.hasPrefix("#"), let code = UInt32(body.dropFirst()), let scalar = Unicode.Scalar(code) {
                result.unicodeScalars.append(scalar)
            } else if let named = entities[body] ?? entities[body.lowercased()] {
                result += named
            } else {
                result += text[range]
            }
            last = range.upperBound
        }
        return result + text[last...]
    }

    // MARK: Writing

    struct Writer {
        let plain: Bool

        private static let blockTags: Set<String> = ["p", "div", "h1", "h2", "h3", "h4", "h5", "h6", "ul", "ol", "pre", "blockquote", "hr", "table", "section", "article", "header", "footer", "nav", "main", "figure", "figcaption", "dl", "dt", "dd", "address", "aside", "details", "summary", "form", "fieldset", "li", "body", "html", "tr", "thead", "tbody"]
        private static let skipped: Set<String> = ["head", "script", "style", "title", "meta", "link", "noscript", "template", "button", "select", "option", "svg", "iframe"]

        static func rawText(_ node: Node) -> String {
            node.isText ? node.text : node.children.map(rawText).joined()
        }

        /// A container's children as blocks; runs of inline content become paragraphs.
        func blocks(_ node: Node) -> String {
            var parts: [String] = []
            var run: [Node] = []
            func flush() {
                let text = inline(run).trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty { parts.append(text) }
                run.removeAll()
            }
            for child in node.children {
                if Self.skipped.contains(child.tag) { continue }
                if !child.isText, Self.blockTags.contains(child.tag) {
                    flush()
                    let block = self.block(child)
                    if !block.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { parts.append(block) }
                } else {
                    run.append(child)
                }
            }
            flush()
            return parts.joined(separator: "\n\n")
        }

        private func block(_ node: Node) -> String {
            switch node.tag {
            case "h1", "h2", "h3", "h4", "h5", "h6":
                let level = Int(node.tag.dropFirst()) ?? 1
                let text = inline(node.children).trimmingCharacters(in: .whitespacesAndNewlines)
                return plain ? text : String(repeating: "#", count: level) + " " + text
            case "p", "dt", "figcaption", "summary", "address":
                return inline(node.children).trimmingCharacters(in: .whitespacesAndNewlines)
            case "hr":
                return plain ? "" : "---"
            case "pre":
                let code = node.children.first { $0.tag == "code" }
                let raw = Self.rawText(node).trimmingCharacters(in: .newlines)
                if plain { return raw }
                let classes = (code?.attributes["class"] ?? node.attributes["class"] ?? "").split(separator: " ")
                let language = classes.first { $0.hasPrefix("language-") || $0.hasPrefix("lang-") }.map { String($0.split(separator: "-", maxSplits: 1).last ?? "") } ?? ""
                let fence = raw.contains("```") ? "~~~" : "```"
                return "\(fence)\(language)\n\(raw)\n\(fence)"
            case "blockquote":
                let inner = blocks(node)
                return inner.components(separatedBy: "\n").map { plain ? "    \($0)" : ($0.isEmpty ? ">" : "> \($0)") }.joined(separator: "\n")
            case "ul", "ol":
                return list(node)
            case "table":
                return table(node)
            case "dd":
                return (plain ? "    " : ": ") + inline(node.children).trimmingCharacters(in: .whitespacesAndNewlines)
            default:
                return blocks(node)
            }
        }

        private func list(_ node: Node) -> String {
            let ordered = node.tag == "ol"
            var number = Int(node.attributes["start"] ?? "") ?? 1
            var items: [String] = []
            for item in node.children where item.tag == "li" {
                var marker = ordered ? "\(number). " : (plain ? "• " : "- ")
                number += 1
                var content = item
                if let box = item.children.first(where: { $0.tag == "input" && $0.attributes["type"] == "checkbox" }) {
                    marker += box.attributes["checked"] != nil ? "[x] " : "[ ] "
                    content = Node(tag: "li")
                    content.children = item.children.filter { $0 !== box }
                }
                var body = blocks(content)
                // Items without paragraphs are tight: their text and a nested list sit line by line.
                if !content.children.contains(where: { $0.tag == "p" }) { body = body.replacingOccurrences(of: "\n\n", with: "\n") }
                let indent = String(repeating: " ", count: marker.count)
                let lines = body.components(separatedBy: "\n")
                let rendered = lines.enumerated().map { index, line in
                    index == 0 ? marker + line : (line.isEmpty ? "" : indent + line)
                }.joined(separator: "\n")
                items.append(rendered)
            }
            // Items that hold several paragraphs are spaced out; others stay tight.
            let loose = items.contains { $0.contains("\n\n") }
            return items.joined(separator: loose ? "\n\n" : "\n")
        }

        private func table(_ node: Node) -> String {
            var rows: [(cells: [String], header: Bool, aligns: [String?])] = []
            func collect(_ n: Node, inHead: Bool) {
                for child in n.children {
                    switch child.tag {
                    case "thead": collect(child, inHead: true)
                    case "tbody", "tfoot": collect(child, inHead: false)
                    case "tr":
                        let cells = child.children.filter { $0.tag == "td" || $0.tag == "th" }
                        let texts = cells.map { inline($0.children).trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "\n", with: " ") }
                        let aligns = cells.map { cell -> String? in
                            let style = (cell.attributes["style"] ?? "").replacingOccurrences(of: " ", with: "").lowercased()
                            if let align = cell.attributes["align"]?.lowercased() { return align }
                            for value in ["left", "right", "center"] where style.contains("text-align:\(value)") { return value }
                            return nil
                        }
                        rows.append((texts, inHead || cells.allSatisfy { $0.tag == "th" }, aligns))
                    default: collect(child, inHead: inHead)
                    }
                }
            }
            collect(node, inHead: false)
            guard !rows.isEmpty else { return "" }
            let columns = rows.map(\.cells.count).max() ?? 0
            func pad(_ cells: [String]) -> [String] { (0..<columns).map { $0 < cells.count ? cells[$0] : "" } }
            if plain { return rows.map { pad($0.cells).joined(separator: "\t") }.joined(separator: "\n") }
            let headerIndex = rows.firstIndex { $0.header } ?? 0
            let header = rows[headerIndex]
            let body = rows.enumerated().filter { $0.offset != headerIndex }.map(\.element)
            func line(_ cells: [String]) -> String { "| " + pad(cells).map { $0.replacingOccurrences(of: "|", with: "\\|") }.joined(separator: " | ") + " |" }
            let delimiter = "| " + (0..<columns).map { column -> String in
                switch column < header.aligns.count ? header.aligns[column] : nil {
                case "center"?: return ":---:"
                case "right"?: return "---:"
                case "left"?: return ":---"
                default: return "---"
                }
            }.joined(separator: " | ") + " |"
            return ([line(header.cells), delimiter] + body.map { line($0.cells) }).joined(separator: "\n")
        }

        /// Inline content: text with its whitespace collapsed, emphasis, links, images, code.
        func inline(_ nodes: [Node]) -> String {
            nodes.map(inline).joined()
                .replacingOccurrences(of: #"[ \t]+"#, with: " ", options: .regularExpression)
                .replacingOccurrences(of: " \n", with: "\n")
                // Line breaks were held as a mark, so collapsing spaces couldn't eat them.
                .replacingOccurrences(of: " ?\u{E002} ?", with: "\u{E002}", options: .regularExpression)
                .replacingOccurrences(of: "\u{E002}", with: plain ? "\n" : "  \n")
        }

        private func inline(_ node: Node) -> String {
            if node.isText {
                let text = node.text.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                return plain ? text : escapeMarkdown(text)
            }
            if Self.skipped.contains(node.tag) { return "" }
            let inner = { inline(node.children) }
            switch node.tag {
            case "br": return "\u{E002}"
            case "strong", "b": return wrap(inner(), plain ? "" : "**")
            case "em", "i", "cite": return wrap(inner(), plain ? "" : "*")
            case "del", "s", "strike": return wrap(inner(), plain ? "" : "~~")
            case "code", "kbd", "samp":
                let code = Self.rawText(node).replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                if plain { return code }
                let fence = code.contains("`") ? "``" : "`"
                return fence == "``" ? "`` \(code) ``" : "`\(code)`"
            case "a":
                let text = inner().trimmingCharacters(in: .whitespaces)
                guard !plain, let href = node.attributes["href"], !href.isEmpty, !href.hasPrefix("javascript:") else { return text }
                if text == href, href.hasPrefix("http") { return "<\(href)>" }
                let title = node.attributes["title"].map { " \"\($0.replacingOccurrences(of: "\"", with: "\\\""))\"" } ?? ""
                return "[\(text.isEmpty ? href : text)](\(href.replacingOccurrences(of: " ", with: "%20"))\(title))"
            case "img":
                let alt = node.attributes["alt"] ?? ""
                guard !plain, let src = node.attributes["src"] else { return alt }
                return "![\(alt)](\(src.replacingOccurrences(of: " ", with: "%20")))"
            case "input":
                guard node.attributes["type"] == "checkbox" else { return "" }
                return node.attributes["checked"] != nil ? "[x] " : "[ ] "
            case "sup": return plain ? inner() : "<sup>\(inner())</sup>"
            case "sub": return plain ? inner() : "<sub>\(inner())</sub>"
            case "u", "ins", "mark": return inner()
            default:
                // A block inside inline content (a div in a span): give it its own line.
                if Self.blockTags.contains(node.tag) { return "\n" + blocks(node) + "\n" }
                return inner()
            }
        }

        private func wrap(_ text: String, _ marker: String) -> String {
            let trimmed = text.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !marker.isEmpty else { return text }
            // Spaces stay outside the markers, or Markdown wouldn't see them.
            let leading = text.hasPrefix(" ") ? " " : "", trailing = text.hasSuffix(" ") ? " " : ""
            return leading + marker + trimmed + marker + trailing
        }

        private func escapeMarkdown(_ text: String) -> String {
            var out = ""
            for character in text {
                if "*_`\\".contains(character) { out.append("\\") }
                out.append(character)
            }
            return out.replacingOccurrences(of: "\u{00A0}", with: " ")
        }
    }
}
