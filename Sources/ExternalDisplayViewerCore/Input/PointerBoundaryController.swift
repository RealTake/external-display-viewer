@preconcurrency import CoreGraphics
import Foundation

@MainActor
public protocol PointerBoundaryControlling: AnyObject {
    var onExit: @MainActor (PointerPortalExit) -> Void { get set }
    var onTapFailure: @MainActor () -> Void { get set }

    func start(displayFrame: CGRect) -> Bool

    func prepareForReturn() -> PointerBoundaryReturnPreparationResult

    func stop()
}

public enum PointerBoundaryReturnPreparationResult: Equatable, Sendable {
    case tornDown
    case draining
    case failed
}

@MainActor
public final class PointerBoundaryController: PointerBoundaryControlling {
    public static let syntheticForcedMouseUpTag: Int64 = 0x5054424f554e4455

    public var onExit: @MainActor (PointerPortalExit) -> Void
    public var onTapFailure: @MainActor () -> Void

    private let poster: PointerEventPosting
    private let tapLifecycle: PointerBoundaryTapLifecycle
    private var state: PointerBoundaryState?
    private var eventTap: PointerBoundaryTapHandle?
    private var tapContext: PointerBoundaryTapContextLifetime?
    private var pendingPhysicalReleases: [PointerButton] = []
    private var didReenableAfterDisable = false
    private var didNotifyTapFailure = false

    public convenience init(
        poster: PointerEventPosting = CGEventPoster(),
        onExit: @escaping @MainActor (PointerPortalExit) -> Void = { _ in },
        onTapFailure: @escaping @MainActor () -> Void = {}
    ) {
        self.init(
            poster: poster,
            tapLifecycle: .live,
            onExit: onExit,
            onTapFailure: onTapFailure
        )
    }

    init(
        poster: PointerEventPosting,
        tapLifecycle: PointerBoundaryTapLifecycle,
        onExit: @escaping @MainActor (PointerPortalExit) -> Void = { _ in },
        onTapFailure: @escaping @MainActor () -> Void = {}
    ) {
        self.poster = poster
        self.tapLifecycle = tapLifecycle
        self.onExit = onExit
        self.onTapFailure = onTapFailure
    }

    public func start(displayFrame: CGRect) -> Bool {
        guard eventTap == nil else {
            return true
        }

        let context = PointerBoundaryTapContextLifetime(
            acquireUserInfo: { Unmanaged.passRetained(self).toOpaque() },
            releaseUserInfo: { Unmanaged<PointerBoundaryController>.fromOpaque($0).release() }
        )
        guard let tap = tapLifecycle.create(
            .cgSessionEventTap,
            .headInsertEventTap,
            .defaultTap,
            Self.mouseEventMask,
            Self.handleEvent,
            context.userInfo
        ) else {
            context.release()
            return false
        }

        guard tapLifecycle.addToMainRunLoop(tap) else {
            tapLifecycle.invalidate(tap)
            context.release()
            return false
        }

        eventTap = tap
        tapContext = context
        state = PointerBoundaryState(displayFrame: displayFrame)
        pendingPhysicalReleases = []
        didReenableAfterDisable = false
        didNotifyTapFailure = false
        tapLifecycle.enable(tap, true)
        return true
    }

    public func prepareForReturn() -> PointerBoundaryReturnPreparationResult {
        guard var currentState = state else {
            stop()
            return .tornDown
        }

        let releases = currentState.beginForcedReturn()
        state = currentState

        guard !releases.isEmpty else {
            performStopTeardown()
            return .tornDown
        }

        guard poster is TaggedPointerEventPosting else {
            performStopTeardown()
            return .failed
        }

        var didFail = false
        for release in releases {
            if postForcedMouseUp(release) {
                appendPendingPhysicalRelease(release.button)
            } else {
                didFail = true
            }
        }

        guard !pendingPhysicalReleases.isEmpty else {
            performStopTeardown()
            return didFail ? .failed : .tornDown
        }

        return didFail ? .failed : .draining
    }

    public func stop() {
        performStopTeardown()
    }

