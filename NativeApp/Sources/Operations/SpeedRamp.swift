import AVFoundation
import Foundation

/// A video's speed over time: from each key on, it plays at that key's speed, until the next.
/// Speeds go from 0.1× to 25×, on a scale where each step multiplies, as a pitch fader does.
struct SpeedRamp: Equatable, Sendable {
    struct Key: Equatable, Identifiable, Sendable {
        var id = UUID()
        /// In the original video, in seconds.
        var time: Double
        var speed: Double
    }

    struct Segment: Equatable, Sendable {
        let start: Double
        let end: Double
        let speed: Double
        var length: Double { end - start }
    }

    static let range: ClosedRange<Double> = 0.1...25

    /// The first key always sits at the start.
    private(set) var keys: [Key]

    init(speed: Double = 1) {
        keys = [Key(time: 0, speed: Self.clamp(speed))]
    }

    init(keys: [(time: Double, speed: Double)]) {
        var made = keys.map { Key(time: max(0, $0.time), speed: Self.clamp($0.speed)) }.sorted { $0.time < $1.time }
        if made.first?.time ?? 1 > 0 { made.insert(Key(time: 0, speed: 1), at: 0) }
        self.keys = made
    }

    static func clamp(_ speed: Double) -> Double { min(range.upperBound, max(range.lowerBound, speed)) }

    /// The fader: 0 at the bottom (0.1×) to 1 at the top (25×), logarithmic, 1× a little below the middle.
    static func speed(atPosition position: Double) -> Double {
        clamp(range.lowerBound * pow(range.upperBound / range.lowerBound, min(1, max(0, position))))
    }

    static func position(for speed: Double) -> Double {
        log(clamp(speed) / range.lowerBound) / log(range.upperBound / range.lowerBound)
    }

    /// Rounded the way people say speeds: 0.25×, 1.5×, 12×.
    static func label(_ speed: Double) -> String {
        speed >= 10 ? String(format: "%.0f×", speed) : speed >= 1 ? String(format: "%g×", (speed * 10).rounded() / 10) : String(format: "%g×", (speed * 100).rounded() / 100)
    }

    var isUniform: Bool { keys.count == 1 }

    func speed(at time: Double) -> Double {
        keys.last { $0.time <= time + 0.0001 }?.speed ?? keys[0].speed
    }

    func segments(duration: Double) -> [Segment] {
        var result: [Segment] = []
        for (index, key) in keys.enumerated() where key.time < duration {
            let end = index + 1 < keys.count ? min(duration, keys[index + 1].time) : duration
            if end - key.time > 0.001 { result.append(Segment(start: key.time, end: end, speed: key.speed)) }
        }
        return result
    }

    func outputDuration(_ duration: Double) -> Double {
        segments(duration: duration).reduce(0) { $0 + $1.length / $1.speed }
    }

    /// A new key at `time`, starting at the speed already playing there.
    @discardableResult
    mutating func addKey(at time: Double) -> Key.ID {
        if let existing = keys.first(where: { abs($0.time - time) < 0.05 }) { return existing.id }
        let key = Key(time: max(0, time), speed: speed(at: time))
        keys.append(key)
        keys.sort { $0.time < $1.time }
        return key.id
    }

    mutating func setSpeed(_ speed: Double, for id: Key.ID) {
        guard let index = keys.firstIndex(where: { $0.id == id }) else { return }
        keys[index].speed = Self.clamp(speed)
    }

    /// Keys keep their order: a key can't pass its neighbours, and the first stays at the start.
    mutating func move(_ id: Key.ID, to time: Double, duration: Double) {
        guard let index = keys.firstIndex(where: { $0.id == id }), index > 0 else { return }
        let low = keys[index - 1].time + 0.05
        let high = index + 1 < keys.count ? keys[index + 1].time - 0.05 : duration - 0.05
        guard low <= high else { return }
        keys[index].time = min(high, max(low, time))
    }

    mutating func remove(_ id: Key.ID) {
        guard let index = keys.firstIndex(where: { $0.id == id }), index > 0 else { return }
        keys.remove(at: index)
    }

    /// The key whose part of the video holds `time`.
    func key(at time: Double) -> Key {
        keys.last { $0.time <= time + 0.0001 } ?? keys[0]
    }
}

