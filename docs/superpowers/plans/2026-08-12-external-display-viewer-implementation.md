# External Display Viewer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

> **Supersession:** The hover-first entry, all-edge return, drag-clamp behavior, and current HUD copy are governed by `2026-08-13-pointer-portal-implementation.md`. The click-first steps below remain historical fallback implementation context only.

**Goal:** Build a directly runnable native macOS application that mirrors one extended external display, maps Viewer pointer gestures to the real external-display pointer, returns to the Viewer after a 0.8-second ESC hold, and briefly shows transition HUDs.

**Architecture:** A Swift Package produces a SwiftUI/AppKit executable and a packaging script wraps it in a stable `.app` bundle. Pure value/state components cover coordinate mapping, permission policy, session transitions, drag sequencing, and ESC decisions; thin ScreenCaptureKit, CoreGraphics, and AppKit adapters perform privileged side effects under one `@MainActor` coordinator.

**Tech Stack:** macOS 15+, Swift 6, SwiftUI, AppKit, ScreenCaptureKit, CoreGraphics, CoreAnimation, IOSurface, XCTest; no third-party packages.

## Global Constraints

- Deployment target is macOS 15.0 or newer.
- Build in Swift 6 language mode with strict concurrency enabled.
- Produce a non-sandboxed, directly runnable macOS app; do not target the Mac App Store.
- Do not add external packages.
- Capture exactly one selected external display with audio disabled and cursor included.
- Keep View Only as the default; enable Interactive only when Post Event and Listen Event access are both usable and no visible app window intersects the source display.
- Use CoreGraphics global point coordinates for pointer mapping; apply display scale only to capture pixel dimensions.
- Treat the Viewer-started pointer sequence as proxy-owned until the matching synthetic mouse-up is posted.
- Keep normal keyboard synthesis out of scope; only replay a captured short ESC to its unchanged live frontmost PID.
- Show the control HUD for 1.5 seconds and the return HUD for 1.2 seconds without consuming pointer events.
- A long ESC means 0.8 seconds or more.
- Do not create Git commits unless the user explicitly requests commits; each task ends with fresh verification instead.

---

## File Map

```text
Package.swift                                      SwiftPM products and targets
Support/Info.plist                                 Stable application bundle metadata
Scripts/build-app.sh                               Release build, bundle assembly, ad-hoc signing
Sources/ExternalDisplayViewerApp/App.swift         SwiftUI executable entry point
Sources/ExternalDisplayViewerCore/App/             Coordinator and session state
Sources/ExternalDisplayViewerCore/Capture/         ScreenCaptureKit configuration and stream adapter
Sources/ExternalDisplayViewerCore/Display/         Display discovery and reconfiguration
Sources/ExternalDisplayViewerCore/Input/           CoreGraphics pointer and ESC event adapters
Sources/ExternalDisplayViewerCore/Permissions/     TCC access checks and policy
Sources/ExternalDisplayViewerCore/Viewer/          Coordinate mapping, surface, window, HUD
Sources/ExternalDisplayViewerCore/UI/              Selection and Viewer SwiftUI views
Tests/ExternalDisplayViewerCoreTests/               Deterministic unit and policy tests
README.md                                           Build, launch, permissions, manual QA
```

### Task 1: Buildable App Skeleton and Session State

**Files:**
- Create: `Package.swift`
- Create: `Support/Info.plist`
- Create: `Scripts/build-app.sh`
- Create: `Sources/ExternalDisplayViewerApp/App.swift`
- Create: `Sources/ExternalDisplayViewerCore/App/InteractionContract.swift`
- Create: `Sources/ExternalDisplayViewerCore/App/MirrorSession.swift`
- Create: `Sources/ExternalDisplayViewerCore/UI/RootView.swift`
- Create: `Tests/ExternalDisplayViewerCoreTests/MirrorSessionTests.swift`

**Interfaces:**
- Produces: `MirrorSessionState`, `MirrorSessionEvent`, `MirrorSession.apply(_:) throws`, `RootView.init()`.
- Produces: `InteractionContract.escapeHoldDuration`, `controlHUDDuration`, and `returnHUDDuration`.
- Produces: executable product `ExternalDisplayViewer` and library product `ExternalDisplayViewerCore`.

- [ ] **Step 1: Write the session transition test before the implementation**

```swift
@testable import ExternalDisplayViewerCore
import XCTest

final class MirrorSessionTests: XCTestCase {
    func testHappyPathReturnsToViewOnly() throws {
        var session = MirrorSession()
        try session.apply(.prepare)
        try session.apply(.captureStarted)
        try session.apply(.interactiveEnabled)
        try session.apply(.pointerTransferred)
        try session.apply(.returnRequested)
        try session.apply(.returnCompleted)
        XCTAssertEqual(session.state, .viewOnly)
    }

    func testCannotControlBeforeInteractiveIsEnabled() {
        var session = MirrorSession()
        XCTAssertThrowsError(try session.apply(.pointerTransferred))
        XCTAssertEqual(session.state, .idle)
    }
}
```

- [ ] **Step 2: Run the targeted test and confirm the module/type failure**

Run: `swift test --filter MirrorSessionTests`

Expected: FAIL because the package and `MirrorSession` types do not exist.

