@testable import ExternalDisplayViewerCore
import XCTest

final class InteractionGateTests: XCTestCase {
    func testBlockReasonPriorityIsDeterministic() {
        XCTAssertEqual(
            InteractionGate.evaluate(
                permissions: PermissionSnapshot(screenRecording: false, postEvents: false, listenEvents: false, eventTapUsable: false),
                isSourceOverlapped: true
            ),
            .blocked(.postEventsDenied)
        )
        XCTAssertEqual(
            InteractionGate.evaluate(
                permissions: PermissionSnapshot(screenRecording: true, postEvents: true, listenEvents: false, eventTapUsable: false),
                isSourceOverlapped: true
            ),
            .blocked(.listenEventsDenied)
        )
        XCTAssertEqual(
            InteractionGate.evaluate(
                permissions: PermissionSnapshot(screenRecording: true, postEvents: true, listenEvents: true, eventTapUsable: false),
                isSourceOverlapped: true
            ),
            .blocked(.eventTapUnavailable)
        )
        XCTAssertEqual(
            InteractionGate.evaluate(
                permissions: PermissionSnapshot(screenRecording: true, postEvents: true, listenEvents: true, eventTapUsable: true),
                isSourceOverlapped: true
            ),
            .blocked(.sourceOverlapped)
        )
    }

    func testScreenRecordingDoesNotBlockInteractionGate() {
        XCTAssertEqual(
            InteractionGate.evaluate(
                permissions: PermissionSnapshot(screenRecording: false, postEvents: true, listenEvents: true, eventTapUsable: true),
                isSourceOverlapped: false
            ),
            .allowed
        )
    }
}

@MainActor
final class AppCoordinatorPolicyTests: XCTestCase {
    func testRefreshWithoutScreenRecordingStillDiscoversExternalDisplay() async {
        let harness = AppCoordinatorHarness(
            permissions: PermissionSnapshot(
                screenRecording: false,
                postEvents: false,
                listenEvents: false,
                eventTapUsable: false
            )
        )
        let coordinator = harness.makeCoordinator()

        await coordinator.refresh()

        XCTAssertEqual(harness.refreshCount, 1)
        XCTAssertNil(coordinator.recoverableError)
        XCTAssertEqual(coordinator.externalDisplays, [harness.externalDisplay])
        XCTAssertFalse(coordinator.canStartMirroring)
    }

    func testDeniedScreenRecordingRequestOpensScreenRecordingSettingsInsteadOfFailingSilently() {
        let harness = AppCoordinatorHarness(
            permissions: PermissionSnapshot(
                screenRecording: false,
                postEvents: true,
                listenEvents: true,
                eventTapUsable: true
            )
        )
        harness.screenRecordingRequestResults = [false]
        let coordinator = harness.makeCoordinator()
        harness.permissionRefreshCount = 0

        let result = coordinator.requestScreenRecording()

        XCTAssertFalse(result)
        XCTAssertEqual(harness.screenRecordingRequestCount, 1)
        XCTAssertEqual(harness.permissionRefreshCount, 1)
        XCTAssertEqual(harness.openedPermissionSettings.map(\.systemSettingsAnchor), ["Privacy_ScreenCapture"])
        guard case let .manualSettingsRequired(pane)? = coordinator.permissionRequestNotice else {
            XCTFail("Denied Screen Recording should publish manual settings guidance")
            return
        }
        XCTAssertEqual(pane.systemSettingsAnchor, "Privacy_ScreenCapture")
        XCTAssertFalse(coordinator.permissions.screenRecording)
    }

    func testDeniedPostEventRequestOpensAccessibilitySettingsInsteadOfFailingSilently() {
        let harness = AppCoordinatorHarness(
            permissions: PermissionSnapshot(
                screenRecording: true,
                postEvents: false,
                listenEvents: true,
                eventTapUsable: false
            )
        )
        harness.postEventRequestResults = [false]
        let coordinator = harness.makeCoordinator()
        harness.permissionRefreshCount = 0

        let result = coordinator.requestPostEvents()

        XCTAssertFalse(result)
        XCTAssertEqual(harness.postEventRequestCount, 1)
        XCTAssertEqual(harness.permissionRefreshCount, 1)
        XCTAssertEqual(harness.openedPermissionSettings, [.accessibility])
        XCTAssertEqual(coordinator.permissionRequestNotice, .manualSettingsRequired(.accessibility))
        XCTAssertFalse(coordinator.permissions.postEvents)
    }

    func testDeniedListenEventRequestOpensInputMonitoringSettingsInsteadOfFailingSilently() {
        let harness = AppCoordinatorHarness(
            permissions: PermissionSnapshot(
                screenRecording: true,
                postEvents: true,
                listenEvents: false,
                eventTapUsable: false
            )
        )
        harness.listenEventRequestResults = [false]
        let coordinator = harness.makeCoordinator()
        harness.permissionRefreshCount = 0

        let result = coordinator.requestListenEvents()

        XCTAssertFalse(result)
        XCTAssertEqual(harness.listenEventRequestCount, 1)
        XCTAssertEqual(harness.permissionRefreshCount, 1)
        XCTAssertEqual(harness.openedPermissionSettings, [.inputMonitoring])
        XCTAssertEqual(coordinator.permissionRequestNotice, .manualSettingsRequired(.inputMonitoring))
        XCTAssertFalse(coordinator.permissions.listenEvents)
    }

    func testPostEventRequestResultDoesNotHideAuthoritativeDeniedPermission() {
        let harness = AppCoordinatorHarness(
            permissions: PermissionSnapshot(
                screenRecording: true,
                postEvents: false,
                listenEvents: true,
                eventTapUsable: false
            )
        )
        harness.postEventRequestResults = [true]
        let coordinator = harness.makeCoordinator()
        harness.permissionRefreshCount = 0

        let result = coordinator.requestPostEvents()

        XCTAssertTrue(result)
        XCTAssertEqual(harness.postEventRequestCount, 1)
        XCTAssertEqual(harness.permissionRefreshCount, 1)
        XCTAssertEqual(harness.openedPermissionSettings, [.accessibility])
        XCTAssertEqual(coordinator.permissionRequestNotice, .manualSettingsRequired(.accessibility))
        XCTAssertFalse(coordinator.permissions.postEvents)
    }

    func testListenEventRequestResultDoesNotHideAuthoritativeDeniedPermission() {
        let harness = AppCoordinatorHarness(
            permissions: PermissionSnapshot(
                screenRecording: true,
                postEvents: true,
                listenEvents: false,
                eventTapUsable: false
            )
        )
        harness.listenEventRequestResults = [true]
        let coordinator = harness.makeCoordinator()
        harness.permissionRefreshCount = 0

        let result = coordinator.requestListenEvents()

        XCTAssertTrue(result)
        XCTAssertEqual(harness.listenEventRequestCount, 1)
        XCTAssertEqual(harness.permissionRefreshCount, 1)
        XCTAssertEqual(harness.openedPermissionSettings, [.inputMonitoring])
        XCTAssertEqual(coordinator.permissionRequestNotice, .manualSettingsRequired(.inputMonitoring))
        XCTAssertFalse(coordinator.permissions.listenEvents)
    }

