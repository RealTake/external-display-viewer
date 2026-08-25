import CoreGraphics
import CoreMedia
import CoreVideo
import ScreenCaptureKit

public enum CaptureSettings {
    public static func makeConfiguration(widthInPoints: CGFloat, heightInPoints: CGFloat, scale: CGFloat) -> SCStreamConfiguration {
        let configuration = SCStreamConfiguration()
        configuration.width = max(1, Int((widthInPoints * scale).rounded()))
        configuration.height = max(1, Int((heightInPoints * scale).rounded()))
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 60)
        configuration.queueDepth = 3
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.showsCursor = true
        configuration.capturesAudio = false
        return configuration
    }
}
