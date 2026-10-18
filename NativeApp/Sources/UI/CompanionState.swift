import SwiftUI

@MainActor final class CompanionState: ObservableObject {
    static let shared = CompanionState()
    enum Phase: String { case watching, received, processing, delivering, success, failed, cancelled }
    @Published var phase: Phase = .watching
    @Published var gaze: CGFloat = 0
    @Published var caption = "Choose a format — I’m ready"
    private var generation = 0
    func watch(label: String? = nil, direction: CGFloat = 0) {
        guard phase == .watching else { return }
        gaze = max(-1, min(1, direction))
        caption = label.map { "Looking at \($0)" } ?? "Choose a format — I’m ready"
    }
    func set(_ phase: Phase) {
        generation += 1
        self.phase = phase
        switch phase {
        case .watching: caption = "Choose a format — I’m ready"
        case .received: caption = "Got it!"
        case .processing: caption = "Making it happen…"
        case .delivering: caption = "Here you go…"
        case .success: caption = "Done. Your file is ready."
        case .failed: caption = "Something needs a look."
        case .cancelled: caption = "Stopped. Your original is safe."
        }
    }
    @discardableResult
    func transition(from: Phase, to: Phase, after delay: Double) -> Task<Void, Never> {
        set(from)
        let token = generation
        return Task {
            try? await Task.sleep(for: .seconds(delay))
            guard generation == token else { return }
            set(to)
        }
    }
}
