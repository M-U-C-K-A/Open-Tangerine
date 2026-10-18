import AppKit
import Combine
import SwiftUI

final class Job: ObservableObject, Identifiable {
    let id = UUID()
    let title: String
    let detail: String
    let symbol: String
    @Published var progress: Double = 0
    @Published var status: Status = .waiting
    var outputs: [URL] = []
    var task: Task<Void, Never>?

    enum Status: Equatable {
        case waiting
        case running
        case done
        case cancelled
        case failed(String)

        var isFinished: Bool {
            switch self {
            case .done, .cancelled, .failed: return true
            case .waiting, .running: return false
            }
        }
    }

    init(title: String, detail: String, symbol: String = "arrow.triangle.2.circlepath") {
        self.title = title
        self.detail = detail
        self.symbol = symbol
    }
}

@MainActor
final class JobRunner: ObservableObject {
    static let shared = JobRunner()

    @Published private(set) var jobs: [Job] = []
    private var hud: JobHUD?
    private var hudStyle: ProgressStyle?
    private var hideWorkItem: DispatchWorkItem?
    private let semaphore = AsyncSemaphore(limit: 1)
    private var jobSubscriptions: [UUID: AnyCancellable] = [:]

    private init() {}

    func convert(_ urls: [URL], to target: FileFormat) {
        DiagnosticLog.log("convert \(urls.map(\.lastPathComponent)) -> \(target.displayName)")
        var reserved = Set<String>()
        for url in urls {
            guard let source = FileFormat.detect(url) else {
                DiagnosticLog.log("skipping \(url.lastPathComponent): format not detected")
                continue
            }
            let directory = AppSettings.shared.outputLocation.directory(for: url)
            let destination = ConversionMatrix.outputURL(for: url, target: target, in: directory, existing: reserved)
            DiagnosticLog.log("destination \(destination.path)")
            reserved.insert(destination.lastPathComponent)
            let job = Job(title: "Converting to \(target.displayName)", detail: url.lastPathComponent, symbol: target.category.symbol)
            enqueue(job) { progress in
                let request = ConversionRequest(source: url, sourceFormat: source, target: target, destination: destination, progress: progress)
                try await Engines.convert(request)
                return [destination]
            }
        }
    }

    func enqueue(_ job: Job, work: @escaping (@escaping (Double) -> Void) async throws -> [URL]) {
        CompanionState.shared.transition(from: .received, to: .processing, after: 0.45)
        jobs.append(job)
        jobSubscriptions[job.id] = job.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
        DiagnosticLog.log("enqueue \(job.title) / \(job.detail); jobs=\(jobs.count)")
        showHUD()
        DiagnosticLog.log("hud shown")
        job.task = Task {
            await semaphore.wait()
            guard !Task.isCancelled else {
                job.status = .cancelled
                await semaphore.signal()
                return
            }
            DiagnosticLog.log("job running: \(job.detail)")
            job.status = .running
            let progress: (Double) -> Void = { value in
                Task { @MainActor in job.progress = value }
            }
            do {
                let outputs = try await work(progress)
                job.outputs = outputs
                job.progress = 1
                job.status = .done
                if jobs.allSatisfy({ $0.status.isFinished }) { CompanionState.shared.transition(from: .delivering, to: .success, after: 0.5) }
                DiagnosticLog.log("job done: \(job.detail) -> \(outputs.map(\.lastPathComponent))")
                if AppSettings.shared.revealInFinder, !outputs.isEmpty {
                    NSWorkspace.shared.activateFileViewerSelecting(outputs)
                }
            } catch is CancellationError {
                DiagnosticLog.log("job cancelled: \(job.detail)")
                job.status = .cancelled
            } catch OpenTangerineError.cancelled {
                DiagnosticLog.log("job cancelled: \(job.detail)")
                job.status = .cancelled
            } catch {
                DiagnosticLog.log("job failed: \(job.detail): \(error)")
                job.status = .failed(error.localizedDescription)
                CompanionState.shared.set(.failed)
            }
            await semaphore.signal()
            scheduleHide()
        }
    }