- [ ] **Step 3: Create the package, state machine, minimal root view, and bundle metadata**

Use these exact public state names:

```swift
public enum MirrorSessionState: Equatable, Sendable {
    case idle, preparing, viewOnly, interactiveReady
    case controllingExternal, returning
    case failed(String)
}

public enum MirrorSessionEvent: Sendable {
    case prepare, captureStarted, interactiveEnabled, interactiveDisabled
    case pointerTransferred, returnRequested, returnCompleted
    case stop, fail(String)
}

public struct MirrorSession: Sendable {
    public private(set) var state: MirrorSessionState = .idle
    public init() {}
    public mutating func apply(_ event: MirrorSessionEvent) throws
}
```

Define the approved timings once and consume them from the ESC and HUD components:

```swift
public enum InteractionContract {
    public static let escapeHoldDuration: Duration = .milliseconds(800)
    public static let controlHUDDuration: Duration = .milliseconds(1500)
    public static let returnHUDDuration: Duration = .milliseconds(1200)
}
```

The package must declare `.macOS(.v15)`, Swift 6 language mode, one library target, one executable target, and one XCTest target. `Info.plist` must set `CFBundleIdentifier` to `local.codex.ExternalDisplayViewer`, `CFBundleExecutable` to `ExternalDisplayViewer`, `CFBundlePackageType` to `APPL`, `CFBundleVersion` and `CFBundleShortVersionString` to `1`, `LSMinimumSystemVersion` to `15.0`, `NSHighResolutionCapable` to true, and `NSPrincipalClass` to `NSApplication`.

- [ ] **Step 4: Implement the packaging script with explicit paths and ad-hoc signing**

```bash
#!/bin/zsh
set -euo pipefail
swift build -c release
APP_DIR="$PWD/build/ExternalDisplayViewer.app"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$PWD/.build/release/ExternalDisplayViewer" "$APP_DIR/Contents/MacOS/ExternalDisplayViewer"
cp "$PWD/Support/Info.plist" "$APP_DIR/Contents/Info.plist"
codesign --force --deep --sign - "$APP_DIR"
codesign --verify --deep --strict "$APP_DIR"
```

- [ ] **Step 5: Verify the first deliverable**

Run: `swift test --filter MirrorSessionTests && swift build`

Expected: both session tests pass and the debug executable builds.

### Task 2: Coordinate Mapping and Drag-Edge Clamping

**Files:**
- Create: `Sources/ExternalDisplayViewerCore/Viewer/CoordinateMapper.swift`
- Create: `Tests/ExternalDisplayViewerCoreTests/CoordinateMapperTests.swift`

**Interfaces:**
- Produces: `CoordinateMapper.renderRect(contentSize:sourceAspectRatio:) -> CGRect`.
- Produces: `CoordinateMapper.map(point:in:to:) -> CGPoint?` for down/click hit testing.
- Produces: `CoordinateMapper.mapClamped(point:in:to:) -> CGPoint` for an active drag.

- [ ] **Step 1: Add failing tests for exact mapping, letterboxing, negative coordinates, and maximum edges**

```swift
func testMapsCenterIntoDisplayWithNegativeOrigin() {
    let render = CGRect(x: 0, y: 100, width: 1000, height: 500)
    let display = CGRect(x: -1920, y: 0, width: 1920, height: 1080)
    XCTAssertEqual(
        CoordinateMapper.map(point: CGPoint(x: 500, y: 350), in: render, to: display),
        CGPoint(x: -960, y: 540)
    )
}

func testRejectsLetterboxAndClampsActiveDrag() {
    let render = CGRect(x: 0, y: 100, width: 1000, height: 500)
    let display = CGRect(x: 1728, y: -1080, width: 1920, height: 1080)
    XCTAssertNil(CoordinateMapper.map(point: CGPoint(x: 500, y: 50), in: render, to: display))
    let clamped = CoordinateMapper.mapClamped(point: CGPoint(x: 500, y: 50), in: render, to: display)
    XCTAssertEqual(clamped.y, display.minY)
    XCTAssertLessThan(clamped.x, display.maxX)
}
```

- [ ] **Step 2: Run the mapper tests and confirm the missing-symbol failure**

Run: `swift test --filter CoordinateMapperTests`

Expected: FAIL because `CoordinateMapper` does not exist.

- [ ] **Step 3: Implement pure aspect-fit and point-space mapping**

Clamp normalized values to `0...1`; for the right and bottom limits, clamp the global point to `display.maxX.nextDown` and `display.maxY.nextDown`. Do not multiply the pointer coordinates by Retina scale and do not invert Y because the input view is flipped.

- [ ] **Step 4: Add the full matrix and run it**

Cover same aspect, horizontal letterbox, vertical letterbox, source display on every side, negative origins, all four corners, and an outside drag point on every edge.

Run: `swift test --filter CoordinateMapperTests`

Expected: all mapper tests pass.

### Task 3: Permission Policy and Display Discovery

**Files:**
- Create: `Sources/ExternalDisplayViewerCore/Permissions/PermissionSnapshot.swift`
- Create: `Sources/ExternalDisplayViewerCore/Permissions/PermissionManager.swift`
- Create: `Sources/ExternalDisplayViewerCore/Display/DisplayInfo.swift`
- Create: `Sources/ExternalDisplayViewerCore/Display/DisplayManager.swift`
- Create: `Tests/ExternalDisplayViewerCoreTests/PermissionSnapshotTests.swift`
- Create: `Tests/ExternalDisplayViewerCoreTests/DisplayInfoTests.swift`

