import SwiftUI
import Translation

@MainActor
struct TranslateToolView: View {
    let session: ToolSession
    @State private var languages: [Locale.Language] = []
    @State private var source: Locale.Language?
    @State private var target: Locale.Language = Locale.current.language
    @State private var configuration: TranslationSession.Configuration?
    @State private var sample: [String] = []
    @State private var status = ""
    @State private var failure: String?
    @State private var working = false
    @State private var done = 0

    var body: some View {
        FormShell(session: session,
                  saveTitle: working ? "Translating…" : (session.files.count == 1 ? "Translate" : "Translate \(session.files.count) files"),
                  saveEnabled: !working && !languages.isEmpty,
                  onSave: start) {
            HStack(spacing: 16) {
                FormRow(title: "From") {
                    Picker("", selection: $source) {
                        Text("Detect automatically").tag(Locale.Language?.none)
                        Divider()
                        ForEach(languages, id: \.minimalIdentifier) { Text(name($0)).tag(Optional($0)) }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                Image(systemName: "arrow.right").foregroundStyle(.secondary)
                FormRow(title: "To") {
                    Picker("", selection: $target) {
                        ForEach(languages, id: \.minimalIdentifier) { Text(name($0)).tag($0) }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
            }
            FormHint("Apple translates on this Mac. The first time you use a language, macOS asks to download it.")

            VStack(alignment: .leading, spacing: 8) {
                Text(sample.isEmpty ? "Reading the text…" : "Beginning of \(session.primary.lastPathComponent)")
                    .font(.caption).foregroundStyle(.secondary)
                Text(sample.prefix(6).joined(separator: "\n\n"))
                    .font(.callout)
                    .lineLimit(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(16)
            .card()

            if working || !status.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    if working {
                        ProgressView(value: Double(done), total: Double(max(session.files.count, 1)))
                    }
                    Text(status).font(.callout).foregroundStyle(.secondary)
                }
            }
            if let failure {
                Text(failure).font(.callout).foregroundStyle(.red)
            }
            FormHint("Subtitles keep every timing and are saved as “name.\(target.minimalIdentifier).srt”, which players pick up by themselves. Pictures and PDFs give their text, translated, as .txt.")
        }
        .task { await prepare() }
        .translationTask(configuration) { session in
            await translate(with: session)
        }
    }

    private func name(_ language: Locale.Language) -> String {
        Locale.current.localizedString(forIdentifier: language.minimalIdentifier) ?? language.minimalIdentifier
    }

    private func prepare() async {
        let supported = await LanguageAvailability().supportedLanguages
        var seen = Set<String>()
        languages = supported.filter { seen.insert($0.minimalIdentifier).inserted }.sorted { name($0) < name($1) }
        if !languages.contains(where: { $0.minimalIdentifier == target.minimalIdentifier }) {
            target = languages.first { $0.minimalIdentifier.hasPrefix("en") } ?? languages.first ?? target
        } else if let match = languages.first(where: { $0.minimalIdentifier == target.minimalIdentifier }) {
            target = match
        }
        let url = session.primary
        if let document = try? await Task.detached(priority: .userInitiated, operation: { try TextTranslation.document(for: url) }).value {
            sample = document.segments
        }
    }

    private func start() {
        failure = nil
        done = 0
        status = "Preparing \(name(target))…"
        working = true
        // A new configuration starts the translation task; macOS asks about downloads if needed.
        if configuration == nil {
            configuration = TranslationSession.Configuration(source: source, target: target)
        } else {
            configuration?.source = source
            configuration?.target = target
            configuration?.invalidate()
        }
    }

    private func translate(with translator: TranslationSession) async {
        guard working else { return }
        var outputs: [URL] = []
        let code = target.minimalIdentifier
        for url in session.files {
            status = "Translating \(url.lastPathComponent)…"
            do {
                let document = try await Task.detached(priority: .userInitiated) { try TextTranslation.document(for: url) }.value
                let segments = document.segments
                let requests = segments.enumerated().compactMap { index, text in
                    text.isEmpty ? nil : TranslationSession.Request(sourceText: text, clientIdentifier: String(index))
                }
                var translated = segments
                for response in try await translator.translations(from: requests) {
                    if let id = response.clientIdentifier, let index = Int(id) { translated[index] = response.targetText }
                }
                let destination = TextTranslation.outputURL(for: url, language: code, format: document.outputFormat, directory: AppSettings.shared.outputLocation.directory(for: url))
                try document.rebuilt(with: translated).write(to: destination, atomically: true, encoding: .utf8)
                outputs.append(destination)
            } catch {
                failure = "\(url.lastPathComponent): \(error.localizedDescription)"
            }
            done += 1
        }
        working = false
        guard failure == nil else {
            status = outputs.isEmpty ? "" : "\(outputs.count) translated."
            return
        }
        let finished = outputs
        ToolWindowManager.shared.close(session)
        JobRunner.shared.run(title: "Translated to \(name(target))", detail: finished.count == 1 ? finished[0].lastPathComponent : "\(finished.count) files", symbol: self.session.tool.symbol) { _ in finished }
    }
}
