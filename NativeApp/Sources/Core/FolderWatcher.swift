import Combine
import Foundation

/// A folder whose new files are converted on arrival.
struct WatchRule: Codable, Identifiable, Equatable {
    var id = UUID()
    var path: String
    var target: String
    var enabled = true

    var folder: URL { URL(fileURLWithPath: path, isDirectory: true) }
    var targetFormat: FileFormat? { FileFormat(rawValue: target) }
}

/// Watches the folders in Settings and converts files that arrive in them. Files already
/// there when watching starts are left alone; a file is taken once its size stops changing.
@MainActor
final class FolderWatcher {
    static let shared = FolderWatcher()

    private struct Watch {
        let rule: WatchRule
        let source: DispatchSourceFileSystemObject
        var known: Set<String>
        /// Names produced from files this watch converted, so outputs never loop back in.
        var produced: Set<String> = []
        var pending: [String: Int64] = [:]
    }

    private var watches: [UUID: Watch] = [:]
    private var subscription: AnyCancellable?
    private var timer: Timer?

    func start() {
        subscription = AppSettings.shared.$watchRules
            .removeDuplicates()
            .sink { [weak self] rules in
                Task { @MainActor in self?.apply(rules) }
            }
    }

    private func apply(_ rules: [WatchRule]) {
        let wanted = rules.filter { $0.enabled && $0.targetFormat != nil }
        for (id, watch) in watches where !wanted.contains(watch.rule) {
            watch.source.cancel()
            watches[id] = nil
        }
        for rule in wanted where watches[rule.id] == nil {
            let descriptor = open(rule.path, O_EVTONLY)
            guard descriptor >= 0 else {
                DiagnosticLog.log("watch: cannot open \(rule.path)")
                continue
            }
            let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: [.write, .rename], queue: .main)
            source.setEventHandler { [weak self] in
                Task { @MainActor in self?.scan(rule.id) }
            }
            source.setCancelHandler { close(descriptor) }
            source.resume()
            watches[rule.id] = Watch(rule: rule, source: source, known: Set(Self.names(in: rule.folder)))
        }
        timer?.invalidate()
        timer = watches.isEmpty ? nil : Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.scanAll() }
        }
    }

    private func scanAll() {
        for id in watches.keys { scan(id) }
    }

    /// New names are noted with their size; a name whose size held since the last look is converted.
    private func scan(_ id: UUID) {
        guard var watch = watches[id], let target = watch.rule.targetFormat else { return }
        for name in Self.names(in: watch.rule.folder) where !watch.known.contains(name) {
            let url = watch.rule.folder.appendingPathComponent(name)
            let size = FileSizeFormatter.size(of: url)
            if let previous = watch.pending[name], previous == size, size > 0 {
                watch.pending[name] = nil
                watch.known.insert(name)
                let base = ConversionMatrix.strippedBaseName(name).lowercased()
                guard Self.shouldConvert(url, to: target), !watch.produced.contains(base) else { continue }
                watch.produced.insert(base)
                DiagnosticLog.log("watch: converting \(name) -> \(target.displayName)")
                JobRunner.shared.convert([url], to: target)
            } else {
                watch.pending[name] = size
            }
        }
        watches[id] = watch
    }

    /// A file is converted when it can become the target and is not already in that format.
    static func shouldConvert(_ url: URL, to target: FileFormat) -> Bool {
        guard let format = FileFormat.detect(url), format != target else { return false }
        return ConversionMatrix.targets(for: format).contains(target)
    }

    /// Visible regular files; downloads in progress and the app's own staging files are skipped.
    static func names(in folder: URL) -> [String] {
        let items = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles])) ?? []
        let partial = ["download", "crdownload", "part", "partial"]
        return items.compactMap { url in
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true,
                  !partial.contains(url.pathExtension.lowercased()) else { return nil }
            return url.lastPathComponent
        }
    }
}
