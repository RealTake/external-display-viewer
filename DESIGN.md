# External Display Viewer Design System

## 1. Atmosphere & Identity

External Display Viewer는 macOS 시스템 설정 패널처럼 조용하고 예측 가능한 작업 도구다. 시각적 서명은 영상 자체를 방해하지 않는 검은 Viewer 표면과, 제어권이 바뀌는 순간에만 캡처 영역 상단 중앙에 나타나는 반투명 HUD다. 장식보다 상태 가시성, 좌표 정확성, 안전한 복귀를 우선한다.

## 2. Color

### Semantic palette

| Role | SwiftUI token | Usage |
| --- | --- | --- |
| Surface/viewer | `Color.black` | 영상 배경과 레터박스 |
| Surface/panel | `.regularMaterial` | Viewer 제어·진단 푸터 |
| Surface/HUD | `.ultraThinMaterial` | 제어 전환과 복귀 HUD |
| Text/primary | `.primary` | 제목, 주요 라벨 |
| Text/secondary | `.secondary` | 설명, 상태, 진단 정보 |
| Status/success | `.green` | 허용된 권한 |
| Status/warning | `.orange` | 권한 누락, 겹침, 외부 디스플레이 없음 |
| Status/error | `.red` | 복구 가능한 오류 |

### Rules

- macOS의 Light/Dark Mode와 접근성 대비 설정을 따르도록 시스템 의미 색상과 Material을 사용한다.
- 상태 색상만으로 의미를 전달하지 않고 SF Symbol과 문구를 함께 표시한다.
- 새 고정 RGB/hex 색상은 추가하지 않는다. 새로운 의미 역할이 필요하면 먼저 이 표에 기록한다.
- Viewer 영상 영역은 좌표와 레터박스 경계를 분명하게 유지하기 위해 항상 검은색이다.

## 3. Typography

| Level | SwiftUI style | Weight | Usage |
| --- | --- | --- | --- |
| Screen title | `.title2` | semibold | 선택 창 제목 |
| Section title | `.headline` | system | Display, Permissions |
| Primary control | `.body` / control default | system | Picker, Button, Toggle |
| Status | `.callout` | system or monospaced digits | 상태와 오류 |
| Metadata | `.caption` | system | 디스플레이, 모드, 권한 설명 |
| Diagnostics | `.caption.monospacedDigit()` | system | FPS와 프레임 카운터 |
| HUD | `.callout` | semibold | 제어 전환 안내 |

- 글꼴은 macOS 시스템 글꼴과 시스템 고정폭 숫자만 사용한다.
- 사용자 텍스트 크기와 운영체제 렌더링을 보존하기 위해 고정 포인트 크기를 사용하지 않는다.
- 한글과 영문이 혼합된 라벨은 잘림보다 줄바꿈 또는 축소를 우선한다.

## 4. Spacing & Layout

### Extracted spacing tokens

기존 AppKit/SwiftUI 구현의 2pt 보조 그리드와 4pt 주 그리드를 그대로 계약화한다.

| Token | Value | Usage |
| --- | --- | --- |
| `space-tight` | 2pt | 권한 제목과 설명 |
| `space-xs` | 6pt | 헤더 내부, 상태 줄 |
| `space-sm` | 8pt | 선택 섹션과 Viewer 제어 행 |
| `space-control` | 10pt | 인라인 컨트롤과 권한 행 |
| `space-panel-x` | 12pt | Viewer 푸터 가로 패딩 |
| `space-hud` | 14pt | HUD 내부/상단 여백 |
| `space-section` | 18pt | 선택 창의 주요 섹션 간격 |
| `space-page` | 24pt | 선택 창 바깥 여백 |

### Window contracts

- 선택 창: 최소 560 × 460pt, 상단 왼쪽 정렬, 세로 Stack.
- Viewer: 최소 640 × 420pt. 남는 영역은 Viewer가 소유하고 제어 푸터와 진단 푸터는 하단에 고정한다.
- 영상은 소스 종횡비를 보존한 aspect-fit 사각형이며, 입력 좌표와 HUD 배치는 같은 `renderRect`를 사용한다.
- 진단 문자열이 길어지면 한 줄에서 최소 0.8까지 축소할 수 있으나 주요 제어는 가리지 않는다.

## 5. Components

### Display Selection Panel

- **Structure**: 제목/설명 → 외부 디스플레이 Picker → 권한 행 → Refresh/Start/Retry → 상태.
- **States**: idle, preparing, external-display empty, permission denied, recoverable error, ready.
- **Spacing**: `space-page`, `space-section`, `space-control`.
- **Accessibility**: 시스템 Picker/Button, 의미 있는 라벨, 기본 동작 키보드 단축키.
- **Motion**: 별도 장식 모션 없음. 상태 문구만 즉시 갱신한다.

### Permission Row

- **Structure**: SF Symbol + 권한명/설명 + 필요할 때 Request 버튼.
- **States**: granted, denied, check-only event-tap status.
- **Accessibility**: 아이콘과 색상에 더해 텍스트로 권한 상태와 용도를 설명한다.

### Viewer Surface

