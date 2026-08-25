import AppKit
@preconcurrency import CoreGraphics
import Foundation

enum EscapeReturnTeardownDecision: Equatable, Sendable {
    case none
    case deferUntilKeyUp
    case rescheduleCleanup
    case teardownNow
}

struct EscapeReturnLifecycle: Sendable {
    private var state: State = .running

    mutating func longEscapeReturnRequested() -> EscapeReturnTeardownDecision {
        switch state {
        case .running:
            state = .awaitingLongEscapeRelease(pendingStop: false)
            return .none
        case .awaitingLongEscapeRelease, .stopped:
            return .none
        }
    }

    mutating func stop() -> EscapeReturnTeardownDecision {
        switch state {
        case .running:
            state = .stopped
            return .teardownNow
        case .awaitingLongEscapeRelease(pendingStop: false):
            state = .awaitingLongEscapeRelease(pendingStop: true)
            return .deferUntilKeyUp
        case .awaitingLongEscapeRelease(pendingStop: true):
            return .none
        case .stopped:
            return .none
        }
    }

    mutating func longEscapeKeyUpSuppressed() -> EscapeReturnTeardownDecision {
        switch state {
        case .awaitingLongEscapeRelease(pendingStop: true):
            state = .stopped
            return .teardownNow
        case .awaitingLongEscapeRelease(pendingStop: false):
            state = .running
            return .none
        case .running, .stopped:
            return .none
        }
    }

    mutating func cleanupFallbackReached(isEscapePressed: Bool) -> EscapeReturnTeardownDecision {
        switch state {
        case .awaitingLongEscapeRelease(pendingStop: true):
            guard !isEscapePressed else {
                return .rescheduleCleanup
            }

            state = .stopped
            return .teardownNow
        case .awaitingLongEscapeRelease(pendingStop: false), .running, .stopped:
            return .none
        }
    }
}

private enum State: Sendable {
    case running
    case awaitingLongEscapeRelease(pendingStop: Bool)
    case stopped
}

protocol EscapeScheduledTimer {
    func cancel()
}

final class EscapeTapContextLifetime {
    private var storedUserInfo: UnsafeMutableRawPointer?
    private let releaseUserInfo: (UnsafeMutableRawPointer) -> Void

