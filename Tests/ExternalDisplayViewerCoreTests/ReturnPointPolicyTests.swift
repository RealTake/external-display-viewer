@testable import ExternalDisplayViewerCore
import XCTest

final class ReturnPointPolicyTests: XCTestCase {
    func testValidSavedPointInsideViewerCaptureFrameIsReturned() {
        let captureFrame = CGRect(x: -800, y: 200, width: 600, height: 400)
        let savedPoint = CGPoint(x: -500, y: 350)

        XCTAssertEqual(
            ReturnPointPolicy.resolve(savedGlobalPoint: savedPoint, viewerCaptureGlobalFrame: captureFrame),
            savedPoint
        )
    }

    func testNilSavedPointFallsBackToViewerCaptureCenter() {
        let captureFrame = CGRect(x: 100, y: 200, width: 600, height: 400)

        XCTAssertEqual(
            ReturnPointPolicy.resolve(savedGlobalPoint: nil, viewerCaptureGlobalFrame: captureFrame),
            CGPoint(x: 400, y: 400)
        )
    }

    func testOutsideSavedPointFallsBackToViewerCaptureCenter() {
        let captureFrame = CGRect(x: 100, y: 200, width: 600, height: 400)

        XCTAssertEqual(
            ReturnPointPolicy.resolve(savedGlobalPoint: CGPoint(x: 5000, y: 5000), viewerCaptureGlobalFrame: captureFrame),
            CGPoint(x: 400, y: 400)
        )
    }

    func testNonFiniteSavedPointFallsBackToViewerCaptureCenter() {
        let captureFrame = CGRect(x: -300, y: -200, width: 800, height: 600)

        XCTAssertEqual(
            ReturnPointPolicy.resolve(savedGlobalPoint: CGPoint(x: CGFloat.nan, y: 100), viewerCaptureGlobalFrame: captureFrame),
            CGPoint(x: 100, y: 100)
        )
        XCTAssertEqual(
            ReturnPointPolicy.resolve(savedGlobalPoint: CGPoint(x: 100, y: CGFloat.infinity), viewerCaptureGlobalFrame: captureFrame),
            CGPoint(x: 100, y: 100)
        )
    }
}
