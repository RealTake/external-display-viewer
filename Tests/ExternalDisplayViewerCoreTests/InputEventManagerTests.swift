@testable import ExternalDisplayViewerCore
import CoreGraphics
import XCTest

final class InputEventManagerTests: XCTestCase {
    private let render = CGRect(x: 0, y: 0, width: 100, height: 100)
    private let display = CGRect(x: 1000, y: 0, width: 200, height: 200)

    func testDragWarpsThenPostsDownDraggedAndUp() throws {
        let (manager, poster) = makeManager(currentLocation: CGPoint(x: 500, y: 500))

        let begin = begin(manager)
        let drag = manager.drag(to: CGPoint(x: 120, y: 50), renderRect: render, displayFrame: display)
        let end = manager.end(at: CGPoint(x: 120, y: 50), renderRect: render, displayFrame: display)

        XCTAssertEqual(begin, .transferred(returnPoint: CGPoint(x: 500, y: 500)))
        XCTAssertEqual(drag, .continued)
        XCTAssertEqual(end, .ended)
        XCTAssertEqual(poster.actions.map(\.kind), [.warp, .mouseDown, .mouseDragged, .mouseUp])
        XCTAssertEqual(poster.actions.compactMap(\.button), [.left, .left, .left])
        XCTAssertEqual(poster.actions[0].location, CGPoint(x: 1050, y: 50))
        XCTAssertLessThan(poster.actions[2].location.x, display.maxX)
        XCTAssertEqual(poster.actions[2].location.y, 100)
        XCTAssertEqual(poster.actions[3].location, poster.actions[2].location)
    }

    func testBeginInLetterboxIsIgnoredWithoutPosting() {
        let (manager, poster) = makeManager()
        let render = CGRect(x: 0, y: 100, width: 100, height: 100)
        let display = CGRect(x: 1000, y: 0, width: 200, height: 200)

        let result = manager.begin(
            button: .right,
            clickCount: 1,
            viewerPoint: CGPoint(x: 50, y: 50),
            renderRect: render,
            displayFrame: display
        )

        XCTAssertEqual(result, .ignoredLetterbox)
        XCTAssertTrue(poster.actions.isEmpty)
    }

    func testDragAndEndWithoutActiveSequenceAreIgnored() {
        let (manager, poster) = makeManager()

        XCTAssertEqual(
            manager.drag(to: CGPoint(x: 50, y: 50), renderRect: render, displayFrame: display),
            .ignoredLetterbox
        )
        XCTAssertEqual(
            manager.end(at: CGPoint(x: 50, y: 50), renderRect: render, displayFrame: display),
            .ignoredLetterbox
        )
        XCTAssertTrue(poster.actions.isEmpty)
    }

    func testAllButtonsKeepMatchingButtonThroughCancel() {
        for button in PointerButton.allCases {
            let (manager, poster) = makeManager()

            begin(manager, button: button)
            _ = manager.drag(to: CGPoint(x: 75, y: 75), renderRect: render, displayFrame: display)
            let cancelled = manager.cancelActiveSequence()
            let idempotentCancel = manager.cancelActiveSequence()

            XCTAssertEqual(cancelled, .ended)
            XCTAssertEqual(idempotentCancel, .ignoredLetterbox)
            XCTAssertEqual(
                poster.actions.map(\.kind),
                [.warp, .mouseDown, .mouseDragged, .mouseUp],
                "unexpected action sequence for \(button)"
            )
            XCTAssertEqual(
                poster.actions.compactMap(\.button),
                [button, button, button],
                "unexpected button sequence for \(button)"
            )
            XCTAssertEqual(poster.actions[3].location, CGPoint(x: 1150, y: 150))
        }
    }

    func testDoubleClickStateIsAttachedToDownDraggedAndUp() {
        let (manager, poster) = makeManager()

        begin(manager, clickCount: 2)
        _ = manager.drag(to: CGPoint(x: 75, y: 75), renderRect: render, displayFrame: display)
        _ = manager.end(at: CGPoint(x: 75, y: 75), renderRect: render, displayFrame: display)

        XCTAssertEqual(poster.actions.map(\.clickCount), [nil, 2, 2, 2])
    }

    func testScrollPostsHorizontalAndVerticalPixelDeltasAtMappedPoint() {
        let (manager, poster) = makeManager()

        let result = manager.scroll(
            deltaX: -7,
            deltaY: 13,
            viewerPoint: CGPoint(x: 25, y: 75),
            renderRect: render,
            displayFrame: display
        )

        XCTAssertEqual(result, .continued)
        XCTAssertEqual(poster.actions.map(\.kind), [.scroll])
        XCTAssertEqual(poster.actions[0].location, CGPoint(x: 1050, y: 150))
        XCTAssertEqual(poster.actions[0].deltaX, -7)
        XCTAssertEqual(poster.actions[0].deltaY, 13)
    }

