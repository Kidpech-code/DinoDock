import Cocoa

/// Pixel-art dinosaur — an orange 8-bit T-rex traced from a 44×44 reference —
/// plus the prey it chases and the meat it eats.
///
/// Legend — dino: '.' clear   'o' orange       'O' light orange   'r' red
///                'd' dark-red outline   'y' yellow belly   'g' green patch
///                'b' blue (eye / feet)  'k' black (pupil / nostril)  'w' eye-white
///          prey: 'c' outline  'C' purple body  ('w'/'k' for its eye)
///          meat: 'm' edge     'M' meat         'B' bone
///
/// Faces RIGHT; PetView mirrors it to walk left. The walk gait cycles
/// [walkB, stand, walkC, stand] — lifting the back foot, passing, then the
/// front foot — so both feet step. `blink` shuts the eye.
enum DinoPixelArt {
    static let width = 44
    static let height = 44

    static let stand: [String] = [
        ".............................rrrr..rrrO.....",
        "...........................rroooorrroorO....",
        "..........................OrrooooooooorO....",
        ".........................OroorrrryyyoorO....",
        ".........................OrorbbrdroyyorrOO..",
        "........................OorobbbgkbooOyOrrrO.",
        ".......................OoooobbbkkbooooOyyyrO",
        ".......................ooooorbbbbooooodkoyyr",
        ".......................oooooooooooooooodkood",
        ".......................roooooOOOoooooooooood",
        ".......................rddoOOOOOrooooooooood",
        "........................ddooOOOOyrrrrrrrrrrr",
        "........................rdoooOOOOOyyyyyyyyO.",
        ".........................rddooooooooOOOOOy..",
        ".........................rddoooooOOO........",
        "...........................doooooOO.........",
        "...........................doooooOO.........",
        "...........................doooooyO.........",
        "..........................roooooOyO.........",
        ".......................rrrooooooyyO.........",
        "r...................rrrooooyooooyyO.........",
        "rOy..............rrroooooooyooooyyO.........",
        "rOy.............rroooOOoyyooooooyyo.........",
        "rOOr............rroooyyoooooooryygd.........",
        "dOOr...........rrooyyoooooorooryggd.........",
        "dooor.........rroyoooooooooroorgggddO.......",
        "dooor.........rOyorrrroooooroorgggoooO......",
        ".door........rOOoooyyyroooooroorrgddodg.....",
        ".doooo.......rOOOyyyyyyroooodooood.dodg.....",
        ".dooOyo.....roOoOOyyyyyrorrrgdoood..rdg.....",
        "..doOyyr...roOOoOOyyyyyyrdyygggdod..rO......",
        "..gdoooorrroOOOoOOOOyyyyryyygggddd..........",
        "...doooooooOOOooOOOOyyyyrgggggg.d...........",
        "...ddoooooOOOooooOOOyyyyrgggggg.............",
        "....ddoooooooddggddOOyyyrgggggr.............",
        ".....ddooodddgggggdOOyyrgggddor.............",
        "......ddOgggggggggdOyyyrdddooor.............",
        ".......ddgggggddddoOyyrOdddood..............",
        ".........dddddO..doOyrOOdoood...............",
        "...........OOO...doOOrOOdoood...............",
        ".................doOOOoooooodrr.............",
        ".................doooooobbooooobr...........",
        ".................doooooobbboooobrb..........",
        ".................dddddddbbbddddbbb..........",
    ]

