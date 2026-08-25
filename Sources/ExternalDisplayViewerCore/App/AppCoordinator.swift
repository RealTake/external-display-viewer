import AppKit
import Combine
import CoreGraphics
import Foundation
import ScreenCaptureKit

@MainActor
public final class AppCoordinator: ObservableObject {
    public enum ReturnReason: Equatable, Sendable {
        case escapeHold
        case captureError
        case displayRemoved
        case eventTapFailure
        case sourceOverlap
        case stop
        case termination
    }

    public struct ViewerCallbacks {
        public let onPointerDown: MirrorSurfaceView.MouseCallback
        public let onPointerDragged: MirrorSurfaceView.MouseCallback
        public let onPointerUp: MirrorSurfaceView.MouseCallback
        public let onScroll: MirrorSurfaceView.ScrollCallback
        public let onPortalEntered: MirrorSurfaceView.PortalCallback
        public let onPortalExited: MirrorSurfaceView.PortalCallback
        public let onModeIntent: ViewerViewModel.ModeIntentCallback
        public let onAlwaysOnTopChange: ViewerViewModel.TopLevelCallback
        public let onOverlapChanged: @MainActor (Bool) -> Void
        public let onStop: ViewerViewModel.VoidCallback
    }

    public struct ViewerAdapter {
        public let model: ViewerViewModel
        public let open: @MainActor () -> Void
        public let close: @MainActor () -> Void
        public let bringForward: @MainActor () -> Void
        public let setAlwaysOnTop: @MainActor (Bool) -> Void
        public let captureGlobalFrame: @MainActor () -> CGRect?
        public let pointerPortalGeometry: @MainActor () -> PointerPortalViewerGeometry?

        public init(
            model: ViewerViewModel,
            open: @escaping @MainActor () -> Void,
            close: @escaping @MainActor () -> Void,
            bringForward: @escaping @MainActor () -> Void,
            setAlwaysOnTop: @escaping @MainActor (Bool) -> Void,
            captureGlobalFrame: @escaping @MainActor () -> CGRect?,
            pointerPortalGeometry: @escaping @MainActor () -> PointerPortalViewerGeometry? = { nil }
        ) {
            self.model = model
            self.open = open
            self.close = close
            self.bringForward = bringForward
            self.setAlwaysOnTop = setAlwaysOnTop
            self.captureGlobalFrame = captureGlobalFrame
            self.pointerPortalGeometry = pointerPortalGeometry
        }
    }

    public struct Dependencies {
        public typealias FrameHandler = @MainActor @Sendable (CaptureFrame) -> Void

        let refreshPermissions: @MainActor () -> PermissionSnapshot
        let requestScreenRecording: @MainActor () -> Bool
        let requestPostEvents: @MainActor () -> Bool
        let requestListenEvents: @MainActor () -> Bool
        let openPermissionSettings: @MainActor (PermissionSettingsPane) -> Void
        let refreshDisplays: @MainActor () async throws -> [DisplayInfo]
        let startCapture: @MainActor (DisplayInfo, @escaping FrameHandler) async throws -> Void
        let stopCapture: @MainActor () async -> Void
        let makeViewer: @MainActor (DisplayInfo, ViewerCallbacks) -> ViewerAdapter
        let beginInput: @MainActor (PointerButton, Int, CGPoint, CGRect, CGRect) -> InputResult
        let dragInput: @MainActor (CGPoint, CGRect, CGRect) -> InputResult
        let endInput: @MainActor (CGPoint, CGRect, CGRect) -> InputResult
        let scrollInput: @MainActor (Int32, Int32, CGPoint, CGRect, CGRect) -> InputResult
        let cancelInput: @MainActor () -> InputResult
        let startEscapeTap: @MainActor () -> Bool
        let stopEscapeTap: @MainActor () -> Void
        let startPointerBoundary: @MainActor (CGRect, @escaping @MainActor (PointerPortalExit) -> Void, @escaping @MainActor () -> Void) -> Bool
        let preparePointerBoundaryReturn: @MainActor () -> PointerBoundaryReturnPreparationResult
        let stopPointerBoundary: @MainActor () -> Void
        let warpCursor: @MainActor (CGPoint) -> Bool
        let activateApp: @MainActor () -> Void
        let showControlHUD: @MainActor () -> Void
        let showReturnHUD: @MainActor () -> Void
        let publishViewerMode: @MainActor (ViewerMode) -> Void

