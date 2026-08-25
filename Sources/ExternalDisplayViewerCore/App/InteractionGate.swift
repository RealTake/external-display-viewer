public enum InteractionGateResult: Equatable, Sendable {
    case allowed
    case blocked(InteractionGateBlockReason)
}

public enum InteractionGateBlockReason: Equatable, Sendable {
    case postEventsDenied
    case listenEventsDenied
    case eventTapUnavailable
    case sourceOverlapped
}

public enum InteractionGate {
    public static func evaluate(
        permissions: PermissionSnapshot,
        isSourceOverlapped: Bool
    ) -> InteractionGateResult {
        if !permissions.postEvents {
            return .blocked(.postEventsDenied)
        }

        if !permissions.listenEvents {
            return .blocked(.listenEventsDenied)
        }

        if !permissions.eventTapUsable {
            return .blocked(.eventTapUnavailable)
        }

        if isSourceOverlapped {
            return .blocked(.sourceOverlapped)
        }

        return .allowed
    }
}
