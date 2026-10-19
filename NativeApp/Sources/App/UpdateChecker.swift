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
    /// This fork's releases. Upstream builds lack the fork's tools, so updates never point there.
    static let repository = "M-U-C-K-A/Open-Tangerine"
    private let endpoint = URL(string: "https://api.github.com/repos/\(UpdateChecker.repository)/releases/latest")!
    var downloadPage: URL {
        URL(string: "https://github.com/\(Self.repository)/releases")!
    }
    private let session: URLSession
    private let defaults: UserDefaults
    private let currentVersion: String
    private let openPage: (URL) -> Void
    init(session: URLSession = .shared, defaults: UserDefaults = .standard,
         currentVersion: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0",
         openPage: @escaping (URL) -> Void = { NSWorkspace.shared.open($0) }) {
        self.session = session
        self.defaults = defaults
        self.currentVersion = currentVersion
        self.openPage = openPage
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
            openPage(downloadPage)
            return
        }
        guard !checking else { return }
        if let last = defaults.object(forKey: "lastUpdateCheck") as? Date,
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
            }
        } catch {
            // Background failures remain silent; manual checks always open the website.
        }
    }
}
