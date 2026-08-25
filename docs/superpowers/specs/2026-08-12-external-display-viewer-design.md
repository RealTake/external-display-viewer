# External Display Viewer 설계

## 1. 문서 상태

- 작성일: 2026-08-12
- 대상: macOS 15 이상
- 언어 및 UI: Swift 6, SwiftUI, AppKit
- 핵심 API: ScreenCaptureKit, CoreGraphics, CoreAnimation
- 배포 형태: 직접 실행하는 비샌드박스 macOS 앱
- 외부 패키지: 사용하지 않음

이 문서는 확장 모드로 연결된 외부 디스플레이를 MacBook의 Viewer 창에서 보고 조작하는 MVP의 승인된 설계다.

## 2. 목표

사용자는 macOS의 실제 디스플레이 구성을 확장 모드로 유지한 채 다음 작업을 수행할 수 있어야 한다.

1. 연결된 외부 디스플레이를 선택한다.
2. 선택한 디스플레이 전체 화면을 MacBook의 별도 Viewer 창에서 실시간으로 본다.
3. Viewer의 실제 미러링 영상 영역에 커서를 올리면 실제 시스템 포인터가 대응하는 외부 디스플레이 좌표로 이동한다.
4. 클릭, 우클릭, 중간 클릭, 더블 클릭, 드래그, 수직·수평 스크롤을 외부 화면에 전달한다.
5. 외부 화면 제어 중 ESC를 길게 누르면 포인터가 Viewer의 원래 위치로 복귀한다.

## 3. MVP 제외 범위

- 일반 키보드 입력 전달 및 합성
- 오디오 캡처
- 여러 외부 디스플레이의 동시 Viewer
- 네트워크 또는 VNC 기능
- Mac App Store 배포
- HDR 전용 렌더링과 색 공간 보정
- Metal 렌더러

외부 앱을 클릭해 포커스가 이동한 뒤의 실제 키보드 입력은 macOS가 해당 앱에 자연스럽게 전달한다. 앱은 일반 키보드 이벤트를 합성하지 않는다. 단, ESC 길게 누르기를 판별하기 위해 가로챈 짧은 ESC를 전면 앱이 바뀌지 않았을 때 돌려주는 down/up 재게시·검증만 제어 프로토콜의 예외로 허용한다.

## 4. 기술 검토와 선택

### 4.1 화면 캡처

`SCShareableContent`에서 `SCDisplay` 목록을 가져오고, 선택한 디스플레이로 `SCContentFilter`를 만든다. 필터는 데스크톱과 Dock을 포함하는 전체 디스플레이 캡처를 사용하되, 재귀 캡처가 발생하지 않도록 현재 앱의 창은 제외한다.

캡처 필터는 화면에 포함할 픽셀만 바꾸며 이벤트 hit testing에는 영향을 주지 않는다. Viewer 또는 이 앱의 다른 보이는 창이 원본 외부 디스플레이와 겹치면 게시한 이벤트가 앱 자신에게 전달될 수 있으므로 Interactive 모드는 이 앱의 보이는 창이 원본 디스플레이와 전혀 겹치지 않을 때만 허용한다. Chrome 같은 제어 대상 앱의 창은 이 검사 대상이 아니다.

### 4.2 렌더링

MVP는 `SCStream`이 제공하는 `CMSampleBuffer`에서 `CVPixelBuffer`와 IOSurface를 얻어 레이어 기반 `NSView`에 직접 표시한다.

선택 이유:

- CPU 이미지 복사가 필요 없다.
- 30~60 FPS에 적합하다.
- Metal 렌더러보다 구현과 장애 복구가 단순하다.
- Apple의 ScreenCaptureKit 예제와 같은 IOSurface 기반 경로를 사용한다.

Metal은 실제 측정에서 IOSurface 레이어 경로가 지연 또는 색 처리 목표를 만족하지 못할 때만 후속 단계로 도입한다.

### 4.3 실제 포인터 이동

