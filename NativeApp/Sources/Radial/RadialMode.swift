import Foundation

/// The three wheels. The modifier held when the wheel opens picks one; scrolling
/// over the wheel (or Tab in the picker) moves between them.
enum RadialMode: Int, CaseIterable {
    case convert
    case tools
    case actions

    var title: String {
        switch self {
        case .convert: return "CONVERT"
        case .tools: return "TOOLS"
        case .actions: return "ACTIONS"
        }
    }

    var accessibilityName: String {
        switch self {
        case .convert: return "Convert"
        case .tools: return "Tools"
        case .actions: return "File actions"
        }
    }

    /// The wheel the held modifiers ask for: Control for file actions, Command or Option for tools.
    static func forModifiers(command: Bool, option: Bool, control: Bool) -> RadialMode {
        if control { return .actions }
        if command || option { return .tools }
        return .convert
    }

    /// The next (or previous, for a negative step) wheel, wrapping round.
    func stepped(_ step: Int) -> RadialMode {
        let count = Self.allCases.count
        return Self(rawValue: ((rawValue + step) % count + count) % count) ?? .convert
    }
}

/// Turns scroll events into whole steps between wheels. A mouse-wheel notch is
/// one step, with a short pause so a fast spin does not race through every wheel;
/// a trackpad swipe is one step per `threshold` points; momentum is ignored.
struct ScrollStepper {
    var threshold: Double = 30
    var notchInterval: TimeInterval = 0.18
    private var accumulated: Double = 0
    private var lastStep: TimeInterval = -.infinity

    /// - Parameters:
    ///   - delta: the dominant scroll delta; negative when scrolling down or right.
    ///   - precise: true for trackpads and Magic Mouse (pixel deltas), false for wheel notches.
    ///   - momentum: true for the inertial events after a swipe.
    ///   - ended: true when the swipe gesture ends.
    /// - Returns: +1 for the next wheel, -1 for the previous one, 0 for none yet.
    mutating func step(delta: Double, precise: Bool, momentum: Bool, ended: Bool, at time: TimeInterval) -> Int {
        defer { if ended { accumulated = 0 } }
        guard !momentum, delta != 0 else { return 0 }
        if !precise {
            guard time - lastStep >= notchInterval else { return 0 }
            lastStep = time
            return delta < 0 ? 1 : -1
        }
        if (accumulated < 0) != (delta < 0) { accumulated = 0 }
        accumulated += delta
        guard abs(accumulated) >= threshold else { return 0 }
        let step = accumulated < 0 ? 1 : -1
        accumulated = 0
        return step
    }
}

/// Recognises Shift held on its own for a moment while Finder is in front: the
/// gesture that opens the wheel for Finder's selection without a drag. Typing a
/// capital letter never counts, because a key goes down while Shift is held.
struct ShiftHoldRecognizer {
    enum Event: Equatable {
        case none
        /// Shift has been held alone long enough: open the wheel.
        case fire
        /// Shift was let go after the wheel opened: pick what is under the pointer.
        case release
    }

    var holdDuration: TimeInterval = 0.4
    private var pressedAt: TimeInterval?
    private var spoiled = false
    private var fired = false

    /// - Parameters:
    ///   - shift: Shift is held.
    ///   - otherModifiers: Command, Option, Control or Fn is held too.
    ///   - mouseDown: the primary button is down (a drag has its own path).
    ///   - finderFront: Finder is the frontmost app.
    ///   - secondsSinceKeyDown: time since any key went down, system-wide.
    mutating func update(now: TimeInterval, shift: Bool, otherModifiers: Bool, mouseDown: Bool, finderFront: Bool, secondsSinceKeyDown: TimeInterval) -> Event {
        if fired {
            guard !shift else { return .none }
            reset()
            return .release
        }
        guard shift, !otherModifiers, !mouseDown else {
            reset()
            return .none
        }
        let start = pressedAt ?? now
        pressedAt = start
        if spoiled { return .none }
        // A key went down after Shift did: that is typing, not the gesture.
        if secondsSinceKeyDown + 0.02 < now - start {
            spoiled = true
            return .none
        }
        guard finderFront, now - start >= holdDuration else { return .none }
        fired = true
        return .fire
    }

    mutating func reset() {
        pressedAt = nil
        spoiled = false
        fired = false
    }
}
