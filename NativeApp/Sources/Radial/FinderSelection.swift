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

    /// One POSIX path per line. Folders end with a slash and are left out, as in a drag.
    static func parse(_ output: String) -> [URL] {
        output.split(whereSeparator: \.isNewline).compactMap { line in
            let path = String(line)
            guard path.hasPrefix("/"), !path.hasSuffix("/") else { return nil }
            return URL(fileURLWithPath: path).standardizedFileURL
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
