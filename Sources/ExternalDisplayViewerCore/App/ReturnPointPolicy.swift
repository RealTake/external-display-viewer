import CoreGraphics

public enum ReturnPointPolicy {
    public static func resolve(savedGlobalPoint: CGPoint?, viewerCaptureGlobalFrame: CGRect) -> CGPoint {
        let fallback = CGPoint(x: viewerCaptureGlobalFrame.midX, y: viewerCaptureGlobalFrame.midY)
        guard
            let savedGlobalPoint,
            savedGlobalPoint.x.isFinite,
            savedGlobalPoint.y.isFinite,
            viewerCaptureGlobalFrame.isFiniteReturnFrame,
            viewerCaptureGlobalFrame.contains(savedGlobalPoint)
        else {
            return fallback
        }

        return savedGlobalPoint
    }
}

extension CGRect {
    var isFiniteReturnFrame: Bool {
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