**Interfaces:**
- Produces: `PermissionSnapshot(screenRecording:postEvents:listenEvents:eventTapUsable:)`.
- Produces: `canMirror`, `canInteract`, and `interactionBlockReason`.
- Produces: `PermissionManaging.refresh()`, `requestScreenRecording()`, `requestPostEvents()`, `requestListenEvents()`.
- Produces: `DisplayInfo(id:name:coreGraphicsFrame:appKitFrame:pixelSize:scale:isBuiltIn:)`.
- Produces: `DisplayManager.refresh() async throws -> [DisplayInfo]` and `captureTarget(for:) -> SCDisplay?`.

- [ ] **Step 1: Write permission-policy failures first**

```swift
func testMirrorAndInteractionUseDifferentPermissionSets() {
    XCTAssertTrue(PermissionSnapshot(screenRecording: true, postEvents: false, listenEvents: false, eventTapUsable: false).canMirror)
    XCTAssertFalse(PermissionSnapshot(screenRecording: true, postEvents: true, listenEvents: true, eventTapUsable: false).canInteract)
    XCTAssertTrue(PermissionSnapshot(screenRecording: true, postEvents: true, listenEvents: true, eventTapUsable: true).canInteract)
}
```

Run: `swift test --filter PermissionSnapshotTests`

Expected: FAIL because the policy type is missing.

- [ ] **Step 2: Implement permission policy and real CoreGraphics checks**

Map Screen Recording to `CGPreflightScreenCaptureAccess`, Post Event to `CGPreflightPostEventAccess`, and Listen Event to `CGPreflightListenEventAccess`. Keep event-tap construction as a separate `eventTapUsable` fact; a positive preflight result alone must not enable Interactive.

- [ ] **Step 3: Test display identity independent of ScreenCaptureKit objects**

```swift
func testExternalDisplayLabelIncludesResolution() {
    let display = DisplayInfo(
        id: 42,
        name: "External Display",
        coreGraphicsFrame: CGRect(x: 1728, y: 0, width: 1920, height: 1080),
        appKitFrame: CGRect(x: 1728, y: 0, width: 1920, height: 1080),
        pixelSize: CGSize(width: 1920, height: 1080),
        scale: 1,
        isBuiltIn: false
    )
    XCTAssertEqual(display.menuLabel, "External Display · 1920×1080")
}
```

- [ ] **Step 4: Implement shareable-content discovery and display reconfiguration**

Use `SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)`, match `SCDisplay.displayID` to `NSScreenNumber`, derive built-in status with `CGDisplayIsBuiltin`, and retain the latest `[CGDirectDisplayID: SCDisplay]`. Register `CGDisplayRegisterReconfigurationCallback`; dispatch its notification to the main actor and refresh the list.

- [ ] **Step 5: Verify policies and package compilation**

Run: `swift test --filter PermissionSnapshotTests && swift test --filter DisplayInfoTests && swift build`

Expected: policy and display value tests pass; ScreenCaptureKit adapter compiles on macOS 15+.

### Task 4: Capture Configuration and Latest-Frame Stream

**Files:**
- Create: `Sources/ExternalDisplayViewerCore/Capture/CaptureSettings.swift`
- Create: `Sources/ExternalDisplayViewerCore/Capture/ScreenCaptureManager.swift`
- Create: `Sources/ExternalDisplayViewerCore/Capture/CaptureMetrics.swift`
- Create: `Tests/ExternalDisplayViewerCoreTests/CaptureSettingsTests.swift`
- Create: `Tests/ExternalDisplayViewerCoreTests/CaptureMetricsTests.swift`

**Interfaces:**
- Produces: `CaptureSettings.makeConfiguration(widthInPoints:heightInPoints:scale:) -> SCStreamConfiguration`.
- Produces: `ScreenCaptureManager.start(display:excluding:frameHandler:) async throws` and `stop() async`.
- Produces: `CaptureFrame(surface: IOSurface, size: CGSize, displayTime: UInt64)`.
- Produces: `CaptureMetricsSnapshot(displayedFPS:incompleteRatio:receivedFrames:displayedFrames:)`.
- Produces: a main-actor metrics callback whose cumulative snapshot is shown in the Viewer diagnostics footer and updated at most once per second.

- [ ] **Step 1: Write failing configuration and metrics tests**

```swift
func testLowLatencyCaptureConfiguration() {
    let configuration = CaptureSettings.makeConfiguration(widthInPoints: 1920, heightInPoints: 1080, scale: 2)
    XCTAssertEqual(configuration.width, 3840)
    XCTAssertEqual(configuration.height, 2160)
    XCTAssertEqual(configuration.queueDepth, 3)
    XCTAssertTrue(configuration.showsCursor)
    XCTAssertFalse(configuration.capturesAudio)
    XCTAssertEqual(configuration.pixelFormat, kCVPixelFormatType_32BGRA)
}

func testMetricsCountIncompleteFramesWithoutDisplayingThem() {
    var metrics = CaptureMetrics()
    metrics.recordReceived(isComplete: false, at: 0)
    metrics.recordReceived(isComplete: true, at: 1)
    metrics.recordDisplayed(at: 1)
    XCTAssertEqual(metrics.snapshot.incompleteRatio, 0.5, accuracy: 0.001)
    XCTAssertEqual(metrics.snapshot.displayedFrames, 1)
}
```

