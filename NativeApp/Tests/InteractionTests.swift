import Foundation
@main struct InteractionTests {
    @MainActor static func main() async throws {
        precondition(AppVersion("0.1.10")! > AppVersion("0.1.9")!)
        precondition(AppVersion("v1.0.0")! == AppVersion("1.0.0")!)
        precondition(AppVersion("1.2.3-beta") == nil)
        precondition(AppVersion("1.2") == nil)
        let state = CompanionState.shared
        state.set(.watching)
        state.watch(label: "PNG", direction: 3)
        precondition(state.gaze == 1 && state.caption.contains("PNG"))
        state.transition(from: .received, to: .processing, after: 0.01)
        state.set(.failed)
        try await Task.sleep(for: .milliseconds(30))
        precondition(state.phase == .failed, "Late animation must not overwrite error")
        state.transition(from: .delivering, to: .success, after: 0.01)
        try await Task.sleep(for: .milliseconds(30))
        precondition(state.phase == .success)
        print("PASS version ordering, invalid version rejection, gaze bounds, interrupted and completion transitions")
    }
}