        public init(
            refreshPermissions: @escaping @MainActor () -> PermissionSnapshot,
            requestScreenRecording: @escaping @MainActor () -> Bool,
            requestPostEvents: @escaping @MainActor () -> Bool,
            requestListenEvents: @escaping @MainActor () -> Bool,
            openPermissionSettings: @escaping @MainActor (PermissionSettingsPane) -> Void,
            refreshDisplays: @escaping @MainActor () async throws -> [DisplayInfo],
            startCapture: @escaping @MainActor (DisplayInfo, @escaping FrameHandler) async throws -> Void,
            stopCapture: @escaping @MainActor () async -> Void,
            makeViewer: @escaping @MainActor (DisplayInfo, ViewerCallbacks) -> ViewerAdapter,
            beginInput: @escaping @MainActor (PointerButton, Int, CGPoint, CGRect, CGRect) -> InputResult,
            dragInput: @escaping @MainActor (CGPoint, CGRect, CGRect) -> InputResult,
            endInput: @escaping @MainActor (CGPoint, CGRect, CGRect) -> InputResult,
            scrollInput: @escaping @MainActor (Int32, Int32, CGPoint, CGRect, CGRect) -> InputResult,
            cancelInput: @escaping @MainActor () -> InputResult,
            startEscapeTap: @escaping @MainActor () -> Bool,
            stopEscapeTap: @escaping @MainActor () -> Void,
            startPointerBoundary: @escaping @MainActor (CGRect, @escaping @MainActor (PointerPortalExit) -> Void, @escaping @MainActor () -> Void) -> Bool = { _, _, _ in true },
            preparePointerBoundaryReturn: @escaping @MainActor () -> PointerBoundaryReturnPreparationResult = { .tornDown },
            stopPointerBoundary: @escaping @MainActor () -> Void = {},
            warpCursor: @escaping @MainActor (CGPoint) -> Bool,
            activateApp: @escaping @MainActor () -> Void,
            showControlHUD: @escaping @MainActor () -> Void,
            showReturnHUD: @escaping @MainActor () -> Void,
            publishViewerMode: @escaping @MainActor (ViewerMode) -> Void = { _ in }
        ) {
            self.refreshPermissions = refreshPermissions
            self.requestScreenRecording = requestScreenRecording
            self.requestPostEvents = requestPostEvents
            self.requestListenEvents = requestListenEvents
            self.openPermissionSettings = openPermissionSettings
            self.refreshDisplays = refreshDisplays
            self.startCapture = startCapture
            self.stopCapture = stopCapture
            self.makeViewer = makeViewer
            self.beginInput = beginInput
            self.dragInput = dragInput
            self.endInput = endInput
            self.scrollInput = scrollInput
            self.cancelInput = cancelInput
            self.startEscapeTap = startEscapeTap
            self.stopEscapeTap = stopEscapeTap
            self.startPointerBoundary = startPointerBoundary
            self.preparePointerBoundaryReturn = preparePointerBoundaryReturn
            self.stopPointerBoundary = stopPointerBoundary
            self.warpCursor = warpCursor
            self.activateApp = activateApp
            self.showControlHUD = showControlHUD
            self.showReturnHUD = showReturnHUD
            self.publishViewerMode = publishViewerMode
        }
    }

    @Published public private(set) var session = MirrorSession()
    @Published public private(set) var displays: [DisplayInfo] = []
    @Published public private(set) var permissions: PermissionSnapshot
    @Published public var selectedDisplayID: CGDirectDisplayID?
    @Published public private(set) var recoverableError: String?
    @Published public private(set) var permissionRequestNotice: PermissionRequestNotice?
    @Published public private(set) var isPreparing = false

    private let dependencies: Dependencies
    private var viewer: ViewerAdapter?
    private var selectedDisplay: DisplayInfo?
    private var lastRequestedDisplayID: CGDirectDisplayID?
    private var savedReturnPoint: CGPoint?
    private var savedPortalGeometry: PointerPortalViewerGeometry?
    private var isPortalDisarmedUntilExit = false
    private var isPointerBoundaryActive = false
    private var pendingReturnTarget: ReturnTarget?
    private var didReturnForCurrentTransfer = false

