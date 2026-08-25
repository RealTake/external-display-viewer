#if DEBUG
import CoreGraphics
import SwiftUI

@MainActor
public struct VisualQAPreviewRoot: View {
    private let state: VisualQAPreviewState

    public init(state: VisualQAPreviewState) {
        self.state = state
    }

    public var body: some View {
        switch state.surface {
        case .selection:
            VisualQASelectionPreview(state: state)
        case .viewer:
            ViewerRootView(previewState: state)
        }
    }
}

@MainActor
private struct VisualQASelectionPreview: View {
    let state: VisualQAPreviewState

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            displaySelection
            permissions
            actions
            status
        }
        .padding(24)
        .frame(minWidth: 560, minHeight: 460, alignment: .topLeading)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("External Display Viewer")
                .font(.title2.weight(.semibold))
            Text("외부 디스플레이를 선택한 뒤 Viewer 영상 영역에 커서를 올려 외부 화면을 제어하세요.")
                .foregroundStyle(.secondary)
        }
    }

    private var displaySelection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("External Display")
                .font(.headline)

            Picker("Display", selection: .constant(state.selectedDisplayID)) {
                if state.displays.isEmpty {
                    Text("연결된 외부 디스플레이 없음").tag(Optional<CGDirectDisplayID>.none)
                }

                ForEach(state.displays) { display in
                    Text(display.menuLabel).tag(Optional(display.id))
                }
            }
            .labelsHidden()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var permissions: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Permissions")
                .font(.headline)

            permissionRow(
                title: "Screen Recording",
                granted: state.permissions.screenRecording,
                note: PermissionGuidanceCopy.screenRecordingNote,
                actionTitle: "Request"
            )
            permissionRow(
                title: "Accessibility / Post Event",
                granted: state.permissions.postEvents,
                note: "클릭·드래그·스크롤 전달에 필요",
                actionTitle: "Request"
            )
            permissionRow(
                title: "Input Monitoring / Listen Event",
                granted: state.permissions.listenEvents,
                note: "외부 앱 포커스 상태에서 ESC 복귀 감지에 필요",
                actionTitle: "Request"
            )
            permissionRow(
                title: "ESC Event Tap",
                granted: state.permissions.eventTapUsable,
                note: "Interactive 시작 직전에 실제 사용 가능 여부를 다시 확인",
                actionTitle: nil
            )
        }
    }

    private var actions: some View {
        HStack(spacing: 10) {
            Button("Refresh") {}

            Button(state.isPreparing ? "Preparing..." : "Start Mirroring") {}
                .disabled(!state.canStartMirroring)
                .keyboardShortcut(.defaultAction)

            if state.recoverableError != nil {
                Button("Retry") {}
            }
        }
    }

    private var status: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("State: \(state.selectionStateText)")
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)

            if let recoverableError = state.recoverableError {
                Text(recoverableError)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            } else if let permissionRequestMessage {
                Text(permissionRequestMessage)
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            } else if !state.permissions.screenRecording {
                Text(PermissionGuidanceCopy.screenRecordingRestartGuidance)
                    .font(.callout)
                    .foregroundStyle(.orange)
            } else if state.displays.isEmpty {
                Text("확장 모드 외부 디스플레이가 감지되지 않았습니다.")
                    .font(.callout)
                    .foregroundStyle(.orange)
            }
        }
    }

    private var permissionRequestMessage: String? {
        switch state.permissionRequestNotice {
        case .manualSettingsRequired(.screenRecording):
            PermissionGuidanceCopy.screenRecordingRestartGuidance
        case .manualSettingsRequired(.accessibility):
            "시스템 설정 > 개인정보 보호 및 보안 > 손쉬운 사용에서 이 앱을 켠 뒤 다시 실행하세요."
        case .manualSettingsRequired(.inputMonitoring):
            "시스템 설정 > 개인정보 보호 및 보안 > 입력 모니터링에서 이 앱을 켠 뒤 다시 실행하세요."
        case nil:
            nil
        }
    }

    private func permissionRow(title: String, granted: Bool, note: String, actionTitle: String?) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(granted ? .green : .orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let actionTitle, !granted {
                Button(actionTitle) {}
            }
        }
    }
}
#endif
