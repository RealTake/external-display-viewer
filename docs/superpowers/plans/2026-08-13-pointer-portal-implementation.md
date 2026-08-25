# Viewer Pointer Portal Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Viewer 영상 진입 위치와 외부 디스플레이 좌표를 연결하고, 외부 화면의 네 경계 이탈 시 같은 비율의 Viewer 비영상 영역으로 실제 커서를 자연스럽게 복귀시킨다.

**Architecture:** `MirrorSurfaceView`의 `NSTrackingArea`가 Viewer 진입·이탈 의도만 전달하고, 별도의 `PointerBoundaryController`가 외부 앱이 전면인 동안 mouse move/down/up/dragged를 감시한다. 순수 `PointerPortalMapper`와 `PointerBoundaryState`가 좌표·경계·버튼 상태를 계산하며, `AppCoordinator`가 권한, 두 이벤트 탭, warp, HUD와 기존 안전 복귀 경로를 단일 상태 전환으로 조정한다.

**Tech Stack:** Swift 6, SwiftUI, AppKit, CoreGraphics, XCTest, ScreenCaptureKit; 외부 패키지 없음.

## Global Constraints

- 대상은 macOS 15 이상이며 앱은 직접 실행하는 비샌드박스 macOS 앱이다.
- Viewer 영상 진입은 클릭이나 dwell 없이 즉시 동작하고, 레터박스·컨트롤·진단 UI에서는 동작하지 않는다.
- 외부 디스플레이의 상·하·좌·우 모든 경계를 감시하고 경계상의 0...1 위치 비율을 보존한다.
- 정상 경계 복귀점은 Viewer 영상 내부가 아니라 레터박스, 하단 컨트롤 또는 가장 가까운 비영상 영역이다.
- 실제 외부 드래그 중에는 자동 복귀하지 않으며 버튼 해제 후 다음 바깥 방향 move에서 복귀한다.
- ESC 0.8초 길게 누르기, 소스 화면 겹침 차단, 권한 게이트와 기존 클릭 전환은 안전 보조 경로로 유지한다.
- 제어 HUD 문구는 `외부 디스플레이 제어 중 · 화면 경계 또는 ESC를 길게 눌러 돌아오기`, 복귀 HUD는 `Viewer로 돌아왔습니다`다.
- 포털 hot path는 타이머 폴링과 SwiftUI 프레임 발행을 추가하지 않는다.
- 새 외부 의존성을 추가하지 않는다.
- 저장소는 최초 커밋이 없는 사용자 작업본이므로 이 계획에서는 git commit을 생성하지 않는다. 각 Task 보고서와 명령 출력으로 검증을 남긴다.
- 자동 환경의 외부 모니터·TCC·실제 포인터 검증 한계는 최종 보고서에 분리한다.

---

### Task 1: 순수 포털 좌표와 landing 영역

**Files:**
- Create: `Sources/ExternalDisplayViewerCore/Viewer/PointerPortalMapper.swift`
- Create: `Tests/ExternalDisplayViewerCoreTests/PointerPortalMapperTests.swift`

**Interfaces:**
- Produces: `PointerPortalEdge`, `PointerPortalExit`, `PointerPortalViewerGeometry`, `PointerPortalMapper.externalPoint(for:)`, `PointerPortalMapper.exit(at:delta:in:)`, `PointerPortalMapper.returnPoint(for:viewer:safetyInset:)`.
- Consumes: CoreGraphics `CGPoint`, `CGRect`; existing top-left CoreGraphics coordinate convention.

- [ ] **Step 1: Write failing mapper tests**

```swift
final class PointerPortalMapperTests: XCTestCase {
    func testEntryMapsViewerPointToMatchingExternalPoint() {
        let request = PointerPortalEntry(
            viewerPoint: CGPoint(x: 250, y: 125),
            renderRect: CGRect(x: 0, y: 0, width: 1000, height: 500),
            displayFrame: CGRect(x: -1920, y: 0, width: 1920, height: 1080)
        )
        XCTAssertEqual(PointerPortalMapper.externalPoint(for: request), CGPoint(x: -1440, y: 270))
    }

    func testBottomExitReturnsToSameHorizontalRatioBelowCapture() {
        let viewer = PointerPortalViewerGeometry(
            captureFrame: CGRect(x: 100, y: 100, width: 800, height: 450),
            surfaceFrame: CGRect(x: 100, y: 100, width: 800, height: 500),
            contentFrame: CGRect(x: 100, y: 100, width: 800, height: 620)
        )
        let point = PointerPortalMapper.returnPoint(
            for: PointerPortalExit(edge: .bottom, position: 0.25),
            viewer: viewer,
            safetyInset: 2
        )
        XCTAssertEqual(point, CGPoint(x: 300, y: 552))
    }
}
```

