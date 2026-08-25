@testable import ExternalDisplayViewerCore
import XCTest

@MainActor
final class TransitionHUDControllerTests: XCTestCase {
    func testReturnHUDReplacesControlHUDAndExpires() async throws {
        let hud = TransitionHUDController()

        hud.showControlTransfer(duration: .milliseconds(50))
        XCTAssertEqual(hud.message, TransitionHUDController.controlMessage)
        hud.showReturn(duration: .milliseconds(10))
        XCTAssertEqual(hud.message, TransitionHUDController.returnMessage)
        try await Task.sleep(for: .milliseconds(30))

        XCTAssertNil(hud.message)
    }

    func testEarlierExpiryCannotHideNewerMessage() async throws {
        let hud = TransitionHUDController()

        hud.showControlTransfer(duration: .milliseconds(10))
        try await Task.sleep(for: .milliseconds(5))
        hud.showReturn(duration: .milliseconds(50))
        try await Task.sleep(for: .milliseconds(20))

        XCTAssertEqual(hud.message, TransitionHUDController.returnMessage)
    }

    func testDefaultDurationsComeFromInteractionContract() {
        XCTAssertEqual(InteractionContract.controlHUDDuration, .milliseconds(1500))
        XCTAssertEqual(InteractionContract.returnHUDDuration, .milliseconds(1200))
    }

    func testMessageStaysMountedDuringFadeOutBeforeRemoval() async throws {
        let hud = TransitionHUDController(fadeDuration: .milliseconds(20))

        hud.showReturn(duration: .milliseconds(50))
        try await Task.sleep(for: .milliseconds(35))
        XCTAssertEqual(hud.message, TransitionHUDController.returnMessage)
        XCTAssertEqual(hud.opacity, 0)
        try await Task.sleep(for: .milliseconds(30))

        XCTAssertNil(hud.message)
    }

    func testReplacementFadeCannotHideNewerMessage() async throws {
        let hud = TransitionHUDController(fadeDuration: .milliseconds(20))

        hud.showControlTransfer(duration: .milliseconds(30))
        try await Task.sleep(for: .milliseconds(20))
        hud.showReturn(duration: .milliseconds(50))
        try await Task.sleep(for: .milliseconds(20))

        XCTAssertEqual(hud.message, TransitionHUDController.returnMessage)
        XCTAssertEqual(hud.opacity, 1)
    }
}

@MainActor
final class MirrorSurfaceScrollAccumulatorTests: XCTestCase {
    func testFractionalTrackpadDeltasAccumulateUntilWholePixels() {
        var accumulator = MirrorSurfaceScrollAccumulator()

        XCTAssertNil(accumulator.emit(deltaX: 0.25, deltaY: -0.4))
        XCTAssertNil(accumulator.emit(deltaX: 0.25, deltaY: -0.4))
        XCTAssertEqual(accumulator.emit(deltaX: 0.25, deltaY: -0.4), MirrorSurfaceScrollDelta(deltaX: 0, deltaY: -1))
        XCTAssertEqual(accumulator.emit(deltaX: 0.25, deltaY: -0.4), MirrorSurfaceScrollDelta(deltaX: 1, deltaY: 0))
    }

    func testSignChangeResetsAxisResiduals() {
        var accumulator = MirrorSurfaceScrollAccumulator()

        XCTAssertNil(accumulator.emit(deltaX: 0.75, deltaY: 0))

        XCTAssertNil(accumulator.emit(deltaX: -0.4, deltaY: 0))
        XCTAssertEqual(accumulator.emit(deltaX: -0.6, deltaY: 0), MirrorSurfaceScrollDelta(deltaX: -1, deltaY: 0))
    }

    func testZeroEmissionIsNotForwardedAndResetDropsStaleMotion() {
        var accumulator = MirrorSurfaceScrollAccumulator()

        XCTAssertNil(accumulator.emit(deltaX: 0.75, deltaY: 0.75))
        accumulator.reset()

        XCTAssertNil(accumulator.emit(deltaX: 0.25, deltaY: 0.25))
    }

    func testLargeDeltasClampDeterministically() {
        var accumulator = MirrorSurfaceScrollAccumulator()

        XCTAssertEqual(
            accumulator.emit(deltaX: CGFloat(Int32.max) + 1000, deltaY: CGFloat(Int32.min) - 1000),
            MirrorSurfaceScrollDelta(deltaX: Int32.max, deltaY: Int32.min)
        )
        XCTAssertNil(accumulator.emit(deltaX: 0, deltaY: 0))
    }
}

@MainActor
final class ViewerRootLayoutTests: XCTestCase {
    func testHUDFrameIsTopCenteredInsideVerticalLetterboxedRenderRect() {
        let renderRect = ViewerRootLayout.renderRect(
            containerSize: CGSize(width: 1000, height: 800),
            sourceAspectRatio: 16.0 / 9.0
        )

        let hudFrame = ViewerRootLayout.hudFrame(
            in: renderRect,
            preferredWidth: 420,
            horizontalPadding: 16,
            topPadding: 14,
            height: 48
        )

        XCTAssertEqual(renderRect.origin.y, 118.75, accuracy: 0.001)
        XCTAssertEqual(hudFrame.midX, renderRect.midX, accuracy: 0.001)
        XCTAssertEqual(hudFrame.minY, renderRect.minY + 14, accuracy: 0.001)
        XCTAssertLessThanOrEqual(hudFrame.width, renderRect.width - 32)
    }

    func testHUDFrameIsConstrainedToNarrowRenderRect() {
        let renderRect = CGRect(x: 220, y: 0, width: 160, height: 480)

        let hudFrame = ViewerRootLayout.hudFrame(
            in: renderRect,
            preferredWidth: 420,
            horizontalPadding: 16,
            topPadding: 14,
            height: 48
        )

        XCTAssertEqual(hudFrame.minX, renderRect.minX + 16, accuracy: 0.001)
        XCTAssertEqual(hudFrame.width, 128, accuracy: 0.001)
    }

    func testPreviewPatternUsesDeterministicAspectFitRenderRect() {
        let renderRect = ViewerRootLayout.previewRenderRect(containerSize: CGSize(width: 800, height: 800))

        XCTAssertEqual(renderRect, CGRect(x: 0, y: 175, width: 800, height: 450))
    }
}
