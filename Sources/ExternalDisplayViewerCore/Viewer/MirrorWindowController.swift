import AppKit
import SwiftUI

public enum MirrorWindowCloseEffect: Equatable, Sendable {
    case ignore
    case requestStop
    case cleanupOnly
}

public struct MirrorWindowLifecyclePolicy: Equatable, Sendable {
    public private(set) var hasWindow: Bool
    private var hasRequestedStopForNativeClose = false

    public init(hasWindow: Bool = true) {
        self.hasWindow = hasWindow
    }

    public mutating func windowOpened() {
        hasWindow = true
        hasRequestedStopForNativeClose = false
    }

    public mutating func nativeCloseRequested() -> MirrorWindowCloseEffect {
        guard hasWindow, !hasRequestedStopForNativeClose else {
            return .ignore
        }

        hasRequestedStopForNativeClose = true
        return .requestStop
    }

    public mutating func programmaticCloseCompleted() -> MirrorWindowCloseEffect {
        guard hasWindow else {
            return .ignore
        }

        hasWindow = false
        hasRequestedStopForNativeClose = false
        return .cleanupOnly
    }
}

@MainActor
public final class MirrorWindowController: NSObject, NSWindowDelegate {
    public typealias OverlapCallback = @MainActor (Bool) -> Void

    private let viewModel: ViewerViewModel
    private let onOverlapChanged: OverlapCallback?
    private var window: NSWindow?
    private var lifecycle = MirrorWindowLifecyclePolicy(hasWindow: false)
    private var isRejectingSourceFullScreen = false