    func testGrantedPostEventRequestDoesNotOpenSettingsAndClearsManualAction() {
        let harness = AppCoordinatorHarness(
            permissions: PermissionSnapshot(
                screenRecording: true,
                postEvents: false,
                listenEvents: true,
                eventTapUsable: false
            )
        )
        harness.postEventRequestResults = [true]
        let coordinator = harness.makeCoordinator()
        harness.permissions = PermissionSnapshot(
            screenRecording: true,
            postEvents: true,
            listenEvents: true,
            eventTapUsable: true
        )
        harness.permissionRefreshCount = 0

        let result = coordinator.requestPostEvents()

        XCTAssertTrue(result)
        XCTAssertEqual(harness.postEventRequestCount, 1)
        XCTAssertEqual(harness.permissionRefreshCount, 1)
        XCTAssertTrue(harness.openedPermissionSettings.isEmpty)
        XCTAssertNil(coordinator.permissionRequestNotice)
        XCTAssertTrue(coordinator.permissions.postEvents)
    }

    func testGrantedListenEventRequestDoesNotOpenSettingsAndClearsManualAction() {
        let harness = AppCoordinatorHarness(
            permissions: PermissionSnapshot(
                screenRecording: true,
                postEvents: true,
                listenEvents: false,
                eventTapUsable: false
            )
        )
        harness.listenEventRequestResults = [true]
        let coordinator = harness.makeCoordinator()
        harness.permissions = PermissionSnapshot(
            screenRecording: true,
            postEvents: true,
            listenEvents: true,
            eventTapUsable: true
        )
        harness.permissionRefreshCount = 0

        let result = coordinator.requestListenEvents()

        XCTAssertTrue(result)
        XCTAssertEqual(harness.listenEventRequestCount, 1)
        XCTAssertEqual(harness.permissionRefreshCount, 1)
        XCTAssertTrue(harness.openedPermissionSettings.isEmpty)
        XCTAssertNil(coordinator.permissionRequestNotice)
        XCTAssertTrue(coordinator.permissions.listenEvents)
    }

    func testStartMirroringNeedsOnlyScreenRecordingAndOpensViewOnly() async {
        let harness = AppCoordinatorHarness(
            permissions: PermissionSnapshot(screenRecording: true, postEvents: false, listenEvents: false, eventTapUsable: false)
        )
        let coordinator = harness.makeCoordinator()

        await coordinator.startMirroring(displayID: harness.externalDisplay.id)

        XCTAssertEqual(coordinator.session.state, .viewOnly)
        XCTAssertEqual(harness.captureStartedDisplayIDs, [harness.externalDisplay.id])
        XCTAssertEqual(harness.openedViewerModes, [.viewOnly])
    }

    func testInteractiveCommitsOnlyAfterEscapeTapStarts() async {
        let harness = AppCoordinatorHarness(permissions: .allGranted)
        let coordinator = harness.makeCoordinator()
        await coordinator.startMirroring(displayID: harness.externalDisplay.id)

        await coordinator.setInteractive(true)

        XCTAssertEqual(harness.escapeStartCount, 1)
        XCTAssertEqual(coordinator.session.state, .interactiveReady)
        XCTAssertEqual(harness.viewerModes, [.interactive])
    }

    func testTapStartFailureLeavesViewerViewOnly() async {
        let harness = AppCoordinatorHarness(permissions: .allGranted)
        harness.escapeStartResult = false
        let coordinator = harness.makeCoordinator()
        await coordinator.startMirroring(displayID: harness.externalDisplay.id)

        await coordinator.setInteractive(true)

        XCTAssertEqual(coordinator.session.state, .viewOnly)
        XCTAssertEqual(harness.viewerModes, [.viewOnly])
        XCTAssertEqual(harness.escapeStopCount, 1)
    }

    func testValidDownSavesExactReturnPointAndShowsControlHUD() async {
        let harness = AppCoordinatorHarness(permissions: .allGranted)
        let coordinator = harness.makeCoordinator()
        await coordinator.startMirroring(displayID: harness.externalDisplay.id)
        await coordinator.setInteractive(true)

        coordinator.handlePointerDown(
            MirrorSurfaceMouseEvent(
                button: .left,
                location: CGPoint(x: 50, y: 50),
                renderRect: CGRect(x: 0, y: 0, width: 100, height: 100),
                clickCount: 1
            )
        )

        XCTAssertEqual(coordinator.session.state, .controllingExternal)
        XCTAssertEqual(coordinator.savedReturnPointForTesting, CGPoint(x: 321, y: 654))
        XCTAssertEqual(harness.hudEvents, [.control])
    }

    func testLetterboxDownDoesNotChangeStateOrShowHUD() async {
        let harness = AppCoordinatorHarness(permissions: .allGranted)
        let coordinator = harness.makeCoordinator()
        await coordinator.startMirroring(displayID: harness.externalDisplay.id)
        await coordinator.setInteractive(true)

        coordinator.handlePointerDown(
            MirrorSurfaceMouseEvent(
                button: .left,
                location: CGPoint(x: 50, y: 50),
                renderRect: CGRect(x: 0, y: 100, width: 100, height: 100),
                clickCount: 1
            )
        )

        XCTAssertEqual(coordinator.session.state, .interactiveReady)
        XCTAssertTrue(harness.hudEvents.isEmpty)
    }

    func testSafeReturnIsOrderedAndIdempotent() async {
        let harness = AppCoordinatorHarness(permissions: .allGranted)
        let coordinator = harness.makeCoordinator()
        await coordinator.startMirroring(displayID: harness.externalDisplay.id)
        await coordinator.setInteractive(true)
        coordinator.handlePointerDown(
            MirrorSurfaceMouseEvent(
                button: .left,
                location: CGPoint(x: 50, y: 50),
                renderRect: CGRect(x: 0, y: 0, width: 100, height: 100),
                clickCount: 1
            )
        )

        await coordinator.returnToViewer(reason: .escapeHold)
        await coordinator.returnToViewer(reason: .escapeHold)

        XCTAssertEqual(harness.returnActions, [
            .cancelInput,
            .stopEscapeTap,
            .captureViewerFrame,
            .warp(CGPoint(x: 321, y: 654)),
            .activateApp,
            .bringViewerForward,
            .publishViewOnly,
            .showReturnHUD
        ])
        XCTAssertEqual(coordinator.session.state, .viewOnly)
    }

    func testInteractiveReadyDisableStopsTapWithoutCursorWarp() async {
        let harness = AppCoordinatorHarness(permissions: .allGranted)
        let coordinator = harness.makeCoordinator()
        await coordinator.startMirroring(displayID: harness.externalDisplay.id)
        await coordinator.setInteractive(true)

        await coordinator.setInteractive(false)

        XCTAssertEqual(coordinator.session.state, .viewOnly)
        XCTAssertEqual(harness.returnActions, [
            .stopEscapeTap,
            .publishViewOnly
        ])
    }

    func testSourceOverlapWhileControllingUsesSafeReturn() async {
        let harness = AppCoordinatorHarness(permissions: .allGranted)
        let coordinator = harness.makeCoordinator()
        await coordinator.startMirroring(displayID: harness.externalDisplay.id)
        await coordinator.setInteractive(true)
        coordinator.handlePointerDown(
            MirrorSurfaceMouseEvent(
                button: .left,
                location: CGPoint(x: 50, y: 50),
                renderRect: CGRect(x: 0, y: 0, width: 100, height: 100),
                clickCount: 1
            )
        )

        coordinator.handleSourceOverlapChanged(true)

        XCTAssertEqual(coordinator.session.state, .viewOnly)
        XCTAssertTrue(harness.returnActions.contains(.warp(CGPoint(x: 321, y: 654))))
    }