    static let walkB: [String] = [
        ".............................rrrr..rrrO.....",
        "...........................rroooorrroorO....",
        "..........................OrrooooooooorO....",
        ".........................OroorrrryyyoorO....",
        ".........................OrorbbrdroyyorrOO..",
        "........................OorobbbgkbooOyOrrrO.",
        ".......................OoooobbbkkbooooOyyyrO",
        ".......................ooooorbbbbooooodkoyyr",
        ".......................oooooooooooooooodkood",
        ".......................roooooOOOoooooooooood",
        ".......................rddoOOOOOrooooooooood",
        "........................ddooOOOOyrrrrrrrrrrr",
        "........................rdoooOOOOOyyyyyyyyO.",
        ".........................rddooooooooOOOOOy..",
        ".........................rddoooooOOO........",
        "...........................doooooOO.........",
        "...........................doooooOO.........",
        "...........................doooooyO.........",
        "..........................roooooOyO.........",
        ".......................rrrooooooyyO.........",
        "r...................rrrooooyooooyyO.........",
        "rOy..............rrroooooooyooooyyO.........",
        "rOy.............rroooOOoyyooooooyyo.........",
        "rOOr............rroooyyoooooooryygd.........",
        "dOOr...........rrooyyoooooorooryggd.........",
        "dooor.........rroyoooooooooroorgggddO.......",
        "dooor.........rOyorrrroooooroorgggoooO......",
        ".door........rOOoooyyyroooooroorrgddodg.....",
        ".doooo.......rOOOyyyyyyroooodooood.dodg.....",
        ".dooOyo.....roOoOOyyyyyrorrrgdoood..rdg.....",
        "..doOyyr...roOOoOOyyyyyyrdyygggdod..rO......",
        "..gdoooorrroOOOoOOOOyyyyryyygggddd..........",
        "...doooooooOOOooOOOOyyyyrgggggg.d...........",
        "...ddoooooOOOooooOOOyyyyrgggggg.............",
        "....ddoooooooddggddOOyyyrgggggr.............",
        ".....ddooodddgggggdOOyyrgggddor.............",
        "......ddOgggggggggdOyyyrdddooor.............",
        ".......ddgggggddddoOyyrOdddood..............",
        ".........dddddO..doOyrOoooooo...............",
        "...........OOO...doOOrOoobboo...............",
        ".................doOOO.oobbborr.............",
        ".................doooo.ddbbbdoobr...........",
        ".................doooo......ooobrb..........",
        ".................ddddd......dddbbb..........",
    ]

    static let walkC: [String] = [
        ".............................rrrr..rrrO.....",
        "...........................rroooorrroorO....",
        "..........................OrrooooooooorO....",
        ".........................OroorrrryyyoorO....",
        ".........................OrorbbrdroyyorrOO..",
        "........................OorobbbgkbooOyOrrrO.",
        ".......................OoooobbbkkbooooOyyyrO",
        ".......................ooooorbbbbooooodkoyyr",
        ".......................oooooooooooooooodkood",
        ".......................roooooOOOoooooooooood",
        ".......................rddoOOOOOrooooooooood",
        "........................ddooOOOOyrrrrrrrrrrr",
        "........................rdoooOOOOOyyyyyyyyO.",
        ".........................rddooooooooOOOOOy..",
        ".........................rddoooooOOO........",
        "...........................doooooOO.........",
        "...........................doooooOO.........",
        "...........................doooooyO.........",
        "..........................roooooOyO.........",
        ".......................rrrooooooyyO.........",
        "r...................rrrooooyooooyyO.........",
        "rOy..............rrroooooooyooooyyO.........",
        "rOy.............rroooOOoyyooooooyyo.........",
        "rOOr............rroooyyoooooooryygd.........",
        "dOOr...........rrooyyoooooorooryggd.........",
        "dooor.........rroyoooooooooroorgggddO.......",
        "dooor.........rOyorrrroooooroorgggoooO......",
        ".door........rOOoooyyyroooooroorrgddodg.....",
        ".doooo.......rOOOyyyyyyroooodooood.dodg.....",
        ".dooOyo.....roOoOOyyyyyrorrrgdoood..rdg.....",
        "..doOyyr...roOOoOOyyyyyyrdyygggdod..rO......",
        "..gdoooorrroOOOoOOOOyyyyryyygggddd..........",
        "...doooooooOOOooOOOOyyyyrgggggg.d...........",
        "...ddoooooOOOooooOOOyyyyrgggggg.............",
        "....ddoooooooddggddOOyyyrgggggr.............",
        ".....ddooodddgggggdOOyyrgggddor.............",
        "......ddOgggggggggdOyyyrdddooor.............",
        ".......ddgggggddddoOyyrOdddood..............",
        ".........dddddO..doOyrOOdoood.rr............",
        "...........OOO...doOOrOOdoood.oobr..........",
        ".................doOOOooooood.oobrb.........",
        ".................doooooobbooo.ddbbb.........",
        ".................doooooobbboo...............",
        ".................dddddddbbbdd...............",
    ]