    private static var mouseEventMask: CGEventMask {
        [
            CGEventType.mouseMoved,
            .leftMouseDown,
            .leftMouseUp,
            .leftMouseDragged,
            .rightMouseDown,
            .rightMouseUp,
            .rightMouseDragged,
            .otherMouseDown,
            .otherMouseUp,
            .otherMouseDragged
        ].reduce(CGEventMask(0)) { mask, type in
            mask | CGEventMask(1 << type.rawValue)
        }
    }

    private static let handleEvent: CGEventTapCallBack = { _, type, event, userInfo in
        guard let userInfo else {
            return Unmanaged.passUnretained(event)
        }

        let controller = Unmanaged<PointerBoundaryController>.fromOpaque(userInfo).takeUnretainedValue()
        return MainActor.assumeIsolated {
            controller.handle(type: type, event: event)
        }
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            handleTapDisablement()
            return Unmanaged.passUnretained(event)
        case .mouseMoved,
             .leftMouseDown, .rightMouseDown, .otherMouseDown,
             .leftMouseUp, .rightMouseUp, .otherMouseUp,
             .leftMouseDragged, .rightMouseDragged, .otherMouseDragged:
            return handleMouse(type: type, event: event)
        default:
            return Unmanaged.passUnretained(event)
        }
    }

    private func handleMouse(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        guard event.getIntegerValueField(.eventSourceUserData) != Self.syntheticForcedMouseUpTag else {
            return Unmanaged.passUnretained(event)
        }

        guard var currentState = state, let boundaryEvent = boundaryEvent(type: type, event: event) else {
            return Unmanaged.passUnretained(event)
        }

        let action: PointerBoundaryAction
        if case let .up(button, _) = boundaryEvent, pendingPhysicalReleases.contains(button) {
            action = currentState.consumeRelease(button)
        } else {
            action = currentState.consume(boundaryEvent)
        }
        state = currentState

        switch action {
        case .forward:
            return Unmanaged.passUnretained(event)
        case let .forwardAt(location):
            if type.isDraggedMouseEvent && event.location != location {
                event.location = location
            }
            return Unmanaged.passUnretained(event)
        case .suppress:
            if case let .up(button, _) = boundaryEvent {
                removePendingPhysicalRelease(button)
            }
            if pendingPhysicalReleases.isEmpty {
                performStopTeardown()
            }
            return nil
        case let .requestReturn(exit):
            onExit(exit)
            return Unmanaged.passUnretained(event)
        }
    }

    private func boundaryEvent(type: CGEventType, event: CGEvent) -> PointerBoundaryEvent? {
        let location = event.location
        let delta = CGVector(
            dx: CGFloat(event.getIntegerValueField(.mouseEventDeltaX)),
            dy: CGFloat(event.getIntegerValueField(.mouseEventDeltaY))
        )

        switch type {
        case .mouseMoved:
            return .move(location: location, delta: delta)
        case .leftMouseDown:
            return .down(button: .left, location: location)
        case .rightMouseDown:
            return .down(button: .right, location: location)
        case .otherMouseDown:
            return .down(button: .middle, location: location)
        case .leftMouseUp:
            return .up(button: .left, location: location)
        case .rightMouseUp:
            return .up(button: .right, location: location)
        case .otherMouseUp:
            return .up(button: .middle, location: location)
        case .leftMouseDragged:
            return .dragged(button: .left, location: location, delta: delta)
        case .rightMouseDragged:
            return .dragged(button: .right, location: location, delta: delta)
        case .otherMouseDragged:
            return .dragged(button: .middle, location: location, delta: delta)
        default:
            return nil
        }
    }

    private func postForcedMouseUp(_ release: PointerBoundaryForcedRelease) -> Bool {
        guard let taggedPoster = poster as? TaggedPointerEventPosting else {
            return false
        }

        return taggedPoster.postMouse(
            .mouseUp,
            button: release.button,
            at: release.location,
            clickCount: 1,
            eventSourceUserData: Self.syntheticForcedMouseUpTag
        )
    }

    private func appendPendingPhysicalRelease(_ button: PointerButton) {
        guard !pendingPhysicalReleases.contains(button) else {
            return
        }

        pendingPhysicalReleases.append(button)
    }

    private func removePendingPhysicalRelease(_ button: PointerButton) {
        pendingPhysicalReleases.removeAll { $0 == button }
    }

    private func handleTapDisablement() {
        guard let eventTap else {
            notifyTapFailureOnce()
            return
        }

        guard !didReenableAfterDisable else {
            notifyTapFailureOnce()
            performStopTeardown()
            return
        }

        didReenableAfterDisable = true
        tapLifecycle.enable(eventTap, true)
    }

    private func notifyTapFailureOnce() {
        guard !didNotifyTapFailure else {
            return
        }

        didNotifyTapFailure = true
        onTapFailure()
    }

    private func performStopTeardown() {
        let eventTap = self.eventTap
        let context = self.tapContext
        state = nil
        pendingPhysicalReleases = []
        didReenableAfterDisable = false
        self.eventTap = nil
        self.tapContext = nil

        guard let eventTap else {
            context?.release()
            return
        }

        tapLifecycle.removeFromMainRunLoop(eventTap)
        tapLifecycle.invalidate(eventTap)
        context?.release()
    }
}