    func testNoViewerFrameAndNoSavedPointDoesNotWarpToZero() async {
        let harness = AppCoordinatorHarness(permissions: .allGranted)
        harness.viewerFrame = nil
        let coordinator = harness.makeCoordinator()
        await coordinator.startMirroring(displayID: harness.externalDisplay.id)
        await coordinator.setInteractive(true)

        await coordinator.returnToViewer(reason: .stop)

        XCTAssertFalse(harness.returnActions.contains(.warp(.zero)))
        XCTAssertFalse(harness.returnActions.contains { action in
            if case .warp = action {
                return true
            }
            return false
        })
    }

    func testRestartStopsPreviousSessionAndStartsFresh() async {
        let harness = AppCoordinatorHarness(permissions: .allGranted)
        let coordinator = harness.makeCoordinator()
        await coordinator.startMirroring(displayID: harness.externalDisplay.id)

        await coordinator.startMirroring(displayID: harness.externalDisplay.id)

        XCTAssertEqual(harness.stopCaptureCount, 1)
        XCTAssertEqual(harness.closeCount, 1)
        XCTAssertEqual(harness.captureStartedDisplayIDs, [harness.externalDisplay.id, harness.externalDisplay.id])
        XCTAssertEqual(coordinator.session.state, .viewOnly)
    }

    func testRestartDoesNotStartNewCaptureWhenExistingSafeReturnFails() async {
        let harness = AppCoordinatorHarness(permissions: .allGranted)
        harness.cancelResults = [.failed(.mouseUp)]
        let coordinator = harness.makeCoordinator()
        await coordinator.startMirroring(displayID: harness.externalDisplay.id)
        await coordinator.setInteractive(true)
        coordinator.handlePointerDown(
            MirrorSurfaceMouseEvent(
                button: .left,
                location: CGPoint(x: 50, y: 50),
                renderRect: CGRect(x: 0, y: 0, width: 100, height: 100),
                clickCount: 1
            )
        )

        await coordinator.startMirroring(displayID: harness.externalDisplay.id)

        XCTAssertEqual(harness.captureStartedDisplayIDs, [harness.externalDisplay.id])
        XCTAssertEqual(harness.stopCaptureCount, 0)
        XCTAssertEqual(harness.closeCount, 0)
        XCTAssertEqual(coordinator.session.state, .returning)
        XCTAssertEqual(coordinator.savedReturnPointForTesting, harness.returnPoint)
    }

    func testDisplayRemovalStopsMirroring() async {
        let harness = AppCoordinatorHarness(permissions: .allGranted)
        let coordinator = harness.makeCoordinator()
        await coordinator.startMirroring(displayID: harness.externalDisplay.id)

        await coordinator.handleDisplayRefresh(.success([]))

        XCTAssertEqual(harness.stopCaptureCount, 1)
        XCTAssertEqual(harness.closeCount, 1)
        XCTAssertEqual(coordinator.session.state, .idle)
    }

    func testStopAfterDrainingPortalReturnForceStopsBoundaryTap() async {
        let harness = AppCoordinatorHarness(permissions: .allGranted)
        harness.boundaryPrepareResult = .draining
        let coordinator = harness.makeCoordinator()
        await coordinator.startMirroring(displayID: harness.externalDisplay.id)
        coordinator.handlePortalEntered(
            MirrorSurfacePortalEvent(location: CGPoint(x: 25, y: 75), renderRect: CGRect(x: 0, y: 0, width: 100, height: 100))
        )
        harness.boundaryExitHandler?(PointerPortalExit(edge: .bottom, position: 0.25))
        harness.returnActions.removeAll()

        await coordinator.stopMirroring()

        XCTAssertEqual(harness.returnActions, [
            .stopBoundaryTap,
            .stopCapture
        ])
        XCTAssertEqual(coordinator.session.state, .idle)
    }

    func testDisplayRemovalAfterDrainingPortalReturnForceStopsBoundaryTap() async {
        let harness = AppCoordinatorHarness(permissions: .allGranted)
        harness.boundaryPrepareResult = .draining
        let coordinator = harness.makeCoordinator()
        await coordinator.startMirroring(displayID: harness.externalDisplay.id)
        coordinator.handlePortalEntered(
            MirrorSurfacePortalEvent(location: CGPoint(x: 25, y: 75), renderRect: CGRect(x: 0, y: 0, width: 100, height: 100))
        )
        harness.boundaryExitHandler?(PointerPortalExit(edge: .bottom, position: 0.25))
        harness.returnActions.removeAll()

        await coordinator.handleDisplayRefresh(.success([]))

        XCTAssertEqual(harness.returnActions, [
            .stopBoundaryTap,
            .stopCapture
        ])
        XCTAssertEqual(coordinator.session.state, .idle)
    }

    func testTerminationAfterDrainingPortalReturnForceStopsBoundaryTap() async {
        let harness = AppCoordinatorHarness(permissions: .allGranted)
        harness.boundaryPrepareResult = .draining
        let coordinator = harness.makeCoordinator()
        await coordinator.startMirroring(displayID: harness.externalDisplay.id)
        coordinator.handlePortalEntered(
            MirrorSurfacePortalEvent(location: CGPoint(x: 25, y: 75), renderRect: CGRect(x: 0, y: 0, width: 100, height: 100))
        )
        harness.boundaryExitHandler?(PointerPortalExit(edge: .bottom, position: 0.25))
        harness.returnActions.removeAll()

        let cleaned = await coordinator.performTerminationCleanup()

        XCTAssertTrue(cleaned)
        XCTAssertEqual(harness.returnActions, [
            .stopBoundaryTap,
            .stopCapture
        ])
    }

    func testViewOnlyStopDoesNotStopInactiveBoundaryTap() async {
        let harness = AppCoordinatorHarness(permissions: .allGranted)
        let coordinator = harness.makeCoordinator()
        await coordinator.startMirroring(displayID: harness.externalDisplay.id)
        harness.returnActions.removeAll()

        await coordinator.stopMirroring()

        XCTAssertTrue(harness.returnActions.contains(.stopCapture))
        XCTAssertFalse(harness.returnActions.contains(.stopBoundaryTap))
    }

    func testReturnGuardResetsForNewInteractiveCycleBeforePointerDown() async {
        let harness = AppCoordinatorHarness(permissions: .allGranted)
        let coordinator = harness.makeCoordinator()
        await coordinator.startMirroring(displayID: harness.externalDisplay.id)
        await coordinator.setInteractive(true)
        coordinator.handlePointerDown(
            MirrorSurfaceMouseEvent(
                button: .left,
                location: CGPoint(x: 50, y: 50),
                renderRect: CGRect(x: 0, y: 0, width: 100, height: 100),
                clickCount: 1
            )
        )
        await coordinator.returnToViewer(reason: .escapeHold)
        harness.returnActions.removeAll()

        await coordinator.setInteractive(true)
        await coordinator.returnToViewer(reason: .eventTapFailure)

        XCTAssertEqual(harness.returnActions, [
            .cancelInput,
            .stopEscapeTap,
            .activateApp,
            .bringViewerForward,
            .publishViewOnly,
            .showReturnHUD
        ])
        XCTAssertEqual(coordinator.session.state, .viewOnly)
    }

