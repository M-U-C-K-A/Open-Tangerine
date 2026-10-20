import AVFoundation
import CoreGraphics
import Foundation

/// Renders previews one at a time, always the latest request: edits or playback faster
/// than the Mac can draw are merged, never piled up.
@MainActor
final class LatestRenderer<Output: Sendable>: ObservableObject {
    @Published private(set) var output: Output?
    private var running = false
    private var pending: (@Sendable () async -> Output?)?

    func submit(_ job: @escaping @Sendable () async -> Output?) {
        pending = job
        guard !running else { return }
        running = true
        Task {
            while let job = pending {
                pending = nil
                let result = await Task.detached(priority: .userInitiated) { await job() }.value
                if let result { output = result }
            }
            running = false
        }
    }
}

/// Video frames for previews: one generator kept open, frames at most `maxSide` pixels,
/// with a little time tolerance so scrubbing doesn't decode from the last keyframe each time.
final class VideoFrameGrabber: @unchecked Sendable {
    private let url: URL
    private let generator: AVAssetImageGenerator

    init(url: URL, maxSide: CGFloat = 1600) {
        self.url = url
        generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: maxSide, height: maxSide)
        generator.requestedTimeToleranceBefore = CMTime(value: 1, timescale: 60)
        generator.requestedTimeToleranceAfter = CMTime(value: 1, timescale: 60)
    }

    func frame(at seconds: Double) async -> CGImage? {
        if let result = try? await generator.image(at: CMTime(seconds: seconds, preferredTimescale: 600)) { return result.image }
        // Formats macOS doesn't read go through FFmpeg, one exact frame at a time.
        return try? await VideoOps.snapshot(url, at: seconds)
    }
}
