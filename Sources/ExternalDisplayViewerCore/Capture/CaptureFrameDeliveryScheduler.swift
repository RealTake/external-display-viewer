struct CaptureFrameDeliveryScheduler<Frame> {
    struct PreparedDelivery {
        fileprivate let frame: Frame
        fileprivate let generation: UInt64
    }

    private(set) var generation: UInt64 = 0
    private var latestFrame: Frame?
    private var isTurnScheduled = false
    private var isDeliveryPrepared = false
    private var isDeliveryInProgress = false

    mutating func beginSession() -> UInt64 {
        generation &+= 1
        resetDeliveryState()
        return generation
    }

    mutating func beginSession(generation: UInt64) {
        self.generation = generation
        resetDeliveryState()
    }

    mutating func endSession() {
        generation &+= 1
        resetDeliveryState()
    }

    mutating func submit(_ frame: Frame, generation submittedGeneration: UInt64) -> Bool {
        guard submittedGeneration == generation else {
            return false
        }

        latestFrame = frame

        guard !isTurnScheduled, !isDeliveryPrepared, !isDeliveryInProgress else {
            return false
        }

        isTurnScheduled = true
        return true
    }

    mutating func takeFrameForDelivery(generation submittedGeneration: UInt64) -> Frame? {
        guard let preparedDelivery = prepareDelivery(generation: submittedGeneration) else {
            return nil
        }

        return commitPreparedDelivery(preparedDelivery)
    }

    mutating func prepareDelivery(generation submittedGeneration: UInt64) -> PreparedDelivery? {
        guard submittedGeneration == generation, isTurnScheduled, let frame = latestFrame else {
            return nil
        }

        latestFrame = nil
        isTurnScheduled = false
        isDeliveryPrepared = true
        return PreparedDelivery(frame: frame, generation: submittedGeneration)
    }

    mutating func commitPreparedDelivery(_ preparedDelivery: PreparedDelivery?) -> Frame? {
        guard let preparedDelivery, preparedDelivery.generation == generation, isDeliveryPrepared else {
            return nil
        }

        isDeliveryPrepared = false
        isDeliveryInProgress = true
        return preparedDelivery.frame
    }

    mutating func completeScheduledTurn(generation submittedGeneration: UInt64) -> Bool {
        guard submittedGeneration == generation else {
            return false
        }

        isDeliveryPrepared = false
        isDeliveryInProgress = false

        guard latestFrame != nil else {
            return false
        }

        isTurnScheduled = true
        return true
    }

    private mutating func resetDeliveryState() {
        latestFrame = nil
        isTurnScheduled = false
        isDeliveryPrepared = false
        isDeliveryInProgress = false
    }
}

struct CaptureStreamSession<Stream: AnyObject> {
    private(set) var generation: UInt64 = 0
    private var activeStreamID: ObjectIdentifier?

    mutating func begin(stream: Stream) -> UInt64 {
        generation &+= 1
        activeStreamID = ObjectIdentifier(stream)
        return generation
    }

    mutating func end(stream: Stream) {
        guard activeStreamID == ObjectIdentifier(stream) else {
            return
        }

        generation &+= 1
        activeStreamID = nil
    }

    mutating func endCurrent() {
        generation &+= 1
        activeStreamID = nil
    }

    func accept(stream: Stream) -> UInt64? {
        guard activeStreamID == ObjectIdentifier(stream) else {
            return nil
        }

        return generation
    }
}