Viewer의 실제 미러링 영상 영역에 포인터가 들어오면 `CGWarpMouseCursorPosition`으로 같은 정규화 위치의 외부 디스플레이 좌표로 실제 포인터를 이동하고 제어권을 넘긴다. 이 hover 진입에는 합성 mouse-down을 게시하지 않으며, 이후 실제 하드웨어 입력은 포인터가 놓인 외부 앱에 macOS가 직접 전달한다. 레터박스와 Viewer UI 진입은 전환하지 않는다.

기존 Viewer 클릭 기반 입력 합성은 hover 포털을 사용할 수 없는 경우를 위한 보조 경로로 유지한다. 이 경로의 단순 클릭은 합성 mouse-up이 끝난 뒤 외부 화면으로 제어권을 넘기며, Viewer에서 시작한 드래그는 Viewer가 mouse-up까지 완전히 소유하고 외부 화면에는 합성 down/dragged/up만 전달한다. 포인터를 즉시 Viewer로 되돌리는 방식은 hover와 드래그를 불안정하게 만들기 때문에 사용하지 않는다. ScreenCaptureKit이 외부 포인터를 함께 캡처하므로 사용자는 Viewer를 보면서 현재 포인터 위치를 확인할 수 있다.

## 5. 사용자 흐름

### 5.1 시작

1. 앱이 화면 기록, 이벤트 전송, 입력 감시 권한을 확인한다.
2. 권한이 부족하면 필요한 시스템 설정 위치와 재시작 필요 여부를 안내한다.
3. 앱이 연결된 디스플레이를 조회한다.
4. 내장 디스플레이와 외부 디스플레이를 이름, 해상도, 위치와 함께 표시한다.
5. 사용자가 외부 디스플레이를 선택하고 `Start Mirroring`을 누른다.

### 5.2 Viewer

Viewer는 일반 `NSWindow`이며 다음을 지원한다.

- 이동, 크기 조절, 최소화
- macOS 전체 화면
- Always on Top 토글
- View Only / Interactive 모드
- 원본 종횡비 유지와 검은색 레터박스
- 캡처 중지와 선택 화면 복귀

기본 모드는 View Only다. 이 모드에서는 Viewer의 캡처 영역이 click, drag, scroll 전달을 수행하지 않는다. 단, 실제 미러링 영상 영역 hover는 2026-08-13 포인터 포털의 진입 gate로 동작할 수 있으며, 레터박스와 컨트롤·진단 UI hover는 아무 동작도 하지 않는다.

Viewer는 기본적으로 내장 디스플레이에 연다. Viewer 프레임이 원본 외부 디스플레이와 교차하면 Interactive 진입을 차단하고 상태 표시를 View Only로 유지하며 내장 디스플레이로 옮기라는 안내를 표시한다. 전체 화면도 원본이 아닌 디스플레이에서만 허용한다.

### 5.3 외부 화면으로 제어 전환

2026-08-13 포인터 포털 설계가 이 절의 클릭-first 흐름을 오버레이한다. 현재 기본 동작은 Viewer의 실제 미러링 영상 영역에 커서가 들어오는 순간 전환하는 hover 포털이며, 아래 클릭 기반 흐름은 보조 fallback 경로로 유지한다. 레터박스, 하단 컨트롤, 진단 UI hover는 전환하지 않는다.

hover 포털은 다음 순서로 동작한다.

1. 진입점이 실제 캡처 영상 사각형 안인지 확인한다.
2. 권한, 이벤트 탭 사용 가능 여부, 소스 화면 겹침을 재검사한다.
3. Viewer 진입 위치를 외부 디스플레이의 같은 정규화 CoreGraphics 전역 좌표로 변환한다.
4. ESC 탭과 포인터 경계 탭을 시작한다.
5. ESC fallback을 위해 Viewer 진입 위치를 저장한다.
6. 실제 시스템 포인터를 변환 좌표로 이동한다.
7. Viewer에 제어 전환 HUD를 약 1.5초 표시한다.

기존 Interactive 클릭 fallback에서는 캡처 영역을 클릭하면 다음 순서로 동작한다.

