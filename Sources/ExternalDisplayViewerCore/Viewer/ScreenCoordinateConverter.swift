import CoreGraphics

public enum ScreenCoordinateConverter {
    public static func coreGraphicsGlobalRect(appKitGlobalRect: CGRect, mainDisplayHeight: CGFloat) -> CGRect {
        CGRect(
            x: appKitGlobalRect.minX,
            y: mainDisplayHeight - appKitGlobalRect.maxY,
            width: appKitGlobalRect.width,
            height: appKitGlobalRect.height
        )
    }
}
