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
    @AppStorage("resize.social") private var social: SocialFormat = .instagramPost
    @AppStorage("resize.socialFill") private var socialFill = true
    @AppStorage("social.account") private var account = ""
    @AppStorage("social.title") private var postTitle = ""
    @AppStorage("social.caption") private var caption = ""
    @State private var showCovered = true
    @State private var width = 0
    @State private var height = 0
    @State private var targetValue: Double = 1
    @State private var targetUnit: SizeUnit = .megabytes
    @State private var sizes: [URL: CGSize] = [:]
    @State private var showOriginal = false
    @State private var zoom: Zoom = .whole
    @StateObject private var render = LatestRenderer<ResizePreview>()
    @State private var requested = 0

    enum Zoom: String, CaseIterable, Identifiable {
        case feed, whole, detail
        var id: String { rawValue }
    }

    /// The first picture, made exactly as it will be saved: what it looks like and weighs.
    struct ResizePreview: Sendable {
        let request: Int
        let before: CGImage
        let after: CGImage
        let size: CGSize
        let bytes: Int64
        let format: FileFormat
        let error: String?
    }

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
        ImageSizing(mode: mode, longEdge: longEdge, enlargeToLongEdge: enlargeToLongEdge, percent: percent, width: width, height: height, keepAspect: keepAspect, social: social, socialFill: socialFill)
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

    var body: some View {
        ToolShell(session: session, saveTitle: session.files.count == 1 ? "Save copy" : "Save \(session.files.count) copies", saveEnabled: changes && tooLarge == nil && !sizes.isEmpty, onSave: save) {
            VStack(spacing: 0) {
                previewPane
                if session.files.count > 1 {
                    Divider()
                    fileList.frame(height: min(170, CGFloat(session.files.count) * 44 + 12))
                }
            }
        } sidebar: {
            SidebarSection(title: "Size") {
                Picker("", selection: $mode) {
                    ForEach(ImageSizing.Mode.allCases) { Text($0.title).tag($0) }
                }
                .labelsHidden()
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
                case .social:
                    Picker("", selection: $social) {
                        ForEach(SocialFormat.imageFormats) { Text($0.title).tag($0) }
                    }
                    .labelsHidden()
                    Picker("", selection: $socialFill) {
                        Text("Crop around the subject").tag(true)
                        Text("Fit, blurred sides").tag(false)
                    }
                    .pickerStyle(.radioGroup).labelsHidden()
                    Text("\(Int(social.size.width)) × \(Int(social.size.height)) pixels. Cropping keeps what draws the eye in the frame, found on this Mac.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                if let tooLarge {
                    Text(tooLarge).font(.caption2).foregroundStyle(.red)
                }
            }
            if mode == .social {
                SidebarSection(title: "In the preview") {
                    TextField("Account name", text: $account).textFieldStyle(.roundedBorder)
                    if social.layout != .feed {
                        TextField(social.layout == .video ? "Video title" : social == .tiktok ? "Sound" : social == .pinterestPin ? "Pin title" : "Name shown", text: $postTitle).textFieldStyle(.roundedBorder)
                    }
                    TextField(social.layout == .video ? "Description" : "Caption", text: $caption, axis: .vertical)
                        .lineLimit(2...4).textFieldStyle(.roundedBorder)
                    if social.layout == .story {
                        Toggle("Show what the buttons cover", isOn: $showCovered)
                    }
                    Text("Only for the preview, to see the picture as it will appear; the saved file is the picture alone.")
                        .font(.caption2).foregroundStyle(.secondary)
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
            zoom = mode == .social ? .feed : enlarging ? .detail : .whole
            refreshPreview()
        }
        .onChange(of: document.original) { refreshPreview() }
        .onChange(of: method) { refreshPreview() }
        .onChange(of: sizing) { refreshPreview() }
        .onChange(of: lighter) { refreshPreview() }
        .onChange(of: targetValue) { refreshPreview() }
        .onChange(of: targetUnit) { refreshPreview() }
        .onChange(of: zoom) { refreshPreview() }
        .onChange(of: enlarging) { if enlarging, mode != .social { zoom = .detail } }
        .onChange(of: mode) { if mode == .social { zoom = .feed } else if zoom == .feed { zoom = .whole } }
    }

    private var current: ResizePreview? {
        render.output.flatMap { $0.request == requested ? $0 : nil }
    }

    private var previewPane: some View {
        ZStack {
            CheckerboardBackground()
            if let shown = render.output, zoom == .feed, mode == .social, !showOriginal {
                GeometryReader { proxy in
                    SocialMockupView(format: social, image: ImageOps.nsImage(shown.after), account: account, title: postTitle, caption: caption, showCovered: showCovered,
                                     available: CGSize(width: proxy.size.width - 48, height: proxy.size.height - 112))
                        .shadow(color: .black.opacity(0.35), radius: 14, y: 6)
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .opacity(current == nil ? 0.55 : 1)
                }
            } else if let shown = render.output {
                ZoomableView(showsControls: false) {
                    Image(nsImage: ImageOps.nsImage(showOriginal ? shown.before : shown.after))
                        .resizable()
                        .interpolation(zoom == .detail ? .none : .high)
                        .aspectRatio(contentMode: .fit)
                        .padding(zoom == .detail ? 24 : 16)
                        .opacity(current == nil ? 0.55 : 1)
                }
                if let error = shown.error {
                    Text(error).font(.callout).foregroundStyle(.white)
                        .padding(10).background(.red.opacity(0.8), in: RoundedRectangle(cornerRadius: 8))
                }
            } else {
                LoadingOrError(error: document.error)
            }
            if current == nil, render.output != nil {
                ProgressView().controlSize(.small)
            }
            VStack {
                HStack(alignment: .top) {
                    Picker("", selection: $zoom) {
                        if mode == .social { Text("On \(social.network)").tag(Zoom.feed) }
                        Text("Whole picture").tag(Zoom.whole)
                        Text("Detail at 100%").tag(Zoom.detail)
                    }
                    .pickerStyle(.segmented).labelsHidden().fixedSize()
                    Spacer()
                    if let current {
                        Text(previewLine(current))
                            .font(.caption.monospacedDigit()).foregroundStyle(.white.opacity(0.9))
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(.black.opacity(0.5), in: Capsule())
                    }
                }
                Spacer()
                Picker("", selection: $showOriginal) {
                    Text("Before").tag(true)
                    Text("After").tag(false)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
            .padding(12)
            .environment(\.colorScheme, .dark)
        }
    }

    private func previewLine(_ preview: ResizePreview) -> String {
        let original = document.size
        let before = FileSizeFormatter.string(FileSizeFormatter.size(of: session.primary))
        let after = FileSizeFormatter.string(preview.bytes)
        let dims = preview.size == original ? "\(Int(original.width)) × \(Int(original.height))" : "\(Int(original.width)) × \(Int(original.height)) → \(Int(preview.size.width)) × \(Int(preview.size.height))"
        return "\(dims) · \(before) → \(after) \(preview.format.displayName)"
    }

    /// Makes the first picture for real, into a temporary file, then shows it.
    private func refreshPreview() {
        guard let original = document.original else { return }
        requested += 1
        let request = requested
        let url = session.primary
        let sizing = sizing, method = method, zoom = zoom
        let preset = lighter.preset
        let target = lighter == .target ? Int64(targetValue * targetUnit.multiplier) : nil
        let quality = AppSettings.shared.jpegQuality
        let format = ImageResizer.outputFormat(for: url, compressing: preset != nil)
        render.submit {
            // A short pause, so typing a size doesn't render every keystroke.
            try? await Task.sleep(for: .milliseconds(200))
            let temp = FileManager.default.temporaryDirectory.appendingPathComponent("opentangerine-preview-\(UUID().uuidString).\(format.fileExtension)")
            defer { try? FileManager.default.removeItem(at: temp) }
            do {
                try await ImageResizer.process(url, sizing: sizing, method: method, preset: preset, targetBytes: target, quality: quality, to: temp, progress: { _ in })
                let result = try ImageIOBridge.load(temp)
                let bytes = FileSizeFormatter.size(of: temp)
                let size = CGSize(width: result.width, height: result.height)
                let (before, after) = Self.framing(original: original, result: result, zoom: zoom)
                return ResizePreview(request: request, before: before, after: after, size: size, bytes: bytes, format: format, error: nil)
            } catch {
                return ResizePreview(request: request, before: original, after: original, size: CGSize(width: original.width, height: original.height), bytes: 0, format: format, error: error.localizedDescription)
            }
        }
    }

    /// The whole picture fitted for the screen, or a 512-pixel detail of the result at 100%
    /// with the same part of the original beside it.
    nonisolated private static func framing(original: CGImage, result: CGImage, zoom: Zoom) -> (CGImage, CGImage) {
        switch zoom {
        case .whole, .feed:
            let after = ImageIOBridge.resized(result, longEdge: 1800)
            let before = ImageIOBridge.scaled(original, to: CGSize(width: after.width, height: after.height))
            return (before, after)
        case .detail:
            let side = min(512, result.width, result.height)
            let rect = CGRect(x: (result.width - side) / 2, y: (result.height - side) / 2, width: side, height: side)
            let after = result.cropping(to: rect) ?? result
            let sx = CGFloat(original.width) / CGFloat(result.width), sy = CGFloat(original.height) / CGFloat(result.height)
            let source = CGRect(x: rect.minX * sx, y: rect.minY * sy, width: rect.width * sx, height: rect.height * sy).integral
            let crop = original.cropping(to: source) ?? original
            // The original's pixels, blown up without smoothing, so the gain is plain to see.
            let before = nearest(crop, to: CGSize(width: after.width, height: after.height))
            return (before, after)
        }
    }

    nonisolated private static func nearest(_ image: CGImage, to size: CGSize) -> CGImage {
        guard let context = CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return image }
        context.interpolationQuality = .none
        context.draw(image, in: CGRect(origin: .zero, size: size))
        return context.makeImage() ?? image
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