Add separate Given/When/Then tests for all four edges, 0/0.5/1 ratios, negative origins, letterbox rejection, corner dominant-axis selection, and no landing-region result.

- [ ] **Step 2: Run the focused tests and record RED**

Run:

```zsh
swift test --disable-sandbox --filter PointerPortalMapperTests
```

Expected: compile failure because the portal types do not exist.

- [ ] **Step 3: Implement the value types and pure mapping**

```swift
public enum PointerPortalEdge: Equatable, Sendable { case left, right, top, bottom }

public struct PointerPortalExit: Equatable, Sendable {
    public let edge: PointerPortalEdge
    public let position: CGFloat
}

public struct PointerPortalEntry: Equatable, Sendable {
    public let viewerPoint: CGPoint
    public let renderRect: CGRect
    public let displayFrame: CGRect
}

public struct PointerPortalViewerGeometry: Equatable, Sendable {
    public let captureFrame: CGRect
    public let surfaceFrame: CGRect
    public let contentFrame: CGRect
}

public enum PointerPortalMapper {
    public static func externalPoint(for entry: PointerPortalEntry) -> CGPoint?
    public static func exit(at point: CGPoint, delta: CGVector, in displayFrame: CGRect) -> PointerPortalExit?
    public static func returnPoint(
        for exit: PointerPortalExit,
        viewer: PointerPortalViewerGeometry,
        safetyInset: CGFloat = 2
    ) -> CGPoint?
}
```

Reuse `CoordinateMapper.map` for entry. For return, derive top/left/right/bottom non-capture rectangles from `surfaceFrame` and use the content area below `surfaceFrame` as the footer. Preserve the parallel-axis ratio and choose the matching nonvideo strip; if absent, choose the footer. Return `nil` when no finite nonvideo point exists.

- [ ] **Step 4: Run mapper tests and record GREEN**

Run the focused test command. Expected: all `PointerPortalMapperTests` pass.

- [ ] **Step 5: Write Task 1 report**

Record changed files, RED error, GREEN counts, public signatures and known limits in the plan workspace report.

---

### Task 2: 포인터 경계와 직접 버튼 상태 머신

**Files:**
- Create: `Sources/ExternalDisplayViewerCore/Input/PointerBoundaryState.swift`
- Create: `Tests/ExternalDisplayViewerCoreTests/PointerBoundaryStateTests.swift`

**Interfaces:**
- Consumes: `PointerPortalExit`, `PointerPortalMapper.exit` from Task 1.
- Produces: `PointerBoundaryEvent`, `PointerBoundaryAction`, `PointerBoundaryState.consume(_:)`, `PointerBoundaryState.beginForcedReturn()` and `PointerBoundaryState.consumeRelease(_:)`.

- [ ] **Step 1: Write failing state tests**

Define independent Given/When/Then tests proving:

```swift
var state = PointerBoundaryState(displayFrame: CGRect(x: 0, y: 0, width: 1920, height: 1080))
XCTAssertEqual(
    state.consume(.move(location: CGPoint(x: 1919, y: 270), delta: CGVector(dx: 4, dy: 0))),
    .requestReturn(PointerPortalExit(edge: .right, position: 0.25))
)
```

Cover all four edge deltas, inward/parallel move ignore, one exit per session, direct down/up tracking, dragged event clamping without return, release then next move return, forced-up buttons exactly once and physical-up suppression.

- [ ] **Step 2: Run focused tests and record RED**

Run `swift test --disable-sandbox --filter PointerBoundaryStateTests`. Expected: missing-type compile failure.

- [ ] **Step 3: Implement the deterministic state machine**

```swift
public enum PointerBoundaryEvent: Equatable, Sendable {
    case move(location: CGPoint, delta: CGVector)
    case down(button: PointerButton, location: CGPoint)
    case dragged(button: PointerButton, location: CGPoint, delta: CGVector)
    case up(button: PointerButton, location: CGPoint)
}

public enum PointerBoundaryAction: Equatable, Sendable {
    case forward
    case forwardAt(CGPoint)
    case suppress
    case requestReturn(PointerPortalExit)
}

public struct PointerBoundaryForcedRelease: Equatable, Sendable {
    public let button: PointerButton
    public let location: CGPoint
}
```