1. 클릭 직전 시스템 포인터의 CoreGraphics 전역 좌표를 `returnPoint`로 저장한다.
2. 클릭이 실제 캡처 영역 안인지 확인한다. 레터박스면 중단한다.
3. Viewer 좌표를 외부 디스플레이 전역 좌표로 변환한다.
4. 실제 시스템 포인터를 변환 좌표로 이동한다.
5. 클릭 종류와 상태에 맞는 `CGEvent`를 게시한다.
6. 드래그라면 Viewer가 mouse-up까지 추적하고 외부 화면에 합성 dragged/up을 게시한다.
7. Viewer에 제어 전환 HUD를 약 1.5초 표시한다.

HUD 문구:

> 외부 디스플레이 제어 중 · 화면 경계 또는 ESC를 길게 눌러 돌아오기

HUD는 캡처 영역 중앙 상단에 표시되는 비차단 반투명 패널이다. 포인터 이벤트를 소비하지 않고 짧은 페이드인·페이드아웃만 사용한다.

외부 디스플레이 경계 복귀는 상·하·좌·우 모든 경계를 감시한다. 바깥 방향 이동이 감지되면 경계상의 위치 비율을 보존해 Viewer의 대응 경계로 돌아오며, 최종 지점은 영상 내부가 아니라 해당 방향의 레터박스, 하단 컨트롤 UI 또는 가장 가까운 비영상 영역이다. 드래그 중에는 자동 복귀하지 않고 외부 경계로 클램프하며, 버튼을 놓은 뒤 다음 바깥 방향 이동에서 복귀한다.

### 5.4 ESC 길게 눌러 복귀

외부 앱이 포커스를 가진 상태에서도 ESC를 감지해야 하므로 `CGEventTap`으로 전역 키 이벤트를 감시한다. 이벤트 탭은 `.cgSessionEventTap`, `.headInsertEventTap`, active/default 옵션을 사용하고 외부 제어가 활성화된 동안에만 ESC keyDown/keyUp을 가로챈다. 이벤트 탭 생성이 거부되거나 ESC 마스크가 사용할 수 없으면 외부 제어를 시작하지 않는다.

- ESC 누름 시작 시 0.8초 타이머를 시작한다.
- 첫 keyDown 시점의 전면 앱 PID와 원본 ESC 이벤트 복사본을 저장한다.
- ESC 반복 키 이벤트는 하나의 길게 누르기로 합친다.
- 0.8초 전에 키를 놓으면 저장한 PID가 아직 실행 중이고 현재 전면 앱 PID와 같을 때만 식별 값을 넣은 ESC down/up 복사본을 해당 PID로 게시한다.
- ESC를 누르는 동안 전면 앱이 바뀌면 잘못된 대상에 보내지 않도록 짧은 ESC를 폐기한다.
- 0.8초를 넘기면 ESC를 대상 앱에 전달하지 않고 복귀 절차를 실행한다.
- 재게시한 ESC에는 식별 값을 넣어 이벤트 탭이 다시 가로채지 않게 한다.

복귀 절차:

1. 드래그 중이면 현재 외부 좌표에 대응하는 mouse-up을 먼저 게시한다.
2. ESC 복귀는 포털 진입 당시 저장한 Viewer 위치 또는 클릭 fallback의 `returnPoint`로 이동한다.
3. Viewer 창을 앞으로 가져오고 활성화한다.
4. 입력 모드를 View Only로 바꾼다.
5. 복귀 HUD를 약 1.2초 표시한다.

복귀 HUD 문구:

> Viewer로 돌아왔습니다

Viewer가 이동했거나 저장 좌표가 현재 Viewer 범위를 벗어나면 현재 캡처 영역 중앙을 복귀 지점으로 사용한다. 외부 디스플레이 분리, 캡처 중단, 앱 종료도 같은 안전 복귀 절차를 사용한다.

## 6. 좌표계

`CoordinateMapper`는 UI와 시스템 API에서 분리된 순수 값 타입으로 구현한다.

입력:

- 외부 디스플레이의 `CGDisplayBounds`
- Viewer 콘텐츠 뷰 크기
- aspect-fit으로 계산한 실제 렌더링 영역
- Viewer 내부 포인터 위치

처리:

