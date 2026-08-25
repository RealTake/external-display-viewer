@testable import ExternalDisplayViewerCore
import XCTest

final class PermissionSnapshotTests: XCTestCase {
    func testMirrorAndInteractionUseDifferentPermissionSets() {
        XCTAssertTrue(PermissionSnapshot(screenRecording: true, postEvents: false, listenEvents: false, eventTapUsable: false).canMirror)
        XCTAssertFalse(PermissionSnapshot(screenRecording: true, postEvents: true, listenEvents: true, eventTapUsable: false).canInteract)
        XCTAssertTrue(PermissionSnapshot(screenRecording: true, postEvents: true, listenEvents: true, eventTapUsable: true).canInteract)
    }
}
