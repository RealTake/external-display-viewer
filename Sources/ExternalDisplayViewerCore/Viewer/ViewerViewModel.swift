import Combine
import Foundation

public enum ViewerMode: Hashable, Sendable {
    case viewOnly
    case interactive

    public var title: String {
        switch self {
        case .viewOnly:
            "View Only"
        case .interactive:
            "Interactive"
        }
    }
}

public enum ViewerModeIntent: Equatable, Sendable {
    case enableInteractive
    case disableInteractive
}

@MainActor
public final class ViewerViewModel: ObservableObject {
    public typealias VoidCallback = @MainActor () -> Void
    public typealias TopLevelCallback = @MainActor (Bool) -> Void
    public typealias ModeIntentCallback = @MainActor (ViewerModeIntent) -> Void

    @Published public private(set) var selectedDisplay: DisplayInfo
    @Published public private(set) var sourceSize: CGSize
    @Published public private(set) var metrics: CaptureMetricsSnapshot
    @Published public private(set) var mode: ViewerMode = .viewOnly
    @Published public private(set) var isAlwaysOnTop = false
    @Published public private(set) var isOverlappingSource = false
    @Published public private(set) var captureWarning: String?
    @Published public private(set) var permissions: PermissionSnapshot

    public let hud: TransitionHUDController
    public let presenter: SurfacePresenter
    public private(set) var frame: CaptureFrame?
    public let onPointerDown: MirrorSurfaceView.MouseCallback?
    public let onPointerDragged: MirrorSurfaceView.MouseCallback?
    public let onPointerUp: MirrorSurfaceView.MouseCallback?
    public let onScroll: MirrorSurfaceView.ScrollCallback?
    public let onPortalEntered: MirrorSurfaceView.PortalCallback?
    public let onPortalExited: MirrorSurfaceView.PortalCallback?
    private let onModeIntent: ModeIntentCallback?
    private let onAlwaysOnTopChange: TopLevelCallback?
    private let onStop: VoidCallback?
    private var hasPendingInteractiveRequest = false
    private var hasSentDisableIntentForCurrentMode = false

    public init(
        selectedDisplay: DisplayInfo,
        frame: CaptureFrame? = nil,
        metrics: CaptureMetricsSnapshot = CaptureMetricsSnapshot(
            displayedFPS: 0,
            incompleteRatio: 0,
            receivedFrames: 0,
            displayedFrames: 0
        ),
        hud: TransitionHUDController,
        presenter: SurfacePresenter,
        permissions: PermissionSnapshot = PermissionSnapshot(
            screenRecording: false,
            postEvents: false,
            listenEvents: false,
            eventTapUsable: false
        ),
        onPointerDown: MirrorSurfaceView.MouseCallback? = nil,
        onPointerDragged: MirrorSurfaceView.MouseCallback? = nil,
        onPointerUp: MirrorSurfaceView.MouseCallback? = nil,
        onScroll: MirrorSurfaceView.ScrollCallback? = nil,
        onPortalEntered: MirrorSurfaceView.PortalCallback? = nil,
        onPortalExited: MirrorSurfaceView.PortalCallback? = nil,
        onModeIntent: ModeIntentCallback? = nil,
        onAlwaysOnTopChange: TopLevelCallback? = nil,
        onStop: VoidCallback? = nil
    ) {
        self.selectedDisplay = selectedDisplay
        self.frame = frame
        self.sourceSize = frame?.size ?? .zero
        self.metrics = metrics
        self.hud = hud
        self.presenter = presenter
        self.permissions = permissions
        self.onPointerDown = onPointerDown
        self.onPointerDragged = onPointerDragged
        self.onPointerUp = onPointerUp
        self.onScroll = onScroll
        self.onPortalEntered = onPortalEntered
        self.onPortalExited = onPortalExited
        self.onModeIntent = onModeIntent
        self.onAlwaysOnTopChange = onAlwaysOnTopChange
        self.onStop = onStop
        presenter.present(frame)
    }

    public var isInteractive: Bool {
        mode == .interactive && canEnableInteractive
    }

