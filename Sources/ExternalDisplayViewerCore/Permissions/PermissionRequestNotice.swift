public enum PermissionSettingsPane: Equatable, Sendable {
    case screenRecording
    case accessibility
    case inputMonitoring

    var systemSettingsAnchor: String {
        switch self {
        case .screenRecording:
            "Privacy_ScreenCapture"
        case .accessibility:
            "Privacy_Accessibility"
        case .inputMonitoring:
            "Privacy_ListenEvent"
        }
    }
}

public enum PermissionRequestNotice: Equatable, Sendable {
    case manualSettingsRequired(PermissionSettingsPane)
}