    func testScrollInLetterboxIsIgnoredWithoutPosting() {
        let (manager, poster) = makeManager()
        let render = CGRect(x: 0, y: 100, width: 100, height: 100)
        let display = CGRect(x: 1000, y: 0, width: 200, height: 200)

        let result = manager.scroll(
            deltaX: 1,
            deltaY: 1,
            viewerPoint: CGPoint(x: 50, y: 50),
            renderRect: render,
            displayFrame: display
        )

        XCTAssertEqual(result, .ignoredLetterbox)
        XCTAssertTrue(poster.actions.isEmpty)
    }

    func testDownFailureWarpsBackAndDoesNotOwnActiveSequence() {
        let (manager, poster) = makeManager(currentLocation: CGPoint(x: 500, y: 500))
        poster.failedMouseKinds.insert(.mouseDown)

        let begin = begin(manager)
        let cancel = manager.cancelActiveSequence()

        XCTAssertEqual(begin, .failed(.mouseDown))
        XCTAssertEqual(cancel, .ignoredLetterbox)
        XCTAssertEqual(poster.actions.map(\.kind), [.warp, .mouseDown, .warp])
        XCTAssertEqual(poster.actions[0].location, CGPoint(x: 1050, y: 50))
        XCTAssertEqual(poster.actions[2].location, CGPoint(x: 500, y: 500))
    }

    func testWarpFailureDoesNotPostDownOrOwnActiveSequence() {
        let (manager, poster) = makeManager(currentLocation: CGPoint(x: 500, y: 500))
        poster.shouldFailWarp = true

        let begin = begin(manager)
        let cancel = manager.cancelActiveSequence()

        XCTAssertEqual(begin, .failed(.warp))
        XCTAssertEqual(cancel, .ignoredLetterbox)
        XCTAssertEqual(poster.actions.map(\.kind), [.warp])
        XCTAssertEqual(poster.actions[0].location, CGPoint(x: 1050, y: 50))
    }

    func testMissingCurrentLocationFailsBeforeAnyPointerAction() {
        let (manager, poster) = makeManager(currentLocation: nil)

        let begin = begin(manager)

        XCTAssertEqual(begin, .failed(.currentLocationUnavailable))
        XCTAssertTrue(poster.actions.isEmpty)
    }

    func testGenuineZeroCurrentLocationIsPreservedAsReturnPoint() {
        let (manager, poster) = makeManager(currentLocation: .zero)

        let begin = begin(manager)

        XCTAssertEqual(begin, .transferred(returnPoint: .zero))
        XCTAssertEqual(poster.actions.map(\.kind), [.warp, .mouseDown])
    }

    func testCGEventPosterReportsWarpFailureWithoutMovingCursor() {
        var requestedLocation: CGPoint?
        let poster = CGEventPoster(warpCursor: { location in
            requestedLocation = location
            return .failure
        })
        let location = CGPoint(x: 123, y: 456)

        XCTAssertFalse(poster.warp(to: location))
        XCTAssertEqual(requestedLocation, location)
    }

    func testDragFailureKeepsActiveSequenceForLaterUp() {
        let (manager, poster) = makeManager(currentLocation: CGPoint(x: 500, y: 500))

        begin(manager, button: .middle)
        poster.failedMouseKinds.insert(.mouseDragged)
        let failedDrag = manager.drag(to: CGPoint(x: 75, y: 75), renderRect: render, displayFrame: display)
        poster.failedMouseKinds.remove(.mouseDragged)
        let end = manager.end(at: CGPoint(x: 75, y: 75), renderRect: render, displayFrame: display)

        XCTAssertEqual(failedDrag, .failed(.mouseDragged))
        XCTAssertEqual(end, .ended)
        XCTAssertEqual(poster.actions.map(\.kind), [.warp, .mouseDown, .mouseDragged, .mouseUp])
        XCTAssertEqual(poster.actions.compactMap(\.button), [.middle, .middle, .middle])
        XCTAssertEqual(poster.actions[3].location, CGPoint(x: 1150, y: 150))
    }

