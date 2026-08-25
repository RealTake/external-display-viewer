@testable import ExternalDisplayViewerCore
import XCTest

final class SmokeContractTests: XCTestCase {
    @MainActor
    func testInteractionConstantsMatchApprovedContract() {
        XCTAssertEqual(InteractionContract.escapeHoldDuration, .milliseconds(800))
        XCTAssertEqual(InteractionContract.controlHUDDuration, .milliseconds(1500))
        XCTAssertEqual(InteractionContract.returnHUDDuration, .milliseconds(1200))
        XCTAssertEqual(
            InteractionHUDMessages.control,
            "외부 디스플레이 제어 중 · 화면 경계 또는 ESC를 길게 눌러 돌아오기"
        )
        XCTAssertEqual(
            InteractionHUDMessages.returnToViewer,
            "Viewer로 돌아왔습니다"
        )
        XCTAssertEqual(
            TransitionHUDController.controlMessage,
            InteractionHUDMessages.control
        )
        XCTAssertEqual(
            TransitionHUDController.returnMessage,
            InteractionHUDMessages.returnToViewer
        )
    }

    func testPackagingUsesStableCodeSigningIdentity() throws {
        let script = try buildScript()

        XCTAssertTrue(script.contains("EXTERNAL_DISPLAY_VIEWER_CODESIGN_IDENTITY"))
        XCTAssertTrue(script.contains("security find-identity"))
        XCTAssertFalse(script.contains("codesign --force --deep --sign -"))
    }

    func testPackagingSignsOutsideSyncedWorkspaceAndLinksDurableApp() throws {
        let script = try buildScript()

        XCTAssertTrue(script.contains("applicationSupportDirectory"))
        XCTAssertTrue(script.contains("STAGING_APP"))
        XCTAssertTrue(script.contains("ln -s"))
    }

    func testPackagingPreservesKnownGoodArchiveUntilReplacementIsVerified() throws {
        let script = try buildScript()

        XCTAssertTrue(script.contains("TEMP_ARCHIVE"))
        XCTAssertFalse(script.contains("rm -f \"$ARCHIVE\""))

        let verification = try XCTUnwrap(
            script.range(of: "codesign --verify --deep --strict \"$VERIFY_DIR/ExternalDisplayViewer.app\"")
        )
        let promotion = try XCTUnwrap(script.range(of: "mv -f \"$TEMP_ARCHIVE\" \"$ARCHIVE\""))
        XCTAssertLessThan(verification.lowerBound, promotion.lowerBound)
    }

    func testVisualQACaptureScopesWindowLookupToNewlyLaunchedBundleProcess() throws {
        let captureScript = try script(named: "capture-visual-qa.sh")
        let windowLookup = try script(named: "window-id.swift")

        XCTAssertTrue(captureScript.contains("--bundle-pid \"$QA_APP\""))
        XCTAssertTrue(captureScript.contains("--owner-pid \"$app_pid\" \"$title\""))
        XCTAssertTrue(captureScript.contains("--activate \"$app_pid\""))
        XCTAssertTrue(captureScript.contains("screencapture -x -o -l \"$window_id\""))
        XCTAssertFalse(captureScript.contains("\"$WINDOW_LOOKUP_BINARY\" \"$title\""))
        XCTAssertTrue(windowLookup.contains("NSRunningApplication"))
        XCTAssertTrue(windowLookup.contains("NSRunningApplication(processIdentifier:"))
        XCTAssertTrue(windowLookup.contains("kCGWindowOwnerPID"))
    }

    func testSelectionAndVisualQAPreviewShareScreenRecordingGuidance() throws {
        let rootView = try source(named: "UI/RootView.swift")
        let preview = try source(named: "UI/VisualQAPreviewRoot.swift")

        XCTAssertEqual(PermissionGuidanceCopy.screenRecordingNote, "허용 후 앱 재시작 필요")
        XCTAssertEqual(
            PermissionGuidanceCopy.screenRecordingRestartGuidance,
            "Screen Recording을 허용한 뒤 앱을 완전히 종료하고 다시 실행하세요."
        )
        XCTAssertTrue(rootView.contains("PermissionGuidanceCopy.screenRecordingNote"))
        XCTAssertTrue(preview.contains("PermissionGuidanceCopy.screenRecordingNote"))
        XCTAssertTrue(rootView.contains("PermissionGuidanceCopy.screenRecordingRestartGuidance"))
        XCTAssertTrue(preview.contains("PermissionGuidanceCopy.screenRecordingRestartGuidance"))
    }

    private func buildScript() throws -> String {
        try script(named: "build-app.sh")
    }

    private func script(named name: String) throws -> String {
        let scriptURL = packageRoot.appendingPathComponent("Scripts/\(name)")
        return try String(contentsOf: scriptURL, encoding: .utf8)
    }

    private func source(named name: String) throws -> String {
        let sourceURL = packageRoot.appendingPathComponent("Sources/ExternalDisplayViewerCore/\(name)")
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }

    private var packageRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