    func testStartAlwaysRefreshesDisplaysAndRejectsStaleOrBuiltInTarget() async {
        let harness = AppCoordinatorHarness(permissions: .allGranted)
        let builtIn = DisplayInfo(
            id: 99,
            name: "Built-in",
            coreGraphicsFrame: CGRect(x: 0, y: 0, width: 1000, height: 800),
            appKitFrame: CGRect(x: 0, y: 0, width: 1000, height: 800),
            pixelSize: CGSize(width: 1000, height: 800),
            scale: 1,
            isBuiltIn: true
        )
        harness.refreshDisplayResults = [[harness.externalDisplay], [builtIn]]
        let coordinator = harness.makeCoordinator()
        await coordinator.refresh()

        await coordinator.startMirroring(displayID: harness.externalDisplay.id)

        XCTAssertEqual(harness.refreshCount, 2)
        XCTAssertTrue(harness.captureStartedDisplayIDs.isEmpty)
        XCTAssertEqual(coordinator.recoverableError, "선택한 외부 디스플레이를 찾을 수 없습니다.")
    }

    func testRetryAfterCaptureFailureRestartsSelectedCaptureAndClearsError() async {
        let harness = AppCoordinatorHarness(permissions: .allGranted)
        harness.captureStartFailures = [HarnessError.captureFailed]
        let coordinator = harness.makeCoordinator()

        await coordinator.startMirroring(displayID: harness.externalDisplay.id)
        XCTAssertEqual(coordinator.session.state, .failed("capture failed"))
        XCTAssertEqual(coordinator.recoverableError, "capture failed")

        await coordinator.retryMirroring()

        XCTAssertEqual(harness.captureStartedDisplayIDs, [harness.externalDisplay.id, harness.externalDisplay.id])
        XCTAssertNil(coordinator.recoverableError)
        XCTAssertEqual(coordinator.session.state, .viewOnly)
    }

    func testProductionOverlapCallbackReachesCoordinatorSafeReturn() async {
        let harness = AppCoordinatorHarness(permissions: .allGranted)
        let coordinator = harness.makeCoordinator()
        await coordinator.startMirroring(displayID: harness.externalDisplay.id)
        await coordinator.setInteractive(true)
        coordinator.handlePointerDown(
            MirrorSurfaceMouseEvent(
                button: .left,
                location: CGPoint(x: 50, y: 50),
                renderRect: CGRect(x: 0, y: 0, width: 100, height: 100),
                clickCount: 1
            )
        )

        harness.viewerCallbacks?.onOverlapChanged(true)

        XCTAssertEqual(coordinator.session.state, .viewOnly)
        XCTAssertTrue(harness.returnActions.contains(.warp(CGPoint(x: 321, y: 654))))
    }

    func testInputFailureSetsRecoverableErrorAndFailedState() async {
        let harness = AppCoordinatorHarness(permissions: .allGranted)
        harness.beginResultOverride = .failed(.warp)
        let coordinator = harness.makeCoordinator()
        await coordinator.startMirroring(displayID: harness.externalDisplay.id)
        await coordinator.setInteractive(true)

        coordinator.handlePointerDown(
            MirrorSurfaceMouseEvent(
                button: .left,
                location: CGPoint(x: 50, y: 50),
                renderRect: CGRect(x: 0, y: 0, width: 100, height: 100),
                clickCount: 1
            )
        )

        XCTAssertEqual(coordinator.recoverableError, "포인터 제어를 시작할 수 없습니다.")
        XCTAssertEqual(coordinator.session.state, .failed("포인터 제어를 시작할 수 없습니다."))
    }

    func testTerminationReplyWaitsUntilAfterSafeReturnAndCaptureStop() async {
        let harness = AppCoordinatorHarness(permissions: .allGranted)
        let coordinator = harness.makeCoordinator()
        await coordinator.startMirroring(displayID: harness.externalDisplay.id)
        await coordinator.setInteractive(true)
        coordinator.handlePointerDown(
            MirrorSurfaceMouseEvent(
                button: .left,
                location: CGPoint(x: 50, y: 50),
                renderRect: CGRect(x: 0, y: 0, width: 100, height: 100),
                clickCount: 1
            )
        )

        await coordinator.applicationShouldTerminate { shouldTerminate in
            XCTAssertTrue(shouldTerminate)
            harness.returnActions.append(.terminationReply)
        }

        XCTAssertEqual(harness.returnActions.suffix(3), [
            .showReturnHUD,
            .stopCapture,
            .terminationReply
        ])
    }

    func testReturnCleanupCancelFailureRemainsRetryableWithoutWarpOrSuccessHUD() async {
        let harness = AppCoordinatorHarness(permissions: .allGranted)
        harness.cancelResults = [.failed(.mouseUp), .ended]
        let coordinator = harness.makeCoordinator()
        await coordinator.startMirroring(displayID: harness.externalDisplay.id)
        await coordinator.setInteractive(true)
        coordinator.handlePointerDown(
            MirrorSurfaceMouseEvent(
                button: .left,
                location: CGPoint(x: 50, y: 50),
                renderRect: CGRect(x: 0, y: 0, width: 100, height: 100),
                clickCount: 1
            )
        )

        await coordinator.returnToViewer(reason: .escapeHold)

        XCTAssertEqual(coordinator.session.state, .returning)
        XCTAssertEqual(coordinator.savedReturnPointForTesting, harness.returnPoint)
        XCTAssertFalse(harness.returnActions.contains(.captureViewerFrame))
        XCTAssertFalse(harness.returnActions.contains(.warp(harness.returnPoint)))
        XCTAssertFalse(harness.returnActions.contains(.showReturnHUD))
        XCTAssertTrue(harness.returnActions.contains(.stopEscapeTap))
        XCTAssertTrue(harness.returnActions.contains(.activateApp))
        XCTAssertTrue(harness.returnActions.contains(.bringViewerForward))
        XCTAssertTrue(harness.returnActions.contains(.publishViewOnly))

        await coordinator.returnToViewer(reason: .stop)

        XCTAssertEqual(coordinator.session.state, .viewOnly)
        XCTAssertNil(coordinator.savedReturnPointForTesting)
        XCTAssertEqual(harness.returnActions.filter { $0 == .captureViewerFrame }.count, 1)
        XCTAssertEqual(harness.returnActions.filter { $0 == .warp(harness.returnPoint) }.count, 1)
        XCTAssertEqual(harness.returnActions.filter { $0 == .showReturnHUD }.count, 1)
    }

    func testReturnCleanupWarpFailureRemainsRetryableWithoutSuccessHUD() async {
        let harness = AppCoordinatorHarness(permissions: .allGranted)
        harness.warpResults = [false, true]
        let coordinator = harness.makeCoordinator()
        await coordinator.startMirroring(displayID: harness.externalDisplay.id)
        await coordinator.setInteractive(true)
        coordinator.handlePointerDown(
            MirrorSurfaceMouseEvent(
                button: .left,
                location: CGPoint(x: 50, y: 50),
                renderRect: CGRect(x: 0, y: 0, width: 100, height: 100),
                clickCount: 1
            )
        )

        await coordinator.returnToViewer(reason: .escapeHold)

        XCTAssertEqual(coordinator.session.state, .returning)
        XCTAssertEqual(coordinator.savedReturnPointForTesting, harness.returnPoint)
        XCTAssertEqual(harness.returnActions.filter { $0 == .warp(harness.returnPoint) }.count, 1)
        XCTAssertFalse(harness.returnActions.contains(.showReturnHUD))

        await coordinator.returnToViewer(reason: .stop)

        XCTAssertEqual(coordinator.session.state, .viewOnly)
        XCTAssertNil(coordinator.savedReturnPointForTesting)
        XCTAssertEqual(harness.returnActions.filter { $0 == .warp(harness.returnPoint) }.count, 2)
        XCTAssertEqual(harness.returnActions.filter { $0 == .showReturnHUD }.count, 1)
    }

