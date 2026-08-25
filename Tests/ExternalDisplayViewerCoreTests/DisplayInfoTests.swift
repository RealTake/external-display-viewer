@testable import ExternalDisplayViewerCore
import CoreGraphics
import XCTest

final class DisplayInfoTests: XCTestCase {
    func testExternalDisplayLabelIncludesResolution() {
        let display = DisplayInfo(
            id: 42,
            name: "External Display",
            coreGraphicsFrame: CGRect(x: 1728, y: 0, width: 1920, height: 1080),
            appKitFrame: CGRect(x: 1728, y: 0, width: 1920, height: 1080),
            pixelSize: CGSize(width: 1920, height: 1080),
            scale: 1,
            isBuiltIn: false
        )

        XCTAssertEqual(display.menuLabel, "External Display · 1920×1080")
    }
}
