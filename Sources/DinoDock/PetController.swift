import Cocoa
import ApplicationServices

/// Owns the floating, click-through window that sits above the Dock and brings
/// the dinosaur to life: it walks, runs, pauses, looks around, hops, naps,
/// hunts down prey and eats, occasionally muses a quote — and, when enabled,
/// echoes your keystrokes in a speech bubble.
final class PetController: NSObject {

    // UI
    private var window: NSWindow?
    private var petView: PetView?
    private var statusItem: NSStatusItem?
    private var timer: Timer?
    private let keyboard = KeyboardWatcher()

    // Which character is active, and its art set.
    private var petKind: PetKind = .saved
    private var current: CharacterArt { petKind.art }
    /// The human's idle frame for this tick (slow 3-frame breathing), facing the
    /// travel direction so it matches the explicit left/right walk frames.
    private func humanIdle(_ facingRight: Bool) -> NSImage {
        let f = facingRight ? HumanImageArt.idleRight : HumanImageArt.idleLeft
        return f[(tick / max(1, Int(Self.fps * 0.7))) % f.count]
    }

    // Walk band / position
    private var mode: WalkMode = .saved
    private var band = DockBand(groundY: 0, minX: 0, maxX: 0, thickness: 0)
    private var posX: CGFloat = 0
    private var posY: CGFloat = 0         // height above the floor (0 = on the Dock); driven by throws
    private var walkMinX: CGFloat = 0     // walk range within the window (see clampWalkX)
    private var walkMaxX: CGFloat = 0
    private var staged = false            // window grown to the full-screen throw stage
    private var lastSpriteRect: NSRect = .zero  // for dirty-rect redraws while staged
    private var direction: CGFloat = 1   // +1 faces right, -1 faces left

    // Grab & throw
    private var grabEnabled = (UserDefaults.standard.object(forKey: "DinoDock.catchThrow") as? Bool) ?? true
    private var vx: CGFloat = 0           // throw velocity, points/tick
    private var vy: CGFloat = 0
    private var grabDX: CGFloat = 0       // cursor offset from the sprite origin while held
    private var grabDY: CGFloat = 0
    private var recoverCounter = 0        // sequences the impact→hurt→dazed→getUp poses
    private var throwTicks = 0            // airborne watchdog
    private var pendingRebuild = false    // a Dock/size/character change deferred until the pet settles
    private var mouseMonitor: Any?        // global cursor probe that toggles click-through
    private var heartsCountdown = 0       // shows a brief ♥ after a poke
    private var tick = 0

    // Behaviour state machine
    private enum Behavior { case walk, run, idle, look, hop, sleep, chase, eat, speak,
                                 held, flying, recovering }
    private var behavior: Behavior = .walk
    /// True while the pet is grabbed, airborne, or recovering from a throw —
    /// during which normal behaviour, props, and Dock rebuilds are suspended.
    private var interacting: Bool { behavior == .held || behavior == .flying || behavior == .recovering }
    private var behaviorTicks = 0        // ticks left in the current behaviour
    private var walkPhase = 0            // 0..3 gait cycle: stepBack, pass, stepFront, pass
    private var animCounter = 0
    private var blinkCountdown = 0       // ticks until the next blink
    private var blinkHold = 0            // ticks the eyes stay shut
    private var lookCountdown = 0        // ticks until the next head turn
    private var hopTotal = 0             // ticks the whole hop sequence lasts
    private var eatCounter = 0           // chomp animation counter
    private var forceEat = false         // a successful chase forces eating next

    // Prey / food props
    private var preyActive = false
    private var preyX: CGFloat = 0
    private var preyFacing = false
    private var foodActive = false
    private var currentQuote = ""

    // Keyboard reaction
    private var reactsToKeys = KeyboardPrefs.enabled
    private var typedBuffer = ""
    private var typingCountdown = 0      // ticks until the bubble fades
    private var mouthCounter = 0
    private var keyMonitorArmed = false  // monitor created while fully permitted

    // Tuning. The engine runs at a high frame rate for smooth motion (especially
    // a thrown pet flying across the screen); per-tick speeds were tuned at 12
    // fps, so multiplying them by `dt = 12/fps` keeps the *feel* identical while
    // the motion gets finer. Durations expressed as `x * fps` already scale.
    private static let fps = 30.0
    private static let dt = CGFloat(12.0 / fps)  // per-tick scale relative to the original 12 fps
    private static let refreshTicks = Int(fps)   // re-read the Dock ~once a second
    private static let hopLen = Int(fps * 1.3)   // ticks per single hop arc
    private static let maxTyped = 18             // characters kept in the bubble
    private static let typingHold = Int(1.6 * fps)
    private static let animDiv = max(1, Int(3.0 / dt))      // small-anim tick divisor (chomp/nod) ≈3 @12fps
    private static let blinkHoldTicks = max(1, Int(2.0 / dt))
    private static let walkStride = max(1, Int(3.0 / dt))   // ticks per gait phase, walk (dino grid)
    private static let runStride = max(1, Int(2.0 / dt))    // ticks per gait phase, run/chase
    private static let walkFrameDiv = max(1, Int(fps * 0.5)) // ticks per human walk-frame swap (full 4-frame cycle ≈2.0s — slow, calm legs)

