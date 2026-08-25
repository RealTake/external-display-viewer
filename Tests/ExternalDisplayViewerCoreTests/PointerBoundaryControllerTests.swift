@testable import ExternalDisplayViewerCore
import CoreGraphics
import XCTest

@MainActor
final class PointerBoundaryControllerTests: XCTestCase {
    private let displayFrame = CGRect(x: 0, y: 0, width: 1920, height: 1080)

    func testStartIsIdempotentAndInstallsSessionHeadDefaultTapWithFullMouseMask() {
        let lifecycle = TapLifecycleSpy()
        let controller = PointerBoundaryController(poster: PointerPosterSpy(), tapLifecycle: lifecycle.lifecycle)

        XCTAssertTrue(controller.start(displayFrame: displayFrame))
        XCTAssertTrue(controller.start(displayFrame: displayFrame))

        XCTAssertEqual(lifecycle.createCalls.count, 1)
        XCTAssertEqual(lifecycle.createCalls[0].tap, .cgSessionEventTap)
        XCTAssertEqual(lifecycle.createCalls[0].place, .headInsertEventTap)
        XCTAssertEqual(lifecycle.createCalls[0].options, .defaultTap)
        XCTAssertEqual(lifecycle.createCalls[0].mask, expectedMouseMask)
        XCTAssertEqual(lifecycle.enableCalls.map(\.enable), [true])

        controller.stop()
        controller.stop()

        XCTAssertEqual(lifecycle.removeCount, 1)
        XCTAssertEqual(lifecycle.invalidateCount, 1)
    }

    func testMoveExitCallbackFiresOnceAndOrdinaryEventsPassUnretained() throws {
        let lifecycle = TapLifecycleSpy()
        let controller = PointerBoundaryController(poster: PointerPosterSpy(), tapLifecycle: lifecycle.lifecycle)
        var exits: [PointerPortalExit] = []
        controller.onExit = { exits.append($0) }
        XCTAssertTrue(controller.start(displayFrame: displayFrame))

        let first = mouseEvent(.mouseMoved, at: CGPoint(x: 1919, y: 270), delta: CGVector(dx: 4, dy: 0))
        let second = mouseEvent(.mouseMoved, at: CGPoint(x: 1919, y: 270), delta: CGVector(dx: 4, dy: 0))

        let firstResult = try XCTUnwrap(lifecycle.dispatch(.mouseMoved, first)?.takeUnretainedValue())
        let secondResult = try XCTUnwrap(lifecycle.dispatch(.mouseMoved, second)?.takeUnretainedValue())

        XCTAssertTrue(firstResult === first)
        XCTAssertTrue(secondResult === second)
        XCTAssertEqual(exits, [PointerPortalExit(edge: .right, position: 0.25)])
    }

    func testDraggedLocationMutatesOnlyWhenForwardAtDiffers() throws {
        let lifecycle = TapLifecycleSpy()
        let controller = PointerBoundaryController(poster: PointerPosterSpy(), tapLifecycle: lifecycle.lifecycle)
        XCTAssertTrue(controller.start(displayFrame: displayFrame))

        let down = mouseEvent(.leftMouseDown, button: .left, at: CGPoint(x: 1919, y: 270))
        _ = lifecycle.dispatch(.leftMouseDown, down)
        let dragged = mouseEvent(
            .leftMouseDragged,
            button: .left,
            at: CGPoint(x: 1930, y: -10),
            delta: CGVector(dx: 12, dy: -20)
        )
        let moved = mouseEvent(.mouseMoved, at: CGPoint(x: 1930, y: -10), delta: CGVector(dx: 12, dy: -20))

        let draggedResult = try XCTUnwrap(lifecycle.dispatch(.leftMouseDragged, dragged)?.takeUnretainedValue())
        let movedResult = try XCTUnwrap(lifecycle.dispatch(.mouseMoved, moved)?.takeUnretainedValue())

        XCTAssertTrue(draggedResult === dragged)
        XCTAssertEqual(dragged.location, CGPoint(x: 1919, y: 0))
        XCTAssertTrue(movedResult === moved)
        XCTAssertEqual(moved.location, CGPoint(x: 1930, y: -10))
    }