    static let blink: [String] = [
        ".............................rrrr..rrrO.....",
        "...........................rroooorrroorO....",
        "..........................OrrooooooooorO....",
        ".........................OroorrrryyyoorO....",
        ".........................OroroordroyyorrOO..",
        "........................OorddddddddoOyOrrrO.",
        ".......................OooooooooooooooOyyyrO",
        ".......................ooooorooooooooodkoyyr",
        ".......................oooooooooooooooodkood",
        ".......................roooooOOOoooooooooood",
        ".......................rddoOOOOOrooooooooood",
        "........................ddooOOOOyrrrrrrrrrrr",
        "........................rdoooOOOOOyyyyyyyyO.",
        ".........................rddooooooooOOOOOy..",
        ".........................rddoooooOOO........",
        "...........................doooooOO.........",
        "...........................doooooOO.........",
        "...........................doooooyO.........",
        "..........................roooooOyO.........",
        ".......................rrrooooooyyO.........",
        "r...................rrrooooyooooyyO.........",
        "rOy..............rrroooooooyooooyyO.........",
        "rOy.............rroooOOoyyooooooyyo.........",
        "rOOr............rroooyyoooooooryygd.........",
        "dOOr...........rrooyyoooooorooryggd.........",
        "dooor.........rroyoooooooooroorgggddO.......",
        "dooor.........rOyorrrroooooroorgggoooO......",
        ".door........rOOoooyyyroooooroorrgddodg.....",
        ".doooo.......rOOOyyyyyyroooodooood.dodg.....",
        ".dooOyo.....roOoOOyyyyyrorrrgdoood..rdg.....",
        "..doOyyr...roOOoOOyyyyyyrdyygggdod..rO......",
        "..gdoooorrroOOOoOOOOyyyyryyygggddd..........",
        "...doooooooOOOooOOOOyyyyrgggggg.d...........",
        "...ddoooooOOOooooOOOyyyyrgggggg.............",
        "....ddoooooooddggddOOyyyrgggggr.............",
        ".....ddooodddgggggdOOyyrgggddor.............",
        "......ddOgggggggggdOyyyrdddooor.............",
        ".......ddgggggddddoOyyrOdddood..............",
        ".........dddddO..doOyrOOdoood...............",
        "...........OOO...doOOrOOdoood...............",
        ".................doOOOoooooodrr.............",
        ".................doooooobbooooobr...........",
        ".................doooooobbboooobrb..........",
        ".................dddddddbbbddddbbb..........",
    ]

    // MARK: - Props

    static let prey: [String] = [
        "...........",
        "......ccc..",
        "....ccCCCc.",
        "...cCCCCwkc",
        "...cCCCCCCc",
        "...cCCCCCc.",
        "....c.cc.c.",
        "...........",
    ]

    static let meat: [String] = [
        "..mmmm..",
        ".mMMMMm.",
        ".mMMMMm.",
        ".mMMMMm.",
        "..mmm...",
        "...BB...",
        "....BB..",
    ]

    // MARK: - Character art

    /// The dino's body colours (the shared prop colours — prey, meat, eye-white,
    /// black, dazed stars, dust — are merged in via `CharacterArt.palette`).
    static let bodyPalette: [Character: NSColor] = [
        "o": NSColor(srgbRed: 0.910, green: 0.392, blue: 0.165, alpha: 1), // orange body
        "O": NSColor(srgbRed: 0.969, green: 0.569, blue: 0.110, alpha: 1), // light orange
        "r": NSColor(srgbRed: 0.820, green: 0.318, blue: 0.282, alpha: 1), // red
        "d": NSColor(srgbRed: 0.659, green: 0.208, blue: 0.098, alpha: 1), // dark-red outline
        "y": NSColor(srgbRed: 0.980, green: 0.784, blue: 0.216, alpha: 1), // yellow belly
        "g": NSColor(srgbRed: 0.592, green: 0.671, blue: 0.271, alpha: 1), // green patch
        "b": NSColor(srgbRed: 0.176, green: 0.424, blue: 0.620, alpha: 1), // blue eye / feet
    ]

    /// The dino as a `CharacterArt`. It has no bespoke throw poses yet, so the
    /// grab-and-throw feature reuses `stand` (held / get-up / tumble) and
    /// `blink` (the woozy impact / hurt / dazed frames) — still fully throwable.
    static let art = CharacterArt(
        width: width,
        height: height,
        stand: stand,
        walkB: walkB,
        walkC: walkC,
        blink: blink,
        held: stand,
        tumble: [stand],
        impact: blink,
        hurt: blink,
        dazed: blink,
        getUp: stand,
        palette: CharacterArt.palette(bodyPalette)
    )
}
