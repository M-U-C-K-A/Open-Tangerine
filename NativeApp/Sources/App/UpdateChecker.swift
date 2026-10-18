import AppKit
import Foundation

struct AppVersion: Comparable {
    let numbers: [Int]
    init?(_ text: String) {
        let value = text.hasPrefix("v") ? String(text.dropFirst()) : text
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3, parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }),
              parts.allSatisfy({ Int($0) != nil }) else { return nil }
        numbers = parts.compactMap { Int($0) }
    }
    static func < (lhs: Self, rhs: Self) -> Bool { lhs.numbers.lexicographicallyPrecedes(rhs.numbers) }
}

@MainActor final class UpdateChecker {
    static let shared = UpdateChecker()
    private let endpoint = URL(string: "https://api.github.com/repos/sintaxerrorpvtltd/Open-Tangerine/releases/latest")!
    var downloadPage: URL {
        var page = URLComponents(string: "https://sintaxerrorpvtltd.github.io/Open-Tangerine/")!
        page.queryItems = [URLQueryItem(name: "version", value: currentVersion)]
        page.fragment = "download"
        return page.url!
    }
    private let session: URLSession
    private let defaults: UserDefaults
    private let currentVersion: String
    init(session: URLSession = .shared, defaults: UserDefaults = .standard,
         currentVersion: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0") {
        self.session = session
        self.defaults = defaults
        self.currentVersion = currentVersion
    }
    private var checking = false
    private var timer: Timer?
    var onAvailable: ((String) -> Void)?
    private(set) var availableVersion: String?
    struct Release: Decodable { let tag_name: String; let draft: Bool; let prerelease: Bool }

    func start() {
        Task { await check(interactive: false) }
        timer = Timer.scheduledTimer(withTimeInterval: 86400, repeats: true) { _ in
            Task { @MainActor in await UpdateChecker.shared.check(interactive: false) }
        }
    }
    func check(interactive: Bool) async {
        if interactive {
            NSWorkspace.shared.open(downloadPage)
            return
        }
        guard !checking else { return }
        if !interactive, let last = defaults.object(forKey: "lastUpdateCheck") as? Date,
           Date().timeIntervalSince(last) < 86400 { return }
        checking = true
        defer { checking = false }
        do {
            var request = URLRequest(url: endpoint, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.setValue("Open-Tangerine-UpdateChecker", forHTTPHeaderField: "User-Agent")
            let (data, response) = try await session.data(for: request)
            guard let response = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
            if response.statusCode == 404 {
                if interactive { show("No published releases yet", "You are using a developer build. Releases will appear here when published.") }
                return
            }
            guard response.statusCode == 200, data.count < 1_000_000 else { throw URLError(.badServerResponse) }
            let release = try JSONDecoder().decode(Release.self, from: data)
            guard !release.draft, !release.prerelease, let remote = AppVersion(release.tag_name),
                  let current = AppVersion(currentVersion) else {
                throw URLError(.cannotParseResponse)
            }
            defaults.set(Date(), forKey: "lastUpdateCheck")
            if remote > current {
                availableVersion = release.tag_name
                onAvailable?(release.tag_name)

            } else {
                availableVersion = nil
                if interactive { show("No newer published release", "This app is as new as the latest published release. Source-code changes on GitHub appear here only after a release has been published.") }
            }
        } catch {
            if interactive { show("Couldn’t check for updates", "Check your connection and try again. GitHub may also be temporarily unavailable or rate-limited.") }
        }
    }
    private func show(_ title: String, _ detail: String) {
        let alert = NSAlert(); alert.messageText = title; alert.informativeText = detail
        NSApp.activate(ignoringOtherApps: true); alert.runModal()
    }
}
