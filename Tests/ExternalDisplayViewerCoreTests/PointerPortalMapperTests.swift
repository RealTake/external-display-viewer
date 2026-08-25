@testable import ExternalDisplayViewerCore
import CoreGraphics
import XCTest

final class PointerPortalMapperTests: XCTestCase {
    func testEntryMapsViewerPointToMatchingExternalPoint() {
        // Given
        let request = PointerPortalEntry(
            viewerPoint: CGPoint(x: 250, y: 125),
            renderRect: CGRect(x: 0, y: 0, width: 1000, height: 500),
            displayFrame: CGRect(x: -1920, y: 0, width: 1920, height: 1080)
        )

        // When
        let point = PointerPortalMapper.externalPoint(for: request)

        // Then
        XCTAssertEqual(point, CGPoint(x: -1440, y: 270))
    }

    func testEntryRejectsViewerPointInLetterbox() {
        // Given
        let request = PointerPortalEntry(
            viewerPoint: CGPoint(x: 200, y: 40),
            renderRect: CGRect(x: 0, y: 100, width: 1000, height: 500),
            displayFrame: CGRect(x: 1728, y: -1080, width: 1920, height: 1080)
        )

        // When
        let point = PointerPortalMapper.externalPoint(for: request)

        // Then
        XCTAssertNil(point)
    }

    func testExitDetectsAllEdgesAndRatiosWithNegativeOrigin() {
        let cases: [(name: String, point: CGPoint, delta: CGVector, expected: PointerPortalExit)] = [
            (
                "left start",
                CGPoint(x: -1920, y: -1080),
                CGVector(dx: -1, dy: 0),
                PointerPortalExit(edge: .left, position: 0)
            ),
            (
                "left middle",
                CGPoint(x: -1920, y: -540),
                CGVector(dx: -1, dy: 0),
                PointerPortalExit(edge: .left, position: 0.5)
            ),
            (
                "left end",
                CGPoint(x: -1920, y: 0),
                CGVector(dx: -1, dy: 0),
                PointerPortalExit(edge: .left, position: 1)
            ),
            (
                "right start",
                CGPoint(x: 0, y: -1080),
                CGVector(dx: 1, dy: 0),
                PointerPortalExit(edge: .right, position: 0)
            ),
            (
                "right middle",
                CGPoint(x: 0, y: -540),
                CGVector(dx: 1, dy: 0),
                PointerPortalExit(edge: .right, position: 0.5)
            ),
            (
                "right end",
                CGPoint(x: 0, y: 0),
                CGVector(dx: 1, dy: 0),
                PointerPortalExit(edge: .right, position: 1)
            ),
            (
                "top start",
                CGPoint(x: -1920, y: -1080),
                CGVector(dx: 0, dy: -1),
                PointerPortalExit(edge: .top, position: 0)
            ),
            (
                "top middle",
                CGPoint(x: -960, y: -1080),
                CGVector(dx: 0, dy: -1),
                PointerPortalExit(edge: .top, position: 0.5)
            ),
            (
                "top end",
                CGPoint(x: 0, y: -1080),
                CGVector(dx: 0, dy: -1),
                PointerPortalExit(edge: .top, position: 1)
            ),
            (
                "bottom start",
                CGPoint(x: -1920, y: 0),
                CGVector(dx: 0, dy: 1),
                PointerPortalExit(edge: .bottom, position: 0)
            ),
            (
                "bottom middle",
                CGPoint(x: -960, y: 0),
                CGVector(dx: 0, dy: 1),
                PointerPortalExit(edge: .bottom, position: 0.5)
            ),
            (
                "bottom end",
                CGPoint(x: 0, y: 0),
                CGVector(dx: 0, dy: 1),
                PointerPortalExit(edge: .bottom, position: 1)
            )
        ]
        let displayFrame = CGRect(x: -1920, y: -1080, width: 1920, height: 1080)

        for testCase in cases {
            // Given
            let point = testCase.point
            let delta = testCase.delta

            // When
            let exit = PointerPortalMapper.exit(at: point, delta: delta, in: displayFrame)

            // Then
            XCTAssertEqual(exit, testCase.expected, testCase.name)
        }
    }

