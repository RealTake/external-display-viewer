# Viewer 포인터 포털 설계

## 1. 문서 상태와 우선순위

- 작성일: 2026-08-13
- 상태: 구현 반영 완료, 물리 외부 모니터 QA 대기
- 대상: macOS 15 이상, 확장 모드 외부 디스플레이
- 관련 설계: `2026-08-12-external-display-viewer-design.md`

이 문서는 기존 External Display Viewer 설계의 포인터 전환 부분을 확장한다. 두 문서가 충돌하면 Viewer 진입, 외부 화면 경계 복귀, HUD 문구에는 이 문서를 우선 적용한다. 캡처, 렌더링, 권한, 창 겹침 방지, ESC 길게 누르기와 안전 복귀 계약은 기존 설계를 유지한다.

## 2. 목표

사용자가 Viewer의 실제 미러링 영상과 외부 디스플레이 사이를 하나의 연속된 포인터 공간처럼 이동할 수 있게 한다.

1. Viewer의 실제 영상 영역에 커서가 들어오면 클릭 없이 즉시 Interactive로 전환한다.
2. Viewer 진입 위치와 같은 정규화 좌표의 외부 디스플레이 위치로 실제 커서를 이동한다.
3. 외부 디스플레이의 상·하·좌·우 경계를 벗어나려 하면 Viewer의 대응 경계로 돌아온다.
4. 복귀 위치는 영상 내부가 아니라 빠져나온 방향의 레터박스, 컨트롤 UI 또는 가장 가까운 비영상 영역이다.
5. 경계상의 위치 비율을 보존해 포인터가 끊기지 않고 이어진 것처럼 보이게 한다.
6. ESC 길게 누르기는 언제나 별도의 안전 복귀 수단으로 유지한다.

## 3. 확정된 사용자 동작

### 3.1 Viewer에서 외부 화면으로 진입

- 추적 대상은 Viewer 전체 창이 아니라 aspect-fit으로 계산한 실제 영상 사각형이다.
- 레터박스, 하단 컨트롤, 진단 정보와 창 크롬에서는 자동 전환하지 않는다.
- 커서가 영상 사각형의 바깥에서 안으로 교차한 순간 전환을 시작한다. dwell이나 클릭을 요구하지 않는다.
- 화면 기록, Accessibility/Post Event, Input Monitoring/Listen Event, 이벤트 탭 사용 가능 여부와 소스 화면 겹침 검사를 통과해야 한다.
- Viewer 로컬 진입점을 외부 디스플레이의 CoreGraphics 전역 좌표로 변환한다.
- 실제 커서를 변환 좌표로 이동하고 Viewer 상태를 `controllingExternal`로 전환한다.
- hover 진입에는 합성 mouse-down을 만들지 않는다. 이후의 실제 포인터 입력은 커서가 위치한 외부 앱에 macOS가 직접 전달한다.
- hover warp만으로 외부 앱의 키보드 포커스가 바뀐다고 가정하지 않는다. 키보드 입력은 사용자가 외부 앱을 정상적으로 클릭해 macOS 포커스가 바뀐 뒤에만 해당 앱에 전달되며, 앱은 일반 키보드 입력을 합성하지 않는다.
- 기존 클릭 기반 전환 코드는 안전한 보조 경로로 유지한다.

### 3.1.1 모드 의미

- 자동 포털은 기존의 명시적 Interactive 선택 후 클릭하는 기본 흐름을 대체한다.
- 미러링 시작 직후와 복귀 직후의 세션 상태는 View Only지만, 권한과 창 겹침 게이트가 허용되면 포털 진입은 항상 준비된 상태다.
- 기존 View Only / Interactive 모드 컨트롤은 사용자 설정 토글이 아니라 현재 세션 상태를 보여주는 비활성 상태 표시로 바꾼다.
- 영상 진입이 확정되면 Interactive, 경계·ESC·오류 복귀가 완료되면 View Only를 표시한다.
- 권한 또는 창 겹침 때문에 자동 포털을 사용할 수 없으면 View Only를 유지하고 기존 안내 문구를 표시한다.