    init(
        acquireUserInfo: () -> UnsafeMutableRawPointer,
        releaseUserInfo: @escaping (UnsafeMutableRawPointer) -> Void
    ) {
        self.storedUserInfo = acquireUserInfo()
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

struct EscapeTapContextReleasePlan {
    private let context: EscapeTapContextLifetime?
    private let clearOwnerState: () -> Void

    init(context: EscapeTapContextLifetime?, clearOwnerState: @escaping () -> Void) {
        self.context = context
        self.clearOwnerState = clearOwnerState
    }

    func releaseAfterClearingOwnerState() {
        clearOwnerState()
        context?.release()
    }
}

struct EscapeHoldTimerScheduler {
    private let addTimer: @MainActor (Timer, RunLoop.Mode) -> Void

    init(addTimer: @escaping @MainActor (Timer, RunLoop.Mode) -> Void = { timer, mode in
        RunLoop.main.add(timer, forMode: mode)
    }) {
        self.addTimer = addTimer
    }

    @MainActor
    func schedule(after duration: Duration, fire: @escaping @MainActor @Sendable () -> Void) -> EscapeScheduledTimer {
        let timer = Timer(timeInterval: duration.timeInterval, repeats: false) { _ in
            MainActor.assumeIsolated {
                fire()
            }
        }
        addTimer(timer, .common)
        return TimerBackedEscapeScheduledTimer(timer: timer)
    }
}

private struct TimerBackedEscapeScheduledTimer: EscapeScheduledTimer {
    let timer: Timer

    func cancel() {
        timer.invalidate()
    }
}

@MainActor
public final class EscapeReturnController {
    public static let replayEventTag: Int64 = 0x45534348524f4c44

    public var onReturnRequested: @MainActor () -> Void
    public var onTapFailure: @MainActor () -> Void

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var tapContext: EscapeTapContextLifetime?
    private var thresholdTimer: EscapeScheduledTimer?
    private var deferredStopCleanupTimer: EscapeScheduledTimer?
    private let timerScheduler: EscapeHoldTimerScheduler
    private let isEscapeKeyPressed: @MainActor () -> Bool
    private var lifecycle = EscapeReturnLifecycle()
    private var stateMachine = EscapeHoldStateMachine()
    private var firstDownEvent: CGEvent?
    private var releaseEvent: CGEvent?
    private var originalPID: pid_t?
    private var didReenableAfterDisable = false

    public convenience init(
        onReturnRequested: @escaping @MainActor () -> Void = {},
        onTapFailure: @escaping @MainActor () -> Void = {}
    ) {
        self.init(
            timerScheduler: EscapeHoldTimerScheduler(),
            onReturnRequested: onReturnRequested,
            onTapFailure: onTapFailure
        )
    }

    init(
        timerScheduler: EscapeHoldTimerScheduler = EscapeHoldTimerScheduler(),
        isEscapeKeyPressed: @escaping @MainActor () -> Bool = {
            CGEventSource.keyState(.combinedSessionState, key: CGKeyCode(53))
        },
        onReturnRequested: @escaping @MainActor () -> Void = {},
        onTapFailure: @escaping @MainActor () -> Void = {}
    ) {
        self.timerScheduler = timerScheduler
        self.isEscapeKeyPressed = isEscapeKeyPressed
        self.onReturnRequested = onReturnRequested
        self.onTapFailure = onTapFailure
    }

    deinit {}

    public func start() -> Bool {
        guard eventTap == nil else {
            return true
        }

        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue) | CGEventMask(1 << CGEventType.keyUp.rawValue)
        let context = EscapeTapContextLifetime(
            acquireUserInfo: { Unmanaged.passRetained(self).toOpaque() },
            releaseUserInfo: { Unmanaged<EscapeReturnController>.fromOpaque($0).release() }
        )
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: Self.handleEvent,
            userInfo: context.userInfo
        ) else {
            context.release()
            return false
        }

        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            CFMachPortInvalidate(tap)
            context.release()
            return false
        }

        eventTap = tap
        runLoopSource = source
        tapContext = context
        didReenableAfterDisable = false
        lifecycle = EscapeReturnLifecycle()
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    public func stop() {
        handle(teardown: lifecycle.stop())
    }

    private func handle(teardown: EscapeReturnTeardownDecision) {
        switch teardown {
        case .none:
            return
        case .deferUntilKeyUp:
            scheduleDeferredStopCleanup()
        case .rescheduleCleanup:
            scheduleDeferredStopCleanup()
        case .teardownNow:
            performStopTeardown()
        }
    }

    private func performStopTeardown() {
        let thresholdTimer = self.thresholdTimer
        let deferredStopCleanupTimer = self.deferredStopCleanupTimer
        let runLoopSource = self.runLoopSource
        let eventTap = self.eventTap
        let context = self.tapContext

        let releasePlan = EscapeTapContextReleasePlan(context: context) {
            self.thresholdTimer = nil
            self.deferredStopCleanupTimer = nil
            self.clearSavedEvents()
            self.runLoopSource = nil
            self.eventTap = nil
            self.tapContext = nil
        }

        thresholdTimer?.cancel()
        deferredStopCleanupTimer?.cancel()
        stateMachine = EscapeHoldStateMachine()
        didReenableAfterDisable = false

        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }

        if let eventTap {
            CFMachPortInvalidate(eventTap)
        }

