import AVFoundation
import SwiftUI
import UniformTypeIdentifiers

@MainActor
struct CropVideoToolView: View {
    let session: ToolSession
    @StateObject private var media: MediaController
    @State private var frame: NSImage?
    @State private var rects: [RectangleOverlay] = []
    @State private var selected: UUID?
    @State private var aspect = AspectPreset.all[0]
    @State private var outWidth = 0
    @State private var outHeight = 0
    @State private var keepSize = true

    init(session: ToolSession) {
        self.session = session
        _media = StateObject(wrappedValue: MediaController(url: session.primary))
    }

    private var cropRect: CGRect? { rects.first?.rect }
    private var videoSize: CGSize { media.info.naturalSize }
    private var aspectRatio: CGFloat? {
        guard let ratio = aspect.ratio else { return nil }
        if ratio < 0, videoSize.height > 0 { return videoSize.width / videoSize.height }
        return ratio
    }

    var body: some View {
        ToolShell(session: session, saveTitle: "Crop", saveEnabled: cropRect.map { $0.width > 8 && $0.height > 8 } ?? false, onSave: save) {
            VStack(spacing: 10) {
                ZStack {
                    Color.black
                    if let frame {
                        RectangleEditorCanvas(image: frame, imageSize: videoSize, rectangles: $rects, selected: $selected, allowMultiple: false, aspect: aspectRatio)
                    } else {
                        ProgressView()
                    }
                }
                TransportBar(controller: media)
            }
            .padding(12)
        } sidebar: {
            SidebarSection(title: "Aspect ratio") {
                Picker("", selection: $aspect) {
                    ForEach(AspectPreset.all) { Text($0.title).tag($0) }
                }
                .labelsHidden()
            }
            SidebarSection(title: "Crop area") {
                if let rect = cropRect {
                    Text("\(Int(rect.width)) × \(Int(rect.height)) at \(Int(rect.minX)), \(Int(rect.minY))").font(.callout.monospacedDigit())
                }
                Text("Video: \(Int(videoSize.width)) × \(Int(videoSize.height))").font(.caption2).foregroundStyle(.secondary)
            }
            SidebarSection(title: "Output dimensions") {
                Toggle("Same as crop area", isOn: $keepSize)
                NumberField(title: "Width", value: $outWidth, suffix: "px").disabled(keepSize)
                NumberField(title: "Height", value: $outHeight, suffix: "px").disabled(keepSize)
                Text("Audio is kept as is. Output is MP4 (H.264).").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .onChange(of: media.currentTime) { _ in loadFrame() }
        .onChange(of: media.loaded) { loaded in
            guard loaded else { return }
            loadFrame()
            let inset = CGRect(origin: .zero, size: videoSize).insetBy(dx: videoSize.width * 0.1, dy: videoSize.height * 0.1)
            let id = UUID()
            rects = [RectangleOverlay(id: id, rect: inset.integral, color: .orange, label: "")]
            selected = id
        }
        .onChange(of: rects) { new in
            if keepSize, let rect = new.first?.rect { outWidth = Int(rect.width); outHeight = Int(rect.height) }
        }
        .onChange(of: aspect) { _ in
            guard let ratio = aspectRatio, let rect = cropRect else { return }
            var new = rect
            new.size.height = rect.width / ratio
            if new.maxY > videoSize.height { new.size.height = videoSize.height - rect.minY; new.size.width = new.height * ratio }
            rects = [RectangleOverlay(id: rects[0].id, rect: new.integral, color: .orange, label: "")]
        }
    }

    private func loadFrame() {
        let url = session.primary
        let time = media.currentTime
        Task.detached {
            guard let cg = try? await VideoOps.snapshot(url, at: time) else { return }
            let ns = ImageOps.nsImage(cg)
            await MainActor.run { frame = ns }
        }
    }

    private func save() {
        guard let rect = cropRect else { return }
        let url = session.primary
        let even = CGRect(x: rect.minX.rounded(), y: rect.minY.rounded(), width: (rect.width / 2).rounded(.down) * 2, height: (rect.height / 2).rounded(.down) * 2)
        let output: CGSize? = keepSize ? nil : CGSize(width: (CGFloat(outWidth) / 2).rounded(.down) * 2, height: (CGFloat(outHeight) / 2).rounded(.down) * 2)
        let destination = session.outputURL(suffix: "cropped", ext: "mp4")
        session.run(title: "Cropping", detail: "\(url.lastPathComponent)") { progress in
            try await VideoOps.crop(url, rect: even, outputSize: output, to: destination, progress: progress)
            return [destination]
        }
    }
}

@MainActor
struct VideoSpeedToolView: View {
    let session: ToolSession
    @StateObject private var media: MediaController
    @State private var ramp = SpeedRamp(speed: 2)
    @State private var selected: SpeedRamp.Key.ID?
    @State private var preservePitch = true
    /// Playing with the speed following the keys, as the copy will.
    @State private var previewing = false

    init(session: ToolSession) {
        self.session = session
        _media = StateObject(wrappedValue: MediaController(url: session.primary))
    }

    private var current: SpeedRamp.Key { selected.flatMap { id in ramp.keys.first { $0.id == id } } ?? ramp.key(at: media.currentTime) }

    private var speedBinding: Binding<Double> {
        Binding(get: { current.speed }, set: { ramp.setSpeed($0, for: current.id) })
    }

    var body: some View {
        ToolShell(session: session, saveTitle: "Save copy", saveEnabled: media.loaded, onSave: save) {
            VStack(spacing: 10) {
                PlayerSurface(player: media.player, showsControls: false)
                    .background(Color.black)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                HStack(spacing: 12) {
                    Button { togglePreview() } label: { Image(systemName: previewing ? "pause.fill" : "play.fill").frame(width: 20) }
                        .keyboardShortcut(.space, modifiers: [])
                        .help("Play with the speeds (Space)")
                    Text("\(TimeFormatter.clock(media.currentTime)) · \(SpeedRamp.label(ramp.speed(at: media.currentTime)))")
                        .font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                    Spacer()
                    Button { selected = ramp.addKey(at: media.currentTime) } label: { Label("Add a keyframe", systemImage: "diamond") }
                        .keyboardShortcut("k", modifiers: [])
                        .help("A new speed from the playhead on (K)")
                    Button(role: .destructive) { if let id = selected { ramp.remove(id); selected = nil } } label: { Image(systemName: "trash") }
                        .disabled(selected == nil || selected == ramp.keys.first?.id)
                        .help("Remove the selected keyframe")
                }
                SpeedTimeline(ramp: $ramp, selected: $selected, duration: media.duration, playhead: media.currentTime) { media.seek($0) }
                    .frame(height: 132)
            }
            .padding(12)
        } sidebar: {
            SidebarSection(title: "Speed from \(TimeFormatter.clock(current.time))") {
                HStack(alignment: .center, spacing: 14) {
                    PitchFader(speed: speedBinding)
                        .frame(width: 54, height: 230)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(SpeedRamp.label(current.speed)).font(.system(size: 30, weight: .semibold, design: .rounded).monospacedDigit())
                        ForEach([25.0, 10, 4, 2, 1, 0.5, 0.25, 0.1], id: \.self) { value in
                            Button(SpeedRamp.label(value)) { ramp.setSpeed(value, for: current.id) }
                                .controlSize(.small)
                        }
                    }
                }
                Text("Up to 25× faster at the top, down to 0.1× at the bottom; the middle notch is normal speed. It sets the part of the video under the playhead, or the keyframe you picked.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            SidebarSection(title: "Keyframes (\(ramp.keys.count))") {
                ForEach(ramp.keys) { key in
                    HStack {
                        Image(systemName: key.id == current.id ? "diamond.fill" : "diamond").foregroundStyle(key.id == current.id ? Theme.accent : .secondary)
                        Text(TimeFormatter.clock(key.time)).font(.callout.monospacedDigit())
                        Spacer()
                        Text(SpeedRamp.label(key.speed)).font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { selected = key.id; media.seek(key.time) }
                }
                HStack {
                    Button("All at 1×") { ramp = SpeedRamp(speed: 1); selected = nil }
                    Button("Normal, fast, slow") {
                        // The classic: normal, then fast, then a slow finish.
                        let d = media.duration
                        ramp = SpeedRamp(keys: [(0, 1), (d * 0.15, 4), (d * 0.75, 0.5)])
                        selected = nil
                    }
                }
                .controlSize(.small)
                Text("A keyframe starts a new speed, held until the next one. Drag a part up or down on the timeline to change its speed, a diamond sideways to move it; K adds one at the playhead.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            SidebarSection(title: "Result") {
                Text("\(TimeFormatter.clock(media.duration)) → \(TimeFormatter.clock(ramp.outputDuration(media.duration)))").font(.callout.monospacedDigit())
                Toggle("Preserve pitch", isOn: $preservePitch).disabled(!media.info.hasAudio)
                Text(media.info.hasAudio ? "Voices keep their pitch; off, sound speeds up and slows down like tape." : "This video has no sound.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .onChange(of: media.currentTime) { followRamp() }
        .onChange(of: media.isPlaying) { if !media.isPlaying { previewing = false } }
        .onDisappear { media.pause() }
    }

    private func togglePreview() {
        if previewing {
            media.pause()
            previewing = false
            return
        }
        if media.currentTime >= media.duration - 0.05 { media.seek(0) }
        media.player.currentItem?.audioTimePitchAlgorithm = preservePitch ? .spectral : .varispeed
        previewing = true
        media.player.rate = Float(ramp.speed(at: media.currentTime))
        media.isPlaying = true
    }

    /// While previewing, the player changes speed as it crosses each keyframe.
    private func followRamp() {
        guard previewing else { return }
        let wanted = Float(ramp.speed(at: media.currentTime))
        if abs(media.player.rate - wanted) > 0.001, media.player.rate != 0 { media.player.rate = wanted }
    }

    private func save() {
        let url = session.primary, ramp = ramp, pitch = preservePitch
        let suffix = ramp.isUniform ? SpeedRamp.label(ramp.keys[0].speed).replacingOccurrences(of: "×", with: "x") : "speed ramp"
        let destination = session.outputURL(suffix: suffix, ext: "mp4")
        media.pause()
        session.run(title: "Changing speed", detail: "\(url.lastPathComponent)") { progress in
            try await VideoOps.changeSpeed(url, ramp: ramp, preservePitch: pitch, to: destination, progress: progress)
            return [destination]
        }
    }
}

/// A tall fader like a turntable's pitch control, on a log scale: 0.1× at the bottom,
/// 25× at the top, with a notch at normal speed. Drag, scroll, or use the arrow keys.
struct PitchFader: View {
    @Binding var speed: Double
    @State private var startPosition: Double?

    private let marks: [Double] = [25, 10, 4, 2, 1, 0.5, 0.25, 0.1]

    var body: some View {
        GeometryReader { proxy in
            let height = proxy.size.height
            let position = SpeedRamp.position(for: speed)
            let y = (1 - position) * height
            ZStack(alignment: .top) {
                Capsule().fill(Color.primary.opacity(0.12)).frame(width: 6)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                // The part above normal speed glows; below, it stays quiet.
                let normal = (1 - SpeedRamp.position(for: 1)) * height
                Capsule().fill(Theme.accent.opacity(0.85))
                    .frame(width: 6, height: abs(normal - y))
                    .offset(y: min(normal, y))
                    .frame(maxWidth: .infinity, alignment: .center)
                ForEach(marks, id: \.self) { mark in
                    Rectangle().fill(Color.primary.opacity(mark == 1 ? 0.6 : 0.25))
                        .frame(width: mark == 1 ? 30 : 16, height: 1)
                        .offset(y: (1 - SpeedRamp.position(for: mark)) * height)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                RoundedRectangle(cornerRadius: 4)
                    .fill(.background)
                    .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Theme.accent, lineWidth: 2))
                    .overlay(Rectangle().fill(Theme.accent).frame(height: 2))
                    .frame(width: 44, height: 18)
                    .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
                    .offset(y: y - 9)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let start = startPosition ?? position
                        if startPosition == nil { startPosition = position }
                        // Dragging moves from where the knob was, finely: the whole height spans the range.
                        let moved = start - Double(value.translation.height / height)
                        var next = SpeedRamp.speed(atPosition: moved)
                        // It catches at normal speed, as a pitch fader's notch does.
                        if abs(SpeedRamp.position(for: next) - SpeedRamp.position(for: 1)) < 0.015 { next = 1 }
                        speed = next
                    }
                    .onEnded { _ in startPosition = nil }
            )
            .onTapGesture(count: 2) { speed = 1 }
            .help("Drag up to speed up, down to slow down; double-click for normal speed")
        }
        .focusable()
        .onKeyPress(.upArrow) { speed = SpeedRamp.speed(atPosition: SpeedRamp.position(for: speed) + 0.02); return .handled }
        .onKeyPress(.downArrow) { speed = SpeedRamp.speed(atPosition: SpeedRamp.position(for: speed) - 0.02); return .handled }
    }
}

/// The video's length left to right, each part as tall as its speed (log scale, normal speed
/// marked); diamonds where speeds change. Drag a part up or down, a diamond sideways.
struct SpeedTimeline: View {
    @Binding var ramp: SpeedRamp
    @Binding var selected: SpeedRamp.Key.ID?
    let duration: Double
    let playhead: Double
    let onSeek: (Double) -> Void
    @State private var dragging: Drag?

    private enum Drag {
        case speed(SpeedRamp.Key.ID, startPosition: Double)
        case key(SpeedRamp.Key.ID)
        case scrub
    }

    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width, h = proxy.size.height - 18
            let x = { (time: Double) in duration > 0 ? CGFloat(time / duration) * w : 0 }
            let y = { (speed: Double) in (1 - CGFloat(SpeedRamp.position(for: speed))) * h }
            let segments = ramp.segments(duration: max(duration, 0.01))
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.06)).frame(width: w, height: h)
                Path { path in
                    path.move(to: CGPoint(x: 0, y: y(1))); path.addLine(to: CGPoint(x: w, y: y(1)))
                }
                .stroke(Color.primary.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                Text("1×").font(.caption2.monospacedDigit()).foregroundStyle(.secondary).offset(x: 4, y: y(1) - 14)
                ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                    let key = ramp.key(at: segment.start)
                    let isSelected = key.id == selected
                    let top = y(segment.speed)
                    Rectangle()
                        .fill((segment.speed >= 1 ? Theme.accent : Color.blue).opacity(isSelected ? 0.55 : 0.3))
                        .overlay(alignment: .top) { Rectangle().fill(segment.speed >= 1 ? Theme.accent : Color.blue).frame(height: 2) }
                        .frame(width: max(1, x(segment.end) - x(segment.start)), height: max(2, h - top))
                        .offset(x: x(segment.start), y: top)
                    Text(SpeedRamp.label(segment.speed))
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(.regularMaterial, in: Capsule())
                        .offset(x: x(segment.start) + 6, y: max(0, top - 20))
                        .opacity(x(segment.end) - x(segment.start) > 44 ? 1 : 0)
                }
                ForEach(ramp.keys) { key in
                    Image(systemName: key.id == selected ? "diamond.fill" : "diamond")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Theme.accent)
                        .background(Circle().fill(.background).frame(width: 12, height: 12))
                        .position(x: x(key.time), y: h + 9)
                }
                Rectangle().fill(Color.primary).frame(width: 1.5, height: h + 18).offset(x: x(playhead) - 0.75)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let time = duration * Double(min(max(0, value.location.x / max(w, 1)), 1))
                        if dragging == nil {
                            let start = value.startLocation
                            let startTime = duration * Double(min(max(0, start.x / max(w, 1)), 1))
                            if start.y > h - 2, let key = ramp.keys.dropFirst().min(by: { abs(x($0.time) - start.x) < abs(x($1.time) - start.x) }), abs(x(key.time) - start.x) < 10 {
                                dragging = .key(key.id)
                                selected = key.id
                            } else if start.y <= h {
                                let key = ramp.key(at: startTime)
                                dragging = .speed(key.id, startPosition: SpeedRamp.position(for: key.speed))
                                selected = key.id
                                onSeek(startTime)
                            } else {
                                dragging = .scrub
                            }
                        }
                        switch dragging {
                        case .speed(let id, let startPosition)?:
                            var next = SpeedRamp.speed(atPosition: startPosition - Double(value.translation.height / max(h, 1)))
                            if abs(SpeedRamp.position(for: next) - SpeedRamp.position(for: 1)) < 0.015 { next = 1 }
                            ramp.setSpeed(next, for: id)
                        case .key(let id)?:
                            ramp.move(id, to: time, duration: duration)
                        case .scrub?:
                            onSeek(time)
                        case nil:
                            break
                        }
                    }
                    .onEnded { _ in dragging = nil }
            )
        }
    }
}