### 3.2 외부 화면에서 Viewer로 복귀

- 외부 디스플레이의 상·하·좌·우 모든 경계를 감시한다.
- 커서 좌표가 디스플레이 밖으로 넘어간 경우뿐 아니라 데스크톱 끝에서 좌표가 경계에 고정된 채 바깥 방향 이동량이 발생한 경우도 이탈 시도로 판정한다.
- 코너에서는 바깥 방향 이동량의 절댓값이 더 큰 축을 우선한다. 값이 같으면 마지막으로 확정된 이동 축을 사용해 한 경계만 선택한다.
- 선택한 경계에서 커서 위치를 0...1 비율로 정규화하고 Viewer 영상의 같은 경계와 같은 비율 위치로 역매핑한다.
- 최종 복귀점은 영상 사각형에서 해당 방향으로 안전 여백만큼 바깥쪽에 둔다.
  - 하단은 컨트롤 UI 영역을 우선한다.
  - 좌·우·상단은 해당 위치의 레터박스 또는 가장 가까운 비영상 영역을 우선한다.
  - 정확히 대응하는 비영상 띠가 없으면 Viewer 창 안의 가장 가까운 안전 지점으로 제한한다.
- Viewer 창이 이동 또는 리사이즈되어도 복귀 직전에 현재 영상 사각형과 Viewer 창 사각형을 다시 읽는다.
- 복귀가 끝나면 Viewer를 앞으로 가져오고 View Only로 전환한다.

### 3.3 드래그 중 경계

- 포인터 경계 감시기는 외부 앱에 직접 전달되는 left, right, middle down/up/dragged를 관찰하고 눌린 버튼 집합과 마지막 유효 외부 좌표를 기록한다.
- left, right, middle 버튼 중 하나라도 눌린 드래그 이벤트에서는 자동 경계 복귀를 실행하지 않는다.
- 드래그가 외부 디스플레이 밖으로 나가려 하면 이벤트 좌표를 가장 가까운 외부 경계로 제한해 커서와 대상 앱의 dragged 위치를 같은 경계에 유지한다.
- 버튼을 놓은 뒤 바깥 방향의 일반 mouse-move가 다시 발생할 때 복귀한다.
- ESC, 디스플레이 분리, 캡처 실패, 이벤트 탭 실패처럼 안전상 강제 복귀가 필요한 경우에는 직접 입력 세션에서 눌린 각 버튼의 대응 mouse-up을 마지막 외부 좌표에 한 번 게시한 뒤 복귀한다.
- 강제 mouse-up 뒤 실제 버튼이 아직 눌려 있으면 포인터 탭은 해당 물리 mouse-up을 한 번 억제한 뒤 정리한다. 이미 해제된 버튼에는 추가 mouse-up을 게시하지 않는다.
- 기존 Viewer 클릭 기반 합성 드래그는 `InputEventManager`의 활성 시퀀스와 기존 안전 mouse-up 경로가 계속 소유한다.

### 3.4 재진입 방지

- `CGWarpMouseCursorPosition` 호출 자체에는 포인터 이동 이벤트가 발생하지 않는다는 API 계약을 이용하되, 상태 머신에서도 한 번의 진입과 한 번의 복귀만 허용한다.
- 복귀점은 영상 사각형 바깥에 둔다.
- `returning` 동안 Viewer hover 이벤트를 무시한다.
- 정상 경계 복귀 완료 후 실제 커서가 다시 영상 영역을 바깥에서 안으로 교차해야 다음 포털 세션을 시작한다.
- geometry 오류 때문에 비영상 복귀점을 만들지 못해 영상 내부 fallback을 사용한 경우에는 포털을 `disarmedUntilExit` 상태로 둔다. 커서가 영상 밖으로 실제 이동한 것이 확인되기 전에는 hover 진입을 다시 허용하지 않는다.
- 시간 기반 지연은 기본 동작에 넣지 않는다. 좌표와 상태 기반 재무장만으로 즉각적인 재진입 의도를 보존한다.

## 4. 검토한 구현 방식

### 4.1 선택: `NSTrackingArea`와 전용 포인터 경계 감시기

