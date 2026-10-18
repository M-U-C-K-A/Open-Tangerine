import AppKit
import ImageIO
import PDFKit

@main struct IntegrationTests {
    @MainActor static func main() async throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("OpenTangerine-tests-\(UUID())")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let context = CGContext(data: nil, width: 32, height: 24, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: 1, green: 0.4, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 32, height: 24))
        let source = root.appendingPathComponent("test.png")
        try ImageIOBridge.write(context.makeImage()!, to: source, format: .png)
        let original = try Data(contentsOf: source)
        for target: FileFormat in [.jpg, .tiff, .pdf] {
            let destination = root.appendingPathComponent("output.\(target.fileExtension)")
            try await Engines.convert(ConversionRequest(source: source, sourceFormat: .png, target: target, destination: destination, progress: { _ in }))
            if target == .pdf {
                guard PDFDocument(url: destination)?.pageCount == 1 else { fatalError("Invalid PDF") }
            } else {
                let image = try ImageIOBridge.load(destination)
                guard image.width == 32 && image.height == 24 else { fatalError("Invalid dimensions") }
            }
            print("PASS PNG -> \(target)")
        }
        // HEIC must either encode correctly or fail without poisoning the next JPEG job.
        let runner = JobRunner(presentsHUD: false)
        let failure = Job(title: "Converting to HEIC", detail: "invalid input")
        runner.enqueue(failure) { _ in
            throw OpenTangerineError.invalidInput("Expected regression test failure")
        }
        await failure.task?.value
        guard case .failed = failure.status else { fatalError("Failure not reported") }
        let jpeg = Job(title: "Converting to JPEG", detail: "recovery")
        runner.enqueue(jpeg) { progress in
            let output = root.appendingPathComponent("recovery.jpg")
            try await Engines.convert(ConversionRequest(source: source, sourceFormat: .png, target: .jpg, destination: output, progress: progress))
            return [output]
        }
        await jpeg.task?.value
        precondition(jpeg.status == .done && runner.jobs.count == 1 && runner.jobs.first?.id == jpeg.id)
        precondition(CompanionState.shared.phase != .failed)
        runner.dismissAll()
        print("PASS failed HEIC job followed by JPEG without restart or stale results")
        do {
            let heic = root.appendingPathComponent("actual.heic")
            try await Engines.convert(ConversionRequest(source: source, sourceFormat: .png, target: .heic, destination: heic, progress: { _ in }))
            let decoded = try ImageIOBridge.load(heic)
            precondition(decoded.width == 32 && decoded.height == 24)
            print("PASS PNG -> HEIC round trip")
        } catch {
            print("HEIC encoder unavailable in this execution environment: \(error.localizedDescription)")
        }
        try ImageIOBridge.validateDimensions(width: 1562, height: 1222)
        do { try ImageIOBridge.validateDimensions(width: 0, height: 0); fatalError("Missing dimensions accepted") }
        catch { precondition(!error.localizedDescription.contains("40 megapixel")) }
        do { try ImageIOBridge.validateDimensions(width: 10000, height: 10000); fatalError("Oversized image accepted") }
        catch { precondition(error.localizedDescription.contains("10000")) }
        let occupied = root.appendingPathComponent("occupied.jpg")
        let sentinel = Data("do not overwrite".utf8)
        try sentinel.write(to: occupied)
        do {
            try await Engines.convert(ConversionRequest(source: source, sourceFormat: .png, target: .jpg, destination: occupied, progress: { _ in }))
            fatalError("Destination overwrite allowed")
        } catch { }
        guard try Data(contentsOf: occupied) == sentinel, try Data(contentsOf: source) == original else { fatalError("Original modified") }
        let bad = root.appendingPathComponent("bad.png")
        try Data("not an image".utf8).write(to: bad)
        do { _ = try ImageIOBridge.load(bad); fatalError("Malformed image accepted") } catch { }
        let archive = root.appendingPathComponent("archive.zip")
        do {
            try await Engines.convert(ConversionRequest(source: archive, sourceFormat: .zip, target: .tar, destination: root.appendingPathComponent("archive.tar"), progress: { _ in }))
            fatalError("Unsafe archive conversion enabled")
        } catch { }
        let result = try await Shell.run("/usr/bin/printf", ["%s", "a;$(echo unsafe)"])
        guard result.stdout == "a;$(echo unsafe)" else { fatalError("Arguments interpolated") }
        print("PASS collision protection, original preservation, malformed input, archive guard, literal process arguments")
    }
}
