@testable import ExternalDisplayViewerCore
import CoreGraphics
import XCTest

final class PointerBoundaryStateTests: XCTestCase {
    private let displayFrame = CGRect(x: 0, y: 0, width: 1920, height: 1080)

    func testMoveRequestsReturnForAllEdgesAtLastValidPixels() {
        let cases: [(name: String, event: PointerBoundaryEvent, expected: PointerBoundaryAction)] = [
            (
                "left",
                .move(location: CGPoint(x: 0, y: 270), delta: CGVector(dx: -4, dy: 0)),
                .requestReturn(PointerPortalExit(edge: .left, position: 0.25))
            ),
            (
                "right",
                .move(location: CGPoint(x: 1919, y: 270), delta: CGVector(dx: 4, dy: 0)),
                .requestReturn(PointerPortalExit(edge: .right, position: 0.25))
            ),
            (
                "top",
                .move(location: CGPoint(x: 480, y: 0), delta: CGVector(dx: 0, dy: -4)),
                .requestReturn(PointerPortalExit(edge: .top, position: 0.25))
            ),
            (
                "bottom",
                .move(location: CGPoint(x: 480, y: 1079), delta: CGVector(dx: 0, dy: 4)),
                .requestReturn(PointerPortalExit(edge: .bottom, position: 0.25))
            )
        ]

        for testCase in cases {
            // Given
            var state = PointerBoundaryState(displayFrame: displayFrame)

            // When
            let action = state.consume(testCase.event)

            // Then
            XCTAssertEqual(action, testCase.expected, testCase.name)
        }
    }

    func testMoveIgnoresInwardAndParallelDeltasAtBoundary() {
        let cases: [(name: String, event: PointerBoundaryEvent)] = [
            ("left inward", .move(location: CGPoint(x: 0, y: 540), delta: CGVector(dx: 4, dy: 0))),
            ("left parallel", .move(location: CGPoint(x: 0, y: 540), delta: CGVector(dx: 0, dy: 4))),
            ("right inward", .move(location: CGPoint(x: 1919, y: 540), delta: CGVector(dx: -4, dy: 0))),
            ("top inward", .move(location: CGPoint(x: 960, y: 0), delta: CGVector(dx: 0, dy: 4))),
            ("bottom inward", .move(location: CGPoint(x: 960, y: 1079), delta: CGVector(dx: 0, dy: -4)))
        ]

        for testCase in cases {
            // Given
            var state = PointerBoundaryState(displayFrame: displayFrame)

            // When
            let action = state.consume(testCase.event)

            // Then
            XCTAssertEqual(action, .forward, testCase.name)
        }
    }

    func testMoveUsesDominantAxisAtCornerAndFreshTieDefaultsHorizontal() {
        // Given
        var verticalState = PointerBoundaryState(displayFrame: displayFrame)
        var tiedState = PointerBoundaryState(displayFrame: displayFrame)

        // When
        let verticalAction = verticalState.consume(
            .move(location: CGPoint(x: 1919, y: 1079), delta: CGVector(dx: 3, dy: 9))
        )
        let tiedAction = tiedState.consume(
            .move(location: CGPoint(x: 1919, y: 1079), delta: CGVector(dx: 9, dy: 9))
        )

        // Then
        XCTAssertEqual(verticalAction, .requestReturn(PointerPortalExit(edge: .bottom, position: 1919 / 1920)))
        XCTAssertEqual(tiedAction, .requestReturn(PointerPortalExit(edge: .right, position: 1079 / 1080)))
    }