- Viewer 영상 진입은 `MirrorSurfaceView`의 `NSTrackingArea`로 처리한다.
- 외부 앱이 전면에 있는 동안에는 별도의 CoreGraphics 이벤트 탭으로 move/down/up/dragged를 관찰한다.
- 일반 move/down/up은 그대로 통과시키고, 외부 경계를 벗어나려는 dragged 좌표만 경계로 제한한다. 따라서 포인터 탭은 `.defaultTap`을 사용하되 변경 범위를 포털 세션의 외부 경계 드래그로 한정한다.
- ESC 키 탭과 포인터 탭의 책임과 수명 주기를 분리한다.
- 기존 `AppCoordinator`의 권한 게이트와 안전 복귀 경로를 재사용한다.

선택 이유:

- Viewer 내부 추적과 시스템 전역 추적을 각각 맞는 API에서 처리한다.
- 타이머 폴링보다 반응이 빠르고 불필요한 주기 작업이 없다.
- 복잡한 ESC 억제·재게시 로직에 마우스 처리를 섞지 않아 회귀 범위를 줄인다.

### 4.2 제외: 전역 커서 위치 폴링

구현은 단순하지만 주기 선택에 따라 지연 또는 CPU 사용이 생기며, 데스크톱 끝에서의 바깥 방향 의도를 정확히 보존하기 어렵다.

### 4.3 제외: 기존 ESC 이벤트 탭에 마우스 통합

이벤트 탭 수는 줄지만 ESC 짧게 누르기 재게시, 길게 누르기 타이머, 탭 재활성화와 포인터 경계 상태가 한 객체에 결합된다. 안전 복귀의 회귀 위험이 커서 채택하지 않는다.

## 5. 좌표와 경계 모델

### 5.1 진입 좌표

`PointerPortalMapper`는 다음 입력을 받는 순수 값 로직으로 둔다.

- Viewer 로컬 진입점
- Viewer 로컬 영상 사각형
- 외부 디스플레이 CoreGraphics 전역 사각형

진입점이 영상 사각형 안이면 각 축을 0...1로 정규화해 외부 사각형에 적용한다. 최대 좌표는 기존 `CoordinateMapper`와 동일하게 `maxX.nextDown`, `maxY.nextDown`으로 제한한다.

### 5.2 이탈 판정

`PointerBoundaryController`가 직전 위치, 현재 이벤트 위치와 `mouseEventDeltaX/Y`, 눌린 버튼 집합을 사용한다.

- 현재 위치가 외부 사각형 밖이면 직전 위치에서 현재 위치로 이어지는 선분과 처음 교차한 경계를 선택한다.
- 현재 위치가 외부 경계 안쪽에 고정되어 있어도 경계 허용 오차 안에서 이동량이 바깥을 향하면 해당 경계를 선택한다.
- dragged 이벤트는 위치와 버튼 상태를 추적하고 외부 경계로 제한하지만 복귀를 발생시키지 않는다.
- 하나의 포털 세션에서 첫 이탈만 coordinator에 전달한다.

### 5.3 복귀 좌표

`PointerPortalMapper`는 다음 입력으로 복귀점을 계산한다.

- 이탈 경계
- 해당 경계상의 정규화 위치
- 현재 Viewer 영상의 CoreGraphics 전역 사각형
- 현재 Viewer 영상 surface, 콘텐츠와 창의 CoreGraphics 전역 사각형
- surface의 레터박스 띠와 콘텐츠의 컨트롤·진단 영역으로 계산한 비영상 landing region 목록
- 영상 바깥 안전 여백

경계 방향과 평행한 축에는 정규화 위치를 적용한다. 수직 축 또는 수평 축은 영상 경계에서 바깥 방향으로 이동시키고 대응 비영상 landing region 안으로 제한한다. 정확한 대응 띠가 없으면 같은 축 위치를 가장 잘 보존하는 비영상 영역, 하단 컨트롤 영역 순으로 선택한다.

