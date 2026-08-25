import CoreGraphics

public enum WindowOverlapPolicy {
    public static func canEnableInteractive(
        appWindowFrames: [CGRect],
        sourceAppKitFrame: CGRect
    ) -> Bool {
        guard sourceAppKitFrame.isUsableForOverlap else {
            return false
        }

        return !appWindowFrames.contains { appWindowFrame in
            guard appWindowFrame.isUsableForOverlap else {
                return false
            }

            let intersection = appWindowFrame.intersection(sourceAppKitFrame)
            return intersection.isUsableForOverlap
        }
    }
}

private extension CGRect {
    var isUsableForOverlap: Bool {
        isFinite && standardized == self && !isNull && !isEmpty && width > 0 && height > 0
    }

    var isFinite: Bool {
        origin.x.isFinite &&
            origin.y.isFinite &&
            size.width.isFinite &&
            size.height.isFinite
    }
}
