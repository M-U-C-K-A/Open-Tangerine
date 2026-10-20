import AppKit
import AVFoundation

@main struct MediaIntegrationTests {
    static var failures = 0
    static var passed = 0
    static func test(_ name: String, _ work: () async throws -> Void) async {
        do { try await work(); passed += 1; print("PASS \(name)") }
        catch { failures += 1; print("FAIL \(name): \(error)") }
    }
    static func check(_ condition: Bool, _ message: String) throws { if !condition { throw OpenTangerineError.invalidInput(message) } }
    static func inspect(_ url: URL, audio: Bool = true, video: Bool = false, duration: Double? = nil, channels: Int? = nil, width: Int? = nil) async throws {
        let result = try await Shell.run(FFmpeg.probePath!, ["-v", "error", "-show_streams", "-show_format", "-of", "json", url.path])
        let obj = try JSONSerialization.jsonObject(with: Data(result.stdout.utf8)) as! [String: Any]
        let streams = obj["streams"] as? [[String: Any]] ?? []
        let a = streams.first { $0["codec_type"] as? String == "audio" }
        let v = streams.first { $0["codec_type"] as? String == "video" }
        try check(!audio || a != nil, "Missing audio")
        try check(!video || v != nil, "Missing video")
        if let channels { try check(a?["channels"] as? Int == channels, "Incorrect channel count") }
        if let width { try check(v?["width"] as? Int == width, "Incorrect width") }
        if let duration {
            let actual = Double((obj["format"] as? [String: Any])?["duration"] as? String ?? "") ?? 0
            try check(abs(actual - duration) < 0.25, "Duration \(actual), expected \(duration)")
        }
        // Decode whole short output, not just a valid header.
        try await FFmpeg.run(["-i", url.path, "-f", "null", "-"], purpose: "Validate output")
    }
    static func frequency(_ url: URL, channel: Int, start: Double, end: Double) throws -> Double {
        let file = try AVAudioFile(forReading: url)
        let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))!
        try file.read(into: buffer)
        let samples = buffer.floatChannelData![channel]
        let rate = file.processingFormat.sampleRate
        let lo = Int(start * rate), hi = min(Int(end * rate), Int(buffer.frameLength))
        var crossings = 0
        for frame in (lo + 1)..<hi { if samples[frame - 1] <= 0 && samples[frame] > 0 { crossings += 1 } }
        return Double(crossings) * rate / Double(hi - lo)
    }
    @MainActor static func main() async throws {
        guard FFmpeg.isAvailable, FFmpeg.probePath != nil else { print("SKIP media matrix: FFmpeg/ffprobe unavailable"); return }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("OpenTangerine-media-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        func out(_ name: String) -> URL { root.appendingPathComponent(name) }
        let wav = out("tone.wav"), mp4 = out("clip.mp4"), silent = out("silent.mkv")
        try await FFmpeg.run(["-f", "lavfi", "-i", "aevalsrc=0.1*sin(2*PI*440*t)|0.3*sin(2*PI*660*t):s=48000:d=2", wav.path], purpose: "Audio fixture")
        try await FFmpeg.run(["-f", "lavfi", "-i", "testsrc2=size=160x120:rate=24:duration=2", "-i", wav.path, "-c:v", "libx264", "-c:a", "aac", "-shortest", mp4.path], purpose: "Video fixture")
        try await FFmpeg.run(["-i", mp4.path, "-an", "-c:v", "copy", silent.path], purpose: "Silent fixture")
        for format: FileFormat in [.mp3,.m4a,.wav,.aiff,.flac,.ogg,.opus,.wma] {
            await test("audio WAV -> \(format)") {
                let dest = out("audio.\(format.fileExtension)")
                try await AudioEngine().convert(ConversionRequest(source: wav, sourceFormat: .wav, target: format, destination: dest, progress: { _ in }))
                try await inspect(dest, duration: 2)
            }
        }
        for format: FileFormat in [.mp4,.mov,.mkv,.webm,.avi,.wmv,.gif,.mp3] {
            await test("video MP4 -> \(format)") {
                let dest = out("video.\(format.fileExtension)")
                try await VideoEngine().convert(ConversionRequest(source: mp4, sourceFormat: .mp4, target: format, destination: dest, progress: { _ in }))
                try await inspect(dest, audio: format != .gif, video: format != .mp3, duration: 2)
            }
        }
        await test("audio trim") { let dest = out("trim.wav"); try await AudioOps.trim(wav, start: 0.5, end: 1.5, to: dest, format: .wav, progress: {_ in}); try await inspect(dest, duration: 1) }
        await test("audio normalize") { let dest = out("normalize.wav"); try await AudioOps.normalize(wav, targetLUFS: -16, range: 7, truePeak: -1, to: dest, format: .wav, progress: {_ in}); try await inspect(dest, duration: 2); let stats = await AudioOps.measureLoudness(dest); try check(abs((stats?.integrated ?? 0) + 16) < 1, "Incorrect loudness") }
        for mode in AudioOps.ChannelMode.allCases {
            await test("channels \(mode)") { let dest = out("\(mode).wav"); try await AudioOps.convertChannels(wav, mode: mode, leftGain: 1, rightGain: 1, to: dest, format: .wav, progress: {_ in}); try await inspect(dest, duration: 2, channels: mode == .mono ? 1 : 2)
                if mode != .mono {
                    let expectedLeft = mode == .rightOnly || mode == .swap ? 660.0 : 440.0
                    let expectedRight = mode == .leftOnly || mode == .swap ? 440.0 : 660.0
                    try check(abs(try frequency(dest, channel: 0, start: 0.2, end: 1.8) - expectedLeft) < 3, "Wrong left channel content")
                    try check(abs(try frequency(dest, channel: 1, start: 0.2, end: 1.8) - expectedRight) < 3, "Wrong right channel content")
                }
            }
        }
        await test("audio bleep") { let dest = out("bleep.wav"); try await AudioOps.bleep(wav, ranges: [.init(start: 0.5, end: 1)], frequency: 1000, to: dest, format: .wav, progress: {_ in}); try await inspect(dest, duration: 2)
            try check(abs(try frequency(dest, channel: 0, start: 0.65, end: 0.9) - 1000) < 8, "Missing bleep tone")
            try check(abs(try frequency(dest, channel: 0, start: 1.2, end: 1.8) - 440) < 3, "Bleep modified audio outside range")
        }
        await test("waveform and silence") { let wave = await AudioOps.waveform(wav, buckets: 100); try check(wave.count == 100 && (wave.max() ?? 0) > 0, "Invalid waveform"); let silence = await AudioOps.detectSilence(wav); try check(silence != nil, "Missing silence scan") }
        await test("video trim") { let dest = out("trim.mp4"); try await VideoOps.trim(mp4, start: 0.5, end: 1.5, to: dest, progress: {_ in}); try await inspect(dest, video: true, duration: 1) }
        await test("silent MKV exact trim") { let dest = out("trim.mkv"); try await VideoOps.trim(silent, start: 0.5, end: 1.5, to: dest, progress: {_ in}); try await inspect(dest, audio: false, video: true, duration: 1) }
        await test("video split") { let urls = try await VideoOps.split(mp4, at: [1], duration: 2, into: out("split"), progress: {_ in}); try check(urls.count == 2, "Wrong split count"); for url in urls { try await inspect(url, video: true, duration: 1) } }
        await test("video crop") { let dest = out("crop.mp4"); try await VideoOps.crop(mp4, rect: CGRect(x: 0,y: 0,width: 80,height: 80), outputSize: nil, to: dest, progress: {_ in}); try await inspect(dest, video: true, width: 80) }
        for source in [mp4, silent] {
            await test("speed \(source.pathExtension)") { let dest = out("speed-\(source.pathExtension).mp4"); try await VideoOps.changeSpeed(source, factor: 2, preservePitch: true, to: dest, progress: {_ in}); try await inspect(dest, audio: source == mp4, video: true, duration: 1) }
        }
        await test("join silent MKV and audio MP4") { let dest = out("join.mp4"); try await VideoOps.join([silent, mp4], to: dest, progress: {_ in}); try await inspect(dest, video: true, duration: 4, width: 160) }
        await test("snapshot") { let image = try await VideoOps.snapshot(mp4, at: 0.5); try check(image.width == 160 && image.height == 120, "Invalid snapshot") }
        await test("video compression") { let dest = out("compressed.mp4"); try await VideoOps.compress(silent, preset: .balanced, targetBytes: nil, to: dest, progress: {_ in}); try await inspect(dest, audio: false, video: true, duration: 2) }
        await test("video compression to HEVC, smaller and slower") {
            let dest = out("compressed-hevc.mp4")
            try await VideoOps.compress(mp4, preset: .balanced, targetBytes: nil, video: VideoCompression(codec: .hevc, maxLongEdge: 80, maxFrameRate: 12), to: dest, progress: {_ in})
            try await inspect(dest, audio: true, video: true, duration: 2)
            let probe = try await Shell.run(FFmpeg.probePath!, ["-v", "error", "-select_streams", "v:0", "-show_entries", "stream=codec_name,codec_tag_string,width,height,r_frame_rate", "-of", "csv=p=0", dest.path])
            let fields = probe.stdout.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: ",").map(String.init)
            try check(fields.first == "hevc" && fields.contains("hvc1"), "Expected HEVC tagged hvc1, got \(fields)")
            try check(fields.contains("80") && fields.contains("12/1"), "Expected an 80 px long edge at 12 fps, got \(fields)")
        }
        await test("audio compression") { let dest = out("compressed.m4a"); try await Compressor.compressAudio(wav, format: .wav, preset: .balanced, targetBytes: nil, to: dest, progress: {_ in}); try await inspect(dest, duration: 2) }
        for style in RedactionStyle.allCases {
            await test("video redact \(style)") { let dest = out("redact-\(style).mp4"); try await VideoOps.redact(mp4, redactions: [Redaction(rect: CGRect(x: 10,y: 10,width: 30,height: 30), style: style)], displaySize: CGSize(width: 80,height: 60), to: dest, progress: {_ in}); try await inspect(dest, video: true, duration: 2, width: 160) }
        }
        for (name, source) in [("MP4", mp4), ("M4A", out("audio.m4a")), ("MP3", out("audio.mp3")), ("FLAC", out("audio.flac"))] {
            await test("\(name) tags written and read back") {
                let format = FileFormat.detect(source)!
                let tagged = out("tagged.\(format.fileExtension)"), retagged = out("retagged.\(format.fileExtension)")
                try await MetadataOps.write(source, tags: [.title: "Citrus song", .artist: "Ada", .comment: "First take"], removeAll: false, removeSensitive: false, to: tagged, progress: { _ in })
                let back = await MetadataOps.readTags(tagged)
                try check(back[.title] == "Citrus song" && back[.artist] == "Ada" && back[.comment] == "First take", "Expected the new tags, got \(back)")
                try await MetadataOps.write(tagged, tags: [.title: "Lemon song"], removeAll: false, removeSensitive: false, to: retagged, progress: { _ in })
                let again = await MetadataOps.readTags(retagged)
                try check(again[.title] == "Lemon song" && again[.artist] == "Ada", "Expected one tag changed and the others kept, got \(again)")
                try await inspect(retagged, duration: 2)
            }
        }
        await test("video enhance: denoise, sharpen, light, doubled, sound kept") {
            let dest = out("enhanced.mp4")
            try await VideoEnhance.apply(mp4, options: VideoEnhance.Options(denoise: .light, sharpen: true, autoLight: true, double: true, method: .enlarge), to: dest, progress: { _ in })
            try await inspect(dest, audio: true, video: true, duration: 2, width: 320)
        }
        await test("video enhance with super resolution") {
            let dest = out("enhanced-sr.mp4")
            try await VideoEnhance.apply(mp4, options: VideoEnhance.Options(denoise: .strong, sharpen: false, double: true, method: .enhance), to: dest, progress: { _ in })
            try await inspect(dest, audio: true, video: true, duration: 2, width: 320)
        }
        await test("video enhance through FFmpeg for MKV") {
            let dest = out("enhanced-mkv.mp4")
            try await VideoEnhance.apply(silent, options: VideoEnhance.Options(denoise: .light, sharpen: true, double: true), to: dest, progress: { _ in })
            try await inspect(dest, audio: false, video: true, duration: 2, width: 320)
        }
        func size(_ url: URL) async throws -> (Int, Int, Double) {
            let probe = try await Shell.run(FFmpeg.probePath!, ["-v", "error", "-select_streams", "v:0", "-show_entries", "stream=width,height:format=duration", "-of", "csv=p=0", url.path])
            let numbers = probe.stdout.split(whereSeparator: { $0 == "," || $0 == "\n" }).compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
            return (Int(numbers.first ?? 0), Int(numbers.dropFirst().first ?? 0), numbers.dropFirst(2).first ?? 0)
        }
        func frame(_ url: URL, at seconds: Double) async throws -> [UInt8] {
            let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
            generator.appliesPreferredTrackTransform = true
            generator.requestedTimeToleranceBefore = .zero; generator.requestedTimeToleranceAfter = .zero
            let image = try await generator.image(at: CMTime(seconds: seconds, preferredTimescale: 600)).image
            let context = CGContext(data: nil, width: 90, height: 160, bitsPerComponent: 8, bytesPerRow: 360, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.draw(image, in: CGRect(x: 0, y: 0, width: 90, height: 160))
            return Array(UnsafeBufferPointer(start: context.data!.assumingMemoryBound(to: UInt8.self), count: 90 * 160 * 4))
        }
        await test("social video: TikTok size, sound kept") {
            let dest = out("clip tiktok.mp4")
            try await SocialVideo.apply(mp4, options: SocialVideo.Options(format: .tiktok, fill: true), to: dest, progress: { _ in })
            let (w, h, d) = try await size(dest)
            try check(w == 1080 && h == 1920 && abs(d - 2) < 0.2, "Expected 1080 × 1920 for 2 s, got \(w) × \(h) for \(d) s")
            try await inspect(dest, audio: true, video: true, duration: 2, width: 1080)
        }
        await test("social video: fitted square, trimmed to one second, HEVC") {
            let dest = out("clip square.mp4")
            try await SocialVideo.apply(mp4, options: SocialVideo.Options(format: .instagramSquare, fill: false, seconds: 1, hevc: true), to: dest, progress: { _ in })
            let (w, h, d) = try await size(dest)
            try check(w == 1080 && h == 1080 && abs(d - 1) < 0.15, "Expected 1080 × 1080 for 1 s, got \(w) × \(h) for \(d) s")
        }
        await test("social video through FFmpeg for MKV") {
            let dest = out("silent youtube.mp4")
            try await SocialVideo.apply(silent, options: SocialVideo.Options(format: .youtubeVideo, fill: false, seconds: 1), to: dest, progress: { _ in })
            let (w, h, d) = try await size(dest)
            try check(w == 1920 && h == 1080 && abs(d - 1) < 0.15, "Expected 1920 × 1080 for 1 s, got \(w) × \(h) for \(d) s")
        }
        await test("social video follows a moving subject") {
            // A white square crosses a dark frame from left to right; a centred crop would miss it at both ends.
            let moving = out("moving.mp4"), dest = out("moving tiktok.mp4")
            try await FFmpeg.run(["-f", "lavfi", "-i", "color=c=0x101010:s=1280x720:d=3:r=24", "-f", "lavfi", "-i", "color=c=white:s=160x160:d=3:r=24", "-filter_complex", "[0][1]overlay=x='100+t*300':y=280", "-c:v", "libx264", "-pix_fmt", "yuv420p", moving.path], purpose: "Moving fixture")
            try await SocialVideo.apply(moving, options: SocialVideo.Options(format: .tiktok, fill: true), to: dest, progress: { _ in })
            for seconds in [0.25, 1.5, 2.75] {
                let pixels = try await frame(dest, at: seconds)
                let bright = stride(from: 0, to: pixels.count, by: 4).filter { pixels[$0] > 200 && pixels[$0 + 1] > 200 }.count
                try check(bright > 600, "The subject is in the crop at \(seconds) s (\(bright) bright pixels)")
            }
        }
        await test("social video keeps phone videos upright") {
            // Red on the left, blue on the right, then marked as rotated, as phones record.
            let halves = out("halves.mp4"), rotated = out("rotated.mp4"), dest = out("rotated square.mp4")
            try await FFmpeg.run(["-f", "lavfi", "-i", "color=c=red:s=160x120:d=1:r=24", "-f", "lavfi", "-i", "color=c=blue:s=160x120:d=1:r=24", "-filter_complex", "hstack", "-c:v", "libx264", "-pix_fmt", "yuv420p", halves.path], purpose: "Halves fixture")
            try await FFmpeg.run(["-display_rotation", "90", "-i", halves.path, "-c", "copy", rotated.path], purpose: "Rotated fixture")
            try await SocialVideo.apply(rotated, options: SocialVideo.Options(format: .instagramSquare, fill: false), to: dest, progress: { _ in })
            let source = try await frame(rotated, at: 0.5), result = try await frame(dest, at: 0.5)
            func color(_ pixels: [UInt8], row: Int) -> (Int, Int) { let i = (row * 90 + 45) * 4; return (Int(pixels[i]), Int(pixels[i + 2])) }
            // The middle of the top and bottom rows: the same colours as the upright source.
            let (srcTop, srcBottom) = (color(source, row: 20), color(source, row: 140))
            let (outTop, outBottom) = (color(result, row: 60), color(result, row: 100))
            try check(srcTop.0 > srcTop.1 ? outTop.0 > outTop.1 : outTop.1 > outTop.0, "Top colour kept: source \(srcTop), result \(outTop)")
            try check(srcBottom.0 > srcBottom.1 ? outBottom.0 > outBottom.1 : outBottom.1 > outBottom.0, "Bottom colour kept: source \(srcBottom), result \(outBottom)")
            try check((srcTop.0 > srcTop.1) != (srcBottom.0 > srcBottom.1), "The rotated fixture is upright red over blue or blue over red")
        }
        await test("speed fader and keyframes") {
            try check(abs(SpeedRamp.speed(atPosition: 0) - 0.1) < 0.0001 && abs(SpeedRamp.speed(atPosition: 1) - 25) < 0.0001 && abs(SpeedRamp.position(for: 1) - 0.4167) < 0.001, "The fader runs from 0.1× to 25×, logarithmic")
            var ramp = SpeedRamp(speed: 1)
            let fast = ramp.addKey(at: 0.5), slow = ramp.addKey(at: 1.5)
            ramp.setSpeed(4, for: fast); ramp.setSpeed(0.5, for: slow)
            try check(abs(ramp.outputDuration(2) - 1.75) < 0.0001 && ramp.speed(at: 1) == 4 && ramp.speed(at: 1.6) == 0.5 && ramp.segments(duration: 2).count == 3, "Normal, then 4×, then 0.5×: 0.5 + 0.25 + 1 seconds")
            ramp.move(slow, to: 0.2, duration: 2)
            try check(abs((ramp.keys.last?.time ?? 0) - 0.55) < 0.0001, "A keyframe can't pass the one before it")
            ramp.setSpeed(400, for: fast)
            try check(ramp.speed(at: 0.52) == 25, "Speeds stop at 25×")
        }
        for (name, source, hasSound) in [("MP4", mp4, true), ("MKV through FFmpeg", silent, false)] {
            await test("speed ramp \(name): normal, fast, slow") {
                let dest = out("ramp-\(name.prefix(3)).mp4")
                let ramp = SpeedRamp(keys: [(0, 1), (0.5, 4), (1.5, 0.5)])
                try await VideoOps.changeSpeed(source, ramp: ramp, preservePitch: true, to: dest, progress: { _ in })
                try await inspect(dest, audio: hasSound, video: true, duration: 1.75)
            }
        }
        await test("video redact with faces") { let dest = out("redact-faces.mp4"); try await VideoOps.redact(mp4, redactions: [Redaction(rect: CGRect(x: 10, y: 10, width: 30, height: 30), style: .blur)], displaySize: CGSize(width: 80, height: 60), faces: FaceBlur.Options(), to: dest, progress: {_ in}); try await inspect(dest, video: true, duration: 2, width: 160) }
        let frame = out("frame.png")
        try await FFmpeg.run(["-i", mp4.path, "-frames:v", "1", frame.path], purpose: "Visualizer fixture")
        for style in AudioOps.VisualizerStyle.allCases {
            await test("visualizer \(style)") { let dest = out("visualizer-\(style).mp4"); try await AudioOps.visualize(wav, style: style, orientation: .square, accent: "orange", background: "black", image: frame, to: dest, progress: {_ in}); try await inspect(dest, video: true, duration: 2, width: 1080) }
        }
        for format: FileFormat in [.mp3,.m4a,.aiff,.flac,.ogg,.opus,.wma] {
            await test("audio \(format) -> WAV round trip") {
                let dest = out("roundtrip-\(format).wav")
                try await AudioEngine().convert(ConversionRequest(source: out("audio.\(format.fileExtension)"), sourceFormat: format, target: .wav, destination: dest, progress: {_ in}))
                try await inspect(dest, duration: 2)
            }
        }
        for format: FileFormat in [.mov,.mkv,.webm,.avi,.wmv,.gif] {
            await test("video \(format) -> MP4 round trip") {
                let dest = out("roundtrip-\(format).mp4")
                try await VideoEngine().convert(ConversionRequest(source: out("video.\(format.fileExtension)"), sourceFormat: format, target: .mp4, destination: dest, progress: {_ in}))
                try await inspect(dest, audio: format != .gif, video: true, duration: 2)
            }
        }
        await test("transparent PNG compression format and alpha") {
            let context = CGContext(data: nil, width: 48, height: 32, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.setFillColor(CGColor(red: 1,green: 0,blue: 0,alpha: 0.5)); context.fill(CGRect(x: 0,y: 0,width: 48,height: 32))
            let source = out("alpha.png"); try ImageIOBridge.write(context.makeImage()!, to: source, format: .png)
            try check(Compressor.outputFormat(for: source) == .png, "Transparent PNG named JPEG")
            for target: Int64? in [nil, 5000] {
                let dest = out("alpha-compressed-\(target ?? 0).png")
                try await Compressor.compressImage(source, format: .png, preset: .balanced, resizeLongEdge: 0, targetBytes: target, to: dest, progress: {_ in})
                let data = try Data(contentsOf: dest)
                try check(Array(data.prefix(8)) == [137,80,78,71,13,10,26,10], "PNG extension has wrong payload")
                let decoded = try ImageIOBridge.load(dest)
                try check(decoded.alphaInfo != .none && decoded.alphaInfo != .noneSkipLast, "PNG transparency lost")
            }
        }
        print("MEDIA RESULT: \(passed) passed, \(failures) failed")
        if failures > 0 { exit(1) }
    }
}
