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
        precondition(checker.downloadPage.absoluteString == "https://sintaxerrorpvtltd.github.io/Open-Tangerine/?version=0.1.2#download")
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
    }
}
