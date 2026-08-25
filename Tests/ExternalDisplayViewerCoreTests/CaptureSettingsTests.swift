@testable import ExternalDisplayViewerCore
import CoreVideo
import ScreenCaptureKit
import XCTest

final class CaptureSettingsTests: XCTestCase {
    func testLowLatencyCaptureConfiguration() {
        let configuration = CaptureSettings.makeConfiguration(widthInPoints: 1920, heightInPoints: 1080, scale: 2)

        XCTAssertEqual(configuration.width, 3840)
        XCTAssertEqual(configuration.height, 2160)
        XCTAssertEqual(configuration.queueDepth, 3)
        XCTAssertTrue(configuration.showsCursor)
        XCTAssertFalse(configuration.capturesAudio)
        XCTAssertEqual(configuration.pixelFormat, kCVPixelFormatType_32BGRA)
    }
}
