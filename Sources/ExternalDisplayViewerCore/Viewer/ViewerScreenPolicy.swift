import AppKit
import CoreGraphics

public enum ViewerScreenPolicy {
    public static func preferredScreen(screens: [NSScreen]) -> NSScreen? {
        screens.first { screen in
            guard let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
                return false
            }

            return CGDisplayIsBuiltin(CGDirectDisplayID(screenNumber.uint32Value)) != 0
        } ?? NSScreen.main ?? screens.first
    }
}
