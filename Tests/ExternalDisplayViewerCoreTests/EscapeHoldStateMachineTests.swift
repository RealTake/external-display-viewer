@testable import ExternalDisplayViewerCore
import XCTest

final class EscapeHoldStateMachineTests: XCTestCase {
    func testShortEscapeReplaysOnlyToUnchangedLivePID() {
        var machine = EscapeHoldStateMachine()

        XCTAssertEqual(machine.keyDown(pid: 100), .startThresholdTimer)
        XCTAssertEqual(machine.keyUp(currentPID: 100, isOriginalPIDRunning: true), .replayShortESC(pid: 100))

        XCTAssertEqual(machine.keyDown(pid: 100), .startThresholdTimer)
        XCTAssertEqual(machine.keyUp(currentPID: 200, isOriginalPIDRunning: true), .discard)
    }

    func testThresholdRequestsReturnAndSuppressesRelease() {
        var machine = EscapeHoldStateMachine()

        _ = machine.keyDown(pid: 100)
        XCTAssertEqual(machine.thresholdReached(), .requestReturn)
        XCTAssertEqual(machine.keyUp(currentPID: 100, isOriginalPIDRunning: true), .suppress)
    }

    func testRepeatKeyDownIsMergedIntoActiveHold() {
        var machine = EscapeHoldStateMachine()

        XCTAssertEqual(machine.keyDown(pid: 100), .startThresholdTimer)
        XCTAssertEqual(machine.keyDown(pid: 100), .suppress)
        XCTAssertEqual(machine.keyUp(currentPID: 100, isOriginalPIDRunning: true), .replayShortESC(pid: 100))
    }
}