- [ ] **Step 2: Run and confirm failures**

Run: `swift test --filter 'Capture(Settings|Metrics)Tests'`

Expected: FAIL because capture settings and metrics do not exist.

- [ ] **Step 3: Implement the exact stream configuration**

Set `minimumFrameInterval = CMTime(value: 1, timescale: 60)`, `queueDepth = 3`, `pixelFormat = kCVPixelFormatType_32BGRA`, `showsCursor = true`, `capturesAudio = false`, and scaled pixel dimensions. Build an `SCContentFilter` that excludes this app's `SCRunningApplication` when it is present in the current shareable content.

- [ ] **Step 4: Implement serial frame delivery without CPU image conversion**

Accept only frame attachments whose `SCStreamFrameInfo.status` is `.complete`. Extract `CVPixelBuffer`, then `CVPixelBufferGetIOSurface`, and submit only the newest surface to the main-actor frame handler. Report `stream(_:didStopWithError:)` through an error handler and make stop idempotent.

- [ ] **Step 5: Run capture tests and compile**

Run: `swift test --filter 'Capture(Settings|Metrics)Tests' && swift build`

Expected: tests pass and all ScreenCaptureKit delegate signatures compile.

### Task 5: Proxy-Owned Pointer Input

**Files:**
- Create: `Sources/ExternalDisplayViewerCore/Input/PointerEvent.swift`
- Create: `Sources/ExternalDisplayViewerCore/Input/CGEventPoster.swift`
- Create: `Sources/ExternalDisplayViewerCore/Input/InputEventManager.swift`
- Create: `Tests/ExternalDisplayViewerCoreTests/InputEventManagerTests.swift`

**Interfaces:**
- Consumes: `CoordinateMapper.map` and `CoordinateMapper.mapClamped`.
- Produces: `PointerButton.left`, `.right`, `.middle`.
- Produces: `InputEventManager.begin(button:clickCount:viewerPoint:renderRect:displayFrame:) -> InputResult`.
- Produces: `drag(to:renderRect:displayFrame:)`, `end(at:renderRect:displayFrame:)`, `scroll(deltaX:deltaY:viewerPoint:renderRect:displayFrame:)`, and `cancelActiveSequence()`.
- Produces: `InputResult.ignoredLetterbox`, `.transferred(returnPoint:)`, `.continued`, `.ended`.

- [ ] **Step 1: Write a spy-poster test for ordering and drag clamping**

```swift
func testDragWarpsThenPostsDownDraggedAndUp() throws {
    let poster = PointerPosterSpy(currentLocation: CGPoint(x: 500, y: 500))
    let manager = InputEventManager(poster: poster)
    let render = CGRect(x: 0, y: 0, width: 100, height: 100)
    let display = CGRect(x: 1000, y: 0, width: 200, height: 200)

    _ = manager.begin(button: .left, clickCount: 1, viewerPoint: CGPoint(x: 25, y: 25), renderRect: render, displayFrame: display)
    _ = manager.drag(to: CGPoint(x: 120, y: 50), renderRect: render, displayFrame: display)
    _ = manager.end(at: CGPoint(x: 120, y: 50), renderRect: render, displayFrame: display)

    XCTAssertEqual(poster.actions.map(\.kind), [.warp, .mouseDown, .mouseDragged, .mouseUp])
    XCTAssertLessThan(poster.actions[2].location.x, display.maxX)
}
```

- [ ] **Step 2: Run and confirm the missing input types**

Run: `swift test --filter InputEventManagerTests`

Expected: FAIL because `InputEventManager` and its poster protocol do not exist.

- [ ] **Step 3: Implement the injectable poster and pointer state machine**

Use `CGWarpMouseCursorPosition` before synthetic down. Map left/right/middle to matching CoreGraphics down, dragged, and up types and button fields. Set `mouseEventClickState` for double clicks. Use pixel-unit scroll events with both vertical and horizontal deltas. Ignore a new down in letterbox, but clamp every drag/up after a valid down to the nearest render edge.

- [ ] **Step 4: Make every interruption release the exact active button**

`cancelActiveSequence()` must post a matching synthetic up at the last external point exactly once, clear the sequence, and be idempotent. Add tests for left/right/middle, double click state, two-axis scrolling, ignored letterbox, and repeated cancellation.

- [ ] **Step 5: Run the full input suite**

Run: `swift test --filter InputEventManagerTests`

Expected: all pointer sequencing tests pass.

### Task 6: ESC Hold Detection, Short Replay, and Safe Return Request

**Files:**
- Create: `Sources/ExternalDisplayViewerCore/Input/EscapeHoldStateMachine.swift`
- Create: `Sources/ExternalDisplayViewerCore/Input/EscapeReturnController.swift`
- Create: `Tests/ExternalDisplayViewerCoreTests/EscapeHoldStateMachineTests.swift`
- Create: `Tests/ExternalDisplayViewerCoreTests/EscapeReplayPolicyTests.swift`

