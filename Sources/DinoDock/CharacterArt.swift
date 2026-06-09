import Cocoa

/// Immutable pixel-art data for one pet character: the standing / walking /
/// blinking frames the behaviour engine cycles through, the extra poses the
/// grab-and-throw feature plays, and the colour palette its grid chars map to.
///
/// It's a value type (not a protocol) so `PetController` can hold the current
/// character as a plain stored property and switching is just a reassignment.
/// `DinoPixelArt.art` and `HumanPixelArt.art` are the two instances.
struct CharacterArt {
    let width: Int
    let height: Int

    // Core gait / idle frames (every frame must be `height` rows × `width` cols).
    let stand: [String]
    let walkB: [String]   // back foot lifted
    let walkC: [String]   // front foot lifted
    let blink: [String]   // eyes shut

    // Grab-and-throw poses. Characters without bespoke art reuse simpler frames
    // (e.g. the dino points `held`/`getUp` at `stand` and the woozy frames at
    // `blink`), so every character is throwable even before it has custom poses.
    let held: [String]        // dangling from the cursor
    let tumble: [[String]]    // airborne flail loop (1+ frames)
    let impact: [String]      // squashed on landing
    let hurt: [String]        // sitting, clutching the bump
    let dazed: [String]       // sitting, woozy (paired with the spinning stars)
    let getUp: [String]       // pushing back up to its feet

    let palette: [Character: NSColor]

    /// Colours shared by every character: the chase prey, the eaten meat, and
    /// the throw effect props (spinning stars, impact dust). Merged into each
    /// character's palette so a human can chase prey and a dino can be dazed.
    static let sharedProps: [Character: NSColor] = [
        "C": NSColor(srgbRed: 0.588, green: 0.353, blue: 0.784, alpha: 1), // prey body (purple)
        "c": NSColor(srgbRed: 0.353, green: 0.196, blue: 0.510, alpha: 1), // prey outline
        "M": NSColor(srgbRed: 0.784, green: 0.220, blue: 0.239, alpha: 1), // meat
        "m": NSColor(srgbRed: 0.549, green: 0.129, blue: 0.149, alpha: 1), // meat edge
        "B": NSColor(srgbRed: 0.941, green: 0.910, blue: 0.831, alpha: 1), // bone
        "w": NSColor(srgbRed: 0.973, green: 0.973, blue: 0.973, alpha: 1), // eye-white / shine
        "k": NSColor(srgbRed: 0.098, green: 0.098, blue: 0.098, alpha: 1), // black (pupil / nostril)
        "T": NSColor(srgbRed: 1.000, green: 0.851, blue: 0.255, alpha: 1), // dazed star (bright)
        "t": NSColor(srgbRed: 0.901, green: 0.651, blue: 0.106, alpha: 1), // dazed star (gold edge)
        "u": NSColor(srgbRed: 0.855, green: 0.824, blue: 0.780, alpha: 1), // impact dust puff
    ]

    /// Convenience: a character's own colours merged with the shared props.
    static func palette(_ body: [Character: NSColor]) -> [Character: NSColor] {
        body.merging(sharedProps) { own, _ in own }
    }
}
