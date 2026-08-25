@preconcurrency import CoreMedia
@preconcurrency import CoreVideo
import Foundation
import IOSurface
@preconcurrency import ScreenCaptureKit

public struct CaptureFrame: @unchecked Sendable {
    public let surface: IOSurfaceRef
    public let size: CGSize
    public let displayTime: UInt64

    public init(surface: IOSurfaceRef, size: CGSize, displayTime: UInt64) {
        self.surface = surface
        self.size = size
        self.displayTime = displayTime
    }
}

public final class ScreenCaptureManager: NSObject, @unchecked Sendable {
    public typealias FrameHandler = @MainActor @Sendable (CaptureFrame) -> Void
    public typealias MetricsHandler = @MainActor @Sendable (CaptureMetricsSnapshot) -> Void
    public typealias ErrorHandler = @MainActor @Sendable (Error) -> Void

    private let sampleQueue = DispatchQueue(label: "local.codex.ExternalDisplayViewer.capture.samples")
    private let stateQueue = DispatchQueue(label: "local.codex.ExternalDisplayViewer.capture.state")
    private var stream: SCStream?
    private var frameHandler: FrameHandler?
    private var metricsHandler: MetricsHandler?
    private var errorHandler: ErrorHandler?
    private var metrics = CaptureMetrics()
    private var deliveryScheduler = CaptureFrameDeliveryScheduler<CaptureFrame>()
    private var streamSession = CaptureStreamSession<SCStream>()

    public init(metricsHandler: MetricsHandler? = nil, errorHandler: ErrorHandler? = nil) {
        self.metricsHandler = metricsHandler
        self.errorHandler = errorHandler
        super.init()
    }

    public func setMetricsHandler(_ handler: MetricsHandler?) {
        stateQueue.sync {
            metricsHandler = handler
        }
    }

    public func setErrorHandler(_ handler: ErrorHandler?) {
        stateQueue.sync {
            errorHandler = handler
        }
    }

    @MainActor
    public func start(
        display: SCDisplay,
        excluding bundleIdentifier: String? = Bundle.main.bundleIdentifier,
        frameHandler: @escaping FrameHandler
    ) async throws {
        await stop()

        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let excludedApplication = bundleIdentifier.flatMap { identifier in
            content.applications.first { $0.bundleIdentifier == identifier }
        }
        let filter = Self.makeFilter(display: display, excluding: excludedApplication)
        let scale = CGFloat(filter.pointPixelScale == 0 ? 1 : filter.pointPixelScale)
        let configuration = CaptureSettings.makeConfiguration(
            widthInPoints: CGFloat(display.width),
            heightInPoints: CGFloat(display.height),
            scale: scale
        )
        let stream = SCStream(filter: filter, configuration: configuration, delegate: self)

        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: sampleQueue)

        stateQueue.sync {
            self.stream = stream
            self.frameHandler = frameHandler
            self.metrics = CaptureMetrics()
            let generation = self.streamSession.begin(stream: stream)
            self.deliveryScheduler.beginSession(generation: generation)
        }