    func testEqualCornerOutwardDeltaReusesPriorDecisiveAxis() {
        // Given
        var verticalState = PointerBoundaryState(displayFrame: displayFrame)
        _ = verticalState.consume(.move(location: CGPoint(x: 960, y: 100), delta: CGVector(dx: 10, dy: 20)))
        var horizontalState = PointerBoundaryState(displayFrame: displayFrame)
        _ = horizontalState.consume(.move(location: CGPoint(x: 960, y: 100), delta: CGVector(dx: 20, dy: 10)))

        // When
        let verticalTie = verticalState.consume(
            .move(location: CGPoint(x: 1919, y: 1079), delta: CGVector(dx: 9, dy: 9))
        )
        let horizontalTie = horizontalState.consume(
            .move(location: CGPoint(x: 1919, y: 1079), delta: CGVector(dx: 9, dy: 9))
        )

        // Then
        XCTAssertEqual(verticalTie, .requestReturn(PointerPortalExit(edge: .bottom, position: 1919 / 1920)))
        XCTAssertEqual(horizontalTie, .requestReturn(PointerPortalExit(edge: .right, position: 1079 / 1080)))
    }

    func testOutsideMoveRequestsFirstCrossedEdgeBeforeUpdatingLastValidPoint() {
        let cases: [(name: String, previous: CGPoint, current: CGPoint, delta: CGVector, expected: PointerPortalExit)] = [
            (
                "right before bottom",
                CGPoint(x: 1910, y: 1000),
                CGPoint(x: 1930, y: 1090),
                CGVector(dx: 20, dy: 90),
                PointerPortalExit(edge: .right, position: 1040.5 / 1080)
            ),
            (
                "bottom before right",
                CGPoint(x: 1800, y: 1070),
                CGPoint(x: 1940, y: 1090),
                CGVector(dx: 140, dy: 20),
                PointerPortalExit(edge: .bottom, position: 1863 / 1920)
            ),
            (
                "negative origin left before top",
                CGPoint(x: -1910, y: -1040),
                CGPoint(x: -1930, y: -1100),
                CGVector(dx: -20, dy: -60),
                PointerPortalExit(edge: .left, position: 10 / 1080)
            )
        ]

        for testCase in cases {
            // Given
            var state = PointerBoundaryState(displayFrame: testCase.name == "negative origin left before top"
                ? CGRect(x: -1920, y: -1080, width: 1920, height: 1080)
                : displayFrame)
            _ = state.consume(.move(location: testCase.previous, delta: CGVector(dx: 1, dy: 1)))

            // When
            let action = state.consume(.move(location: testCase.current, delta: testCase.delta))

            // Then
            XCTAssertEqual(action, .requestReturn(testCase.expected), testCase.name)
        }
    }

    func testMoveRequestsOnlyOneExitForStateLifetime() {
        // Given
        var state = PointerBoundaryState(displayFrame: displayFrame)

        // When
        let first = state.consume(.move(location: CGPoint(x: 1919, y: 270), delta: CGVector(dx: 4, dy: 0)))
        let second = state.consume(.move(location: CGPoint(x: 1919, y: 270), delta: CGVector(dx: 4, dy: 0)))
        _ = state.consume(.down(button: .left, location: CGPoint(x: 1919, y: 270)))
        _ = state.consume(.up(button: .left, location: CGPoint(x: 1919, y: 270)))
        _ = state.beginForcedReturn()
        _ = state.consumeRelease(.left)
        let afterRelease = state.consume(.move(location: CGPoint(x: 1919, y: 270), delta: CGVector(dx: 4, dy: 0)))
        var freshState = PointerBoundaryState(displayFrame: displayFrame)
        let fresh = freshState.consume(.move(location: CGPoint(x: 1919, y: 270), delta: CGVector(dx: 4, dy: 0)))

        // Then
        XCTAssertEqual(first, .requestReturn(PointerPortalExit(edge: .right, position: 0.25)))
        XCTAssertEqual(second, .forward)
        XCTAssertEqual(afterRelease, .forward)
        XCTAssertEqual(fresh, .requestReturn(PointerPortalExit(edge: .right, position: 0.25)))
    }

