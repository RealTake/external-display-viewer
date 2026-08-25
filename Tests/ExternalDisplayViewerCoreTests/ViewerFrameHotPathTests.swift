@testable import ExternalDisplayViewerCore
import AppKit
import Combine
import CoreVideo
import IOSurface
import XCTest

@MainActor
final class ViewerFrameHotPathTests: XCTestCase {
    func testUpdateFramePresentsEveryFrameAndPublishesOnlyWhenSourceSizeChanges() throws {
        let presenter = SurfacePresenter()
        let model = ViewerViewModel(
            selectedDisplay: Self.display,
            hud: TransitionHUDController(),
            presenter: presenter
        )
        var changeCount = 0
        let cancellable = model.objectWillChange.sink { _ in changeCount += 1 }

        let firstFrame = try Self.frame(width: 100, height: 50, displayTime: 1)
        let secondFrame = try Self.frame(width: 100, height: 50, displayTime: 2)
        let resizedFrame = try Self.frame(width: 120, height: 50, displayTime: 3)

        model.updateFrame(firstFrame)
        let changesAfterFirstSize = changeCount
        model.updateFrame(secondFrame)
        model.updateFrame(resizedFrame)

        XCTAssertEqual(presenter.currentFrame?.displayTime, 3)
        XCTAssertEqual(changesAfterFirstSize, 1)
        XCTAssertEqual(changeCount, 2)
        cancellable.cancel()
    }

    func testPresenterDoesNotRequestLayoutForSameSourceSizeContentUpdate() throws {
        let presenter = SurfacePresenter()
        let view = MirrorSurfaceView(frame: CGRect(x: 0, y: 0, width: 200, height: 100))
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 200, height: 100),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = view
        let firstFrame = try Self.frame(width: 100, height: 50, displayTime: 1)
        let secondFrame = try Self.frame(width: 100, height: 50, displayTime: 2)

        presenter.attach(view)
        presenter.present(firstFrame)
        view.layoutSubtreeIfNeeded()
        view.needsLayout = false

        presenter.present(secondFrame)

        XCTAssertEqual(presenter.currentFrame?.displayTime, 2)
        XCTAssertFalse(view.needsLayout)
        withExtendedLifetime(window) {}
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

    private static func frame(width: Int, height: Int, displayTime: UInt64) throws -> CaptureFrame {
        try CaptureFrame(
            surface: surface(width: width, height: height),
            size: CGSize(width: width, height: height),
            displayTime: displayTime
        )
    }

    private static func surface(width: Int, height: Int) throws -> IOSurfaceRef {
        let bytesPerRow = width * 4
        let properties: [String: Any] = [
            kIOSurfaceWidth as String: width,
            kIOSurfaceHeight as String: height,
            kIOSurfacePixelFormat as String: UInt32(kCVPixelFormatType_32BGRA),
            kIOSurfaceBytesPerElement as String: 4,
            kIOSurfaceBytesPerRow as String: bytesPerRow,
            kIOSurfaceAllocSize as String: bytesPerRow * height
        ]

        guard let surface = IOSurfaceCreate(properties as CFDictionary) else {
            throw XCTSkip("IOSurfaceCreate unavailable in this test environment for \(width)x\(height), bytesPerRow=\(bytesPerRow), properties=\(properties)")
        }

        return surface
    }
}
