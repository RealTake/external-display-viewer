import AppKit
import CoreGraphics
import ScreenCaptureKit

@MainActor
public final class DisplayManager {
    public var onReconfiguration: (@MainActor (Result<[DisplayInfo], Error>) -> Void)?

    private var captureTargets: [CGDirectDisplayID: SCDisplay] = [:]
    private var didRegisterReconfigurationCallback = false

    public init() {}

    deinit {
        if didRegisterReconfigurationCallback {
            CGDisplayRemoveReconfigurationCallback(Self.reconfigurationCallback, Unmanaged.passUnretained(self).toOpaque())
        }
    }

    public func refresh() async throws -> [DisplayInfo] {
        registerReconfigurationCallbackIfNeeded()

        let displays = NSScreen.screens.compactMap { screen -> DisplayInfo? in
            guard let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
                return nil
            }

            let displayID = CGDirectDisplayID(screenNumber.uint32Value)
            let scale = screen.backingScaleFactor

            return DisplayInfo(
                id: displayID,
                name: screen.localizedName,
                coreGraphicsFrame: CGDisplayBounds(displayID),
                appKitFrame: screen.frame,
                pixelSize: CGSize(width: screen.frame.width * scale, height: screen.frame.height * scale),
                scale: scale,
                isBuiltIn: CGDisplayIsBuiltin(displayID) != 0
            )
        }

        guard CGPreflightScreenCaptureAccess() else {
            captureTargets.removeAll()
            return displays
        }

        let shareableContent = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        captureTargets = Dictionary(uniqueKeysWithValues: shareableContent.displays.map { ($0.displayID, $0) })
        return displays
    }

    public func captureTarget(for display: DisplayInfo) -> SCDisplay? {
        captureTargets[display.id]
    }

    private func registerReconfigurationCallbackIfNeeded() {
        guard !didRegisterReconfigurationCallback else {
            return
        }

        let error = CGDisplayRegisterReconfigurationCallback(Self.reconfigurationCallback, Unmanaged.passUnretained(self).toOpaque())
        didRegisterReconfigurationCallback = error == .success
    }

    nonisolated private static let reconfigurationCallback: CGDisplayReconfigurationCallBack = { _, _, userInfo in
        guard let userInfo else {
            return
        }

        let manager = Unmanaged<DisplayManager>.fromOpaque(userInfo).takeUnretainedValue()
        Task { @MainActor in
            do {
                let displays = try await manager.refresh()
                manager.onReconfiguration?(.success(displays))
            } catch {
                manager.onReconfiguration?(.failure(error))
            }
        }
    }
}
