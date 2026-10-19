import SwiftUI

@MainActor
struct TranscribeToolView: View {
    let session: ToolSession
    @State private var languages: [Locale] = []
    @State private var language = Locale.current
    @State private var format: FileFormat = .srt
    @State private var denied = false

    var body: some View {
        FormShell(session: session, saveTitle: session.files.count == 1 ? "Make subtitles" : "Subtitle \(session.files.count) files", saveEnabled: !languages.isEmpty, onSave: start) {
            FormRow(title: "Spoken language") {
                Picker("", selection: $language) {
                    ForEach(languages, id: \.identifier) { Text(SpeechSubtitles.name($0)).tag($0) }
                }
                .labelsHidden()
                .fixedSize()
            }
            FormRow(title: "Save as") {
                SegmentedPicker(selection: $format, options: [(.srt, "SRT"), (.vtt, "WebVTT"), (.txt, "Text")])
            }
            FormHint("Apple's speech recognition runs on this Mac. The first time you use a language, macOS downloads its model, and asks once to allow speech recognition.")
            FormHint("Subtitles are timed word by word, two short lines at most, and saved as “\(session.baseName).\(language.language.minimalIdentifier).\(format.fileExtension)” next to the original, so players find them.")
            if denied {
                Text("Speech recognition is turned off for Open Tangerine. Allow it in System Settings → Privacy & Security → Speech Recognition.")
                    .font(.callout).foregroundStyle(.red)
            }
        }
        .task {
            languages = await SpeechSubtitles.languages()
            let wanted = language.language.minimalIdentifier
            language = languages.first { $0.identifier == Locale.current.identifier }
                ?? languages.first { $0.language.minimalIdentifier == wanted }
                ?? languages.first { $0.identifier.hasPrefix("en") }
                ?? languages.first
                ?? language
        }
    }

    private func start() {
        Task {
            guard await SpeechSubtitles.authorize() else {
                denied = true
                return
            }
            let language = language, format = format
            ToolWindowManager.shared.close(session)
            for source in session.files {
                let destination = TextTranslation.outputURL(for: source, language: language.language.minimalIdentifier, format: format, directory: AppSettings.shared.outputLocation.directory(for: source))
                JobRunner.shared.run(title: session.tool.progressTitle, detail: source.lastPathComponent, symbol: session.tool.symbol) { progress in
                    let cues = try await SpeechSubtitles.transcribe(source, locale: language, progress: progress)
                    try SubtitleParser.serialize(cues, as: format).write(to: destination, atomically: true, encoding: .utf8)
                    return [destination]
                }
            }
        }
    }
}