        releasePlan.releaseAfterClearingOwnerState()
    }

    private static let handleEvent: CGEventTapCallBack = { _, type, event, userInfo in
        guard let userInfo else {
            return Unmanaged.passUnretained(event)
        }

        let controller = Unmanaged<EscapeReturnController>.fromOpaque(userInfo).takeUnretainedValue()
        // The tap source is installed on CFRunLoop.main, so the callback is synchronously delivered
        // through the main run loop before mutable tap/timer state is touched.
        return MainActor.assumeIsolated {
            return controller.handle(type: type, event: event)
        }
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            handleTapDisablement()
            return Unmanaged.passUnretained(event)
        case .keyDown:
            return handleKeyDown(event)
        case .keyUp:
            return handleKeyUp(event)
        default:
            return Unmanaged.passUnretained(event)
        }
    }

    private func handleKeyDown(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        guard isOriginalEscapeEvent(event) else {
            return Unmanaged.passUnretained(event)
        }

        let pid = frontmostPID()
        switch stateMachine.keyDown(pid: pid) {
        case .startThresholdTimer:
            firstDownEvent = event.copy()
            originalPID = pid
            startThresholdTimer()
            return nil
        case .suppress:
            return nil
        case .replayShortESC, .requestReturn, .discard:
            return nil
        }
    }

    private func handleKeyUp(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        guard isOriginalEscapeEvent(event) else {
            return Unmanaged.passUnretained(event)
        }

        releaseEvent = event.copy()
        thresholdTimer?.cancel()
        thresholdTimer = nil

        let decision = stateMachine.keyUp(
            currentPID: frontmostPID(),
            isOriginalPIDRunning: originalPID.map(isRunning(pid:)) ?? false
        )
        handle(decision: decision)
        if decision == .suppress {
            handle(teardown: lifecycle.longEscapeKeyUpSuppressed())
        }
        return nil
    }

    private func handle(decision: EscapeDecision) {
        switch decision {
        case .startThresholdTimer, .suppress, .discard:
            clearSavedEvents()
        case .requestReturn:
            _ = lifecycle.longEscapeReturnRequested()
            clearSavedEvents()
            onReturnRequested()
        case let .replayShortESC(pid):
            replaySavedEscape(to: pid)
            clearSavedEvents()
        }
    }

    private func startThresholdTimer() {
        thresholdTimer?.cancel()
        thresholdTimer = timerScheduler.schedule(after: InteractionContract.escapeHoldDuration) { [weak self] in
            self?.thresholdTimer = nil
            self?.handle(decision: self?.stateMachine.thresholdReached() ?? .discard)
        }
    }

    private func scheduleDeferredStopCleanup() {
        deferredStopCleanupTimer?.cancel()
        deferredStopCleanupTimer = timerScheduler.schedule(after: .seconds(2)) { [weak self] in
            self?.deferredStopCleanupTimer = nil
            guard let self else {
                return
            }

            handle(teardown: lifecycle.cleanupFallbackReached(isEscapePressed: isEscapeKeyPressed()))
        }
    }

    private func replaySavedEscape(to pid: pid_t) {
        guard let down = taggedCopy(firstDownEvent), let up = taggedCopy(releaseEvent) else {
            return
        }

        down.postToPid(pid)
        up.postToPid(pid)
    }

    private func taggedCopy(_ event: CGEvent?) -> CGEvent? {
        guard let copy = event?.copy() else {
            return nil
        }

        copy.setIntegerValueField(.eventSourceUserData, value: Self.replayEventTag)
        return copy
    }

    private func isOriginalEscapeEvent(_ event: CGEvent) -> Bool {
        event.getIntegerValueField(.keyboardEventKeycode) == 53
            && event.getIntegerValueField(.eventSourceUserData) != Self.replayEventTag
    }

    private func frontmostPID() -> pid_t {
        NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0
    }

    private func isRunning(pid: pid_t) -> Bool {
        NSRunningApplication(processIdentifier: pid) != nil
    }

    private func handleTapDisablement() {
        guard let eventTap else {
            onTapFailure()
            return
        }

        guard !didReenableAfterDisable else {
            onTapFailure()
            stop()
            return
        }

        didReenableAfterDisable = true
        CGEvent.tapEnable(tap: eventTap, enable: true)
    }

    private func clearSavedEvents() {
        firstDownEvent = nil
        releaseEvent = nil
        originalPID = nil
    }
}

private extension Duration {
    var timeInterval: TimeInterval {
        let parts = components
        return TimeInterval(parts.seconds) + TimeInterval(parts.attoseconds) / 1_000_000_000_000_000_000
    }
}
