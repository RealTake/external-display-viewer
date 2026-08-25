import CoreGraphics

public enum PointerBoundaryEvent: Equatable, Sendable {
    case move(location: CGPoint, delta: CGVector)
    case down(button: PointerButton, location: CGPoint)
    case dragged(button: PointerButton, location: CGPoint, delta: CGVector)
    case up(button: PointerButton, location: CGPoint)
}

public enum PointerBoundaryAction: Equatable, Sendable {
    case forward
    case forwardAt(CGPoint)
    case suppress
    case requestReturn(PointerPortalExit)
}

public struct PointerBoundaryForcedRelease: Equatable, Sendable {
    public let button: PointerButton
    public let location: CGPoint

    public init(button: PointerButton, location: CGPoint) {
        self.button = button
        self.location = location
    }
}

public struct PointerBoundaryState: Sendable {
    private let displayFrame: CGRect
    private var pressedButtons: [PointerButton]
    private var pendingPhysicalReleases: [PointerButton]
    private var lastValidPoint: CGPoint
    private var emittedExit: Bool
    private var lastMovementAxis: MovementAxis?
    private let isValidDisplayFrame: Bool

    public init(displayFrame: CGRect) {
        self.displayFrame = displayFrame
        pressedButtons = []
        pendingPhysicalReleases = []
        isValidDisplayFrame = displayFrame.isValidPointerDisplayFrame
        lastValidPoint = displayFrame.isValidPointerDisplayFrame ? displayFrame.lastValidCenter : .zero
        emittedExit = false
        lastMovementAxis = nil
    }

    public mutating func consume(_ event: PointerBoundaryEvent) -> PointerBoundaryAction {
        guard isValidDisplayFrame else {
            return .forward
        }

        switch event {
        case let .move(location, delta):
            return consumeMove(location: location, delta: delta)
        case let .down(button, location):
            track(button)
            updateLastValidPoint(from: location)
            return .forward
        case let .dragged(button, location, delta):
            track(button)
            guard location.isFinitePointerPoint, delta.isFinitePointerDelta else {
                return .forward
            }
            updateMovementAxis(for: delta)
            updateLastValidPoint(from: location)
            return .forwardAt(lastValidPoint)
        case let .up(button, location):
            untrack(button)
            guard location.isFinitePointerPoint else {
                return .forward
            }
            let clampedPoint = location.clampedToLastValidPoint(in: displayFrame)
            lastValidPoint = clampedPoint
            return location == clampedPoint ? .forward : .forwardAt(clampedPoint)
        }
    }

    public mutating func beginForcedReturn() -> [PointerBoundaryForcedRelease] {
        guard isValidDisplayFrame else {
            return []
        }

        let buttons = PointerButton.allCases.filter { pressedButtons.contains($0) && !pendingPhysicalReleases.contains($0) }
        pendingPhysicalReleases.append(contentsOf: buttons)
        pressedButtons.removeAll { buttons.contains($0) }
        return buttons.map { PointerBoundaryForcedRelease(button: $0, location: lastValidPoint) }
    }

    public mutating func consumeRelease(_ button: PointerButton) -> PointerBoundaryAction {
        guard isValidDisplayFrame else {
            return .forward
        }

        guard pendingPhysicalReleases.contains(button) else {
            untrack(button)
            return .forward
        }

        pendingPhysicalReleases.removeAll { $0 == button }
        untrack(button)
        return .suppress
    }

    private mutating func consumeMove(location: CGPoint, delta: CGVector) -> PointerBoundaryAction {
        guard location.isFinitePointerPoint, delta.isFinitePointerDelta else {
            return .forward
        }

        updateMovementAxis(for: delta)
        let previousPoint = lastValidPoint
        let nextPoint = location.clampedToLastValidPoint(in: displayFrame)
        guard pressedButtons.isEmpty, !emittedExit else {
            lastValidPoint = nextPoint
            return .forward
        }

        guard let exit = exit(from: previousPoint, to: location, delta: delta) else {
            lastValidPoint = nextPoint
            return .forward
        }

        lastValidPoint = nextPoint
        emittedExit = true
        return .requestReturn(exit)
    }

    private mutating func updateLastValidPoint(from location: CGPoint) {
        guard location.isFinitePointerPoint else {
            return
        }
        lastValidPoint = location.clampedToLastValidPoint(in: displayFrame)
    }

