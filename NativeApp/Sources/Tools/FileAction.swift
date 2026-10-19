import AppKit
import CryptoKit

enum FileAction: String, CaseIterable, Hashable {
    case reveal = "Reveal", copy = "Copy Files", paths = "Copy Paths", duplicate = "Duplicate"
    case zip = "ZIP", rename = "Rename", copyText = "Copy Text", hash = "SHA-256"
    var symbol: String {
        switch self {
        case .reveal: return "folder"
        case .copy: return "doc.on.doc"
        case .paths: return "link"
        case .duplicate: return "plus.square.on.square"
        case .zip: return "doc.zipper"
        case .rename: return "pencil.line"
        case .copyText: return "text.viewfinder"
        case .hash: return "number"
        }
    }

    static func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }

    /// The actions that make sense for this selection: folders can be zipped, renamed
    /// and copied but have no checksum; text can be read from images and PDFs.
    static func available(for urls: [URL]) -> [FileAction] {
        let folders = urls.contains(where: isDirectory)
        let readable = !urls.isEmpty && urls.allSatisfy { url in
            guard let format = FileFormat.detect(url) else { return false }
            return format.category == .image || format == .pdf
        }
        return allCases.filter { action in
            switch action {
            case .hash: return !folders
            case .copyText: return readable && !folders
            default: return true
            }
        }
    }

    /// Zips the selection next to it, as Finder does: one item becomes “name.zip”,
    /// several become “Archive.zip”. Nothing is ever overwritten.
    static func zip(_ urls: [URL]) async throws -> URL {
        guard let first = urls.first else { throw OpenTangerineError.invalidInput("Nothing to zip.") }
        let fm = FileManager.default
        let folder = first.deletingLastPathComponent()
        let destination = ConversionMatrix.uniqueURL(directory: folder, baseName: urls.count == 1 ? first.lastPathComponent : "Archive", suffix: "", ext: "zip")
        let staged = folder.appendingPathComponent(".opentangerine-\(UUID().uuidString).zip")
        defer { try? fm.removeItem(at: staged) }
        var source = first
        var keepParent = true
        var gathered: URL?
        defer { if let gathered { try? fm.removeItem(at: gathered) } }
        if urls.count > 1 {
            // Several items sit side by side at the root of the archive, as with Finder's Compress.
            let temp = fm.temporaryDirectory.appendingPathComponent("opentangerine-zip-\(UUID().uuidString)")
            try fm.createDirectory(at: temp, withIntermediateDirectories: true)
            gathered = temp
            var used = Set<String>()
            for url in urls {
                var name = url.lastPathComponent
                var counter = 2
                while used.contains(name.lowercased()) {
                    name = "\(url.deletingPathExtension().lastPathComponent) \(counter)" + (url.pathExtension.isEmpty ? "" : ".\(url.pathExtension)")
                    counter += 1
                }
                used.insert(name.lowercased())
                try fm.copyItem(at: url, to: temp.appendingPathComponent(name))
            }
            source = temp
            keepParent = false
        }
        let result = try await Shell.run("/usr/bin/ditto", ["-c", "-k", "--sequesterRsrc"] + (keepParent ? ["--keepParent"] : []) + [source.path, staged.path])
        guard result.succeeded else { throw OpenTangerineError.toolFailed("ditto", result.stderr) }
        try fm.moveItem(at: staged, to: destination)
        return destination
    }

    static func duplicateFiles(_ urls: [URL]) throws -> [URL] {
        try urls.map { source in
            let destination = ConversionMatrix.uniqueURL(directory: source.deletingLastPathComponent(), baseName: source.deletingPathExtension().lastPathComponent, suffix: "copy", ext: source.pathExtension)
            try FileManager.default.copyItem(at: source, to: destination)
            return destination
        }
    }

    static func hashReport(_ urls: [URL]) throws -> String {
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
                try Self.duplicateFiles(urls)
            }
        case .zip:
            JobRunner.shared.run(title: "Zipping", detail: urls.count == 1 ? urls[0].lastPathComponent : "\(urls.count) items", symbol: symbol) { progress in
                progress(0.2)
                return [try await Self.zip(urls)]
            }
        case .rename:
            ToolWindowManager.shared.open(.renameFiles, files: urls)
        case .copyText:
            JobRunner.shared.run(title: "Copying text", detail: urls.count == 1 ? urls[0].lastPathComponent : "\(urls.count) files", symbol: symbol) { progress in
                let text = try await Task.detached(priority: .userInitiated) {
                    try TextRecognition.text(in: urls, progress: progress)
                }.value
                await MainActor.run {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                }
                return []
            }
        case .hash:
            Task {
                do {
                    let report = try await Task.detached(priority: .userInitiated) {
                        try Self.hashReport(urls)
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