    func testTerminationCancelFailureDoesNotStopCaptureAndCanRetryToSuccess() async {
        let harness = AppCoordinatorHarness(permissions: .allGranted)
        harness.cancelResults = [.failed(.mouseUp), .ended]
        let coordinator = harness.makeCoordinator()
        await coordinator.startMirroring(displayID: harness.externalDisplay.id)
        await coordinator.setInteractive(true)
        coordinator.handlePointerDown(
            MirrorSurfaceMouseEvent(
                button: .left,
                location: CGPoint(x: 50, y: 50),
                renderRect: CGRect(x: 0, y: 0, width: 100, height: 100),
                clickCount: 1
            )
        )

        let failedTermination = await coordinator.performTerminationCleanup()

        XCTAssertFalse(failedTermination)
        XCTAssertEqual(harness.stopCaptureCount, 0)
        XCTAssertEqual(coordinator.session.state, .returning)
        XCTAssertEqual(coordinator.savedReturnPointForTesting, harness.returnPoint)

        let successfulTermination = await coordinator.performTerminationCleanup()

        XCTAssertTrue(successfulTermination)
        XCTAssertEqual(harness.stopCaptureCount, 1)
        XCTAssertEqual(coordinator.session.state, .viewOnly)
        XCTAssertNil(coordinator.savedReturnPointForTesting)
    }

    func testTerminationWarpFailureDoesNotStopCaptureAndCanRetryToSuccess() async {
        let harness = AppCoordinatorHarness(permissions: .allGranted)
        harness.warpResults = [false, true]
        let coordinator = harness.makeCoordinator()
        await coordinator.startMirroring(displayID: harness.externalDisplay.id)
        await coordinator.setInteractive(true)
        coordinator.handlePointerDown(
            MirrorSurfaceMouseEvent(
                button: .left,
                location: CGPoint(x: 50, y: 50),
                renderRect: CGRect(x: 0, y: 0, width: 100, height: 100),
                clickCount: 1
            )
        )

        let failedTermination = await coordinator.performTerminationCleanup()

        XCTAssertFalse(failedTermination)
        XCTAssertEqual(harness.stopCaptureCount, 0)
        XCTAssertEqual(coordinator.session.state, .returning)
        XCTAssertEqual(coordinator.savedReturnPointForTesting, harness.returnPoint)

        let successfulTermination = await coordinator.performTerminationCleanup()

        XCTAssertTrue(successfulTermination)
        XCTAssertEqual(harness.stopCaptureCount, 1)
        XCTAssertEqual(harness.returnActions.filter { $0 == .warp(harness.returnPoint) }.count, 2)
        XCTAssertEqual(harness.returnActions.filter { $0 == .showReturnHUD }.count, 1)
    }

    func testInteractiveEnableWhileReturnIncompleteDoesNotStartTapOrCorruptState() async {
        let harness = AppCoordinatorHarness(permissions: .allGranted)
        harness.cancelResults = [.failed(.mouseUp)]
        let coordinator = harness.makeCoordinator()
        await coordinator.startMirroring(displayID: harness.externalDisplay.id)
        await coordinator.setInteractive(true)
        coordinator.handlePointerDown(
            MirrorSurfaceMouseEvent(
                button: .left,
                location: CGPoint(x: 50, y: 50),
                renderRect: CGRect(x: 0, y: 0, width: 100, height: 100),
                clickCount: 1
            )
        )
        await coordinator.returnToViewer(reason: .escapeHold)
        harness.returnActions.removeAll()
        let escapeStartCountAfterFailedReturn = harness.escapeStartCount

        await coordinator.setInteractive(true)

        XCTAssertEqual(coordinator.session.state, .returning)
        XCTAssertEqual(harness.escapeStartCount, escapeStartCountAfterFailedReturn)
        XCTAssertEqual(harness.viewerModes.suffix(1), [.viewOnly])
        XCTAssertEqual(harness.returnActions, [.publishViewOnly])
    }

    func testPortalHoverEntryStartsTapsWarpsAndPublishesWithoutSyntheticDown() async {
        let harness = AppCoordinatorHarness(permissions: .allGranted)
        harness.recordEscapeStartAction = true
        harness.recordPortalEntryOrder = true
        let coordinator = harness.makeCoordinator()
        await coordinator.startMirroring(displayID: harness.externalDisplay.id)
        harness.returnActions.removeAll()

        coordinator.handlePortalEntered(
            MirrorSurfacePortalEvent(
                location: CGPoint(x: 25, y: 75),
                renderRect: CGRect(x: 0, y: 0, width: 100, height: 100)
            )
        )

        XCTAssertEqual(coordinator.session.state, .controllingExternal)
        XCTAssertEqual(harness.beginInputCount, 0)
        XCTAssertEqual(harness.returnActions, [
            .permissionRefresh,
            .portalGeometry,
            .startEscapeTap,
            .startBoundaryTap(harness.externalDisplay.coreGraphicsFrame),
            .warp(CGPoint(x: 1250, y: 750)),
            .publishInteractive,
            .showControlHUD
        ])
        XCTAssertEqual(harness.viewerModes, [.interactive])
        XCTAssertEqual(harness.hudEvents, [.control])
    }

    func testPortalHoverEntryRejectsDeniedPermissionOverlapAndInvalidGeometryWithoutWarp() async {
        let harness = AppCoordinatorHarness(permissions: .allGranted)
        let coordinator = harness.makeCoordinator()
        await coordinator.startMirroring(displayID: harness.externalDisplay.id)
        harness.permissions = PermissionSnapshot(screenRecording: true, postEvents: false, listenEvents: true, eventTapUsable: true)

        coordinator.handlePortalEntered(
            MirrorSurfacePortalEvent(
                location: CGPoint(x: 25, y: 75),
                renderRect: CGRect(x: 0, y: 0, width: 100, height: 100)
            )
        )

        XCTAssertEqual(coordinator.session.state, .viewOnly)
        XCTAssertEqual(harness.returnActions, [.publishViewOnly])

        harness.permissions = .allGranted
        harness.returnActions.removeAll()
        harness.viewerCallbacks?.onOverlapChanged(true)
        harness.returnActions.removeAll()
        coordinator.handlePortalEntered(
            MirrorSurfacePortalEvent(
                location: CGPoint(x: 25, y: 75),
                renderRect: CGRect(x: 0, y: 0, width: 100, height: 100)
            )
        )

        XCTAssertEqual(coordinator.session.state, .viewOnly)
        XCTAssertEqual(harness.returnActions, [.publishViewOnly])

        harness.viewerCallbacks?.onOverlapChanged(false)
        harness.portalGeometry = nil
        harness.returnActions.removeAll()
        coordinator.handlePortalEntered(
            MirrorSurfacePortalEvent(
                location: CGPoint(x: 25, y: 75),
                renderRect: CGRect(x: 0, y: 0, width: 100, height: 100)
            )
        )

        XCTAssertEqual(coordinator.session.state, .viewOnly)
        XCTAssertEqual(harness.returnActions, [.portalGeometry, .publishViewOnly])
    }

