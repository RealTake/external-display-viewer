import CoreGraphics
import Foundation

public enum PointerPortalEdge: Equatable, Sendable {
    case left
    case right
    case top
    case bottom
}

public struct PointerPortalExit: Equatable, Sendable {
    public let edge: PointerPortalEdge
    public let position: CGFloat

    public init(edge: PointerPortalEdge, position: CGFloat) {
        self.edge = edge
        self.position = position
    }
}

public struct PointerPortalEntry: Equatable, Sendable {
    public let viewerPoint: CGPoint
    public let renderRect: CGRect
    public let displayFrame: CGRect

    public init(viewerPoint: CGPoint, renderRect: CGRect, displayFrame: CGRect) {
        self.viewerPoint = viewerPoint
        self.renderRect = renderRect
        self.displayFrame = displayFrame
    }
}

public struct PointerPortalViewerGeometry: Equatable, Sendable {
    public let captureFrame: CGRect
    public let surfaceFrame: CGRect
    public let contentFrame: CGRect

    public init(captureFrame: CGRect, surfaceFrame: CGRect, contentFrame: CGRect) {
        self.captureFrame = captureFrame
        self.surfaceFrame = surfaceFrame
        self.contentFrame = contentFrame
    }
}

public enum PointerPortalMapper {
    private static let boundaryTolerance: CGFloat = 1

    public static func externalPoint(for entry: PointerPortalEntry) -> CGPoint? {
        CoordinateMapper.map(point: entry.viewerPoint, in: entry.renderRect, to: entry.displayFrame)
    }

    public static func exit(at point: CGPoint, delta: CGVector, in displayFrame: CGRect) -> PointerPortalExit? {
        guard point.isFinitePortalPoint, displayFrame.isFinitePortalRect else {
            return nil
        }

        let horizontal = horizontalExit(at: point, delta: delta, in: displayFrame)
        let vertical = verticalExit(at: point, delta: delta, in: displayFrame)

        switch (horizontal, vertical) {
        case let (.some(horizontal), .some(vertical)):
            return abs(delta.dx) >= abs(delta.dy) ? horizontal : vertical
        case let (.some(horizontal), .none):
            return horizontal
        case let (.none, .some(vertical)):
            return vertical
        case (.none, .none):
            return nil
        }
    }

    public static func returnPoint(
        for exit: PointerPortalExit,
        viewer: PointerPortalViewerGeometry,
        safetyInset: CGFloat = 2
    ) -> CGPoint? {
        guard
            exit.position.isFinite,
            viewer.captureFrame.isFinitePortalRect,
            viewer.surfaceFrame.isFinitePortalRect,
            viewer.contentFrame.isFinitePortalRect
        else {
            return nil
        }

        let inset = max(safetyInset, 0)
        let strips = LandingStrips(capture: viewer.captureFrame, surface: viewer.surfaceFrame)
        if let point = point(for: exit, in: strips.matchingStrip(for: exit.edge), capture: viewer.captureFrame, inset: inset) {
            return point
        }

        return footerPoint(for: exit, viewer: viewer, inset: inset)
    }

    private static func horizontalExit(at point: CGPoint, delta: CGVector, in frame: CGRect) -> PointerPortalExit? {
        if point.x <= frame.minX + boundaryTolerance, delta.dx < 0 {
            return PointerPortalExit(edge: .left, position: normalized(point.y, in: frame.minY ... frame.maxY))
        }

        if point.x >= frame.maxX - boundaryTolerance, delta.dx > 0 {
            return PointerPortalExit(edge: .right, position: normalized(point.y, in: frame.minY ... frame.maxY))
        }

        return nil
    }

    private static func verticalExit(at point: CGPoint, delta: CGVector, in frame: CGRect) -> PointerPortalExit? {
        if point.y <= frame.minY + boundaryTolerance, delta.dy < 0 {
            return PointerPortalExit(edge: .top, position: normalized(point.x, in: frame.minX ... frame.maxX))
        }

        if point.y >= frame.maxY - boundaryTolerance, delta.dy > 0 {
            return PointerPortalExit(edge: .bottom, position: normalized(point.x, in: frame.minX ... frame.maxX))
        }

        return nil
    }

