import AVFoundation
import Foundation
import ImageIO
import PDFKit
import UniformTypeIdentifiers

struct MetadataField: Identifiable, Hashable {
    let id: String
    let group: String
    let key: String
    var value: String
    let editable: Bool
    let sensitive: Bool
}

enum MetadataOps {
    static let sensitiveGroups: Set<String> = ["GPS", "Exif", "MakerApple", "TIFF", "IPTC", "XMP"]

    static func read(_ url: URL) async -> [MetadataField] {
        guard let format = FileFormat.detect(url) else { return [] }
        switch format.category {
        case .image: return readImage(url)
        case .audio, .video: return await readAV(url)
        case .document where format == .pdf: return readPDF(url)
        default: return fileFields(url)
        }
    }

    static func fileFields(_ url: URL) -> [MetadataField] {
        var fields: [MetadataField] = []
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        fields.append(MetadataField(id: "file.name", group: "File", key: "Name", value: url.lastPathComponent, editable: false, sensitive: false))
        if let size = attrs?[.size] as? Int64 {
            fields.append(MetadataField(id: "file.size", group: "File", key: "Size", value: FileSizeFormatter.string(size), editable: false, sensitive: false))
        }
        if let created = attrs?[.creationDate] as? Date {
            fields.append(MetadataField(id: "file.created", group: "File", key: "Created", value: created.formatted(), editable: false, sensitive: false))
        }
        if let modified = attrs?[.modificationDate] as? Date {
            fields.append(MetadataField(id: "file.modified", group: "File", key: "Modified", value: modified.formatted(), editable: false, sensitive: false))
        }
        return fields
    }

    static func readImage(_ url: URL) -> [MetadataField] {
        var fields = fileFields(url)
        let props = ImageIOBridge.properties(url)
        for (key, value) in props {
            let name = key as String
            if let dictionary = value as? [CFString: Any] {
                let group = name.replacingOccurrences(of: "{", with: "").replacingOccurrences(of: "}", with: "")
                for (subKey, subValue) in dictionary {
                    let sub = subKey as String
                    fields.append(MetadataField(id: "\(group).\(sub)", group: group, key: sub, value: describe(subValue), editable: isEditableImageKey(group: group, key: sub), sensitive: sensitiveGroups.contains(group)))
                }
            } else {
                fields.append(MetadataField(id: "Image.\(name)", group: "Image", key: name, value: describe(value), editable: false, sensitive: false))
            }
        }
        return fields.sorted { ($0.group, $0.key) < ($1.group, $1.key) }
    }

    private static func isEditableImageKey(group: String, key: String) -> Bool {
        let editable: Set<String> = ["Artist", "Copyright", "ImageDescription", "Software", "Make", "Model", "UserComment", "DateTimeOriginal", "DateTimeDigitized", "DateTime", "LensModel", "Keywords", "Caption/Abstract", "Byline", "CopyrightNotice", "ObjectName", "City", "Country/PrimaryLocationName"]
        return editable.contains(key)
    }

    static func readAV(_ url: URL) async -> [MetadataField] {
        var fields = fileFields(url)
        let asset = AVURLAsset(url: url)
        let info = await MediaInfo.load(url)
        if info.duration > 0 { fields.append(MetadataField(id: "media.duration", group: "Media", key: "Duration", value: TimeFormatter.clock(info.duration), editable: false, sensitive: false)) }
        if info.hasVideo { fields.append(MetadataField(id: "media.size", group: "Media", key: "Dimensions", value: "\(Int(info.naturalSize.width)) × \(Int(info.naturalSize.height))", editable: false, sensitive: false)) }
        if info.frameRate > 0 { fields.append(MetadataField(id: "media.fps", group: "Media", key: "Frame rate", value: String(format: "%.2f fps", info.frameRate), editable: false, sensitive: false)) }
        if info.channelCount > 0 { fields.append(MetadataField(id: "media.channels", group: "Media", key: "Channels", value: "\(info.channelCount)", editable: false, sensitive: false)) }
        if info.sampleRate > 0 { fields.append(MetadataField(id: "media.rate", group: "Media", key: "Sample rate", value: "\(Int(info.sampleRate)) Hz", editable: false, sensitive: false)) }
        let items = (try? await asset.load(.metadata)) ?? []
        let common = (try? await asset.load(.commonMetadata)) ?? []
        for item in common + items {
            guard let key = item.commonKey?.rawValue ?? (item.key.map { "\($0)" }) else { continue }
            var value = (try? await item.load(.stringValue)) ?? ""
            if value.isEmpty, let raw = try? await item.load(.value) { value = "\(raw)" }
            guard !value.isEmpty else { continue }
            let id = "av.\(item.keySpace?.rawValue ?? "common").\(key)"
            if fields.contains(where: { $0.id == id }) { continue }
            fields.append(MetadataField(id: id, group: "Tags", key: key.replacingOccurrences(of: "©", with: ""), value: value, editable: item.commonKey != nil, sensitive: key.lowercased().contains("location")))
        }
        if let ffmpegFields = await readWithFFprobe(url), !ffmpegFields.isEmpty {
            for field in ffmpegFields where !fields.contains(where: { $0.key.lowercased() == field.key.lowercased() && $0.group == field.group }) {
                fields.append(field)
            }
        }
        return fields
    }

