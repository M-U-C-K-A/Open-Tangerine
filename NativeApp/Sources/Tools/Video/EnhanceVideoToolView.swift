import SwiftUI

/// Enhance video: less noise, crisper detail, corrected light, or twice the resolution, with
/// a before and after of the frame at the playhead.
@MainActor
struct EnhanceVideoToolView: View {
    let session: ToolSession
    @StateObject private var media: MediaController
    @StateObject private var preview = LatestRenderer<FramePair>()
    @State private var grabber: VideoFrameGrabber
    @State private var options = VideoEnhance.Options()
    @State private var look: VideoEnhance.Look?
    @State private var showOriginal = false
    @State private var detail = false

    struct FramePair: Sendable {
        let before: CGImage
        let after: CGImage
    }

    init(session: ToolSession) {
        self.session = session
        _media = StateObject(wrappedValue: MediaController(url: session.primary))
        _grabber = State(initialValue: VideoFrameGrabber(url: session.primary, maxSide: 1920))
    }

    private var size: CGSize { media.info.naturalSize }

    var body: some View {
        ToolShell(session: session, saveTitle: "Enhance", saveEnabled: options.changesSomething, onSave: save) {
            VStack(spacing: 10) {
                ZStack {
                    Color.black
                    if let pair = preview.output {
                        Image(nsImage: ImageOps.nsImage(showOriginal ? pair.before : pair.after))
                            .resizable()
                            .interpolation(detail ? .none : .high)
                            .aspectRatio(contentMode: .fit)
                    } else {
                        ProgressView()
                    }
                    VStack {
                        HStack {
                            Picker("", selection: $detail) {
                                Text("Whole frame").tag(false)
                                Text("Detail at 100%").tag(true)
                            }
                            .pickerStyle(.segmented).labelsHidden().fixedSize()
                            Spacer()
                        }
                        Spacer()
                        Picker("", selection: $showOriginal) {
                            Text("Before").tag(true)
                            Text("After").tag(false)
                        }
                        .pickerStyle(.segmented).labelsHidden().fixedSize()
                    }
                    .padding(12)
                    .environment(\.colorScheme, .dark)
                }
                TransportBar(controller: media)
            }
            .padding(12)
        } sidebar: {
            SidebarSection(title: "Clean up") {
                Picker("Noise", selection: $options.denoise) {
                    ForEach(VideoEnhance.Options.Denoise.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                Toggle("Sharpen details", isOn: $options.sharpen)
                Toggle("Fix light and color", isOn: $options.autoLight)
                Text("Noise reduction smooths the grain of dim scenes; light and color are worked out once from the middle of the video, so every shot gets the same correction.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            SidebarSection(title: "Resolution") {
                Toggle(size.width > 0 ? "Double it: \(Int(size.width)) × \(Int(size.height)) → \(Int(size.width) * 2) × \(Int(size.height) * 2)" : "Double the resolution", isOn: $options.double)
                if options.double {
                    Picker("", selection: $options.method) {
                        ForEach(Upscale.Method.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented).labelsHidden()
                    Text(options.method == .enhance
                         ? "Machine-learning super resolution rebuilds detail in every frame, on this Mac. It takes a while: count a few minutes per minute of video."
                         : "Smooth resampling: bigger and sharp, without inventing detail. Much quicker.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            SidebarSection(title: "Output") {
                Text("An MP4 (HEVC) next to the original, named “\(session.baseName) enhanced.mp4”. The sound is copied as it is.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .task {
            // Light and color are measured once, on a frame from the middle.
            while !media.loaded { try? await Task.sleep(for: .milliseconds(100)) }
            if let middle = await grabber.frame(at: media.duration / 2) { look = VideoEnhance.Look.from(CIImage(cgImage: middle)) }
            render()
        }
        .onChange(of: media.currentTime) { render() }
        .onChange(of: options) { render() }
        .onChange(of: detail) { render() }
    }

    private func render() {
        let grabber = grabber, time = media.currentTime, options = options, detail = detail
        let look = options.autoLight ? look : nil
        preview.submit {
            guard var frame = await grabber.frame(at: time) else { return nil }
            if detail {
                // A 400-pixel square from the middle, so grain and sharpness can be judged.
                let side = min(400, frame.width, frame.height)
                frame = frame.cropping(to: CGRect(x: (frame.width - side) / 2, y: (frame.height - side) / 2, width: side, height: side)) ?? frame
            }
            let resolver = options.double && options.method == .enhance ? try? SuperResolver(width: frame.width, height: frame.height) : nil
            guard let processed = try? await VideoEnhance.process(CIImage(cgImage: frame), options: options, look: look, resolver: resolver),
                  let after = ImageToolSupport.cgImage(processed) else { return nil }
            return FramePair(before: frame, after: after)
        }
    }

    private func save() {
        let url = session.primary, options = options
        let destination = session.outputURL(suffix: "enhanced", ext: "mp4")
        session.run(title: session.tool.progressTitle, detail: url.lastPathComponent) { progress in
            try await VideoEnhance.apply(url, options: options, to: destination, progress: progress)
            return [destination]
        }
    }
}