extension VideoOps {
    /// Plays each part of the video at its own speed. macOS stretches each part of the picture
    /// and sound; pitch stays natural unless asked otherwise.
    static func changeSpeed(_ url: URL, ramp: SpeedRamp, preservePitch: Bool, to destination: URL, progress: @escaping (Double) -> Void) async throws {
        guard await MediaInfo.isNativelyReadable(url) else {
            try await changeSpeedWithFFmpeg(url, ramp: ramp, preservePitch: preservePitch, to: destination, progress: progress)
            return
        }
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration)
        let seconds = CMTimeGetSeconds(duration)
        let segments = ramp.segments(duration: seconds)
        guard !segments.isEmpty else { throw OpenTangerineError.invalidInput("The video is empty.") }
        let composition = AVMutableComposition()
        let fullRange = CMTimeRange(start: .zero, duration: duration)
        var tracks: [AVMutableCompositionTrack] = []
        var audioParameters: [AVMutableAudioMixInputParameters] = []
        var frameRate: Float = 30
        for source in try await asset.loadTracks(withMediaType: .video) {
            frameRate = try await source.load(.nominalFrameRate)
            guard let track = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else { continue }
            try track.insertTimeRange(fullRange, of: source, at: .zero)
            track.preferredTransform = try await source.load(.preferredTransform)
            tracks.append(track)
        }
        for source in try await asset.loadTracks(withMediaType: .audio) {
            guard let track = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else { continue }
            try track.insertTimeRange(fullRange, of: source, at: .zero)
            tracks.append(track)
            let parameters = AVMutableAudioMixInputParameters(track: track)
            parameters.audioTimePitchAlgorithm = preservePitch ? .spectral : .varispeed
            audioParameters.append(parameters)
        }
        // From the last part back, so stretching one never moves the parts before it.
        for segment in segments.reversed() where abs(segment.speed - 1) > 0.0001 {
            let range = CMTimeRange(start: CMTime(seconds: segment.start, preferredTimescale: 600), duration: CMTime(seconds: segment.length, preferredTimescale: 600))
            let scaled = CMTime(seconds: segment.length / segment.speed, preferredTimescale: 600)
            for track in tracks { track.scaleTimeRange(range, toDuration: scaled) }
        }
        let mix = AVMutableAudioMix()
        mix.inputParameters = audioParameters
        // Parts at different speeds come at different frame rates; the exporter wants one,
        // so frames are drawn again at the source's own rate.
        let video = try await AVMutableVideoComposition.videoComposition(withPropertiesOf: composition)
        video.frameDuration = CMTime(value: 1, timescale: CMTimeScale(min(60, max(24, frameRate.rounded()))))
        try await AVExporter.export(asset: composition, to: destination, format: .mp4, preset: AVAssetExportPresetHighestQuality, videoComposition: video, audioMix: audioParameters.isEmpty ? nil : mix, progress: progress)
    }

    /// Formats macOS doesn't read: each part trimmed, retimed and joined back by FFmpeg.
    static func changeSpeedWithFFmpeg(_ url: URL, ramp: SpeedRamp, preservePitch: Bool, to destination: URL, progress: @escaping (Double) -> Void) async throws {
        guard FFmpeg.isAvailable else { throw OpenTangerineError.ffmpegMissing("Changing the speed of \(url.pathExtension.uppercased()) videos") }
        let total = await FFmpeg.probeDuration(url) ?? 0
        let audio = await FFmpeg.hasAudio(url) ?? false
        let segments = ramp.segments(duration: total > 0 ? total : 86_400)
        var graph: [String] = []
        var joins = ""
        for (index, segment) in segments.enumerated() {
            let start = String(format: "%.4f", segment.start), end = String(format: "%.4f", segment.end)
            graph.append("[0:v]trim=start=\(start):end=\(end),setpts=(PTS-STARTPTS)/\(segment.speed)[v\(index)]")
            joins += "[v\(index)]"
            if audio {
                let tempo = preservePitch ? atempoChain(segment.speed) : "asetrate=48000*\(segment.speed),aresample=48000"
                graph.append("[0:a]atrim=start=\(start):end=\(end),asetpts=PTS-STARTPTS,aresample=48000,\(tempo)[a\(index)]")
                joins += "[a\(index)]"
            }
        }
        graph.append("\(joins)concat=n=\(segments.count):v=1:a=\(audio ? 1 : 0)[v]" + (audio ? "[a]" : ""))
        var args = ["-i", url.path, "-filter_complex", graph.joined(separator: ";"), "-map", "[v]"]
        if audio { args += ["-map", "[a]"] }
        args += VideoEngine.codecArguments(for: .mp4) + [destination.path]
        try await FFmpeg.run(args, purpose: "Changing speed", duration: ramp.outputDuration(total), progress: progress)
    }
}
