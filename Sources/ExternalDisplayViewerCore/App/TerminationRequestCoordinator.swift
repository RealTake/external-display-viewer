import Foundation

@MainActor
public final class TerminationRequestCoordinator {
    public enum Decision: Equatable, Sendable {
        case terminateNow
        case terminateLaterStarted
        case terminateLaterAlreadyInProgress
    }

    private var isCleanupInProgress = false

    public init() {}

    @discardableResult
    public func request(
        hasCoordinator: Bool,
        cleanup: @escaping @MainActor () async -> Bool,
        reply: @escaping @MainActor (Bool) -> Void
    ) -> Decision {
        guard hasCoordinator else {
            return .terminateNow
        }

        guard !isCleanupInProgress else {
            return .terminateLaterAlreadyInProgress
        }

        isCleanupInProgress = true
        Task { @MainActor [weak self] in
            let shouldTerminate = await cleanup()
            reply(shouldTerminate)
            self?.isCleanupInProgress = false
        }
        return .terminateLaterStarted
    }
}
