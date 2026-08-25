@testable import ExternalDisplayViewerCore
import CoreGraphics
import XCTest

final class CoordinateMapperTests: XCTestCase {
    func testMapsCenterIntoDisplayWithNegativeOrigin() {
        let render = CGRect(x: 0, y: 100, width: 1000, height: 500)
        let display = CGRect(x: -1920, y: 0, width: 1920, height: 1080)

        XCTAssertEqual(
            CoordinateMapper.map(point: CGPoint(x: 500, y: 350), in: render, to: display),
            CGPoint(x: -960, y: 540)
        )
    }

    func testRejectsLetterboxAndClampsActiveDrag() {
        let render = CGRect(x: 0, y: 100, width: 1000, height: 500)
        let display = CGRect(x: 1728, y: -1080, width: 1920, height: 1080)

        XCTAssertNil(CoordinateMapper.map(point: CGPoint(x: 500, y: 50), in: render, to: display))
        let clamped = CoordinateMapper.mapClamped(point: CGPoint(x: 500, y: 50), in: render, to: display)
        XCTAssertEqual(clamped.y, display.minY)
        XCTAssertLessThan(clamped.x, display.maxX)
    }

    func testRenderRectUsesFullContentForSameAspectRatio() {
        let contentSize = CGSize(width: 1920, height: 1080)

        XCTAssertEqual(
            CoordinateMapper.renderRect(contentSize: contentSize, sourceAspectRatio: 16.0 / 9.0),
            CGRect(x: 0, y: 0, width: 1920, height: 1080)
        )
    }

    func testRenderRectAddsHorizontalLetterboxForNarrowSource() {
        let contentSize = CGSize(width: 1200, height: 800)

        XCTAssertEqual(
            CoordinateMapper.renderRect(contentSize: contentSize, sourceAspectRatio: 1.0),
            CGRect(x: 200, y: 0, width: 800, height: 800)
        )
    }

    func testRenderRectAddsVerticalLetterboxForWideSource() {
        let contentSize = CGSize(width: 1200, height: 800)

        XCTAssertEqual(
            CoordinateMapper.renderRect(contentSize: contentSize, sourceAspectRatio: 3.0),
            CGRect(x: 0, y: 200, width: 1200, height: 400)
        )
    }

    func testMapsAllCornersWithoutYInversion() {
        let render = CGRect(x: 10, y: 20, width: 100, height: 50)
        let display = CGRect(x: -1920, y: -1080, width: 1920, height: 1080)

        XCTAssertEqual(CoordinateMapper.map(point: CGPoint(x: 10, y: 20), in: render, to: display), CGPoint(x: -1920, y: -1080))
        XCTAssertEqual(CoordinateMapper.map(point: CGPoint(x: 110, y: 20), in: render, to: display), CGPoint(x: display.maxX.nextDown, y: -1080))
        XCTAssertEqual(CoordinateMapper.map(point: CGPoint(x: 10, y: 70), in: render, to: display), CGPoint(x: -1920, y: display.maxY.nextDown))
        XCTAssertEqual(CoordinateMapper.map(point: CGPoint(x: 110, y: 70), in: render, to: display), CGPoint(x: display.maxX.nextDown, y: display.maxY.nextDown))
    }

    func testMapsDisplaysOnEverySideOfSource() {
        let render = CGRect(x: 0, y: 0, width: 100, height: 100)
        let center = CGPoint(x: 50, y: 50)

        XCTAssertEqual(
            CoordinateMapper.map(point: center, in: render, to: CGRect(x: -1920, y: 0, width: 1920, height: 1080)),
            CGPoint(x: -960, y: 540)
        )
        XCTAssertEqual(
            CoordinateMapper.map(point: center, in: render, to: CGRect(x: 1728, y: 0, width: 1920, height: 1080)),
            CGPoint(x: 2688, y: 540)
        )
        XCTAssertEqual(
            CoordinateMapper.map(point: center, in: render, to: CGRect(x: 0, y: -1080, width: 1920, height: 1080)),
            CGPoint(x: 960, y: -540)
        )
        XCTAssertEqual(
            CoordinateMapper.map(point: center, in: render, to: CGRect(x: 0, y: 1117, width: 1920, height: 1080)),
            CGPoint(x: 960, y: 1657)
        )
    }

    func testClampsActiveDragOutsideEveryEdge() {
        let render = CGRect(x: 100, y: 200, width: 400, height: 300)
        let display = CGRect(x: -1920, y: -1080, width: 1920, height: 1080)

        XCTAssertEqual(
            CoordinateMapper.mapClamped(point: CGPoint(x: 50, y: 350), in: render, to: display),
            CGPoint(x: display.minX, y: -540)
        )
        XCTAssertEqual(
            CoordinateMapper.mapClamped(point: CGPoint(x: 550, y: 350), in: render, to: display),
            CGPoint(x: display.maxX.nextDown, y: -540)
        )
        XCTAssertEqual(
            CoordinateMapper.mapClamped(point: CGPoint(x: 300, y: 150), in: render, to: display),
            CGPoint(x: -960, y: display.minY)
        )
        XCTAssertEqual(
            CoordinateMapper.mapClamped(point: CGPoint(x: 300, y: 550), in: render, to: display),
            CGPoint(x: -960, y: display.maxY.nextDown)
        )
    }
}