    func testForcedReturnPostsOneUpPerPressedButtonAndDrainsPhysicalUps() throws {
        let lifecycle = TapLifecycleSpy()
        let poster = PointerPosterSpy()
        let controller = PointerBoundaryController(poster: poster, tapLifecycle: lifecycle.lifecycle)
        XCTAssertTrue(controller.start(displayFrame: displayFrame))
        _ = lifecycle.dispatch(.leftMouseDown, mouseEvent(.leftMouseDown, button: .left, at: CGPoint(x: 300, y: 400)))
        _ = lifecycle.dispatch(.rightMouseDown, mouseEvent(.rightMouseDown, button: .right, at: CGPoint(x: 600, y: 700)))

        let result = controller.prepareForReturn()

        XCTAssertEqual(result, .draining)
        XCTAssertEqual(poster.mousePosts, [
            PointerPosterSpy.MousePost(
                kind: .mouseUp,
                button: .left,
                location: CGPoint(x: 600, y: 700),
                clickCount: 1,
                tag: PointerBoundaryController.syntheticForcedMouseUpTag
            ),
            PointerPosterSpy.MousePost(
                kind: .mouseUp,
                button: .right,
                location: CGPoint(x: 600, y: 700),
                clickCount: 1,
                tag: PointerBoundaryController.syntheticForcedMouseUpTag
            )
        ])

        XCTAssertNil(lifecycle.dispatch(.leftMouseUp, mouseEvent(.leftMouseUp, button: .left, at: CGPoint(x: 600, y: 700))))
        let duplicateLeftUp = mouseEvent(.leftMouseUp, button: .left, at: CGPoint(x: 600, y: 700))
        XCTAssertTrue(try XCTUnwrap(lifecycle.dispatch(.leftMouseUp, duplicateLeftUp)?.takeUnretainedValue()) === duplicateLeftUp)
        XCTAssertEqual(lifecycle.invalidateCount, 0)
        XCTAssertNil(lifecycle.dispatch(.rightMouseUp, mouseEvent(.rightMouseUp, button: .right, at: CGPoint(x: 600, y: 700))))
        XCTAssertEqual(lifecycle.invalidateCount, 1)
        XCTAssertEqual(lifecycle.removeCount, 1)
    }

    func testPrepareForReturnWithoutPendingReleasesTearsDownImmediately() {
        let lifecycle = TapLifecycleSpy()
        let controller = PointerBoundaryController(poster: PointerPosterSpy(), tapLifecycle: lifecycle.lifecycle)
        XCTAssertTrue(controller.start(displayFrame: displayFrame))

        XCTAssertEqual(controller.prepareForReturn(), .tornDown)

        XCTAssertEqual(lifecycle.invalidateCount, 1)
        XCTAssertEqual(lifecycle.removeCount, 1)
    }

    func testPartialForcedReturnFailureDoesNotCallTapFailureAndDrainsOnlySuccessfullyPostedButton() throws {
        let lifecycle = TapLifecycleSpy()
        let poster = PointerPosterSpy(failingButtons: [.right])
        let controller = PointerBoundaryController(poster: poster, tapLifecycle: lifecycle.lifecycle)
        var failureCount = 0
        controller.onTapFailure = { failureCount += 1 }
        XCTAssertTrue(controller.start(displayFrame: displayFrame))
        _ = lifecycle.dispatch(.leftMouseDown, mouseEvent(.leftMouseDown, button: .left, at: CGPoint(x: 300, y: 400)))
        _ = lifecycle.dispatch(.rightMouseDown, mouseEvent(.rightMouseDown, button: .right, at: CGPoint(x: 600, y: 700)))

        let result = controller.prepareForReturn()

        XCTAssertEqual(result, .failed)
        XCTAssertEqual(failureCount, 0)
        XCTAssertEqual(poster.mousePosts.map(\.button), [.left, .right])
        let failedButtonUp = mouseEvent(.rightMouseUp, button: .right, at: CGPoint(x: 600, y: 700))
        XCTAssertTrue(try XCTUnwrap(lifecycle.dispatch(.rightMouseUp, failedButtonUp)?.takeUnretainedValue()) === failedButtonUp)
        XCTAssertEqual(lifecycle.invalidateCount, 0)
        XCTAssertNil(lifecycle.dispatch(.leftMouseUp, mouseEvent(.leftMouseUp, button: .left, at: CGPoint(x: 600, y: 700))))
        XCTAssertEqual(lifecycle.invalidateCount, 1)
        XCTAssertEqual(lifecycle.removeCount, 1)
        XCTAssertEqual(failureCount, 0)
    }

    func testPrepareForReturnFailsWithoutTaggedPosterAndTearsDownWithoutPostingUntaggedMouseUp() {
        let lifecycle = TapLifecycleSpy()
        let poster = UntaggedPointerPosterSpy()
        let controller = PointerBoundaryController(poster: poster, tapLifecycle: lifecycle.lifecycle)
        var failureCount = 0
        controller.onTapFailure = { failureCount += 1 }
        XCTAssertTrue(controller.start(displayFrame: displayFrame))
        _ = lifecycle.dispatch(.leftMouseDown, mouseEvent(.leftMouseDown, button: .left, at: CGPoint(x: 300, y: 400)))

        let result = controller.prepareForReturn()

        XCTAssertEqual(result, .failed)
        XCTAssertEqual(failureCount, 0)
        XCTAssertEqual(poster.mousePosts, [])
        XCTAssertEqual(lifecycle.invalidateCount, 1)
    }