**Interfaces:**
- Produces: `EscapeHoldStateMachine.keyDown(pid:)`, `thresholdReached()`, `keyUp(currentPID:isOriginalPIDRunning:)`.
- Produces: decisions `.startThresholdTimer`, `.suppress`, `.replayShortESC(pid:)`, `.requestReturn`, `.discard`.
- Produces: `EscapeReturnController.start() -> Bool`, `stop()`, `onReturnRequested`, and `onTapFailure`.

- [ ] **Step 1: Add deterministic boundary tests**

```swift
func testShortEscapeReplaysOnlyToUnchangedLivePID() {
    var machine = EscapeHoldStateMachine()
    XCTAssertEqual(machine.keyDown(pid: 100), .startThresholdTimer)
    XCTAssertEqual(machine.keyUp(currentPID: 100, isOriginalPIDRunning: true), .replayShortESC(pid: 100))

    XCTAssertEqual(machine.keyDown(pid: 100), .startThresholdTimer)
    XCTAssertEqual(machine.keyUp(currentPID: 200, isOriginalPIDRunning: true), .discard)
}

func testThresholdRequestsReturnAndSuppressesRelease() {
    var machine = EscapeHoldStateMachine()
    _ = machine.keyDown(pid: 100)
    XCTAssertEqual(machine.thresholdReached(), .requestReturn)
    XCTAssertEqual(machine.keyUp(currentPID: 100, isOriginalPIDRunning: true), .suppress)
}
```

- [ ] **Step 2: Run and confirm failures**

Run: `swift test --filter 'Escape(HoldStateMachine|ReplayPolicy)Tests'`

Expected: FAIL because ESC decision types are missing.

- [ ] **Step 3: Implement a single active session event tap**

Create an active `CGEventTap` at `.cgSessionEventTap` and `.headInsertEventTap` for keyDown/keyUp only. Intercept key code 53 only while control is active. Merge repeat keyDown events. Start a 0.8-second one-shot timer from the first down. Store copies of the first down and release events plus the original frontmost PID.

- [ ] **Step 4: Replay short ESC safely and tag synthetic copies**

On release before the threshold, check both `NSRunningApplication(processIdentifier:)` and `NSWorkspace.shared.frontmostApplication?.processIdentifier`. Replay down/up to the saved PID only when it is alive and unchanged. Set a fixed `eventSourceUserData` tag on both copies and let tagged events pass through the tap. If focus changed or the PID exited, discard both events.

- [ ] **Step 5: Handle event-tap disablement and test decisions**

Re-enable once on `.tapDisabledByTimeout` or `.tapDisabledByUserInput`; if the tap disables again, invoke `onTapFailure`, which the coordinator routes to immediate safe return. Stop must remove the run-loop source, cancel the timer, and clear saved event copies.

Run: `swift test --filter 'Escape(HoldStateMachine|ReplayPolicy)Tests' && swift build`

Expected: boundary and PID policy tests pass; event-tap code compiles.

### Task 7: IOSurface Viewer and Nonblocking Transition HUD

**Files:**
- Create: `Sources/ExternalDisplayViewerCore/Viewer/MirrorSurfaceView.swift`
- Create: `Sources/ExternalDisplayViewerCore/Viewer/MirrorSurfaceRepresentable.swift`
- Create: `Sources/ExternalDisplayViewerCore/Viewer/SurfacePresenter.swift`
- Create: `Sources/ExternalDisplayViewerCore/Viewer/TransitionHUDController.swift`
- Create: `Sources/ExternalDisplayViewerCore/UI/ViewerRootView.swift`
- Create: `Tests/ExternalDisplayViewerCoreTests/TransitionHUDControllerTests.swift`

**Interfaces:**
- Consumes: `CaptureFrame`, pointer callbacks, and `CoordinateMapper.renderRect`.
- Produces: flipped `MirrorSurfaceView`, `currentRenderRect`, and AppKit mouse/scroll callbacks.
- Produces: `TransitionHUDController.showControlTransfer()` and `showReturn()`.
- Produces: exact messages `외부 디스플레이 제어 중 · 화면 경계 또는 ESC를 길게 눌러 돌아오기` and `Viewer로 돌아왔습니다`.

- [ ] **Step 1: Write HUD replacement and expiry tests**

```swift
@MainActor
func testReturnHUDReplacesControlHUDAndExpires() async throws {
    let hud = TransitionHUDController()
    hud.showControlTransfer(duration: .milliseconds(50))
    XCTAssertEqual(hud.message, TransitionHUDController.controlMessage)
    hud.showReturn(duration: .milliseconds(10))
    XCTAssertEqual(hud.message, TransitionHUDController.returnMessage)
    try await Task.sleep(for: .milliseconds(30))
    XCTAssertNil(hud.message)
}
```

- [ ] **Step 2: Run and confirm the HUD type failure**

Run: `swift test --filter TransitionHUDControllerTests`

Expected: FAIL because the HUD controller does not exist.

- [ ] **Step 3: Implement direct IOSurface presentation**

Make the `NSView` layer-backed, black, flipped, and aspect-fit. Assign the received `IOSurface` directly to `layer.contents`; never create `CGImage`, `NSImage`, or CPU bitmap data. Update `currentRenderRect` on layout. Override left/right/other down, dragged, up, and `scrollWheel`, forwarding flipped local points and click count without consuming events in View Only.

