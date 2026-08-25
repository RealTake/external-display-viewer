import ExternalDisplayViewerCore
import SwiftUI

struct ExternalDisplayViewerLaunchScene: Scene {
    private let installCoordinator: @MainActor (AppCoordinator) -> Void

    init(installCoordinator: @escaping @MainActor (AppCoordinator) -> Void) {
        self.installCoordinator = installCoordinator
    }

    var body: some Scene {
        WindowGroup(windowTitle) {
            launchRoot
        }
        .defaultSize(width: windowSize.width, height: windowSize.height)
    }

    @ViewBuilder
    private var launchRoot: some View {
        #if DEBUG
        if let previewState {
            VisualQAPreviewRoot(state: previewState)
        } else {
            LiveRootView(installCoordinator: installCoordinator)
        }
        #else
        LiveRootView(installCoordinator: installCoordinator)
        #endif
    }

    private var windowTitle: String {
        #if DEBUG
        if let previewState {
            return previewState.windowTitle
        }
        #endif
        return "External Display Viewer"
    }

    private var windowSize: CGSize {
        #if DEBUG
        if let previewState {
            return previewState.windowSize
        }
        #endif
        return CGSize(width: 620, height: 520)
    }

    #if DEBUG
    private var previewState: VisualQAPreviewState? {
        VisualQAPreviewState.parse(
            environment: ProcessInfo.processInfo.environment,
            arguments: CommandLine.arguments
        )
    }
    #endif
}

@MainActor
private struct LiveRootView: View {
    let installCoordinator: @MainActor (AppCoordinator) -> Void
    @StateObject private var coordinator = AppCoordinator()

    var body: some View {
        RootView(coordinator: coordinator)
            .onAppear {
                installCoordinator(coordinator)
            }
    }
}
