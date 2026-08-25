import SwiftUI

@MainActor
public struct ViewerRootView: View {
    @ObservedObject private var model: ViewerViewModel
    #if DEBUG
    private let showsPreviewPattern: Bool
    private let previewHUDMessage: String?
    private let previewHUDOpacity: Double
    #endif

    public init(model: ViewerViewModel) {
        self.model = model
        #if DEBUG
        showsPreviewPattern = false
        previewHUDMessage = nil
        previewHUDOpacity = 0
        #endif
    }

    #if DEBUG
    public init(
        previewMetrics metrics: CaptureMetricsSnapshot = CaptureMetricsSnapshot(
            displayedFPS: 59.8,
            incompleteRatio: 0.003,
            receivedFrames: 1800,
            displayedFrames: 1794
        ),
        hud: TransitionHUDController = TransitionHUDController(),
        presenter: SurfacePresenter = SurfacePresenter()
    ) {
        let display = DisplayInfo(
            id: 2,
            name: "Preview",
            coreGraphicsFrame: CGRect(x: 1920, y: 0, width: 1920, height: 1080),
            appKitFrame: CGRect(x: 1920, y: 0, width: 1920, height: 1080),
            pixelSize: CGSize(width: 1920, height: 1080),
            scale: 1,
            isBuiltIn: false
        )
        let model = ViewerViewModel(
            selectedDisplay: display,
            metrics: metrics,
            hud: hud,
            presenter: presenter
        )
        self.model = model
        self.showsPreviewPattern = true
        self.previewHUDMessage = nil
        self.previewHUDOpacity = 0
    }

    public init(previewState state: VisualQAPreviewState) {
        let display = state.displays.first ?? DisplayInfo(
            id: 2,
            name: "Preview",
            coreGraphicsFrame: CGRect(x: 1920, y: 0, width: 1920, height: 1080),
            appKitFrame: CGRect(x: 1920, y: 0, width: 1920, height: 1080),
            pixelSize: CGSize(width: 1920, height: 1080),
            scale: 1,
            isBuiltIn: false
        )
        let model = ViewerViewModel(
            selectedDisplay: display,
            metrics: state.metrics,
            hud: TransitionHUDController(),
            presenter: SurfacePresenter(),
            permissions: state.permissions
        )
        model.updateOverlap(isOverlappingSource: state.isOverlappingSource)
        model.updateModeFromCoordinator(state.viewerMode)
        self.model = model
        self.showsPreviewPattern = true
        self.previewHUDMessage = state.hudMessage
        self.previewHUDOpacity = state.hudOpacity
    }
    #endif

    public var body: some View {
        VStack(spacing: 0) {
            viewerSurface
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()

            controlsFooter
            diagnosticsFooter
        }
        .background(Color.black)
        .frame(minWidth: 640, minHeight: 420)
    }

    private var viewerSurface: some View {
        GeometryReader { proxy in
            let sourceAspectRatio = ViewerRootLayout.sourceAspectRatio(sourceSize: model.sourceSize)
            let renderRect = ViewerRootLayout.renderRect(
                containerSize: proxy.size,
                sourceAspectRatio: sourceAspectRatio
            )

            ZStack(alignment: .topLeading) {
                MirrorSurfaceRepresentable(
                    presenter: model.presenter,
                    isInteractive: model.isInteractive,
                    onPointerDown: model.onPointerDown,
                    onPointerDragged: model.onPointerDragged,
                    onPointerUp: model.onPointerUp,
                    onScroll: model.onScroll,
                    onPortalEntered: model.onPortalEntered,
                    onPortalExited: model.onPortalExited
                )
                .background(Color.black)

                #if DEBUG
                if showsPreviewPattern {
                    PreviewGridPattern(renderRect: renderRect)
                        .allowsHitTesting(false)
                }
                #endif

                #if DEBUG
                if let message = model.hud.message {
                    hudView(message, opacity: model.hud.opacity, renderRect: renderRect)
                } else if let message = previewHUDMessage {
                    hudView(message, opacity: previewHUDOpacity, renderRect: renderRect)
                }
                #else
                if let message = model.hud.message {
                    hudView(message, opacity: model.hud.opacity, renderRect: renderRect)
                }
                #endif
            }
        }
    }

    private var controlsFooter: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                modeIndicator
                    .frame(width: 220)

                Toggle("Always on Top", isOn: alwaysOnTopBinding)
                    .toggleStyle(.switch)
                    .fixedSize(horizontal: true, vertical: false)

                Spacer(minLength: 8)

