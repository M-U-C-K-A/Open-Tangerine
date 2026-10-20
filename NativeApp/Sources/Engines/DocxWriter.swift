import Foundation
import ImageIO

enum ZipTool {
    static func zip(directory: URL, to destination: URL) async throws {
        try? FileManager.default.removeItem(at: destination)
        let result = try await Shell.run("/usr/bin/zip", ["-r", "-X", "-q", destination.path, "."], currentDirectory: directory)
        guard result.succeeded else { throw OpenTangerineError.toolFailed("zip", result.stderr) }
    }

    static func zipOrdered(directory: URL, entries: [String], to destination: URL) async throws {
        try? FileManager.default.removeItem(at: destination)
        var args = ["-X", "-q", destination.path]
        args += entries
        let result = try await Shell.run("/usr/bin/zip", args, currentDirectory: directory)
        guard result.succeeded else { throw OpenTangerineError.toolFailed("zip", result.stderr) }
    }

    static func unzip(_ archive: URL, into directory: URL) async throws {
        let result = try await Shell.run("/usr/bin/ditto", ["-x", "-k", archive.path, directory.path])
        guard result.succeeded else { throw OpenTangerineError.toolFailed("ditto", result.stderr) }
    }
}

enum DocxWriter {
    enum Block { case paragraph(String), image(URL), pageBreak }

    static func write(paragraphs: [String], images: [URL], to destination: URL) async throws {
        try await write(blocks: paragraphs.map { .paragraph($0) } + images.map { .image($0) }, to: destination)
    }

