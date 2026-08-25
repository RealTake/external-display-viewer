import CoreGraphics

public struct DisplayInfo: Equatable, Identifiable, Sendable {
    public let id: CGDirectDisplayID
    public let name: String
    public let coreGraphicsFrame: CGRect
    public let appKitFrame: CGRect
    public let pixelSize: CGSize
    public let scale: CGFloat
    public let isBuiltIn: Bool

    public init(
        id: CGDirectDisplayID,
        name: String,
        coreGraphicsFrame: CGRect,
        appKitFrame: CGRect,
        pixelSize: CGSize,
        scale: CGFloat,
        isBuiltIn: Bool
    ) {
        self.id = id
        self.name = name
        self.coreGraphicsFrame = coreGraphicsFrame
        self.appKitFrame = appKitFrame
        self.pixelSize = pixelSize
        self.scale = scale
        self.isBuiltIn = isBuiltIn
    }

    public var menuLabel: String {
        "\(name) · \(Int(pixelSize.width))×\(Int(pixelSize.height))"
    }
}