    private mutating func updateMovementAxis(for delta: CGVector) {
        let horizontal = abs(delta.dx)
        let vertical = abs(delta.dy)
        if horizontal > vertical {
            lastMovementAxis = .horizontal
        } else if vertical > horizontal {
            lastMovementAxis = .vertical
        }
    }

    private func exit(from previousPoint: CGPoint, to location: CGPoint, delta: CGVector) -> PointerPortalExit? {
        guard location.isFinitePointerPoint, delta.isFinitePointerDelta else {
            return nil
        }

        if displayFrame.containsLastValid(location) {
            return exit(at: location.clampedToLastValidPoint(in: displayFrame), delta: delta)
        }

        return segmentExit(from: previousPoint, to: location, delta: delta)
    }

    private func exit(at point: CGPoint, delta: CGVector) -> PointerPortalExit? {
        guard let mappedExit = PointerPortalMapper.exit(at: point, delta: delta, in: displayFrame) else {
            return nil
        }

        let horizontal = horizontalExit(at: point, delta: delta)
        let vertical = verticalExit(at: point, delta: delta)

        switch (horizontal, vertical) {
        case let (.some(horizontal), .some(vertical)):
            guard abs(delta.dx) == abs(delta.dy) else {
                return mappedExit
            }
            switch preferredAxis(for: delta) {
            case .horizontal:
                return horizontal
            case .vertical:
                return vertical
            }
        default:
            return mappedExit
        }
    }

    private func segmentExit(from previousPoint: CGPoint, to location: CGPoint, delta: CGVector) -> PointerPortalExit? {
        let crossings = segmentCrossings(from: previousPoint, to: location, delta: delta)
        guard !crossings.isEmpty else {
            return exit(at: previousPoint, delta: delta)
        }

        return crossings.sorted { first, second in
            if first.t == second.t {
                let axis = preferredAxis(for: delta)
                return first.axis == axis && second.axis != axis
            }
            return first.t < second.t
        }.first?.exit
    }

    private func segmentCrossings(from previousPoint: CGPoint, to location: CGPoint, delta: CGVector) -> [SegmentCrossing] {
        let dx = location.x - previousPoint.x
        let dy = location.y - previousPoint.y
        var crossings: [SegmentCrossing] = []

        if dx < 0 {
            appendVerticalCrossing(
                edge: .left,
                boundaryX: displayFrame.minX,
                previousPoint: previousPoint,
                dy: dy,
                dx: dx,
                to: &crossings
            )
        } else if dx > 0 {
            appendVerticalCrossing(
                edge: .right,
                boundaryX: displayFrame.lastValidMaxX,
                previousPoint: previousPoint,
                dy: dy,
                dx: dx,
                to: &crossings
            )
        }

        if dy < 0 {
            appendHorizontalCrossing(
                edge: .top,
                boundaryY: displayFrame.minY,
                previousPoint: previousPoint,
                dx: dx,
                dy: dy,
                to: &crossings
            )
        } else if dy > 0 {
            appendHorizontalCrossing(
                edge: .bottom,
                boundaryY: displayFrame.lastValidMaxY,
                previousPoint: previousPoint,
                dx: dx,
                dy: dy,
                to: &crossings
            )
        }

        return crossings.filter { $0.t >= 0 && $0.t <= 1 && isOutward($0.exit.edge, delta: delta) }
    }

    private func appendVerticalCrossing(
        edge: PointerPortalEdge,
        boundaryX: CGFloat,
        previousPoint: CGPoint,
        dy: CGFloat,
        dx: CGFloat,
        to crossings: inout [SegmentCrossing]
    ) {
        let t = (boundaryX - previousPoint.x) / dx
        let y = previousPoint.y + t * dy
        guard y >= displayFrame.minY && y <= displayFrame.lastValidMaxY else {
            return
        }
        crossings.append(SegmentCrossing(
            t: t,
            axis: .horizontal,
            exit: PointerPortalExit(edge: edge, position: normalized(y, start: displayFrame.minY, length: displayFrame.height))
        ))
    }

