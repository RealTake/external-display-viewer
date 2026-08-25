import CoreGraphics

public enum PointerButton: CaseIterable, Equatable, Sendable {
    case left
    case right
    case middle
}

public enum PointerEvent {
    public enum Kind: Equatable, Hashable, Sendable {
        case warp
        case mouseDown
        case mouseDragged
        case mouseUp
        case scroll
    }
}
