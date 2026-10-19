import AppKit
import CoreImage
import SwiftUI

@MainActor
struct RemoveBackgroundToolView: View {
    let session: ToolSession
    @StateObject private var document: ImageDocument
    @State private var softness: Double = 0
    @State private var cropToSubject = false
    @State private var showOriginal = false
    @State private var subject: Subject?
    @State private var detectionError: String?
    @State private var detecting = false
    @State private var rendered: NSImage?
    @State private var renderTask: Task<Void, Never>?

    /// The preview image and its Vision mask, computed once; softness and cropping only re-blend.
    struct Subject {
        let image: CIImage
        let mask: CIImage
    }

    init(session: ToolSession) {
        self.session = session
        _document = StateObject(wrappedValue: ImageDocument(url: session.primary, previewMaxPixels: 1600))
    }

    private var options: BackgroundRemoval.Options {
        BackgroundRemoval.Options(softness: softness, cropToSubject: cropToSubject)
    }

    private var saveTitle: String {
        session.files.count == 1 ? "Save PNG" : "Remove from \(session.files.count) images"
    }

    var body: some View {
        ToolShell(session: session, saveTitle: saveTitle, saveEnabled: session.files.count > 1 || subject != nil, onSave: save) {
            ZStack {
                CheckerboardBackground()
                if showOriginal, let preview = document.preview {
                    Image(nsImage: preview).resizable().interpolation(.high).aspectRatio(contentMode: .fit).padding(12)
                } else if let rendered {
                    Image(nsImage: rendered).resizable().interpolation(.high).aspectRatio(contentMode: .fit).padding(12)
                } else if detecting {
                    VStack(spacing: 10) {
                        ProgressView()
                        Text("Finding the subject…").foregroundStyle(.secondary)
                    }
                } else {
                    LoadingOrError(error: detectionError ?? document.error)
                }
                VStack {
                    Spacer()
                    Picker("", selection: $showOriginal) {
                        Text("Before").tag(true)
                        Text("After").tag(false)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                    .disabled(document.preview == nil)
                    // The checkerboard is dark in both appearances.
                    .environment(\.colorScheme, .dark)
                    .padding(12)
                }
            }
        } sidebar: {
            SidebarSection(title: "Edges") {
                LabeledSlider(title: "Softness", value: $softness, range: 0...1) { String(format: "%.0f%%", $0 * 100) }
                Toggle("Crop to subject", isOn: $cropToSubject)
            }
            SidebarSection(title: "Output") {
                Text(session.files.count == 1
                     ? "A transparent PNG next to the original, named “\(session.baseName) \(BackgroundRemoval.suffix).png”."
                     : "A transparent PNG next to each original, named like “\(session.baseName) \(BackgroundRemoval.suffix).png”.")
                    .font(.caption2).foregroundStyle(.secondary)
                Text("Apple Vision finds the people, animals and objects in front and clears everything else, on this Mac.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            if session.files.count > 1 {
                SidebarSection(title: "Batch") {
                    Text("The same edges are applied to all \(session.files.count) images. Each one gets its own job; an image without a clear subject fails alone.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .onAppear(perform: detectSubject)
        .onChange(of: document.preview) { _ in detectSubject() }
        .onChange(of: softness) { _ in scheduleRender() }
        .onChange(of: cropToSubject) { _ in scheduleRender() }
    }

    private func detectSubject() {
        guard subject == nil, !detecting, let preview = document.preview,
              let cg = preview.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        detecting = true
        detectionError = nil
        Task.detached(priority: .userInitiated) {
            do {
                let found = Subject(image: CIImage(cgImage: cg), mask: try BackgroundRemoval.mask(for: cg))
                await MainActor.run {
                    subject = found
                    detecting = false
                    scheduleRender()
                }
            } catch {
                await MainActor.run {
                    detectionError = error.localizedDescription
                    detecting = false
                }
            }
        }
    }

    private func scheduleRender() {
        renderTask?.cancel()
        guard let subject else { return }
        let options = options
        renderTask = Task.detached(priority: .userInitiated) {
            guard let cutout = try? BackgroundRemoval.cutout(subject.image, mask: subject.mask, options: options), !Task.isCancelled else { return }
            let image = ImageOps.nsImage(cutout)
            await MainActor.run { rendered = image }
        }
    }

    private func save() {
        let options = options
        let destinations = BackgroundRemoval.outputURLs(for: session.files) { AppSettings.shared.outputLocation.directory(for: $0) }
        ToolWindowManager.shared.close(session)
        for (source, destination) in zip(session.files, destinations) {
            JobRunner.shared.run(title: session.tool.progressTitle, detail: source.lastPathComponent, symbol: session.tool.symbol) { progress in
                progress(0.1)
                try await Task.detached(priority: .userInitiated) {
                    let cutout = try BackgroundRemoval.remove(try ImageIOBridge.load(source), options: options)
                    try ImageIOBridge.write(cutout, to: destination, format: .png)
                }.value
                return [destination]
            }
        }
    }
}
