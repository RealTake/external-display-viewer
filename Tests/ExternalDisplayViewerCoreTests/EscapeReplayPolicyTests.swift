@testable import ExternalDisplayViewerCore
import XCTest

final class EscapeReplayPolicyTests: XCTestCase {
    func testShortEscapeIsDiscardedWhenOriginalPIDExited() {
        var machine = EscapeHoldStateMachine()

        XCTAssertEqual(machine.keyDown(pid: 100), .startThresholdTimer)
        XCTAssertEqual(machine.keyUp(currentPID: 100, isOriginalPIDRunning: false), .discard)
    }

    func testThresholdReachedIsIdempotentUntilRelease() {
        var machine = EscapeHoldStateMachine()

        _ = machine.keyDown(pid: 100)

        XCTAssertEqual(machine.thresholdReached(), .requestReturn)
        XCTAssertEqual(machine.thresholdReached(), .suppress)
        XCTAssertEqual(machine.keyUp(currentPID: 100, isOriginalPIDRunning: true), .suppress)
    }

    func testStopAfterThresholdReturnRequestDefersTeardownUntilPhysicalReleaseIsSuppressed() {
        var lifecycle = EscapeReturnLifecycle()

        XCTAssertEqual(lifecycle.longEscapeReturnRequested(), .none)
        XCTAssertEqual(lifecycle.stop(), .deferUntilKeyUp)
        XCTAssertEqual(lifecycle.stop(), .none)
        XCTAssertEqual(lifecycle.longEscapeKeyUpSuppressed(), .teardownNow)
        XCTAssertEqual(lifecycle.stop(), .none)
    }

    func testDeferredCleanupReschedulesWhileEscapeIsPhysicallyPressedAndTearsDownAfterRelease() {
        var lifecycle = EscapeReturnLifecycle()

        XCTAssertEqual(lifecycle.longEscapeReturnRequested(), .none)
        XCTAssertEqual(lifecycle.stop(), .deferUntilKeyUp)
        XCTAssertEqual(lifecycle.cleanupFallbackReached(isEscapePressed: true), .rescheduleCleanup)
        XCTAssertEqual(lifecycle.cleanupFallbackReached(isEscapePressed: false), .teardownNow)
        XCTAssertEqual(lifecycle.stop(), .none)
    }

    func testStopOutsideAwaitingLongEscapeReleaseTearsDownImmediatelyAndIdempotently() {
        var lifecycle = EscapeReturnLifecycle()

        XCTAssertEqual(lifecycle.stop(), .teardownNow)
        XCTAssertEqual(lifecycle.stop(), .none)
    }

    func testTapContextLifetimeReleasesAcquiredRetainExactlyOnce() {
        var acquiredCount = 0
        var releasedPointers: [UnsafeMutableRawPointer] = []
        let pointer = UnsafeMutableRawPointer(bitPattern: 0x1)!
        let lifetime = EscapeTapContextLifetime(
            acquireUserInfo: {
                acquiredCount += 1
                return pointer
            },
            releaseUserInfo: { releasedPointers.append($0) }
        )

        XCTAssertEqual(acquiredCount, 1)
        XCTAssertEqual(lifetime.userInfo, pointer)
        XCTAssertTrue(lifetime.release())
        XCTAssertFalse(lifetime.release())
        XCTAssertEqual(releasedPointers, [pointer])
    }

    func testTapContextReleasePlanClearsOwnerStateBeforeFinalRelease() {
        var events: [String] = []
        let pointer = UnsafeMutableRawPointer(bitPattern: 0x2)!
        let lifetime = EscapeTapContextLifetime(
            acquireUserInfo: { pointer },
            releaseUserInfo: { _ in events.append("release") }
        )
        let plan = EscapeTapContextReleasePlan(
            context: lifetime,
            clearOwnerState: { events.append("clear") }
        )

        plan.releaseAfterClearingOwnerState()
        plan.releaseAfterClearingOwnerState()

        XCTAssertEqual(events, ["clear", "release", "clear"])
    }

    @MainActor
    func testThresholdTimerUsesEscapeHoldDurationInCommonRunLoopMode() {
        let scheduledAt = Date()
        var addedTimers: [(fireDate: Date, mode: RunLoop.Mode)] = []
        let scheduler = EscapeHoldTimerScheduler { timer, mode in
            addedTimers.append((timer.fireDate, mode))
        }

        let scheduledTimer = scheduler.schedule(after: InteractionContract.escapeHoldDuration) {}

        XCTAssertEqual(addedTimers.count, 1)
        XCTAssertEqual(addedTimers[0].fireDate.timeIntervalSince(scheduledAt), 0.8, accuracy: 0.05)
        XCTAssertEqual(addedTimers[0].mode, .common)
        scheduledTimer.cancel()
    }
}
