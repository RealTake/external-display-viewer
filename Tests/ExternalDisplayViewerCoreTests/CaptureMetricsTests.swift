@testable import ExternalDisplayViewerCore
import XCTest

final class CaptureMetricsTests: XCTestCase {
    func testMetricsCountIncompleteFramesWithoutDisplayingThem() {
        var metrics = CaptureMetrics()

        metrics.recordReceived(isComplete: false, at: 0)
        metrics.recordReceived(isComplete: true, at: 1)
        metrics.recordDisplayed(at: 1)

        XCTAssertEqual(metrics.snapshot.incompleteRatio, 0.5, accuracy: 0.001)
        XCTAssertEqual(metrics.snapshot.displayedFrames, 1)
    }

    func testShouldPublishSnapshotUsesOneSecondCadence() {
        var metrics = CaptureMetrics()

        XCTAssertTrue(metrics.shouldPublishSnapshot(at: 0))
        XCTAssertFalse(metrics.shouldPublishSnapshot(at: 0.99))
        XCTAssertTrue(metrics.shouldPublishSnapshot(at: 1.0))
    }

    func testDisplayedFPSUsesRecentDisplayWindow() {
        var metrics = CaptureMetrics()

        metrics.recordReceived(isComplete: false, at: 0)
        metrics.recordReceived(isComplete: true, at: 0.25)
        metrics.recordReceived(isComplete: true, at: 0.5)
        metrics.recordReceived(isComplete: true, at: 1.5)
        metrics.recordReceived(isComplete: true, at: 1.75)

        metrics.recordDisplayed(at: 0)
        metrics.recordDisplayed(at: 0.25)
        metrics.recordDisplayed(at: 0.5)
        metrics.recordDisplayed(at: 1.5)
        metrics.recordDisplayed(at: 1.75)

        let snapshot = metrics.snapshot

        XCTAssertEqual(snapshot.displayedFPS, 4.0, accuracy: 0.001)
        XCTAssertEqual(snapshot.incompleteRatio, 0.2, accuracy: 0.001)
        XCTAssertEqual(snapshot.receivedFrames, 5)
        XCTAssertEqual(snapshot.displayedFrames, 5)
    }

    func testDisplayedFPSFallsToZeroWhenOnlyReceivedFramesAdvancePastRecentDisplayWindow() {
        var metrics = CaptureMetrics()

        metrics.recordReceived(isComplete: false, at: 0)
        metrics.recordReceived(isComplete: true, at: 0.5)
        metrics.recordDisplayed(at: 0)
        metrics.recordDisplayed(at: 0.5)

        metrics.recordReceived(isComplete: true, at: 1.6)

        let snapshot = metrics.snapshot

        XCTAssertEqual(snapshot.displayedFPS, 0, accuracy: 0.001)
        XCTAssertEqual(snapshot.incompleteRatio, 1.0 / 3.0, accuracy: 0.001)
        XCTAssertEqual(snapshot.receivedFrames, 3)
        XCTAssertEqual(snapshot.displayedFrames, 2)
    }
}
