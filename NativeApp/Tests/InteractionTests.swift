import AVFoundation
import Foundation
final class UpdateResponse: URLProtocol {
    static var body = ""
    static var status = 200
    static var requests = 0
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.requests += 1
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: Self.status, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(Self.body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
@main struct InteractionTests {
    @MainActor static func main() async throws {
        precondition(AppVersion("0.1.10")! > AppVersion("0.1.9")!)
        precondition(AppVersion("v1.0.0")! == AppVersion("1.0.0")!)
        precondition(AppVersion("1.2.3-beta") == nil)
        precondition(AppVersion("1.2") == nil)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [UpdateResponse.self]
        let suite = "OpenTangerine-update-tests-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        var openedPage: URL?
        let checker = UpdateChecker(session: URLSession(configuration: config), defaults: defaults, currentVersion: "0.1.2", openPage: { openedPage = $0 })
        precondition(checker.downloadPage.absoluteString == "https://github.com/M-U-C-K-A/Open-Tangerine/releases", "updates point at this fork, not upstream")
        await checker.check(interactive: true)
        precondition(openedPage == checker.downloadPage)
        precondition(UpdateResponse.requests == 0, "Manual update must open the website without waiting for GitHub")
        UpdateResponse.body = #"{"tag_name":"v0.1.3","draft":false,"prerelease":false}"#
        await checker.check(interactive: false)
        precondition(checker.availableVersion == "v0.1.3")
        defaults.removeObject(forKey: "lastUpdateCheck")
        UpdateResponse.body = #"{"tag_name":"v0.1.2","draft":false,"prerelease":false}"#
        await checker.check(interactive: false)
        precondition(checker.availableVersion == nil)
        defaults.removeObject(forKey: "lastUpdateCheck")
        UpdateResponse.status = 404
        await checker.check(interactive: false)
        precondition(defaults.object(forKey: "lastUpdateCheck") == nil)
        print("PASS HTTP update detection, current version, unpublished release")
        let state = CompanionState.shared
        state.set(.watching)
        state.watch(label: "PNG", direction: 3)
        precondition(state.gaze == 1 && state.caption.contains("PNG"))
        let interrupted = state.transition(from: .received, to: .processing, after: 0.01)
        state.set(.failed)
        await interrupted.value
        precondition(state.phase == .failed, "Late animation must not overwrite error")
        let completed = state.transition(from: .delivering, to: .success, after: 0.01)
        await completed.value
        precondition(state.phase == .success)
        print("PASS version ordering, invalid version rejection, gaze bounds, interrupted and completion transitions")

        // Wheels: modifiers pick one, steps wrap round.
        precondition(RadialMode.forModifiers(command: false, option: false, control: false) == .convert)
        precondition(RadialMode.forModifiers(command: true, option: false, control: false) == .tools)
        precondition(RadialMode.forModifiers(command: false, option: true, control: false) == .tools)
        precondition(RadialMode.forModifiers(command: true, option: true, control: true) == .actions)
        precondition(RadialMode.convert.stepped(1) == .tools && RadialMode.tools.stepped(1) == .actions && RadialMode.actions.stepped(1) == .convert)
        precondition(RadialMode.convert.stepped(-1) == .actions && RadialMode.convert.stepped(-4) == .actions)

        // Scroll: a wheel notch is one step with a pause, a swipe needs distance, momentum never counts.
        var scroll = ScrollStepper()
        precondition(scroll.step(delta: -1, precise: false, momentum: false, ended: false, at: 10) == 1, "scroll down goes to the next wheel")
        precondition(scroll.step(delta: -1, precise: false, momentum: false, ended: false, at: 10.05) == 0, "a fast spin does not race through every wheel")
        precondition(scroll.step(delta: 3, precise: false, momentum: false, ended: false, at: 10.4) == -1, "scroll up goes back")
        precondition(scroll.step(delta: -12, precise: true, momentum: false, ended: false, at: 11) == 0)
        precondition(scroll.step(delta: -12, precise: true, momentum: false, ended: false, at: 11.01) == 0)
        precondition(scroll.step(delta: -12, precise: true, momentum: false, ended: false, at: 11.02) == 1, "a long enough swipe is one step")
        precondition(scroll.step(delta: -80, precise: true, momentum: true, ended: false, at: 11.1) == 0, "momentum is ignored")
        precondition(scroll.step(delta: -20, precise: true, momentum: false, ended: true, at: 12) == 0)
        precondition(scroll.step(delta: -20, precise: true, momentum: false, ended: false, at: 12.5) == 0, "a new swipe starts from zero")
        precondition(scroll.step(delta: 25, precise: true, momentum: false, ended: false, at: 12.6) == 0, "turning back starts from zero")
        print("PASS wheel modes from modifiers, wrapping steps, mouse-wheel notches, trackpad swipes and momentum")

        // Shift alone: fires after a hold over Finder, never while typing, picks on release.
        func run(_ recognizer: inout ShiftHoldRecognizer, _ samples: [(TimeInterval, Bool, Bool, Bool, Bool, TimeInterval)]) -> [ShiftHoldRecognizer.Event] {
            samples.map { recognizer.update(now: $0.0, shift: $0.1, otherModifiers: $0.2, mouseDown: $0.3, finderFront: $0.4, secondsSinceKeyDown: $0.5) }
        }
        var hold = ShiftHoldRecognizer()
        precondition(run(&hold, [(0, true, false, false, true, 5), (0.2, true, false, false, true, 5.2), (0.41, true, false, false, true, 5.41), (0.6, true, false, false, true, 5.6), (0.7, false, false, false, false, 5.7)]) == [.none, .none, .fire, .none, .release])
        hold = ShiftHoldRecognizer()
        precondition(!run(&hold, [(0, true, false, false, true, 5), (0.1, true, false, false, true, 0.0), (0.5, true, false, false, true, 0.4), (0.9, true, false, false, true, 0.8)]).contains(.fire), "a capital letter typed while Shift is held is not the gesture")
        hold = ShiftHoldRecognizer()
        precondition(!run(&hold, [(0, true, true, false, true, 5), (0.5, true, true, false, true, 5.5)]).contains(.fire), "Shift with Command is a shortcut, not the gesture")
        hold = ShiftHoldRecognizer()
        precondition(!run(&hold, [(0, true, false, true, true, 5), (0.5, true, false, true, true, 5.5)]).contains(.fire), "a drag has its own path")
        hold = ShiftHoldRecognizer()
        precondition(run(&hold, [(0, true, false, false, false, 5), (0.5, true, false, false, false, 5.5), (0.6, true, false, false, true, 5.6)]) == [.none, .none, .fire], "only over Finder")
        hold = ShiftHoldRecognizer()
        precondition(run(&hold, [(0, true, false, false, true, 5), (0.2, false, false, false, true, 5.2), (0.3, true, false, false, true, 5.3), (0.5, true, false, false, true, 5.5), (0.71, true, false, false, true, 5.71)]) == [.none, .none, .none, .none, .fire], "letting go restarts the hold")
        print("PASS Shift-alone hold: timing, typing, other modifiers, drags, Finder in front, release")

        precondition(FinderSelection.parse("/Users/me/photo.heic\n/Users/me/Folder/\n/Users/me/clip copy.mov\n\nnot a path\n") == [URL(fileURLWithPath: "/Users/me/photo.heic"), URL(fileURLWithPath: "/Users/me/Folder", isDirectory: true), URL(fileURLWithPath: "/Users/me/clip copy.mov")])
        precondition(FinderSelection.parse("").isEmpty)
        print("PASS Finder selection parsing keeps files and folders")

        // File actions follow the selection: folders zip but have no checksum, text comes from images and PDFs.
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("ot-actions-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }
        let image = scratch.appendingPathComponent("scan.png"), pdf = scratch.appendingPathComponent("doc.pdf"), note = scratch.appendingPathComponent("note.key")
        for url in [image, pdf, note] { try Data("x".utf8).write(to: url) }
        let folder = scratch.appendingPathComponent("Album", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        precondition(FileAction.available(for: [image, pdf]).contains(.copyText) && FileAction.available(for: [image, pdf]).contains(.hash))
        precondition(!FileAction.available(for: [image, note]).contains(.copyText), "unknown files have no text to read")
        precondition(FileAction.available(for: [folder]).contains(.zip) && !FileAction.available(for: [folder]).contains(.hash), "folders zip but have no checksum")
        precondition(FileAction.available(for: [note]).contains(.rename))
        precondition(!ToolID.available(for: [.png]).contains(.renameFiles), "renaming lives on the File actions wheel")
        print("PASS file actions for folders, unknown files, images and PDFs")

        // Batch rename: pattern, counter, find and replace, case, conflicts, swaps and rollback.
        let names = ["IMG_001.JPG", "IMG_002.JPG", "notes.txt"].map { scratch.appendingPathComponent($0) }
        for url in names { try Data(url.lastPathComponent.utf8).write(to: url) }
        let day = Date(timeIntervalSince1970: 1_790_000_000)
        var plan = BatchRename.plan(names, options: BatchRename.Options(pattern: "Trip {n} {name}", find: "IMG_", replace: "", start: 7, digits: 3, textCase: .lower), date: { _ in day })
        precondition(plan.map(\.name) == ["trip 007 001.JPG", "trip 008 002.JPG", "trip 009 notes.txt"], "\(plan.map(\.name))")
        precondition(BatchRename.problems(plan).isEmpty)
        plan = BatchRename.plan(names, options: BatchRename.Options(pattern: "{date}"), date: { _ in day })
        precondition(plan[0].name == "\(BatchRename.dayFormat.string(from: day)).JPG" && BatchRename.problems(plan)[0] == .duplicate && BatchRename.problems(plan)[1] == .duplicate, "same date twice clashes")
        precondition(BatchRename.problems(BatchRename.plan([names[0]], options: BatchRename.Options(pattern: "notes"))) == [:], "a different extension does not clash")
        precondition(BatchRename.problems([BatchRename.Item(source: names[0], name: "IMG_002.JPG"), BatchRename.Item(source: names[1], name: "IMG_001.JPG")], exists: { _ in true }) == [:], "taking a name another file in the batch gives up is not a clash")
        precondition(BatchRename.problems([BatchRename.Item(source: names[2], name: "IMG_001.JPG")], exists: { _ in true }) == [0: .exists], "taking the name of a file that stays is a clash")
        precondition(BatchRename.problems([BatchRename.Item(source: names[2], name: "a/b.txt")])[0] == .invalidCharacter)
        precondition(BatchRename.problems([BatchRename.Item(source: names[2], name: ".hidden.txt")])[0] == .hidden)
        precondition(BatchRename.problems([BatchRename.Item(source: names[2], name: "")])[0] == .empty)
        // A swap and a case-only change both go through.
        let swapped = try BatchRename.apply([BatchRename.Item(source: names[0], name: "IMG_002.JPG"), BatchRename.Item(source: names[1], name: "IMG_001.JPG"), BatchRename.Item(source: names[2], name: "Notes.txt")])
        let first = try String(contentsOf: swapped[0], encoding: .utf8), second = try String(contentsOf: swapped[1], encoding: .utf8)
        precondition(first == "IMG_001.JPG" && second == "IMG_002.JPG", "the two files traded names")
        let listing = try FileManager.default.contentsOfDirectory(atPath: scratch.path)
        precondition(listing.contains("Notes.txt") && !listing.contains("notes.txt"), "case-only rename")
        // A failure halfway puts everything back.
        let blocker = scratch.appendingPathComponent("locked", isDirectory: true)
        try FileManager.default.createDirectory(at: blocker, withIntermediateDirectories: true)
        let inside = blocker.appendingPathComponent("a.txt")
        try Data("a".utf8).write(to: inside)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: blocker.path)
        do {
            _ = try BatchRename.apply([BatchRename.Item(source: swapped[0], name: "first.JPG"), BatchRename.Item(source: inside, name: "b.txt")])
            preconditionFailure("renaming in a locked folder must fail")
        } catch {
            precondition(FileManager.default.fileExists(atPath: swapped[0].path) && !FileManager.default.fileExists(atPath: scratch.appendingPathComponent("first.JPG").path), "rollback restores the first rename")
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: blocker.path)
        print("PASS batch rename: pattern, counter, case, clashes, swaps, case-only changes and rollback")

        // Compression 2.0: shrink to the long edge, never enlarge, cap the frame rate.
        let wide = VideoCompression(codec: .hevc, maxLongEdge: 1280, maxFrameRate: 30)
        precondition(wide.filters(size: CGSize(width: 3840, height: 2160), frameRate: 59.94, presetScale: 1) == ["scale=1280:-2", "fps=30"])
        precondition(wide.filters(size: CGSize(width: 1080, height: 1920), frameRate: 30, presetScale: 1) == ["scale=-2:1280"], "portrait keeps its orientation; 30 fps is left alone")
        precondition(wide.filters(size: CGSize(width: 640, height: 360), frameRate: 24, presetScale: 1).isEmpty, "small videos are never enlarged")
        precondition(VideoCompression().filters(size: CGSize(width: 1920, height: 1080), frameRate: 30, presetScale: 0.75) == ["scale=1440:-2"], "the Strong preset still shrinks")
        precondition(VideoOps.nativePreset(longEdge: 3840, strong: false, hevc: true) == AVAssetExportPresetHEVC3840x2160 && VideoOps.nativePreset(longEdge: 1600, strong: false, hevc: true) == AVAssetExportPresetHEVC1920x1080)
        print("PASS video compression options: long edge, orientation, no upscaling, frame rate, native presets")

        // Watch folders: what gets converted, and what is ignored.
        precondition(FolderWatcher.shouldConvert(URL(fileURLWithPath: "/w/a.heic"), to: .jpg) && !FolderWatcher.shouldConvert(URL(fileURLWithPath: "/w/a.jpg"), to: .jpg) && !FolderWatcher.shouldConvert(URL(fileURLWithPath: "/w/a.wav"), to: .jpg))
        try Data("x".utf8).write(to: scratch.appendingPathComponent("movie.mp4.download"))
        try Data("x".utf8).write(to: scratch.appendingPathComponent(".hidden.png"))
        let seen = FolderWatcher.names(in: scratch)
        precondition(!seen.contains("movie.mp4.download") && !seen.contains(".hidden.png") && !seen.contains("Album") && seen.contains("scan.png"), "\(seen)")
        print("PASS watch folders skip targets, partial downloads, hidden files and folders")
    }
}