    private static func readWithFFprobe(_ url: URL) async -> [MetadataField]? {
        guard let probe = FFmpeg.probePath else { return nil }
        guard let result = try? await Shell.run(probe, ["-v", "error", "-show_entries", "format_tags:stream_tags:chapters", "-of", "json", url.path]), result.succeeded,
              let data = result.stdout.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        var fields: [MetadataField] = []
        if let format = object["format"] as? [String: Any], let tags = format["tags"] as? [String: Any] {
            for (key, value) in tags {
                fields.append(MetadataField(id: "ff.format.\(key)", group: "Tags", key: key, value: describe(value), editable: true, sensitive: key.lowercased().contains("location")))
            }
        }
        if let streams = object["streams"] as? [[String: Any]] {
            for (index, stream) in streams.enumerated() {
                guard let tags = stream["tags"] as? [String: Any] else { continue }
                for (key, value) in tags {
                    fields.append(MetadataField(id: "ff.stream\(index).\(key)", group: "Track \(index + 1)", key: key, value: describe(value), editable: false, sensitive: false))
                }
            }
        }
        if let chapters = object["chapters"] as? [[String: Any]] {
            for (index, chapter) in chapters.enumerated() {
                let title = ((chapter["tags"] as? [String: Any])?["title"] as? String) ?? "Chapter \(index + 1)"
                let start = chapter["start_time"] as? String ?? ""
                fields.append(MetadataField(id: "ff.chapter\(index)", group: "Chapters", key: title, value: start, editable: false, sensitive: false))
            }
        }
        return fields
    }

    static func readPDF(_ url: URL) -> [MetadataField] {
        var fields = fileFields(url)
        guard let document = PDFDocument(url: url) else { return fields }
        fields.append(MetadataField(id: "pdf.pages", group: "Document", key: "Pages", value: "\(document.pageCount)", editable: false, sensitive: false))
        for (key, value) in document.documentAttributes ?? [:] {
            let name = (key.base as? PDFDocumentAttribute)?.rawValue ?? "\(key)"
            fields.append(MetadataField(id: "pdf.\(name)", group: "Document", key: name, value: describe(value), editable: true, sensitive: name == "Author" || name == "Creator" || name == "Producer"))
        }
        return fields
    }

    static func describe(_ value: Any) -> String {
        if let string = value as? String { return string }
        if let number = value as? NSNumber { return number.stringValue }
        if let date = value as? Date { return date.formatted() }
        if let array = value as? [Any] { return array.map(describe).joined(separator: ", ") }
        if let dictionary = value as? [AnyHashable: Any] { return dictionary.map { "\($0.key)=\(describe($0.value))" }.sorted().joined(separator: "; ") }
        return "\(value)"
    }

    /// A copy with these common fields changed ("" removes one), after the removals asked for.
    static func write(_ url: URL, tags: [MetadataTag: String], removeAll: Bool, removeSensitive: Bool, to destination: URL, progress: @escaping (Double) -> Void) async throws {
        guard let format = FileFormat.detect(url) else { throw OpenTangerineError.unreadable(url) }
        let tags = removeAll ? [:] : tags.filter { MetadataTag.tags(for: format).contains($0.key) }
        switch format.category {
        case .image:
            try writeImage(url, tags: tags, removeAll: removeAll, removeSensitive: removeSensitive, to: destination)
        case .audio, .video:
            try await writeAV(url, format: format, tags: tags, removeAll: removeAll || removeSensitive, to: destination, progress: progress)
        case .document where format == .pdf:
            try writePDF(url, tags: tags, removeAll: removeAll, removeSensitive: removeSensitive, to: destination)
        default:
            throw OpenTangerineError.invalidInput("Metadata editing is not supported for \(format.displayName).")
        }
        progress(1)
    }

