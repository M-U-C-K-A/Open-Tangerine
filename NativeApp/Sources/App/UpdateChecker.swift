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
    private let releases = URL(string: "https://github.com/sintaxerrorpvtltd/Open-Tangerine/releases")!
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
        guard !checking else { return }
        if !interactive, let last = UserDefaults.standard.object(forKey: "lastUpdateCheck") as? Date,
           Date().timeIntervalSince(last) < 86400 { return }
        checking = true
        defer { checking = false }
        do {
            var request = URLRequest(url: endpoint, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.setValue("Open-Tangerine-UpdateChecker", forHTTPHeaderField: "User-Agent")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let response = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
            if response.statusCode == 404 {
                if interactive { show("No published releases yet", "You are using a developer build. Releases will appear here when published.") }
                return
            }
            guard response.statusCode == 200, data.count < 1_000_000 else { throw URLError(.badServerResponse) }
            let release = try JSONDecoder().decode(Release.self, from: data)
            guard !release.draft, !release.prerelease, let remote = AppVersion(release.tag_name),
                  let current = AppVersion(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0") else {
                throw URLError(.cannotParseResponse)
            }
            UserDefaults.standard.set(Date(), forKey: "lastUpdateCheck")
            if remote > current {
                availableVersion = release.tag_name
                onAvailable?(release.tag_name)
                if interactive {
                    let alert = NSAlert()
                    alert.messageText = "Open Tangerine \(release.tag_name) is available"
                    alert.informativeText = "Open the release page to download the update. Quit Open Tangerine and replace the app. Automatic installation is not enabled in this developer trial."
                    alert.addButton(withTitle: "View Update")
                    alert.addButton(withTitle: "Later")
                    NSApp.activate(ignoringOtherApps: true)
                    if alert.runModal() == .alertFirstButtonReturn { NSWorkspace.shared.open(releases) }
                }
            } else if interactive { show("You’re up to date", "This app is as new as the latest published release.") }
        } catch {
            if interactive { show("Couldn’t check for updates", "Check your connection and try again. GitHub may also be temporarily unavailable or rate-limited.") }
        }
    }
    private func show(_ title: String, _ detail: String) {
        let alert = NSAlert(); alert.messageText = title; alert.informativeText = detail
        NSApp.activate(ignoringOtherApps: true); alert.runModal()
    }
}
