import AppKit
import ImageIO

@main struct BatchTests {
    @MainActor static func main() async throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("OpenTangerine-batch-\(UUID())")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let settings = AppSettings.shared
        let previousOutput = settings.outputLocation
        let previousReveal = settings.revealInFinder
        settings.outputLocation = .besideOriginal
        settings.revealInFinder = false
        defer { settings.outputLocation = previousOutput; settings.revealInFinder = previousReveal }
        let context = CGContext(data: nil, width: 32, height: 24, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: 1, green: 0.4, blue: 0.1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 32, height: 24))
        let image = context.makeImage()!
        var files: [URL] = []
        for index in 1...4 {
            let url = root.appendingPathComponent("image-\(index).png")
            try ImageIOBridge.write(image, to: url, format: .png)
            files.append(url)
        }
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        pasteboard.writeObjects(files as [NSURL])
        let dragged = DragMonitor.fileURLs(on: pasteboard)
        if pasteboard.pasteboardItems?.isEmpty != false {
            print("SKIP drag pasteboard service unavailable in this execution environment")
        } else {
            precondition(dragged == files, "Full drag selection must survive")
            print("PASS drag pasteboard preserves all four files")
        }
        let runner = JobRunner(presentsHUD: false)
        runner.convert(files, to: .jpg)
        let first = runner.jobs
        precondition(first.count == 4)
        // A second batch started before the first writes must reserve different names.
        runner.convert([files[0]], to: .jpg)
        let queued = runner.jobs
        for job in queued { await job.task?.value }
        precondition(queued.allSatisfy { $0.status == .done })
        let outputs = queued.flatMap(\.outputs)
        precondition(Set(outputs).count == 5)
        for output in outputs {
            let decoded = try ImageIOBridge.load(output)
            precondition(decoded.width == 32 && decoded.height == 24)
        }
        print("PASS four PNG batch -> four JPEG outputs; overlapping batches reserve unique names")
        let tiff = root.appendingPathComponent("mixed.tiff")
        try ImageIOBridge.write(image, to: tiff, format: .tiff)
        precondition(ConversionMatrix.targets(for: [.png, .tiff]).contains(.jpg))
        precondition(ConversionMatrix.targets(for: [.png, .mp3]).isEmpty)
        let corrupt = root.appendingPathComponent("corrupt.png")
        let unknown = root.appendingPathComponent("unknown.xyz")
        try Data("invalid".utf8).write(to: corrupt)
        try Data("unknown".utf8).write(to: unknown)
        runner.convert([files[0], corrupt, unknown, tiff], to: .jpg)
        let mixed = runner.jobs
        precondition(mixed.count == 4, "No unknown file may disappear silently")
        for job in mixed { await job.task?.value }
        precondition(mixed[0].status == .done && mixed[3].status == .done)
        guard case .failed = mixed[1].status, case .failed = mixed[2].status else { fatalError("Per-file errors missing") }
        precondition(mixed[0].outputs.count == 1 && mixed[3].outputs.count == 1)
        runner.dismissAll()
        print("PASS mixed formats share targets; corrupt/unknown files fail individually without blocking later files")
    }
}
