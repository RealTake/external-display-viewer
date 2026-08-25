public struct PermissionSnapshot: Equatable, Sendable {
    public let screenRecording: Bool
    public let postEvents: Bool
    public let listenEvents: Bool
    public let eventTapUsable: Bool

    public init(screenRecording: Bool, postEvents: Bool, listenEvents: Bool, eventTapUsable: Bool) {
        self.screenRecording = screenRecording
        self.postEvents = postEvents
        self.listenEvents = listenEvents
        self.eventTapUsable = eventTapUsable
    }

    public var canMirror: Bool {
        screenRecording
    }

    public var canInteract: Bool {
        postEvents && listenEvents && eventTapUsable
    }

    public var interactionBlockReason: PermissionInteractionBlockReason? {
        if !postEvents {
            return .postEventsDenied
        }

        if !listenEvents {
            return .listenEventsDenied
        }

        if !eventTapUsable {
            return .eventTapUnavailable
        }

        return nil
    }
}

public enum PermissionInteractionBlockReason: Equatable, Sendable {
    case postEventsDenied
    case listenEventsDenied
    case eventTapUnavailable
}
