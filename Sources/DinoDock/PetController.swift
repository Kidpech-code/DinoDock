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

    // Walk band / position
    private var mode: WalkMode = .saved
    private var band = DockBand(groundY: 0, minX: 0, maxX: 0, thickness: 0)
    private var posX: CGFloat = 0
    private var direction: CGFloat = 1   // +1 faces right, -1 faces left
    private var tick = 0

    // Behaviour state machine
    private enum Behavior { case walk, run, idle, look, hop, sleep, chase, eat, speak }
    private var behavior: Behavior = .walk
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

    // Tuning
    private static let fps = 12.0
    private static let refreshTicks = 12         // re-read the Dock ~once a second
    private static let hopLen = 16               // ticks per single hop arc
    private static let maxTyped = 18             // characters kept in the bubble
    private static let typingHold = Int(1.6 * fps)

    // Size: a user-chosen scale (% of the dock-fitted base) applied to the pixel.
    static let sizeOptions = [50, 65, 80, 100, 125, 150]
    private static let sizeKey = "DinoDock.sizePct"
    private var sizePct: Int {
        get { let v = UserDefaults.standard.integer(forKey: Self.sizeKey); return v == 0 ? 80 : v }
        set { UserDefaults.standard.set(newValue, forKey: Self.sizeKey) }
    }

    private var pixel: CGFloat { petView?.pixel ?? 2 }
    private var spriteW: CGFloat { CGFloat(DinoPixelArt.width) * pixel }
    private var spriteH: CGFloat { CGFloat(DinoPixelArt.height) * pixel }
    private var hopHeight: CGFloat { max(8, pixel * 4) }
    private var preyW: CGFloat { CGFloat(DinoPixelArt.prey.first?.count ?? 0) * pixel }
    private var foodW: CGFloat { CGFloat(DinoPixelArt.meat.first?.count ?? 0) * pixel }
    private var stripWidth: CGFloat { window?.frame.width ?? band.width }

    // MARK: - Lifecycle

    func start() {
        setupMenu()
        rebuildWindow()

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
        window?.orderOut(nil)
        window = nil
        NotificationCenter.default.removeObserver(self)
    }

    deinit { stop() }

    // MARK: - Window

    /// The dock-fitted "100%" pixel size, before the user's size preference.
    private func basePixel(for band: DockBand) -> CGFloat {
        max(2, floor(band.thickness * 0.95 / CGFloat(DinoPixelArt.height)))
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
        petView = view

        let height = spriteH + topReserve
        let frame = NSRect(x: band.minX,
                           y: band.groundY,
                           width: max(band.width, spriteW),
                           height: height)

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
        clampPosition()
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

    private func clampPosition() {
        if posX < 0 { posX = 0; direction = 1 }
        if posX > walkWidth { posX = walkWidth; direction = -1 }
    }

    // MARK: - Menu

    private func setupMenu() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "🦖"

        let menu = NSMenu()
        menu.addItem(disabledItem("DinoDock"))
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
        for item in menu.items where item.action == #selector(selectMode(_:)) {
            item.state = (item.representedObject as? String == mode.rawValue) ? .on : .off
        }
        for item in menu.items where item.action == #selector(enableExactTracking) {
            item.state = DockGeometry.hasAccessibilityPermission ? .on : .off
        }
        for item in menu.items where item.action == #selector(toggleKeyboard) {
            item.state = reactsToKeys ? .on : .off
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
        rebuildWindow()
        refreshMenuState()
    }

    @objc private func selectSize(_ sender: NSMenuItem) {
        guard let pct = sender.representedObject as? Int, pct != sizePct else { return }
        sizePct = pct
        rebuildWindow()
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

        if reactsToKeys, typingCountdown > 0 {
            typingCountdown -= 1
            if typingCountdown == 0 {
                typedBuffer = ""
                view.bubbleText = nil
            } else {
                runTypingReaction(view)
                view.needsDisplay = true
                return
            }
        }

        runBehavior(view)
        view.needsDisplay = true
    }

    /// While the user types, the pet pauses and flaps its mouth, showing the
    /// text in its bubble (and tucking away any prey/food it was busy with).
    private func runTypingReaction(_ view: PetView) {
        mouthCounter += 1
        view.grid = DinoPixelArt.stand
        view.posX = posX
        view.facingRight = direction >= 0
        view.bob = (mouthCounter / 3) % 2 == 1 ? pixel : 0   // gentle nod while "talking"
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
        case .idle, .hop, .sleep, .eat, .speak:
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
        let speed = max(1, pixel * 0.6) * speedScale
        posX += speed * direction
        if posX >= walkWidth {
            posX = walkWidth
            direction = -1
        } else if posX <= 0 {
            posX = 0
            direction = 1
        }
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
        preyX = max(0, min(maxX, preyX + max(1, pixel * 0.95) * fleeDir))
        preyFacing = fleeDir >= 0

        direction = preyCenter >= dinoCenter ? 1 : -1
        posX = max(0, min(walkWidth, posX + max(1, pixel * 0.6) * 2.1 * direction))

        if abs((posX + spriteW / 2) - preyCenter) < spriteW * 0.32 {
            preyActive = false       // caught!
            forceEat = true
            behaviorTicks = 0        // ends the chase → forced into .eat
        }
    }

    private func updateAppearance(_ view: PetView) {
        view.posX = posX
        view.facingRight = direction >= 0

        let moving = (behavior == .walk || behavior == .run || behavior == .chase)

        // Gait: advance the 4-phase walk cycle while moving.
        if moving {
            animCounter += 1
            let stride = (behavior == .run || behavior == .chase) ? 2 : 3
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
                    blinkHold = 2
                    blinkCountdown = randTicks(1.5, 6)
                }
            }
        }

        // Pick the grid for this frame.
        if behavior == .eat {
            eatCounter += 1
            view.grid = DinoPixelArt.stand   // chomp is shown via the bob below
        } else if behavior == .sleep || blinkHold > 0 {
            view.grid = DinoPixelArt.blink
        } else if moving {
            switch walkPhase {
            case 0: view.grid = DinoPixelArt.walkB   // lift back foot
            case 2: view.grid = DinoPixelArt.walkC   // lift front foot
            default: view.grid = DinoPixelArt.stand  // passing
            }
        } else {
            view.grid = DinoPixelArt.stand
        }

        // Vertical motion.
        if behavior == .hop {
            let elapsed = hopTotal - behaviorTicks
            let phase = Double(elapsed % Self.hopLen) / Double(Self.hopLen)
            view.bob = CGFloat(sin(.pi * phase)) * hopHeight
        } else if behavior == .eat {
            view.bob = (eatCounter / 3) % 2 == 1 ? pixel : 0   // chomp
        } else if moving {
            view.bob = (walkPhase % 2 == 1) ? pixel : 0        // body lifts on the passing beats
        } else {
            view.bob = 0
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
            view.bubbleText = nil
        }
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
        rebuildWindow()
        refreshMenuState()
    }
}
