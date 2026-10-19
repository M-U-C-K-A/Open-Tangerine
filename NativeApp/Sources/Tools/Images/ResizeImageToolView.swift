import AppKit
import SwiftUI

/// Resize & compress: one window to make pictures smaller, bigger (with rebuilt detail
/// if you like) or lighter, or all of it at once.
@MainActor
struct ResizeImageToolView: View {
    let session: ToolSession
    @StateObject private var document: ImageDocument
    @AppStorage("resize.mode") private var mode: ImageSizing.Mode = .longEdge
    @AppStorage("resize.longEdge") private var longEdge = 1920
    @AppStorage("resize.enlargeToLongEdge") private var enlargeToLongEdge = false
    @AppStorage("resize.percent") private var percent = 50
    @AppStorage("resize.keepAspect") private var keepAspect = true
    @AppStorage("resize.method") private var method: Upscale.Method = Upscale.enhanceAvailable ? .enhance : .enlarge
    @AppStorage("resize.lighter") private var lighter: Lighter = .off
    @State private var width = 0
    @State private var height = 0
    @State private var targetValue: Double = 1
    @State private var targetUnit: SizeUnit = .megabytes
    @State private var sizes: [URL: CGSize] = [:]
    @State private var showOriginal = false
    @State private var sample: CGImage?
    @State private var preview: NSImage?
    @State private var previewError: String?
    @State private var working = false
    @State private var renderTask: Task<Void, Never>?

    enum Lighter: String, CaseIterable, Identifiable {
        case off, balanced, strong, target
        var id: String { rawValue }
        var title: String {
            switch self {
            case .off: return "Same quality"
            case .balanced: return "Balanced"
            case .strong: return "Strong"
            case .target: return "Target size"
            }
        }
        var preset: CompressionPreset? {
            switch self {
            case .off: return nil
            case .balanced, .target: return .balanced
            case .strong: return .strong
            }
        }
    }

    enum SizeUnit: String, CaseIterable, Identifiable {
        case kilobytes = "KB"
        case megabytes = "MB"
        var id: String { rawValue }
        var multiplier: Double { self == .kilobytes ? 1_000 : 1_000_000 }
    }

    init(session: ToolSession) {
        self.session = session
        _document = StateObject(wrappedValue: ImageDocument(url: session.primary, previewMaxPixels: nil))
    }

    private var sizing: ImageSizing {
        ImageSizing(mode: mode, longEdge: longEdge, enlargeToLongEdge: enlargeToLongEdge, percent: percent, width: width, height: height, keepAspect: keepAspect)
    }

    private var compressing: Bool { lighter != .off }

    private var enlarging: Bool { session.files.contains { sizes[$0].map(sizing.enlarges) == true } }

    private var changes: Bool { compressing || session.files.contains { url in sizes[url].map { sizing.target(for: $0) != $0 } == true } }

    /// The first picture that would grow past what this Mac should hold.
    private var tooLarge: String? {
        for url in session.files {
            guard let size = sizes[url] else { continue }
            let target = sizing.target(for: size)
            let w = Int(target.width), h = Int(target.height)
            if w > Upscale.maxSide || h > Upscale.maxSide || w * h > Upscale.maxPixels {
                return "\(url.lastPathComponent) would be \(w) × \(h) pixels, more than this Mac should hold at once."
            }
        }
        return nil
    }

    /// How much bigger the first picture gets, for the detail preview.
    private var primaryFactor: Double {
        guard let size = sizes[session.primary], size.width > 0, size.height > 0 else { return 1 }
        let target = sizing.target(for: size)
        return max(target.width / size.width, target.height / size.height)
    }

