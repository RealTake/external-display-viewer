import Foundation

public struct CaptureMetricsSnapshot: Equatable, Sendable {
    public let displayedFPS: Double
    public let incompleteRatio: Double
    public let receivedFrames: Int
    public let displayedFrames: Int

    public init(displayedFPS: Double, incompleteRatio: Double, receivedFrames: Int, displayedFrames: Int) {
        self.displayedFPS = displayedFPS
        self.incompleteRatio = incompleteRatio
        self.receivedFrames = receivedFrames
        self.displayedFrames = displayedFrames
    }
}

public struct CaptureMetrics: Sendable {
    private static let recentDisplayedWindow: TimeInterval = 1

    private var receivedFrameCount = 0
    private var incompleteFrameCount = 0
    private var displayedFrameCount = 0
    private var recentDisplayedTimestamps: [TimeInterval] = []
    private var lastPublishedAt: TimeInterval?

    public init() {}

    public mutating func recordReceived(isComplete: Bool, at timestamp: TimeInterval) {
        receivedFrameCount += 1

        if !isComplete {
            incompleteFrameCount += 1
        }

        pruneRecentDisplayedTimestamps(at: timestamp)
    }

    public mutating func recordDisplayed(at timestamp: TimeInterval) {
        displayedFrameCount += 1
        recentDisplayedTimestamps.append(timestamp)

        pruneRecentDisplayedTimestamps(at: timestamp)
    }

    private mutating func pruneRecentDisplayedTimestamps(at timestamp: TimeInterval) {
        let recentWindowStart = timestamp - Self.recentDisplayedWindow
        recentDisplayedTimestamps.removeAll { $0 < recentWindowStart }
    }

    public mutating func shouldPublishSnapshot(at timestamp: TimeInterval) -> Bool {
        guard let lastPublishedAt else {
            self.lastPublishedAt = timestamp
            return true
        }

        guard timestamp - lastPublishedAt >= 1 else {
            return false
        }

        self.lastPublishedAt = timestamp
        return true
    }

    public var snapshot: CaptureMetricsSnapshot {
        let incompleteRatio = receivedFrameCount == 0 ? 0 : Double(incompleteFrameCount) / Double(receivedFrameCount)
        let displayedFPS: Double

        if let firstDisplayedAt = recentDisplayedTimestamps.first,
           let lastDisplayedAt = recentDisplayedTimestamps.last,
           lastDisplayedAt > firstDisplayedAt {
            displayedFPS = Double(recentDisplayedTimestamps.count - 1) / (lastDisplayedAt - firstDisplayedAt)
        } else {
            displayedFPS = 0
        }

        return CaptureMetricsSnapshot(
            displayedFPS: displayedFPS,
            incompleteRatio: incompleteRatio,
            receivedFrames: receivedFrameCount,
            displayedFrames: displayedFrameCount
        )
    }
}
