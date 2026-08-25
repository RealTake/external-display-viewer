@testable import ExternalDisplayViewerCore
import XCTest

final class MirrorSessionTests: XCTestCase {
    func testHappyPathReturnsToViewOnly() throws {
        var session = MirrorSession()
        try session.apply(.prepare)
        try session.apply(.captureStarted)
        try session.apply(.interactiveEnabled)
        try session.apply(.pointerTransferred)
        try session.apply(.returnRequested)
        try session.apply(.returnCompleted)
        XCTAssertEqual(session.state, .viewOnly)
    }

    func testCannotControlBeforeInteractiveIsEnabled() {
        var session = MirrorSession()
        XCTAssertThrowsError(try session.apply(.pointerTransferred))
        XCTAssertEqual(session.state, .idle)
    }
}
