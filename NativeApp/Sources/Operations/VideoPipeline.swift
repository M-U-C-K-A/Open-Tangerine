import AVFoundation
import CoreImage
import Foundation

/// Reads a video frame by frame, hands each frame to `process`, and writes the results as an
/// MP4 next to an untouched copy of the sound. The tools that rework every picture of a video
/// (enhancing, reframing) share it.
enum VideoPipeline {
    struct Source: Sendable {
        /// The frame size as stored, before rotation.
        let natural: CGSize
        let transform: CGAffineTransform
        let frameRate: Float
        let dataRate: Float
        let duration: Double

        /// The frame size as people see it, after rotation.
        var upright: CGSize {
            let rect = CGRect(origin: .zero, size: natural).applying(transform)
            return CGSize(width: abs(rect.width).rounded(), height: abs(rect.height).rounded())
        }

        /// How the stored frame must be turned to stand upright.
        var orientation: CGImagePropertyOrientation {
            let t = transform
            switch (t.a.rounded(), t.b.rounded(), t.c.rounded(), t.d.rounded()) {
            case (0, 1, -1, 0): return .right
            case (0, -1, 1, 0): return .left
            case (-1, 0, 0, -1): return .down
            case (-1, 0, 0, 1): return .upMirrored
            case (1, 0, 0, -1): return .downMirrored
            default: return .up
            }
        }
    }

    static func source(_ url: URL) async throws -> (AVURLAsset, AVAssetTrack, Source) {
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else { throw OpenTangerineError.invalidInput("No video track found.") }
        let source = Source(
            natural: try await track.load(.naturalSize),
            transform: try await track.load(.preferredTransform),
            frameRate: try await track.load(.nominalFrameRate),
            dataRate: try await track.load(.estimatedDataRate),
            duration: CMTimeGetSeconds(try await asset.load(.duration))
        )
        return (asset, track, source)
    }

    /// - Parameters:
    ///   - upright: frames come turned upright and are written without rotation (reframing);
    ///     otherwise they come as stored, and the rotation is kept on the output track.
    ///   - size: the output frame size, from the size of the frames handed over.
    ///   - bitrate: bits per second for the output.
    ///   - seconds: keep only the start of the video, this long.
    static func run(_ url: URL, upright: Bool, codec: AVVideoCodecType = .hevc, seconds: Double? = nil, size: (Source, CGSize) -> CGSize, bitrate: (Source, CGSize) -> Double,
                    to destination: URL, progress: @escaping (Double) -> Void, process: (CIImage, CMTime) async throws -> CIImage) async throws {
        guard await MediaInfo.isNativelyReadable(url) else {
            throw OpenTangerineError.invalidInput("\(url.lastPathComponent) needs converting to MP4 first.")
        }
        let (asset, videoTrack, source) = try await source(url)
        let audioTrack = try await asset.loadTracks(withMediaType: .audio).first
        let frameSize = upright ? source.upright : source.natural
        let output = size(source, frameSize)
        let outWidth = max(2, Int(output.width) / 2 * 2), outHeight = max(2, Int(output.height) / 2 * 2)
        let total = min(source.duration, seconds ?? .infinity)

        let reader = try AVAssetReader(asset: asset)
        if let seconds { reader.timeRange = CMTimeRange(start: .zero, duration: CMTime(seconds: seconds, preferredTimescale: 600)) }
        let videoOutput = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
        videoOutput.alwaysCopiesSampleData = false
        reader.add(videoOutput)
        var audioOutput: AVAssetReaderTrackOutput?
        if let audioTrack {
            let output = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: nil)
            if reader.canAdd(output) { reader.add(output); audioOutput = output }
        }

        try? FileManager.default.removeItem(at: destination)
        let writer = try AVAssetWriter(outputURL: destination, fileType: .mp4)
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: codec,
            AVVideoWidthKey: outWidth,
            AVVideoHeightKey: outHeight,
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: Int(bitrate(source, CGSize(width: outWidth, height: outHeight)))],
        ])
        videoInput.expectsMediaDataInRealTime = false
        if !upright { videoInput.transform = source.transform }
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: videoInput, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: outWidth,
            kCVPixelBufferHeightKey as String: outHeight,
        ])
        writer.add(videoInput)
        var audioInput: AVAssetWriterInput?
        if let audioTrack, audioOutput != nil {
            let hint = try await audioTrack.load(.formatDescriptions).first
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: nil, sourceFormatHint: hint)
            input.expectsMediaDataInRealTime = false
            if writer.canAdd(input) { writer.add(input); audioInput = input }
        }

        guard reader.startReading() else { throw OpenTangerineError.encodeFailed(reader.error?.localizedDescription ?? "reading the video") }
        guard writer.startWriting() else { throw OpenTangerineError.encodeFailed(writer.error?.localizedDescription ?? "writing the video") }
        writer.startSession(atSourceTime: .zero)
        let context = CIContext(options: [.cacheIntermediates: false])
        let orientation = source.orientation

        // Sound goes across while the pictures are worked on, as the writer wants them interleaved.
        let audioTask = Task.detached {
            guard let audioInput, let audioOutput else { return }
            while true {
                while !audioInput.isReadyForMoreMediaData {
                    if Task.isCancelled { return }
                    try? await Task.sleep(nanoseconds: 5_000_000)
                }
                guard let sample = audioOutput.copyNextSampleBuffer() else { break }
                audioInput.append(sample)
            }
            audioInput.markAsFinished()
        }

        do {
            while let sample = videoOutput.copyNextSampleBuffer() {
                try Task.checkCancellation()
                guard let pixels = CMSampleBufferGetImageBuffer(sample) else { continue }
                let time = CMSampleBufferGetPresentationTimeStamp(sample)
                var frame = CIImage(cvPixelBuffer: pixels)
                if upright, orientation != .up {
                    frame = frame.oriented(orientation)
                    frame = frame.transformed(by: CGAffineTransform(translationX: -frame.extent.minX, y: -frame.extent.minY))
                }
                let result = try await process(frame, time)
                while !videoInput.isReadyForMoreMediaData {
                    try Task.checkCancellation()
                    try await Task.sleep(nanoseconds: 5_000_000)
                }
                guard let pool = adaptor.pixelBufferPool else { throw OpenTangerineError.encodeFailed("a video frame") }
                var buffer: CVPixelBuffer?
                CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
                guard let buffer else { throw OpenTangerineError.encodeFailed("a video frame") }
                context.render(result, to: buffer, bounds: CGRect(x: 0, y: 0, width: outWidth, height: outHeight), colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
                guard adaptor.append(buffer, withPresentationTime: time) else { throw OpenTangerineError.encodeFailed(writer.error?.localizedDescription ?? "a video frame") }
                if total > 0 { progress(min(0.99, CMTimeGetSeconds(time) / total)) }
            }
            videoInput.markAsFinished()
            await audioTask.value
            guard reader.status != .failed else { throw OpenTangerineError.encodeFailed(reader.error?.localizedDescription ?? "reading the video") }
            await writer.finishWriting()
            guard writer.status == .completed else { throw OpenTangerineError.encodeFailed(writer.error?.localizedDescription ?? "writing the video") }
            progress(1)
        } catch {
            audioTask.cancel()
            reader.cancelReading()
            writer.cancelWriting()
            try? FileManager.default.removeItem(at: destination)
            throw error is CancellationError ? OpenTangerineError.cancelled : error
        }
    }
}