                Button("Stop") {
                    model.stop()
                }
                .keyboardShortcut(.cancelAction)
            }

            HStack(spacing: 10) {
                Text(model.selectedDisplay.menuLabel)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(model.mode == .interactive ? "Interactive" : "View Only")
                    .fontWeight(.semibold)
                Spacer(minLength: 8)
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if let disabledReason = model.interactiveDisabledReason {
                Text(disabledReason)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .font(.callout)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial)
    }

    private var diagnosticsFooter: some View {
        HStack(spacing: 14) {
            Text("FPS \(model.metrics.displayedFPS, specifier: "%.1f")")
            Text("Incomplete \(model.metrics.incompleteRatio * 100, specifier: "%.1f")%")
            Text("Received \(model.metrics.receivedFrames)")
            Text("Displayed \(model.metrics.displayedFrames)")
        }
        .font(.caption.monospacedDigit())
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity)
        .background(.regularMaterial)
    }

    private var alwaysOnTopBinding: Binding<Bool> {
        Binding(
            get: { model.isAlwaysOnTop },
            set: { model.setAlwaysOnTop($0) }
        )
    }

    private var modeIndicator: some View {
        HStack(spacing: 0) {
            modeSegment(.viewOnly)
            modeSegment(.interactive)
        }
        .padding(2)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .opacity(0.72)
        .allowsHitTesting(false)
        .accessibilityLabel("Mode")
        .accessibilityValue(model.mode.title)
    }

    private func modeSegment(_ mode: ViewerMode) -> some View {
        Text(mode.title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(model.mode == mode ? .primary : .secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(maxWidth: .infinity, minHeight: 22)
            .background {
                if model.mode == mode {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(.regularMaterial)
                }
            }
    }

    private func hudView(_ message: String, opacity: Double, renderRect: CGRect) -> some View {
        let frame = ViewerRootLayout.hudFrame(
            in: renderRect,
            preferredWidth: 420,
            horizontalPadding: 16,
            topPadding: 14,
            height: 56
        )

        return hudLabel(message)
            .font(.callout.weight(.semibold))
            .lineLimit(2)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .frame(width: frame.width)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .position(x: frame.midX, y: frame.midY)
            .opacity(opacity)
            .animation(.easeInOut(duration: 0.16), value: opacity)
            .allowsHitTesting(false)
    }

    private func hudLabel(_ message: String) -> Text {
        guard message == TransitionHUDController.controlMessage else {
            return Text(message)
        }

        return Text("외부 디스플레이 제어 중 ")
            + Text("·")
                .font(.caption2.weight(.medium))
                .baselineOffset(-1)
            + Text(" 화면 경계 또는 ESC를 길게 눌러 돌아오기")
    }
}

enum ViewerRootLayout {
    static let previewSourceAspectRatio: CGFloat = 16.0 / 9.0

    static func sourceAspectRatio(sourceSize: CGSize) -> CGFloat {
        guard sourceSize.width > 0, sourceSize.height > 0 else {
            return previewSourceAspectRatio
        }

        return sourceSize.width / sourceSize.height
    }

    static func renderRect(containerSize: CGSize, sourceAspectRatio: CGFloat) -> CGRect {
        CoordinateMapper.renderRect(contentSize: containerSize, sourceAspectRatio: sourceAspectRatio)
    }

    static func previewRenderRect(containerSize: CGSize) -> CGRect {
        renderRect(containerSize: containerSize, sourceAspectRatio: previewSourceAspectRatio)
    }

    static func hudFrame(
        in renderRect: CGRect,
        preferredWidth: CGFloat,
        horizontalPadding: CGFloat,
        topPadding: CGFloat,
        height: CGFloat
    ) -> CGRect {
        let availableWidth = max(0, renderRect.width - horizontalPadding * 2)
        let width = min(preferredWidth, availableWidth)
        return CGRect(
            x: renderRect.midX - width / 2,
            y: renderRect.minY + topPadding,
            width: width,
            height: height
        )
    }
}

#if DEBUG
private struct PreviewGridPattern: View {
    let renderRect: CGRect

    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.black))

            var grid = Path()
            let step: CGFloat = 48
            stride(from: renderRect.minX, through: renderRect.maxX, by: step).forEach { x in
                grid.move(to: CGPoint(x: x, y: renderRect.minY))
                grid.addLine(to: CGPoint(x: x, y: renderRect.maxY))
            }
            stride(from: renderRect.minY, through: renderRect.maxY, by: step).forEach { y in
                grid.move(to: CGPoint(x: renderRect.minX, y: y))
                grid.addLine(to: CGPoint(x: renderRect.maxX, y: y))
            }
            context.stroke(grid, with: .color(.white.opacity(0.22)), lineWidth: 1)

            let horizontal = CGRect(x: renderRect.minX, y: renderRect.midY - 1, width: renderRect.width, height: 2)
            let vertical = CGRect(x: renderRect.midX - 1, y: renderRect.minY, width: 2, height: renderRect.height)
            context.fill(Path(horizontal), with: .color(.red.opacity(0.75)))
            context.fill(Path(vertical), with: .color(.green.opacity(0.75)))
        }
    }
}
#endif