    func testPortalHoverEntryRollsBackTapsOnStartOrWarpFailure() async {
        let escapeFailureHarness = AppCoordinatorHarness(permissions: .allGranted)
        escapeFailureHarness.recordEscapeStartAction = true
        escapeFailureHarness.escapeStartResult = false
        let escapeCoordinator = escapeFailureHarness.makeCoordinator()
        await escapeCoordinator.startMirroring(displayID: escapeFailureHarness.externalDisplay.id)
        escapeFailureHarness.returnActions.removeAll()

        escapeCoordinator.handlePortalEntered(
            MirrorSurfacePortalEvent(location: CGPoint(x: 25, y: 75), renderRect: CGRect(x: 0, y: 0, width: 100, height: 100))
        )

        XCTAssertEqual(escapeCoordinator.session.state, .viewOnly)
        XCTAssertEqual(escapeFailureHarness.returnActions, [
            .portalGeometry,
            .startEscapeTap,
            .stopEscapeTap,
            .publishViewOnly
        ])

        let boundaryFailureHarness = AppCoordinatorHarness(permissions: .allGranted)
        boundaryFailureHarness.recordEscapeStartAction = true
        boundaryFailureHarness.boundaryStartResult = false
        let boundaryCoordinator = boundaryFailureHarness.makeCoordinator()
        await boundaryCoordinator.startMirroring(displayID: boundaryFailureHarness.externalDisplay.id)
        boundaryFailureHarness.returnActions.removeAll()

        boundaryCoordinator.handlePortalEntered(
            MirrorSurfacePortalEvent(location: CGPoint(x: 25, y: 75), renderRect: CGRect(x: 0, y: 0, width: 100, height: 100))
        )

        XCTAssertEqual(boundaryCoordinator.session.state, .viewOnly)
        XCTAssertEqual(boundaryFailureHarness.returnActions, [
            .portalGeometry,
            .startEscapeTap,
            .startBoundaryTap(boundaryFailureHarness.externalDisplay.coreGraphicsFrame),
            .stopBoundaryTap,
            .stopEscapeTap,
            .publishViewOnly
        ])

        let warpFailureHarness = AppCoordinatorHarness(permissions: .allGranted)
        warpFailureHarness.recordEscapeStartAction = true
        warpFailureHarness.warpResults = [false]
        let warpCoordinator = warpFailureHarness.makeCoordinator()
        await warpCoordinator.startMirroring(displayID: warpFailureHarness.externalDisplay.id)
        warpFailureHarness.returnActions.removeAll()

        warpCoordinator.handlePortalEntered(
            MirrorSurfacePortalEvent(location: CGPoint(x: 25, y: 75), renderRect: CGRect(x: 0, y: 0, width: 100, height: 100))
        )

        XCTAssertEqual(warpCoordinator.session.state, .viewOnly)
        XCTAssertEqual(warpFailureHarness.returnActions, [
            .portalGeometry,
            .startEscapeTap,
            .startBoundaryTap(warpFailureHarness.externalDisplay.coreGraphicsFrame),
            .warp(CGPoint(x: 1250, y: 750)),
            .stopBoundaryTap,
            .stopEscapeTap,
            .publishViewOnly
        ])
    }

    func testBoundaryReturnUsesCurrentGeometryRatioAndOrderedCleanup() async {
        let harness = AppCoordinatorHarness(permissions: .allGranted)
        let coordinator = harness.makeCoordinator()
        await coordinator.startMirroring(displayID: harness.externalDisplay.id)
        coordinator.handlePortalEntered(
            MirrorSurfacePortalEvent(location: CGPoint(x: 25, y: 75), renderRect: CGRect(x: 0, y: 0, width: 100, height: 100))
        )
        harness.portalGeometry = PointerPortalViewerGeometry(
            captureFrame: CGRect(x: 400, y: 500, width: 300, height: 200),
            surfaceFrame: CGRect(x: 350, y: 450, width: 400, height: 300),
            contentFrame: CGRect(x: 350, y: 450, width: 400, height: 360)
        )
        harness.returnActions.removeAll()

        harness.boundaryExitHandler?(PointerPortalExit(edge: .bottom, position: 0.25))

        XCTAssertEqual(coordinator.session.state, .viewOnly)
        XCTAssertEqual(harness.returnActions, [
            .cancelInput,
            .prepareBoundaryReturn,
            .stopEscapeTap,
            .portalGeometry,
            .warp(CGPoint(x: 475, y: 702)),
            .activateApp,
            .bringViewerForward,
            .publishViewOnly,
            .showReturnHUD
        ])
    }

    func testBoundaryReturnDoesNotStopTapImmediatelyWhilePrepareIsDrainingOrFailed() async {
        for preparationResult in [PointerBoundaryReturnPreparationResult.draining, .failed] {
            let harness = AppCoordinatorHarness(permissions: .allGranted)
            harness.boundaryPrepareResult = preparationResult
            let coordinator = harness.makeCoordinator()
            await coordinator.startMirroring(displayID: harness.externalDisplay.id)
            coordinator.handlePortalEntered(
                MirrorSurfacePortalEvent(location: CGPoint(x: 25, y: 75), renderRect: CGRect(x: 0, y: 0, width: 100, height: 100))
            )
            harness.returnActions.removeAll()

            harness.boundaryExitHandler?(PointerPortalExit(edge: .bottom, position: 0.25))

            XCTAssertEqual(coordinator.session.state, .viewOnly)
            XCTAssertTrue(harness.returnActions.contains(.prepareBoundaryReturn))
            XCTAssertFalse(harness.returnActions.contains(.stopBoundaryTap))
        }
    }

    func testBoundaryReturnRetryPreservesBoundaryTargetAfterWarpFailure() async {
        let harness = AppCoordinatorHarness(permissions: .allGranted)
        harness.warpResults = [true, false, true]
        let coordinator = harness.makeCoordinator()
        await coordinator.startMirroring(displayID: harness.externalDisplay.id)
        coordinator.handlePortalEntered(
            MirrorSurfacePortalEvent(location: CGPoint(x: 25, y: 75), renderRect: CGRect(x: 0, y: 0, width: 100, height: 100))
        )
        harness.portalGeometry = PointerPortalViewerGeometry(
            captureFrame: CGRect(x: 400, y: 500, width: 300, height: 200),
            surfaceFrame: CGRect(x: 400, y: 500, width: 300, height: 200),
            contentFrame: CGRect(x: 400, y: 500, width: 300, height: 260)
        )
        harness.returnActions.removeAll()

        harness.boundaryExitHandler?(PointerPortalExit(edge: .bottom, position: 0.25))

        XCTAssertEqual(coordinator.session.state, .returning)
        XCTAssertTrue(harness.returnActions.contains(.warp(CGPoint(x: 475, y: 702))))

        harness.portalGeometry = PointerPortalViewerGeometry(
            captureFrame: CGRect(x: 100, y: 200, width: 300, height: 200),
            surfaceFrame: CGRect(x: 100, y: 200, width: 300, height: 200),
            contentFrame: CGRect(x: 100, y: 200, width: 300, height: 260)
        )
        harness.returnActions.removeAll()

        await coordinator.returnToViewer(reason: .escapeHold)

        XCTAssertEqual(coordinator.session.state, .viewOnly)
        XCTAssertTrue(harness.returnActions.contains(.warp(CGPoint(x: 175, y: 402))))
        XCTAssertFalse(harness.returnActions.contains(.warp(CGPoint(x: 400, y: 750))))
    }