1. Viewer 안에서 캡처 영상이 차지하는 aspect-fit 사각형을 계산한다.
2. 포인터가 사각형 밖이면 `nil`을 반환한다.
3. 사각형 내부 좌표를 0...1 범위로 정규화한다.
4. 정규화 좌표를 `CGDisplayBounds`에 적용한다.
5. 최대 경계는 인접 디스플레이로 넘어가지 않도록 CoreGraphics 포인트 공간에서 `maxX.nextDown`과 `maxY.nextDown`까지 제한한다.

AppKit 입력 뷰는 위쪽이 원점이 되도록 뒤집어 사용한다. CoreGraphics 디스플레이 전역 좌표도 메인 디스플레이 왼쪽 위를 기준으로 하므로 입력 변환 과정에서 Retina 배율이나 추가 Y축 반전을 적용하지 않는다.

Retina 배율은 캡처 출력 크기에만 사용한다. `SCShareableContent`의 point-to-pixel scale을 사용해 `SCStreamConfiguration.width`와 `height`를 픽셀 단위로 설정한다.

## 7. 입력 이벤트

`InputEventManager`는 포인터 이동과 이벤트 게시를 담당한다.

- left down/up/click
- right down/up/click
- other down/up/click의 middle button
- click state를 포함한 double click
- left/right/other drag
- pixel 단위 수직·수평 scroll wheel

드래그는 Viewer가 받은 mouse-down부터 mouse-up까지 하나의 프록시 세션으로 유지한다. Viewer가 원본 하드웨어 down/dragged/up을 소유하고, 외부 앱에는 각각 대응하는 합성 down/dragged/up만 게시한다. 각 dragged 이벤트의 Viewer 좌표를 다시 변환해 외부 좌표에 게시하고, Viewer 밖 또는 레터박스로 이동한 좌표는 가장 가까운 캡처 경계로 제한한다. 중단·분리·ESC 복귀 시 반드시 대응하는 합성 mouse-up을 게시한다.

## 8. 상태 모델

`MirrorSession`은 다음 상태만 가진다.

- `idle`: 선택된 디스플레이와 스트림이 없음
- `preparing`: 권한과 공유 가능 콘텐츠 확인 중
- `viewOnly`: 캡처 중이며 입력 전달 비활성
- `interactiveReady`: 실제 미러링 영상 hover 포털 진입을 받을 준비가 됨. 클릭 기반 전환은 보조 경로로만 유지됨
- `controllingExternal`: 포인터가 외부 화면으로 이동했고 복귀 지점이 저장됨
- `returning`: mouse-up, 포인터 복귀, 창 활성화를 수행 중
- `failed`: 사용자에게 복구 가능한 오류를 표시

상태 전환은 `@MainActor`의 단일 조정자가 소유한다. 캡처 콜백과 전역 이벤트 탭은 상태를 직접 변경하지 않고 조정자에 메시지를 전달한다.

## 9. 구성 요소

### `AppCoordinator`

앱 상태, 선택 화면, MirrorSession과 Viewer 생명주기를 조정한다.

### `DisplayManager`

`SCShareableContent`와 CoreGraphics display ID를 연결하고 디스플레이 재구성 콜백을 처리한다.

### `PermissionManager`

다음을 각각 검사하고 요청한다.

- `CGPreflightScreenCaptureAccess` / `CGRequestScreenCaptureAccess`
- `CGPreflightPostEventAccess` / `CGRequestPostEventAccess`
- `CGPreflightListenEventAccess` / `CGRequestListenEventAccess`

권한별 기능과 실패 동작은 다음과 같다.

| 권한/API | 필요한 기능 | 거부 또는 실패 시 동작 |
| --- | --- | --- |
| Screen Recording / `CGPreflightScreenCaptureAccess` | 디스플레이 목록과 프레임 캡처 | 미러링 시작 차단, 화면 및 시스템 오디오 기록 설정 안내 |
| Accessibility·Post Event / `CGPreflightPostEventAccess` | 포인터 이동 후 클릭·드래그·스크롤 게시 | Viewer를 View Only로 제한, 손쉬운 사용 설정 안내 |
| Input Monitoring·Listen Event / `CGPreflightListenEventAccess` | 외부 앱이 활성화된 동안 ESC 감지 | Interactive 시작 차단, 입력 모니터링 설정 안내 |

