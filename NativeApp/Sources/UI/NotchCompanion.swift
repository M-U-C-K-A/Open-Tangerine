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
                    HStack(spacing: 8) {
                        eye
                        eye
                    }.offset(x: state.phase == .watching ? state.gaze * 4 : 0, y: -3)
                    HStack(spacing: 24) {
                        Ellipse().fill(Color.pink.opacity(0.55)).frame(width: 8, height: 4)
                        Ellipse().fill(Color.pink.opacity(0.55)).frame(width: 8, height: 4)
                    }.offset(y: 5)
                    if state.phase == .received {
                        Ellipse().fill(Color(red: 0.3, green: 0.1, blue: 0.05)).frame(width: 7, height: 9).offset(y: 10)
                    } else {
                        Path { path in
                            path.move(to: CGPoint(x: 16, y: failed ? 32 : 28))
                            path.addQuadCurve(to: CGPoint(x: 28, y: failed ? 32 : 28),
                                              control: CGPoint(x: 22, y: failed ? 24 : 38))
                        }.stroke(Color(red: 0.3, green: 0.1, blue: 0.05), style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
                        .frame(width: 44, height: 44)
                    }
                    if working {
                        Image(systemName: "gearshape.fill").font(.system(size: 12)).foregroundStyle(.white.opacity(0.85))
                            .rotationEffect(.degrees(reduceMotion ? 0 : phase * 30)).offset(x: 26, y: 15)
                    }
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
    @ViewBuilder private var eye: some View {
        if state.phase == .success || state.phase == .delivering {
            Path { path in
                path.move(to: CGPoint(x: 0, y: 6))
                path.addQuadCurve(to: CGPoint(x: 9, y: 6), control: CGPoint(x: 4.5, y: -2))
            }.stroke(.black.opacity(0.85), style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
                .frame(width: 9, height: 10)
        } else {
            ZStack(alignment: .topLeading) {
                Ellipse().fill(Color(red: 0.25, green: 0.09, blue: 0.04))
                Circle().fill(.white).frame(width: 3, height: 3).offset(x: 1.5, y: 1.5)
                Circle().fill(.white.opacity(0.5)).frame(width: 1.5, height: 1.5).offset(x: 5, y: 6)
            }.frame(width: 8, height: state.phase == .cancelled ? 4 : failed ? 7 : 11)
        }
    }

}

struct NotchJobRow: View {
    @ObservedObject var job: Job
    let cancel: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(title).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                Spacer(minLength: 5)
                if job.status.isFinished {
                    Image(systemName: failed ? "exclamationmark.circle.fill" : job.status == .cancelled ? "xmark.circle.fill" : "checkmark.circle.fill")
                        .foregroundStyle(failed ? .red : .green)
                } else {
                    Text("\(Int(min(max(job.progress, 0), 1) * 100))%")
                        .font(.system(size: 10, design: .monospaced)).foregroundStyle(.white.opacity(0.65))
                    Button(action: cancel) { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain).help("Cancel this job").accessibilityLabel("Cancel \(job.detail)")
                }
            }
            Text(detail).font(.system(size: 10)).foregroundStyle(failed ? .red : .white.opacity(0.6)).lineLimit(1).help(detail)
            if job.status == .done && !job.outputs.isEmpty {
                JobOutputActions(job: job)
            } else {
                ProgressView(value: job.status == .done ? 1 : min(max(job.progress, 0), 1))
                    .tint(Theme.accent).progressViewStyle(.linear).controlSize(.mini)
            }
        }.foregroundStyle(.white).frame(height: 48)
    }
    private var title: String {
        switch job.status {
        case .failed: return job.title.replacingOccurrences(of: "Converting to", with: "Couldn’t convert to")
        case .done: return job.title.replacingOccurrences(of: "Converting to", with: "Converted to")
        case .cancelled: return "Conversion cancelled"
        case .waiting, .running: return job.title
        }
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
