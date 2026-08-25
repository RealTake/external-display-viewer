import AppKit

public struct MirrorSurfaceMouseEvent: Equatable, Sendable {
    public let button: PointerButton
    public let location: CGPoint
    public let renderRect: CGRect
    public let clickCount: Int

    public init(button: PointerButton, location: CGPoint, renderRect: CGRect, clickCount: Int) {
        self.button = button
        self.location = location
        self.renderRect = renderRect
        self.clickCount = clickCount
    }
}

public struct MirrorSurfaceScrollEvent: Equatable, Sendable {
    public let location: CGPoint
    public let renderRect: CGRect
    public let deltaX: Int32
    public let deltaY: Int32

    public init(location: CGPoint, renderRect: CGRect, deltaX: Int32, deltaY: Int32) {
        self.location = location
        self.renderRect = renderRect
        self.deltaX = deltaX
        self.deltaY = deltaY
    }
}

public struct MirrorSurfacePortalEvent: Equatable, Sendable {
    public let location: CGPoint
    public let renderRect: CGRect

    public init(location: CGPoint, renderRect: CGRect) {
        self.location = location
        self.renderRect = renderRect
    }
}

struct MirrorSurfaceScrollDelta: Equatable, Sendable {
    let deltaX: Int32
    let deltaY: Int32
}

struct MirrorSurfaceScrollAccumulator: Sendable {
    private var residualX: CGFloat = 0
    private var residualY: CGFloat = 0

    mutating func emit(deltaX: CGFloat, deltaY: CGFloat) -> MirrorSurfaceScrollDelta? {
        let emittedX = Self.consume(deltaX, residual: &residualX)
        let emittedY = Self.consume(deltaY, residual: &residualY)

        guard emittedX != 0 || emittedY != 0 else {
            return nil
        }

        return MirrorSurfaceScrollDelta(deltaX: emittedX, deltaY: emittedY)
    }

    mutating func reset() {
        residualX = 0
        residualY = 0
    }

    private static func consume(_ delta: CGFloat, residual: inout CGFloat) -> Int32 {
        if delta == 0 {
            return 0
        }

        if residual != 0, delta.sign != residual.sign {
            residual = 0
        }

        let combined = residual + delta
        let emitted = Self.clampedWholePixels(combined)
        residual = Self.residual(afterEmitting: emitted, from: combined)
        return emitted
    }

    private static func clampedWholePixels(_ value: CGFloat) -> Int32 {
        guard value <= CGFloat(Int32.max) else {
            return Int32.max
        }

        guard value >= CGFloat(Int32.min) else {
            return Int32.min
        }

        return Int32(value.rounded(.towardZero))
    }

    private static func residual(afterEmitting emitted: Int32, from value: CGFloat) -> CGFloat {
        if emitted == Int32.max || emitted == Int32.min {
            return 0
        }

        return value - CGFloat(emitted)
    }
}

@MainActor
public final class MirrorSurfaceView: NSView {
    public typealias MouseCallback = @MainActor (MirrorSurfaceMouseEvent) -> Void
    public typealias ScrollCallback = @MainActor (MirrorSurfaceScrollEvent) -> Void
    public typealias PortalCallback = @MainActor (MirrorSurfacePortalEvent) -> Void

    public var isInteractive = false {
        didSet {
            if !isInteractive {
                scrollAccumulator.reset()
            }
        }
    }
    public var onPointerDown: MouseCallback?
    public var onPointerDragged: MouseCallback?
    public var onPointerUp: MouseCallback?
    public var onScroll: ScrollCallback?
    public var onPortalEntered: PortalCallback?
    public var onPortalExited: PortalCallback?
    public private(set) var currentRenderRect: CGRect = .zero

    public var sourceSize: CGSize = .zero {
        didSet {
            guard oldValue != sourceSize else {
                return
            }

            needsLayout = true
        }
    }
    private var scrollAccumulator = MirrorSurfaceScrollAccumulator()
    private var renderTrackingArea: NSTrackingArea?

    var pressedMouseButtonsProvider: @MainActor () -> Int = {
        NSEvent.pressedMouseButtons
    }