    func testSyntheticTaggedMouseUpsAreIgnoredByTapAndDoNotDrainPhysicalRelease() throws {
        let lifecycle = TapLifecycleSpy()
        let poster = PointerPosterSpy()
        let controller = PointerBoundaryController(poster: poster, tapLifecycle: lifecycle.lifecycle)
        XCTAssertTrue(controller.start(displayFrame: displayFrame))
        _ = lifecycle.dispatch(.leftMouseDown, mouseEvent(.leftMouseDown, button: .left, at: CGPoint(x: 300, y: 400)))
        XCTAssertEqual(controller.prepareForReturn(), .draining)

        let taggedUp = mouseEvent(.leftMouseUp, button: .left, at: CGPoint(x: 300, y: 400), tag: PointerBoundaryController.syntheticForcedMouseUpTag)
        let taggedResult = try XCTUnwrap(lifecycle.dispatch(.leftMouseUp, taggedUp)?.takeUnretainedValue())

        XCTAssertTrue(taggedResult === taggedUp)
        XCTAssertEqual(lifecycle.invalidateCount, 0)
        XCTAssertNil(lifecycle.dispatch(.leftMouseUp, mouseEvent(.leftMouseUp, button: .left, at: CGPoint(x: 300, y: 400))))
        XCTAssertEqual(lifecycle.invalidateCount, 1)
    }

    func testFinalSuppressedPhysicalUpTearsDownAndReleasesRetainedContext() {
        let lifecycle = TapLifecycleSpy()
        var controller: PointerBoundaryController? = PointerBoundaryController(
            poster: PointerPosterSpy(),
            tapLifecycle: lifecycle.lifecycle
        )
        let weakController = WeakBox(controller)
        XCTAssertTrue(controller?.start(displayFrame: displayFrame) == true)
        _ = lifecycle.dispatch(.leftMouseDown, mouseEvent(.leftMouseDown, button: .left, at: CGPoint(x: 300, y: 400)))
        XCTAssertEqual(controller?.prepareForReturn(), .draining)

        XCTAssertNil(lifecycle.dispatch(.leftMouseUp, mouseEvent(.leftMouseUp, button: .left, at: CGPoint(x: 300, y: 400))))
        controller = nil

        XCTAssertNil(weakController.value)
        XCTAssertEqual(lifecycle.invalidateCount, 1)
        XCTAssertEqual(lifecycle.removeCount, 1)
    }

    func testTapDisablementReenablesOnceThenReportsFailureAndTearsDown() throws {
        let lifecycle = TapLifecycleSpy()
        let controller = PointerBoundaryController(poster: PointerPosterSpy(), tapLifecycle: lifecycle.lifecycle)
        var failureCount = 0
        controller.onTapFailure = { failureCount += 1 }
        XCTAssertTrue(controller.start(displayFrame: displayFrame))
        let first = mouseEvent(.mouseMoved, at: CGPoint(x: 10, y: 10))
        let second = mouseEvent(.mouseMoved, at: CGPoint(x: 10, y: 10))

        XCTAssertTrue(try XCTUnwrap(lifecycle.dispatch(.tapDisabledByTimeout, first)?.takeUnretainedValue()) === first)
        XCTAssertEqual(lifecycle.enableCalls.map(\.enable), [true, true])
        XCTAssertEqual(failureCount, 0)

        XCTAssertTrue(try XCTUnwrap(lifecycle.dispatch(.tapDisabledByUserInput, second)?.takeUnretainedValue()) === second)
        XCTAssertEqual(failureCount, 1)
        XCTAssertEqual(lifecycle.invalidateCount, 1)
    }

    func testStopReleasesRetainedContextAfterClearingOwnerState() {
        let lifecycle = TapLifecycleSpy()
        var controller: PointerBoundaryController? = PointerBoundaryController(
            poster: PointerPosterSpy(),
            tapLifecycle: lifecycle.lifecycle
        )
        let weakController = WeakBox(controller)

        XCTAssertTrue(controller?.start(displayFrame: displayFrame) == true)
        controller?.stop()
        controller = nil

        XCTAssertNil(weakController.value)
        XCTAssertNil(lifecycle.ownerDuringRemove)
        XCTAssertNil(lifecycle.ownerDuringInvalidate)
    }

