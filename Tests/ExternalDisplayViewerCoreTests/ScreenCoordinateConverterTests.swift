@testable import ExternalDisplayViewerCore
import XCTest

final class ScreenCoordinateConverterTests: XCTestCase {
    func testAppKitGlobalRectConvertsToCoreGraphicsGlobalRect() {
        let appKitRect = CGRect(x: 200, y: 600, width: 400, height: 300)

        XCTAssertEqual(
            ScreenCoordinateConverter.coreGraphicsGlobalRect(appKitGlobalRect: appKitRect, mainDisplayHeight: 1080),
            CGRect(x: 200, y: 180, width: 400, height: 300)
        )
    }

    func testConversionPreservesNegativeOriginsAndDoesNotApplyRetinaScale() {
        let appKitRect = CGRect(x: -1440, y: -120, width: 720, height: 360)

        XCTAssertEqual(
            ScreenCoordinateConverter.coreGraphicsGlobalRect(appKitGlobalRect: appKitRect, mainDisplayHeight: 900),
            CGRect(x: -1440, y: 660, width: 720, height: 360)
        )
    }
}
