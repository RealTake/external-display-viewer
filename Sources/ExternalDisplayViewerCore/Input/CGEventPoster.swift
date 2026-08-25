import CoreGraphics

public protocol PointerEventPosting: AnyObject {
    var currentLocation: CGPoint? { get }

    func warp(to location: CGPoint) -> Bool
    func postMouse(_ kind: PointerEvent.Kind, button: PointerButton, at location: CGPoint, clickCount: Int) -> Bool
    func postScroll(deltaX: Int32, deltaY: Int32, at location: CGPoint) -> Bool
}

public protocol TaggedPointerEventPosting: PointerEventPosting {
    func postMouse(
        _ kind: PointerEvent.Kind,
        button: PointerButton,
        at location: CGPoint,
        clickCount: Int,
        eventSourceUserData: Int64
    ) -> Bool
}

public final class CGEventPoster: TaggedPointerEventPosting {
    private let warpCursor: (CGPoint) -> CGError

    public init(warpCursor: @escaping (CGPoint) -> CGError = CGWarpMouseCursorPosition) {
        self.warpCursor = warpCursor
    }

    public var currentLocation: CGPoint? {
        CGEvent(source: nil)?.location
    }

    public func warp(to location: CGPoint) -> Bool {
        warpCursor(location) == .success
    }

    public func postMouse(_ kind: PointerEvent.Kind, button: PointerButton, at location: CGPoint, clickCount: Int) -> Bool {
        guard let event = CGEvent(
            mouseEventSource: nil,
            mouseType: kind.cgEventType(for: button),
            mouseCursorPosition: location,
            mouseButton: button.cgMouseButton
        ) else {
            return false
        }

        event.setIntegerValueField(.mouseEventClickState, value: Int64(clickCount))
        event.post(tap: .cghidEventTap)
        return true
    }

    public func postMouse(
        _ kind: PointerEvent.Kind,
        button: PointerButton,
        at location: CGPoint,
        clickCount: Int,
        eventSourceUserData: Int64
    ) -> Bool {
        guard let event = CGEvent(
            mouseEventSource: nil,
            mouseType: kind.cgEventType(for: button),
            mouseCursorPosition: location,
            mouseButton: button.cgMouseButton
        ) else {
            return false
        }

        event.setIntegerValueField(.mouseEventClickState, value: Int64(clickCount))
        event.setIntegerValueField(.eventSourceUserData, value: eventSourceUserData)
        event.post(tap: .cghidEventTap)
        return true
    }

    public func postScroll(deltaX: Int32, deltaY: Int32, at location: CGPoint) -> Bool {
        guard let event = CGEvent(
            scrollWheelEvent2Source: nil,
            units: .pixel,
            wheelCount: 2,
            wheel1: deltaY,
            wheel2: deltaX,
            wheel3: 0
        ) else {
            return false
        }

        event.location = location
        event.post(tap: .cghidEventTap)
        return true
    }
}

private extension PointerEvent.Kind {
    func cgEventType(for button: PointerButton) -> CGEventType {
        switch self {
        case .mouseDown:
            return button.downEventType
        case .mouseDragged:
            return button.draggedEventType
        case .mouseUp:
            return button.upEventType
        case .warp, .scroll:
            preconditionFailure("PointerEvent.Kind.\(self) is not a mouse event")
        }
    }
}

private extension PointerButton {
    var cgMouseButton: CGMouseButton {
        switch self {
        case .left:
            return .left
        case .right:
            return .right
        case .middle:
            return .center
        }
    }

    var downEventType: CGEventType {
        switch self {
        case .left:
            return .leftMouseDown
        case .right:
            return .rightMouseDown
        case .middle:
            return .otherMouseDown
        }
    }

    var draggedEventType: CGEventType {
        switch self {
        case .left:
            return .leftMouseDragged
        case .right:
            return .rightMouseDragged
        case .middle:
            return .otherMouseDragged
        }
    }

    var upEventType: CGEventType {
        switch self {
        case .left:
            return .leftMouseUp
        case .right:
            return .rightMouseUp
        case .middle:
            return .otherMouseUp
        }
    }
}
