import AppKit

/// Reads the files selected in Finder, for the wheel opened with Shift alone.
/// It asks Finder over Apple Events, so macOS asks once for permission
/// (Privacy & Security → Automation); nothing else is read.
enum FinderSelection {
    enum Failure: Error, Equatable {
        case notAuthorized
        case failed(String)
    }

    static let script = """
    tell application "Finder"
        set out to ""
        repeat with f in (get selection)
            set out to out & POSIX path of (f as alias) & linefeed
        end repeat
        return out
    end tell
    """

    static func current() async -> Result<[URL], Failure> {
        do {
            let result = try await Shell.run("/usr/bin/osascript", ["-e", script])
            guard result.succeeded else {
                // -1743: the user has not allowed (or has denied) controlling Finder.
                return .failure(result.stderr.contains("-1743") ? .notAuthorized : .failed(result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)))
            }
            return .success(parse(result.stdout))
        } catch {
            return .failure(.failed(error.localizedDescription))
        }
    }

    /// One POSIX path per line. Folders end with a slash; they stay, for the file actions.
    static func parse(_ output: String) -> [URL] {
        output.split(whereSeparator: \.isNewline).compactMap { line in
            var path = String(line)
            guard path.hasPrefix("/") else { return nil }
            let folder = path.count > 1 && path.hasSuffix("/")
            if folder { path.removeLast() }
            return URL(fileURLWithPath: path, isDirectory: folder).standardizedFileURL
        }
    }

    private static var explained = false

    /// Says once per launch how to allow it, with a way to the right settings pane.
    @MainActor static func explainPermission() {
        guard !explained else { return }
        explained = true
        let alert = NSAlert()
        alert.messageText = "Allow Open Tangerine to see Finder's selection"
        alert.informativeText = "Opening the wheel with Shift alone asks Finder which files are selected. Turn on Finder for Open Tangerine in System Settings → Privacy & Security → Automation, or turn the option off in Open Tangerine's settings."
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Not Now")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn, let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
            NSWorkspace.shared.open(url)
        }
    }
}

/// Shows files selected in a Finder window brought to the front. Asked over Apple Events,
/// as for the selection: since macOS 14 a menu-bar app can't bring Finder forward itself,
/// so `activateFileViewerSelecting` alone selects the files out of sight.
enum FinderReveal {
    static func script(for urls: [URL]) -> String {
        let items = urls.map { url -> String in
            let path = url.path.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
            return "POSIX file \"\(path)\""
        }.joined(separator: ", ")
        return "tell application \"Finder\"\nreveal {\(items)}\nactivate\nend tell"
    }

    static func reveal(_ urls: [URL]) {
        let files = urls.filter { FileManager.default.fileExists(atPath: $0.path) }
        guard !files.isEmpty else { return }
        Task {
            let result = try? await Shell.run("/usr/bin/osascript", ["-e", script(for: files)])
            if result?.succeeded != true {
                await MainActor.run { NSWorkspace.shared.activateFileViewerSelecting(files) }
            }
        }
    }
}
