import SwiftUI

/// Social video: a video reframed for Reels, Shorts, TikTok or a feed, the crop following
/// the subject, previewed at the playhead as it will appear on the network.
@MainActor
struct SocialVideoToolView: View {
    let session: ToolSession
    @StateObject private var media: MediaController
    @StateObject private var preview = LatestRenderer<CGImage>()
    @State private var grabber: VideoFrameGrabber
    @AppStorage("socialVideo.format") private var format: SocialFormat = .instagramStory
    @AppStorage("socialVideo.fill") private var fill = true
    @AppStorage("socialVideo.hevc") private var hevc = false
    @AppStorage("socialVideo.trim") private var trim = false
    @AppStorage("socialVideo.seconds") private var seconds = 60
    @AppStorage("social.account") private var account = ""
    @AppStorage("social.title") private var postTitle = ""
    @AppStorage("social.caption") private var caption = ""
    @State private var showCovered = true
    @State private var inFeed = true
    @State private var track: SocialVideo.FocusTrack?

    init(session: ToolSession) {
        self.session = session
        _media = StateObject(wrappedValue: MediaController(url: session.primary))
        _grabber = State(initialValue: VideoFrameGrabber(url: session.primary, maxSide: 1280))
    }

    private var options: SocialVideo.Options {
        SocialVideo.Options(format: format, fill: fill, seconds: trim ? Double(max(1, seconds)) : nil, hevc: hevc)
    }

    var body: some View {
        ToolShell(session: session, saveTitle: "Save copy", saveEnabled: media.loaded && (!fill || track != nil), onSave: save) {
            VStack(spacing: 10) {
                ZStack {
                    CheckerboardBackground()
                    if let frame = preview.output {
                        GeometryReader { proxy in
                            if inFeed {
                                SocialMockupView(format: format, image: ImageOps.nsImage(frame), account: account, title: postTitle, caption: caption, showCovered: showCovered,
                                                 available: CGSize(width: proxy.size.width - 48, height: proxy.size.height - 80))
                                    .shadow(color: .black.opacity(0.35), radius: 14, y: 6)
                                    .frame(width: proxy.size.width, height: proxy.size.height)
                            } else {
                                Image(nsImage: ImageOps.nsImage(frame)).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
                                    .padding(24)
                                    .frame(width: proxy.size.width, height: proxy.size.height)
                            }
                        }
                    } else {
                        ProgressView()
                    }
                    VStack {
                        HStack {
                            Picker("", selection: $inFeed) {
                                Text("On \(format.network)").tag(true)
                                Text("Frame only").tag(false)
                            }
                            .pickerStyle(.segmented).labelsHidden().fixedSize()
                            Spacer()
                            if fill, track == nil {
                                Label("Following the subject…", systemImage: "scope")
                                    .font(.caption).foregroundStyle(.white.opacity(0.9))
                                    .padding(.horizontal, 10).padding(.vertical, 5)
                                    .background(.black.opacity(0.5), in: Capsule())
                            }
                        }
                        Spacer()
                    }
                    .padding(12)
                    .environment(\.colorScheme, .dark)
                }
                TransportBar(controller: media)
            }
            .padding(12)
        } sidebar: {
            SidebarSection(title: "Format") {
                Picker("", selection: $format) {
                    ForEach(SocialFormat.videoFormats) { Text($0.title).tag($0) }
                }
                .labelsHidden()
                Picker("", selection: $fill) {
                    Text("Crop around the subject").tag(true)
                    Text("Fit, blurred sides").tag(false)
                }
                .pickerStyle(.radioGroup).labelsHidden()
                Text(fill
                     ? "\(Int(format.size.width)) × \(Int(format.size.height)). The crop follows what draws the eye through the video, gliding from one shot to the next; found on this Mac."
                     : "\(Int(format.size.width)) × \(Int(format.size.height)). The whole frame, on a blurred copy of itself.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            SidebarSection(title: "Length") {
                Toggle("Keep only the beginning", isOn: $trim)
                if trim {
                    NumberField(title: "Seconds", value: $seconds, suffix: "s")
                    HStack {
                        ForEach([15, 30, 60, 90, 180], id: \.self) { value in
                            Button("\(value)") { seconds = value }.controlSize(.mini)
                        }
                    }
                }
                Text(media.duration > 0 ? "The video lasts \(TimeFormatter.clock(media.duration)). Each network sets its own maximum, and changes it from time to time." : "")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            SidebarSection(title: "In the preview") {
                TextField("Account name", text: $account).textFieldStyle(.roundedBorder)
                if format.layout != .feed {
                    TextField(format.layout == .video || format == .youtubeShort ? "Video title" : format == .tiktok ? "Sound" : "Name shown", text: $postTitle).textFieldStyle(.roundedBorder)
                }
                TextField(format.layout == .video ? "Description" : "Caption", text: $caption, axis: .vertical)
                    .lineLimit(2...4).textFieldStyle(.roundedBorder)
                if format.layout == .story {
                    Toggle("Show what the buttons cover", isOn: $showCovered)
                }
                Text("Only for the preview; the saved video is the picture and sound alone.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            SidebarSection(title: "Output") {
                Picker("Codec", selection: $hevc) {
                    Text("H.264").tag(false)
                    Text("HEVC").tag(true)
                }
                .pickerStyle(.segmented)
                Text("An MP4 next to the original, named “\(session.baseName) \(SocialVideo.suffix(format)).mp4”. The sound is copied as it is.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .task {
            while !media.loaded { try? await Task.sleep(for: .milliseconds(100)) }
            render()
            track = await SocialVideo.track(session.primary, duration: media.duration)
        }
        .onChange(of: media.currentTime) { render() }
        .onChange(of: options) { render() }
        .onChange(of: track) { render() }
    }

    private func render() {
        let grabber = grabber, time = media.currentTime, options = options
        let focus = track?.point(at: time) ?? CGPoint(x: 0.5, y: 0.5)
        preview.submit {
            guard let frame = await grabber.frame(at: time) else { return nil }
            return ImageToolSupport.cgImage(SocialVideo.reframe(CIImage(cgImage: frame), focus: focus, options: options))
        }
    }

    private func save() {
        let url = session.primary, options = options, track = track
        let destination = session.outputURL(suffix: SocialVideo.suffix(options.format), ext: "mp4")
        session.run(title: session.tool.progressTitle, detail: url.lastPathComponent) { progress in
            try await SocialVideo.apply(url, options: options, track: track, to: destination, progress: progress)
            return [destination]
        }
    }
}