    public var canEnableInteractive: Bool {
        interactiveDisabledReason == nil
    }

    public var interactiveDisabledReason: String? {
        if !permissions.postEvents {
            return "손쉬운 사용 권한이 필요합니다. 시스템 설정에서 이 앱의 제어 권한을 허용하세요."
        }

        if !permissions.listenEvents {
            return "입력 모니터링 권한이 필요합니다. 시스템 설정에서 이 앱의 키 입력 감지를 허용하세요."
        }

        if !permissions.eventTapUsable {
            return "ESC 복귀 감지를 시작할 수 없습니다. 권한을 다시 확인하거나 앱을 재실행하세요."
        }

        if isOverlappingSource {
            return Self.overlapWarning
        }

        return nil
    }

    public var statusText: String {
        if isInteractive {
            return "Interactive 준비됨"
        }

        if let interactiveDisabledReason {
            return interactiveDisabledReason
        }

        return "View Only"
    }

    public func updateSelectedDisplay(_ selectedDisplay: DisplayInfo) {
        self.selectedDisplay = selectedDisplay
    }

    public func updateFrame(_ frame: CaptureFrame?) {
        self.frame = frame
        presenter.present(frame)
        let nextSourceSize = frame?.size ?? .zero
        if sourceSize != nextSourceSize {
            sourceSize = nextSourceSize
        }
    }

    public func updateMetrics(_ metrics: CaptureMetricsSnapshot) {
        self.metrics = metrics
    }

    public func updatePermissions(_ permissions: PermissionSnapshot) {
        self.permissions = permissions
        enforceGate()
    }

    public func updateOverlap(isOverlappingSource: Bool) {
        self.isOverlappingSource = isOverlappingSource
        captureWarning = isOverlappingSource ? Self.overlapWarning : nil
        enforceGate()
    }

    public func requestMode(_ mode: ViewerMode) {
        switch mode {
        case .viewOnly:
            transitionToViewOnly(notifyCoordinator: modeRequiresCoordinatorDisable)
        case .interactive:
            guard canEnableInteractive else {
                transitionToViewOnly(notifyCoordinator: modeRequiresCoordinatorDisable)
                return
            }

            guard self.mode != .interactive, !hasPendingInteractiveRequest else {
                return
            }

            hasPendingInteractiveRequest = true
            hasSentDisableIntentForCurrentMode = false
            onModeIntent?(.enableInteractive)
        }
    }

    public func updateModeFromCoordinator(_ mode: ViewerMode) {
        hasPendingInteractiveRequest = false

        switch mode {
        case .viewOnly:
            self.mode = .viewOnly
            hasSentDisableIntentForCurrentMode = false
        case .interactive:
            guard canEnableInteractive else {
                transitionToViewOnly(notifyCoordinator: true)
                return
            }

            self.mode = .interactive
            hasSentDisableIntentForCurrentMode = false
        }
    }

    public func setAlwaysOnTop(_ isAlwaysOnTop: Bool) {
        guard self.isAlwaysOnTop != isAlwaysOnTop else {
            return
        }

        self.isAlwaysOnTop = isAlwaysOnTop
        onAlwaysOnTopChange?(isAlwaysOnTop)
    }

    public func stop() {
        mode = .viewOnly
        onStop?()
    }

    private func enforceGate() {
        if modeRequiresCoordinatorDisable, !canEnableInteractive {
            transitionToViewOnly(notifyCoordinator: true)
        }
    }

    private var modeRequiresCoordinatorDisable: Bool {
        mode == .interactive || hasPendingInteractiveRequest
    }

    private func transitionToViewOnly(notifyCoordinator: Bool) {
        mode = .viewOnly
        hasPendingInteractiveRequest = false

        guard notifyCoordinator, !hasSentDisableIntentForCurrentMode else {
            return
        }

        hasSentDisableIntentForCurrentMode = true
        onModeIntent?(.disableInteractive)
    }

    private static let overlapWarning = "Interactive를 켜려면 Viewer 창을 소스 외부 디스플레이 밖으로 이동하세요."
}