    func testUpFailureKeepsActiveSequenceForRetry() {
        let (manager, poster) = makeManager(currentLocation: CGPoint(x: 500, y: 500))

        begin(manager, button: .right)
        poster.failedMouseKinds.insert(.mouseUp)
        let failedEnd = manager.end(at: CGPoint(x: 75, y: 75), renderRect: render, displayFrame: display)
        poster.failedMouseKinds.remove(.mouseUp)
        let retry = manager.cancelActiveSequence()
        let idempotentRetry = manager.cancelActiveSequence()

        XCTAssertEqual(failedEnd, .failed(.mouseUp))
        XCTAssertEqual(retry, .ended)
        XCTAssertEqual(idempotentRetry, .ignoredLetterbox)
        XCTAssertEqual(poster.actions.map(\.kind), [.warp, .mouseDown, .mouseUp, .mouseUp])
        XCTAssertEqual(poster.actions.compactMap(\.button), [.right, .right, .right])
        XCTAssertEqual(poster.actions[2].location, CGPoint(x: 1150, y: 150))
        XCTAssertEqual(poster.actions[3].location, CGPoint(x: 1150, y: 150))
    }

    func testCancelFailureKeepsActiveSequenceForRetry() {
        let (manager, poster) = makeManager(currentLocation: CGPoint(x: 500, y: 500))

        begin(manager, button: .middle)
        poster.failedMouseKinds.insert(.mouseUp)
        let failedCancel = manager.cancelActiveSequence()
        poster.failedMouseKinds.remove(.mouseUp)
        let retry = manager.cancelActiveSequence()
        let idempotentRetry = manager.cancelActiveSequence()

        XCTAssertEqual(failedCancel, .failed(.mouseUp))
        XCTAssertEqual(retry, .ended)
        XCTAssertEqual(idempotentRetry, .ignoredLetterbox)
        XCTAssertEqual(poster.actions.map(\.kind), [.warp, .mouseDown, .mouseUp, .mouseUp])
        XCTAssertEqual(poster.actions.compactMap(\.button), [.middle, .middle, .middle])
        XCTAssertEqual(poster.actions[2].location, CGPoint(x: 1050, y: 50))
        XCTAssertEqual(poster.actions[3].location, CGPoint(x: 1050, y: 50))
    }

    func testScrollFailureReportsFailure() {
        let (manager, poster) = makeManager()
        poster.shouldFailScroll = true

        let result = manager.scroll(
            deltaX: -7,
            deltaY: 13,
            viewerPoint: CGPoint(x: 25, y: 75),
            renderRect: render,
            displayFrame: display
        )

        XCTAssertEqual(result, .failed(.scroll))
        XCTAssertEqual(poster.actions.map(\.kind), [.scroll])
    }

    @discardableResult
    private func begin(_ manager: InputEventManager, button: PointerButton = .left, clickCount: Int = 1) -> InputResult {
        manager.begin(
            button: button,
            clickCount: clickCount,
            viewerPoint: CGPoint(x: 25, y: 25),
            renderRect: render,
            displayFrame: display
        )
    }

    private func makeManager(currentLocation: CGPoint? = CGPoint(x: 10, y: 10)) -> (InputEventManager, PointerPosterSpy) {
        let poster = PointerPosterSpy(currentLocation: currentLocation)
        return (InputEventManager(poster: poster), poster)
    }
}

private final class PointerPosterSpy: PointerEventPosting {
    struct Action: Equatable {
        let kind: PointerEvent.Kind
        let button: PointerButton?
        let location: CGPoint
        let clickCount: Int?
        let deltaX: Int32?
        let deltaY: Int32?
    }

    private(set) var currentLocation: CGPoint?
    private(set) var actions: [Action] = []
    var failedMouseKinds: Set<PointerEvent.Kind> = []
    var shouldFailWarp = false
    var shouldFailScroll = false

    init(currentLocation: CGPoint?) {
        self.currentLocation = currentLocation
    }

    func warp(to location: CGPoint) -> Bool {
        actions.append(Action(kind: .warp, button: nil, location: location, clickCount: nil, deltaX: nil, deltaY: nil))
        guard !shouldFailWarp else {
            return false
        }

        currentLocation = location
        return true
    }

    func postMouse(_ kind: PointerEvent.Kind, button: PointerButton, at location: CGPoint, clickCount: Int) -> Bool {
        actions.append(Action(kind: kind, button: button, location: location, clickCount: clickCount, deltaX: nil, deltaY: nil))
        guard !failedMouseKinds.contains(kind) else {
            return false
        }

        currentLocation = location
        return true
    }

    func postScroll(deltaX: Int32, deltaY: Int32, at location: CGPoint) -> Bool {
        actions.append(Action(kind: .scroll, button: nil, location: location, clickCount: nil, deltaX: deltaX, deltaY: deltaY))
        return !shouldFailScroll
    }
}