권한 요청 결과와 실제 이벤트 탭 생성 결과를 별도로 확인한다. 시스템 설정 변경 뒤 현재 프로세스에서 권한이 갱신되지 않으면 앱 재실행을 안내한다. `CGEventTapCreate`가 `nil`을 반환하거나 필요한 키 마스크가 제거되면 Listen Event 권한이 있다고 가정하지 않는다.

### `ScreenCaptureManager`

`SCStream`, 출력 큐, 최신 IOSurface 프레임, 시작·중지·실패를 소유한다.

### `MirrorWindowController`

Viewer의 `NSWindow`, 전체 화면, Always on Top, 화면 선택 복귀를 관리한다.

### `MirrorSurfaceView`

IOSurface 렌더링, aspect-fit 영역 계산, AppKit 포인터 이벤트 수신을 담당한다.

### `CoordinateMapper`

Viewer 로컬 좌표를 외부 디스플레이 전역 좌표로 변환한다.

### `InputEventManager`

포인터 이동, 마우스 이벤트 게시, 드래그 상태와 안전 mouse-up을 담당한다.

### `EscapeReturnController`

전역 ESC 이벤트 탭, 0.8초 길게 누르기 판정, 짧은 ESC 재게시, 복귀 요청을 담당한다.

### `TransitionHUDController`

제어 진입과 Viewer 복귀 HUD의 메시지, 표시 시간, 페이드 전환을 관리한다.

## 10. 캡처 설정과 성능

- 전체 디스플레이용 `SCContentFilter`
- 60 FPS 목표의 `minimumFrameInterval`
- 낮은 지연을 우선한 `queueDepth = 3`
- BGRA 픽셀 포맷
- 원본 디스플레이의 point-to-pixel scale을 반영한 출력 크기
- 커서 포함
- 오디오 제외
- 완료 상태의 최신 프레임만 표시
- 프레임을 CPU 이미지로 변환하지 않음
- 매 프레임은 SwiftUI 상태로 발행하지 않고 IOSurface를 Viewer CALayer에 직접 표시
- 소스 크기가 바뀌거나 비워질 때만 레이아웃 재계산
- Viewer FPS는 최근 1초 동안 실제 표시된 프레임의 이동값으로 계산

프레임 처리 큐는 직렬로 유지하고 UI에는 최신 프레임만 전달한다. Viewer가 느려졌을 때 과거 프레임을 순서대로 재생하지 않는다.

## 11. 오류와 복구

- 화면 기록 권한 거부: 선택 화면에서 설정 이동 안내
- 이벤트 전송 권한 거부: View Only만 허용
- 입력 감시 권한 거부: 외부 제어 시작을 차단하고 ESC 복귀 불가 이유 안내
- Viewer가 원본 디스플레이와 교차: Interactive 비활성화와 내장 디스플레이 이동 안내
- 외부 디스플레이 분리: 안전 mouse-up과 포인터 복귀 후 세션 종료
- `SCStream` 중단: 마지막 프레임 위에 오류 오버레이를 표시하고 재시도 제공
- 이벤트 탭 비활성화: 한 번 재활성화하고 실패하면 즉시 포인터 복귀
- 정상 앱 종료: 스트림과 이벤트 탭을 정리하고 저장된 지점으로 포인터 복귀

강제 종료나 프로세스 충돌에서는 정리 코드 실행을 보장할 수 없다. 이 설계는 마우스와 커서를 분리하지 않으므로 이런 경우에도 사용자가 실제 마우스를 움직여 내장 디스플레이로 돌아올 수 있어야 한다.

## 12. 테스트

### 단위 테스트

`CoordinateMapper`:

- 동일 종횡비
- 가로 레터박스
- 세로 레터박스
- 레터박스 클릭 무시
- Retina 디스플레이
- 외부 디스플레이가 오른쪽, 왼쪽, 위, 아래에 있는 구성
- 음수 전역 좌표
- 최대 경계 클램핑

입력 상태:

- 좌클릭, 우클릭, 중간 클릭
- 더블 클릭의 click state
- 드래그 down/dragged/up 순서
- Viewer 경계와 레터박스 밖으로 이어지는 드래그 클램핑
- ESC 복귀 중 안전 mouse-up
- 짧은 ESC 재게시와 자체 이벤트 무시
- 짧은 ESC 대상 PID 종료 또는 포커스 변경
- 0.8초 경계 전후의 길게 누르기
- 유효하지 않은 복귀 지점의 중앙 대체

HUD:

- 진입과 복귀 메시지
- 표시 시간 후 자동 해제
- HUD가 hit testing을 차단하지 않음

### 통합 및 수동 검증

- `xcodebuild build`와 전체 단위 테스트
- 화면 기록 권한 허용·거부 흐름
- Accessibility와 Input Monitoring 허용·거부 흐름
- 실제 외부 모니터에서 Chrome 클릭, 우클릭, 스크롤, 드래그
- Viewer가 원본 외부 디스플레이와 겹칠 때 Interactive 차단
- ESC 길게 누르기 복귀와 짧은 ESC 전달
- Viewer 크기 조절, 전체 화면, Always on Top
- 외부 디스플레이 케이블 분리 중 복귀
- 원본 해상도에서 60초 동안 최근 1초 표시 FPS를 주기적으로 표본 기록하고 불완전·누락 프레임 비율 기록
- 240 FPS 카메라 촬영으로 입력 시점부터 Viewer 피드백까지 지연 측정

성능 합격 기준:

- 원본 해상도에서 60초 동안 표본 기록한 최근 1초 표시 FPS의 평균 30 이상
- 불완전·누락 프레임 비율 5% 미만
- 입력부터 Viewer의 시각 변화까지 지연 중앙값 100 ms 이하, 95백분위 180 ms 이하

현재 자동 실행 환경에서는 온라인 디스플레이가 노출되지 않으므로 외부 모니터가 필요한 항목은 컴파일·단위 테스트와 별도로 실제 GUI 세션에서 검증한다.

## 13. MVP 완료 조건

다음 시나리오가 모두 성공하면 MVP를 완료한 것으로 판단한다.

1. 외부 디스플레이를 선택하고 Viewer를 연다.
2. Viewer가 외부 화면 전체를 종횡비에 맞게 실시간 표시한다.
3. Viewer의 실제 미러링 영상 영역에 커서를 올리면 실제 포인터가 같은 normalized 외부 좌표로 이동한다.
4. 레터박스, 컨트롤 UI, 진단 UI hover는 아무 동작도 하지 않는다.
5. 클릭 기반 진입 경로는 hover 포털을 보조하는 fallback으로만 동작한다.
6. Chrome에서 좌클릭, 우클릭, 스크롤, 드래그가 동작한다.
7. Viewer를 포함한 이 앱의 보이는 창이 원본 외부 화면과 겹치면 Interactive가 시작되지 않는다.
8. 외부 제어 진입 HUD가 잠깐 표시된다.
9. 짧은 ESC는 누르는 동안 같은 앱이 계속 전면에 있을 때만 해당 앱에 전달된다.
10. ESC를 0.8초 이상 누르면 포인터가 원래 Viewer 위치로 돌아온다.
11. Viewer가 다시 활성화되고 복귀 HUD가 표시된다.
12. 디스플레이가 분리되어도 버튼이 눌린 상태나 외부 포인터 고립이 남지 않는다.
13. 60초 성능 측정이 FPS, 누락 프레임, 지연 기준을 만족한다.

## 14. 참고 자료

- [Capturing screen content in macOS](https://developer.apple.com/documentation/screencapturekit/capturing-screen-content-in-macos)
- [CGEvent](https://developer.apple.com/documentation/coregraphics/cgevent)
- [CGWarpMouseCursorPosition](https://developer.apple.com/documentation/coregraphics/cgwarpmousecursorposition%28_%3A%29)
- [CGDisplayBounds](https://developer.apple.com/documentation/coregraphics/cgdisplaybounds%28_%3A%29)
- [CGPreflightListenEventAccess](https://developer.apple.com/documentation/coregraphics/cgpreflightlisteneventaccess%28%29)
- [CGPreflightPostEventAccess](https://developer.apple.com/documentation/coregraphics/cgpreflightposteventaccess%28%29)