    var savedReturnPointForTesting: CGPoint? {
        savedReturnPoint
    }

    public convenience init() {
        let permissionManager = PermissionManager()
        let displayManager = DisplayManager()
        let captureManager = ScreenCaptureManager()
        let inputManager = InputEventManager()
        let escapeController = EscapeReturnController()
        let poster = CGEventPoster()
        let pointerBoundaryController = PointerBoundaryController(poster: poster)
        let dependencies = Self.liveDependencies(
            permissionManager: permissionManager,
            displayManager: displayManager,
            captureManager: captureManager,
            inputManager: inputManager,
            escapeController: escapeController,
            pointerBoundaryController: pointerBoundaryController,
            poster: poster
        )
        self.init(dependencies: dependencies)

        displayManager.onReconfiguration = { [weak self] result in
            Task { @MainActor in
                await self?.handleDisplayRefresh(result)
            }
        }
        captureManager.setErrorHandler { [weak self] error in
            Task { @MainActor in
                await self?.handleCaptureError(error)
            }
        }
        captureManager.setMetricsHandler { [weak self] metrics in
            Task { @MainActor in
                self?.viewer?.model.updateMetrics(metrics)
            }
        }
        escapeController.onReturnRequested = { [weak self] in
            Task { @MainActor in
                await self?.returnToViewer(reason: .escapeHold)
            }
        }
        escapeController.onTapFailure = { [weak self] in
            Task { @MainActor in
                await self?.returnToViewer(reason: .eventTapFailure)
            }
        }
        pointerBoundaryController.onExit = { [weak self] exit in
            self?.returnFromBoundaryExit(exit)
        }
        pointerBoundaryController.onTapFailure = { [weak self] in
            Task { @MainActor in
                await self?.returnToViewer(reason: .eventTapFailure)
            }
        }
    }

    public init(dependencies: Dependencies) {
        self.dependencies = dependencies
        self.permissions = dependencies.refreshPermissions()
    }

    public var externalDisplays: [DisplayInfo] {
        displays.filter { !$0.isBuiltIn }
    }

    public var canStartMirroring: Bool {
        permissions.canMirror && selectedDisplayID != nil && !isPreparing
    }

    public func refresh() async {
        permissions = dependencies.refreshPermissions()
        clearResolvedPermissionRequestNotice()
        do {
            let refreshedDisplays = try await dependencies.refreshDisplays()
            applyDisplays(refreshedDisplays)
            recoverableError = nil
        } catch {
            recoverableError = error.localizedDescription
        }
        viewer?.model.updatePermissions(permissions)
    }

    @discardableResult
    public func requestScreenRecording() -> Bool {
        let result = dependencies.requestScreenRecording()
        permissions = dependencies.refreshPermissions()
        viewer?.model.updatePermissions(permissions)
        handlePermissionRequestResult(isGranted: permissions.screenRecording, pane: .screenRecording)
        return result
    }

    @discardableResult
    public func requestPostEvents() -> Bool {
        let result = dependencies.requestPostEvents()
        permissions = dependencies.refreshPermissions()
        viewer?.model.updatePermissions(permissions)
        handlePermissionRequestResult(isGranted: permissions.postEvents, pane: .accessibility)
        return result
    }

    @discardableResult
    public func requestListenEvents() -> Bool {
        let result = dependencies.requestListenEvents()
        permissions = dependencies.refreshPermissions()
        viewer?.model.updatePermissions(permissions)
        handlePermissionRequestResult(isGranted: permissions.listenEvents, pane: .inputMonitoring)
        return result
    }

    private func handlePermissionRequestResult(isGranted: Bool, pane: PermissionSettingsPane) {
        let pendingNotice = PermissionRequestNotice.manualSettingsRequired(pane)
        guard !isGranted else {
            if permissionRequestNotice == pendingNotice {
                permissionRequestNotice = nil
            }
            return
        }

        permissionRequestNotice = pendingNotice
        dependencies.openPermissionSettings(pane)
    }