경계 복귀는 영상 중앙을 fallback으로 사용하지 않는다. 현재 geometry로 비영상 지점을 만들지 못하면 포털 진입 때 저장한 geometry로 다시 계산한다. 저장 geometry도 무효이면 기존 저장 진입점을 사용하되 `disarmedUntilExit`로 복귀해 영상 밖 실제 이동 전까지 자동 재진입을 차단한다.

## 6. 상태와 데이터 흐름

포털 제어 상태는 `AppCoordinator`가 소유하고 View와 이벤트 탭은 의도만 전달한다.

1. `viewOnly`: Viewer 영상 진입을 기다린다.
2. `enteringPortal`: 권한·겹침 검사, 현재 Viewer geometry 수집, ESC 탭과 포인터 탭 시작을 원자적으로 수행한다.
3. `controllingExternal`: 실제 커서가 외부 화면에 있으며 일반 입력은 macOS가 대상 앱에 직접 전달한다.
4. `returning`: 첫 경계 이탈 또는 기존 안전 복귀 이유를 처리한다.
5. `viewOnly`: 정상 복귀 완료 후 다음 실제 교차를 기다린다.
6. `disarmedUntilExit`: 비영상 복귀점 계산 실패 시 영상 밖 이동을 확인한 뒤 `viewOnly`로 돌아간다.

진입 순서:

1. Viewer 영상 `mouseEntered` 수신
2. 중복 진입과 드래그 여부 확인
3. 권한과 소스 겹침 재검사
4. Viewer 로컬 좌표를 외부 전역 좌표로 변환
5. ESC 탭과 포인터 경계 탭 시작
6. 현재 Viewer 진입점을 ESC 복귀용 지점으로 저장
7. 실제 커서 warp
8. `controllingExternal`과 Interactive UI 게시
9. 제어 HUD 표시

경계 복귀 순서:

1. 포인터 경계 탭이 이탈 경계와 정규화 위치를 한 번 전달
2. coordinator가 `returning`으로 전환
3. 기존 합성 입력 또는 직접 입력의 눌린 버튼이 있으면 안전 mouse-up
4. ESC 탭을 중지하고 포인터 경계 탭을 release-drain 상태로 전환한다. 대기 중인 물리 mouse-up이 없으면 즉시 중지하고, 있으면 해당 up을 한 번 억제한 뒤 중지한다.
5. 현재 Viewer 영상·창 geometry 재조회
6. 비영상 복귀점 계산 후 cursor warp
7. 앱 활성화와 Viewer 전면 배치
8. View Only 게시
9. 복귀 HUD 표시

## 7. 구성 요소 변경

### `MirrorSurfaceView`

- 현재 렌더 사각형에 맞춘 tracking area를 layout 변경 시 갱신한다.
- tracking area는 `.mouseEnteredAndExited`와 `.activeAlways`를 사용하고, 렌더 사각형이 바뀔 때 기존 area를 제거한 뒤 새 사각형으로 교체한다.
- `NSEvent.pressedMouseButtons != 0`인 진입은 무시한다.
- 영상 진입 이벤트에 로컬 좌표와 현재 render rect를 담아 전달한다.
- 레터박스와 Viewer UI는 추적 대상에서 제외한다.

### `MirrorSurfaceRepresentable` / `ViewerViewModel`

- 포털 진입 callback을 coordinator까지 전달한다.
- Interactive/View Only 표시는 coordinator가 확정한 현재 상태만 반영한다.

### `PointerBoundaryController`

- 포털 세션 동안만 mouse-move/down/up/dragged 이벤트 탭을 유지한다.
- 실제 외부 입력의 눌린 버튼 집합과 마지막 유효 외부 좌표를 추적한다.
- 이벤트 위치와 이동량으로 네 경계 이탈을 판정한다.
- 드래그 이탈 이벤트는 좌표를 외부 경계로 제한하고 대상 앱에 제한된 이벤트를 전달한다.
- 강제 복귀 시 직접 입력의 안전 mouse-up과 이후 물리 mouse-up 한 번 억제를 소유한다.
- 이탈 callback은 세션당 한 번만 보낸다.
- 탭 비활성화 시 기존 이벤트 탭 실패 안전 복귀를 요청한다.

### `PointerPortalMapper`