    func testExitUsesDominantAxisAtCorner() {
        // Given
        let displayFrame = CGRect(x: -1920, y: -1080, width: 1920, height: 1080)
        let corner = CGPoint(x: 0, y: 0)

        // When
        let exit = PointerPortalMapper.exit(at: corner, delta: CGVector(dx: 3, dy: 9), in: displayFrame)

        // Then
        XCTAssertEqual(exit, PointerPortalExit(edge: .bottom, position: 1))
    }

    func testExitReturnsNilWhenPointIsInsideAndDeltaDoesNotLeaveDisplay() {
        // Given
        let displayFrame = CGRect(x: -1920, y: -1080, width: 1920, height: 1080)

        // When
        let exit = PointerPortalMapper.exit(
            at: CGPoint(x: -960, y: -540),
            delta: CGVector(dx: 10, dy: 10),
            in: displayFrame
        )

        // Then
        XCTAssertNil(exit)
    }

    func testExitDetectsOutwardMovementWithinBoundaryTolerance() {
        let displayFrame = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let cases: [(name: String, point: CGPoint, delta: CGVector, expected: PointerPortalExit)] = [
            (
                "left",
                CGPoint(x: 1, y: 540),
                CGVector(dx: -2, dy: 0),
                PointerPortalExit(edge: .left, position: 0.5)
            ),
            (
                "right",
                CGPoint(x: 1919, y: 540),
                CGVector(dx: 2, dy: 0),
                PointerPortalExit(edge: .right, position: 0.5)
            ),
            (
                "top",
                CGPoint(x: 960, y: 1),
                CGVector(dx: 0, dy: -2),
                PointerPortalExit(edge: .top, position: 0.5)
            ),
            (
                "bottom",
                CGPoint(x: 960, y: 1079),
                CGVector(dx: 0, dy: 2),
                PointerPortalExit(edge: .bottom, position: 0.5)
            )
        ]

        for testCase in cases {
            // Given
            let point = testCase.point
            let delta = testCase.delta

            // When
            let exit = PointerPortalMapper.exit(at: point, delta: delta, in: displayFrame)

            // Then
            XCTAssertEqual(exit, testCase.expected, testCase.name)
        }
    }

    func testBottomExitReturnsToSameHorizontalRatioBelowCapture() {
        // Given
        let viewer = PointerPortalViewerGeometry(
            captureFrame: CGRect(x: 100, y: 100, width: 800, height: 450),
            surfaceFrame: CGRect(x: 100, y: 100, width: 800, height: 500),
            contentFrame: CGRect(x: 100, y: 100, width: 800, height: 620)
        )

        // When
        let point = PointerPortalMapper.returnPoint(
            for: PointerPortalExit(edge: .bottom, position: 0.25),
            viewer: viewer,
            safetyInset: 2
        )

        // Then
        XCTAssertEqual(point, CGPoint(x: 300, y: 552))
    }

    func testReturnUsesMatchingLetterboxStripForEveryEdge() {
        let viewer = PointerPortalViewerGeometry(
            captureFrame: CGRect(x: 100, y: 150, width: 800, height: 450),
            surfaceFrame: CGRect(x: 50, y: 100, width: 900, height: 550),
            contentFrame: CGRect(x: 50, y: 100, width: 900, height: 700)
        )
        let cases: [(name: String, exit: PointerPortalExit, expected: CGPoint)] = [
            ("left", PointerPortalExit(edge: .left, position: 0), CGPoint(x: 98, y: 150)),
            ("right", PointerPortalExit(edge: .right, position: 0.5), CGPoint(x: 902, y: 375)),
            ("top", PointerPortalExit(edge: .top, position: 1), CGPoint(x: 900, y: 148)),
            ("bottom", PointerPortalExit(edge: .bottom, position: 0.5), CGPoint(x: 500, y: 602))
        ]

        for testCase in cases {
            // Given
            let exit = testCase.exit

            // When
            let point = PointerPortalMapper.returnPoint(for: exit, viewer: viewer, safetyInset: 2)

            // Then
            XCTAssertEqual(point, testCase.expected, testCase.name)
        }
    }