    private func clearResolvedPermissionRequestNotice() {
        switch permissionRequestNotice {
        case .manualSettingsRequired(.screenRecording) where permissions.screenRecording:
            permissionRequestNotice = nil
        case .manualSettingsRequired(.accessibility) where permissions.postEvents:
            permissionRequestNotice = nil
        case .manualSettingsRequired(.inputMonitoring) where permissions.listenEvents:
            permissionRequestNotice = nil
        default:
            break
        }
    }

    public func startMirroring(displayID: CGDirectDisplayID) async {
        lastRequestedDisplayID = displayID
        if viewer != nil || session.state != .idle {
            guard await stopMirroring() else {
                return
            }
        }

        permissions = dependencies.refreshPermissions()
        guard permissions.canMirror else {
            recoverableError = "화면 기록 권한이 필요합니다."
            return
        }

        do {
            applyDisplays(try await dependencies.refreshDisplays())
        } catch {
            recoverableError = error.localizedDescription
            return
        }

        guard let display = displays.first(where: { $0.id == displayID && !$0.isBuiltIn }) else {
            recoverableError = "선택한 외부 디스플레이를 찾을 수 없습니다."
            return
        }

        isPreparing = true
        recoverableError = nil
        resetSession()
        apply(.prepare)

        do {
            try await dependencies.startCapture(display) { [weak self] frame in
                self?.handleFrame(frame)
            }
            selectedDisplay = display
            selectedDisplayID = display.id
            let viewer = makeViewer(display: display)
            self.viewer = viewer
            viewer.open()
            apply(.captureStarted)
            viewer.model.updateModeFromCoordinator(.viewOnly)
        } catch {
            recoverableError = error.localizedDescription
            apply(.fail(error.localizedDescription))
        }
        isPreparing = false
    }

    public func retryMirroring() async {
        guard let displayID = selectedDisplayID ?? lastRequestedDisplayID else {
            await refresh()
            return
        }

        await startMirroring(displayID: displayID)
    }

    public func setInteractive(_ enabled: Bool) async {
        guard enabled else {
            await disableInteractive()
            return
        }

        guard session.state == .viewOnly else {
            publishMode(.viewOnly)
            return
        }

        guard let viewer else {
            return
        }

        permissions = dependencies.refreshPermissions()
        viewer.model.updatePermissions(permissions)
        guard InteractionGate.evaluate(permissions: permissions, isSourceOverlapped: viewer.model.isOverlappingSource) == .allowed else {
            publishMode(.viewOnly)
            return
        }

        guard dependencies.startEscapeTap() else {
            dependencies.stopEscapeTap()
            publishMode(.viewOnly)
            return
        }

        didReturnForCurrentTransfer = false
        apply(.interactiveEnabled)
        publishMode(.interactive)
    }

    public func handlePointerDown(_ event: MirrorSurfaceMouseEvent) {
        guard let selectedDisplay, session.state == .interactiveReady else {
            return
        }

        let result = dependencies.beginInput(
            event.button,
            event.clickCount,
            event.location,
            event.renderRect,
            selectedDisplay.coreGraphicsFrame
        )
        switch result {
        case let .transferred(returnPoint):
            savedReturnPoint = returnPoint
            didReturnForCurrentTransfer = false
            apply(.pointerTransferred)
            viewer?.model.hud.showControlTransfer()
            dependencies.showControlHUD()
        case let .failed(failure):
            handleInputFailure(failure)
        case .ignoredLetterbox, .continued, .ended:
            return
        }
    }

    public func handlePointerDragged(_ event: MirrorSurfaceMouseEvent) {
        guard let selectedDisplay, session.state == .controllingExternal else {
            return
        }

        if case .failed = dependencies.dragInput(event.location, event.renderRect, selectedDisplay.coreGraphicsFrame) {
            handleInputFailure(.mouseDragged)
        }
    }

    public func handlePointerUp(_ event: MirrorSurfaceMouseEvent) {
        guard let selectedDisplay, session.state == .controllingExternal else {
            return
        }

        if case .failed = dependencies.endInput(event.location, event.renderRect, selectedDisplay.coreGraphicsFrame) {
            handleInputFailure(.mouseUp)
        }
    }