    private var expectedMouseMask: CGEventMask {
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

    private func mouseEvent(
        _ type: CGEventType,
        button: CGMouseButton = .left,
        at location: CGPoint,
        delta: CGVector = .zero,
        tag: Int64 = 0
    ) -> CGEvent {
        let event = CGEvent(
            mouseEventSource: nil,
            mouseType: type,
            mouseCursorPosition: location,
            mouseButton: button
        )!
        event.setIntegerValueField(.mouseEventDeltaX, value: Int64(delta.dx))
        event.setIntegerValueField(.mouseEventDeltaY, value: Int64(delta.dy))
        event.setIntegerValueField(.eventSourceUserData, value: tag)
        return event
    }
}

private final class WeakBox<T: AnyObject> {
    weak var value: T?

    init(_ value: T?) {
        self.value = value
    }
}

private final class PointerPosterSpy: TaggedPointerEventPosting {
    struct MousePost: Equatable {
        let kind: PointerEvent.Kind
        let button: PointerButton
        let location: CGPoint
        let clickCount: Int
        let tag: Int64?
    }

    var mousePosts: [MousePost] = []
    var currentLocation: CGPoint?
    private let failingButtons: [PointerButton]

    init(failingButtons: [PointerButton] = []) {
        self.failingButtons = failingButtons
    }

    func warp(to location: CGPoint) -> Bool {
        true
    }

    func postMouse(_ kind: PointerEvent.Kind, button: PointerButton, at location: CGPoint, clickCount: Int) -> Bool {
        mousePosts.append(MousePost(kind: kind, button: button, location: location, clickCount: clickCount, tag: nil))
        return true
    }

    func postMouse(
        _ kind: PointerEvent.Kind,
        button: PointerButton,
        at location: CGPoint,
        clickCount: Int,
        eventSourceUserData: Int64
    ) -> Bool {
        mousePosts.append(MousePost(
            kind: kind,
            button: button,
            location: location,
            clickCount: clickCount,
            tag: eventSourceUserData
        ))
        return !failingButtons.contains(button)
    }

    func postScroll(deltaX: Int32, deltaY: Int32, at location: CGPoint) -> Bool {
        true
    }
}

private final class UntaggedPointerPosterSpy: PointerEventPosting {
    var mousePosts: [PointerEvent.Kind] = []
    var currentLocation: CGPoint?

    func warp(to location: CGPoint) -> Bool {
        true
    }

    func postMouse(_ kind: PointerEvent.Kind, button: PointerButton, at location: CGPoint, clickCount: Int) -> Bool {
        mousePosts.append(kind)
        return true
    }

    func postScroll(deltaX: Int32, deltaY: Int32, at location: CGPoint) -> Bool {
        true
    }
}

@MainActor
private final class TapLifecycleSpy {
    struct CreateCall {
        let tap: CGEventTapLocation
        let place: CGEventTapPlacement
        let options: CGEventTapOptions
        let mask: CGEventMask
    }

    struct EnableCall {
        let enable: Bool
    }

    var createCalls: [CreateCall] = []
    var enableCalls: [EnableCall] = []
    var removeCount = 0
    var invalidateCount = 0
    weak var ownerDuringRemove: PointerBoundaryController?
    weak var ownerDuringInvalidate: PointerBoundaryController?
    private var callback: CGEventTapCallBack?
    private var userInfo: UnsafeMutableRawPointer?
    private let handle = PointerBoundaryTapHandle(tap: nil, runLoopSource: nil)

    var lifecycle: PointerBoundaryTapLifecycle {
        PointerBoundaryTapLifecycle(
            create: { [weak self] tap, place, options, mask, callback, userInfo in
                self?.createCalls.append(CreateCall(tap: tap, place: place, options: options, mask: mask))
                self?.callback = callback
                self?.userInfo = userInfo
                return self?.handle
            },
            addToMainRunLoop: { _ in true },
            removeFromMainRunLoop: { [weak self] _ in
                self?.ownerDuringRemove = self?.userInfo.map {
                    Unmanaged<PointerBoundaryController>.fromOpaque($0).takeUnretainedValue()
                }
                self?.removeCount += 1
            },
            enable: { [weak self] _, enable in
                self?.enableCalls.append(EnableCall(enable: enable))
            },
            invalidate: { [weak self] _ in
                self?.ownerDuringInvalidate = self?.userInfo.map {
                    Unmanaged<PointerBoundaryController>.fromOpaque($0).takeUnretainedValue()
                }
                self?.invalidateCount += 1
            }
        )
    }

    func dispatch(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        callback?(OpaquePointer(bitPattern: 1)!, type, event, userInfo)
    }
}
