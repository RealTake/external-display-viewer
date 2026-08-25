import CoreGraphics

public enum InputResult: Equatable, Sendable {
    case ignoredLetterbox
    case transferred(returnPoint: CGPoint)
    case continued
    case ended
    case failed(PointerOperationFailure)
}

public enum PointerOperationFailure: Equatable, Sendable {
    case currentLocationUnavailable
    case warp
    case mouseDown
    case mouseDragged
    case mouseUp
    case scroll
}

public final class InputEventManager {
    private let poster: PointerEventPosting
    private var activeSequence: ActiveSequence?

    public init(poster: PointerEventPosting = CGEventPoster()) {
        self.poster = poster
    }

    public func begin(
        button: PointerButton,
        clickCount: Int,
        viewerPoint: CGPoint,
        renderRect: CGRect,
        displayFrame: CGRect
    ) -> InputResult {
        guard let externalPoint = CoordinateMapper.map(point: viewerPoint, in: renderRect, to: displayFrame) else {
            return .ignoredLetterbox
        }

        guard let returnPoint = poster.currentLocation else {
            return .failed(.currentLocationUnavailable)
        }

        let cancelResult = cancelActiveSequence()
        if case .failed = cancelResult {
            return cancelResult
        }

        let clickCount = max(1, clickCount)
        guard poster.warp(to: externalPoint) else {
            return .failed(.warp)
        }

        guard poster.postMouse(.mouseDown, button: button, at: externalPoint, clickCount: clickCount) else {
            _ = poster.warp(to: returnPoint)
            return .failed(.mouseDown)
        }

        activeSequence = ActiveSequence(button: button, clickCount: clickCount, lastExternalPoint: externalPoint)
        return .transferred(returnPoint: returnPoint)
    }

    public func drag(to viewerPoint: CGPoint, renderRect: CGRect, displayFrame: CGRect) -> InputResult {
        guard var activeSequence else {
            return .ignoredLetterbox
        }

        let externalPoint = CoordinateMapper.mapClamped(point: viewerPoint, in: renderRect, to: displayFrame)
        guard poster.postMouse(
            .mouseDragged,
            button: activeSequence.button,
            at: externalPoint,
            clickCount: activeSequence.clickCount
        ) else {
            return .failed(.mouseDragged)
        }

        activeSequence.lastExternalPoint = externalPoint
        self.activeSequence = activeSequence
        return .continued
    }

    public func end(at viewerPoint: CGPoint, renderRect: CGRect, displayFrame: CGRect) -> InputResult {
        guard let activeSequence else {
            return .ignoredLetterbox
        }

        let externalPoint = CoordinateMapper.mapClamped(point: viewerPoint, in: renderRect, to: displayFrame)
        guard poster.postMouse(
            .mouseUp,
            button: activeSequence.button,
            at: externalPoint,
            clickCount: activeSequence.clickCount
        ) else {
            self.activeSequence?.lastExternalPoint = externalPoint
            return .failed(.mouseUp)
        }

        self.activeSequence = nil
        return .ended
    }

    public func scroll(
        deltaX: Int32,
        deltaY: Int32,
        viewerPoint: CGPoint,
        renderRect: CGRect,
        displayFrame: CGRect
    ) -> InputResult {
        guard let externalPoint = CoordinateMapper.map(point: viewerPoint, in: renderRect, to: displayFrame) else {
            return .ignoredLetterbox
        }

        guard poster.postScroll(deltaX: deltaX, deltaY: deltaY, at: externalPoint) else {
            return .failed(.scroll)
        }

        return .continued
    }

    public func cancelActiveSequence() -> InputResult {
        guard let activeSequence else {
            return .ignoredLetterbox
        }

        guard poster.postMouse(
            .mouseUp,
            button: activeSequence.button,
            at: activeSequence.lastExternalPoint,
            clickCount: activeSequence.clickCount
        ) else {
            return .failed(.mouseUp)
        }

        self.activeSequence = nil
        return .ended
    }
}

private struct ActiveSequence {
    let button: PointerButton
    let clickCount: Int
    var lastExternalPoint: CGPoint
}
