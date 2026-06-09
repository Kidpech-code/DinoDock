import Foundation

/// Which pet walks the Dock. Persisted across launches.
///
/// (Named `PetKind`, not `Character`, to avoid shadowing Swift's own
/// `Character` type — which is the key type of the art palettes.)
enum PetKind: String, CaseIterable {
    case dino
    case human

    private static let defaultsKey = "DinoDock.character"

    /// The user's saved choice, defaulting to the dino.
    static var saved: PetKind {
        get {
            guard let raw = UserDefaults.standard.string(forKey: defaultsKey),
                  let kind = PetKind(rawValue: raw) else { return .dino }
            return kind
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: defaultsKey) }
    }

    /// Human-readable label for the menu.
    var title: String {
        switch self {
        case .dino:  return "Dino (T-rex)"
        case .human: return "Human (chibi)"
        }
    }

    /// The pixel-art set for this character.
    var art: CharacterArt {
        switch self {
        case .dino:  return DinoPixelArt.art
        case .human: return HumanPixelArt.art
        }
    }
}