    // Throw physics. Per-tick values scaled from a 12-fps tuning by `dt` (and
    // `dt²` for the acceleration) so the trajectory is unchanged, just smoother.
    private static let gravity: CGFloat = 7.0 * dt * dt   // downward pull each tick
    private static let restitution: CGFloat = 0.52        // fraction of speed kept on a bounce
    private static let floorFriction: CGFloat = 0.78      // horizontal damping on a floor bounce
    private static let settleSpeed: CGFloat = 10.0 * dt   // |vy| under this on the floor ⇒ stop & recover
    private static let maxFling: CGFloat = 120.0 * dt     // clamp on release velocity (prevents tunnelling)
    private static let recoverTotal = Int(3.3 * fps)      // ticks for impact→hurt→dazed→getUp

    // Size: a user-chosen scale (% of the dock-fitted base) applied to the pixel.
    static let sizeOptions = [50, 65, 80, 100, 125, 150]
    private static let sizeKey = "DinoDock.sizePct"
    private var sizePct: Int {
        get { let v = UserDefaults.standard.integer(forKey: Self.sizeKey); return v == 0 ? 80 : v }
        set { UserDefaults.standard.set(newValue, forKey: Self.sizeKey) }
    }

    private var pixel: CGFloat { petView?.pixel ?? 2 }
    private var spriteW: CGFloat { CGFloat(current.width) * pixel }
    private var spriteH: CGFloat { CGFloat(current.height) * pixel }
    private var hopHeight: CGFloat { max(8, pixel * 4) }
    private var preyW: CGFloat { CGFloat(DinoPixelArt.prey.first?.count ?? 0) * pixel }
    private var foodW: CGFloat { CGFloat(DinoPixelArt.meat.first?.count ?? 0) * pixel }
    private var stripWidth: CGFloat { window?.frame.width ?? band.width }

    // MARK: - Lifecycle

    func start() {
        setupMenu()
        rebuildWindow()
        wireInteractions()

        keyboard.onText = { [weak self] text in self?.handleTyped(text) }
        if reactsToKeys, KeyboardWatcher.hasPermission {
            keyboard.start()
            keyMonitorArmed = true
        } else if reactsToKeys {
            // Surface both prompts so this (signed) binary registers in the
            // Accessibility AND Input Monitoring lists. The periodic refresh then
            // (re)creates the monitor automatically once both switches are on.
            KeyboardWatcher.requestPermission()
        }

        startBehavior(.walk)
        blinkCountdown = randTicks(2, 5)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil)

        let timer = Timer.scheduledTimer(withTimeInterval: 1.0 / Self.fps, repeats: true) { [weak self] _ in
            self?.step()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        keyboard.stop()
        stopGrabWatch()
        window?.orderOut(nil)
        window = nil
        NotificationCenter.default.removeObserver(self)
    }

    deinit { stop() }

    // MARK: - Window

    /// The dock-fitted "100%" pixel size, before the user's size preference.
    private func basePixel(for band: DockBand) -> CGFloat {
        max(2, floor(band.thickness * 0.95 / CGFloat(current.height)))
    }

    /// The pixel size actually used, scaled by the user's size preference.
    private func scaledPixel(for band: DockBand) -> CGFloat {
        max(1, basePixel(for: band) * CGFloat(sizePct) / 100)
    }

    /// Headroom reserved above the sprite for hops and the (possibly wrapped,
    /// multi-line) speech bubble.
    private var topReserve: CGFloat { max(150, hopHeight + 10) }

    /// (Re)creates the floating window for the current mode, keeping the pet's
    /// relative horizontal position so the walk does not visibly restart.
    private func rebuildWindow() {
        let previousWidth = band.width
        let previousPosX = posX

        band = DockGeometry.band(for: mode)

        let view = petView ?? PetView(frame: .zero)
        view.pixel = scaledPixel(for: band)
        view.palette = current.palette
        view.spriteCols = current.width
        view.spriteRows = current.height
        view.image = (petKind == .human) ? HumanImageArt.idleRight.first : nil
        view.flipImage = false; view.lean = 0; view.stretchX = 1; view.stretchY = 1
        petView = view

        let frame = stripFrame()

        let window = self.window ?? makeWindow(frame: frame, view: view)
        window.setFrame(frame, display: true)
        if self.window == nil {
            window.orderFrontRegardless()
            self.window = window
        }

        // Preserve relative position across rebuilds; cancel any active hunt.
        if previousWidth > 0 {
            posX = previousPosX * (band.width / previousWidth)
        }
        preyActive = false
        foodActive = false
        // In the resting strip the walk range is the whole window; the throw
        // stage (growToStage) overrides these with the Dock sub-range.
        walkMinX = 0
        walkMaxX = walkWidth
        clampWalkX()
        view.posX = posX
        view.facingRight = direction >= 0
        view.needsDisplay = true
    }