        do {
            try await stream.startCapture()
        } catch {
            stateQueue.sync {
                if self.stream === stream {
                    self.stream = nil
                    self.frameHandler = nil
                    self.streamSession.end(stream: stream)
                    self.deliveryScheduler.beginSession(generation: self.streamSession.generation)
                }
            }
            throw error
        }
    }

    @MainActor
    public func stop() async {
        let activeStream = stateQueue.sync { () -> SCStream? in
            let activeStream = stream
            stream = nil
            frameHandler = nil
            streamSession.endCurrent()
            deliveryScheduler.beginSession(generation: streamSession.generation)
            return activeStream
        }

        guard let activeStream else {
            return
        }

        try? activeStream.removeStreamOutput(self, type: .screen)
        try? await activeStream.stopCapture()
    }

    private static func makeFilter(display: SCDisplay, excluding application: SCRunningApplication?) -> SCContentFilter {
        guard let application else {
            return SCContentFilter(display: display, excludingWindows: [])
        }

        return SCContentFilter(display: display, excludingApplications: [application], exceptingWindows: [])
    }

    private func handle(sampleBuffer: CMSampleBuffer, from stream: SCStream) {
        let timestamp = ProcessInfo.processInfo.systemUptime
        let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]]
        let statusRawValue = attachments?.first?[.status] as? Int
        let isComplete = statusRawValue.flatMap(SCFrameStatus.init(rawValue:)) == .complete
        let receivedState = stateQueue.sync { () -> (UInt64?, CaptureMetricsSnapshot?) in
            guard let generation = streamSession.accept(stream: stream) else {
                return (nil, nil)
            }

            metrics.recordReceived(isComplete: isComplete, at: timestamp)

            if metrics.shouldPublishSnapshot(at: timestamp) {
                return (generation, metrics.snapshot)
            }

            return (generation, nil)
        }

        guard let generation = receivedState.0 else {
            return
        }

        publishMetricsIfNeeded(receivedState.1, generation: generation)

        guard isComplete, let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }

        guard let unmanagedSurface = CVPixelBufferGetIOSurface(pixelBuffer) else {
            return
        }

        let surface = unmanagedSurface.takeUnretainedValue()
        let displayTime = (attachments?.first?[.displayTime] as? NSNumber)?.uint64Value ?? 0
        let frame = CaptureFrame(
            surface: surface,
            size: CGSize(width: CVPixelBufferGetWidth(pixelBuffer), height: CVPixelBufferGetHeight(pixelBuffer)),
            displayTime: displayTime
        )
        submitLatestFrame(frame, generation: generation)
    }

    private func submitLatestFrame(_ frame: CaptureFrame, generation: UInt64) {
        let generationToSchedule = stateQueue.sync { () -> UInt64? in
            guard frameHandler != nil, streamSession.generation == generation else {
                return nil
            }

            return deliveryScheduler.submit(frame, generation: generation) ? generation : nil
        }

        guard let generationToSchedule else {
            return
        }

        scheduleFrameDelivery(generation: generationToSchedule)
    }

    private func scheduleFrameDelivery(generation: UInt64) {
        Task { @MainActor in
            let preparedDelivery = stateQueue.sync {
                deliveryScheduler.prepareDelivery(generation: generation)
            }

            let committedDelivery = stateQueue.sync { () -> (CaptureFrame?, FrameHandler?) in
                guard streamSession.generation == generation else {
                    return (nil, nil)
                }

                let frame = deliveryScheduler.commitPreparedDelivery(preparedDelivery)
                return (frame, frameHandler)
            }

            guard let frame = committedDelivery.0, let handler = committedDelivery.1 else {
                return
            }

            handler(frame)

            let timestamp = ProcessInfo.processInfo.systemUptime
            let nextGenerationToSchedule = stateQueue.sync { () -> (CaptureMetricsSnapshot?, UInt64?) in
                guard generation == streamSession.generation else {
                    return (nil, nil)
                }

                metrics.recordDisplayed(at: timestamp)
                let snapshot = metrics.shouldPublishSnapshot(at: timestamp) ? metrics.snapshot : nil
                let shouldReschedule = deliveryScheduler.completeScheduledTurn(generation: generation)
                return (snapshot, shouldReschedule ? generation : nil)
            }
            publishMetricsIfNeeded(nextGenerationToSchedule.0, generation: generation)

            if let generation = nextGenerationToSchedule.1 {
                scheduleFrameDelivery(generation: generation)
            }
        }
    }

    private func publishMetricsIfNeeded(_ snapshot: CaptureMetricsSnapshot?, generation: UInt64) {
        guard let snapshot else {
            return
        }

        let handler = stateQueue.sync {
            metricsHandler
        }

        guard let handler else {
            return
        }

        Task { @MainActor in
            let isCurrentGeneration = stateQueue.sync {
                streamSession.generation == generation
            }
            guard isCurrentGeneration else {
                return
            }

            handler(snapshot)
        }
    }

    private func publishError(_ error: Error, generation: UInt64) {
        let handler = stateQueue.sync {
            errorHandler
        }

        guard let handler else {
            return
        }

        Task { @MainActor in
            let isCurrentGeneration = stateQueue.sync {
                streamSession.generation == generation
            }
            guard isCurrentGeneration else {
                return
            }

            handler(error)
        }
    }
}

extension ScreenCaptureManager: SCStreamOutput, SCStreamDelegate {
    public func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen else {
            return
        }

        handle(sampleBuffer: sampleBuffer, from: stream)
    }

    public func stream(_ stream: SCStream, didStopWithError error: Error) {
        Task { @MainActor in
            let errorGeneration = stateQueue.sync { () -> UInt64? in
                guard self.stream === stream else {
                    return nil
                }

                self.stream = nil
                self.frameHandler = nil
                self.streamSession.end(stream: stream)
                self.deliveryScheduler.beginSession(generation: self.streamSession.generation)
                return self.streamSession.generation
            }

            if let errorGeneration {
                publishError(error, generation: errorGeneration)
            }
        }
    }
}
