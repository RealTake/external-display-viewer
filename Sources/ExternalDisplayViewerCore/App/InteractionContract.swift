public enum InteractionContract {
    public static let escapeHoldDuration: Duration = .milliseconds(800)
    public static let controlHUDDuration: Duration = .milliseconds(1500)
    public static let returnHUDDuration: Duration = .milliseconds(1200)
}

public enum InteractionHUDMessages {
    public static let control = "외부 디스플레이 제어 중 · 화면 경계 또는 ESC를 길게 눌러 돌아오기"
    public static let returnToViewer = "Viewer로 돌아왔습니다"
}

public enum PermissionGuidanceCopy {
    public static let screenRecordingNote = "허용 후 앱 재시작 필요"
    public static let screenRecordingRestartGuidance =
        "Screen Recording을 허용한 뒤 앱을 완전히 종료하고 다시 실행하세요."
}