    private func appendHorizontalCrossing(
        edge: PointerPortalEdge,
        boundaryY: CGFloat,
        previousPoint: CGPoint,
        dx: CGFloat,
        dy: CGFloat,
        to crossings: inout [SegmentCrossing]
    ) {
        let t = (boundaryY - previousPoint.y) / dy
        let x = previousPoint.x + t * dx
        guard x >= displayFrame.minX && x <= displayFrame.lastValidMaxX else {
            return
        }
        crossings.append(SegmentCrossing(
            t: t,
            axis: .vertical,
            exit: PointerPortalExit(edge: edge, position: normalized(x, start: displayFrame.minX, length: displayFrame.width))
        ))
    }

    private func horizontalExit(at point: CGPoint, delta: CGVector) -> PointerPortalExit? {
        if point.x <= displayFrame.minX + 1, delta.dx < 0 {
            return PointerPortalExit(edge: .left, position: normalized(point.y, start: displayFrame.minY, length: displayFrame.height))
        }

        if point.x >= displayFrame.lastValidMaxX, delta.dx > 0 {
            return PointerPortalExit(edge: .right, position: normalized(point.y, start: displayFrame.minY, length: displayFrame.height))
        }

        return nil
    }

    private func verticalExit(at point: CGPoint, delta: CGVector) -> PointerPortalExit? {
        if point.y <= displayFrame.minY + 1, delta.dy < 0 {
            return PointerPortalExit(edge: .top, position: normalized(point.x, start: displayFrame.minX, length: displayFrame.width))
        }

        if point.y >= displayFrame.lastValidMaxY, delta.dy > 0 {
            return PointerPortalExit(edge: .bottom, position: normalized(point.x, start: displayFrame.minX, length: displayFrame.width))
        }

        return nil
    }

    private func preferredAxis(for delta: CGVector) -> MovementAxis {
        let horizontal = abs(delta.dx)
        let vertical = abs(delta.dy)
        if horizontal > vertical {
            return .horizontal
        }
        if vertical > horizontal {
            return .vertical
        }
        return lastMovementAxis ?? .horizontal
    }

    private func isOutward(_ edge: PointerPortalEdge, delta: CGVector) -> Bool {
        switch edge {
        case .left:
            return delta.dx < 0
        case .right:
            return delta.dx > 0
        case .top:
            return delta.dy < 0
        case .bottom:
            return delta.dy > 0
        }
    }

    private func normalized(_ value: CGFloat, start: CGFloat, length: CGFloat) -> CGFloat {
        min(max((value - start) / length, 0), 1)
    }

    private mutating func track(_ button: PointerButton) {
        guard !pressedButtons.contains(button) else {
            return
        }
        pressedButtons.append(button)
    }

    private mutating func untrack(_ button: PointerButton) {
        pressedButtons.removeAll { $0 == button }
    }
}

private enum MovementAxis: Sendable {
    case horizontal
    case vertical
}

private struct SegmentCrossing: Sendable {
    let t: CGFloat
    let axis: MovementAxis
    let exit: PointerPortalExit
}

private extension CGRect {
    var isValidPointerDisplayFrame: Bool {
        origin.x.isFinite &&
            origin.y.isFinite &&
            size.width.isFinite &&
            size.height.isFinite &&
            !isNull &&
            !isEmpty &&
            size.width > 0 &&
            size.height > 0
    }

    var lastValidCenter: CGPoint {
        CGPoint(x: (minX + lastValidMaxX) / 2, y: (minY + lastValidMaxY) / 2)
    }

    var lastValidMaxX: CGFloat {
        width > 0 ? max(minX, maxX - 1) : minX
    }

    var lastValidMaxY: CGFloat {
        height > 0 ? max(minY, maxY - 1) : minY
    }

    func containsLastValid(_ point: CGPoint) -> Bool {
        point.isFinitePointerPoint &&
            point.x >= minX &&
            point.x <= lastValidMaxX &&
            point.y >= minY &&
            point.y <= lastValidMaxY
    }
}

private extension CGPoint {
    var isFinitePointerPoint: Bool {
        x.isFinite && y.isFinite
    }

    func clampedToLastValidPoint(in rect: CGRect) -> CGPoint {
        CGPoint(
            x: min(max(x, rect.minX), rect.lastValidMaxX),
            y: min(max(y, rect.minY), rect.lastValidMaxY)
        )
    }
}

private extension CGVector {
    var isFinitePointerDelta: Bool {
        dx.isFinite && dy.isFinite
    }
}
