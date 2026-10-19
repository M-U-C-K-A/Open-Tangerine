import AVFoundation
import Foundation
import Speech

/// Subtitles from what is said in a video or a recording, with Apple's on-device speech
/// recognition. The first time, macOS downloads the model for the chosen language.
enum SpeechSubtitles {
    struct Word: Equatable {
        let text: String
        let start: Double
        let end: Double
    }

    /// Cues of at most two short lines and a few seconds, cut at the end of sentences when it can.
    static func cues(from words: [Word], maxCharacters: Int = 84, maxDuration: Double = 6) -> [SubtitleCue] {
        var cues: [SubtitleCue] = []
        var current: [Word] = []
        func flush() {
            guard let first = current.first, let last = current.last else { return }
            let text = current.map(\.text).joined(separator: " ").replacingOccurrences(of: " ,", with: ",").replacingOccurrences(of: " .", with: ".")
            cues.append(SubtitleCue(start: first.start, end: max(last.end, first.start + 0.8), text: wrap(text, width: maxCharacters / 2)))
            current = []
        }
        for word in words where !word.text.trimmingCharacters(in: .whitespaces).isEmpty {
            let length = current.map(\.text.count).reduce(0, +) + current.count + word.text.count
            if let first = current.first, length > maxCharacters || word.end - first.start > maxDuration || word.start - (current.last?.end ?? word.start) > 1.5 {
                flush()
            }
            current.append(Word(text: word.text.trimmingCharacters(in: .whitespaces), start: word.start, end: word.end))
            if let last = word.text.last, ".?!…".contains(last), current.map(\.text.count).reduce(0, +) > 10 { flush() }
        }
        flush()
        return cues
    }

    /// Breaks a cue into two balanced lines when it is long.
    static func wrap(_ text: String, width: Int) -> String {
        guard text.count > width else { return text }
        let words = text.split(separator: " ")
        var best = text, bestScore = Int.max
        for split in 1..<words.count {
            let first = words[..<split].joined(separator: " "), second = words[split...].joined(separator: " ")
            let score = abs(first.count - second.count)
            if score < bestScore { best = first + "\n" + second; bestScore = score }
        }
        return best
    }

    /// The languages this Mac can transcribe.
    static func languages() async -> [Locale] {
        await SpeechTranscriber.supportedLocales.sorted { name($0) < name($1) }
    }

    static func name(_ locale: Locale) -> String {
        Locale.current.localizedString(forIdentifier: locale.identifier) ?? locale.identifier
    }

    /// Asks once for speech recognition, as macOS requires.
    static func authorize() async -> Bool {
        if SFSpeechRecognizer.authorizationStatus() == .authorized { return true }
        return await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0 == .authorized) }
        }
    }

    static func transcribe(_ url: URL, locale: Locale, progress: @escaping (Double) -> Void) async throws -> [SubtitleCue] {
        guard let supported = await SpeechTranscriber.supportedLocale(equivalentTo: locale) else {
            throw OpenTangerineError.invalidInput("\(name(locale)) can't be transcribed on this Mac.")
        }
        let transcriber = SpeechTranscriber(locale: supported, transcriptionOptions: [], reportingOptions: [], attributeOptions: [.audioTimeRange])
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await request.downloadAndInstall()
        }
        progress(0.1)
        // A plain audio copy the analyzer can read, whatever the container.
        let audio = FileManager.default.temporaryDirectory.appendingPathComponent("opentangerine-speech-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: audio) }
        if FFmpeg.isAvailable {
            _ = try await FFmpeg.run(["-i", url.path, "-vn", "-ac", "1", "-ar", "16000", "-c:a", "pcm_s16le", audio.path], purpose: "Preparing audio")
        } else {
            try await AVExporter.exportAudioPCM(asset: AVURLAsset(url: url), to: audio, format: .wav)
        }
        progress(0.2)
        let file = try AVAudioFile(forReading: audio)
        let duration = Double(file.length) / file.fileFormat.sampleRate
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        let collector = Task { () throws -> [Word] in
            var words: [Word] = []
            for try await result in transcriber.results {
                for (range, slice) in result.text.runs[\.audioTimeRange] {
                    let text = String(result.text[slice].characters).trimmingCharacters(in: .whitespacesAndNewlines)
                    guard let range, !text.isEmpty else { continue }
                    words.append(Word(text: text, start: range.start.seconds, end: range.end.seconds))
                    if duration > 0 { progress(0.2 + 0.75 * min(1, range.end.seconds / duration)) }
                }
            }
            return words
        }
        do {
            if let last = try await analyzer.analyzeSequence(from: file) {
                try await analyzer.finalizeAndFinish(through: last)
            } else {
                await analyzer.cancelAndFinishNow()
            }
        } catch {
            collector.cancel()
            throw OpenTangerineError.toolFailed("Speech recognition", error.localizedDescription)
        }
        let words = try await collector.value
        guard !words.isEmpty else { throw OpenTangerineError.invalidInput("No speech found in \(url.lastPathComponent).") }
        return cues(from: words)
    }
}
