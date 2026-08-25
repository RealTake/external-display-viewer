import Darwin

public enum EscapeDecision: Equatable, Sendable {
    case startThresholdTimer
    case suppress
    case replayShortESC(pid: pid_t)
    case requestReturn
    case discard
}

public struct EscapeHoldStateMachine: Sendable {
    private var state: State = .idle

    public init() {}

    public mutating func keyDown(pid: pid_t) -> EscapeDecision {
        switch state {
        case .idle:
            state = .holding(originalPID: pid, didRequestReturn: false)
            return .startThresholdTimer
        case .holding:
            return .suppress
        }
    }

    public mutating func thresholdReached() -> EscapeDecision {
        switch state {
        case .idle:
            return .discard
        case let .holding(originalPID, didRequestReturn: false):
            state = .holding(originalPID: originalPID, didRequestReturn: true)
            return .requestReturn
        case .holding(originalPID: _, didRequestReturn: true):
            return .suppress
        }
    }

    public mutating func keyUp(currentPID: pid_t?, isOriginalPIDRunning: Bool) -> EscapeDecision {
        switch state {
        case .idle:
            return .discard
        case .holding(originalPID: _, didRequestReturn: true):
            state = .idle
            return .suppress
        case let .holding(originalPID, didRequestReturn: false):
            state = .idle
            guard isOriginalPIDRunning, currentPID == originalPID else {
                return .discard
            }

            return .replayShortESC(pid: originalPID)
        }
    }
}

private enum State: Sendable {
    case idle
    case holding(originalPID: pid_t, didRequestReturn: Bool)
}
