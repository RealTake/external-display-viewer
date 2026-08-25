#if DEBUG
import CoreGraphics
import Foundation

public enum VisualQAPreviewSurface: Equatable, Sendable {
    case selection
    case viewer
}

public struct VisualQAPreviewState: Equatable, Sendable {
    public enum Identifier: String, CaseIterable, Sendable {
        case selectionReady = "selection-ready"
        case selectionScreenRecordingDenied = "selection-screen-recording-denied"
        case selectionInteractionDenied = "selection-interaction-denied"
        case selectionAccessibilitySettings = "selection-accessibility-settings"
        case selectionInputMonitoringSettings = "selection-input-monitoring-settings"
        case selectionNoExternalDisplay = "selection-no-external-display"
        case selectionRefreshError = "selection-refresh-error"
        case viewerViewOnly = "viewer-view-only"
        case viewerInteractiveReady = "viewer-interactive-ready"
        case viewerControlHUD = "viewer-control-hud"
        case viewerReturnHUD = "viewer-return-hud"
        case viewerOverlapWarning = "viewer-overlap-warning"
        case viewerMetricsStress = "viewer-metrics-stress"
    }

    public let identifier: Identifier
    public let surface: VisualQAPreviewSurface
    public let permissions: PermissionSnapshot
    public let displays: [DisplayInfo]
    public let selectedDisplayID: CGDirectDisplayID?
    public let isPreparing: Bool
    public let recoverableError: String?
    public let viewerMode: ViewerMode
    public let isOverlappingSource: Bool
    public let hudMessage: String?
    public let hudOpacity: Double
    public let metrics: CaptureMetricsSnapshot

    public init(identifier: Identifier) {
        self.identifier = identifier

        let previewDisplay = Self.previewDisplay
        switch identifier {
        case .selectionReady:
            surface = .selection
            permissions = .allGranted
            displays = [previewDisplay]
            selectedDisplayID = previewDisplay.id
            isPreparing = false
            recoverableError = nil
            viewerMode = .viewOnly
            isOverlappingSource = false
            hudMessage = nil
            hudOpacity = 0
            metrics = .nominalPreview
        case .selectionScreenRecordingDenied:
            surface = .selection
            permissions = PermissionSnapshot(screenRecording: false, postEvents: true, listenEvents: true, eventTapUsable: true)
            displays = []
            selectedDisplayID = nil
            isPreparing = false
            recoverableError = nil
            viewerMode = .viewOnly
            isOverlappingSource = false
            hudMessage = nil
            hudOpacity = 0
            metrics = .nominalPreview
        case .selectionInteractionDenied, .selectionAccessibilitySettings, .selectionInputMonitoringSettings:
            surface = .selection
            permissions = PermissionSnapshot(screenRecording: true, postEvents: false, listenEvents: false, eventTapUsable: false)
            displays = [previewDisplay]
            selectedDisplayID = previewDisplay.id
            isPreparing = false
            recoverableError = nil
            viewerMode = .viewOnly
            isOverlappingSource = false
            hudMessage = nil
            hudOpacity = 0
            metrics = .nominalPreview
        case .selectionNoExternalDisplay:
            surface = .selection
            permissions = .allGranted
            displays = []
            selectedDisplayID = nil
            isPreparing = false
            recoverableError = nil
            viewerMode = .viewOnly
            isOverlappingSource = false
            hudMessage = nil
            hudOpacity = 0
            metrics = .nominalPreview
        case .selectionRefreshError:
            surface = .selection
            permissions = .allGranted
            displays = [previewDisplay]
            selectedDisplayID = previewDisplay.id
            isPreparing = false
            recoverableError = "디스플레이 목록을 새로 고칠 수 없습니다. 연결 상태를 확인한 뒤 다시 시도하세요."
            viewerMode = .viewOnly
            isOverlappingSource = false
            hudMessage = nil
            hudOpacity = 0
            metrics = .nominalPreview
        case .viewerViewOnly:
            surface = .viewer
            permissions = .allGranted
            displays = [previewDisplay]
            selectedDisplayID = previewDisplay.id
            isPreparing = false
            recoverableError = nil
            viewerMode = .viewOnly
            isOverlappingSource = false
            hudMessage = nil
            hudOpacity = 0
            metrics = .nominalPreview
        case .viewerInteractiveReady:
            surface = .viewer
            permissions = .allGranted
            displays = [previewDisplay]
            selectedDisplayID = previewDisplay.id
            isPreparing = false
            recoverableError = nil
            viewerMode = .interactive
            isOverlappingSource = false
            hudMessage = nil
            hudOpacity = 0
            metrics = .nominalPreview
        case .viewerControlHUD:
            surface = .viewer
            permissions = .allGranted
            displays = [previewDisplay]
            selectedDisplayID = previewDisplay.id
            isPreparing = false
            recoverableError = nil
            viewerMode = .interactive
            isOverlappingSource = false
            hudMessage = Self.controlHUDMessage
            hudOpacity = 1
            metrics = .nominalPreview
        case .viewerReturnHUD:
            surface = .viewer
            permissions = .allGranted
            displays = [previewDisplay]
            selectedDisplayID = previewDisplay.id
            isPreparing = false
            recoverableError = nil
            viewerMode = .viewOnly
            isOverlappingSource = false
            hudMessage = Self.returnHUDMessage
            hudOpacity = 1
            metrics = .nominalPreview
        case .viewerOverlapWarning:
            surface = .viewer
            permissions = .allGranted
            displays = [previewDisplay]
            selectedDisplayID = previewDisplay.id
            isPreparing = false
            recoverableError = nil
            viewerMode = .interactive
            isOverlappingSource = true
            hudMessage = nil
            hudOpacity = 0
            metrics = .nominalPreview
        case .viewerMetricsStress:
            surface = .viewer
            permissions = .allGranted
            displays = [previewDisplay]
            selectedDisplayID = previewDisplay.id
            isPreparing = false
            recoverableError = nil
            viewerMode = .interactive
            isOverlappingSource = false
            hudMessage = nil
            hudOpacity = 0
            metrics = CaptureMetricsSnapshot(
                displayedFPS: 123.4,
                incompleteRatio: 0.987,
                receivedFrames: 987_654_321,
                displayedFrames: 876_543_210
            )
        }
    }

