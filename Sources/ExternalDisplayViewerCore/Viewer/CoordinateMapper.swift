import CoreGraphics
import Foundation

public enum CoordinateMapper {
    public static func renderRect(contentSize: CGSize, sourceAspectRatio: CGFloat) -> CGRect {
        guard contentSize.width > 0, contentSize.height > 0, sourceAspectRatio > 0 else {
            return .zero
        }

        let contentAspectRatio = contentSize.width / contentSize.height
        if sourceAspectRatio > contentAspectRatio {
            let height = contentSize.width / sourceAspectRatio
            return CGRect(
                x: 0,
                y: (contentSize.height - height) / 2,
                width: contentSize.width,
                height: height
            )
        }

        let width = contentSize.height * sourceAspectRatio
        return CGRect(
            x: (contentSize.width - width) / 2,
            y: 0,
            width: width,
            height: contentSize.height
        )
    }

    public static func map(point: CGPoint, in renderRect: CGRect, to displayRect: CGRect) -> CGPoint? {
        guard isValid(renderRect), isValid(displayRect), contains(point, in: renderRect) else {
            return nil
        }

        return mappedPoint(point, in: renderRect, to: displayRect, clamped: false)
    }

    public static func mapClamped(point: CGPoint, in renderRect: CGRect, to displayRect: CGRect) -> CGPoint {
        guard isValid(renderRect), isValid(displayRect) else {
            return CGPoint(x: displayRect.minX, y: displayRect.minY)
        }

        return mappedPoint(point, in: renderRect, to: displayRect, clamped: true)
    }

    private static func mappedPoint(_ point: CGPoint, in renderRect: CGRect, to displayRect: CGRect, clamped: Bool) -> CGPoint {
        let normalizedX = normalized(point.x, origin: renderRect.minX, length: renderRect.width, clamped: clamped)
        let normalizedY = normalized(point.y, origin: renderRect.minY, length: renderRect.height, clamped: clamped)

        return CGPoint(
            x: clampDisplayCoordinate(displayRect.minX + normalizedX * displayRect.width, in: displayRect.minX ... displayRect.maxX),
            y: clampDisplayCoordinate(displayRect.minY + normalizedY * displayRect.height, in: displayRect.minY ... displayRect.maxY)
        )
    }

    private static func normalized(_ value: CGFloat, origin: CGFloat, length: CGFloat, clamped: Bool) -> CGFloat {
        let raw = (value - origin) / length
        if clamped {
            return min(max(raw, 0), 1)
        }

        return raw
    }

    private static func clampDisplayCoordinate(_ coordinate: CGFloat, in range: ClosedRange<CGFloat>) -> CGFloat {
        if coordinate <= range.lowerBound {
            return range.lowerBound
        }

        if coordinate >= range.upperBound {
            return range.upperBound.nextDown
        }

        return coordinate
    }

    private static func contains(_ point: CGPoint, in rect: CGRect) -> Bool {
        point.x >= rect.minX && point.x <= rect.maxX && point.y >= rect.minY && point.y <= rect.maxY
    }

    private static func isValid(_ rect: CGRect) -> Bool {
        rect.width > 0 && rect.height > 0
    }
}
