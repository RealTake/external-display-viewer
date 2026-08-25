@testable import ExternalDisplayViewerCore
import XCTest

final class WindowOverlapPolicyTests: XCTestCase {
    func testAnyVisibleAppWindowIntersectionBlocksInteractive() {
        let source = CGRect(x: 1000, y: 0, width: 1000, height: 800)

        XCTAssertFalse(WindowOverlapPolicy.canEnableInteractive(
            appWindowFrames: [CGRect(x: 900, y: 100, width: 200, height: 200)],
            sourceAppKitFrame: source
        ))
        XCTAssertTrue(WindowOverlapPolicy.canEnableInteractive(
            appWindowFrames: [CGRect(x: 0, y: 0, width: 800, height: 800)],
            sourceAppKitFrame: source
        ))
    }

    func testContainmentBlocksInteractive() {
        let source = CGRect(x: 1000, y: 0, width: 1000, height: 800)

        XCTAssertFalse(WindowOverlapPolicy.canEnableInteractive(
            appWindowFrames: [CGRect(x: 1100, y: 100, width: 300, height: 300)],
            sourceAppKitFrame: source
        ))
    }

    func testTouchingEdgesDoesNotBlockInteractive() {
        let source = CGRect(x: 1000, y: 0, width: 1000, height: 800)

        XCTAssertTrue(WindowOverlapPolicy.canEnableInteractive(
            appWindowFrames: [
                CGRect(x: 800, y: 100, width: 200, height: 200),
                CGRect(x: 2000, y: 100, width: 300, height: 200),
                CGRect(x: 1200, y: 800, width: 300, height: 200)
            ],
            sourceAppKitFrame: source
        ))
    }

    func testEmptyAndInvalidFramesAreIgnored() {
        let source = CGRect(x: 1000, y: 0, width: 1000, height: 800)

        XCTAssertTrue(WindowOverlapPolicy.canEnableInteractive(
            appWindowFrames: [
                .zero,
                .null,
                CGRect(x: 1200, y: 100, width: 0, height: 200),
                CGRect(x: CGFloat.infinity, y: 100, width: 200, height: 200),
                CGRect(x: CGFloat.nan, y: 100, width: 200, height: 200)
            ],
            sourceAppKitFrame: source
        ))
        XCTAssertFalse(WindowOverlapPolicy.canEnableInteractive(
            appWindowFrames: [CGRect(x: 0, y: 0, width: 200, height: 200)],
            sourceAppKitFrame: CGRect(x: 0, y: 0, width: 0, height: 800)
        ))
    }
}

@MainActor
final class ViewerViewModelInteractionGateTests: XCTestCase {
    func testDefaultsToViewOnly() {
        let model = makeModel()

        XCTAssertEqual(model.mode, .viewOnly)
        XCTAssertFalse(model.isInteractive)
    }

    func testPermissionBlockReasonPriorityIsDeterministic() {
        let model = makeModel()

        model.updatePermissions(PermissionSnapshot(
            screenRecording: true,
            postEvents: false,
            listenEvents: false,
            eventTapUsable: false
        ))
        XCTAssertEqual(model.interactiveDisabledReason, "손쉬운 사용 권한이 필요합니다. 시스템 설정에서 이 앱의 제어 권한을 허용하세요.")

        model.updatePermissions(PermissionSnapshot(
            screenRecording: true,
            postEvents: true,
            listenEvents: false,
            eventTapUsable: false
        ))
        XCTAssertEqual(model.interactiveDisabledReason, "입력 모니터링 권한이 필요합니다. 시스템 설정에서 이 앱의 키 입력 감지를 허용하세요.")

        model.updatePermissions(PermissionSnapshot(
            screenRecording: true,
            postEvents: true,
            listenEvents: true,
            eventTapUsable: false
        ))
        XCTAssertEqual(model.interactiveDisabledReason, "ESC 복귀 감지를 시작할 수 없습니다. 권한을 다시 확인하거나 앱을 재실행하세요.")
    }

    func testOverlapBlocksInteractiveAfterPermissionsAreClear() {
        let model = makeModel()
        model.updatePermissions(.allGranted)

        model.updateOverlap(isOverlappingSource: true)

        XCTAssertFalse(model.canEnableInteractive)
        XCTAssertEqual(model.interactiveDisabledReason, "Interactive를 켜려면 Viewer 창을 소스 외부 디스플레이 밖으로 이동하세요.")
    }

    func testInteractiveRequestDoesNotEnableModeWhenGated() {
        var intents: [ViewerModeIntent] = []
        let model = makeModel(onModeIntent: { intents.append($0) })
        model.updatePermissions(PermissionSnapshot(
            screenRecording: true,
            postEvents: false,
            listenEvents: true,
            eventTapUsable: true
        ))

        model.requestMode(.interactive)

        XCTAssertEqual(model.mode, .viewOnly)
        XCTAssertFalse(model.isInteractive)
        XCTAssertTrue(intents.isEmpty)
    }