    func testEscapeAfterPortalHoverReturnsToSavedViewerEntryPoint() async {
        let harness = AppCoordinatorHarness(permissions: .allGranted)
        let coordinator = harness.makeCoordinator()
        await coordinator.startMirroring(displayID: harness.externalDisplay.id)
        coordinator.handlePortalEntered(
            MirrorSurfacePortalEvent(location: CGPoint(x: 25, y: 75), renderRect: CGRect(x: 0, y: 0, width: 100, height: 100))
        )
        harness.returnActions.removeAll()

        await coordinator.returnToViewer(reason: .escapeHold)

        XCTAssertEqual(coordinator.session.state, .viewOnly)
        XCTAssertEqual(harness.returnActions, [
            .cancelInput,
            .prepareBoundaryReturn,
            .stopEscapeTap,
            .captureViewerFrame,
            .warp(CGPoint(x: 400, y: 750)),
            .activateApp,
            .bringViewerForward,
            .publishViewOnly,
            .showReturnHUD
        ])
    }

    func testPortalDuplicateEntryAndExitDisarmAreIdempotent() async {
        let harness = AppCoordinatorHarness(permissions: .allGranted)
        let coordinator = harness.makeCoordinator()
        await coordinator.startMirroring(displayID: harness.externalDisplay.id)
        coordinator.handlePortalEntered(
            MirrorSurfacePortalEvent(location: CGPoint(x: 25, y: 75), renderRect: CGRect(x: 0, y: 0, width: 100, height: 100))
        )
        coordinator.handlePortalEntered(
            MirrorSurfacePortalEvent(location: CGPoint(x: 75, y: 25), renderRect: CGRect(x: 0, y: 0, width: 100, height: 100))
        )

        XCTAssertEqual(harness.returnActions.filter { action in
            if case .startBoundaryTap = action { return true }
            return false
        }.count, 1)

        harness.portalGeometry = nil
        harness.returnActions.removeAll()
        harness.boundaryExitHandler?(PointerPortalExit(edge: .right, position: 0.5))
        XCTAssertEqual(coordinator.session.state, .viewOnly)
        XCTAssertTrue(harness.returnActions.contains(.warp(CGPoint(x: 698, y: 830))))

        harness.returnActions.removeAll()
        coordinator.handlePortalEntered(
            MirrorSurfacePortalEvent(location: CGPoint(x: 25, y: 75), renderRect: CGRect(x: 0, y: 0, width: 100, height: 100))
        )
        XCTAssertEqual(harness.returnActions, [])

        coordinator.handlePortalExited()
        coordinator.handlePortalEntered(
            MirrorSurfacePortalEvent(location: CGPoint(x: 25, y: 75), renderRect: CGRect(x: 0, y: 0, width: 100, height: 100))
        )
        XCTAssertEqual(harness.returnActions, [.portalGeometry, .publishViewOnly])
    }

    func testProductionPortalCallbacksReachCoordinator() async {
        let harness = AppCoordinatorHarness(permissions: .allGranted)
        let coordinator = harness.makeCoordinator()
        await coordinator.startMirroring(displayID: harness.externalDisplay.id)
        harness.returnActions.removeAll()

        harness.viewerCallbacks?.onPortalEntered(
            MirrorSurfacePortalEvent(location: CGPoint(x: 25, y: 75), renderRect: CGRect(x: 0, y: 0, width: 100, height: 100))
        )

        XCTAssertEqual(coordinator.session.state, .controllingExternal)
        XCTAssertEqual(harness.hudEvents, [.control])

        harness.portalGeometry = nil
        harness.returnActions.removeAll()
        harness.boundaryExitHandler?(PointerPortalExit(edge: .right, position: 0.5))
        harness.returnActions.removeAll()
        harness.viewerCallbacks?.onPortalEntered(
            MirrorSurfacePortalEvent(location: CGPoint(x: 25, y: 75), renderRect: CGRect(x: 0, y: 0, width: 100, height: 100))
        )
        XCTAssertEqual(harness.returnActions, [])

        harness.viewerCallbacks?.onPortalExited(
            MirrorSurfacePortalEvent(location: CGPoint(x: -1, y: -1), renderRect: CGRect(x: 0, y: 0, width: 100, height: 100))
        )
        harness.viewerCallbacks?.onPortalEntered(
            MirrorSurfacePortalEvent(location: CGPoint(x: 25, y: 75), renderRect: CGRect(x: 0, y: 0, width: 100, height: 100))
        )
        XCTAssertEqual(harness.returnActions, [.portalGeometry, .publishViewOnly])
    }
}

private final class AppCoordinatorHarness {
    let externalDisplay = DisplayInfo(
        id: 12,
        name: "External",
        coreGraphicsFrame: CGRect(x: 1000, y: 0, width: 1000, height: 1000),
        appKitFrame: CGRect(x: 1000, y: 0, width: 1000, height: 1000),
        pixelSize: CGSize(width: 1000, height: 1000),
        scale: 1,
        isBuiltIn: false
    )
    var viewerFrame: CGRect? = CGRect(x: 300, y: 600, width: 300, height: 200)
    let returnPoint = CGPoint(x: 321, y: 654)
    var permissions: PermissionSnapshot
    var refreshDisplayResults: [[DisplayInfo]]
    var refreshDisplayError: Error?
    var refreshCount = 0
    var permissionRefreshCount = 0
    var screenRecordingRequestCount = 0
    var postEventRequestCount = 0
    var listenEventRequestCount = 0
    var screenRecordingRequestResults: [Bool] = []
    var postEventRequestResults: [Bool] = []
    var listenEventRequestResults: [Bool] = []
    var openedPermissionSettings: [PermissionSettingsPane] = []
    var captureStartFailures: [Error] = []
    var beginResultOverride: InputResult?
    var cancelResults: [InputResult] = []
    var warpResults: [Bool] = []
    var boundaryStartResult = true
    var boundaryPrepareResult: PointerBoundaryReturnPreparationResult = .tornDown
    var boundaryExitHandler: ((PointerPortalExit) -> Void)?
    var viewerCallbacks: AppCoordinator.ViewerCallbacks?
    var portalGeometry: PointerPortalViewerGeometry?
    var escapeStartResult = true
    var captureStartedDisplayIDs: [CGDirectDisplayID] = []
    var openedViewerModes: [ViewerMode] = []
    var viewerModes: [ViewerMode] = []
    var escapeStartCount = 0
    var escapeStopCount = 0
    var recordEscapeStartAction = false
    var recordPortalEntryOrder = false
    var beginInputCount = 0
    var stopCaptureCount = 0
    var closeCount = 0
    var hudEvents: [HUDEvent] = []
    var returnActions: [ReturnAction] = []

