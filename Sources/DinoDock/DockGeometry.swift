import Cocoa
import ApplicationServices

/// The horizontal strip and ground line where the pet walks, in AppKit
/// (bottom-left origin) global screen coordinates.
struct DockBand: Equatable {
    let groundY: CGFloat   // window bottom — the pet's feet rest here
    let minX: CGFloat      // left limit
    let maxX: CGFloat      // right limit
    let thickness: CGFloat // Dock depth, used to size the sprite

    var width: CGFloat { max(0, maxX - minX) }
}

/// Works out where the Dock is so the pet can walk on or around it.
///
/// Horizontal extent comes from the Accessibility API when permission has been
/// granted (exact, and adapts as the Dock grows/shrinks), otherwise from an
/// estimate derived from the Dock's own preferences. The vertical ground line
/// always comes from the screen's reserved Dock band, which is stable and
/// independent of Dock magnification.
enum DockGeometry {

    /// Resolves the walk band for `mode` on the screen that hosts the Dock.
    static func band(for mode: WalkMode) -> DockBand {
        guard let screen = dockScreen() else {
            return DockBand(groundY: 0, minX: 0, maxX: 0, thickness: 0)
        }

        let full = screen.frame
        let visible = screen.visibleFrame
        let bottomGap = visible.minY - full.minY
        let leftGap   = visible.minX - full.minX
        let rightGap  = full.maxX - visible.maxX
        let orientation = dockOrientation()

        // Dock depth — used only to scale the sprite.
        var thickness = bottomGap
        if orientation == "left" || orientation == "right" {
            thickness = max(leftGap, rightGap)
        }
        if thickness < 8 { thickness = defaultTileSize() } // auto-hidden fallback

        // Ground line: the visible *top* of the *resting* Dock panel — the pet
        // perches on this rim, body fully above it. With magnification off (or a
        // no-op `largesize`), the screen's reserved Dock band equals the resting
        // panel exactly, so use it as-is. Only *real* magnification inflates the
        // band to fit the popped icons; in that case fall back to a resting-size
        // estimate so the pet stays on the resting rim instead of riding the
        // bouncing icons. Falls back to the screen bottom when there is no Dock.
        let tile = defaultTileSize()
        let largeSize = CGFloat(dockDefaults?.double(forKey: "largesize") ?? 0)
        let magnifies = (dockDefaults?.bool(forKey: "magnification") ?? false) && largeSize > tile + 1
        let restingHeight = tile + 22                       // panel ≈ tile + padding
        let panelHeight = magnifies ? min(bottomGap, restingHeight) : bottomGap
        let panelTop = full.minY + panelHeight
        let ground = bottomGap > 8 ? panelTop : full.minY

        // Full-screen mode: walk the whole usable width.
        if mode == .fullScreen {
            return DockBand(groundY: ground, minX: visible.minX, maxX: visible.maxX, thickness: thickness)
        }

        // Dock mode: confine horizontally to the Dock panel.
        if orientation == "bottom" {
            if let exact = dockListBounds(on: screen) {
                return DockBand(groundY: ground, minX: exact.minX, maxX: exact.maxX, thickness: thickness)
            }
            if let estimate = estimatedBottomDockWidth() {
                let inset = (visible.width - estimate) / 2
                return DockBand(groundY: ground,
                                minX: visible.minX + max(0, inset),
                                maxX: visible.maxX - max(0, inset),
                                thickness: thickness)
            }
        }
        // Side / auto-hidden Dock, or unknown layout: use the usable width.
        return DockBand(groundY: ground, minX: visible.minX, maxX: visible.maxX, thickness: thickness)
    }

    // MARK: - Dock preferences

    private static var dockDefaults: UserDefaults? {
        UserDefaults(suiteName: "com.apple.dock")
    }

    static func dockOrientation() -> String {
        dockDefaults?.string(forKey: "orientation") ?? "bottom"
    }

