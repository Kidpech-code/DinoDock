import Foundation

/// Where the dinosaur is allowed to walk. Persisted across launches.
enum WalkMode: String, CaseIterable {
    /// Confined to the visible Dock panel (centred rounded rectangle).
    case dock
    /// Across the full usable width of the screen, edge to edge.
    case fullScreen

    private static let defaultsKey = "DinoDock.walkMode"

    /// The user's saved preference, defaulting to `.dock`.
    static var saved: WalkMode {
        get {
            guard let raw = UserDefaults.standard.string(forKey: defaultsKey),
                  let mode = WalkMode(rawValue: raw) else { return .dock }
            return mode
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: defaultsKey) }
    }

    /// Human-readable label for the menu.
    var title: String {
        switch self {
        case .dock:       return "On the Dock"
        case .fullScreen: return "Full screen width"
        }
    }
}
