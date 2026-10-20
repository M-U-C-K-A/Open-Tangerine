import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
struct WatermarkToolView: View {
    let session: ToolSession
    @StateObject private var document: ImageDocument
    @State private var options = Watermark.Options()
    @State private var useLogo = false
    @State private var logoURL: URL?
    @State private var logo: CGImage?
    @State private var preview: NSImage?
    @State private var renderTask: Task<Void, Never>?

    init(session: ToolSession) {
        self.session = session
        _document = StateObject(wrappedValue: ImageDocument(url: session.primary, previewMaxPixels: 1600))
    }

    private var ready: Bool { document.preview != nil && (useLogo ? logo != nil : !options.text.trimmingCharacters(in: .whitespaces).isEmpty) }

    var body: some View {
        ToolShell(session: session, saveTitle: session.files.count == 1 ? "Save copy" : "Apply to \(session.files.count) images", saveEnabled: ready, onSave: save) {
            ZStack {
                CheckerboardBackground()
                if let image = preview ?? document.preview {
                    ZoomableView {
                        Image(nsImage: image).resizable().interpolation(.high).aspectRatio(contentMode: .fit).padding(24)
                    }
                } else {
                    LoadingOrError(error: document.error)
                }
            }
        } sidebar: {
            SidebarSection(title: "Mark") {
                Picker("", selection: $useLogo) {
                    Text("Text").tag(false)
                    Text("Logo").tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                if useLogo {
                    HStack {
                        Text(logoURL?.lastPathComponent ?? "No image chosen")
                            .font(.callout).foregroundStyle(.secondary)
                            .lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Button("Choose…", action: chooseLogo)
                    }
                    Text("A PNG with transparency works best.").font(.caption2).foregroundStyle(.secondary)
                } else {
                    TextField("© Your name", text: $options.text)
                        .textFieldStyle(.roundedBorder)
                    Picker("", selection: $options.ink) {
                        Text("White").tag(Watermark.Ink.white)
                        Text("Black").tag(Watermark.Ink.black)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
            }
            SidebarSection(title: "Placement") {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(34), spacing: 6), count: 3), spacing: 6) {
                    ForEach(Watermark.Position.allCases.filter { $0 != .tiled }) { position in
                        Button { options.position = position } label: {
                            Image(systemName: position.symbol)
                                .frame(width: 30, height: 24)
                                .foregroundStyle(options.position == position ? Color.white : Color.primary)
                                .background(RoundedRectangle(cornerRadius: 6).fill(options.position == position ? Theme.accent : Color.primary.opacity(0.07)))
                        }
                        .buttonStyle(.plain)
                        .help(position.rawValue)
                    }
                }
                Toggle("Repeat across the picture", isOn: Binding(
                    get: { options.position == .tiled },
                    set: { options.position = $0 ? .tiled : .bottomRight }
                ))
            }
            SidebarSection(title: "Look") {
                LabeledSlider(title: "Size", value: $options.size, range: 0.015...0.2) { String(format: "%.1f%%", $0 * 100) }
                LabeledSlider(title: "Opacity", value: $options.opacity, range: 0.1...1) { String(format: "%.0f%%", $0 * 100) }
            }
            if session.files.count > 1 {
                SidebarSection(title: "Batch") {
                    Text("The same mark, at the same relative size and place, goes on all \(session.files.count) images. Each copy keeps its format.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .onChange(of: document.preview) { scheduleRender() }
        .onChange(of: options) { scheduleRender() }
        .onChange(of: useLogo) { scheduleRender() }
        .onAppear(perform: scheduleRender)
    }

    private func chooseLogo() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .heic, .tiff, .webP, .svg]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            logo = try ImageIOBridge.load(url)
            logoURL = url
            scheduleRender()
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    private func scheduleRender() {
        renderTask?.cancel()
        guard let base = document.preview?.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        let options = options
        let logo = useLogo ? logo : nil
        if useLogo, logo == nil {
            preview = nil
            return
        }
        renderTask = Task.detached(priority: .userInitiated) {
            guard let marked = try? Watermark.apply(base, options: options, logo: logo), !Task.isCancelled else { return }
            let image = ImageOps.nsImage(marked)
            await MainActor.run { preview = image }
        }
    }

    private func save() {
        let options = options
        let logo = useLogo ? logo : nil
        ImageToolSupport.saveEach(session, suffix: "watermarked", title: session.tool.progressTitle, detail: "\(session.files.count) image\(session.files.count == 1 ? "" : "s")") { _, image in
            try Watermark.apply(image, options: options, logo: logo)
        }
    }
}
