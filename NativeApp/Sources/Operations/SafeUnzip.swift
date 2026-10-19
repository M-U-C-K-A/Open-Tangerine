import Foundation

/// Extracts ZIP archives only after reading their table of contents: no absolute
/// paths, no “..” escaping the folder, no links, a bounded number of entries and
/// size, and no archive that inflates a thousand times over. Nothing is overwritten.
enum SafeUnzip {
    struct Entry: Equatable {
        let name: String
        let size: Int64
        let isLink: Bool
        let isDirectory: Bool
    }

    struct Listing: Equatable {
        var entries: [Entry] = []
        var uncompressed: Int64 = 0
        var compressed: Int64 = 0
    }

    static let maxEntries = 100_000
    static let maxBytes: Int64 = 20_000_000_000
    static let maxRatio = 1_000.0

    /// Reads `zipinfo`'s listing: one line per entry, then a summary of the sizes.
    static func parse(_ text: String) -> Listing {
        var listing = Listing()
        let entry = try! NSRegularExpression(pattern: #"^([dl\-])\S*\s+\S+\s+\S+\s+(\d+)\s+\S+\s+\S+\s+\S+\s+\S+\s(.*)$"#)
        let summary = try! NSRegularExpression(pattern: #"^\d+ files?, (\d+) bytes uncompressed, (\d+) bytes compressed"#)
        for line in text.components(separatedBy: .newlines) {
            let range = NSRange(line.startIndex..., in: line)
            if let match = entry.firstMatch(in: line, range: range),
               let kind = Range(match.range(at: 1), in: line), let size = Range(match.range(at: 2), in: line), let name = Range(match.range(at: 3), in: line) {
                listing.entries.append(Entry(name: String(line[name]), size: Int64(line[size]) ?? 0, isLink: line[kind] == "l", isDirectory: line[kind] == "d"))
            } else if let match = summary.firstMatch(in: line, range: range),
                      let total = Range(match.range(at: 1), in: line), let packed = Range(match.range(at: 2), in: line) {
                listing.uncompressed = Int64(line[total]) ?? 0
                listing.compressed = Int64(line[packed]) ?? 0
            }
        }
        if listing.uncompressed == 0 { listing.uncompressed = listing.entries.reduce(0) { $0 + $1.size } }
        return listing
    }

    /// Why an archive is refused, in words; nil when it is safe to extract.
    static func problem(with listing: Listing, freeSpace: Int64) -> String? {
        if listing.entries.isEmpty { return "The archive is empty or can't be read." }
        if listing.entries.count > maxEntries { return "The archive holds more than \(maxEntries) items." }
        if listing.entries.contains(where: \.isLink) { return "The archive contains links, which could point outside the folder." }
        for entry in listing.entries {
            let parts = entry.name.replacingOccurrences(of: "\\", with: "/").split(separator: "/", omittingEmptySubsequences: false)
            if entry.name.hasPrefix("/") || entry.name.hasPrefix("\\") || parts.contains("..") || entry.name.contains(":") && entry.name.first?.isLetter == true && entry.name.dropFirst().first == ":" {
                return "The archive tries to write outside its folder (\(entry.name))."
            }
        }
        if listing.uncompressed > maxBytes { return "The archive would unpack to more than 20 GB." }
        if listing.uncompressed > freeSpace { return "There isn't enough free space to unpack it here." }
        if listing.compressed > 0, listing.uncompressed > 100_000_000, Double(listing.uncompressed) / Double(listing.compressed) > maxRatio {
            return "The archive would grow more than a thousand times when unpacked."
        }
        return nil
    }

    /// Unpacks next to the archive: its single top folder as it is, otherwise a folder named after the archive.
    static func extract(_ archive: URL) async throws -> URL {
        let fm = FileManager.default
        let listed = try await Shell.run("/usr/bin/zipinfo", [archive.path])
        guard listed.succeeded else { throw OpenTangerineError.invalidInput("\(archive.lastPathComponent) isn't a ZIP archive, or it is damaged.") }
        let folder = archive.deletingLastPathComponent()
        let free = (try? folder.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage) ?? Int64.max
        if let problem = problem(with: parse(listed.stdout), freeSpace: free) {
            throw OpenTangerineError.invalidInput(problem)
        }
        let staging = folder.appendingPathComponent(".opentangerine-unzip-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: staging) }
        let result = try await Shell.run("/usr/bin/ditto", ["-x", "-k", archive.path, staging.path])
        guard result.succeeded else { throw OpenTangerineError.toolFailed("ditto", result.stderr) }
        let top = (try fm.contentsOfDirectory(at: staging, includingPropertiesForKeys: [.isDirectoryKey])).filter { $0.lastPathComponent != "__MACOSX" }
        if top.count == 1, (try? top[0].resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
            let destination = ConversionMatrix.uniqueDirectory(directory: folder, name: top[0].lastPathComponent)
            try fm.moveItem(at: top[0], to: destination)
            return destination
        }
        let destination = ConversionMatrix.uniqueDirectory(directory: folder, name: ConversionMatrix.strippedBaseName(archive.lastPathComponent))
        try fm.moveItem(at: staging, to: destination)
        try? fm.removeItem(at: destination.appendingPathComponent("__MACOSX"))
        return destination
    }
}