    var body: some View {
        ToolShell(session: session, saveTitle: session.files.count == 1 ? "Save copy" : "Save \(session.files.count) copies", saveEnabled: changes && tooLarge == nil && !sizes.isEmpty, onSave: save) {
            VStack(spacing: 0) {
                if enlarging, sizing.enlarges(sizes[session.primary] ?? .zero) {
                    detailPreview
                    Divider()
                }
                fileList
                    .frame(maxHeight: enlarging ? 170 : .infinity)
            }
        } sidebar: {
            SidebarSection(title: "Size") {
                Picker("", selection: $mode) {
                    ForEach(ImageSizing.Mode.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden()
                switch mode {
                case .original:
                    Text("Every pixel is kept; only the file changes.").font(.caption2).foregroundStyle(.secondary)
                case .longEdge:
                    NumberField(title: "Long edge", value: $longEdge, suffix: "px")
                    HStack {
                        ForEach([1280, 1920, 2560, 3840], id: \.self) { value in
                            Button("\(value)") { longEdge = value }.controlSize(.mini)
                        }
                    }
                    Toggle("Enlarge smaller pictures too", isOn: $enlargeToLongEdge)
                case .percent:
                    NumberField(title: "Scale", value: $percent, suffix: "%")
                    HStack {
                        ForEach([(25, "25%"), (50, "50%"), (200, "×2"), (400, "×4")], id: \.0) { value, label in
                            Button(label) { percent = value }.controlSize(.mini)
                        }
                    }
                case .exact:
                    NumberField(title: "Width", value: $width, suffix: "px")
                    NumberField(title: "Height", value: $height, suffix: "px")
                    Toggle("Keep proportions (fit inside)", isOn: $keepAspect)
                }
                if let tooLarge {
                    Text(tooLarge).font(.caption2).foregroundStyle(.red)
                }
            }
            if enlarging {
                SidebarSection(title: "Enlarging") {
                    Picker("", selection: $method) {
                        ForEach(Upscale.Method.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented).labelsHidden()
                    Text(method == .enhance
                         ? (Upscale.enhanceAvailable
                            ? "Machine-learning super resolution rebuilds edges and texture, on this Mac. Best on photos and illustrations a little soft or small."
                            : "This Mac can't run super resolution, so pictures are enlarged and sharpened instead.")
                         : "Smooth resampling: bigger, true to the original, without inventing detail.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            SidebarSection(title: "File") {
                Picker("", selection: $lighter) {
                    ForEach(Lighter.allCases) { Text($0.title).tag($0) }
                }
                .labelsHidden()
                if lighter == .target {
                    HStack(spacing: 6) {
                        TextField("Size", value: $targetValue, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 70)
                        Picker("", selection: $targetUnit) {
                            ForEach(SizeUnit.allCases) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.segmented).labelsHidden().fixedSize()
                        Text("each").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Text(fileHint).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .task {
            for url in session.files { sizes[url] = ImageIOBridge.pixelSize(url) }
            if let first = sizes[session.primary] { width = Int(first.width); height = Int(first.height) }
        }
        .onChange(of: document.original) { makeSample() }
        .onChange(of: method) { scheduleRender() }
        .onChange(of: sizing) { scheduleRender() }
        .onAppear(perform: makeSample)
    }

    private var fileHint: String {
        switch lighter {
        case .off: return "Saved in the same format, at the quality set in Settings."
        case .balanced: return "Noticeably lighter with little visible change. PNGs without transparency become JPEGs."
        case .strong: return "The lightest file; the loss shows up close. PNGs without transparency become JPEGs."
        case .target: return "The best quality that fits, shrinking the picture only if it must."
        }
    }

    private var fileList: some View {
        List(session.files, id: \.self) { url in
            HStack {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().frame(width: 28, height: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(url.lastPathComponent).lineLimit(1).truncationMode(.middle)
                    if let size = sizes[url] {
                        let target = sizing.target(for: size)
                        Text(target == size
                             ? "\(Int(size.width)) × \(Int(size.height))  ·  \(FileSizeFormatter.string(FileSizeFormatter.size(of: url)))"
                             : "\(Int(size.width)) × \(Int(size.height))  →  \(Int(target.width)) × \(Int(target.height))  ·  \(FileSizeFormatter.string(FileSizeFormatter.size(of: url)))")
                            .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Text(ImageResizer.outputFormat(for: url, compressing: compressing).displayName)
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .listStyle(.inset)
    }

    private var detailPreview: some View {
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
    }

    /// A centre crop of the first picture, small enough to enlarge quickly for the preview.
    private func makeSample() {
        guard sample == nil, let original = document.original else { return }
        let side = min(256, original.width, original.height)
        let rect = CGRect(x: (original.width - side) / 2, y: (original.height - side) / 2, width: side, height: side)
        sample = original.cropping(to: rect)
        scheduleRender()
    }

    private func scheduleRender() {
        renderTask?.cancel()
        guard let sample, primaryFactor > 1 else { preview = nil; working = false; return }
        let method = method
        // Never more than 2048 pixels a side for the preview, whatever the factor.
        let factor = min(primaryFactor, 2048 / Double(max(sample.width, sample.height)))
        let size = CGSize(width: (Double(sample.width) * factor).rounded(), height: (Double(sample.height) * factor).rounded())
        working = true
        previewError = nil
        preview = nil
        renderTask = Task {
            do {
                try await Task.sleep(for: .milliseconds(150))
                let result = try await Upscale.resize(sample, to: size, method: method)
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
        let sizing = sizing, method = method
        let preset = lighter.preset
        let target = lighter == .target ? Int64(targetValue * targetUnit.multiplier) : nil
        let quality = AppSettings.shared.jpegQuality
        let jobs = session.files.map { url -> (URL, URL) in
            let size = sizes[url] ?? .zero
            let output = ImageResizer.outputFormat(for: url, compressing: preset != nil)
            let suffix = ImageResizer.suffix(sizing: sizing, size: size, compressing: preset != nil)
            let destination = ConversionMatrix.uniqueURL(directory: AppSettings.shared.outputLocation.directory(for: url), baseName: ConversionMatrix.strippedBaseName(url.lastPathComponent), suffix: suffix, ext: output.fileExtension)
            return (url, destination)
        }
        ToolWindowManager.shared.close(session)
        for (source, destination) in jobs {
            JobRunner.shared.run(title: session.tool.progressTitle, detail: source.lastPathComponent, symbol: session.tool.symbol) { progress in
                try await ImageResizer.process(source, sizing: sizing, method: method, preset: preset, targetBytes: target, quality: quality, to: destination, progress: progress)
                return [destination]
            }
        }
    }
}
