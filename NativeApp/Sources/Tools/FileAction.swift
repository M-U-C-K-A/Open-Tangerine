import AppKit
import CryptoKit

enum FileAction: String, CaseIterable, Hashable {
    case reveal = "Reveal", copy = "Copy Files", paths = "Copy Paths", duplicate = "Duplicate", hash = "SHA-256"
    var symbol: String {
        switch self {
        case .reveal: return "folder"
        case .copy: return "doc.on.doc"
        case .paths: return "link"
        case .duplicate: return "plus.square.on.square"
        case .hash: return "number"
        }
    }
    @MainActor func run(_ urls: [URL]) {
        switch self {
        case .reveal: NSWorkspace.shared.activateFileViewerSelecting(urls)
        case .copy:
            NSPasteboard.general.clearContents()
            NSPasteboard.general.writeObjects(urls as [NSURL])
        case .paths:
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(urls.map(\.path).joined(separator: "\n"), forType: .string)
        case .duplicate:
            JobRunner.shared.run(title: "Duplicate", detail: "\(urls.count) files") { _ in
                try urls.map { source in
                    let destination = ConversionMatrix.uniqueURL(directory: source.deletingLastPathComponent(), baseName: source.deletingPathExtension().lastPathComponent, suffix: "copy", ext: source.pathExtension)
                    try FileManager.default.copyItem(at: source, to: destination)
                    return destination
                }
            }
        case .hash:
            Task {
                do {
                    let report = try await Task.detached(priority: .userInitiated) {
                        try urls.map { url in
                            let values = try url.resourceValues(forKeys: [.isRegularFileKey])
                            guard values.isRegularFile == true else { throw OpenTangerineError.unreadable(url) }
                            let file = try FileHandle(forReadingFrom: url)
                            defer { try? file.close() }
                            var hash = SHA256()
                            while let data = try file.read(upToCount: 1_048_576), !data.isEmpty {
                                try Task.checkCancellation()
                                hash.update(data: data)
                            }
                            return hash.finalize().map { String(format: "%02x", $0) }.joined() + "  " + url.lastPathComponent
                        }.joined(separator: "\n")
                    }.value
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(report, forType: .string)
                    let alert = NSAlert()
                    alert.messageText = "SHA-256 copied"
                    alert.informativeText = report
                    alert.runModal()
                } catch {
                    let alert = NSAlert(error: error)
                    alert.runModal()
                }
            }
        }
    }
}