- [ ] **Step 4: Implement the HUD overlay**

Use a SwiftUI overlay aligned top-center inside the capture area. Disable hit testing on the overlay, use a translucent rounded material, and fade only opacity. Default durations are exactly 1.5 and 1.2 seconds. Cancel the previous expiry task when replacing a message so an earlier timer cannot hide the newer HUD.

- [ ] **Step 5: Verify HUD behavior and UI compilation**

Run: `swift test --filter TransitionHUDControllerTests && swift build`

Expected: HUD tests pass and the Viewer surface compiles.

### Task 8: Viewer Window, Overlap Guard, and Controls

**Files:**
- Create: `Sources/ExternalDisplayViewerCore/Viewer/ViewerViewModel.swift`
- Create: `Sources/ExternalDisplayViewerCore/Viewer/MirrorWindowController.swift`
- Create: `Sources/ExternalDisplayViewerCore/Viewer/WindowOverlapPolicy.swift`
- Create: `Tests/ExternalDisplayViewerCoreTests/WindowOverlapPolicyTests.swift`
- Modify: `Sources/ExternalDisplayViewerCore/UI/ViewerRootView.swift`

**Interfaces:**
- Consumes: selected `DisplayInfo`, `SurfacePresenter`, HUD controller, and pointer callbacks.
- Produces: `WindowOverlapPolicy.canEnableInteractive(appWindowFrames:sourceAppKitFrame:)`.
- Produces: `MirrorWindowController.open(onPreferredScreen:)`, `bringForward()`, `setAlwaysOnTop(_:)`, and `close()`.
- Produces: move/resize/screen-change callbacks and full-screen rejection on the source display.

- [ ] **Step 1: Write overlap-policy tests**

```swift
func testAnyVisibleAppWindowIntersectionBlocksInteractive() {
    let source = CGRect(x: 1000, y: 0, width: 1000, height: 800)
    XCTAssertFalse(WindowOverlapPolicy.canEnableInteractive(
        appWindowFrames: [CGRect(x: 900, y: 100, width: 200, height: 200)],
        sourceAppKitFrame: source
    ))
    XCTAssertTrue(WindowOverlapPolicy.canEnableInteractive(
        appWindowFrames: [CGRect(x: 0, y: 0, width: 800, height: 800)],
        sourceAppKitFrame: source
    ))
}
```

- [ ] **Step 2: Run and confirm failure**

Run: `swift test --filter WindowOverlapPolicyTests`

Expected: FAIL because the overlap policy does not exist.

- [ ] **Step 3: Implement the AppKit window and safety callbacks**

Open on the built-in screen when available, preserve native move/resize/minimize behavior, expose Always on Top by switching between `.normal` and `.floating`, and host `ViewerRootView`. On every move, resize, visibility, and screen change, collect visible `NSApp.windows` frames and recompute overlap. If a full-screen transition lands on the source display, exit full screen immediately and publish the same overlap warning.

- [ ] **Step 4: Add Viewer controls and exact disabled reasons**

Provide View Only/Interactive, Always on Top, Stop, and status controls. Disable Interactive when permissions fail, event tap is unusable, or overlap exists. The overlap message must say the Viewer must be moved off the source external display. The surface must keep its aspect ratio during every resize.

- [ ] **Step 5: Run policy tests and build**

Run: `swift test --filter WindowOverlapPolicyTests && swift build`

Expected: policy tests pass and AppKit delegate methods compile.

### Task 9: Main-Actor Coordination and Safety Recovery

**Files:**
- Create: `Sources/ExternalDisplayViewerCore/App/AppCoordinator.swift`
- Create: `Sources/ExternalDisplayViewerCore/App/ReturnPointPolicy.swift`
- Create: `Sources/ExternalDisplayViewerCore/Viewer/ScreenCoordinateConverter.swift`
- Create: `Tests/ExternalDisplayViewerCoreTests/ReturnPointPolicyTests.swift`
- Create: `Tests/ExternalDisplayViewerCoreTests/ScreenCoordinateConverterTests.swift`
- Create: `Tests/ExternalDisplayViewerCoreTests/AppCoordinatorPolicyTests.swift`
- Modify: `Sources/ExternalDisplayViewerCore/UI/RootView.swift`
- Modify: `Sources/ExternalDisplayViewerCore/UI/ViewerRootView.swift`
- Modify: `Sources/ExternalDisplayViewerApp/App.swift`

**Interfaces:**
- Consumes: all managers and controllers from Tasks 2–8.
- Produces: `AppCoordinator.refresh()`, `startMirroring(displayID:)`, `setInteractive(_:)`, `handlePointer(_:)`, `returnToViewer(reason:)`, `stopMirroring()`, and `applicationWillTerminate()`.
- Produces: `ScreenCoordinateConverter.coreGraphicsGlobalRect(appKitGlobalRect:mainDisplayHeight:) -> CGRect`.
- Produces: `MirrorWindowController.captureGlobalFrame() -> CGRect?`, converting the flipped surface's local render rectangle through window/AppKit screen space into CoreGraphics global space.
- Produces: `ReturnPointPolicy.resolve(savedGlobalPoint:viewerCaptureGlobalFrame:) -> CGPoint`.

