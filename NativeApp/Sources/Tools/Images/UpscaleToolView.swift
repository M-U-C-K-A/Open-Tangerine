import AppKit
import SwiftUI

@MainActor
struct UpscaleToolView: View {
    let session: ToolSession
    @StateObject private var document: ImageDocument
    @State private var method: Upscale.Method = Upscale.enhanceAvailable ? .enhance : .enlarge
    @State private var factor = 2
    @State private var showOriginal = false
    @State private var sample: CGImage?
    @State private var preview: NSImage?
    @State private var previewError: String?
    @State private var working = false
    @State private var renderTask: Task<Void, Never>?

    init(session: ToolSession) {
        self.session = session
        _document = StateObject(wrappedValue: ImageDocument(url: session.primary, previewMaxPixels: nil))
    }

    private var sizeLine: String {
        guard let original = document.original else { return "" }
        return "\(original.width) × \(original.height)  →  \(original.width * factor) × \(original.height * factor)"
    }

    private var tooLarge: String? {
        guard let original = document.original else { return nil }
        do { try Upscale.checkSize(width: original.width, height: original.height, factor: factor) } catch { return error.localizedDescription }
        return nil
    }

    var body: some View {
        ToolShell(session: session, saveTitle: session.files.count == 1 ? "Save ×\(factor)" : "Upscale \(session.files.count) images", saveEnabled: document.original != nil && tooLarge == nil, onSave: save) {
            ZStack {
                CheckerboardBackground()
                if let shown = showOriginal ? sample.map(ImageOps.nsImage) : preview {
                    // A detail at the new size, pixel for pixel, so the difference shows.
                    Image(nsImage: shown)
                        .resizable()
                        .interpolation(showOriginal ? .none : .high)
                        .aspectRatio(contentMode: .fit)
                        .padding(24)
                } else if working {
                    VStack(spacing: 10) {
                        ProgressView()
                        Text(method == .enhance ? "Rebuilding details…" : "Enlarging…").foregroundStyle(.secondary)
                    }
                } else {
                    LoadingOrError(error: previewError ?? document.error)
                }
                VStack {
                    HStack {
                        Text("Detail at the new size").font(.caption).foregroundStyle(.white.opacity(0.8))
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(.black.opacity(0.45), in: Capsule())
                        Spacer()
                    }
                    Spacer()
                    Picker("", selection: $showOriginal) {
                        Text("Before").tag(true)
                        Text("After").tag(false)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                    .environment(\.colorScheme, .dark)
                }
                .padding(12)
            }
        } sidebar: {
            SidebarSection(title: "Method") {
                Picker("", selection: $method) {
                    ForEach(Upscale.Method.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                Text(method == .enhance
                     ? (Upscale.enhanceAvailable
                        ? "Machine-learning super resolution rebuilds edges and texture, on this Mac. Best on photos and illustrations a little soft or small."
                        : "This Mac can't run super resolution, so the picture is enlarged and sharpened instead.")
                     : "Smooth resampling: bigger, true to the original, without inventing detail.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            SidebarSection(title: "Size") {
                Picker("", selection: $factor) {
                    Text("×2").tag(2)
                    Text("×4").tag(4)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                Text(sizeLine).font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                if let tooLarge {
                    Text(tooLarge).font(.caption2).foregroundStyle(.red)
                }
            }
            SidebarSection(title: "Output") {
                Text("A copy next to the original, in the same format, named “\(session.baseName) ×\(factor)”.")
                    .font(.caption2).foregroundStyle(.secondary)
                if session.files.count > 1 {
                    Text("The same method and size for all \(session.files.count) images.").font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .onChange(of: document.original) { makeSample() }
        .onChange(of: method) { scheduleRender() }
        .onChange(of: factor) { scheduleRender() }
        .onAppear(perform: makeSample)
    }

    /// A centre crop of the original, small enough to upscale quickly for the preview.
    private func makeSample() {
        guard sample == nil, let original = document.original else { return }
        let side = min(256, original.width, original.height)
        let rect = CGRect(x: (original.width - side) / 2, y: (original.height - side) / 2, width: side, height: side)
        sample = original.cropping(to: rect)
        scheduleRender()
    }

    private func scheduleRender() {
        renderTask?.cancel()
        guard let sample else { return }
        let method = method, factor = factor
        working = true
        previewError = nil
        preview = nil
        renderTask = Task {
            do {
                let result = try await Upscale.upscale(sample, factor: factor, method: method)
                guard !Task.isCancelled else { return }
                preview = ImageOps.nsImage(result)
            } catch is CancellationError {
                return
            } catch {
                previewError = error.localizedDescription
            }
            working = false
        }
    }

    private func save() {
        let method = method, factor = factor
        let quality = AppSettings.shared.jpegQuality
        let jobs = session.files.map { url -> (URL, URL, FileFormat) in
            let output = ImageToolSupport.outputFormat(for: url)
            let destination = ConversionMatrix.uniqueURL(directory: AppSettings.shared.outputLocation.directory(for: url), baseName: ConversionMatrix.strippedBaseName(url.lastPathComponent), suffix: "×\(factor)", ext: output.fileExtension)
            return (url, destination, output)
        }
        ToolWindowManager.shared.close(session)
        for (source, destination, output) in jobs {
            JobRunner.shared.run(title: session.tool.progressTitle, detail: source.lastPathComponent, symbol: session.tool.symbol) { progress in
                progress(0.1)
                let image = try ImageIOBridge.load(source)
                let result = try await Upscale.upscale(image, factor: factor, method: method)
                progress(0.85)
                try await ImageIOBridge.writeAnyFormat(result, to: destination, format: output, quality: quality)
                return [destination]
            }
        }
    }
}
