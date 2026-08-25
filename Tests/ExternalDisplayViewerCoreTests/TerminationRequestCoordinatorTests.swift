@testable import ExternalDisplayViewerCore
import XCTest

@MainActor
final class TerminationRequestCoordinatorTests: XCTestCase {
    func testDuplicateRequestCoalescesUntilFirstCleanupReplies() async {
        let coordinator = TerminationRequestCoordinator()
        let cleanupStarted = expectation(description: "cleanup started")
        let replySent = expectation(description: "reply sent")
        var cleanupContinuation: CheckedContinuation<Void, Never>?
        var cleanupCount = 0
        var replyCount = 0

        let firstDecision = coordinator.request(
            hasCoordinator: true,
            cleanup: {
                cleanupCount += 1
                cleanupStarted.fulfill()
                await withCheckedContinuation { continuation in
                    cleanupContinuation = continuation
                }
                return true
            },
            reply: { shouldTerminate in
                XCTAssertTrue(shouldTerminate)
                replyCount += 1
                replySent.fulfill()
            }
        )
        let duplicateDecision = coordinator.request(
            hasCoordinator: true,
            cleanup: {
                XCTFail("duplicate request must not start another cleanup")
                return true
            },
            reply: { _ in
                XCTFail("duplicate request must not reply independently")
            }
        )

        XCTAssertEqual(firstDecision, .terminateLaterStarted)
        XCTAssertEqual(duplicateDecision, .terminateLaterAlreadyInProgress)
        await fulfillment(of: [cleanupStarted], timeout: 1)
        XCTAssertEqual(cleanupCount, 1)
        XCTAssertEqual(replyCount, 0)

        cleanupContinuation?.resume()
        await fulfillment(of: [replySent], timeout: 1)

        XCTAssertEqual(cleanupCount, 1)
        XCTAssertEqual(replyCount, 1)
    }

    func testFailedCleanupRepliesFalseThenAllowsNewSuccessfulRequest() async {
        let coordinator = TerminationRequestCoordinator()
        let firstReplySent = expectation(description: "first reply sent")
        let secondReplySent = expectation(description: "second reply sent")
        var cleanupResults = [false, true]
        var replyValues: [Bool] = []

        let firstDecision = coordinator.request(
            hasCoordinator: true,
            cleanup: {
                cleanupResults.removeFirst()
            },
            reply: { shouldTerminate in
                replyValues.append(shouldTerminate)
                firstReplySent.fulfill()
            }
        )

        XCTAssertEqual(firstDecision, .terminateLaterStarted)
        await fulfillment(of: [firstReplySent], timeout: 1)

        let secondDecision = coordinator.request(
            hasCoordinator: true,
            cleanup: {
                cleanupResults.removeFirst()
            },
            reply: { shouldTerminate in
                replyValues.append(shouldTerminate)
                secondReplySent.fulfill()
            }
        )

        XCTAssertEqual(secondDecision, .terminateLaterStarted)
        await fulfillment(of: [secondReplySent], timeout: 1)
        XCTAssertEqual(replyValues, [false, true])
    }
}