- [ ] **Step 1: Write return-point and interaction-gate tests**

```swift
func testInvalidSavedPointFallsBackToViewerCaptureCenter() {
    let captureFrame = CGRect(x: 100, y: 200, width: 600, height: 400)
    XCTAssertEqual(
        ReturnPointPolicy.resolve(savedGlobalPoint: CGPoint(x: 5000, y: 5000), viewerCaptureGlobalFrame: captureFrame),
        CGPoint(x: 400, y: 400)
    )
}
```

Test the coordinate-system boundary explicitly:

```swift
func testAppKitGlobalRectConvertsToCoreGraphicsGlobalRect() {
    let appKitRect = CGRect(x: 200, y: 600, width: 400, height: 300)
    XCTAssertEqual(
        ScreenCoordinateConverter.coreGraphicsGlobalRect(appKitGlobalRect: appKitRect, mainDisplayHeight: 1080),
        CGRect(x: 200, y: 180, width: 400, height: 300)
    )
}
```

Test a pure `InteractionGate` matrix covering missing Post Event, missing Listen Event, unusable event tap, overlap, and all-clear. `ReturnPointPolicy` must accept only CoreGraphics-global values; no method may pass `MirrorSurfaceView.currentRenderRect` directly to `CGWarpMouseCursorPosition`.

- [ ] **Step 2: Run and confirm failures**

Run: `swift test --filter 'ReturnPointPolicyTests|AppCoordinatorPolicyTests'`

Expected: FAIL because return policy and interaction gate do not exist.

- [ ] **Step 3: Wire the start and control-transfer flows**

The main-actor coordinator must: refresh permissions and displays; start capture only with Screen Recording; open Viewer in View Only; validate all interaction gates; start the ESC tap before setting Interactive; save `CGEvent(source: nil)?.location` immediately before a valid pointer transfer; invoke the input manager; move to `controllingExternal`; and show the 1.5-second HUD.

- [ ] **Step 4: Implement one idempotent safe-return path**

For ESC threshold, display removal, capture failure, event-tap failure, Stop, and normal termination: cancel the active pointer sequence, stop the ESC tap, obtain `captureGlobalFrame()` from the window controller, resolve the saved CoreGraphics-global return point or that global frame's center, warp the real cursor, activate the app, bring Viewer forward, set View Only, and show the 1.2-second HUD when the Viewer remains open. Multiple concurrent return requests must execute the sequence once.

- [ ] **Step 5: Build the selection and permission UI**

List discovered external displays with `menuLabel`, show each permission separately, expose request buttons, keep `Start Mirroring` disabled without Screen Recording or without an external display, and provide Retry after a capture error. Do not automatically request all privileges at launch.

- [ ] **Step 6: Verify policy and integration compilation**

Run: `swift test --filter 'ReturnPointPolicyTests|ScreenCoordinateConverterTests|AppCoordinatorPolicyTests' && swift test && swift build`

Expected: all unit tests pass and the integrated app compiles.

### Task 10: Packaging, Static Review, and Manual-QA Handoff

**Files:**
- Create: `README.md`
- Create: `Tests/ExternalDisplayViewerCoreTests/SmokeContractTests.swift`
- Modify: `Scripts/build-app.sh`
- Modify: any source file required by fresh compiler or test evidence.

**Interfaces:**
- Produces: `build/ExternalDisplayViewer.app` with a valid executable and `Info.plist`.
- Produces: user instructions for the three macOS privacy permissions and the ESC/HUD interaction.

- [ ] **Step 1: Add smoke contract tests for exact product copy and timing**

```swift
func testInteractionConstantsMatchApprovedContract() {
    XCTAssertEqual(InteractionContract.escapeHoldDuration, .milliseconds(800))
    XCTAssertEqual(InteractionContract.controlHUDDuration, .milliseconds(1500))
    XCTAssertEqual(InteractionContract.returnHUDDuration, .milliseconds(1200))
    XCTAssertEqual(TransitionHUDController.controlMessage, "외부 디스플레이 제어 중 · 화면 경계 또는 ESC를 길게 눌러 돌아오기")
    XCTAssertEqual(TransitionHUDController.returnMessage, "Viewer로 돌아왔습니다")
}
```

- [ ] **Step 2: Run all deterministic verification**

Run: `swift test`

Expected: zero failures.

Run: `swift build -c release`

Expected: release executable links successfully.

Run: `xcodebuild -scheme ExternalDisplayViewer -destination 'platform=macOS' build CODE_SIGNING_ALLOWED=NO`

Expected: Xcode's Swift Package scheme builds successfully.

- [ ] **Step 3: Build and validate the app bundle**

Run: `zsh Scripts/build-app.sh`

Expected: `build/ExternalDisplayViewer.app/Contents/MacOS/ExternalDisplayViewer` exists and `codesign --verify --deep --strict` exits 0.

Run: `plutil -lint Support/Info.plist && plutil -lint build/ExternalDisplayViewer.app/Contents/Info.plist`

Expected: both property lists report `OK`.

- [ ] **Step 4: Perform focused static scans**

