import Cocoa

/// The human character's `CharacterArt`. Its body is rendered from full-colour
/// illustration frames (see `HumanImageArt`), NOT pixel grids — so the grid
/// fields here are blank placeholders that are never drawn. What this struct
/// still provides is the **logical sprite size** (45×64 cells ≈ the frame
/// canvas aspect, so the dock-fit sizing math works) and a **palette** carrying
/// the shared props (prey/meat/dazed stars/impact dust) that ARE drawn as grids
/// around the image.
enum HumanPixelArt {
    static let width = 45
    static let height = 64

    private static let blank = [String](repeating: String(repeating: ".", count: width),
                                        count: height)

    static let art = CharacterArt(
        width: width, height: height,
        stand: blank, walkB: blank, walkC: blank, blink: blank,
        held: blank, tumble: [blank], impact: blank, hurt: blank, dazed: blank, getUp: blank,
        palette: CharacterArt.palette([:])   // shared props only; the body is an image
    )
}