- 진입, 경계 선택, 역매핑과 안전 여백을 UI·이벤트 탭에서 분리된 순수 로직으로 제공한다.

### `MirrorWindowController`

- 기존 영상 전역 사각형과 함께 surface, 콘텐츠, 창의 전역 사각형을 제공한다.
- 이 geometry로 레터박스 띠와 하단 컨트롤·진단 landing region을 계산할 수 있어야 한다.

### `AppCoordinator`

- 포털 진입을 권한, 창 겹침과 세션 상태로 게이트한다.
- ESC 탭과 포인터 탭의 시작 실패를 원자적으로 롤백한다.
- 경계 복귀점을 기존 안전 복귀 경로의 선택적 target으로 전달한다.
- ESC는 저장된 Viewer 진입점, 경계 이탈은 계산된 대응 경계점을 사용한다.

## 8. 오류와 안전 동작

- 권한 또는 소스 겹침 게이트 실패: warp하지 않고 View Only 유지
- 포인터 이벤트 탭 시작 실패: 시작한 ESC 탭을 중지하고 View Only 유지
- ESC 탭 시작 실패: 포인터 탭을 시작하지 않고 View Only 유지
- 진입 좌표 또는 Viewer geometry 무효: 전환하지 않음
- 외부 warp 실패: 두 탭을 중지하고 View Only 복구
- 경계 복귀점 계산 실패: 현재 geometry, 포털 진입 때 저장한 geometry 순으로 비영상 지점을 계산하고, 모두 실패하면 저장 진입점으로 복귀한 뒤 `disarmedUntilExit` 유지
- 복귀 warp 실패: 탭을 중지하고 View Only와 복구 가능한 오류를 게시
- 이벤트 탭 비활성화: 한 번 재활성화하고 실패하면 기존 안전 복귀 실행
- 디스플레이 분리·캡처 실패·앱 종료: 기존 안전 복귀 경로 사용

강제 종료나 프로세스 충돌에서는 정리 코드를 보장할 수 없다. 포인터를 실제 커서와 분리하거나 가두지 않으므로 사용자는 실제 마우스로 다른 화면으로 이동할 수 있다.

## 9. HUD와 UI

제어 HUD 문구를 다음으로 갱신한다.

> 외부 디스플레이 제어 중 · 화면 경계 또는 ESC를 길게 눌러 돌아오기

복귀 HUD는 유지한다.

> Viewer로 돌아왔습니다

모드 컨트롤은 비활성 상태 표시로 현재 세션 상태만 반영한다. Viewer 영상 진입 시 Interactive, 경계 또는 ESC 복귀 시 View Only가 된다. 레터박스와 컨트롤 UI의 hit testing은 유지한다.

## 10. 테스트 전략

### 단위 테스트

`PointerPortalMapper` 진입/이탈:

- 영상 중앙과 네 모서리 진입 좌표
- 가로·세로 레터박스에서 영상 밖 진입 무시
- 왼쪽·오른쪽·위·아래 및 음수 원점 외부 디스플레이
- 최대 경계 `nextDown` 제한

`PointerBoundaryController`의 순수 판정 상태:

- 네 경계의 실제 좌표 이탈
- 데스크톱 끝에서 좌표 고정 + 바깥 방향 delta
- 안쪽 방향과 경계 평행 이동 무시
- 코너에서 주 이동축 선택
- dragged 이벤트에서 복귀 억제
- 외부 경계를 넘는 dragged 이벤트의 좌표 제한
- 직접 입력 down/up의 눌린 버튼 집합과 마지막 좌표 추적
- 버튼 해제 후 다음 바깥 mouse-move에서 복귀
- 강제 복귀의 버튼별 mouse-up 한 번과 후속 물리 up 억제
- 세션당 이탈 callback 한 번
- 탭 비활성화 재시도와 실패

`PointerPortalMapper` 복귀:

- 네 경계와 0, 0.5, 1 위치 비율 보존
- 하단 컨트롤 UI, 좌·우·상단 레터박스 복귀
- 영상 사각형 바깥 안전 여백
- Viewer 리사이즈·이동과 음수 전역 좌표
- 대응 비영상 띠가 없을 때 다른 비영상 영역과 하단 컨트롤 fallback
- 현재 geometry 실패 시 저장 geometry 사용
- 모든 geometry 실패 시 저장 진입점과 `disarmedUntilExit`