Run: `zsh -c 'rg "CGAssociateMouseAndMouseCursorPosition|CGImage|NSImage|capturesAudio\\s*=\\s*true|TO.DO|FIX.ME" Sources Tests; code=$?; if (( code == 0 )); then print -u2 "forbidden source pattern found"; exit 1; elif (( code == 1 )); then exit 0; else exit $code; fi'`

Expected: no cursor decoupling, CPU image conversion, audio capture, or unfinished markers.

Run: `git diff --check`

Expected: no whitespace errors.

- [ ] **Step 5: Document and separate hardware-only evidence**

README must give exact launch steps, explain Screen Recording/Accessibility/Input Monitoring, state that changing TCC permissions may require relaunch, and include this executable manual-QA matrix:

| Scenario | Setup and action | Expected observable result |
| --- | --- | --- |
| Launch and discovery | In System Settings, place the built-in display left of one external display in Extended mode. Run `open build/ExternalDisplayViewer.app`, grant Screen Recording, relaunch, select the non-built-in display, and start. | The external display appears once by name/resolution; Viewer opens on the built-in display in View Only and shows the full source with black letterboxing where needed. |
| Permission denial | Revoke each of Screen Recording, Accessibility, and Input Monitoring one at a time, relaunch, and refresh. | Missing Screen Recording disables Start; missing Accessibility or Input Monitoring still permits View Only but disables Interactive with the matching settings guidance. |
| Click variants | In Interactive, target visible Chrome controls near center and all four capture corners; perform single left, right, middle, and double clicks. | The real cursor lands on the corresponding external point without crossing into an adjacent display; Chrome observes the matching click/button/click count. Letterbox clicks do nothing. |
| Scroll and drag | Over a horizontally and vertically scrollable Chrome page, scroll on both axes; drag a selectable item while moving beyond each Viewer edge before release. | Scroll direction and both axes match; the drag remains active, clamps to the closest source edge, and ends with exactly one matching mouse-up. |
| Source overlap guard | Move any visible window belonging to External Display Viewer so it intersects the selected external display, then try Interactive and full screen on that display. Keep the target app (for example Chrome) on the source display. | Interactive is disabled with the move-off-source warning; source-display full screen exits immediately. Moving this app's visible windows away restores eligibility while the target app remains on the source display. |
| Control HUD | Move the cursor from Viewer nonvideo UI into the actual mirrored video area. | The top-center nonblocking HUD reads `외부 디스플레이 제어 중 · 화면 경계 또는 ESC를 길게 눌러 돌아오기`, accepts no hit tests, fades, and disappears after about 1.5 seconds. |
| Short ESC | Open a Chrome context menu, press and release ESC before 0.8 seconds without changing frontmost app. Repeat while switching frontmost apps before release. | First attempt closes the context menu once and leaves control external; second attempt is discarded and does not send ESC to either app. |
| Long ESC return | Record the cursor position in Viewer, transfer control, hold ESC for at least 0.8 seconds, and release. | Any active drag receives mouse-up; cursor returns within 2 points of the saved global position or current Viewer capture center; Viewer becomes frontmost and View Only; return HUD reads `Viewer로 돌아왔습니다` for about 1.2 seconds. |
| Cable removal | Start a Viewer-owned drag, then disconnect the selected external display before mouse-up. | A safe synthetic mouse-up is attempted once, cursor returns to Viewer, capture closes or shows a recoverable error, and no stuck-button behavior remains. |
| 60-second capture metrics | Keep the native-resolution source changing for 60 seconds and record the Viewer diagnostics footer at regular intervals and at the end. | The average of sampled recent-one-second displayed FPS values is at least 30 and incomplete/dropped ratio is below 5%; record resolution, received/displayed counts, FPS samples, and ratio in the QA evidence. |
| 240-FPS latency | Film the input finger/trackpad and the Viewer feedback in one 240-FPS camera frame for 20 clicks. For each click count frames from physical contact to the first changed Viewer pixel and compute `frames / 240 × 1000 ms`. | Median of 20 measurements is at most 100 ms and the nearest-rank p95 is at most 180 ms; retain the frame counts and computed values. |

- [ ] **Step 6: Record the final evidence without overstating hardware verification**

Report compiler, unit-test, Xcode build, bundle-signature, and plist results as verified. Report physical external-display interaction and camera performance measurements as pending unless they were run in a GUI session with the target hardware.

---

## Final Acceptance Checklist

- [ ] The selection window discovers at least one non-built-in extended display when hardware is available.
- [ ] Viewer starts in View Only and renders the complete display with letterboxing.
- [ ] Letterbox down is ignored; a capture-area down warps the real cursor and posts the matching event.
- [ ] Click, right click, middle click, double click, drag, and two-axis scroll have deterministic proxy tests.
- [ ] Interactive cannot start when any app window intersects the source display.
- [ ] Short ESC replays only to its original unchanged live PID.
- [ ] Holding ESC for 0.8 seconds performs safe mouse-up, cursor return, Viewer activation, View Only, and return HUD.
- [ ] Control and return HUDs use approved Korean copy, durations, fades, and disabled hit testing.
- [ ] Display removal, stream failure, event-tap failure, Stop, and normal termination use one idempotent safe-return path.
- [ ] `swift test`, debug/release builds, Xcode package build, app packaging, signature verification, plist validation, and whitespace checks pass.
- [ ] Hardware-only QA is either evidenced or explicitly listed as pending.