    private static func writeImage(_ url: URL, tags: [MetadataTag: String], removeAll: Bool, removeSensitive: Bool, to destination: URL) throws {
        guard removeAll || removeSensitive else {
            try writeImageTags(url, tags: tags, to: destination)
            return
        }
        guard !tags.isEmpty else {
            try stripImage(url, removeAll: removeAll, to: destination)
            return
        }
        let stripped = FileManager.default.temporaryDirectory.appendingPathComponent("opentangerine-meta-\(UUID().uuidString).\(destination.pathExtension)")
        defer { try? FileManager.default.removeItem(at: stripped) }
        try stripImage(url, removeAll: removeAll, to: stripped)
        try writeImageTags(stripped, tags: tags, to: destination)
    }

    /// The fields people edit, written as XMP: copied without re-encoding where the format
    /// allows it (JPEG, HEIC, TIFF), otherwise with the picture written again.
    private static func writeImageTags(_ url: URL, tags: [MetadataTag: String], to destination: URL) throws {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil), let type = CGImageSourceGetType(source) else { throw OpenTangerineError.unreadable(url) }
        let outputType: CFString = ImageIOBridge.nativeEncoders.contains(type as String) ? type : (UTType.png.identifier as CFString)
        let metadata = CGImageSourceCopyMetadataAtIndex(source, 0, nil).flatMap { CGImageMetadataCreateMutableCopy($0) } ?? CGImageMetadataCreateMutable()
        for (tag, value) in tags {
            guard let (dictionary, key) = tag.imageProperty else { continue }
            for path in tag.xmpPaths { CGImageMetadataRemoveTagWithPath(metadata, nil, path as CFString) }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let written: CFTypeRef = tag == .keywords ? MetadataTag.list(trimmed) as CFArray : trimmed as CFString
            CGImageMetadataSetValueMatchingImageProperty(metadata, dictionary, key, written)
        }
        let copyable: Set<String> = [UTType.jpeg.identifier, UTType.heic.identifier, UTType.tiff.identifier]
        let count = CGImageSourceGetCount(source)
        if count == 1, copyable.contains(outputType as String), outputType == type,
           let dest = CGImageDestinationCreateWithURL(destination as CFURL, outputType, 1, nil),
           CGImageDestinationCopyImageSource(dest, source, [kCGImageDestinationMetadata: metadata, kCGImageDestinationMergeMetadata: false] as CFDictionary, nil) {
            return
        }
        guard let dest = CGImageDestinationCreateWithURL(destination as CFURL, outputType, count, nil) else { throw OpenTangerineError.encodeFailed(destination.lastPathComponent) }
        for index in 0..<count {
            guard let image = CGImageSourceCreateImageAtIndex(source, index, nil) else { continue }
            let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any]
            var options: [CFString: Any] = [:]
            if let orientation = properties?[kCGImagePropertyOrientation] { options[kCGImagePropertyOrientation] = orientation }
            CGImageDestinationAddImageAndMetadata(dest, image, index == 0 ? metadata : CGImageMetadataCreateMutable(), options as CFDictionary)
        }
        guard CGImageDestinationFinalize(dest) else { throw OpenTangerineError.encodeFailed(destination.lastPathComponent) }
    }

    private static func stripImage(_ url: URL, removeAll: Bool, to destination: URL) throws {
        let removeSensitive = !removeAll
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil), let type = CGImageSourceGetType(source) else { throw OpenTangerineError.unreadable(url) }
        let count = CGImageSourceGetCount(source)
        let outputType: CFString = ImageIOBridge.nativeEncoders.contains(type as String) ? type : (UTType.png.identifier as CFString)
        guard let dest = CGImageDestinationCreateWithURL(destination as CFURL, outputType, count, nil) else { throw OpenTangerineError.encodeFailed(destination.lastPathComponent) }
        for index in 0..<count {
            var props = (CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any]) ?? [:]
            if removeAll {
                let keep: Set<CFString> = [kCGImagePropertyOrientation, kCGImagePropertyDPIWidth, kCGImagePropertyDPIHeight, kCGImagePropertyPixelWidth, kCGImagePropertyPixelHeight, kCGImagePropertyColorModel, kCGImagePropertyHasAlpha, kCGImagePropertyDepth, kCGImagePropertyProfileName]
                props = props.filter { keep.contains($0.key) }
                props[kCGImagePropertyExifDictionary] = kCFNull
                props[kCGImagePropertyGPSDictionary] = kCFNull
                props[kCGImagePropertyIPTCDictionary] = kCFNull
                props[kCGImagePropertyTIFFDictionary] = kCFNull
                props[kCGImagePropertyMakerAppleDictionary] = kCFNull
                props[kCGImagePropertyExifAuxDictionary] = kCFNull
            } else {
                if removeSensitive {
                    props[kCGImagePropertyIPTCDictionary] = kCFNull
                    props[kCGImagePropertyGPSDictionary] = kCFNull
                    props[kCGImagePropertyMakerAppleDictionary] = kCFNull
                    props[kCGImagePropertyExifAuxDictionary] = kCFNull
                    if var exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any] {
                        for key in [kCGImagePropertyExifUserComment, kCGImagePropertyExifSubjectLocation, kCGImagePropertyExifLensModel, kCGImagePropertyExifLensMake, kCGImagePropertyExifBodySerialNumber, kCGImagePropertyExifLensSerialNumber, kCGImagePropertyExifCameraOwnerName] {
                            exif[key] = kCFNull
                        }
                        props[kCGImagePropertyExifDictionary] = exif
                    }
                    if var tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any] {
                        for key in [kCGImagePropertyTIFFMake, kCGImagePropertyTIFFModel, kCGImagePropertyTIFFSoftware, kCGImagePropertyTIFFArtist, kCGImagePropertyTIFFHostComputer] {
                            tiff[key] = kCFNull
                        }
                        props[kCGImagePropertyTIFFDictionary] = tiff
                    }
                }
            }
            var options = props
            options[kCGImageDestinationMetadata] = kCFNull
            if removeAll { options[kCGImageDestinationMergeMetadata] = false }
            CGImageDestinationAddImageFromSource(dest, source, index, options as CFDictionary)
        }
        guard CGImageDestinationFinalize(dest) else { throw OpenTangerineError.encodeFailed(destination.lastPathComponent) }
    }

    private static func writeAV(_ url: URL, format: FileFormat, tags: [MetadataTag: String], removeAll: Bool, to destination: URL, progress: @escaping (Double) -> Void) async throws {
        // FFmpeg copies the streams untouched and names each tag the way the container expects.
        if FFmpeg.isAvailable {
            var args = ["-i", url.path, "-map", "0", "-c", "copy"]
            if removeAll {
                args += ["-map_metadata", "-1", "-map_chapters", "-1"]
            } else {
                args += ["-map_metadata", "0"]
                for (tag, value) in tags.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
                    args += ["-metadata", "\(tag.ffmpegKey)=\(value.trimmingCharacters(in: .whitespacesAndNewlines))"]
                }
            }
            args.append(destination.path)
            try await FFmpeg.run(args, purpose: "Writing metadata")
            return
        }
        guard VideoEngine.nativeTargets.contains(format) || format == .m4a, await MediaInfo.isNativelyReadable(url) else {
            throw OpenTangerineError.ffmpegMissing("Editing \(format.displayName) tags")
        }
        let asset = AVURLAsset(url: url)
        var items: [AVMetadataItem] = []
        if !removeAll {
            let existing = (try? await asset.load(.metadata)) ?? []
            items = existing.filter { item in !tags.keys.contains { $0.matches(item) } }
            for (tag, value) in tags {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty, let identifier = tag.avIdentifier(for: format) else { continue }
                let item = AVMutableMetadataItem()
                item.identifier = identifier
                item.value = trimmed as NSString
                item.extendedLanguageTag = "und"
                items.append(item)
            }
        }
        try await AVExporter.export(asset: asset, to: destination, format: format, preset: AVAssetExportPresetPassthrough, metadata: items, progress: progress)
    }

    private static func writePDF(_ url: URL, tags: [MetadataTag: String], removeAll: Bool, removeSensitive: Bool, to destination: URL) throws {
        let document = try PDFOps.document(url)
        if removeAll {
            document.documentAttributes = [:]
        } else {
            var attrs = document.documentAttributes ?? [:]
            if removeSensitive {
                for key in [PDFDocumentAttribute.authorAttribute, .creatorAttribute, .producerAttribute] { attrs.removeValue(forKey: key) }
            }
            for (tag, value) in tags {
                guard let attribute = tag.pdfAttribute else { continue }
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty {
                    attrs.removeValue(forKey: attribute)
                } else {
                    attrs[attribute] = tag == .keywords ? MetadataTag.list(trimmed) as Any : trimmed as Any
                }
            }
            document.documentAttributes = attrs
        }
        guard document.write(to: destination) else { throw OpenTangerineError.encodeFailed(destination.lastPathComponent) }
    }

    /// The common fields as they are in the file now.
    static func readTags(_ url: URL) async -> [MetadataTag: String] {
        guard let format = FileFormat.detect(url) else { return [:] }
        var values: [MetadataTag: String] = [:]
        switch format.category {
        case .image:
            let props = ImageIOBridge.properties(url)
            let xmp = CGImageSourceCreateWithURL(url as CFURL, nil).flatMap { CGImageSourceCopyMetadataAtIndex($0, 0, nil) }
            for tag in MetadataTag.tags(for: format) {
                if let (dictionary, key) = tag.imageProperty, let value = (props[dictionary] as? [CFString: Any])?[key] {
                    values[tag] = tag == .keywords ? ((value as? [Any])?.map(describe).joined(separator: ", ") ?? describe(value)) : describe(value)
                } else if let xmp, let value = tag.xmpPaths.lazy.compactMap({ xmpString(xmp, $0) }).first {
                    values[tag] = value
                }
            }
        case .audio, .video:
            let asset = AVURLAsset(url: url)
            let items = ((try? await asset.load(.metadata)) ?? []) + ((try? await asset.load(.commonMetadata)) ?? [])
            for tag in MetadataTag.tags(for: format) {
                for item in items where tag.matches(item) {
                    if let value = try? await item.load(.stringValue), !value.isEmpty { values[tag] = value; break }
                }
            }
            if let probe = FFmpeg.probePath, let result = try? await Shell.run(probe, ["-v", "error", "-show_entries", "format_tags", "-of", "json", url.path]),
               let data = result.stdout.data(using: .utf8),
               let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let tagsObject = (object["format"] as? [String: Any])?["tags"] as? [String: Any] {
                let lowered = Dictionary(tagsObject.map { ($0.key.lowercased(), describe($0.value)) }, uniquingKeysWith: { a, _ in a })
                for tag in MetadataTag.tags(for: format) where values[tag] == nil {
                    if let value = lowered[tag.ffmpegKey], !value.isEmpty { values[tag] = value }
                }
            }
        case .document where format == .pdf:
            let attributes = PDFDocument(url: url)?.documentAttributes ?? [:]
            for tag in MetadataTag.tags(for: format) {
                guard let attribute = tag.pdfAttribute, let value = attributes[attribute] else { continue }
                values[tag] = tag == .keywords ? ((value as? [Any])?.map(describe).joined(separator: ", ") ?? describe(value)) : describe(value)
            }
        default:
            break
        }
        return values
    }

    private static func xmpString(_ metadata: CGImageMetadata, _ path: String) -> String? {
        guard let tag = CGImageMetadataCopyTagWithPath(metadata, nil, path as CFString), let value = CGImageMetadataTagCopyValue(tag) else { return nil }
        if let string = value as? String { return string }
        if let array = value as? [CGImageMetadataTag] {
            let parts = array.compactMap { CGImageMetadataTagCopyValue($0) as? String }
            return parts.isEmpty ? nil : parts.joined(separator: ", ")
        }
        return nil
    }
}