`AppCoordinator`:

- hover 진입의 gate → taps → warp → state → HUD 순서
- 합성 mouse-down 없이 포털 제어 시작
- hover warp만으로 외부 앱의 키보드 포커스가 바뀌었다고 가정하지 않음
- tap 또는 warp 실패 시 완전 롤백
- 경계 복귀의 cancel → taps stop → geometry → warp → activate → View Only → HUD 순서
- 경계 복귀와 ESC 복귀의 서로 다른 target 정책
- 중복 진입·중복 이탈·동시 ESC의 idempotence
- 기존 클릭 기반 전환과 ESC 회귀 없음

### 시각 및 수동 검증

- DEBUG Viewer 상태에서 갱신된 제어 HUD와 기존 복귀 HUD 캡처
- 모든 기존 selection/viewer 시각 QA 상태 회귀 확인
- 실제 외부 모니터에서 영상 중앙과 네 경계 진입·복귀
- 레터박스가 있는 Viewer와 하단 컨트롤 UI로 위치 비율 복귀
- 데스크톱 가장자리와 다른 디스플레이가 인접한 경계 모두 확인
- 외부 앱 일반 클릭, 스크롤, 짧은 ESC, ESC 길게 누르기
- 외부 앱 드래그 중 경계 억제와 버튼 해제 후 복귀
- 빠르게 반복 진입·복귀했을 때 bounce, stuck button, 중복 HUD 없음

자동 실행 환경에 외부 모니터 또는 TCC 권한이 없으면 컴파일·단위·통합·시각 검증과 실제 하드웨어 검증의 경계를 최종 보고서에 분리한다.

## 11. 완료 조건

1. Viewer 영상 바깥에서 안으로 커서를 이동하면 클릭 없이 대응 외부 좌표로 이동한다.
2. 레터박스와 Viewer UI에서는 자동 진입하지 않는다.
3. 외부 화면의 네 경계를 벗어나려 하면 Viewer의 같은 경계·같은 위치 비율로 복귀한다.
4. 정상 경계 복귀 커서는 영상 바깥의 레터박스, 컨트롤 UI 또는 가장 가까운 안전 영역에 놓인다. geometry 실패 fallback이 영상 안이면 자동 포털은 영상 밖 실제 이동 전까지 재무장되지 않는다.
5. 드래그 중에는 자동 복귀하지 않고 버튼 해제 후 다음 바깥 이동에서 복귀한다.
6. 한 번의 교차가 한 번의 warp만 만들며 즉시 재진입하거나 튕기지 않는다.
7. ESC 0.8초 길게 누르기, 디스플레이 분리와 실패 복귀가 기존대로 동작한다.
8. 권한, 이벤트 탭 또는 geometry 실패가 커서를 외부에 고립시키지 않는다.
9. 기존 전체 테스트와 새 포털 테스트가 통과하고 DEBUG·Release 빌드가 성공한다.
10. 갱신된 HUD와 Viewer의 기존 시각 상태가 시각 QA를 통과한다.

## 12. 참고 자료

- [NSTrackingArea](https://developer.apple.com/documentation/appkit/nstrackingarea)
- [NSTrackingArea.Options](https://developer.apple.com/documentation/appkit/nstrackingarea/options)
- [NSWindow.acceptsMouseMovedEvents](https://developer.apple.com/documentation/appkit/nswindow/acceptsmousemovedevents)
- [CGEvent.tapCreate](https://developer.apple.com/documentation/coregraphics/cgevent/tapcreate%28tap%3Aplace%3Aoptions%3Aeventsofinterest%3Acallback%3Auserinfo%3A%29)
- [CGEvent.location](https://developer.apple.com/documentation/coregraphics/cgevent/location)
- [CGWarpMouseCursorPosition](https://developer.apple.com/documentation/coregraphics/cgwarpmousecursorposition%28_%3A%29)