    func testDirectDownAndUpTrackPressedButtons() {
        // Given
        var state = PointerBoundaryState(displayFrame: displayFrame)

        // When
        let down = state.consume(.down(button: .right, location: CGPoint(x: 400, y: 500)))
        let up = state.consume(.up(button: .right, location: CGPoint(x: 410, y: 510)))
        let forcedAfterDirectUp = state.beginForcedReturn()
        _ = state.consume(.down(button: .right, location: CGPoint(x: 400, y: 500)))
        let forcedWhilePressed = state.beginForcedReturn()
        let physicalUp = state.consumeRelease(.right)
        let forcedAfterRelease = state.beginForcedReturn()

        // Then
        XCTAssertEqual(down, .forward)
        XCTAssertEqual(up, .forward)
        XCTAssertEqual(forcedAfterDirectUp, [])
        XCTAssertEqual(forcedWhilePressed, [
            PointerBoundaryForcedRelease(button: .right, location: CGPoint(x: 400, y: 500))
        ])
        XCTAssertEqual(physicalUp, .suppress)
        XCTAssertEqual(forcedAfterRelease, [])
    }

    func testDraggedClampsForwardLocationWithoutRequestingReturn() {
        // Given
        var state = PointerBoundaryState(displayFrame: displayFrame)
        _ = state.consume(.down(button: .left, location: CGPoint(x: 1919, y: 270)))

        // When
        let action = state.consume(
            .dragged(button: .left, location: CGPoint(x: 1930, y: -10), delta: CGVector(dx: 12, dy: -20))
        )
        let releases = state.beginForcedReturn()

        // Then
        XCTAssertEqual(action, .forwardAt(CGPoint(x: 1919, y: 0)))
        XCTAssertEqual(releases, [
            PointerBoundaryForcedRelease(button: .left, location: CGPoint(x: 1919, y: 0))
        ])
    }

    func testDraggedFirstTracksButtonForForcedSafetyRelease() {
        // Given
        var state = PointerBoundaryState(displayFrame: displayFrame)

        // When
        let action = state.consume(
            .dragged(button: .middle, location: CGPoint(x: 1930, y: 270), delta: CGVector(dx: 11, dy: 0))
        )
        let releases = state.beginForcedReturn()

        // Then
        XCTAssertEqual(action, .forwardAt(CGPoint(x: 1919, y: 270)))
        XCTAssertEqual(releases, [
            PointerBoundaryForcedRelease(button: .middle, location: CGPoint(x: 1919, y: 270))
        ])
    }

    func testReleaseThenNextOutwardMoveCanRequestReturn() {
        // Given
        var state = PointerBoundaryState(displayFrame: displayFrame)
        _ = state.consume(.down(button: .left, location: CGPoint(x: 1919, y: 270)))
        _ = state.consume(
            .dragged(button: .left, location: CGPoint(x: 1930, y: 270), delta: CGVector(dx: 11, dy: 0))
        )

        // When
        let up = state.consume(.up(button: .left, location: CGPoint(x: 1930, y: 270)))
        let move = state.consume(.move(location: CGPoint(x: 1919, y: 270), delta: CGVector(dx: 4, dy: 0)))

        // Then
        XCTAssertEqual(up, .forwardAt(CGPoint(x: 1919, y: 270)))
        XCTAssertEqual(move, .requestReturn(PointerPortalExit(edge: .right, position: 0.25)))
    }

    func testBeginForcedReturnEmitsPressedButtonsOnceAtLastValidPoint() {
        // Given
        var state = PointerBoundaryState(displayFrame: displayFrame)
        _ = state.consume(.move(location: CGPoint(x: 120, y: 200), delta: CGVector(dx: 20, dy: 0)))
        _ = state.consume(.down(button: .left, location: CGPoint(x: 300, y: 400)))
        _ = state.consume(.down(button: .middle, location: CGPoint(x: 600, y: 700)))

        // When
        let first = state.beginForcedReturn()
        let second = state.beginForcedReturn()

        // Then
        XCTAssertEqual(first, [
            PointerBoundaryForcedRelease(button: .left, location: CGPoint(x: 600, y: 700)),
            PointerBoundaryForcedRelease(button: .middle, location: CGPoint(x: 600, y: 700))
        ])
        XCTAssertEqual(second, [])
    }

