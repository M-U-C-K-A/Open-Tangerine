import Foundation

/// Renames files and folders in place from one pattern, with a preview, conflict checks
/// and all-or-nothing renaming: if one rename fails, the earlier ones are put back.
enum BatchRename {
    enum TextCase: String, CaseIterable, Identifiable {
        case keep, lower, upper, title
        var id: String { rawValue }
        var title: String {
            switch self {
            case .keep: return "Keep"
            case .lower: return "lower"
            case .upper: return "UPPER"
            case .title: return "Title"
            }
        }
    }

    struct Options: Equatable {
        /// `{name}` is the current name without its extension, `{n}` the counter, `{date}` the modification day.
        var pattern = "{name}"
        var find = ""
        var replace = ""
        var start = 1
        var digits = 2
        var textCase: TextCase = .keep
    }

    struct Item: Equatable {
        let source: URL
        let name: String
        var destination: URL { source.deletingLastPathComponent().appendingPathComponent(name) }
        var changes: Bool { name != source.lastPathComponent }
    }

    enum Problem: Equatable {
        case empty
        case invalidCharacter
        case hidden
        case duplicate
        case exists

        var message: String {
            switch self {
            case .empty: return "Empty name"
            case .invalidCharacter: return "“/” or “:” can't be in a name"
            case .hidden: return "A leading dot would hide it"
            case .duplicate: return "Same name as another file here"
            case .exists: return "A file with this name already exists"
            }
        }
    }

    static let dayFormat: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    static func modificationDate(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date()
    }

    /// The new name for each file, in order; the extension is kept as it is.
    static func plan(_ urls: [URL], options: Options, date: (URL) -> Date = modificationDate) -> [Item] {
        urls.enumerated().map { index, url in
            let folder = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true || url.hasDirectoryPath
            let ext = folder ? "" : url.pathExtension
            var base = ext.isEmpty ? url.lastPathComponent : String(url.lastPathComponent.dropLast(ext.count + 1))
            if !options.find.isEmpty {
                base = base.replacingOccurrences(of: options.find, with: options.replace)
            }
            let counter = String(options.start + index)
            let padded = String(repeating: "0", count: max(0, options.digits - counter.count)) + counter
            var name = options.pattern
                .replacingOccurrences(of: "{name}", with: base)
                .replacingOccurrences(of: "{n}", with: padded)
                .replacingOccurrences(of: "{date}", with: dayFormat.string(from: date(url)))
            switch options.textCase {
            case .keep: break
            case .lower: name = name.lowercased()
            case .upper: name = name.uppercased()
            case .title: name = name.capitalized
            }
            name = name.trimmingCharacters(in: .whitespaces)
            return Item(source: url, name: ext.isEmpty || name.isEmpty ? name : "\(name).\(ext)")
        }
    }

    /// What stops a rename, by index. Names compare without case, as APFS does by default.
    static func problems(_ items: [Item], exists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }) -> [Int: Problem] {
        var found: [Int: Problem] = [:]
        let sources = Set(items.map { $0.source.standardizedFileURL.path.lowercased() })
        var seen: [String: Int] = [:]
        for (index, item) in items.enumerated() {
            if item.name.isEmpty {
                found[index] = .empty
            } else if item.name.contains("/") || item.name.contains(":") {
                found[index] = .invalidCharacter
            } else if item.name.hasPrefix(".") {
                found[index] = .hidden
            }
            let key = item.destination.standardizedFileURL.path.lowercased()
            if let other = seen[key] {
                found[index] = found[index] ?? .duplicate
                found[other] = found[other] ?? .duplicate
            } else {
                seen[key] = index
            }
            if found[index] == nil, item.changes, !sources.contains(key), exists(item.destination) {
                found[index] = .exists
            }
        }
        return found
    }

    /// Renames in two steps through hidden temporary names, so swaps and case-only
    /// changes work; any failure puts every file back where it was.
    static func apply(_ items: [Item]) throws -> [URL] {
        let fm = FileManager.default
        let changing = items.filter(\.changes)
        guard problems(items).isEmpty else { throw OpenTangerineError.invalidInput("Some names clash or are not allowed.") }
        var staged: [(temp: URL, item: Item)] = []
        var placed: [(temp: URL, item: Item)] = []
        do {
            for item in changing {
                let temp = item.source.deletingLastPathComponent().appendingPathComponent(".opentangerine-rename-\(UUID().uuidString)")
                try fm.moveItem(at: item.source, to: temp)
                staged.append((temp, item))
            }
            for entry in staged {
                try fm.moveItem(at: entry.temp, to: entry.item.destination)
                placed.append(entry)
            }
        } catch {
            for entry in placed.reversed() { try? fm.moveItem(at: entry.item.destination, to: entry.temp) }
            for entry in staged.reversed() { try? fm.moveItem(at: entry.temp, to: entry.item.source) }
            throw error
        }
        return items.map { $0.changes ? $0.destination : $0.source }
    }
}