    public override var isFlipped: Bool {
        true
    }

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configureLayer()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureLayer()
    }

    public override func layout() {
        super.layout()
        currentRenderRect = CoordinateMapper.renderRect(
            contentSize: bounds.size,
            sourceAspectRatio: sourceAspectRatio
        )
        updateRenderTrackingArea()
    }

    public override func mouseEntered(with event: NSEvent) {
        let location = localPoint(from: event)
        guard
            pressedMouseButtonsProvider() == 0,
            currentRenderRect.contains(location)
        else {
            super.mouseEntered(with: event)
            return
        }

        onPortalEntered?(
            MirrorSurfacePortalEvent(
                location: location,
                renderRect: currentRenderRect
            )
        )
    }

    public override func mouseExited(with event: NSEvent) {
        guard currentRenderRect.width > 0, currentRenderRect.height > 0 else {
            super.mouseExited(with: event)
            return
        }

        onPortalExited?(
            MirrorSurfacePortalEvent(
                location: localPoint(from: event),
                renderRect: currentRenderRect
            )
        )
    }

    public override func mouseDown(with event: NSEvent) {
        handleMouse(event, button: .left, callback: onPointerDown) {
            super.mouseDown(with: event)
        }
    }

    public override func rightMouseDown(with event: NSEvent) {
        handleMouse(event, button: .right, callback: onPointerDown) {
            super.rightMouseDown(with: event)
        }
    }

    public override func otherMouseDown(with event: NSEvent) {
        handleMouse(event, button: .middle, callback: onPointerDown) {
            super.otherMouseDown(with: event)
        }
    }

    public override func mouseDragged(with event: NSEvent) {
        handleMouse(event, button: .left, callback: onPointerDragged) {
            super.mouseDragged(with: event)
        }
    }

    public override func rightMouseDragged(with event: NSEvent) {
        handleMouse(event, button: .right, callback: onPointerDragged) {
            super.rightMouseDragged(with: event)
        }
    }

    public override func otherMouseDragged(with event: NSEvent) {
        handleMouse(event, button: .middle, callback: onPointerDragged) {
            super.otherMouseDragged(with: event)
        }
    }

    public override func mouseUp(with event: NSEvent) {
        handleMouse(event, button: .left, callback: onPointerUp) {
            super.mouseUp(with: event)
        }
    }

    public override func rightMouseUp(with event: NSEvent) {
        handleMouse(event, button: .right, callback: onPointerUp) {
            super.rightMouseUp(with: event)
        }
    }

    public override func otherMouseUp(with event: NSEvent) {
        handleMouse(event, button: .middle, callback: onPointerUp) {
            super.otherMouseUp(with: event)
        }
    }

    public override func scrollWheel(with event: NSEvent) {
        guard isInteractive else {
            scrollAccumulator.reset()
            super.scrollWheel(with: event)
            return
        }

        guard let delta = scrollAccumulator.emit(deltaX: event.scrollingDeltaX, deltaY: event.scrollingDeltaY) else {
            return
        }

        onScroll?(
            MirrorSurfaceScrollEvent(
                location: localPoint(from: event),
                renderRect: currentRenderRect,
                deltaX: delta.deltaX,
                deltaY: delta.deltaY
            )
        )
    }

    private var sourceAspectRatio: CGFloat {
        guard sourceSize.width > 0, sourceSize.height > 0 else {
            return 0
        }

        return sourceSize.width / sourceSize.height
    }

    private func configureLayer() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        layer?.contentsGravity = .resizeAspect
        layer?.masksToBounds = true
    }

    private func updateRenderTrackingArea() {
        if let renderTrackingArea {
            removeTrackingArea(renderTrackingArea)
            self.renderTrackingArea = nil
        }

        guard currentRenderRect.width > 0, currentRenderRect.height > 0 else {
            return
        }

        let trackingArea = NSTrackingArea(
            rect: currentRenderRect,
            options: [.mouseEnteredAndExited, .activeAlways],
            owner: self
        )
        addTrackingArea(trackingArea)
        renderTrackingArea = trackingArea
    }

    private func handleMouse(
        _ event: NSEvent,
        button: PointerButton,
        callback: MouseCallback?,
        fallback: () -> Void
    ) {
        guard isInteractive else {
            fallback()
            return
        }

        callback?(
            MirrorSurfaceMouseEvent(
                button: button,
                location: localPoint(from: event),
                renderRect: currentRenderRect,
                clickCount: max(1, event.clickCount)
            )
        )
    }

    private func localPoint(from event: NSEvent) -> CGPoint {
        convert(event.locationInWindow, from: nil)
    }

}
