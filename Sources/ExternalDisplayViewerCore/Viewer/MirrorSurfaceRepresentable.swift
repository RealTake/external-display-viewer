import SwiftUI

@MainActor
public struct MirrorSurfaceRepresentable: NSViewRepresentable {
    public typealias NSViewType = MirrorSurfaceView

    private let presenter: SurfacePresenter
    private let isInteractive: Bool
    private let onPointerDown: MirrorSurfaceView.MouseCallback?
    private let onPointerDragged: MirrorSurfaceView.MouseCallback?
    private let onPointerUp: MirrorSurfaceView.MouseCallback?
    private let onScroll: MirrorSurfaceView.ScrollCallback?
    private let onPortalEntered: MirrorSurfaceView.PortalCallback?
    private let onPortalExited: MirrorSurfaceView.PortalCallback?

    public init(
        presenter: SurfacePresenter,
        isInteractive: Bool,
        onPointerDown: MirrorSurfaceView.MouseCallback? = nil,
        onPointerDragged: MirrorSurfaceView.MouseCallback? = nil,
        onPointerUp: MirrorSurfaceView.MouseCallback? = nil,
        onScroll: MirrorSurfaceView.ScrollCallback? = nil,
        onPortalEntered: MirrorSurfaceView.PortalCallback? = nil,
        onPortalExited: MirrorSurfaceView.PortalCallback? = nil
    ) {
        self.presenter = presenter
        self.isInteractive = isInteractive
        self.onPointerDown = onPointerDown
        self.onPointerDragged = onPointerDragged
        self.onPointerUp = onPointerUp
        self.onScroll = onScroll
        self.onPortalEntered = onPortalEntered
        self.onPortalExited = onPortalExited
    }

    public func makeNSView(context: Context) -> MirrorSurfaceView {
        let view = MirrorSurfaceView()
        presenter.attach(view)
        update(view)
        return view
    }

    public func updateNSView(_ nsView: MirrorSurfaceView, context: Context) {
        update(nsView)
    }

    private func update(_ view: MirrorSurfaceView) {
        view.isInteractive = isInteractive
        view.onPointerDown = onPointerDown
        view.onPointerDragged = onPointerDragged
        view.onPointerUp = onPointerUp
        view.onScroll = onScroll
        view.onPortalEntered = onPortalEntered
        view.onPortalExited = onPortalExited
    }
}
