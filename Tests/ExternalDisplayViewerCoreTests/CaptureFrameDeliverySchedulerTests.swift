@testable import ExternalDisplayViewerCore
import XCTest

final class CaptureFrameDeliverySchedulerTests: XCTestCase {
    func testRejectsInFlightDeliveryAfterSessionInvalidation() {
        var scheduler = CaptureFrameDeliveryScheduler<Int>()
        let oldGeneration = scheduler.beginSession()

        XCTAssertTrue(scheduler.submit(1, generation: oldGeneration))
        scheduler.endSession()
        let newGeneration = scheduler.beginSession()

        XCTAssertNil(scheduler.takeFrameForDelivery(generation: oldGeneration))
        XCTAssertTrue(scheduler.submit(2, generation: newGeneration))
        XCTAssertEqual(scheduler.takeFrameForDelivery(generation: newGeneration), 2)
    }

    func testDeliversOnlyOneFramePerScheduledTurnAndReschedulesNewestFrame() {
        var scheduler = CaptureFrameDeliveryScheduler<Int>()
        let generation = scheduler.beginSession()

        XCTAssertTrue(scheduler.submit(1, generation: generation))
        XCTAssertFalse(scheduler.submit(2, generation: generation))
        XCTAssertEqual(scheduler.takeFrameForDelivery(generation: generation), 2)
        XCTAssertFalse(scheduler.submit(3, generation: generation))
        XCTAssertTrue(scheduler.completeScheduledTurn(generation: generation))
        XCTAssertEqual(scheduler.takeFrameForDelivery(generation: generation), 3)
        XCTAssertFalse(scheduler.completeScheduledTurn(generation: generation))
    }

    func testInvalidatesPreparedDeliveryBeforeCommit() {
        var scheduler = CaptureFrameDeliveryScheduler<Int>()
        let generation = scheduler.beginSession()

        XCTAssertTrue(scheduler.submit(1, generation: generation))
        let preparedDelivery = scheduler.prepareDelivery(generation: generation)
        scheduler.endSession()

        XCTAssertNil(scheduler.commitPreparedDelivery(preparedDelivery))
    }

    func testStreamIdentityRejectsInactiveStreams() {
        final class StreamToken {}

        let oldStream = StreamToken()
        let activeStream = StreamToken()
        var session = CaptureStreamSession<StreamToken>()

        let oldGeneration = session.begin(stream: oldStream)
        _ = session.begin(stream: activeStream)

        XCTAssertNil(session.accept(stream: oldStream))
        XCTAssertEqual(session.accept(stream: activeStream), oldGeneration + 1)
        session.end(stream: activeStream)
        XCTAssertNil(session.accept(stream: activeStream))
    }
}