/// The fields people actually edit, with the same names for every kind of file.
enum MetadataTag: String, CaseIterable, Identifiable {
    case title, artist, album, genre, date, description, comment, keywords, copyright

    var id: String { rawValue }

    static func tags(for format: FileFormat) -> [MetadataTag] {
        switch format.category {
        case .image: return [.title, .description, .artist, .keywords, .copyright, .date, .comment]
        case .audio: return [.title, .artist, .album, .genre, .date, .comment, .copyright]
        case .video: return [.title, .artist, .description, .comment, .date, .copyright]
        case .document where format == .pdf: return [.title, .artist, .description, .keywords]
        default: return []
        }
    }

    func label(for format: FileFormat) -> String {
        switch self {
        case .title: return "Title"
        case .artist: return format.category == .audio ? "Artist" : "Author"
        case .album: return "Album"
        case .genre: return "Genre"
        case .date: return format.category == .image ? "Date taken" : format.category == .audio ? "Year" : "Date"
        case .description: return format == .pdf ? "Subject" : "Description"
        case .comment: return "Comment"
        case .keywords: return "Keywords"
        case .copyright: return "Copyright"
        }
    }

    func placeholder(for format: FileFormat) -> String {
        switch self {
        case .date: return format.category == .image ? "2026:10:19 14:30:00" : format.category == .audio ? "2026" : "2026-10-19"
        case .keywords: return "Separated by commas"
        default: return ""
        }
    }