    public func handleScroll(_ event: MirrorSurfaceScrollEvent) {
        guard let selectedDisplay, session.state == .interactiveReady || session.state == .controllingExternal else {
            return
        }

        let result = dependencies.scrollInput(
            event.deltaX,
            event.deltaY,
            event.location,
            event.renderRect,
            selectedDisplay.coreGraphicsFrame
        )
        if case .failed = result {
            handleInputFailure(.scroll)
        }
    }

    public func handlePortalEntered(_ event: MirrorSurfacePortalEvent) {
        guard
            !isPortalDisarmedUntilExit,
            let selectedDisplay,
            let viewer,
            session.state == .viewOnly
        else {
            return
        }

        permissions = dependencies.refreshPermissions()
        viewer.model.updatePermissions(permissions)
        guard InteractionGate.evaluate(permissions: permissions, isSourceOverlapped: viewer.model.isOverlappingSource) == .allowed else {
            publishMode(.viewOnly)
            return
        }

        guard
            let geometry = viewer.pointerPortalGeometry(),
            let externalPoint = PointerPortalMapper.externalPoint(
                for: PointerPortalEntry(
                    viewerPoint: event.location,
                    renderRect: event.renderRect,
                    displayFrame: selectedDisplay.coreGraphicsFrame
                )
            ),
            let returnPoint = CoordinateMapper.map(point: event.location, in: event.renderRect, to: geometry.captureFrame)
        else {
            publishMode(.viewOnly)
            return
        }

        guard dependencies.startEscapeTap() else {
            dependencies.stopEscapeTap()
            publishMode(.viewOnly)
            return
        }

        guard dependencies.startPointerBoundary(
            selectedDisplay.coreGraphicsFrame,
            { [weak self] exit in self?.returnFromBoundaryExit(exit) },
            { [weak self] in
                Task { @MainActor in
                    await self?.returnToViewer(reason: .eventTapFailure)
                }
            }
        ) else {
            dependencies.stopPointerBoundary()
            dependencies.stopEscapeTap()
            publishMode(.viewOnly)
            return
        }
        isPointerBoundaryActive = true

        guard dependencies.warpCursor(externalPoint) else {
            dependencies.stopPointerBoundary()
            isPointerBoundaryActive = false
            dependencies.stopEscapeTap()
            publishMode(.viewOnly)
            return
        }

        savedReturnPoint = returnPoint
        savedPortalGeometry = geometry
        didReturnForCurrentTransfer = false
        apply(.interactiveEnabled)
        apply(.pointerTransferred)
        publishMode(.interactive)
        viewer.model.hud.showControlTransfer()
        dependencies.showControlHUD()
    }

    public func handlePortalExited() {
        isPortalDisarmedUntilExit = false
    }

    @discardableResult
    public func returnToViewer(reason: ReturnReason) async -> Bool {
        performSynchronousReturnToViewer(target: pendingReturnTarget ?? .savedPoint)
    }

    public func handleSourceOverlapChanged(_ isOverlapping: Bool) {
        guard isOverlapping else {
            return
        }

        switch session.state {
        case .controllingExternal:
            performSynchronousReturnToViewer(target: .savedPoint)
        case .interactiveReady:
            dependencies.stopEscapeTap()
            apply(.interactiveDisabled)
            publishMode(.viewOnly)
        case .idle, .preparing, .viewOnly, .returning, .failed:
            publishMode(.viewOnly)
        }
    }

    @discardableResult
    private func performSynchronousReturnToViewer(target: ReturnTarget = .savedPoint) -> Bool {
        guard !didReturnForCurrentTransfer else {
            return true
        }

        if session.state == .controllingExternal {
            apply(.returnRequested)
        }

        let cancelResult = dependencies.cancelInput()
        if session.state == .returning, isPointerBoundaryActive {
            let boundaryPreparation = dependencies.preparePointerBoundaryReturn()
            if boundaryPreparation == .tornDown {
                isPointerBoundaryActive = false
            }
        }
        dependencies.stopEscapeTap()

        if case .failed = cancelResult {
            pendingReturnTarget = target
            publishSafeViewOnly()
            return false
        }

        let returnPoint = shouldResolveReturnPoint(for: target) ? resolvedReturnPoint(target: target) : nil
        if let returnPoint {
            guard dependencies.warpCursor(returnPoint) else {
                pendingReturnTarget = target
                publishSafeViewOnly()
                return false
            }
        }

        didReturnForCurrentTransfer = true
        pendingReturnTarget = nil
        publishSafeViewOnly()
        if viewer != nil {
            viewer?.model.hud.showReturn()
            dependencies.showReturnHUD()
        }
        savedReturnPoint = nil
        savedPortalGeometry = nil

        if session.state == .returning {
            apply(.returnCompleted)
        } else if session.state == .interactiveReady {
            apply(.interactiveDisabled)
        }
        return true
    }