    func testReturnClampsRatioIntoLandingRegion() {
        // Given
        let viewer = PointerPortalViewerGeometry(
            captureFrame: CGRect(x: -800, y: -400, width: 600, height: 300),
            surfaceFrame: CGRect(x: -900, y: -500, width: 800, height: 500),
            contentFrame: CGRect(x: -900, y: -500, width: 800, height: 620)
        )

        // When
        let point = PointerPortalMapper.returnPoint(
            for: PointerPortalExit(edge: .top, position: 1.5),
            viewer: viewer,
            safetyInset: 2
        )

        // Then
        XCTAssertEqual(point, CGPoint(x: -200, y: -402))
    }

    func testReturnFallsBackToFooterWhenMatchingStripIsAbsent() {
        // Given
        let viewer = PointerPortalViewerGeometry(
            captureFrame: CGRect(x: 100, y: 100, width: 800, height: 500),
            surfaceFrame: CGRect(x: 100, y: 100, width: 800, height: 500),
            contentFrame: CGRect(x: 100, y: 100, width: 800, height: 620)
        )

        // When
        let point = PointerPortalMapper.returnPoint(
            for: PointerPortalExit(edge: .left, position: 0.5),
            viewer: viewer,
            safetyInset: 2
        )

        // Then
        XCTAssertEqual(point, CGPoint(x: 102, y: 660))
    }

    func testLeftAndRightFooterFallbackPreservesVerticalExitRatio() {
        let viewer = PointerPortalViewerGeometry(
            captureFrame: CGRect(x: 100, y: 100, width: 800, height: 500),
            surfaceFrame: CGRect(x: 100, y: 100, width: 800, height: 500),
            contentFrame: CGRect(x: 100, y: 100, width: 800, height: 620)
        )
        let cases: [(name: String, exit: PointerPortalExit, expected: CGPoint)] = [
            ("left start", PointerPortalExit(edge: .left, position: 0), CGPoint(x: 102, y: 600)),
            ("left middle", PointerPortalExit(edge: .left, position: 0.5), CGPoint(x: 102, y: 660)),
            ("left end", PointerPortalExit(edge: .left, position: 1), CGPoint(x: 102, y: 720)),
            ("right start", PointerPortalExit(edge: .right, position: 0), CGPoint(x: 898, y: 600)),
            ("right middle", PointerPortalExit(edge: .right, position: 0.5), CGPoint(x: 898, y: 660)),
            ("right end", PointerPortalExit(edge: .right, position: 1), CGPoint(x: 898, y: 720))
        ]

        for testCase in cases {
            // Given
            let exit = testCase.exit

            // When
            let point = PointerPortalMapper.returnPoint(for: exit, viewer: viewer, safetyInset: 2)

            // Then
            XCTAssertEqual(point, testCase.expected, testCase.name)
        }
    }

    func testReturnReturnsNilWhenNoLandingRegionExists() {
        // Given
        let viewer = PointerPortalViewerGeometry(
            captureFrame: CGRect(x: 100, y: 100, width: 800, height: 500),
            surfaceFrame: CGRect(x: 100, y: 100, width: 800, height: 500),
            contentFrame: CGRect(x: 100, y: 100, width: 800, height: 500)
        )

        // When
        let point = PointerPortalMapper.returnPoint(
            for: PointerPortalExit(edge: .bottom, position: 0.5),
            viewer: viewer,
            safetyInset: 2
        )

        // Then
        XCTAssertNil(point)
    }
}