`PointerBoundaryState` owns display frame, pressed-button set, last valid point, emitted-exit latch and pending physical releases. It must not call AppKit/CoreGraphics APIs.

- [ ] **Step 4: Run focused tests and record GREEN**

Expected: all boundary-state tests pass without timing or event-tap dependencies.

- [ ] **Step 5: Write Task 2 report**

Record RED/GREEN evidence and exact action semantics.

---

### Task 3: CoreGraphics 포인터 경계 감시기

**Files:**
- Create: `Sources/ExternalDisplayViewerCore/Input/PointerBoundaryController.swift`
- Modify: `Sources/ExternalDisplayViewerCore/Input/CGEventPoster.swift`
- Create: `Tests/ExternalDisplayViewerCoreTests/PointerBoundaryControllerTests.swift`

**Interfaces:**
- Consumes: `PointerBoundaryState`, `PointerEventPosting`, `PointerEvent.Kind`.
- Produces: `PointerBoundaryControlling` protocol and `PointerBoundaryController` implementation.

- [ ] **Step 1: Write failing controller lifecycle tests**

Use injected tap creation/enable/invalidate and a fake `PointerEventPosting` to prove:

```swift
@MainActor
func testForcedReturnPostsOneUpPerPressedButtonAndDrainsPhysicalUps() {
    // Given controller consumed left/right down
    // When prepareForReturn() is called
    // Then one synthetic up per button is posted at lastExternalPoint,
    // and later physical ups are suppressed before teardown.
}
```

Add tests for start idempotence, mask coverage, move exit callback once, dragged location mutation, one tap re-enable, failure callback and stop without pending releases.

- [ ] **Step 2: Run focused tests and record RED**

Run `swift test --disable-sandbox --filter PointerBoundaryControllerTests`. Expected: missing protocol/controller compile failure.

- [ ] **Step 3: Implement the controller and synthetic-event tag**

```swift
@MainActor
public protocol PointerBoundaryControlling: AnyObject {
    var onExit: @MainActor (PointerPortalExit) -> Void { get set }
    var onTapFailure: @MainActor () -> Void { get set }
    func start(displayFrame: CGRect) -> Bool
    func prepareForReturn() -> Bool
    func stop()
}
```

Use a `.cgSessionEventTap`, `.headInsertEventTap`, `.defaultTap` callback covering mouseMoved, left/right/other down/up and dragged. Mutate only an out-of-bounds dragged event location. Tag controller-posted forced ups and ignore those tags in the tap. `prepareForReturn()` posts forced ups, enters release-drain when physical buttons remain, or tears down immediately when none remain.

- [ ] **Step 4: Run controller and state tests and record GREEN**

Expected: both focused suites pass.

- [ ] **Step 5: Write Task 3 report**

Record mask, tap mode, forced-release and teardown evidence.

---

### Task 4: Viewer 영상 tracking area와 geometry bridge

**Files:**
- Modify: `Sources/ExternalDisplayViewerCore/Viewer/MirrorSurfaceView.swift`
- Modify: `Sources/ExternalDisplayViewerCore/Viewer/MirrorSurfaceRepresentable.swift`
- Modify: `Sources/ExternalDisplayViewerCore/Viewer/ViewerViewModel.swift`
- Modify: `Sources/ExternalDisplayViewerCore/UI/ViewerRootView.swift`
- Modify: `Sources/ExternalDisplayViewerCore/Viewer/MirrorWindowController.swift`
- Create: `Tests/ExternalDisplayViewerCoreTests/MirrorSurfacePortalTests.swift`
- Modify: `Tests/ExternalDisplayViewerCoreTests/ScreenCoordinateConverterTests.swift`

**Interfaces:**
- Produces: `MirrorSurfacePortalEvent`, enter/exit callbacks, `MirrorWindowController.pointerPortalGeometry()`.
- Consumes: `PointerPortalViewerGeometry` from Task 1.

- [ ] **Step 1: Write failing surface and geometry tests**

Tests must prove the tracking rectangle equals `currentRenderRect`, relayout replaces rather than accumulates tracking areas, entry is ignored with a pressed button, letterbox is excluded, and global capture/surface/content frames share the CoreGraphics coordinate system.

- [ ] **Step 2: Run focused tests and record RED**