    private func returnFromBoundaryExit(_ exit: PointerPortalExit) {
        performSynchronousReturnToViewer(target: .boundaryExit(exit))
    }

    private func publishSafeViewOnly() {
        dependencies.activateApp()
        viewer?.bringForward()
        publishMode(.viewOnly)
    }

    @discardableResult
    public func stopMirroring() async -> Bool {
        guard await returnToViewer(reason: .stop) else {
            return false
        }
        forceStopPointerBoundaryIfNeeded()
        await dependencies.stopCapture()
        viewer?.close()
        viewer = nil
        selectedDisplay = nil
        selectedDisplayID = nil
        resetSession()
        return true
    }

    public func applicationWillTerminate() {
        if performSynchronousReturnToViewer(target: pendingReturnTarget ?? .savedPoint) {
            forceStopPointerBoundaryIfNeeded()
        }
    }

    public func applicationShouldTerminate(reply: @escaping @MainActor (Bool) -> Void) async {
        let shouldTerminate = await performTerminationCleanup()
        reply(shouldTerminate)
    }

    public func performTerminationCleanup() async -> Bool {
        guard performSynchronousReturnToViewer(target: pendingReturnTarget ?? .savedPoint) else {
            return false
        }
        forceStopPointerBoundaryIfNeeded()
        await dependencies.stopCapture()
        return true
    }

    func handleDisplayRefresh(_ result: Result<[DisplayInfo], Error>) async {
        switch result {
        case let .success(displays):
            let previousSelectedDisplayID = selectedDisplayID
            applyDisplays(displays)
            if let previousSelectedDisplayID, !displays.contains(where: { $0.id == previousSelectedDisplayID }) {
                await stopAfterDisplayRemoval()
            }
        case let .failure(error):
            recoverableError = error.localizedDescription
        }
    }

    private func stopAfterDisplayRemoval() async {
        guard await returnToViewer(reason: .displayRemoved) else {
            return
        }
        forceStopPointerBoundaryIfNeeded()
        await dependencies.stopCapture()
        viewer?.close()
        viewer = nil
        resetSession()
    }

    private func handleCaptureError(_ error: Error) async {
        recoverableError = error.localizedDescription
        performSynchronousReturnToViewer(target: .savedPoint)
        apply(.fail(error.localizedDescription))
    }

    private func handleFrame(_ frame: CaptureFrame) {
        viewer?.model.updateFrame(frame)
    }

    private func forceStopPointerBoundaryIfNeeded() {
        guard isPointerBoundaryActive else {
            return
        }

        dependencies.stopPointerBoundary()
        isPointerBoundaryActive = false
    }

    private func disableInteractive() async {
        guard session.state == .interactiveReady || session.state == .controllingExternal else {
            publishMode(.viewOnly)
            return
        }

        if session.state == .controllingExternal {
            _ = await returnToViewer(reason: .stop)
            return
        }

        dependencies.stopEscapeTap()
        apply(.interactiveDisabled)
        publishMode(.viewOnly)
    }