    func cancel(_ job: Job) {
        DiagnosticLog.log("cancel requested: \(job.detail)")
        job.task?.cancel()
        CompanionState.shared.set(.cancelled)
        job.status = .cancelled
        scheduleHide()
    }

    func cancelAll() {
        for job in jobs where !job.status.isFinished {
            job.task?.cancel()
        }
        dismissAll()
    }

    func run(title: String, detail: String, symbol: String = "arrow.triangle.2.circlepath", work: @escaping (@escaping (Double) -> Void) async throws -> [URL]) {
        enqueue(Job(title: title, detail: detail, symbol: symbol), work: work)
    }

    func watchWheel(label: String? = nil, direction: CGFloat = 0) {
        guard jobs.isEmpty, AppSettings.shared.progressStyle == .pill else { return }
        CompanionState.shared.watch(label: label, direction: direction)
        showHUD()
    }
    func beginWatching() {
        guard jobs.isEmpty else { return }
        CompanionState.shared.set(.watching)
        watchWheel()
    }
    func endWatching() { if jobs.isEmpty { hud?.hide() } }

    private func showHUD() {
        hideWorkItem?.cancel()
        let style = AppSettings.shared.progressStyle
        DiagnosticLog.log("showHUD style=\(style.rawValue) existing=\(hud != nil)")
        if hud == nil || hudStyle != style {
            hud?.hide()
            hud = style == .card ? JobHUDPanel(runner: self) : JobPillPanel(runner: self)
            hudStyle = style
        }
        hud?.show()
    }

    private func scheduleHide() {
        guard jobs.allSatisfy({ $0.status.isFinished }) else { return }
        guard !jobs.contains(where: { if case .failed = $0.status { return true }; return false }) else { return }
        hideWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.hud?.hide()
            self.jobs.removeAll()
            self.jobSubscriptions.removeAll()
        }
        hideWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5, execute: item)
    }

    func dismiss(_ job: Job) {
        jobs.removeAll { $0.id == job.id }
        jobSubscriptions[job.id] = nil
        if jobs.isEmpty {
            hud?.hide()
        } else {
            hud?.show()
        }
    }

    func dismissAll() {
        hideWorkItem?.cancel()
        jobs.removeAll()
        jobSubscriptions.removeAll()
        hud?.hide()
    }
}

actor AsyncSemaphore {
    private let limit: Int
    private var count = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(limit: Int) { self.limit = limit }

    func wait() async {
        if count < limit {
            count += 1
            return
        }
        await withCheckedContinuation { waiters.append($0) }
    }

    func signal() {
        if let next = waiters.first {
            waiters.removeFirst()
            next.resume()
        } else {
            count = max(0, count - 1)
        }
    }
}

@MainActor
protocol JobHUD: AnyObject {
    func show()
    func hide()
}

final class JobHUDPanel: NSPanel, NSWindowDelegate, JobHUD {
    private weak var runner: JobRunner?
    private var hosting: NSHostingController<JobHUDView>?

    init(runner: JobRunner) {
        self.runner = runner
        super.init(contentRect: NSRect(x: 0, y: 0, width: 340, height: 100), styleMask: [.titled, .closable, .fullSizeContentView, .nonactivatingPanel, .utilityWindow], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        titlebarAppearsTransparent = true
        titleVisibility = .hidden
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true
        level = .floating
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isMovableByWindowBackground = true
        delegate = self
        DiagnosticLog.log("card panel created")
        let controller = NSHostingController(rootView: JobHUDView(runner: runner))
        controller.sizingOptions = []
        hosting = controller
        contentViewController = controller
        DiagnosticLog.log("card hosting controller attached")
    }

    override var canBecomeKey: Bool { true }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        runner?.cancelAll()
        return false
    }

    func show() {
        guard let screen = NSScreen.main else {
            DiagnosticLog.log("card show: no main screen")
            return
        }
        let visible = screen.visibleFrame
        let size = (hosting?.sizeThatFits(in: unbounded) ?? .zero).roundedUp.nonEmpty(or: frame.size)
        DiagnosticLog.log("card show size=\(size) visible=\(visible)")
        setContentSize(size)
        setFrameOrigin(NSPoint(x: visible.maxX - size.width - 20, y: visible.maxY - size.height - 20))
        makeKeyAndOrderFront(nil)
        DiagnosticLog.log("card ordered front")
    }

