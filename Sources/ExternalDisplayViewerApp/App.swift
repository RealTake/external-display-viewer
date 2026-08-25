import ExternalDisplayViewerCore
import SwiftUI

@main
struct ExternalDisplayViewerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        ExternalDisplayViewerLaunchScene { coordinator in
            appDelegate.coordinator = coordinator
        }
    }
}

@MainActor
private final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var coordinator: AppCoordinator?
    private let terminationRequests = TerminationRequestCoordinator()

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let coordinator else {
            return .terminateNow
        }

        let decision = terminationRequests.request(
            hasCoordinator: true,
            cleanup: { [coordinator] in
                await coordinator.performTerminationCleanup()
            },
            reply: { shouldTerminate in
                sender.reply(toApplicationShouldTerminate: shouldTerminate)
            }
        )

        switch decision {
        case .terminateNow:
            return .terminateNow
        case .terminateLaterStarted, .terminateLaterAlreadyInProgress:
            return .terminateLater
        }
    }
}