- **Structure**: direct IOSurface layer + 선택적 DEBUG 좌표 그리드 + HUD.
- **States**: no frame, view only, interactive, control HUD, return HUD.
- **Layout**: 영상 aspect-fit, 검은 레터박스, 입력과 표시가 공유하는 단일 `renderRect`.
- **Accessibility**: View Only가 기본이며 Interactive는 권한과 안전 조건을 모두 만족할 때만 가능하다.

### Viewer Controls Footer

- **Structure**: View Only/Interactive 상태 표시 + Always on Top + Stop, 디스플레이/모드 설명, 비활성 이유.
- **States**: view only, interactive available, interactive active, interaction blocked.
- **Accessibility**: 시스템 컨트롤, 명시적 비활성 사유, Stop의 cancel 단축키.
- **Surface**: `.regularMaterial`; 별도 테두리나 그림자 없음.

### Diagnostics Footer

- **Structure**: FPS, incomplete ratio, received/displayed frame counts.
- **States**: zero, nominal, long-number stress.
- **Accessibility**: 고정폭 숫자, 보조 텍스트 색, 한 줄 축소.

### Transition HUD

- **Structure**: 최대 420pt 폭의 중앙 정렬 텍스트와 `.ultraThinMaterial` 둥근 배경.
- **Variants**: control transfer, Viewer return.
- **States**: hidden, fading in, visible, fading out.
- **Accessibility**: 캡처 영역 top-center, 최대 2줄, hit testing 없음. 상태 변화는 동일한 의미의 모드 표시와 함께 제공된다.
- **Motion**: opacity만 160ms ease-in-out으로 전환; 제어 1.5초, 복귀 1.2초 표시.

### DEBUG Visual QA Harness

- **Structure**: 환경 변수로 하나의 결정적 선택/Viewer 상태를 렌더링하는 개발 전용 진입점.
- **States**: 선택 준비/권한 누락/외부 디스플레이 없음/오류, Viewer View Only/Interactive/겹침, 두 HUD, 진단 스트레스.
- **Constraint**: 실제 TCC 요청, ScreenCaptureKit, 이벤트 탭, 커서 이동을 생성하지 않는다. Release 빌드에는 포함되지 않는다.

## 6. Motion & Interaction

- 모션은 상태 변화 설명에만 사용한다. 장식 모션은 없다.
- HUD는 `opacity`만 160ms ease-in-out으로 전환하며 레이아웃 속성을 애니메이션하지 않는다.
- 제어권 전환 시 실제 포인터 이동과 HUD 표시가 같은 사용자 행위의 결과여야 한다.
- Interactive 진입은 실제 미러링 영상 영역 hover, 권한/이벤트 탭/겹침 게이트를 모두 거친다. 레터박스와 Viewer UI hover는 전환하지 않는다.
- 외부 디스플레이 상·하·좌·우 경계를 벗어나려 하면 Viewer의 대응 경계 비율 위치로 복귀하며, 복귀점은 레터박스/하단 컨트롤/가장 가까운 비영상 UI를 우선한다.
- 드래그 중 외부 경계 이탈은 자동 복귀하지 않고 경계에 클램프하며, 버튼 release 후 다음 바깥 방향 move에서 복귀한다.
- ESC 0.8초 길게 누르기는 안전 복귀를 실행하고, 짧은 ESC는 원래 frontmost 앱이 그대로일 때만 재생한다.
- `accessibilityReduceMotion` 환경에서도 HUD는 의미를 잃지 않으며, 비필수 이동 애니메이션을 추가하지 않는다.

## 7. Depth & Surface

전략은 **system-material tonal shift**다.

- Viewer 영상과 레터박스는 평평한 검은 기준면이다.
- 하단 제어/진단은 macOS `.regularMaterial`로 영상과 분리한다.
- 일시적 HUD만 `.ultraThinMaterial`로 한 단계 떠 보이게 한다.
- 임의 그림자, 장식 테두리, 브랜드 그라디언트를 추가하지 않는다.
- 시스템 Material이 제공하는 Light/Dark Mode, vibrancy, contrast 동작을 보존한다.

## 8. Accessibility Constraints & Accepted Debt

### Constraints

- macOS 시스템 컨트롤과 의미 색상을 사용하고 모든 기능 버튼에 읽을 수 있는 텍스트 라벨을 제공한다.
- Viewer 제어 모드는 기본적으로 View Only이며, 권한 또는 안전 조건이 충족되지 않으면 이유를 문장으로 표시한다.
- 오류는 복구 가능한 문구와 Retry 경로를 제공한다.
- 포인터를 외부 디스플레이로 이동한 뒤 사용자가 잃어버리지 않도록 ESC 길게 누르기 복귀 경로와 HUD 문구를 항상 함께 제공한다.
- 한글/CJK 혼합 문구, Light/Dark Mode, 확대된 텍스트, 키보드 포커스, Reduced Motion을 시각 QA에서 확인한다.

### Accepted debt

현재 승인된 디자인/접근성 부채는 없다. 실제 외부 모니터 상호작용, VoiceOver 전체 주행, 60초 프레임 지표와 240-FPS 지연 측정은 구현 부채가 아니라 별도의 하드웨어 검증 항목으로 추적한다.