    func hide() { orderOut(nil) }
}

final class JobPillPanel: NSPanel, JobHUD {
    private var hosting: NSHostingController<JobPillView>?
    private weak var runner: JobRunner?

    init(runner: JobRunner) {
        self.runner = runner
        super.init(contentRect: NSRect(x: 0, y: 0, width: 160, height: 32), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .statusBar
        isReleasedWhenClosed = false
        acceptsMouseMovedEvents = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        DiagnosticLog.log("pill panel created")
        let controller = NSHostingController(rootView: JobPillView(runner: runner))
        controller.sizingOptions = []
        hosting = controller
        contentViewController = controller
        DiagnosticLog.log("pill hosting controller attached")
    }

    override var canBecomeKey: Bool { true }

    func show() {
        let notchScreen = NSScreen.screens.first { $0.safeAreaInsets.top > 0 }
        guard let screen = notchScreen ?? NSScreen.main else {
            DiagnosticLog.log("pill show: no screen")
            return
        }
        let size = JobPillView.Layout.size(rows: max(1, runner?.jobs.count ?? 1))
        let top = screen.visibleFrame.maxY
        var centerX = screen.frame.midX
        if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            centerX = (left.maxX + right.minX) / 2
        }
        DiagnosticLog.log("pill show size=\(size) screen=\(screen.frame) inset=\(screen.safeAreaInsets.top) centerX=\(centerX) top=\(top)")
        let target = NSRect(x: (centerX - size.width / 2).rounded(), y: top - size.height - 2, width: size.width, height: size.height)
        if isVisible, frame != target {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.25
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                animator().setFrame(target, display: true)
            }
        } else {
            setFrame(target, display: true)
        }
        makeKeyAndOrderFront(nil)
        DiagnosticLog.log("pill ordered front")
    }

    func hide() { orderOut(nil) }
}

private let unbounded = CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)

private extension CGSize {
    var roundedUp: CGSize { CGSize(width: ceil(width), height: ceil(height)) }
    func nonEmpty(or fallback: CGSize) -> CGSize { width > 0 && height > 0 ? self : fallback }
}

struct JobPillView: View {
    @ObservedObject var runner: JobRunner
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var companion = CompanionState.shared
    enum Layout {
        static let rowHeight: CGFloat = 16
        static let iconWidth: CGFloat = 16
        static let iconSpacing: CGFloat = 8
        static let labelWidth: CGFloat = 92
        static let barWidth: CGFloat = 96
        static func size(rows: Int) -> CGSize { CGSize(width: 360, height: 48 + CGFloat(min(max(rows, 1), 3)) * 56) }
    }
    private var working: Bool { runner.jobs.contains { !$0.status.isFinished } }
    private var failed: Bool { runner.jobs.contains { if case .failed = $0.status { return true }; return false } }
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            CitrusCompanion()
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text(runner.jobs.isEmpty ? "READY WHEN YOU ARE" : companion.caption.uppercased())
                        .font(.system(size: 8, weight: .bold, design: .monospaced)).tracking(1.5)
                        .foregroundStyle(.white.opacity(0.5))
                    Spacer()
                    if runner.jobs.count > 1 {
                        Text("\(runner.jobs.count) files").font(.system(size: 9)).foregroundStyle(.white.opacity(0.5))
                    }
                    if !working {
                        Button { runner.dismissAll() } label: { Image(systemName: "xmark") }
                            .buttonStyle(.plain).foregroundStyle(.white.opacity(0.7)).help("Dismiss results")
                    }
                }
                if runner.jobs.isEmpty {
                    Text(companion.caption).font(.system(size: 12)).foregroundStyle(.white).lineLimit(2)
                    Text("Drop a file onto your choice").font(.system(size: 10)).foregroundStyle(.white.opacity(0.5))
                }
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(runner.jobs) { job in
                            NotchJobRow(job: job) { runner.cancel(job) }
                        }
                    }
                }.scrollIndicators(.hidden)
            }
        }
        .padding(.horizontal, 18).padding(.vertical, 16)
        .frame(width: 352, height: Layout.size(rows: runner.jobs.count).height - 8)
        .background(.black, in: UnevenRoundedRectangle(topLeadingRadius: 10, bottomLeadingRadius: 24, bottomTrailingRadius: 24, topTrailingRadius: 10))
        .overlay(UnevenRoundedRectangle(topLeadingRadius: 10, bottomLeadingRadius: 24, bottomTrailingRadius: 24, topTrailingRadius: 10).strokeBorder(.white.opacity(0.12)))
        .padding(4)
        .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: runner.jobs.map(\.id))
    }
}