final class PointerBoundaryTapHandle {
    let tap: CFMachPort?
    let runLoopSource: CFRunLoopSource?

    init(tap: CFMachPort?, runLoopSource: CFRunLoopSource?) {
        self.tap = tap
        self.runLoopSource = runLoopSource
    }
}

struct PointerBoundaryTapLifecycle {
    let create: @MainActor (
        CGEventTapLocation,
        CGEventTapPlacement,
        CGEventTapOptions,
        CGEventMask,
        CGEventTapCallBack,
        UnsafeMutableRawPointer?
    ) -> PointerBoundaryTapHandle?
    let addToMainRunLoop: @MainActor (PointerBoundaryTapHandle) -> Bool
    let removeFromMainRunLoop: @MainActor (PointerBoundaryTapHandle) -> Void
    let enable: @MainActor (PointerBoundaryTapHandle, Bool) -> Void
    let invalidate: @MainActor (PointerBoundaryTapHandle) -> Void

    static let live = PointerBoundaryTapLifecycle(
        create: { tap, place, options, mask, callback, userInfo in
            guard let machPort = CGEvent.tapCreate(
                tap: tap,
                place: place,
                options: options,
                eventsOfInterest: mask,
                callback: callback,
                userInfo: userInfo
            ) else {
                return nil
            }

            guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, machPort, 0) else {
                CFMachPortInvalidate(machPort)
                return nil
            }

            return PointerBoundaryTapHandle(tap: machPort, runLoopSource: source)
        },
        addToMainRunLoop: { handle in
            guard let source = handle.runLoopSource else {
                return true
            }

            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
            return true
        },
        removeFromMainRunLoop: { handle in
            guard let source = handle.runLoopSource else {
                return
            }

            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        },
        enable: { handle, enable in
            guard let tap = handle.tap else {
                return
            }

            CGEvent.tapEnable(tap: tap, enable: enable)
        },
        invalidate: { handle in
            guard let tap = handle.tap else {
                return
            }

            CFMachPortInvalidate(tap)
        }
    )
}

private final class PointerBoundaryTapContextLifetime {
    private var storedUserInfo: UnsafeMutableRawPointer?
    private let releaseUserInfo: (UnsafeMutableRawPointer) -> Void

    init(
        acquireUserInfo: () -> UnsafeMutableRawPointer,
        releaseUserInfo: @escaping (UnsafeMutableRawPointer) -> Void
    ) {
        storedUserInfo = acquireUserInfo()
        self.releaseUserInfo = releaseUserInfo
    }

    var userInfo: UnsafeMutableRawPointer? {
        storedUserInfo
    }

    @discardableResult
    func release() -> Bool {
        guard let userInfo = storedUserInfo else {
            return false
        }

        storedUserInfo = nil
        releaseUserInfo(userInfo)
        return true
    }

    deinit {
        _ = release()
    }
}

private extension CGEventType {
    var isDraggedMouseEvent: Bool {
        self == .leftMouseDragged || self == .rightMouseDragged || self == .otherMouseDragged
    }
}