Run `swift test --disable-sandbox --filter MirrorSurfacePortalTests`. Expected: missing callback/types.

- [ ] **Step 3: Implement tracking and bridge callbacks**

```swift
public struct MirrorSurfacePortalEvent: Equatable, Sendable {
    public let location: CGPoint
    public let renderRect: CGRect
}
```

`MirrorSurfaceView` owns exactly one `.mouseEnteredAndExited + .activeAlways` tracking area over `currentRenderRect`. Wire `onPortalEntered` and `onPortalExited` through representable, view model and root view. `pointerPortalGeometry()` returns capture, whole surface and content frames converted to CoreGraphics global coordinates.

- [ ] **Step 4: Replace the mode picker with a disabled state indicator**

Keep the existing segmented visual language but remove user mutation. Render `View Only` or `Interactive` from coordinator-owned `model.mode`, and retain the overlap/permission guidance.

- [ ] **Step 5: Run focused tests and Viewer model tests**

Run:

```zsh
swift test --disable-sandbox --filter MirrorSurfacePortalTests
swift test --disable-sandbox --filter ViewerViewModelInteractionGateTests
swift test --disable-sandbox --filter ScreenCoordinateConverterTests
```

Expected: all pass.

- [ ] **Step 6: Write Task 4 report**

Record tracking-area count/rect, callback chain and geometry evidence.

---

### Task 5: Coordinator 포털 진입과 경계 복귀 통합

**Files:**
- Modify: `Sources/ExternalDisplayViewerCore/App/AppCoordinator.swift`
- Modify: `Sources/ExternalDisplayViewerCore/App/MirrorSession.swift`
- Modify: `Tests/ExternalDisplayViewerCoreTests/AppCoordinatorPolicyTests.swift`
- Modify: `Tests/ExternalDisplayViewerCoreTests/MirrorSessionTests.swift`

**Interfaces:**
- Consumes: surface callbacks, `PointerBoundaryControlling`, portal mapping and geometry.
- Produces: `AppCoordinator.handlePortalEntered(_:)`, `handlePortalExited()`, and boundary-return routing through the existing safe-return funnel.

- [ ] **Step 1: Write failing coordinator tests**

Add independent tests for:

- hover enter order: permission refresh → geometry → escape tap → pointer tap → warp → Interactive → control HUD;
- no synthetic mouse-down on hover;
- permission/overlap/invalid geometry rejection without warp;
- pointer-tap or escape-tap failure rollback;
- warp failure stops both taps and stays View Only;
- boundary return target uses current geometry and preserves exit ratio;
- boundary return ordering: input cancel → direct-input prepare → taps stop/drain → geometry → warp → activate → bring forward → View Only → HUD;
- ESC after hover uses the saved Viewer entry point;
- duplicate enter/exit and simultaneous ESC are idempotent;
- `disarmedUntilExit` ignores entry until `handlePortalExited()`;
- existing click-transfer tests still pass.

- [ ] **Step 2: Run coordinator tests and record RED**

Run `swift test --disable-sandbox --filter AppCoordinatorPolicyTests`. Expected: new tests fail for missing dependencies/callbacks.

- [ ] **Step 3: Extend session and dependency seams minimally**

Add portal entry/exit events only where needed; reuse `interactiveEnabled`, `pointerTransferred`, `returnRequested` and `returnCompleted` when their current transitions remain valid. Add dependency closures for starting/preparing/stopping the pointer boundary controller and retrieving portal geometry.

- [ ] **Step 4: Implement atomic hover entry and target-aware safe return**

`handlePortalEntered` performs all gates before state publication, starts both taps before warp, rolls both back on failure, saves Viewer entry point and geometry, then publishes controlling/Interactive/HUD. Boundary callbacks call the existing safe return with an explicit mapped target; ESC continues to use the saved entry point.

- [ ] **Step 5: Run coordinator, session and legacy input tests**

Run:

```zsh
swift test --disable-sandbox --filter AppCoordinatorPolicyTests
swift test --disable-sandbox --filter MirrorSessionTests
swift test --disable-sandbox --filter InputEventManagerTests
swift test --disable-sandbox --filter EscapeReplayPolicyTests
```

Expected: all pass.

- [ ] **Step 6: Write Task 5 report**

Record RED/GREEN results, action ordering and preserved fallback behavior.

---

### Task 6: HUD, preview states and documentation

