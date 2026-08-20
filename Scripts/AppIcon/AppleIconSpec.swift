import Foundation

/// Apple app-icon sizing literals from Human Interface Guidelines + Design Resources.
enum AppleIconSpec {
    static let masterPixels = 1024
    static let keylinePixels = 824
    static let keylineRatio = Double(keylinePixels) / Double(masterPixels)
    static let keylineTolerance = 0.015
    static let continuousCornerFraction = 0.2237
    static let macSizes: [(name: String, pixels: Int)] = [
        ("icon_16x16.png", 16),
        ("icon_16x16_2x.png", 32),
        ("icon_32x32.png", 32),
        ("icon_32x32_2x.png", 64),
        ("icon_128x128.png", 128),
        ("icon_128x128_2x.png", 256),
        ("icon_256x256.png", 256),
        ("icon_256x256_2x.png", 512),
        ("icon_512x512.png", 512),
        ("icon_512x512_2x.png", 1024),
    ]
}
