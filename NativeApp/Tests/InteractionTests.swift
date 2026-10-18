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
        let interrupted = state.transition(from: .received, to: .processing, after: 0.01)
        state.set(.failed)
        await interrupted.value
        precondition(state.phase == .failed, "Late animation must not overwrite error")
        let completed = state.transition(from: .delivering, to: .success, after: 0.01)
        await completed.value
        precondition(state.phase == .success)
        print("PASS version ordering, invalid version rejection, gaze bounds, interrupted and completion transitions")
    }
}