**Files:**
- Modify: `Sources/ExternalDisplayViewerCore/Viewer/TransitionHUDController.swift`
- Modify: `Sources/ExternalDisplayViewerCore/UI/VisualQAPreviewState.swift`
- Modify: `Sources/ExternalDisplayViewerCore/UI/VisualQAPreviewRoot.swift` only if preview state plumbing requires it
- Modify: `Tests/ExternalDisplayViewerCoreTests/SmokeContractTests.swift`
- Modify: `Tests/ExternalDisplayViewerCoreTests/VisualQAPreviewStateTests.swift`
- Modify: `README.md`
- Modify: `DESIGN.md`
- Modify: `docs/superpowers/specs/2026-08-12-external-display-viewer-design.md`
- Modify: `docs/superpowers/specs/2026-08-13-pointer-portal-design.md`

**Interfaces:**
- Consumes: final mode/HUD behavior from Task 5.
- Produces: exact user-facing HUD and current docs/preview contract.

- [ ] **Step 1: Write failing exact-contract and preview tests**

Assert the machine-consumed HUD constant and preview state expose the new control message, while return text and durations remain unchanged.

- [ ] **Step 2: Run focused tests and record RED**

Run `swift test --disable-sandbox --filter 'SmokeContractTests|VisualQAPreviewStateTests'`. Expected: old HUD expectation fails.

- [ ] **Step 3: Update HUD, preview and user documentation**

Replace click-first instructions with automatic hover portal behavior, all-edge return, nonvideo landing and drag suppression. Preserve the existing hardware/TCC validation caveats.

- [ ] **Step 4: Run focused tests and static string scan**

Expected: focused tests pass; old control HUD text appears only in explicitly historical evidence, not current source/README/design.

- [ ] **Step 5: Write Task 6 report**

Record updated copy, tests and static-scan results.

---

### Task 7: 전체 검증, 시각 QA와 배포 번들

**Files:**
- Modify: `Scripts/capture-visual-qa.sh` only if the state set needs a new pointer-portal capture
- Modify: `.omo/evidence/` reports for this feature
- Generated: `build/visual-qa/*.png`
- Generated: `build/ExternalDisplayViewer.app`
- Generated: `build/ExternalDisplayViewer-macOS-arm64.zip`

**Interfaces:**
- Consumes: complete implementation from Tasks 1–6.
- Produces: fresh test/build/visual/package evidence.

- [x] **Step 1: Fix or isolate the pre-existing IOSurface test crash by TDD if it still reproduces**

Run `swift test --disable-sandbox --filter ViewerFrameHotPathTests`. If `IOSurfaceCreate` still returns nil, replace the force unwrap with a throwing XCTest helper that uses a complete IOSurface property dictionary and fails the test with a diagnostic rather than crashing the runner. Re-run until the focused suite passes or record an environment blocker without weakening production tests.

- [x] **Step 2: Run the complete automated suite and builds**

```zsh
swift test --disable-sandbox
swift build -c debug
swift build -c release
zsh -n Scripts/build-app.sh Scripts/capture-visual-qa.sh
```

Expected: zero test failures and both builds succeed.

- [x] **Step 3: Generate and inspect all native visual-QA captures**

Run `Scripts/capture-visual-qa.sh`, verify every required PNG is fresh/nonempty, and inspect the full state set at original detail. Confirm the disabled mode indicator, updated Korean HUD, return HUD, overlap warning, permission states and metrics have no clipping or CJK defects.

- [x] **Step 4: Run the required two fresh visual gate reviews**

Dispatch two fresh read-only `lazycodex-gate-reviewer` agents: one for functional/state correctness and one for visual/CJK integrity. Resolve any product or evidence blocker and regenerate the complete capture set after the last UI change.

- [x] **Step 5: Build and verify the portable app package**

Run `Scripts/build-app.sh`, lint plists, check Mach-O architecture/minimum OS, extract the ZIP to a fresh temporary directory and run `codesign --verify --deep --strict` on the extracted app. Record SHA-256.

- [x] **Step 6: Perform code-quality and context consistency reviews**

Review changed code against the 2026-08-13 portal spec, measure pure LOC for every changed Swift file, verify no new dependency/logging/polling/hot-path regressions, and confirm README/design/reports distinguish automated proof from pending physical external-display/TCC QA.

- [x] **Step 7: Write final implementation and QA reports**

Record changed files, test count, build/package/hash/signature evidence, visual verdicts, pre-existing test disposition and explicit physical-hardware gaps.
