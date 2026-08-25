@testable import ExternalDisplayViewerCore
import AppKit
import XCTest

@MainActor
final class MirrorSurfacePortalTests: XCTestCase {
    func testTrackingAreaMatchesCurrentRenderRect() {
        let view = makeSurfaceView(size: CGSize(width: 200, height: 100), sourceSize: CGSize(width: 100, height: 100))

        XCTAssertEqual(view.currentRenderRect, CGRect(x: 50, y: 0, width: 100, height: 100))
        XCTAssertEqual(view.trackingAreas.count, 1)
        XCTAssertEqual(view.trackingAreas.first?.rect, view.currentRenderRect)
        XCTAssertTrue(view.trackingAreas.first?.options.contains(.mouseEnteredAndExited) == true)
        XCTAssertTrue(view.trackingAreas.first?.options.contains(.activeAlways) == true)
    }

    func testRelayoutReplacesTrackingAreaInsteadOfAccumulating() {
        let view = makeSurfaceView(size: CGSize(width: 200, height: 100), sourceSize: CGSize(width: 100, height: 100))
        let firstTrackingArea = view.trackingAreas.first

        view.setFrameSize(CGSize(width: 300, height: 100))
        view.layoutSubtreeIfNeeded()

        XCTAssertEqual(view.currentRenderRect, CGRect(x: 100, y: 0, width: 100, height: 100))
        XCTAssertEqual(view.trackingAreas.count, 1)
        XCTAssertEqual(view.trackingAreas.first?.rect, view.currentRenderRect)
        XCTAssertFalse(view.trackingAreas.first === firstTrackingArea)
    }

    func testZeroRenderRectRemovesTrackingArea() {
        let view = makeSurfaceView(size: CGSize(width: 200, height: 100), sourceSize: CGSize(width: 100, height: 100))

        view.sourceSize = .zero
        view.layoutSubtreeIfNeeded()

        XCTAssertEqual(view.currentRenderRect, .zero)
        XCTAssertTrue(view.trackingAreas.isEmpty)
    }

    func testEntryRejectsPressedMouseButtons() {
        let view = makeSurfaceView(size: CGSize(width: 200, height: 100), sourceSize: CGSize(width: 100, height: 100))
        var events: [MirrorSurfacePortalEvent] = []
        view.onPortalEntered = { events.append($0) }
        view.pressedMouseButtonsProvider = { 1 }

        view.mouseEntered(with: mouseEvent(at: CGPoint(x: 100, y: 50), in: view))

        XCTAssertTrue(events.isEmpty)
    }

    func testEntryRejectsLetterboxPoint() {
        let view = makeSurfaceView(size: CGSize(width: 200, height: 100), sourceSize: CGSize(width: 100, height: 100))
        var events: [MirrorSurfacePortalEvent] = []
        view.onPortalEntered = { events.append($0) }

        view.mouseEntered(with: mouseEvent(at: CGPoint(x: 25, y: 50), in: view))

        XCTAssertTrue(events.isEmpty)
    }

    func testEntryEmitsInsideRenderRect() {
        let view = makeSurfaceView(size: CGSize(width: 200, height: 100), sourceSize: CGSize(width: 100, height: 100))
        var events: [MirrorSurfacePortalEvent] = []
        view.onPortalEntered = { events.append($0) }

        view.mouseEntered(with: mouseEvent(at: CGPoint(x: 100, y: 50), in: view))

        XCTAssertEqual(
            events,
            [
                MirrorSurfacePortalEvent(
                    location: CGPoint(x: 100, y: 50),
                    renderRect: CGRect(x: 50, y: 0, width: 100, height: 100)
                )
            ]
        )
    }

    func testExitCallbackEmitsCurrentLocationAndRenderRect() {
        let view = makeSurfaceView(size: CGSize(width: 200, height: 100), sourceSize: CGSize(width: 100, height: 100))
        var events: [MirrorSurfacePortalEvent] = []
        view.onPortalExited = { events.append($0) }

        view.mouseExited(with: mouseEvent(at: CGPoint(x: 100, y: 50), in: view))

        XCTAssertEqual(
            events,
            [
                MirrorSurfacePortalEvent(
                    location: CGPoint(x: 100, y: 50),
                    renderRect: CGRect(x: 50, y: 0, width: 100, height: 100)
                )
            ]
        )
    }

