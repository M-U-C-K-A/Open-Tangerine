import SwiftUI

/// Original citrus character. No agent hooks, third-party mascot assets or background monitor.
struct CitrusCompanion: View {
    @ObservedObject var state = CompanionState.shared
    private var working: Bool { state.phase == .processing }
    private var failed: Bool { state.phase == .failed }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 12, paused: ![.processing, .received, .delivering].contains(state.phase) || reduceMotion)) { timeline in
            let phase = !reduceMotion ? timeline.date.timeIntervalSinceReferenceDate * 5 : 0
            let bob = reduceMotion ? 0 : state.phase == .received ? -abs(sin(phase)) * 6 : state.phase == .delivering ? -abs(sin(phase)) * 3 : working ? sin(phase) * 2 : 0
            ZStack {
                if state.phase == .received || state.phase == .delivering {
                    Image(systemName: "doc.fill").font(.system(size: 16)).foregroundStyle(.white)
                        .offset(x: state.phase == .received ? -24 : 24, y: bob - 4)
                }
                if state.phase == .success {
                    Image(systemName: "sparkles").font(.system(size: 14)).foregroundStyle(.yellow).offset(x: 25, y: -20)
                }
                Ellipse().fill(.orange.opacity(0.16)).frame(width: 46, height: 8).offset(y: 24)
                ZStack {
                    Circle().fill(LinearGradient(colors: [.yellow, Theme.accent], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 42, height: 42)
                    Ellipse().fill(.green).frame(width: 17, height: 8).rotationEffect(.degrees(-35)).offset(x: 9, y: -24)
                    HStack(spacing: 10) {
                        Capsule().frame(width: state.phase == .success ? 7 : 4, height: state.phase == .success || state.phase == .cancelled ? 3 : failed ? 4 : state.phase == .received ? 10 : 7)
                        Capsule().frame(width: state.phase == .success ? 7 : 4, height: state.phase == .success || state.phase == .cancelled ? 3 : failed ? 4 : state.phase == .received ? 10 : 7)
                    }.foregroundStyle(Color.black.opacity(0.85)).offset(x: state.phase == .watching ? state.gaze * 5 : 0, y: -3)
                    Image(systemName: failed ? "line.diagonal" : state.phase == .watching ? "minus" : state.phase == .received ? "smallcircle.filled.circle" : working ? "ellipsis" : state.phase == .cancelled ? "minus" : "mouth")
                        .font(.system(size: 11, weight: .heavy)).foregroundStyle(.black.opacity(0.8)).offset(y: 9)
                    Capsule().fill(.white.opacity(0.55)).frame(width: 5, height: 10).rotationEffect(.degrees(35)).offset(x: -13, y: 8)
                }
                .offset(y: bob)
                .rotationEffect(.degrees(working && !reduceMotion ? sin(phase / 2) * 4 : 0))
            }
        }.frame(width: 66, height: 64)
        .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.7), value: state.phase)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: state.gaze)
        .accessibilityHidden(true)
    }
}

struct NotchJobRow: View {
    @ObservedObject var job: Job
    let cancel: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(job.title).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                Spacer(minLength: 5)
                if job.status.isFinished {
                    Image(systemName: failed ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                        .foregroundStyle(failed ? .red : .green)
                } else {
                    Text("\(Int(min(max(job.progress, 0), 1) * 100))%")
                        .font(.system(size: 10, design: .monospaced)).foregroundStyle(.white.opacity(0.65))
                    Button(action: cancel) { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain).help("Cancel this job").accessibilityLabel("Cancel \(job.detail)")
                }
            }
            Text(detail).font(.system(size: 10)).foregroundStyle(failed ? .red : .white.opacity(0.6)).lineLimit(1).help(detail)
            ProgressView(value: job.status == .done ? 1 : min(max(job.progress, 0), 1))
                .tint(Theme.accent).progressViewStyle(.linear).controlSize(.mini)
        }.foregroundStyle(.white).frame(height: 48)
    }
    private var failed: Bool { if case .failed = job.status { return true }; return false }
    private var detail: String {
        switch job.status {
        case .failed(let message): return message
        case .done: return "Ready · " + job.detail
        case .cancelled: return "Cancelled · " + job.detail
        case .waiting: return "Waiting · " + job.detail
        case .running: return job.detail
        }
    }
}
