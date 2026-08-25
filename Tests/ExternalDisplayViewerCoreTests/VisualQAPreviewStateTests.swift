#if DEBUG
@testable import ExternalDisplayViewerCore
import XCTest

final class VisualQAPreviewStateTests: XCTestCase {
    func testParsesEverySupportedStateFromRawValue() {
        for identifier in VisualQAPreviewState.Identifier.allCases {
            let state = VisualQAPreviewState.parse(rawValue: identifier.rawValue)

            XCTAssertEqual(state?.identifier, identifier)
        }
    }

    func testRejectsMissingBlankAndUnknownValues() {
        XCTAssertNil(VisualQAPreviewState.parse(rawValue: nil))
        XCTAssertNil(VisualQAPreviewState.parse(rawValue: "  "))
        XCTAssertNil(VisualQAPreviewState.parse(rawValue: "viewer-unknown"))
    }

    func testArgumentValueOverridesEnvironmentValue() {
        let state = VisualQAPreviewState.parse(
            environment: ["EDV_VISUAL_QA_STATE": "selection-ready"],
            arguments: ["ExternalDisplayViewer", "--visual-qa-state", "viewer-control-hud"]
        )

        XCTAssertEqual(state?.identifier, .viewerControlHUD)
        XCTAssertEqual(state?.surface, .viewer)
    }

    func testEqualsArgumentSyntaxIsSupported() {
        let state = VisualQAPreviewState.parse(
            environment: [:],
            arguments: ["ExternalDisplayViewer", "--visual-qa-state=selection-refresh-error"]
        )

        XCTAssertEqual(state?.identifier, .selectionRefreshError)
        XCTAssertEqual(state?.surface, .selection)
    }

    func testSelectionMappingsAreDeterministic() {
        let ready = VisualQAPreviewState(identifier: .selectionReady)
        XCTAssertEqual(ready.surface, .selection)
        XCTAssertTrue(ready.permissions.screenRecording)
        XCTAssertTrue(ready.permissions.canInteract)
        XCTAssertEqual(ready.displays.count, 1)
        XCTAssertEqual(ready.selectedDisplayID, ready.displays.first?.id)
        XCTAssertTrue(ready.canStartMirroring)

        let screenRecordingDenied = VisualQAPreviewState(identifier: .selectionScreenRecordingDenied)
        XCTAssertFalse(screenRecordingDenied.permissions.screenRecording)
        XCTAssertTrue(screenRecordingDenied.displays.isEmpty)
        XCTAssertNil(screenRecordingDenied.selectedDisplayID)
        XCTAssertFalse(screenRecordingDenied.canStartMirroring)

        let interactionDenied = VisualQAPreviewState(identifier: .selectionInteractionDenied)
        XCTAssertTrue(interactionDenied.permissions.screenRecording)
        XCTAssertFalse(interactionDenied.permissions.canInteract)
        XCTAssertTrue(interactionDenied.canStartMirroring)

        let accessibilitySettings = VisualQAPreviewState(identifier: .selectionAccessibilitySettings)
        XCTAssertEqual(accessibilitySettings.permissionRequestNotice, .manualSettingsRequired(.accessibility))

        let inputMonitoringSettings = VisualQAPreviewState(identifier: .selectionInputMonitoringSettings)
        XCTAssertEqual(inputMonitoringSettings.permissionRequestNotice, .manualSettingsRequired(.inputMonitoring))

        let noExternalDisplay = VisualQAPreviewState(identifier: .selectionNoExternalDisplay)
        XCTAssertTrue(noExternalDisplay.displays.isEmpty)
        XCTAssertNil(noExternalDisplay.selectedDisplayID)
        XCTAssertFalse(noExternalDisplay.canStartMirroring)

        let refreshError = VisualQAPreviewState(identifier: .selectionRefreshError)
        XCTAssertNotNil(refreshError.recoverableError)
    }

    @MainActor
    func testViewerMappingsExposeModeHudOverlapAndMetrics() {
        let viewOnly = VisualQAPreviewState(identifier: .viewerViewOnly)
        XCTAssertEqual(viewOnly.surface, .viewer)
        XCTAssertEqual(viewOnly.viewerMode, .viewOnly)
        XCTAssertNil(viewOnly.hudMessage)

        let interactive = VisualQAPreviewState(identifier: .viewerInteractiveReady)
        XCTAssertEqual(interactive.viewerMode, .interactive)
        XCTAssertTrue(interactive.permissions.canInteract)

        let controlHUD = VisualQAPreviewState(identifier: .viewerControlHUD)
        XCTAssertEqual(controlHUD.hudMessage, InteractionHUDMessages.control)
        XCTAssertEqual(controlHUD.hudMessage, TransitionHUDController.controlMessage)
        XCTAssertEqual(controlHUD.hudOpacity, 1)

        let returnHUD = VisualQAPreviewState(identifier: .viewerReturnHUD)
        XCTAssertEqual(returnHUD.hudMessage, InteractionHUDMessages.returnToViewer)
        XCTAssertEqual(returnHUD.hudMessage, TransitionHUDController.returnMessage)
        XCTAssertEqual(returnHUD.hudOpacity, 1)

        let overlap = VisualQAPreviewState(identifier: .viewerOverlapWarning)
        XCTAssertTrue(overlap.isOverlappingSource)
        XCTAssertEqual(overlap.viewerMode, .interactive)

        let metricsStress = VisualQAPreviewState(identifier: .viewerMetricsStress)
        XCTAssertEqual(metricsStress.metrics.receivedFrames, 987_654_321)
        XCTAssertEqual(metricsStress.metrics.displayedFrames, 876_543_210)
        XCTAssertEqual(metricsStress.metrics.displayedFPS, 123.4)
        XCTAssertEqual(metricsStress.metrics.incompleteRatio, 0.987)
    }
}
#endif