    /// Where ImageIO keeps it; XMP follows from it.
    var imageProperty: (CFString, CFString)? {
        switch self {
        case .title: return (kCGImagePropertyIPTCDictionary, kCGImagePropertyIPTCObjectName)
        case .description: return (kCGImagePropertyTIFFDictionary, kCGImagePropertyTIFFImageDescription)
        case .artist: return (kCGImagePropertyTIFFDictionary, kCGImagePropertyTIFFArtist)
        case .keywords: return (kCGImagePropertyIPTCDictionary, kCGImagePropertyIPTCKeywords)
        case .copyright: return (kCGImagePropertyTIFFDictionary, kCGImagePropertyTIFFCopyright)
        case .date: return (kCGImagePropertyExifDictionary, kCGImagePropertyExifDateTimeOriginal)
        case .comment: return (kCGImagePropertyExifDictionary, kCGImagePropertyExifUserComment)
        case .album, .genre: return nil
        }
    }

    var xmpPaths: [String] {
        switch self {
        case .title: return ["dc:title", "photoshop:Headline"]
        case .description: return ["dc:description", "tiff:ImageDescription"]
        case .artist: return ["dc:creator", "tiff:Artist"]
        case .keywords: return ["dc:subject"]
        case .copyright: return ["dc:rights", "tiff:Copyright"]
        case .date: return ["exif:DateTimeOriginal", "photoshop:DateCreated"]
        case .comment: return ["exif:UserComment"]
        case .album, .genre: return []
        }
    }