struct JobPillRow: View {
    @ObservedObject var job: Job
    let hovering: Bool
    let showsLabel: Bool
    let cancel: () -> Void

    var body: some View {
        HStack(spacing: JobPillView.Layout.iconSpacing) {
            Button(action: cancel) {
                Image(systemName: showsCancel ? "xmark.circle.fill" : symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(tint)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: JobPillView.Layout.iconWidth, height: JobPillView.Layout.rowHeight)
            }
            .buttonStyle(.plain)
            .disabled(!showsCancel)
            .help(showsCancel ? "Cancel" : "")
            if showsLabel {
                Text(job.detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(width: JobPillView.Layout.labelWidth, alignment: .leading)
            }
            ProgressView(value: fraction)
                .progressViewStyle(.linear)
                .controlSize(.mini)
                .frame(width: JobPillView.Layout.barWidth)
        }
        .frame(height: JobPillView.Layout.rowHeight)
        .animation(.easeInOut(duration: 0.35), value: fraction)
    }

    private var showsCancel: Bool { hovering && !job.status.isFinished }

    private var fraction: Double {
        job.status == .done ? 1 : min(max(job.progress, 0), 1)
    }

    private var failed: Bool {
        if case .failed = job.status { return true }
        return false
    }

    private var tint: Color {
        if failed { return .red }
        return showsCancel ? .secondary : Theme.accent
    }

    private var symbol: String {
        switch job.status {
        case .failed: return "exclamationmark.triangle.fill"
        case .done: return "checkmark.circle.fill"
        case .cancelled: return "xmark.circle"
        case .waiting, .running: return job.symbol
        }
    }
}

struct JobHUDView: View {
    @ObservedObject var runner: JobRunner

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(Array(runner.jobs.enumerated()), id: \.element.id) { index, job in
                if index > 0 { Divider() }
                JobCardView(job: job)
            }
        }
        .padding(.top, 12)
        .padding(.leading, 40)
        .padding(.trailing, 16)
        .padding(.bottom, 16)
        .frame(width: 340)
        .background { Color.clear.glassEffect(.regular, in: .rect).ignoresSafeArea() }
        .tint(Theme.accent)
    }
}

struct JobCardView: View {
    @ObservedObject var job: Job

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Text(job.title)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
                Spacer(minLength: 0)
                trailing
            }
            Text(subtitle)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            ProgressView(value: fraction)
                .progressViewStyle(.linear)
                .controlSize(.small)
        }
    }

    private var fraction: CGFloat {
        job.status == .done ? 1 : CGFloat(min(max(job.progress, 0), 1))
    }

    private var subtitle: String {
        switch job.status {
        case .waiting: return "\(job.detail) · Waiting"
        case .running: return "\(job.detail) · \(Int((job.progress * 100).rounded()))%"
        case .done: return "\(job.detail) · Done"
        case .cancelled: return "\(job.detail) · Cancelled"
        case .failed(let message): return "\(job.detail) · \(message)"
        }
    }

    @ViewBuilder
    private var trailing: some View {
        switch job.status {
        case .done:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.accent)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
        case .cancelled:
            Image(systemName: "xmark.circle").foregroundStyle(.secondary)
        case .waiting, .running:
            EmptyView()
        }
    }
}