    private func makeViewer(display: DisplayInfo) -> ViewerAdapter {
        let callbacks = ViewerCallbacks(
            onPointerDown: { [weak self] event in self?.handlePointerDown(event) },
            onPointerDragged: { [weak self] event in self?.handlePointerDragged(event) },
            onPointerUp: { [weak self] event in self?.handlePointerUp(event) },
            onScroll: { [weak self] event in self?.handleScroll(event) },
            onPortalEntered: { [weak self] event in self?.handlePortalEntered(event) },
            onPortalExited: { [weak self] _ in self?.handlePortalExited() },
            onModeIntent: { [weak self] intent in
                Task { @MainActor in
                    switch intent {
                    case .enableInteractive:
                        await self?.setInteractive(true)
                    case .disableInteractive:
                        await self?.setInteractive(false)
                    }
                }
            },
            onAlwaysOnTopChange: { [weak self] isAlwaysOnTop in
                self?.viewer?.setAlwaysOnTop(isAlwaysOnTop)
            },
            onOverlapChanged: { [weak self] isOverlapping in
                self?.viewer?.model.updateOverlap(isOverlappingSource: isOverlapping)
                self?.handleSourceOverlapChanged(isOverlapping)
            },
            onStop: { [weak self] in
                Task { @MainActor in
                    await self?.stopMirroring()
                }
            }
        )
        return dependencies.makeViewer(display, callbacks)
    }

    private func handleInputFailure(_ failure: PointerOperationFailure) {
        let message = "포인터 제어를 시작할 수 없습니다."
        recoverableError = message
        performSynchronousReturnToViewer(target: .savedPoint)
        apply(.fail(message))
    }

    private func publishMode(_ mode: ViewerMode) {
        viewer?.model.updateModeFromCoordinator(mode)
        dependencies.publishViewerMode(mode)
    }

    private func applyDisplays(_ displays: [DisplayInfo]) {
        self.displays = displays
        if selectedDisplayID == nil || !displays.contains(where: { $0.id == selectedDisplayID }) {
            selectedDisplayID = displays.first(where: { !$0.isBuiltIn })?.id
        }
    }

    private func apply(_ event: MirrorSessionEvent) {
        do {
            try session.apply(event)
        } catch {
            session = MirrorSession()
            try? session.apply(.fail("Invalid state transition"))
        }
    }

    private func resetSession() {
        session = MirrorSession()
        savedReturnPoint = nil
        savedPortalGeometry = nil
        isPortalDisarmedUntilExit = false
        isPointerBoundaryActive = false
        pendingReturnTarget = nil
        didReturnForCurrentTransfer = false
    }

    private enum ReturnTarget {
        case savedPoint
        case boundaryExit(PointerPortalExit)
    }

    private func resolvedReturnPoint(target: ReturnTarget) -> CGPoint? {
        switch target {
        case .savedPoint:
            return resolvedSavedReturnPoint()
        case let .boundaryExit(exit):
            if let geometry = viewer?.pointerPortalGeometry(),
               let point = PointerPortalMapper.returnPoint(for: exit, viewer: geometry) {
                return point
            }
            if let savedPortalGeometry,
               let point = PointerPortalMapper.returnPoint(for: exit, viewer: savedPortalGeometry) {
                isPortalDisarmedUntilExit = true
                return point
            }

            isPortalDisarmedUntilExit = true
            return resolvedSavedReturnPoint()
        }
    }

    private func shouldResolveReturnPoint(for target: ReturnTarget) -> Bool {
        switch target {
        case .boundaryExit:
            true
        case .savedPoint:
            session.state == .returning || savedReturnPoint != nil
        }
    }

    private func resolvedSavedReturnPoint() -> CGPoint? {
        let viewerFrame = viewer?.captureGlobalFrame()
        if let viewerFrame, viewerFrame.isFiniteReturnFrame {
            return ReturnPointPolicy.resolve(savedGlobalPoint: savedReturnPoint, viewerCaptureGlobalFrame: viewerFrame)
        }

        guard
            let savedReturnPoint,
            savedReturnPoint.x.isFinite,
            savedReturnPoint.y.isFinite
        else {
            return nil
        }

        return savedReturnPoint
    }