    public var windowTitle: String {
        "Visual QA - \(identifier.rawValue)"
    }

    public var windowSize: CGSize {
        switch surface {
        case .selection:
            CGSize(width: 620, height: 520)
        case .viewer:
            CGSize(width: 960, height: 680)
        }
    }

    public var canStartMirroring: Bool {
        permissions.canMirror && selectedDisplayID != nil && !isPreparing
    }

    public var permissionRequestNotice: PermissionRequestNotice? {
        switch identifier {
        case .selectionAccessibilitySettings:
            .manualSettingsRequired(.accessibility)
        case .selectionInputMonitoringSettings:
            .manualSettingsRequired(.inputMonitoring)
        default:
            nil
        }
    }

    public var selectionStateText: String {
        if isPreparing {
            return "preparing"
        }

        if recoverableError != nil {
            return "failed"
        }

        if displays.isEmpty {
            return "idle"
        }

        return "idle"
    }

    public static func parse(rawValue: String?) -> VisualQAPreviewState? {
        guard let rawValue else {
            return nil
        }

        let normalized = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty, let identifier = Identifier(rawValue: normalized) else {
            return nil
        }

        return VisualQAPreviewState(identifier: identifier)
    }

    public static func parse(environment: [String: String], arguments: [String]) -> VisualQAPreviewState? {
        if let argumentValue = argumentValue(in: arguments) {
            return parse(rawValue: argumentValue)
        }

        return parse(rawValue: environment["EDV_VISUAL_QA_STATE"])
    }

    private static func argumentValue(in arguments: [String]) -> String? {
        for (index, argument) in arguments.enumerated() {
            if argument == "--visual-qa-state" {
                return arguments.dropFirst(index + 1).first
            }

            if argument.hasPrefix("--visual-qa-state=") {
                return String(argument.dropFirst("--visual-qa-state=".count))
            }
        }

        return nil
    }

    private static let previewDisplay = DisplayInfo(
        id: 2,
        name: "Studio Display Preview",
        coreGraphicsFrame: CGRect(x: 1728, y: 0, width: 1920, height: 1080),
        appKitFrame: CGRect(x: 1728, y: 0, width: 1920, height: 1080),
        pixelSize: CGSize(width: 1920, height: 1080),
        scale: 1,
        isBuiltIn: false
    )
    private static let controlHUDMessage = InteractionHUDMessages.control
    private static let returnHUDMessage = InteractionHUDMessages.returnToViewer
}

private extension PermissionSnapshot {
    static let allGranted = PermissionSnapshot(
        screenRecording: true,
        postEvents: true,
        listenEvents: true,
        eventTapUsable: true
    )
}

private extension CaptureMetricsSnapshot {
    static let nominalPreview = CaptureMetricsSnapshot(
        displayedFPS: 59.8,
        incompleteRatio: 0.003,
        receivedFrames: 1800,
        displayedFrames: 1794
    )
}
#endif
