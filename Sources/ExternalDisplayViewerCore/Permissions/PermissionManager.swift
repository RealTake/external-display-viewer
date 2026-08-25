import CoreGraphics

public protocol PermissionManaging: Sendable {
    func refresh() -> PermissionSnapshot
    func requestScreenRecording() -> Bool
    func requestPostEvents() -> Bool
    func requestListenEvents() -> Bool
}

public struct PermissionManager: PermissionManaging {
    public init() {}

    public func refresh() -> PermissionSnapshot {
        PermissionSnapshot(
            screenRecording: CGPreflightScreenCaptureAccess(),
            postEvents: CGPreflightPostEventAccess(),
            listenEvents: CGPreflightListenEventAccess(),
            eventTapUsable: Self.canCreateEscapeEventTap()
        )
    }

    public func requestScreenRecording() -> Bool {
        CGRequestScreenCaptureAccess()
    }

    public func requestPostEvents() -> Bool {
        CGRequestPostEventAccess()
    }

    public func requestListenEvents() -> Bool {
        CGRequestListenEventAccess()
    }

    private static func canCreateEscapeEventTap() -> Bool {
        let escapeMask = CGEventMask(1 << CGEventType.keyDown.rawValue) | CGEventMask(1 << CGEventType.keyUp.rawValue)
        let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: escapeMask,
            callback: { _, _, event, _ in Unmanaged.passUnretained(event) },
            userInfo: nil
        )
        guard let tap else {
            return false
        }

        CFMachPortInvalidate(tap)
        return true
    }
}
