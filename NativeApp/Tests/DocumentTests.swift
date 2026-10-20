import AppKit
import Foundation
import PDFKit

@main struct DocumentTests {
    @MainActor static func main() async throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("OpenTangerine-documents-\(UUID())")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        func url(_ name: String) -> URL { root.appendingPathComponent(name) }
        func convert(_ source: URL, _ from: FileFormat, _ to: FileFormat, _ name: String) async throws -> URL {
            try await Engines.convert(ConversionRequest(source: source, sourceFormat: from, target: to, destination: url(name), progress: { _ in }))
        }
        let text = "Open Tangerine document test\nCafé & <content>\n\nSecond paragraph."
        try text.write(to: url("input.txt"), atomically: true, encoding: .utf8)
        let pdf = try await convert(url("input.txt"), .txt, .pdf, "text.pdf")
        precondition(PDFDocument(url: pdf)!.string!.contains("Open Tangerine"))
        for target: FileFormat in [.png, .jpg, .srt, .vtt] {
            let out = try await convert(url("input.txt"), .txt, target, "text.\(target.fileExtension)")
            if target == .png || target == .jpg { precondition(try! ImageIOBridge.load(out).width == 1275) }
            else { precondition(try! String(contentsOf: out, encoding: .utf8).contains("Second paragraph")) }
            print("PASS TXT -> \(target)")
        }
        for target: FileFormat in [.png, .jpg, .txt, .docx] {
            let out = try await convert(pdf, .pdf, target, "pdf.\(target.fileExtension)")
            switch target {
            case .png, .jpg: precondition(try! ImageIOBridge.load(out).width == 2550)
            case .txt: precondition(try! String(contentsOf: out, encoding: .utf8).contains("Open Tangerine"))
            case .docx:
                let result = try await Shell.run("/usr/bin/unzip", ["-p", out.path, "word/document.xml"])
                precondition(result.succeeded && result.stdout.contains("Open Tangerine") && result.stdout.contains("&amp;"))
            default: break
            }
            print("PASS PDF -> \(target)")
        }
        // Markdown to HTML, block by block and inline.
        let markdownSource = """
        # Citrus guide

        Oranges are **sweet**, lemons are *sour* and `limes` are ~~blue~~ green.
        See [the site](https://example.com "Home") or <https://open.example>.

        ## Kinds
        1. Orange
        2. Lemon
           - Meyer
           - Eureka
        3. Lime

        - [x] Peel
        - [ ] Squeeze

        > Quoted *zest*

        ```swift
        let fruit = "tangerine" // <tag> & co
        ```

        | Fruit | Price |
        | :--- | ---: |
        | Orange | 1.20 |
        | Lemon \\| Lime | 0.80 |

        ---
        Setext title
        ============
        Line one  
        line two & <b>bold</b>
        ![logo](logo.png)
        """
        let html = Markdown.html(markdownSource)
        for expected in ["<h1>Citrus guide</h1>", "<strong>sweet</strong>", "<em>sour</em>", "<code>limes</code>", "<del>blue</del>",
                         "<a href=\"https://example.com\" title=\"Home\">the site</a>", "<a href=\"https://open.example\">https://open.example</a>",
                         "<h2>Kinds</h2>", "<ol>\n<li>Orange</li>", "<ul>\n<li>Meyer</li>\n<li>Eureka</li>\n</ul>", "<input type=\"checkbox\" disabled checked> Peel",
                         "<blockquote>\n<p>Quoted <em>zest</em></p>\n</blockquote>", "<pre><code class=\"language-swift\">let fruit = &quot;tangerine&quot; // &lt;tag&gt; &amp; co\n</code></pre>",
                         "<th style=\"text-align: left\">Fruit</th>", "<td style=\"text-align: right\">0.80</td>", "<td style=\"text-align: left\">Lemon | Lime</td>",
                         "<hr>", "<h1>Setext title</h1>", "Line one<br>\nline two &amp; <b>bold</b>", "<img src=\"logo.png\" alt=\"logo\">"] {
            precondition(html.contains(expected), "Markdown → HTML is missing \(expected) in:\n\(html)")
        }
        print("PASS Markdown → HTML: headings, emphasis, links, nested and task lists, quotes, code, tables, breaks, images")
        // And back: the HTML gives the same Markdown structure.
        let back = HTMLToMarkdown.markdown(html)
        for expected in ["# Citrus guide", "**sweet**", "*sour*", "`limes`", "~~blue~~", "[the site](https://example.com \"Home\")", "<https://open.example>",
                         "## Kinds", "1. Orange\n2. Lemon\n   - Meyer\n   - Eureka\n3. Lime", "- [x] Peel\n- [ ] Squeeze", "> Quoted *zest*",
                         "```swift\nlet fruit = \"tangerine\" // <tag> & co\n```", "| Fruit | Price |\n| :--- | ---: |", "| Lemon \\| Lime | 0.80 |", "---", "# Setext title", "Line one  \nline two & **bold**", "![logo](logo.png)"] {
            precondition(back.contains(expected), "HTML → Markdown is missing \(expected) in:\n\(back)")
        }
        precondition(HTMLToMarkdown.markdown(Markdown.html(back)) == back, "Markdown → HTML → Markdown is stable:\n\(HTMLToMarkdown.markdown(Markdown.html(back)))")
        print("PASS HTML → Markdown, and a round trip that changes nothing")
        let messy = "<html><head><title>Notes</title><style>p{color:red}</style></head><body><div><h2>Plan &amp; ideas</h2><p>First<p>Second with <a href='/x'>a link</a>&nbsp;&#8212; done<ul><li>One<li>Two</ul><script>alert(1)</script><table><tr><th>A<th>B<tr><td>1<td>2</table></div></body></html>"
        let messyMarkdown = HTMLToMarkdown.markdown(messy)
        precondition(messyMarkdown == "## Plan & ideas\n\nFirst\n\nSecond with [a link](/x) — done\n\n- One\n- Two\n\n| A | B |\n| --- | --- |\n| 1 | 2 |\n", "Forgiving HTML parsing:\n\(messyMarkdown)")
        precondition(HTMLToMarkdown.text(messy).hasPrefix("Plan & ideas\n\nFirst") && HTMLToMarkdown.title(messy) == "Notes")
        print("PASS unclosed paragraphs and items, entities, scripts and tables in loose HTML")
        try markdownSource.write(to: url("guide.md"), atomically: true, encoding: .utf8)
        let mdPDF = try await convert(url("guide.md"), .md, .pdf, "guide.pdf")
        precondition((PDFDocument(url: mdPDF)?.string ?? "").contains("Citrus guide"))
        let mdDOCX = try await convert(url("guide.md"), .md, .docx, "guide.docx")
        let mdText = try await convert(url("guide.md"), .md, .txt, "guide-plain.txt")
        let plainGuide = try String(contentsOf: mdText, encoding: .utf8)
        precondition(plainGuide.hasPrefix("Citrus guide\n\nOranges are sweet"), "Markdown → text:\n\(plainGuide)")
        // The Word file has real headings, numbered and bulleted lists, links and a table, and is well-formed.
        let wordXML = try await Shell.run("/usr/bin/unzip", ["-p", mdDOCX.path, "word/document.xml"])
        let numberingXML = try await Shell.run("/usr/bin/unzip", ["-p", mdDOCX.path, "word/numbering.xml"])
        precondition(wordXML.stdout.contains("<w:pStyle w:val=\"Heading1\"/>") && wordXML.stdout.contains("<w:hyperlink r:id=") && wordXML.stdout.contains("<w:numPr>") && wordXML.stdout.contains("<w:tbl>") && numberingXML.stdout.contains("w:val=\"decimal\""))
        for part in ["word/document.xml", "word/numbering.xml", "word/styles.xml", "word/_rels/document.xml.rels", "\\[Content_Types\\].xml"] {
            let extracted = url("part.xml")
            try (try await Shell.run("/usr/bin/unzip", ["-p", mdDOCX.path, part])).stdout.write(to: extracted, atomically: true, encoding: .utf8)
            let lint = try await Shell.run("/usr/bin/xmllint", ["--noout", extracted.path])
            precondition(lint.succeeded, "\(part) is not well-formed: \(lint.stderr)")
        }
        let docxMarkdown = try String(contentsOf: try await convert(mdDOCX, .docx, .md, "from-word.md"), encoding: .utf8)
        precondition(docxMarkdown.hasPrefix("# Citrus guide") && docxMarkdown.contains("## Kinds") && docxMarkdown.contains("**sweet**, lemons") && docxMarkdown.contains("[x] Peel") && docxMarkdown.contains("Line one  \nline two") && docxMarkdown.range(of: #"(-|1\.) Orange"#, options: .regularExpression) != nil && docxMarkdown.contains("> Quoted *zest*") && docxMarkdown.contains("```\nlet fruit"), "Word → Markdown:\n\(docxMarkdown)")
        let docxHTML = try String(contentsOf: try await convert(mdDOCX, .docx, .html, "from-word.html"), encoding: .utf8)
        precondition(docxHTML.contains("<h1>Citrus guide</h1>") && docxHTML.contains("<title>Citrus guide</title>"))
        let htmlFile = url("page.html"); try messy.write(to: htmlFile, atomically: true, encoding: .utf8)
        let pagePDF = try await convert(htmlFile, .html, .pdf, "page.pdf")
        precondition((PDFDocument(url: pagePDF)?.string ?? "").contains("Plan & ideas"))
        precondition(FileFormat.detect(url("guide.md")) == .md && FileFormat.detect(htmlFile) == .html && FileFormat.detect(url("notes.txt")) == .txt)
        print("PASS Markdown, HTML and Word into one another, PDF and text")

        let second = url("second.pdf")
        try TextRenderer.writePDF("Second page marker", to: second)
        let merged = url("merged.pdf")
        try PDFOps.merge([pdf, second], to: merged)
        let mergedDoc = try PDFOps.document(merged)
        precondition(mergedDoc.pageCount == 2 && mergedDoc.page(at: 1)!.string!.contains("Second page"))
        for mode: PDFOps.SplitMode in [.everyPage, .everyN, .ranges] {
            let outputs = try PDFOps.split(merged, mode: mode, every: 2, ranges: "2", into: url("split-\(mode.rawValue)"))
            precondition(outputs.count == (mode == .everyPage ? 2 : 1))
            precondition(try! PDFOps.document(outputs[0]).pageCount == (mode == .everyN ? 2 : 1))
            print("PASS PDF split \(mode)")
        }
        try PDFOps.assemble(pages: [PDFPageRef(sourceIndex: 1, rotation: 90, sourceURL: merged), PDFPageRef(sourceIndex: 0, rotation: 0, sourceURL: merged)], to: url("reordered.pdf"))
        let reordered = try PDFOps.document(url("reordered.pdf"))
        precondition(reordered.page(at: 0)!.rotation == 90 && reordered.page(at: 0)!.string!.contains("Second page"))
        for strong in [false, true] {
            let out = url("compressed-\(strong).pdf")
            try PDFOps.compress(merged, strong: strong, to: out)
            precondition(try! PDFOps.document(out).pageCount == 2)
            print("PASS PDF compression strong=\(strong), preserves page count (size reduction not guaranteed)")
        }
        let imagePDF = url("images.pdf")
        try PDFOps.fromImages([url("text.png"), url("text.jpg")], to: imagePDF, progress: { _ in })
        precondition(try! PDFOps.document(imagePDF).pageCount == 2)
        let multiImages = try await convert(merged, .pdf, .png, "pages.png")
        precondition(multiImages.lastPathComponent == "pages (PNG pages)" && FileFormat.detect(multiImages) == nil, "a multi-page export is a plainly named folder, not something that looks like a PNG")
        let pages = try fm.contentsOfDirectory(at: multiImages, includingPropertiesForKeys: nil)
        precondition(pages.count == 2)
        for page in pages { precondition(try! ImageIOBridge.load(page).width == 2550) }
        let scanDOCX = try await convert(imagePDF, .pdf, .docx, "scanned.docx")
        let listing = try await Shell.run("/usr/bin/unzip", ["-l", scanDOCX.path])
        precondition(listing.stdout.contains("image1.png") && listing.stdout.contains("image2.png"))
        // Scanned pages have no text layer: they are read with Vision now.
        let scanText = try await convert(imagePDF, .pdf, .txt, "scan.txt")
        precondition(try! String(contentsOf: scanText, encoding: .utf8).localizedCaseInsensitiveContains("paragraph"), "Scanned PDF read with OCR")
        let protected = url("protected.pdf")
        precondition(mergedDoc.write(to: protected, withOptions: [.userPasswordOption: "test-password", .ownerPasswordOption: "owner-password"]))
        do { _ = try await convert(protected, .pdf, .png, "locked.png"); fatalError("Locked PDF accepted") } catch { }
        let mixed = url("mixed.pdf")
        try PDFOps.merge([imagePDF, pdf], to: mixed)
        let mixedDocx = try await convert(mixed, .pdf, .docx, "mixed.docx")
        let mixedXML = try await Shell.run("/usr/bin/unzip", ["-p", mixedDocx.path, "word/document.xml"])
        precondition(mixedXML.stdout.range(of: "<w:drawing>")!.lowerBound < mixedXML.stdout.range(of: "Open Tangerine")!.lowerBound)
        precondition(mixedXML.stdout.contains("w:type=\"page\""))
        print("PASS mixed scanned/text PDF -> DOCX preserves page order and breaks")
        print("PASS PDF merge/reorder/rotate, images-to-PDF, multipage export, scanned DOCX, scanned/locked rejection")
        let srt = "1\n00:00:01,250 --> 00:00:03,000\nHello <i>world</i>\n\n2\n00:00:04,000 --> 00:00:05,000\nSecond cue\n"
        try srt.write(to: url("captions.srt"), atomically: true, encoding: .utf8)
        let vtt = try await convert(url("captions.srt"), .srt, .vtt, "captions.vtt")
        let roundtrip = try await convert(vtt, .vtt, .srt, "roundtrip.srt")
        let cues = SubtitleParser.parse(try String(contentsOf: roundtrip, encoding: .utf8), hint: .srt)
        precondition(cues.count == 2 && cues[0].start == 1.25 && cues[1].end == 5)
        for (source, format) in [(url("captions.srt"), FileFormat.srt), (vtt, .vtt)] {
            let out = try await convert(source, format, .txt, "\(format).txt")
            precondition(try! String(contentsOf: out, encoding: .utf8).contains("Hello world"))
        }
        precondition(SubtitleParser.format(59.9999, separator: ",") == "00:01:00,000")
        precondition(SubtitleParser.parseTimestamp("nan") == nil)
        print("PASS SRT/VTT round trip + both TXT exports; millisecond carry and invalid timestamp")
    }
}