    static func write(blocks: [Block], to destination: URL) async throws {
        let images = blocks.compactMap { block -> URL? in if case .image(let url) = block { return url }; return nil }
        let fm = FileManager.default
        let staging = fm.temporaryDirectory.appendingPathComponent("opentangerine-docx-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: staging) }
        try fm.createDirectory(at: staging.appendingPathComponent("_rels"), withIntermediateDirectories: true)
        try fm.createDirectory(at: staging.appendingPathComponent("word/_rels"), withIntermediateDirectories: true)
        try fm.createDirectory(at: staging.appendingPathComponent("word/media"), withIntermediateDirectories: true)

        var relationships = """
        <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
        """
        var body = ""
        var contentTypesExtra = ""
        var seenExtensions = Set<String>()
        var imageIndex = 0
        for block in blocks {
            switch block {
            case .paragraph(let paragraph):
                body += "<w:p><w:r><w:t xml:space=\"preserve\">\(escape(paragraph))</w:t></w:r></w:p>"
                continue
            case .pageBreak:
                body += "<w:p><w:r><w:br w:type=\"page\"/></w:r></w:p>"
                continue
            case .image: break
            }
            guard case .image(let image) = block else { continue }
            let index = imageIndex
            imageIndex += 1
            let ext = image.pathExtension.lowercased().isEmpty ? "png" : image.pathExtension.lowercased()
            let name = "image\(index + 1).\(ext)"
            try fm.copyItem(at: image, to: staging.appendingPathComponent("word/media/\(name)"))
            let rid = "rId\(index + 10)"
            relationships += "<Relationship Id=\"\(rid)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/image\" Target=\"media/\(name)\"/>"
            let size = ImageIOBridge.pixelSize(image)
            let maxWidthEMU = 5_943_600.0
            let maxHeightEMU = 8_229_600.0
            var widthEMU = max(size.width, 1) * 9525
            var heightEMU = max(size.height, 1) * 9525
            let scale = min(maxWidthEMU / widthEMU, maxHeightEMU / heightEMU, 1)
            widthEMU *= scale
            heightEMU *= scale
            body += drawing(rid: rid, id: index + 1, name: name, cx: Int(widthEMU), cy: Int(heightEMU))
            if !seenExtensions.contains(ext) {
                seenExtensions.insert(ext)
                let mime = ext == "jpg" || ext == "jpeg" ? "image/jpeg" : "image/\(ext)"
                contentTypesExtra += "<Default Extension=\"\(ext)\" ContentType=\"\(mime)\"/>"
            }
        }

        try await package(body: body, relationships: relationships, contentTypesExtra: contentTypesExtra, numbering: nil, staging: staging, media: images.indices.map { index in
            "word/media/image\(index + 1).\(images[index].pathExtension.lowercased().isEmpty ? "png" : images[index].pathExtension.lowercased())"
        }, to: destination)
    }

    /// Zips a Word package: `body` is the document's WordprocessingML, `relationships` its
    /// links and pictures (already copied under word/media), `numbering` its list definitions.
    static func package(body: String, relationships: String, contentTypesExtra: String, numbering: String?, staging: URL, media: [String], to destination: URL) async throws {
        var relationships = relationships
        var overrides = ""
        if let numbering {
            try numbering.write(to: staging.appendingPathComponent("word/numbering.xml"), atomically: true, encoding: .utf8)
            relationships += "<Relationship Id=\"rId2\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/numbering\" Target=\"numbering.xml\"/>"
            overrides = "<Override PartName=\"/word/numbering.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.numbering+xml\"/>"
        }
        let contentTypes = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
        <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
        <Default Extension="xml" ContentType="application/xml"/>
        \(contentTypesExtra)
        <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
        <Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>
        \(overrides)
        </Types>
        """
        let rootRels = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
        <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
        </Relationships>
        """
        let documentRels = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">\(relationships)</Relationships>
        """
        let document = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing" xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture">
        <w:body>\(body)<w:sectPr><w:pgSz w:w="12240" w:h="15840"/><w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440" w:header="720" w:footer="720" w:gutter="0"/></w:sectPr></w:body>
        </w:document>
        """
        try contentTypes.write(to: staging.appendingPathComponent("[Content_Types].xml"), atomically: true, encoding: .utf8)
        try rootRels.write(to: staging.appendingPathComponent("_rels/.rels"), atomically: true, encoding: .utf8)
        try documentRels.write(to: staging.appendingPathComponent("word/_rels/document.xml.rels"), atomically: true, encoding: .utf8)
        try document.write(to: staging.appendingPathComponent("word/document.xml"), atomically: true, encoding: .utf8)
        try styles.write(to: staging.appendingPathComponent("word/styles.xml"), atomically: true, encoding: .utf8)
        var entries = ["[Content_Types].xml", "_rels/.rels", "word/document.xml", "word/styles.xml", "word/_rels/document.xml.rels"]
        if numbering != nil { entries.append("word/numbering.xml") }
        entries += media
        try await ZipTool.zipOrdered(directory: staging, entries: entries, to: destination)
    }

    /// Body text, headings, quotes, code, links and list paragraphs, as Word names them.
    static let styles = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
    <w:docDefaults><w:rPrDefault><w:rPr><w:rFonts w:ascii="Helvetica" w:hAnsi="Helvetica"/><w:sz w:val="22"/></w:rPr></w:rPrDefault><w:pPrDefault><w:pPr><w:spacing w:after="160" w:line="276" w:lineRule="auto"/></w:pPr></w:pPrDefault></w:docDefaults>
    <w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/></w:style>
    <w:style w:type="paragraph" w:styleId="Heading1"><w:name w:val="heading 1"/><w:basedOn w:val="Normal"/><w:next w:val="Normal"/><w:pPr><w:keepNext/><w:spacing w:before="360" w:after="120"/><w:outlineLvl w:val="0"/></w:pPr><w:rPr><w:b/><w:sz w:val="40"/></w:rPr></w:style>
    <w:style w:type="paragraph" w:styleId="Heading2"><w:name w:val="heading 2"/><w:basedOn w:val="Normal"/><w:next w:val="Normal"/><w:pPr><w:keepNext/><w:spacing w:before="300" w:after="100"/><w:outlineLvl w:val="1"/></w:pPr><w:rPr><w:b/><w:sz w:val="32"/></w:rPr></w:style>
    <w:style w:type="paragraph" w:styleId="Heading3"><w:name w:val="heading 3"/><w:basedOn w:val="Normal"/><w:next w:val="Normal"/><w:pPr><w:keepNext/><w:spacing w:before="240" w:after="80"/><w:outlineLvl w:val="2"/></w:pPr><w:rPr><w:b/><w:sz w:val="27"/></w:rPr></w:style>
    <w:style w:type="paragraph" w:styleId="Heading4"><w:name w:val="heading 4"/><w:basedOn w:val="Normal"/><w:next w:val="Normal"/><w:pPr><w:keepNext/><w:outlineLvl w:val="3"/></w:pPr><w:rPr><w:b/><w:sz w:val="25"/></w:rPr></w:style>
    <w:style w:type="paragraph" w:styleId="Heading5"><w:name w:val="heading 5"/><w:basedOn w:val="Normal"/><w:next w:val="Normal"/><w:pPr><w:keepNext/><w:outlineLvl w:val="4"/></w:pPr><w:rPr><w:b/><w:sz w:val="23"/></w:rPr></w:style>
    <w:style w:type="paragraph" w:styleId="Heading6"><w:name w:val="heading 6"/><w:basedOn w:val="Normal"/><w:next w:val="Normal"/><w:pPr><w:keepNext/><w:outlineLvl w:val="5"/></w:pPr><w:rPr><w:b/><w:i/><w:sz w:val="22"/></w:rPr></w:style>
    <w:style w:type="paragraph" w:styleId="Quote"><w:name w:val="Quote"/><w:basedOn w:val="Normal"/><w:pPr><w:pBdr><w:left w:val="single" w:sz="18" w:space="8" w:color="D0D0D0"/></w:pBdr><w:ind w:left="360"/></w:pPr><w:rPr><w:color w:val="555555"/></w:rPr></w:style>
    <w:style w:type="paragraph" w:styleId="Code"><w:name w:val="Code"/><w:basedOn w:val="Normal"/><w:pPr><w:shd w:val="clear" w:color="auto" w:fill="F5F5F7"/><w:spacing w:after="0" w:line="240" w:lineRule="auto"/></w:pPr><w:rPr><w:rFonts w:ascii="Menlo" w:hAnsi="Menlo"/><w:sz w:val="19"/></w:rPr></w:style>
    <w:style w:type="paragraph" w:styleId="ListParagraph"><w:name w:val="List Paragraph"/><w:basedOn w:val="Normal"/><w:pPr><w:spacing w:after="60"/></w:pPr></w:style>
    <w:style w:type="character" w:styleId="Hyperlink"><w:name w:val="Hyperlink"/><w:rPr><w:color w:val="0563C1"/><w:u w:val="single"/></w:rPr></w:style>
    <w:style w:type="character" w:styleId="InlineCode"><w:name w:val="Inline Code"/><w:rPr><w:rFonts w:ascii="Menlo" w:hAnsi="Menlo"/><w:sz w:val="19"/><w:shd w:val="clear" w:color="auto" w:fill="F2F2F4"/></w:rPr></w:style>
    <w:style w:type="table" w:styleId="TableGrid"><w:name w:val="Table Grid"/><w:tblPr><w:tblBorders><w:top w:val="single" w:sz="4" w:color="CCCCCC"/><w:left w:val="single" w:sz="4" w:color="CCCCCC"/><w:bottom w:val="single" w:sz="4" w:color="CCCCCC"/><w:right w:val="single" w:sz="4" w:color="CCCCCC"/><w:insideH w:val="single" w:sz="4" w:color="CCCCCC"/><w:insideV w:val="single" w:sz="4" w:color="CCCCCC"/></w:tblBorders><w:tblCellMar><w:left w:w="100" w:type="dxa"/><w:right w:w="100" w:type="dxa"/></w:tblCellMar></w:tblPr></w:style>
    </w:styles>
    """

    static func drawing(rid: String, id: Int, name: String, cx: Int, cy: Int) -> String {
        """
        <w:p><w:r><w:drawing><wp:inline distT="0" distB="0" distL="0" distR="0"><wp:extent cx="\(cx)" cy="\(cy)"/><wp:docPr id="\(id)" name="\(name)"/><a:graphic><a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/picture"><pic:pic><pic:nvPicPr><pic:cNvPr id="\(id)" name="\(name)"/><pic:cNvPicPr/></pic:nvPicPr><pic:blipFill><a:blip r:embed="\(rid)"/><a:stretch><a:fillRect/></a:stretch></pic:blipFill><pic:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="\(cx)" cy="\(cy)"/></a:xfrm><a:prstGeom prst="rect"><a:avLst/></a:prstGeom></pic:spPr></pic:pic></a:graphicData></a:graphic></wp:inline></w:drawing></w:r></w:p>
        """
    }

    static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}