@MainActor
struct JoinVideosToolView: View {
    let session: ToolSession
    @State private var files: [URL]
    @State private var thumbs: [URL: NSImage] = [:]
    @State private var infos: [URL: MediaInfo] = [:]

    init(session: ToolSession) {
        self.session = session
        _files = State(initialValue: session.files)
    }

    private var totalDuration: Double { files.reduce(0) { $0 + (infos[$1]?.duration ?? 0) } }

    var body: some View {
        ToolShell(session: session, saveTitle: "Join \(files.count) clips", saveEnabled: files.count >= 2, onSave: save) {
            OrderedFileList(files: $files, thumbnails: thumbs, allowedTypes: [.movie, .video, .mpeg4Movie, .quickTimeMovie], addTitle: "Add clips…")
        } sidebar: {
            SidebarSection(title: "Canvas") {
                if let first = files.first, let info = infos[first] {
                    Text("\(Int(info.naturalSize.width)) × \(Int(info.naturalSize.height)) from the first clip").font(.callout)
                }
                Text("Other clips are scaled to fit and letterboxed if their aspect ratio differs. Output is a single MP4.").font(.caption2).foregroundStyle(.secondary)
            }
            SidebarSection(title: "Summary") {
                Text("\(files.count) clips · \(TimeFormatter.clock(totalDuration))").font(.callout.monospacedDigit())
            }
        }
        .task(id: files) { await loadInfo() }
    }

    private func loadInfo() async {
        for url in files where infos[url] == nil {
            infos[url] = await MediaInfo.load(url)
            if let cg = try? await VideoOps.snapshot(url, at: 0.5) {
                thumbs[url] = ImageOps.nsImage(ImageIOBridge.resized(cg, longEdge: 200))
            }
        }
    }

    private func save() {
        let files = files
        let destination = session.outputURL(suffix: "joined", ext: "mp4")
        session.run(title: "Joining", detail: "\(files.count) videos") { progress in
            try await VideoOps.join(files, to: destination, progress: progress)
            return [destination]
        }
    }
}

