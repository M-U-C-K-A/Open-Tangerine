import Foundation

/// What a file holds for translation, and how the translated text is put back:
/// subtitles keep every timing, text keeps its paragraphs, pictures and PDFs give
/// their recognised text. The translating itself is Apple's, on this Mac.
enum TextTranslation {
    enum Document {
        case subtitles([SubtitleCue], FileFormat)
        case paragraphs([String])

        /// The pieces sent for translation, in order.
        var segments: [String] {
            switch self {
            case .subtitles(let cues, _): return cues.map { SubtitleParser.stripTags($0.text) }
            case .paragraphs(let paragraphs): return paragraphs
            }
        }

        var outputFormat: FileFormat {
            switch self {
            case .subtitles(_, let format): return format
            case .paragraphs: return .txt
            }
        }

        /// The same document with each segment replaced by its translation.
        func rebuilt(with translations: [String]) -> String {
            switch self {
            case let .subtitles(cues, format):
                let translated = zip(cues, translations).map { SubtitleCue(start: $0.start, end: $0.end, text: $1) }
                return SubtitleParser.serialize(translated, as: format)
            case .paragraphs:
                return translations.joined(separator: "\n\n") + "\n"
            }
        }
    }

    static func document(for url: URL) throws -> Document {
        switch FileFormat.detect(url) {
        case let format? where format == .srt || format == .vtt:
            let cues = SubtitleParser.parse(try String(contentsOf: url, encoding: .utf8), hint: format)
            guard !cues.isEmpty else { throw OpenTangerineError.invalidInput("No subtitles found in \(url.lastPathComponent).") }
            return .subtitles(cues, format)
        case .txt?:
            return .paragraphs(paragraphs(try String(contentsOf: url, encoding: .utf8)))
        case let format? where format == .pdf || format.category == .image:
            return .paragraphs(paragraphs(try TextRecognition.text(in: [url])))
        default:
            throw OpenTangerineError.invalidInput("\(url.lastPathComponent) has no text to translate.")
        }
    }

    /// Paragraphs are separated by blank lines; lines inside one stay together.
    static func paragraphs(_ text: String) -> [String] {
        text.replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// “movie.srt” in French becomes “movie.fr.srt”, the name video players look for.
    static func outputURL(for source: URL, language: String, format: FileFormat, directory: URL) -> URL {
        ConversionMatrix.uniqueURL(directory: directory, baseName: "\(ConversionMatrix.strippedBaseName(source.lastPathComponent)).\(language)", suffix: "", ext: format.fileExtension)
    }
}