    private static func point(
        for exit: PointerPortalExit,
        in strip: CGRect?,
        capture: CGRect,
        inset: CGFloat
    ) -> CGPoint? {
        guard let strip, strip.isFinitePortalRect else {
            return nil
        }

        let ratio = clamped(exit.position)
        let point: CGPoint
        switch exit.edge {
        case .left:
            point = CGPoint(x: capture.minX - inset, y: capture.minY + ratio * capture.height)
        case .right:
            point = CGPoint(x: capture.maxX + inset, y: capture.minY + ratio * capture.height)
        case .top:
            point = CGPoint(x: capture.minX + ratio * capture.width, y: capture.minY - inset)
        case .bottom:
            point = CGPoint(x: capture.minX + ratio * capture.width, y: capture.maxY + inset)
        }

        return point.clamped(to: strip)
    }

    private static func footerPoint(for exit: PointerPortalExit, viewer: PointerPortalViewerGeometry, inset: CGFloat) -> CGPoint? {
        let footer = CGRect(
            x: viewer.contentFrame.minX,
            y: viewer.surfaceFrame.maxY,
            width: viewer.contentFrame.width,
            height: viewer.contentFrame.maxY - viewer.surfaceFrame.maxY
        )
        guard footer.isFinitePortalRect else {
            return nil
        }

        let ratio = clamped(exit.position)
        let point: CGPoint
        switch exit.edge {
        case .left:
            point = CGPoint(x: viewer.captureFrame.minX + inset, y: footer.minY + ratio * footer.height)
        case .right:
            point = CGPoint(x: viewer.captureFrame.maxX - inset, y: footer.minY + ratio * footer.height)
        case .top, .bottom:
            point = CGPoint(x: viewer.captureFrame.minX + ratio * viewer.captureFrame.width, y: footer.minY + inset)
        }

        return point.clamped(to: footer)
    }

    private static func normalized(_ value: CGFloat, in range: ClosedRange<CGFloat>) -> CGFloat {
        clamped((value - range.lowerBound) / (range.upperBound - range.lowerBound))
    }

    private static func clamped(_ value: CGFloat) -> CGFloat {
        min(max(value, 0), 1)
    }
}

private struct LandingStrips {
    let left: CGRect?
    let right: CGRect?
    let top: CGRect?
    let bottom: CGRect?

    init(capture: CGRect, surface: CGRect) {
        left = CGRect(
            x: surface.minX,
            y: capture.minY,
            width: capture.minX - surface.minX,
            height: capture.height
        ).validPortalLanding
        right = CGRect(
            x: capture.maxX,
            y: capture.minY,
            width: surface.maxX - capture.maxX,
            height: capture.height
        ).validPortalLanding
        top = CGRect(
            x: capture.minX,
            y: surface.minY,
            width: capture.width,
            height: capture.minY - surface.minY
        ).validPortalLanding
        bottom = CGRect(
            x: capture.minX,
            y: capture.maxY,
            width: capture.width,
            height: surface.maxY - capture.maxY
        ).validPortalLanding
    }

    func matchingStrip(for edge: PointerPortalEdge) -> CGRect? {
        switch edge {
        case .left:
            return left
        case .right:
            return right
        case .top:
            return top
        case .bottom:
            return bottom
        }
    }
}

private extension CGRect {
    var validPortalLanding: CGRect? {
        isFinitePortalRect ? self : nil
    }

    var isFinitePortalRect: Bool {
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

private extension CGPoint {
    var isFinitePortalPoint: Bool {
        x.isFinite && y.isFinite
    }

    func clamped(to rect: CGRect) -> CGPoint? {
        guard isFinitePortalPoint, rect.isFinitePortalRect else {
            return nil
        }

        return CGPoint(
            x: min(max(x, rect.minX), rect.maxX),
            y: min(max(y, rect.minY), rect.maxY)
        )
    }
}
