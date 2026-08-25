import AppKit

@MainActor
public final class SurfacePresenter {
    private weak var view: MirrorSurfaceView?
    public private(set) var currentFrame: CaptureFrame?

    public init() {}

    public func attach(_ view: MirrorSurfaceView) {
        self.view = view
        updateSourceSize(on: view, to: currentFrame?.size ?? .zero)
        view.layer?.contents = currentFrame?.surface
    }

    public func present(_ frame: CaptureFrame?) {
        currentFrame = frame
        guard let view else {
            return
        }

        updateSourceSize(on: view, to: frame?.size ?? .zero)
        view.layer?.contents = frame?.surface
    }

    private func updateSourceSize(on view: MirrorSurfaceView, to sourceSize: CGSize) {
        if view.sourceSize != sourceSize {
            view.sourceSize = sourceSize
        }
    }
}
