import Cocoa

/// The human character drawn from pre-normalized illustration frames in
/// `Contents/Resources/women/` (built offline by the PIL pipeline: split the
/// 4-frame walk sheets, key out their white background, crop, height-normalize
/// so the character is one consistent size, and bottom-align the feet on a
/// shared baseline). Walk and idle have explicit LEFT/RIGHT sets (so the hair
/// and stride face the travel direction without mirroring); the throw poses are
/// single frames the controller flips by facing.
enum HumanImageArt {
    // Side-profile idle (subtle 3-frame breathing), one set per facing.
    static let idleRight = [img("human_idleR1"), img("human_idleR2"), img("human_idleR3")]
    static let idleLeft  = [img("human_idleL1"), img("human_idleL2"), img("human_idleL3")]

    // 4-frame walk cycle, one set per facing.
    static let walkRight = [img("human_walkR1"), img("human_walkR2"), img("human_walkR3"), img("human_walkR4")]
    static let walkLeft  = [img("human_walkL1"), img("human_walkL2"), img("human_walkL3"), img("human_walkL4")]

    // Throw reaction poses (canonical right; flipped per facing when needed).
    static let held   = img("human_held")
    static let tumble = [img("human_tumble1"), img("human_tumble2"), img("human_tumble3")]
    static let impact = img("human_impact")
    static let hurt   = img("human_hurt")
    static let dazed  = [img("human_dazed1"), img("human_dazed2"), img("human_dazed3")]
    static let getUp  = img("human_getup")

    private static func img(_ name: String) -> NSImage {
        if let url = Bundle.main.url(forResource: name, withExtension: "png", subdirectory: "women"),
           let image = NSImage(contentsOf: url) {
            return image
        }
        NSLog("DinoDock: missing human frame \(name).png in Resources/women")
        return NSImage(size: NSSize(width: 1, height: 1))
    }
}