    func testConsumeReleaseSuppressesPendingPhysicalUpsAndTearsDownSemantics() {
        // Given
        var state = PointerBoundaryState(displayFrame: displayFrame)
        _ = state.consume(.down(button: .left, location: CGPoint(x: 100, y: 100)))
        _ = state.consume(.down(button: .right, location: CGPoint(x: 200, y: 200)))
        _ = state.beginForcedReturn()

        // When
        let leftRelease = state.consumeRelease(.left)
        let duplicateLeftRelease = state.consumeRelease(.left)
        let rightRelease = state.consumeRelease(.right)
        let forcedAfterTeardown = state.beginForcedReturn()

        // Then
        XCTAssertEqual(leftRelease, .suppress)
        XCTAssertEqual(duplicateLeftRelease, .forward)
        XCTAssertEqual(rightRelease, .suppress)
        XCTAssertEqual(forcedAfterTeardown, [])
    }

    func testInvalidDisplayFramesSafelyForwardAndEmitNoForcedReleases() {
        let cases: [(name: String, frame: CGRect)] = [
            ("zero width", CGRect(x: 0, y: 0, width: 0, height: 1080)),
            ("negative width", CGRect(x: 0, y: 0, width: -10, height: 1080)),
            ("infinite origin", CGRect(x: CGFloat.infinity, y: 0, width: 1920, height: 1080)),
            ("nan height", CGRect(x: 0, y: 0, width: 1920, height: CGFloat.nan))
        ]

        for testCase in cases {
            // Given
            var state = PointerBoundaryState(displayFrame: testCase.frame)

            // When
            let move = state.consume(.move(location: CGPoint(x: 0, y: 0), delta: CGVector(dx: -4, dy: -4)))
            let down = state.consume(.down(button: .left, location: CGPoint(x: 10, y: 10)))
            let dragged = state.consume(
                .dragged(button: .left, location: CGPoint(x: 20, y: 20), delta: CGVector(dx: 10, dy: 10))
            )
            let releases = state.beginForcedReturn()

            // Then
            XCTAssertEqual(move, .forward, testCase.name)
            XCTAssertEqual(down, .forward, testCase.name)
            XCTAssertEqual(dragged, .forward, testCase.name)
            XCTAssertEqual(releases, [], testCase.name)
        }
    }

    func testNonFiniteEventsPreserveLastFinitePointAndTrackButtonsSafely() {
        // Given
        var state = PointerBoundaryState(displayFrame: displayFrame)
        _ = state.consume(.move(location: CGPoint(x: 400, y: 500), delta: CGVector(dx: 10, dy: 0)))

        // When
        let invalidMovePoint = state.consume(
            .move(location: CGPoint(x: CGFloat.nan, y: 500), delta: CGVector(dx: 10, dy: 0))
        )
        let invalidMoveDelta = state.consume(
            .move(location: CGPoint(x: 600, y: 700), delta: CGVector(dx: CGFloat.infinity, dy: 0))
        )
        let invalidDown = state.consume(.down(button: .left, location: CGPoint(x: CGFloat.infinity, y: 200)))
        let invalidDragPoint = state.consume(
            .dragged(button: .right, location: CGPoint(x: 100, y: CGFloat.nan), delta: CGVector(dx: 10, dy: 0))
        )
        let invalidDragDelta = state.consume(
            .dragged(button: .middle, location: CGPoint(x: 800, y: 900), delta: CGVector(dx: 0, dy: CGFloat.nan))
        )
        let invalidUp = state.consume(.up(button: .right, location: CGPoint(x: 100, y: CGFloat.infinity)))
        let releases = state.beginForcedReturn()

        // Then
        XCTAssertEqual(invalidMovePoint, .forward)
        XCTAssertEqual(invalidMoveDelta, .forward)
        XCTAssertEqual(invalidDown, .forward)
        XCTAssertEqual(invalidDragPoint, .forward)
        XCTAssertEqual(invalidDragDelta, .forward)
        XCTAssertEqual(invalidUp, .forward)
        XCTAssertEqual(releases, [
            PointerBoundaryForcedRelease(button: .left, location: CGPoint(x: 400, y: 500)),
            PointerBoundaryForcedRelease(button: .middle, location: CGPoint(x: 400, y: 500))
        ])
        XCTAssertTrue(releases.allSatisfy { $0.location.x.isFinite && $0.location.y.isFinite })
    }
}