    var ffmpegKey: String {
        switch self {
        case .artist: return "artist"
        default: return rawValue
        }
    }

    var commonKey: AVMetadataKey? {
        switch self {
        case .title: return .commonKeyTitle
        case .artist: return .commonKeyArtist
        case .album: return .commonKeyAlbumName
        case .description: return .commonKeyDescription
        case .date: return .commonKeyCreationDate
        case .copyright: return .commonKeyCopyrights
        default: return nil
        }
    }

    func avIdentifier(for format: FileFormat) -> AVMetadataIdentifier? {
        switch self {
        case .title: return .commonIdentifierTitle
        case .artist: return .commonIdentifierArtist
        case .album: return .commonIdentifierAlbumName
        case .description: return .commonIdentifierDescription
        case .date: return .commonIdentifierCreationDate
        case .copyright: return .commonIdentifierCopyrights
        case .genre: return format == .mov ? .quickTimeMetadataGenre : .iTunesMetadataUserGenre
        case .comment: return format == .mov ? .quickTimeMetadataComment : .iTunesMetadataUserComment
        case .keywords: return format == .mov ? .quickTimeMetadataKeywords : nil
        }
    }

    func matches(_ item: AVMetadataItem) -> Bool {
        if let commonKey, item.commonKey == commonKey { return true }
        let ids: [AVMetadataIdentifier]
        switch self {
        case .genre: ids = [.quickTimeMetadataGenre, .iTunesMetadataUserGenre, .iTunesMetadataPredefinedGenre, .id3MetadataContentType]
        case .comment: ids = [.quickTimeMetadataComment, .iTunesMetadataUserComment, .id3MetadataComments]
        case .keywords: ids = [.quickTimeMetadataKeywords]
        default: ids = []
        }
        return item.identifier.map(ids.contains) ?? false
    }

    var pdfAttribute: PDFDocumentAttribute? {
        switch self {
        case .title: return .titleAttribute
        case .artist: return .authorAttribute
        case .description: return .subjectAttribute
        case .keywords: return .keywordsAttribute
        default: return nil
        }
    }

    static func list(_ text: String) -> [String] {
        text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }
}