    private static func liveDependencies(
        permissionManager: PermissionManager,
        displayManager: DisplayManager,
        captureManager: ScreenCaptureManager,
        inputManager: InputEventManager,
        escapeController: EscapeReturnController,
        pointerBoundaryController: PointerBoundaryControlling,
        poster: CGEventPoster
    ) -> Dependencies {
        Dependencies(
            refreshPermissions: { permissionManager.refresh() },
            requestScreenRecording: { permissionManager.requestScreenRecording() },
            requestPostEvents: { permissionManager.requestPostEvents() },
            requestListenEvents: { permissionManager.requestListenEvents() },
            openPermissionSettings: { pane in
                let urls = [
                    "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?\(pane.systemSettingsAnchor)",
                    "x-apple.systempreferences:com.apple.preference.security?\(pane.systemSettingsAnchor)"
                ]
                for spec in urls {
                    guard let url = URL(string: spec) else {
                        continue
                    }
                    if NSWorkspace.shared.open(url) {
                        break
                    }
                }
            },
            refreshDisplays: { try await displayManager.refresh() },
            startCapture: { display, frameHandler in
                guard let target = displayManager.captureTarget(for: display) else {
                    throw AppCoordinatorError.captureTargetUnavailable
                }
                try await captureManager.start(display: target, frameHandler: frameHandler)
            },
            stopCapture: { await captureManager.stop() },
            makeViewer: { display, callbacks in
                let hud = TransitionHUDController()
                let presenter = SurfacePresenter()
                let model = ViewerViewModel(
                    selectedDisplay: display,
                    hud: hud,
                    presenter: presenter,
                    permissions: permissionManager.refresh(),
                    onPointerDown: callbacks.onPointerDown,
                    onPointerDragged: callbacks.onPointerDragged,
                    onPointerUp: callbacks.onPointerUp,
                    onScroll: callbacks.onScroll,
                    onPortalEntered: callbacks.onPortalEntered,
                    onPortalExited: callbacks.onPortalExited,
                    onModeIntent: callbacks.onModeIntent,
                    onAlwaysOnTopChange: callbacks.onAlwaysOnTopChange,
                    onStop: callbacks.onStop
                )
                var controller: MirrorWindowController?
                controller = MirrorWindowController(
                    viewModel: model,
                    onOverlapChanged: { isOverlapping in
                        callbacks.onOverlapChanged(isOverlapping)
                    }
                )
                return ViewerAdapter(
                    model: model,
                    open: { controller?.open(onPreferredScreen: ViewerScreenPolicy.preferredScreen(screens: NSScreen.screens)) },
                    close: { controller?.close() },
                    bringForward: { controller?.bringForward() },
                    setAlwaysOnTop: { controller?.setAlwaysOnTop($0) },
                    captureGlobalFrame: { controller?.captureGlobalFrame() },
                    pointerPortalGeometry: { controller?.pointerPortalGeometry() }
                )
            },
            beginInput: { button, clickCount, point, renderRect, displayFrame in
                inputManager.begin(button: button, clickCount: clickCount, viewerPoint: point, renderRect: renderRect, displayFrame: displayFrame)
            },
            dragInput: { point, renderRect, displayFrame in
                inputManager.drag(to: point, renderRect: renderRect, displayFrame: displayFrame)
            },
            endInput: { point, renderRect, displayFrame in
                inputManager.end(at: point, renderRect: renderRect, displayFrame: displayFrame)
            },
            scrollInput: { deltaX, deltaY, point, renderRect, displayFrame in
                inputManager.scroll(deltaX: deltaX, deltaY: deltaY, viewerPoint: point, renderRect: renderRect, displayFrame: displayFrame)
            },
            cancelInput: { inputManager.cancelActiveSequence() },
            startEscapeTap: { escapeController.start() },
            stopEscapeTap: { escapeController.stop() },
            startPointerBoundary: { displayFrame, onExit, onTapFailure in
                pointerBoundaryController.onExit = onExit
                pointerBoundaryController.onTapFailure = onTapFailure
                return pointerBoundaryController.start(displayFrame: displayFrame)
            },
            preparePointerBoundaryReturn: { pointerBoundaryController.prepareForReturn() },
            stopPointerBoundary: { pointerBoundaryController.stop() },
            warpCursor: { poster.warp(to: $0) },
            activateApp: { NSApp.activate(ignoringOtherApps: true) },
            showControlHUD: {},
            showReturnHUD: {}
        )
    }
}

private enum AppCoordinatorError: LocalizedError {
    case captureTargetUnavailable

    var errorDescription: String? {
        switch self {
        case .captureTargetUnavailable:
            "선택한 디스플레이를 캡처 대상으로 찾을 수 없습니다. 디스플레이 목록을 새로고침하세요."
        }
    }
}
