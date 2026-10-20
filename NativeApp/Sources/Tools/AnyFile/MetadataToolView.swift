import SwiftUI

@MainActor
struct MetadataToolView: View {
    let session: ToolSession
    @State private var fields: [MetadataField] = []
    @State private var tags: [MetadataTag: String] = [:]
    @State private var original: [MetadataTag: String] = [:]
    @State private var loading = true
    @State private var search = ""
    @State private var removeAll = false
    @State private var removeSensitive = false
    @State private var selectedFile: URL

    init(session: ToolSession) {
        self.session = session
        _selectedFile = State(initialValue: session.primary)
    }

    private var format: FileFormat { FileFormat.detect(selectedFile) ?? .jpg }

    /// Only the fields you changed are written, to every selected file.
    private var changes: [MetadataTag: String] {
        tags.filter { ($0.value.trimmingCharacters(in: .whitespaces)) != (original[$0.key] ?? "").trimmingCharacters(in: .whitespaces) }
    }

    private var groups: [(String, [MetadataField])] {
        let filtered = fields.filter { search.isEmpty || $0.key.localizedCaseInsensitiveContains(search) || $0.value.localizedCaseInsensitiveContains(search) || $0.group.localizedCaseInsensitiveContains(search) }
        let order = ["File", "Media", "Document", "Tags", "Image", "Exif", "TIFF", "GPS", "IPTC", "MakerApple", "Chapters"]
        var dict: [String: [MetadataField]] = [:]
        for field in filtered { dict[field.group, default: []].append(field) }
        return dict.keys.sorted { a, b in
            let ia = order.firstIndex(of: a) ?? Int.max
            let ib = order.firstIndex(of: b) ?? Int.max
            return ia == ib ? a < b : ia < ib
        }.map { ($0, dict[$0] ?? []) }
    }

    private var saveEnabled: Bool { removeAll || removeSensitive || !changes.isEmpty }

    var body: some View {
        ToolShell(session: session, saveTitle: session.files.count == 1 ? "Save copy" : "Apply to \(session.files.count) files", saveEnabled: saveEnabled, onSave: run) {
            VStack(spacing: 0) {
                HStack {
                    if session.files.count > 1 {
                        Picker("Showing", selection: $selectedFile) {
                            ForEach(session.files, id: \.self) { Text($0.lastPathComponent).tag($0) }
                        }
                        .frame(maxWidth: 320)
                    }
                    Spacer()
                    TextField("Search everything in the file", text: $search)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 240)
                }
                .padding(12)
                Divider()
                if loading {
                    LoadingOrError(error: nil)
                } else {
                    List {
                        if !MetadataTag.tags(for: format).isEmpty {
                            Section("Fields") {
                                ForEach(MetadataTag.tags(for: format)) { tag in
                                    tagRow(tag)
                                }
                            }
                            .disabled(removeAll)
                            .opacity(removeAll ? 0.4 : 1)
                        }
                        ForEach(groups, id: \.0) { group, items in
                            Section(group) {
                                ForEach(items) { field in
                                    fieldRow(field)
                                }
                            }
                        }
                    }
                    .listStyle(.inset(alternatesRowBackgrounds: true))
                }
            }
        } sidebar: {
            SidebarSection(title: "Fields") {
                Text(changes.isEmpty
                     ? "Type in a field to add it or change it; empty it to remove it. Only what you change is written."
                     : "\(changes.count) field\(changes.count == 1 ? "" : "s") changed: \(changes.keys.map { $0.label(for: format) }.sorted().joined(separator: ", ")).")
                    .font(.caption2).foregroundStyle(changes.isEmpty ? Color.secondary : Theme.accent)
                if !changes.isEmpty {
                    Button("Undo changes") { tags = original }.controlSize(.small)
                }
                if session.files.count > 1 {
                    Text("Changed fields go to all \(session.files.count) files; the others keep their own values.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            SidebarSection(title: "Remove") {
                Toggle("Remove all metadata", isOn: $removeAll)
                Toggle("Remove camera, GPS and processing data", isOn: $removeSensitive).disabled(removeAll)
                Text("Orientation and color profile are kept. For audio and video, removing sensitive data clears every tag. The copy is saved next to the original, which stays as it is.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            SidebarSection(title: "Summary") {
                let sensitive = fields.filter(\.sensitive).count
                Text("\(fields.count) fields · \(sensitive) sensitive").font(.callout.monospacedDigit())
            }
        }
        .task(id: selectedFile) { await load() }
    }

    private func tagRow(_ tag: MetadataTag) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(tag.label(for: format)).font(.callout).frame(width: 140, alignment: .leading)
            TextField(tag.placeholder(for: format), text: Binding(get: { tags[tag] ?? "" }, set: { tags[tag] = $0 }))
                .textFieldStyle(.roundedBorder)
            if (tags[tag] ?? "") != (original[tag] ?? "") {
                Circle().fill(Theme.accent).frame(width: 6, height: 6).help("Changed")
            }
        }
    }

    private func fieldRow(_ field: MetadataField) -> some View {
        HStack(alignment: .firstTextBaseline) {
            HStack(spacing: 4) {
                if field.sensitive {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange).font(.caption)
                }
                Text(field.key).font(.callout).frame(width: 200, alignment: .leading).lineLimit(1)
            }
            Text(field.value).font(.callout).foregroundStyle(.secondary).textSelection(.enabled).lineLimit(3)
            Spacer()
        }
    }

    private func load() async {
        loading = true
        let url = selectedFile
        fields = await MetadataOps.read(url)
        let current = await MetadataOps.readTags(url)
        // Switching the file shown keeps what you typed; the reference is that file's values.
        let typed = changes
        original = current
        tags = current.merging(typed) { _, new in new }
        loading = false
    }

    private func run() {
        let changes = changes
        let removeAll = removeAll
        let removeSensitive = removeSensitive
        for url in session.files {
            guard let format = FileFormat.detect(url) else { continue }
            let base = ConversionMatrix.strippedBaseName(url.lastPathComponent)
            let ext = format.category == .image && !ImageIOBridge.canEncodeNatively(format) ? "png" : url.pathExtension
            let destination = ConversionMatrix.uniqueURL(directory: session.outputDirectory, baseName: base, suffix: removeAll ? "clean" : "edited", ext: ext)
            JobRunner.shared.run(title: "Editing metadata", detail: "\(url.lastPathComponent)", symbol: ToolID.editMetadata.symbol) { progress in
                try await MetadataOps.write(url, tags: changes, removeAll: removeAll, removeSensitive: removeSensitive, to: destination, progress: progress)
                return [destination]
            }
        }
        ToolWindowManager.shared.close(session)
    }
}