    func testInteractiveRequestEnablesModeAndCallsBackWhenAllowed() {
        var intents: [ViewerModeIntent] = []
        let model = makeModel(onModeIntent: { intents.append($0) })
        model.updatePermissions(.allGranted)
        model.updateOverlap(isOverlappingSource: false)

        model.requestMode(.interactive)

        XCTAssertEqual(model.mode, .viewOnly)
        XCTAssertFalse(model.isInteractive)
        XCTAssertEqual(intents, [.enableInteractive])
    }

    func testCoordinatorConfirmationPublishesInteractive() {
        let model = makeModel()
        model.updatePermissions(.allGranted)
        model.updateOverlap(isOverlappingSource: false)

        model.requestMode(.interactive)
        model.updateModeFromCoordinator(.interactive)

        XCTAssertEqual(model.mode, .interactive)
        XCTAssertTrue(model.isInteractive)
    }

    func testExplicitViewOnlyNotifiesCoordinatorOnceAndStopsForwarding() {
        var intents: [ViewerModeIntent] = []
        let model = makeModel(onModeIntent: { intents.append($0) })
        model.updatePermissions(.allGranted)
        model.updateOverlap(isOverlappingSource: false)
        model.updateModeFromCoordinator(.interactive)

        model.requestMode(.viewOnly)
        model.requestMode(.viewOnly)

        XCTAssertEqual(model.mode, .viewOnly)
        XCTAssertFalse(model.isInteractive)
        XCTAssertEqual(intents, [.disableInteractive])
    }

    func testForcedGateDowngradeNotifiesCoordinatorOnce() {
        var intents: [ViewerModeIntent] = []
        let model = makeModel(onModeIntent: { intents.append($0) })
        model.updatePermissions(.allGranted)
        model.updateOverlap(isOverlappingSource: false)
        model.updateModeFromCoordinator(.interactive)

        model.updateOverlap(isOverlappingSource: true)
        model.updatePermissions(PermissionSnapshot(
            screenRecording: true,
            postEvents: false,
            listenEvents: true,
            eventTapUsable: true
        ))

        XCTAssertEqual(model.mode, .viewOnly)
        XCTAssertFalse(model.isInteractive)
        XCTAssertEqual(intents, [.disableInteractive])
    }

    func testPendingInteractiveRequestDoesNotDuplicateEnableIntent() {
        var intents: [ViewerModeIntent] = []
        let model = makeModel(onModeIntent: { intents.append($0) })
        model.updatePermissions(.allGranted)
        model.updateOverlap(isOverlappingSource: false)

        model.requestMode(.interactive)
        model.requestMode(.interactive)

        XCTAssertEqual(model.mode, .viewOnly)
        XCTAssertEqual(intents, [.enableInteractive])
    }

    func testNativeWindowCloseRequestsStopAndKeepsWindowOpenForCoordinator() {
        var lifecycle = MirrorWindowLifecyclePolicy()

        let effect = lifecycle.nativeCloseRequested()

        XCTAssertEqual(effect, .requestStop)
        XCTAssertTrue(lifecycle.hasWindow)
    }

    func testDuplicateNativeWindowCloseDoesNotRequestStopAgain() {
        var lifecycle = MirrorWindowLifecyclePolicy()

        let first = lifecycle.nativeCloseRequested()
        let second = lifecycle.nativeCloseRequested()

        XCTAssertEqual(first, .requestStop)
        XCTAssertEqual(second, .ignore)
        XCTAssertTrue(lifecycle.hasWindow)
    }

    func testProgrammaticCloseClearsWindowWithoutRequestingStop() {
        var lifecycle = MirrorWindowLifecyclePolicy()

        let nativeEffect = lifecycle.nativeCloseRequested()
        let closeEffect = lifecycle.programmaticCloseCompleted()
        let secondCloseEffect = lifecycle.programmaticCloseCompleted()

        XCTAssertEqual(nativeEffect, .requestStop)
        XCTAssertEqual(closeEffect, .cleanupOnly)
        XCTAssertEqual(secondCloseEffect, .ignore)
        XCTAssertFalse(lifecycle.hasWindow)
    }

    private func makeModel(onModeIntent: @escaping @MainActor (ViewerModeIntent) -> Void = { _ in }) -> ViewerViewModel {
        ViewerViewModel(
            selectedDisplay: DisplayInfo(
                id: 2,
                name: "External",
                coreGraphicsFrame: CGRect(x: 1920, y: 0, width: 1920, height: 1080),
                appKitFrame: CGRect(x: 1920, y: 0, width: 1920, height: 1080),
                pixelSize: CGSize(width: 1920, height: 1080),
                scale: 1,
                isBuiltIn: false
            ),
            hud: TransitionHUDController(),
            presenter: SurfacePresenter(),
            onModeIntent: onModeIntent
        )
    }
}

private extension PermissionSnapshot {
    static let allGranted = PermissionSnapshot(
        screenRecording: true,
        postEvents: true,
        listenEvents: true,
        eventTapUsable: true
    )
}