    func testViewModelStoresPortalCallbacks() {
        var entered: [MirrorSurfacePortalEvent] = []
        var exited: [MirrorSurfacePortalEvent] = []
        let model = ViewerViewModel(
            selectedDisplay: Self.display,
            hud: TransitionHUDController(),
            presenter: SurfacePresenter(),
            onPortalEntered: { entered.append($0) },
            onPortalExited: { exited.append($0) }
        )
        let event = MirrorSurfacePortalEvent(location: CGPoint(x: 3, y: 4), renderRect: CGRect(x: 1, y: 2, width: 10, height: 20))

        model.onPortalEntered?(event)
        model.onPortalExited?(event)

        XCTAssertEqual(entered, [event])
        XCTAssertEqual(exited, [event])
    }

    func testPointerPortalGeometryConvertsAllFramesWithOneMainDisplayHeight() {
        let geometry = MirrorWindowController.pointerPortalGeometry(
            captureAppKitFrame: CGRect(x: -120, y: 140, width: 80, height: 40),
            surfaceAppKitFrame: CGRect(x: -160, y: 100, width: 200, height: 120),
            contentAppKitFrame: CGRect(x: -180, y: 80, width: 240, height: 170),
            mainDisplayHeight: 900
        )

        XCTAssertEqual(
            geometry,
            PointerPortalViewerGeometry(
                captureFrame: CGRect(x: -120, y: 720, width: 80, height: 40),
                surfaceFrame: CGRect(x: -160, y: 680, width: 200, height: 120),
                contentFrame: CGRect(x: -180, y: 650, width: 240, height: 170)
            )
        )
    }

    func testPointerPortalGeometryRejectsInvalidFrames() {
        let geometry = MirrorWindowController.pointerPortalGeometry(
            captureAppKitFrame: CGRect(x: 0, y: 0, width: 0, height: 40),
            surfaceAppKitFrame: CGRect(x: 0, y: 0, width: 200, height: 120),
            contentAppKitFrame: CGRect(x: 0, y: 0, width: 240, height: 170),
            mainDisplayHeight: 900
        )

        XCTAssertNil(geometry)
    }

    func testPointerPortalGeometryRejectsInvalidMainDisplayHeight() {
        [CGFloat.zero, -1, .nan, .infinity, -.infinity].forEach { mainDisplayHeight in
            let geometry = MirrorWindowController.pointerPortalGeometry(
                captureAppKitFrame: CGRect(x: -120, y: 140, width: 80, height: 40),
                surfaceAppKitFrame: CGRect(x: -160, y: 100, width: 200, height: 120),
                contentAppKitFrame: CGRect(x: -180, y: 80, width: 240, height: 170),
                mainDisplayHeight: mainDisplayHeight
            )

            XCTAssertNil(geometry, "mainDisplayHeight: \(mainDisplayHeight)")
        }
    }

    private func makeSurfaceView(size: CGSize, sourceSize: CGSize) -> MirrorSurfaceView {
        let view = MirrorSurfaceView(frame: CGRect(origin: .zero, size: size))
        let window = NSWindow(
            contentRect: CGRect(origin: .zero, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = view
        view.sourceSize = sourceSize
        view.layoutSubtreeIfNeeded()
        withExtendedLifetime(window) {}
        return view
    }

    private func mouseEvent(at localPoint: CGPoint, in view: MirrorSurfaceView) -> NSEvent {
        let windowPoint = view.convert(localPoint, to: nil)
        return NSEvent.mouseEvent(
            with: .mouseMoved,
            location: windowPoint,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: view.window?.windowNumber ?? 0,
            context: nil,
            eventNumber: 0,
            clickCount: 0,
            pressure: 0
        )!
    }

    private static let display = DisplayInfo(
        id: 2,
        name: "External",
        coreGraphicsFrame: CGRect(x: 1920, y: 0, width: 1920, height: 1080),
        appKitFrame: CGRect(x: 1920, y: 0, width: 1920, height: 1080),
        pixelSize: CGSize(width: 1920, height: 1080),
        scale: 1,
        isBuiltIn: false
    )
}