    static func defaultTileSize() -> CGFloat {
        let size = dockDefaults?.double(forKey: "tilesize") ?? 48
        return CGFloat(size > 0 ? size : 48)
    }

    /// The screen whose bottom edge currently holds the Dock (the one with a
    /// menu bar / where the Dock lives). Falls back to the main screen.
    private static func dockScreen() -> NSScreen? {
        NSScreen.main ?? NSScreen.screens.first
    }

    /// Estimated width (points) of a resting, centred bottom Dock, derived from
    /// the Dock's preferences. Used when the exact AX rectangle is unavailable.
    static func estimatedBottomDockWidth() -> CGFloat? {
        guard let d = dockDefaults else { return nil }
        let tile    = defaultTileSize()
        let apps    = d.array(forKey: "persistent-apps")?.count   ?? 0
        let others  = d.array(forKey: "persistent-others")?.count ?? 0
        let recents = d.array(forKey: "recent-apps")?.count       ?? 0

        // Finder (left) and Trash (right) are always present.
        let tiles = apps + others + recents + 2
        guard tiles > 0 else { return nil }

        let pitch = tile * 1.2                              // tile + inter-tile gap
        let separator = (others + recents > 0) ? pitch * 0.45 : 0
        return CGFloat(tiles) * pitch + separator + tile    // + end padding
    }

    // MARK: - Accessibility (exact Dock rectangle)

    /// Whether the app currently has Accessibility permission.
    static var hasAccessibilityPermission: Bool { AXIsProcessTrusted() }

    /// Requests Accessibility permission, showing the system prompt if needed.
    @discardableResult
    static func requestAccessibilityPermission() -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        return AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    /// The Dock item panel's rectangle (AppKit coordinates), restricted to the
    /// given screen, or `nil` if it cannot be read (e.g. no permission).
    static func dockListBounds(on screen: NSScreen) -> NSRect? {
        guard hasAccessibilityPermission,
              let dockApp = NSRunningApplication
                .runningApplications(withBundleIdentifier: "com.apple.dock")
                .first
        else { return nil }

        let axApp = AXUIElementCreateApplication(dockApp.processIdentifier)

        var childrenRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXChildrenAttribute as CFString, &childrenRef) == .success,
              let children = childrenRef as? [AXUIElement]
        else { return nil }

        // The Dock's items live in an AXList child element.
        guard let list = children.first(where: { axRole($0) == (kAXListRole as String) }) else { return nil }

        guard let point = axPoint(list, kAXPositionAttribute),
              let size  = axSize(list, kAXSizeAttribute),
              size.width > 8, size.height > 8
        else { return nil }

        // AX uses a top-left origin (y grows downward); AppKit uses bottom-left.
        // Flip against the primary screen (anchored at the global origin).
        guard let primary = NSScreen.screens.first else { return nil }
        let cocoaY = primary.frame.maxY - point.y - size.height
        let rect = NSRect(x: point.x, y: cocoaY, width: size.width, height: size.height)

        // Sanity-check it overlaps the target screen.
        return rect.intersects(screen.frame) ? rect : nil
    }

    // MARK: - AX value helpers

    private static func axRole(_ element: AXUIElement) -> String? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &ref) == .success
        else { return nil }
        return ref as? String
    }

    private static func axPoint(_ element: AXUIElement, _ attr: String) -> CGPoint? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attr as CFString, &ref) == .success,
              let value = ref, CFGetTypeID(value) == AXValueGetTypeID()
        else { return nil }
        var point = CGPoint.zero
        return AXValueGetValue(value as! AXValue, .cgPoint, &point) ? point : nil
    }

    private static func axSize(_ element: AXUIElement, _ attr: String) -> CGSize? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attr as CFString, &ref) == .success,
              let value = ref, CFGetTypeID(value) == AXValueGetTypeID()
        else { return nil }
        var size = CGSize.zero
        return AXValueGetValue(value as! AXValue, .cgSize, &size) ? size : nil
    }
}