    init(permissions: PermissionSnapshot) {
        self.permissions = permissions
        self.refreshDisplayResults = [[externalDisplay]]
        self.portalGeometry = PointerPortalViewerGeometry(
            captureFrame: CGRect(x: 300, y: 600, width: 400, height: 200),
            surfaceFrame: CGRect(x: 300, y: 600, width: 400, height: 200),
            contentFrame: CGRect(x: 300, y: 600, width: 400, height: 260)
        )
    }

    @MainActor
    func makeCoordinator() -> AppCoordinator {
        AppCoordinator(
            dependencies: AppCoordinator.Dependencies(
                refreshPermissions: { [self] in
                    permissionRefreshCount += 1
                    if recordPortalEntryOrder {
                        returnActions.append(.permissionRefresh)
                    }
                    return permissions
                },
                requestScreenRecording: { [self] in
                    screenRecordingRequestCount += 1
                    guard !screenRecordingRequestResults.isEmpty else {
                        return true
                    }

                    return screenRecordingRequestResults.removeFirst()
                },
                requestPostEvents: { [self] in
                    postEventRequestCount += 1
                    guard !postEventRequestResults.isEmpty else {
                        return true
                    }

                    return postEventRequestResults.removeFirst()
                },
                requestListenEvents: { [self] in
                    listenEventRequestCount += 1
                    guard !listenEventRequestResults.isEmpty else {
                        return true
                    }

                    return listenEventRequestResults.removeFirst()
                },
                openPermissionSettings: { [self] pane in
                    openedPermissionSettings.append(pane)
                },
                refreshDisplays: { [self] in
                    refreshCount += 1
                    if let refreshDisplayError {
                        throw refreshDisplayError
                    }
                    guard refreshDisplayResults.count > 1 else {
                        return refreshDisplayResults[0]
                    }

                    return refreshDisplayResults.removeFirst()
                },
                startCapture: { [self] display, _ in
                    captureStartedDisplayIDs.append(display.id)
                    if !captureStartFailures.isEmpty {
                        throw captureStartFailures.removeFirst()
                    }
                },
                stopCapture: { [self] in
                    stopCaptureCount += 1
                    returnActions.append(.stopCapture)
                },
                makeViewer: { [self] display, callbacks in
                    viewerCallbacks = callbacks
                    let model = ViewerViewModel(
                        selectedDisplay: display,
                        hud: TransitionHUDController(),
                        presenter: SurfacePresenter(),
                        permissions: permissions,
                        onPointerDown: callbacks.onPointerDown,
                        onPointerDragged: callbacks.onPointerDragged,
                        onPointerUp: callbacks.onPointerUp,
                        onScroll: callbacks.onScroll,
                        onPortalEntered: callbacks.onPortalEntered,
                        onPortalExited: callbacks.onPortalExited,
                        onModeIntent: callbacks.onModeIntent,
                        onAlwaysOnTopChange: callbacks.onAlwaysOnTopChange,
                        onStop: callbacks.onStop
                    )
                    return AppCoordinator.ViewerAdapter(
                        model: model,
                        open: { [self] in openedViewerModes.append(model.mode) },
                        close: { [self] in closeCount += 1 },
                        bringForward: { [self] in returnActions.append(.bringViewerForward) },
                        setAlwaysOnTop: { _ in },
                        captureGlobalFrame: { [self] in
                            returnActions.append(.captureViewerFrame)
                            return viewerFrame
                        },
                        pointerPortalGeometry: { [self] in
                            returnActions.append(.portalGeometry)
                            return portalGeometry
                        }
                    )
                },
                beginInput: { [self] _, _, point, renderRect, displayFrame in
                    beginInputCount += 1
                    if let beginResultOverride {
                        return beginResultOverride
                    }

                    return InputEventManager(poster: HarnessPoster(currentLocation: returnPoint)).begin(
                        button: .left,
                        clickCount: 1,
                        viewerPoint: point,
                        renderRect: renderRect,
                        displayFrame: displayFrame
                    )
                },
                dragInput: { _, _, _ in .continued },
                endInput: { _, _, _ in .ended },
                scrollInput: { _, _, _, _, _ in .continued },
                cancelInput: { [self] in
                    returnActions.append(.cancelInput)
                    if !cancelResults.isEmpty {
                        return cancelResults.removeFirst()
                    }

                    return .ended
                },
                startEscapeTap: { [self] in
                    escapeStartCount += 1
                    if recordEscapeStartAction {
                        returnActions.append(.startEscapeTap)
                    }
                    return escapeStartResult
                },
                stopEscapeTap: { [self] in
                    escapeStopCount += 1
                    returnActions.append(.stopEscapeTap)
                },
                startPointerBoundary: { [self] displayFrame, onExit, _ in
                    returnActions.append(.startBoundaryTap(displayFrame))
                    boundaryExitHandler = onExit
                    return boundaryStartResult
                },
                preparePointerBoundaryReturn: { [self] in
                    returnActions.append(.prepareBoundaryReturn)
                    return boundaryPrepareResult
                },
                stopPointerBoundary: { [self] in
                    returnActions.append(.stopBoundaryTap)
                    boundaryExitHandler = nil
                },
                warpCursor: { [self] point in
                    returnActions.append(.warp(point))
                    guard !warpResults.isEmpty else {
                        return true
                    }

                    return warpResults.removeFirst()
                },
                activateApp: { [self] in returnActions.append(.activateApp) },
                showControlHUD: { [self] in
                    hudEvents.append(.control)
                    if recordPortalEntryOrder {
                        returnActions.append(.showControlHUD)
                    }
                },
                showReturnHUD: { [self] in
                    hudEvents.append(.return)
                    returnActions.append(.showReturnHUD)
                },
                publishViewerMode: { [self] mode in
                    viewerModes.append(mode)
                    if recordPortalEntryOrder, mode == .interactive {
                        returnActions.append(.publishInteractive)
                    }
                    if mode == .viewOnly {
                        returnActions.append(.publishViewOnly)
                    }
                }
            )
        )
    }

    enum HUDEvent: Equatable {
        case control
        case `return`
    }

    enum ReturnAction: Equatable {
        case cancelInput
        case permissionRefresh
        case stopEscapeTap
        case startEscapeTap
        case startBoundaryTap(CGRect)
        case prepareBoundaryReturn
        case stopBoundaryTap
        case portalGeometry
        case captureViewerFrame
        case warp(CGPoint)
        case publishInteractive
        case showControlHUD
        case activateApp
        case bringViewerForward
        case publishViewOnly
        case showReturnHUD
        case stopCapture
        case terminationReply
    }
}

private enum HarnessError: LocalizedError {
    case captureFailed
    case displayRefreshDenied

    var errorDescription: String? {
        switch self {
        case .captureFailed:
            "capture failed"
        case .displayRefreshDenied:
            "raw TCC denial"
        }
    }
}

private final class HarnessPoster: PointerEventPosting {
    let currentLocation: CGPoint?

    init(currentLocation: CGPoint?) {
        self.currentLocation = currentLocation
    }

    func warp(to location: CGPoint) -> Bool { true }
    func postMouse(_ kind: PointerEvent.Kind, button: PointerButton, at location: CGPoint, clickCount: Int) -> Bool { true }
    func postScroll(deltaX: Int32, deltaY: Int32, at location: CGPoint) -> Bool { true }
}

private extension PermissionSnapshot {
    static let allGranted = PermissionSnapshot(
        screenRecording: true,
        postEvents: true,
        listenEvents: true,
        eventTapUsable: true
    )
}
