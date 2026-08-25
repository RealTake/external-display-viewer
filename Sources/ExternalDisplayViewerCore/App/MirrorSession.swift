public enum MirrorSessionState: Equatable, Sendable {
    case idle, preparing, viewOnly, interactiveReady
    case controllingExternal, returning
    case failed(String)
}

public enum MirrorSessionEvent: Sendable {
    case prepare, captureStarted, interactiveEnabled, interactiveDisabled
    case pointerTransferred, returnRequested, returnCompleted
    case stop, fail(String)
}

public enum MirrorSessionError: Error, Equatable, Sendable {
    case invalidTransition(from: MirrorSessionState, event: MirrorSessionEvent)
}

extension MirrorSessionEvent: Equatable {
    public static func == (lhs: MirrorSessionEvent, rhs: MirrorSessionEvent) -> Bool {
        switch (lhs, rhs) {
        case (.prepare, .prepare),
            (.captureStarted, .captureStarted),
            (.interactiveEnabled, .interactiveEnabled),
            (.interactiveDisabled, .interactiveDisabled),
            (.pointerTransferred, .pointerTransferred),
            (.returnRequested, .returnRequested),
            (.returnCompleted, .returnCompleted),
            (.stop, .stop):
            true
        case let (.fail(lhsMessage), .fail(rhsMessage)):
            lhsMessage == rhsMessage
        default:
            false
        }
    }
}

public struct MirrorSession: Sendable {
    public private(set) var state: MirrorSessionState = .idle

    public init() {}

    public mutating func apply(_ event: MirrorSessionEvent) throws {
        if case let .fail(message) = event {
            state = .failed(message)
            return
        }

        if event == .stop {
            state = .idle
            return
        }

        switch (state, event) {
        case (.idle, .prepare):
            state = .preparing
        case (.preparing, .captureStarted):
            state = .viewOnly
        case (.viewOnly, .interactiveEnabled):
            state = .interactiveReady
        case (.interactiveReady, .interactiveDisabled):
            state = .viewOnly
        case (.interactiveReady, .pointerTransferred):
            state = .controllingExternal
        case (.controllingExternal, .returnRequested):
            state = .returning
        case (.returning, .returnCompleted):
            state = .viewOnly
        default:
            throw MirrorSessionError.invalidTransition(from: state, event: event)
        }
    }
}