    public init(
        viewModel: ViewerViewModel,
        onOverlapChanged: OverlapCallback? = nil
    ) {
        self.viewModel = viewModel
        self.onOverlapChanged = onOverlapChanged
        super.init()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    public func open(onPreferredScreen preferredScreen: NSScreen?) {
        if window != nil {
            bringForward()
            updateOverlap()
            return
        }

        let screen = preferredScreen ?? NSScreen.main ?? NSScreen.screens.first
        let initialFrame = Self.initialFrame(on: screen)
        let window = NSWindow(
            contentRect: initialFrame,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false,
            screen: screen
        )
        window.title = "External Display Viewer"
        window.collectionBehavior = [.managed, .fullScreenPrimary]
        window.contentMinSize = CGSize(width: 640, height: 420)
        window.delegate = self
        window.contentView = NSHostingView(rootView: ViewerRootView(model: viewModel))
        window.setFrame(Self.constrainedFrame(initialFrame, on: screen), display: false)

        self.window = window
        lifecycle.windowOpened()
        installObservers(for: window)
        bringForward()
        updateOverlap()
    }

    public func bringForward() {
        guard let window else {
            return
        }

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    public func setAlwaysOnTop(_ isAlwaysOnTop: Bool) {
        window?.level = isAlwaysOnTop ? .floating : .normal
    }

    public func close() {
        guard let window else {
            return
        }

        guard lifecycle.programmaticCloseCompleted() == .cleanupOnly else {
            self.window = nil
            return
        }

        removeObservers()
        window.delegate = nil
        window.orderOut(nil)
        window.close()
        self.window = nil
        viewModel.updateOverlap(isOverlappingSource: false)
        onOverlapChanged?(false)
    }

    public func windowShouldClose(_ sender: NSWindow) -> Bool {
        switch lifecycle.nativeCloseRequested() {
        case .requestStop:
            viewModel.stop()
            return false
        case .ignore, .cleanupOnly:
            return false
        }
    }

    public func captureAppKitGlobalFrame() -> CGRect? {
        guard
            let window,
            let surfaceView = Self.findMirrorSurfaceView(in: window.contentView)
        else {
            return nil
        }

        surfaceView.layoutSubtreeIfNeeded()

        guard
            surfaceView.currentRenderRect.width > 0,
            surfaceView.currentRenderRect.height > 0
        else {
            return nil
        }

        let windowRect = surfaceView.convert(surfaceView.currentRenderRect, to: nil)
        return window.convertToScreen(windowRect)
    }

    public func captureGlobalFrame() -> CGRect? {
        guard let appKitFrame = captureAppKitGlobalFrame() else {
            return nil
        }

        return ScreenCoordinateConverter.coreGraphicsGlobalRect(
            appKitGlobalRect: appKitFrame,
            mainDisplayHeight: Self.mainDisplayHeight()
        )
    }

    public func pointerPortalGeometry() -> PointerPortalViewerGeometry? {
        guard
            let window,
            let contentView = window.contentView,
            let surfaceView = Self.findMirrorSurfaceView(in: contentView)
        else {
            return nil
        }

        surfaceView.layoutSubtreeIfNeeded()

        let captureWindowRect = surfaceView.convert(surfaceView.currentRenderRect, to: nil)
        let surfaceWindowRect = surfaceView.convert(surfaceView.bounds, to: nil)
        let contentWindowRect = contentView.convert(contentView.bounds, to: nil)

        return Self.pointerPortalGeometry(
            captureAppKitFrame: window.convertToScreen(captureWindowRect),
            surfaceAppKitFrame: window.convertToScreen(surfaceWindowRect),
            contentAppKitFrame: window.convertToScreen(contentWindowRect),
            mainDisplayHeight: Self.mainDisplayHeight()
        )
    }

    static func pointerPortalGeometry(
        captureAppKitFrame: CGRect,
        surfaceAppKitFrame: CGRect,
        contentAppKitFrame: CGRect,
        mainDisplayHeight: CGFloat
    ) -> PointerPortalViewerGeometry? {
        guard mainDisplayHeight.isFinite, mainDisplayHeight > 0 else {
            return nil
        }

        let geometry = PointerPortalViewerGeometry(
            captureFrame: ScreenCoordinateConverter.coreGraphicsGlobalRect(
                appKitGlobalRect: captureAppKitFrame,
                mainDisplayHeight: mainDisplayHeight
            ),
            surfaceFrame: ScreenCoordinateConverter.coreGraphicsGlobalRect(
                appKitGlobalRect: surfaceAppKitFrame,
                mainDisplayHeight: mainDisplayHeight
            ),
            contentFrame: ScreenCoordinateConverter.coreGraphicsGlobalRect(
                appKitGlobalRect: contentAppKitFrame,
                mainDisplayHeight: mainDisplayHeight
            )
        )

        guard
            geometry.captureFrame.isFiniteAndNonEmpty,
            geometry.surfaceFrame.isFiniteAndNonEmpty,
            geometry.contentFrame.isFiniteAndNonEmpty
        else {
            return nil
        }

        return geometry
    }

    public func windowDidMove(_ notification: Notification) {
        updateOverlap()
        rejectSourceFullScreenIfNeeded()
    }

    public func windowDidResize(_ notification: Notification) {
        updateOverlap()
        rejectSourceFullScreenIfNeeded()
    }

    public func windowDidMiniaturize(_ notification: Notification) {
        updateOverlap()
    }

    public func windowDidDeminiaturize(_ notification: Notification) {
        updateOverlap()
        rejectSourceFullScreenIfNeeded()
    }

    public func windowDidBecomeKey(_ notification: Notification) {
        updateOverlap()
    }

    public func windowDidBecomeMain(_ notification: Notification) {
        updateOverlap()
    }

    public func windowDidEnterFullScreen(_ notification: Notification) {
        rejectSourceFullScreenIfNeeded()
        updateOverlap()
    }

    public func windowDidExitFullScreen(_ notification: Notification) {
        isRejectingSourceFullScreen = false
        updateOverlap()
    }

    private func installObservers(for window: NSWindow) {
        removeObservers()
        let center = NotificationCenter.default
        let names: [Notification.Name] = [
            NSWindow.didChangeScreenNotification,
            NSWindow.didChangeOcclusionStateNotification,
            NSWindow.didResignKeyNotification
        ]
        names.forEach { name in
            center.addObserver(
                self,
                selector: #selector(handleWindowNotification(_:)),
                name: name,
                object: window
            )
        }
    }

    private func removeObservers() {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func handleWindowNotification(_ notification: Notification) {
        rejectSourceFullScreenIfNeeded()
        updateOverlap()
    }

    private func updateOverlap() {
        let appWindowFrames = Self.visibleAppWindowFrames()
        let canEnable = WindowOverlapPolicy.canEnableInteractive(
            appWindowFrames: appWindowFrames,
            sourceAppKitFrame: viewModel.selectedDisplay.appKitFrame
        )
        let isOverlappingSource = !canEnable
        viewModel.updateOverlap(isOverlappingSource: isOverlappingSource)
        onOverlapChanged?(isOverlappingSource)
    }

    private func rejectSourceFullScreenIfNeeded() {
        guard
            let window,
            window.styleMask.contains(.fullScreen),
            !isRejectingSourceFullScreen,
            Self.framesOverlap(window.screen?.frame, viewModel.selectedDisplay.appKitFrame)
        else {
            return
        }

        isRejectingSourceFullScreen = true
        viewModel.updateOverlap(isOverlappingSource: true)
        onOverlapChanged?(true)
        window.toggleFullScreen(nil)
    }

    private static func initialFrame(on screen: NSScreen?) -> CGRect {
        let visibleFrame = screen?.visibleFrame ?? CGRect(x: 0, y: 0, width: 960, height: 640)
        let width = max(640, visibleFrame.width * 0.72)
        let height = max(420, visibleFrame.height * 0.72)
        return CGRect(
            x: visibleFrame.midX - width / 2,
            y: visibleFrame.midY - height / 2,
            width: min(width, visibleFrame.width),
            height: min(height, visibleFrame.height)
        )
    }

    private static func constrainedFrame(_ frame: CGRect, on screen: NSScreen?) -> CGRect {
        guard let visibleFrame = screen?.visibleFrame else {
            return frame
        }

        let width = min(max(frame.width, 640), visibleFrame.width)
        let height = min(max(frame.height, 420), visibleFrame.height)
        let x = min(max(frame.minX, visibleFrame.minX), visibleFrame.maxX - width)
        let y = min(max(frame.minY, visibleFrame.minY), visibleFrame.maxY - height)
        return CGRect(x: x, y: y, width: width, height: height)
    }

    private static func visibleAppWindowFrames() -> [CGRect] {
        NSApp.windows.compactMap { window in
            guard
                window.isVisible,
                !window.isMiniaturized,
                window.alphaValue > 0,
                window.occlusionState.contains(.visible),
                window.frame.isFiniteAndNonEmpty,
                NSScreen.screens.contains(where: { framesOverlap($0.frame, window.frame) })
            else {
                return nil
            }

            return window.frame
        }
    }

    private static func framesOverlap(_ lhs: CGRect?, _ rhs: CGRect) -> Bool {
        guard let lhs, lhs.isFiniteAndNonEmpty, rhs.isFiniteAndNonEmpty else {
            return false
        }

        let intersection = lhs.intersection(rhs)
        return intersection.isFiniteAndNonEmpty
    }

    private static func mainDisplayHeight() -> CGFloat {
        let mainDisplayID = CGMainDisplayID()
        let mainScreen = NSScreen.screens.first { screen in
            guard let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
                return false
            }

            return CGDirectDisplayID(screenNumber.uint32Value) == mainDisplayID
        }
        return mainScreen?.frame.height ?? NSScreen.main?.frame.height ?? CGDisplayBounds(mainDisplayID).height
    }

    private static func findMirrorSurfaceView(in view: NSView?) -> MirrorSurfaceView? {
        guard let view else {
            return nil
        }

        if let surfaceView = view as? MirrorSurfaceView {
            return surfaceView
        }

        for subview in view.subviews {
            if let surfaceView = findMirrorSurfaceView(in: subview) {
                return surfaceView
            }
        }

        return nil
    }
}

private extension CGRect {
    var isFiniteAndNonEmpty: Bool {
        origin.x.isFinite &&
            origin.y.isFinite &&
            size.width.isFinite &&
            size.height.isFinite &&
            !isNull &&
            !isEmpty &&
            width > 0 &&
            height > 0
    }
}
