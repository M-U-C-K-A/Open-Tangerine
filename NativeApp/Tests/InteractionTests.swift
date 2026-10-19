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

        precondition(FinderSelection.parse("/Users/me/photo.heic\n/Users/me/Folder/\n/Users/me/clip copy.mov\n\nnot a path\n") == [URL(fileURLWithPath: "/Users/me/photo.heic"), URL(fileURLWithPath: "/Users/me/clip copy.mov")])
        precondition(FinderSelection.parse("").isEmpty)
        print("PASS Finder selection parsing keeps files and leaves folders out")
    }
}
