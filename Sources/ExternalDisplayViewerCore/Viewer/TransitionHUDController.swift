import Combine
import Foundation

@MainActor
public final class TransitionHUDController: ObservableObject {
    public static let controlMessage = InteractionHUDMessages.control
    public static let returnMessage = InteractionHUDMessages.returnToViewer

    @Published public private(set) var message: String?
    @Published public private(set) var opacity = 0.0

    private let fadeDuration: Duration
    private var expiryTask: Task<Void, Never>?
    private var generation = 0

    public init(fadeDuration: Duration = .milliseconds(160)) {
        self.fadeDuration = fadeDuration
    }

    deinit {
        expiryTask?.cancel()
    }

    public func showControlTransfer(duration: Duration = InteractionContract.controlHUDDuration) {
        show(Self.controlMessage, duration: duration)
    }

    public func showReturn(duration: Duration = InteractionContract.returnHUDDuration) {
        show(Self.returnMessage, duration: duration)
    }

    private func show(_ message: String, duration: Duration) {
        generation += 1
        let generation = generation
        expiryTask?.cancel()
        self.message = message
        opacity = 1
        let fadeDelay = max(.zero, duration - fadeDuration)
        let removalDelay = duration - fadeDelay
        expiryTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: fadeDelay)
            } catch {
                return
            }

            guard self?.beginFade(generation: generation) == true else {
                return
            }

            do {
                try await Task.sleep(for: removalDelay)
            } catch {
                return
            }

            self?.remove(generation: generation)
        }
    }

    private func beginFade(generation: Int) -> Bool {
        guard generation == self.generation else {
            return false
        }

        opacity = 0
        return true
    }

    private func remove(generation: Int) {
        guard generation == self.generation else {
            return
        }

        message = nil
        expiryTask = nil
    }
}