    private func makeWindow(frame: NSRect, view: PetView) -> NSWindow {
        let window = NSWindow(contentRect: frame,
                              styleMask: [.borderless],
                              backing: .buffered,
                              defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true // never blocks clicks to the Dock/desktop
        // Sit just above the Dock so the pet stands *on* it; the Dock window
        // would otherwise cover the pet's feet.
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.dockWindow)) + 1)
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]

        view.frame = NSRect(origin: .zero, size: frame.size)
        view.autoresizingMask = [.width, .height]
        window.contentView = view
        return window
    }

    private var walkWidth: CGFloat { max(0, (window?.frame.width ?? band.width) - spriteW) }

    /// Confines `posX` to the current walk range, turning around at the ends.
    /// `walkMinX`/`walkMaxX` are the whole window in the resting strip and the
    /// Dock sub-range while a throw has grown the window to full screen.
    private func clampWalkX() {
        if posX <= walkMinX { posX = walkMinX; direction = 1 }
        if posX >= walkMaxX { posX = walkMaxX; direction = -1 }
    }

    // MARK: - Throw stage (a full-screen window so the pet can be flung anywhere)

    /// The resting strip window: a thin band hugging the Dock.
    private func stripFrame() -> NSRect {
        NSRect(x: band.minX, y: band.groundY,
               width: max(band.width, spriteW), height: spriteH + topReserve)
    }

    /// The full play area: from the Dock ground up to the menu bar, full width.
    private func stageFrame() -> NSRect? {
        guard let screen = NSScreen.main else { return nil }
        let vf = screen.visibleFrame
        return NSRect(x: vf.minX, y: band.groundY,
                      width: max(vf.width, spriteW),
                      height: max(spriteH + topReserve, vf.maxY - band.groundY))
    }

    /// Grows the window to fill the screen so a thrown pet can fly to the edges,
    /// keeping its on-screen position. Walking stays confined to the Dock band,
    /// remapped into the larger window's coordinates.
    private func growToStage() {
        guard !staged, let window, let frame = stageFrame() else { return }
        let screenX = window.frame.minX + posX
        window.setFrame(frame, display: true)
        posX = screenX - frame.minX
        walkMinX = max(0, band.minX - frame.minX)
        walkMaxX = max(walkMinX, band.maxX - frame.minX - spriteW)
        staged = true
        lastSpriteRect = .zero
        petView?.posX = posX
    }

    /// Shrinks back to the resting strip once the pet has settled, keeping its
    /// on-screen position and dropping it onto the Dock floor.
    private func shrinkToStrip() {
        guard staged, let window else { staged = false; return }
        let screenX = window.frame.minX + posX
        let frame = stripFrame()
        window.setFrame(frame, display: true)
        posX = screenX - frame.minX
        posY = 0
        staged = false
        walkMinX = 0
        walkMaxX = walkWidth
        clampWalkX()
        if let view = petView {
            view.posX = posX
            view.posY = 0
            view.needsDisplay = true
        }
    }

    /// Marks the smallest region that needs redrawing. In the resting strip the
    /// whole (small) window is cheap to repaint and naturally covers the
    /// bubble/props; on the full-screen stage we repaint only the moving
    /// sprite's neighbourhood so a flight doesn't recomposite the whole screen.
    private func invalidateSprite() {
        guard let view = petView else { return }
        guard staged else { view.needsDisplay = true; return }
        let cur = NSRect(x: posX, y: posY, width: spriteW, height: spriteH).insetBy(dx: -60, dy: -60)
        view.setNeedsDisplay(cur.union(lastSpriteRect))
        lastSpriteRect = cur
    }

    // MARK: - Grab & throw

    /// Wires the view's gesture callbacks and starts the cursor probe.
    private func wireInteractions() {
        guard let view = petView else { return }
        view.grabEnabled = grabEnabled
        view.onGrab    = { [weak self] p in self?.beginGrab(at: p) }
        view.onDrag    = { [weak self] p in self?.dragTo(p) }
        view.onRelease = { [weak self] v in self?.release(velocity: v) }
        view.onPoke    = { [weak self] in self?.poke() }
        if grabEnabled { startGrabWatch() } else { stopGrabWatch() }
    }

    /// A global cursor monitor flips click-through the instant the cursor lands
    /// on the pet (snappy grab); the periodic `step` probe flips it back when
    /// the cursor leaves. Mouse-moved global monitors need no special privilege.
    private func startGrabWatch() {
        guard mouseMonitor == nil else { return }
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) {
            [weak self] _ in
            guard let self, let view = self.petView, self.behavior != .held else { return }
            self.updatePassthrough(view)
        }
    }

    private func stopGrabWatch() {
        if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor) }
        mouseMonitor = nil
        window?.ignoresMouseEvents = true   // back to pure click-through
    }

    /// The window catches the mouse only while the cursor is over an opaque
    /// sprite pixel; everywhere else clicks pass straight through to the Dock.
    private func updatePassthrough(_ view: PetView) {
        guard let window else { return }
        let loc = NSEvent.mouseLocation
        let p = NSPoint(x: loc.x - window.frame.minX, y: loc.y - window.frame.minY)
        window.ignoresMouseEvents = !view.opaqueCell(at: p)
    }

    // ---- gestures (called back from PetView) ----

    private func beginGrab(at p: NSPoint) {
        guard grabEnabled else { return }
        preyActive = false; foodActive = false
        clearTyping()
        // Screen-space grab offset (survives the strip→stage window move because
        // it's a difference, so the origin shift cancels).
        grabDX = p.x - posX
        grabDY = p.y - posY
        vx = 0; vy = 0
        startBehavior(.held)            // grow to the stage lazily, on first drag
    }

    private func dragTo(_ p: NSPoint) {
        guard behavior == .held, let window else { return }
        // Resolve the cursor to screen coords *before* growing, because
        // growToStage moves the window origin (and `p` is window-relative).
        let cursorScreenX = window.frame.minX + p.x
        let cursorScreenY = window.frame.minY + p.y
        if !staged { growToStage() }
        guard let w = self.window else { return }
        posX = min(max(0, cursorScreenX - grabDX - w.frame.minX), max(0, w.frame.width - spriteW))
        posY = min(max(0, cursorScreenY - grabDY - w.frame.minY), max(0, w.frame.height - spriteH))
    }

    private func release(velocity v: CGVector) {
        guard behavior == .held else { return }
        guard staged else { poke(); return }   // released without dragging → treat as a tap
        func clamp(_ x: CGFloat) -> CGFloat { min(max(x, -Self.maxFling), Self.maxFling) }
        vx = clamp(v.dx / Self.fps)
        vy = clamp(v.dy / Self.fps)
        startBehavior(.flying)
    }

    /// A gentle tap (grabbed but not dragged): set the pet back down with a
    /// cheerful little hop instead of throwing it.
    private func poke() {
        guard behavior == .held else { return }
        vx = 0; vy = 0; posY = 0
        if staged { shrinkToStrip() }
        heartsCountdown = Int(1.1 * Self.fps)
        startBehavior(.hop)            // a happy little bounce + a ♥
    }

    // ---- physics driver (runs in place of the normal behaviour while interacting) ----

    private func runPhysics(_ view: PetView) {
        switch behavior {
        case .held:       stepHeld(view)
        case .flying:     stepFlight(view)
        case .recovering: stepRecovery(view)
        default: break
        }
    }

    private func stepHeld(_ view: PetView) {
        frame(view, current.held, HumanImageArt.held)
        view.posX = posX; view.posY = posY; view.facingRight = direction >= 0
        view.bob = 0; view.preyGrid = nil; view.foodGrid = nil; view.fxGrid = nil; view.bubbleText = nil
    }

    private func stepFlight(_ view: PetView) {
        guard let window else { return }
        throwTicks += 1
        vy -= Self.gravity
        posX += vx
        posY += vy

        let maxX = max(0, window.frame.width - spriteW)
        let maxY = max(0, window.frame.height - spriteH)
        if posX <= 0          { posX = 0;    vx = -vx * Self.restitution }
        else if posX >= maxX  { posX = maxX; vx = -vx * Self.restitution }
        if posY >= maxY       { posY = maxY; vy = -vy * Self.restitution }   // bonk the menu-bar ceiling

        if posY <= 0 {                                                       // hit the Dock floor
            posY = 0
            if abs(vy) > Self.settleSpeed {
                vy = -vy * Self.restitution                 // bounce back up
                vx *= Self.floorFriction
            } else {
                vy = 0
                if abs(vx) > Self.settleSpeed {
                    vx *= Self.floorFriction                // skid along the floor
                } else {
                    vx = 0
                    startBehavior(.recovering); stepRecovery(view); return
                }
            }
        }
        if throwTicks > Int(6 * Self.fps) {       // watchdog — never get stuck airborne
            posX = min(max(0, posX), maxX); posY = 0; vx = 0; vy = 0
            startBehavior(.recovering); stepRecovery(view); return
        }

        direction = vx >= 0 ? 1 : -1
        let ti = throwTicks / max(1, Int(Self.fps / 8))      // swap tumble frame ~8×/sec
        frame(view, current.tumble[ti % max(1, current.tumble.count)],
              HumanImageArt.tumble[ti % HumanImageArt.tumble.count])
        view.posX = posX; view.posY = posY; view.facingRight = direction >= 0
        view.bob = 0; view.preyGrid = nil; view.foodGrid = nil; view.fxGrid = nil; view.bubbleText = nil
    }

    private func stepRecovery(_ view: PetView) {
        recoverCounter += 1
        let t = recoverCounter
        let impactEnd = Int(0.5 * Self.fps), hurtEnd = Int(1.3 * Self.fps), dazedEnd = Int(2.6 * Self.fps)
        view.posX = posX; view.posY = 0; view.facingRight = direction >= 0
        view.bob = 0; view.preyGrid = nil; view.foodGrid = nil; view.fxGrid = nil; view.bubbleText = nil

        if t <= impactEnd {
            frame(view, current.impact, HumanImageArt.impact)
            let f = (t <= impactEnd / 2) ? 0 : min(ThrowFX.dust.count - 1, 1)   // dust puff at the feet
            placeFX(view, ThrowFX.dust[f], centeredX: true, atY: 0)
        } else if t <= hurtEnd {
            frame(view, current.hurt, HumanImageArt.hurt)
        } else if t <= dazedEnd {
            let d = HumanImageArt.dazed
            frame(view, current.dazed, d[((t - hurtEnd) / max(1, Int(Self.fps / 4))) % d.count])
            let stars = ThrowFX.stars
            placeFX(view, stars[(t / max(1, Int(Self.fps / 6))) % max(1, stars.count)],
                    centeredX: true, atY: spriteH * 0.6)   // spinning over the head
        } else if t < Self.recoverTotal {
            frame(view, current.getUp, HumanImageArt.getUp)
        } else {
            startBehavior(.walk)
            shrinkToStrip()
            if pendingRebuild { pendingRebuild = false; rebuildWindow(); refreshMenuState() }
        }
    }

    private func placeFX(_ view: PetView, _ grid: [String], centeredX: Bool, atY: CGFloat) {
        view.fxGrid = grid
        let gw = CGFloat(grid.map { $0.count }.max() ?? 0) * pixel
        view.fxX = centeredX ? posX + (spriteW - gw) / 2 : posX
        view.fxY = atY
    }

    /// Sets the main sprite frame for this tick — the dino's pixel grid, or the
    /// human's illustration image. Pass the matching frame for each character;
    /// the unused path is cleared so PetView draws the right one.
    private func frame(_ v: PetView, _ grid: [String], _ image: NSImage) {
        if petKind == .human {
            v.image = image
            v.flipImage = direction < 0      // canonical-right throw poses face travel direction
            v.lean = 0; v.stretchX = 1; v.stretchY = 1
        } else {
            v.image = nil
            v.grid = grid
        }
    }

    // MARK: - Menu

    private func setupMenu() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "🦖"

        let menu = NSMenu()
        menu.addItem(disabledItem("DinoDock"))
        menu.addItem(.separator())

        menu.addItem(disabledItem("Character"))
        for kind in PetKind.allCases {
            let kindItem = NSMenuItem(title: kind.title,
                                      action: #selector(selectCharacter(_:)),
                                      keyEquivalent: "")
            kindItem.target = self
            kindItem.representedObject = kind.rawValue
            kindItem.state = (kind == petKind) ? .on : .off
            menu.addItem(kindItem)
        }
        menu.addItem(.separator())

        menu.addItem(disabledItem("Walk area"))
        for walkMode in WalkMode.allCases {
            let menuItem = NSMenuItem(title: walkMode.title,
                                      action: #selector(selectMode(_:)),
                                      keyEquivalent: "")
            menuItem.target = self
            menuItem.representedObject = walkMode.rawValue
            menuItem.state = (walkMode == mode) ? .on : .off
            menu.addItem(menuItem)
        }

        menu.addItem(.separator())
        menu.addItem(disabledItem("Size"))
        for pct in Self.sizeOptions {
            let sizeItem = NSMenuItem(title: "\(pct)%", action: #selector(selectSize(_:)), keyEquivalent: "")
            sizeItem.target = self
            sizeItem.representedObject = pct
            menu.addItem(sizeItem)
        }

        menu.addItem(.separator())
        let catchThrow = NSMenuItem(title: "Catch & throw",
                                    action: #selector(toggleCatchThrow),
                                    keyEquivalent: "")
        catchThrow.target = self
        menu.addItem(catchThrow)

        let react = NSMenuItem(title: "React to typing",
                               action: #selector(toggleKeyboard),
                               keyEquivalent: "")
        react.target = self
        menu.addItem(react)

        menu.addItem(.separator())
        let track = NSMenuItem(title: "Track Dock exactly (Accessibility)…",
                               action: #selector(enableExactTracking),
                               keyEquivalent: "")
        track.target = self
        menu.addItem(track)

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit DinoDock", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        item.menu = menu
        statusItem = item
        refreshMenuState()
    }

    private func disabledItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func refreshMenuState() {
        guard let menu = statusItem?.menu else { return }
        for item in menu.items where item.action == #selector(selectCharacter(_:)) {
            item.state = (item.representedObject as? String == petKind.rawValue) ? .on : .off
        }
        for item in menu.items where item.action == #selector(selectMode(_:)) {
            item.state = (item.representedObject as? String == mode.rawValue) ? .on : .off
        }
        for item in menu.items where item.action == #selector(enableExactTracking) {
            item.state = DockGeometry.hasAccessibilityPermission ? .on : .off
        }
        for item in menu.items where item.action == #selector(toggleKeyboard) {
            item.state = reactsToKeys ? .on : .off
        }
        for item in menu.items where item.action == #selector(toggleCatchThrow) {
            item.state = grabEnabled ? .on : .off
        }
        for item in menu.items where item.action == #selector(selectSize(_:)) {
            item.state = (item.representedObject as? Int == sizePct) ? .on : .off
        }
    }

    // MARK: - Actions

    @objc private func selectMode(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let newMode = WalkMode(rawValue: raw), newMode != mode else { return }
        mode = newMode
        WalkMode.saved = newMode
        if interacting { pendingRebuild = true } else { rebuildWindow() }
        refreshMenuState()
    }

    @objc private func selectCharacter(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let newKind = PetKind(rawValue: raw), newKind != petKind else { return }
        petKind = newKind
        PetKind.saved = newKind
        if interacting {
            pendingRebuild = true
        } else {
            startBehavior(.walk)   // don't carry a half-finished eat/chase across the swap
            rebuildWindow()
        }
        refreshMenuState()
    }

    @objc private func selectSize(_ sender: NSMenuItem) {
        guard let pct = sender.representedObject as? Int, pct != sizePct else { return }
        sizePct = pct
        if interacting { pendingRebuild = true } else { rebuildWindow() }
        refreshMenuState()
    }

    @objc private func enableExactTracking() {
        guard !DockGeometry.hasAccessibilityPermission else { refreshMenuState(); return }
        // Ask the system to register the app + show its prompt, then guide the user.
        DockGeometry.requestAccessibilityPermission()
        presentPermissionHint(
            title: "Allow exact Dock tracking (optional)",
            body: """
            This is optional — the dino already walks fine without it. Enabling it just \
            lets the dino hug the Dock’s exact edges.

            In Privacy & Security ▸ Accessibility, switch DinoDock on. If it isn’t in the \
            list, click the “+” button and add:
            \(Bundle.main.bundlePath)

            Tip: rebuilding the app changes its (ad-hoc) signature, so macOS may drop the \
            permission and ask again — that’s expected.
            """,
            pane: "Privacy_Accessibility")
        // Permission is granted asynchronously; the periodic refresh will pick it up.
        refreshMenuState()
    }

    @objc private func toggleCatchThrow() {
        grabEnabled.toggle()
        UserDefaults.standard.set(grabEnabled, forKey: "DinoDock.catchThrow")
        petView?.grabEnabled = grabEnabled
        if grabEnabled {
            startGrabWatch()
        } else {
            // Drop any grab/throw in progress and return to pure click-through.
            if interacting {
                vx = 0; vy = 0; posY = 0
                if staged { shrinkToStrip() }
                startBehavior(.walk)
            }
            stopGrabWatch()
        }
        refreshMenuState()
    }

    @objc private func toggleKeyboard() {
        if reactsToKeys {
            reactsToKeys = false
            KeyboardPrefs.enabled = false
            keyboard.stop()
            keyMonitorArmed = false
            clearTyping()
        } else if KeyboardWatcher.hasPermission {
            reactsToKeys = true
            KeyboardPrefs.enabled = true
            keyboard.start()
            keyMonitorArmed = true
        } else {
            reactsToKeys = true            // keep it on; monitor arms once permitted
            KeyboardPrefs.enabled = true
            KeyboardWatcher.requestPermission()
            presentPermissionHint(
                title: "Allow DinoDock to see your typing",
                body: """
                Watching keystrokes needs BOTH permissions below — switch DinoDock on in each, \
                then it starts on its own (no restart needed):

                • Privacy & Security ▸ Accessibility
                • Privacy & Security ▸ Input Monitoring

                If DinoDock isn’t listed, click “+” and add:
                \(Bundle.main.bundlePath)

                Typed text is only shown briefly above the dino — never saved or sent anywhere, \
                and password fields are ignored.
                """,
                pane: "Privacy_ListenEvent")
        }
        refreshMenuState()
    }

    /// Shows a guidance alert with a button that deep-links to the right
    /// System Settings privacy pane (`Privacy_Accessibility`, `Privacy_ListenEvent`, …).
    private func presentPermissionHint(title: String, body: String, pane: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = body
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Later")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn,
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func screenParametersChanged() {
        if interacting {
            pendingRebuild = true
            // A display change mid-flight invalidates the stage coords — bail the
            // pet onto the floor and let it recover, then rebuild.
            if behavior == .flying { posY = 0; vx = 0; vy = 0; startBehavior(.recovering) }
            return
        }
        rebuildWindow()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    // MARK: - Keyboard reaction

    private func handleTyped(_ text: String) {
        guard reactsToKeys else { return }
        for ch in text {
            if ch == "\u{8}" {
                if !typedBuffer.isEmpty { typedBuffer.removeLast() }
            } else {
                typedBuffer.append(ch)
            }
        }
        if typedBuffer.count > Self.maxTyped {
            typedBuffer = String(typedBuffer.suffix(Self.maxTyped))
        }
        typingCountdown = Self.typingHold
    }

    private func clearTyping() {
        typedBuffer = ""
        typingCountdown = 0
        petView?.bubbleText = nil
        petView?.needsDisplay = true
    }

    // MARK: - Animation loop

    private func step() {
        tick += 1
        if tick % Self.refreshTicks == 0 { refreshBandIfNeeded() }
        guard let view = petView else { return }

        // Keep per-pixel click-through current (skipped mid-drag so the grab
        // keeps receiving events). Cheap bounds check; only when grabbing is on.
        if grabEnabled, behavior != .held { updatePassthrough(view) }

        // A grab / throw owns the pet completely: run physics and skip the
        // normal typing reaction, gait, prey/food and quote logic below.
        if interacting {
            runPhysics(view)
            invalidateSprite()
            return
        }

        if reactsToKeys, typingCountdown > 0 {
            typingCountdown -= 1
            if typingCountdown == 0 {
                typedBuffer = ""
                view.bubbleText = nil
            } else {
                runTypingReaction(view)
                invalidateSprite()
                return
            }
        }

        runBehavior(view)
        invalidateSprite()
    }

    /// While the user types, the pet pauses and flaps its mouth, showing the
    /// text in its bubble (and tucking away any prey/food it was busy with).
    private func runTypingReaction(_ view: PetView) {
        mouthCounter += 1
        if petKind == .human {
            view.image = humanIdle(direction >= 0)
            view.flipImage = false; view.lean = 0; view.stretchX = 1; view.stretchY = 1
        } else {
            view.image = nil
            view.grid = current.stand
        }
        view.posX = posX
        view.posY = posY
        view.facingRight = direction >= 0
        view.bob = (mouthCounter / Self.animDiv) % 2 == 1 ? pixel : 0   // gentle nod while "talking"
        view.preyGrid = nil
        view.foodGrid = nil
        view.bubbleStyle = .typing
        view.bubbleText = typedBuffer.isEmpty ? nil : typedBuffer
    }

    // MARK: - Behaviour machine

    private func randTicks(_ lo: Double, _ hi: Double) -> Int {
        Int(Double.random(in: lo...hi) * Self.fps)
    }

    private func startBehavior(_ b: Behavior) {
        behavior = b
        if b != .chase { preyActive = false }
        if b != .eat { foodActive = false }
        switch b {
        case .walk:  behaviorTicks = randTicks(4, 11)
        case .run:   behaviorTicks = randTicks(2, 4.5)
        case .idle:  behaviorTicks = randTicks(1.5, 5)
        case .look:  behaviorTicks = randTicks(3, 6); lookCountdown = randTicks(0.7, 1.5)
        case .hop:   hopTotal = Int.random(in: 2...5) * Self.hopLen; behaviorTicks = hopTotal
        case .sleep: behaviorTicks = randTicks(8, 22)
        case .chase: spawnPrey(); behaviorTicks = randTicks(4, 8)
        case .eat:   foodActive = true; eatCounter = 0; behaviorTicks = randTicks(2, 3.8)
        case .speak:
            currentQuote = Quotes.random()
            let words = max(1, currentQuote.split(separator: " ").count)
            behaviorTicks = min(Int(8 * Self.fps), Int((2.6 + Double(words) * 0.32) * Self.fps))
        case .held:       behaviorTicks = .max               // until released
        case .flying:     behaviorTicks = .max; throwTicks = 0 // until it settles
        case .recovering: recoverCounter = 0; behaviorTicks = Self.recoverTotal
        }
    }

    /// Weighted, context-sensitive choice so the pet moves through states the
    /// way a real critter might. Hunting and quotes are deliberately rare.
    private func nextBehavior() -> Behavior {
        let table: [(Behavior, Int)]
        switch behavior {
        case .walk:  table = [(.idle, 26), (.look, 15), (.hop, 12), (.run, 10), (.walk, 10), (.chase, 10), (.sleep, 8), (.eat, 5), (.speak, 4)]
        case .run:   table = [(.walk, 40), (.idle, 24), (.chase, 14), (.look, 12), (.hop, 10)]
        case .idle:  table = [(.walk, 32), (.look, 16), (.hop, 10), (.sleep, 14), (.run, 8), (.chase, 8), (.eat, 6), (.speak, 6)]
        case .look:  table = [(.walk, 46), (.idle, 18), (.hop, 12), (.chase, 12), (.run, 12)]
        case .hop:   table = [(.walk, 42), (.idle, 24), (.look, 14), (.run, 10), (.chase, 10)]
        case .sleep: table = [(.idle, 55), (.walk, 45)]
        case .chase: table = [(.walk, 45), (.idle, 30), (.look, 15), (.hop, 10)]
        case .eat:   table = [(.idle, 38), (.walk, 38), (.look, 16), (.hop, 8)]
        case .speak: table = [(.walk, 44), (.idle, 34), (.look, 22)]
        case .held, .flying, .recovering: table = [(.walk, 1)]   // unreachable; for exhaustiveness
        }
        let total = table.reduce(0) { $0 + $1.1 }
        var r = Int.random(in: 0..<max(1, total))
        for (b, w) in table {
            if r < w { return b }
            r -= w
        }
        return .walk
    }

    private func runBehavior(_ view: PetView) {
        behaviorTicks -= 1

        switch behavior {
        case .walk:  move(speedScale: 1)
        case .run:   move(speedScale: 2.1)
        case .chase: updateChase()
        case .look:
            lookCountdown -= 1
            if lookCountdown <= 0 {
                direction = -direction
                lookCountdown = randTicks(0.7, 1.5)
            }
        case .idle, .hop, .sleep, .eat, .speak, .held, .flying, .recovering:
            break
        }

        if behaviorTicks <= 0 {
            let next = forceEat ? .eat : nextBehavior()
            forceEat = false
            startBehavior(next)
        }
        updateAppearance(view)
    }

    private func move(speedScale: CGFloat) {
        let speed = max(1, pixel * 0.6) * speedScale * Self.dt
        posX += speed * direction
        clampWalkX()
    }

    /// Spawns the prey a good distance away, on whichever side has more room.
    private func spawnPrey() {
        let maxX = max(0, stripWidth - preyW)
        let dinoCenter = posX + spriteW / 2
        if dinoCenter < stripWidth / 2 {
            preyX = min(maxX, posX + spriteW * 1.8)
        } else {
            preyX = max(0, posX - spriteW * 1.4 - preyW)
        }
        preyFacing = preyX >= posX
        preyActive = true
    }

    /// The prey flees away from the dino (cornering itself at the walls) while
    /// the dino runs it down, re-aiming each tick. Contact ⇒ caught ⇒ eat.
    private func updateChase() {
        let maxX = max(0, stripWidth - preyW)
        let dinoCenter = posX + spriteW / 2
        let preyCenter = preyX + preyW / 2

        let fleeDir: CGFloat = preyCenter >= dinoCenter ? 1 : -1
        preyX = max(0, min(maxX, preyX + max(1, pixel * 0.95) * Self.dt * fleeDir))
        preyFacing = fleeDir >= 0

        direction = preyCenter >= dinoCenter ? 1 : -1
        posX = max(walkMinX, min(walkMaxX, posX + max(1, pixel * 0.6) * 2.1 * Self.dt * direction))

        if abs((posX + spriteW / 2) - preyCenter) < spriteW * 0.32 {
            preyActive = false       // caught!
            forceEat = true
            behaviorTicks = 0        // ends the chase → forced into .eat
        }
    }

    private func updateAppearance(_ view: PetView) {
        view.posX = posX
        view.posY = posY
        view.facingRight = direction >= 0

        let moving = (behavior == .walk || behavior == .run || behavior == .chase)

        // Gait: advance the 4-phase walk cycle while moving.
        if moving {
            animCounter += 1
            let stride = (behavior == .run || behavior == .chase) ? Self.runStride : Self.walkStride
            if animCounter % stride == 0 { walkPhase = (walkPhase + 1) % 4 }
        } else {
            walkPhase = 0
            animCounter = 0
        }

        // Blink scheduling (skipped while asleep — the eyes are already shut).
        if behavior != .sleep {
            if blinkHold > 0 {
                blinkHold -= 1
            } else {
                blinkCountdown -= 1
                if blinkCountdown <= 0 {
                    blinkHold = Self.blinkHoldTicks
                    blinkCountdown = randTicks(1.5, 6)
                }
            }
        }

        if behavior == .eat { eatCounter += 1 }

        // Pick the frame + vertical motion. The human uses illustration frames
        // with continuous procedural "life"; the dino uses pixel grids + discrete bob.
        if petKind == .human {
            pickHumanFrame(view, moving: moving)
        } else {
            view.image = nil
            if behavior == .eat {
                view.grid = current.stand
            } else if behavior == .sleep || blinkHold > 0 {
                view.grid = current.blink
            } else if moving {
                switch walkPhase {
                case 0: view.grid = current.walkB   // lift back foot
                case 2: view.grid = current.walkC   // lift front foot
                default: view.grid = current.stand  // passing
                }
            } else {
                view.grid = current.stand
            }
            // Vertical motion (dino).
            if behavior == .hop {
                let phase = Double((hopTotal - behaviorTicks) % Self.hopLen) / Double(Self.hopLen)
                view.bob = CGFloat(sin(.pi * phase)) * hopHeight
            } else if behavior == .eat {
                view.bob = (eatCounter / Self.animDiv) % 2 == 1 ? pixel : 0   // chomp
            } else if moving {
                view.bob = (walkPhase % 2 == 1) ? pixel : 0        // lifts on passing beats
            } else {
                view.bob = 0
            }
        }

        // Props: prey while hunting, meat while eating.
        if preyActive {
            view.preyGrid = DinoPixelArt.prey
            view.preyX = preyX
            view.preyFacingRight = preyFacing
        } else {
            view.preyGrid = nil
        }
        if foodActive {
            view.foodGrid = DinoPixelArt.meat
            view.foodX = direction >= 0 ? posX + spriteW * 0.80 : posX + spriteW * 0.20 - foodW
            view.foodY = CGFloat(30) * pixel + view.bob   // up at the snout; follows the chomp
        } else {
            view.foodGrid = nil
        }

        // Bubble: "zzz" asleep, a quote when musing, otherwise nothing.
        switch behavior {
        case .sleep:
            view.bubbleStyle = .sleep
            view.bubbleText = String(repeating: "z", count: (tick / 9) % 3 + 1)
        case .speak:
            view.bubbleStyle = .quote
            view.bubbleText = currentQuote
        default:
            if heartsCountdown > 0 {
                heartsCountdown -= 1
                view.bubbleStyle = .quote
                view.bubbleText = "♥"
            } else {
                view.bubbleText = nil
            }
        }
    }

    /// Selects the human's illustration frame + procedural motion for this tick.
    private func pickHumanFrame(_ view: PetView, moving: Bool) {
        view.flipImage = false           // walk/idle use explicit left/right frames
        view.lean = 0; view.stretchX = 1; view.stretchY = 1
        let facingR = direction >= 0
        if behavior == .hop {
            view.image = humanIdle(facingR)
            let phase = Double((hopTotal - behaviorTicks) % Self.hopLen) / Double(Self.hopLen)
            view.bob = CGFloat(sin(.pi * phase)) * hopHeight
        } else if moving {
            let frames = facingR ? HumanImageArt.walkRight : HumanImageArt.walkLeft
            view.image = frames[(animCounter / Self.walkFrameDiv) % max(1, frames.count)]
            applyGait(view)
        } else {
            view.image = humanIdle(facingR)
            applyIdleBreath(view)
        }
    }

    /// Continuous secondary motion over the walk frames: a two-beat body bob, a
    /// gentle side lean and a squash on each footfall — so the gait feels alive
    /// instead of "slapping images".
    private func applyGait(_ view: PetView) {
        let cycle = CGFloat(max(1, Self.walkFrameDiv * HumanImageArt.walkRight.count))
        let pos = CGFloat(animCounter % Int(cycle)) / cycle           // 0..1 over one full cycle
        let twoPi = CGFloat.pi * 2
        let bobN = (1 - cos(pos * twoPi * 2)) / 2                      // 0..1, a bump per step
        view.bob = bobN * max(2, spriteH * 0.016)
        view.lean = sin(pos * twoPi) * 0.012                          // gentle sway (not dizzying)
        let squash = (1 - bobN) * 0.015                               // widest at footfall
        view.stretchX = 1 + squash * 0.5
        view.stretchY = 1 - squash
    }

    /// Slow breathing while standing still.
    private func applyIdleBreath(_ view: PetView) {
        let period = CGFloat(max(1, Int(Self.fps * 2)))
        let breath = sin(CGFloat(tick % Int(period)) / period * .pi * 2)
        view.bob = (breath + 1) / 2 * max(1, spriteH * 0.008)
        view.lean = breath * 0.006
        view.stretchY = 1 + breath * 0.004
        view.stretchX = 1
    }

    /// Re-reads the Dock band and slides the window to match, without
    /// restarting the walk. Picks up Dock resizes and late-granted permission.
    private func refreshBandIfNeeded() {
        // Pick up permissions granted *after* launch. A global key monitor only
        // delivers events if it was created while BOTH Accessibility and Input
        // Monitoring are held, so (re)create it once both are present.
        if reactsToKeys {
            if KeyboardWatcher.hasPermission {
                if !keyMonitorArmed {
                    keyboard.stop()
                    keyboard.start()
                    keyMonitorArmed = true
                }
            } else {
                keyMonitorArmed = false
            }
        }
        let fresh = DockGeometry.band(for: mode)
        guard fresh != band else { return }
        if interacting { pendingRebuild = true; return }   // don't resize the window mid-throw
        rebuildWindow()
        refreshMenuState()
    }
}
