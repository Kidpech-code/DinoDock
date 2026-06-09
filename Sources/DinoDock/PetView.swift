import Cocoa

/// How the bubble above the pet should look.
enum BubbleStyle { case typing, sleep, quote }

/// Draws the dinosaur sprite at `posX` (horizontal offset within the strip)
/// using the current grid, facing direction and pixel scale, plus optional
/// props (the prey it chases, the meat it eats) and a speech bubble above its
/// head (typed text, a quote, or "zzz" while asleep).
final class PetView: NSView {
    var posX: CGFloat = 0
    var posY: CGFloat = 0   // height above the window bottom (the Dock floor); used by throws
    var bob: CGFloat = 0
    var facingRight = true
    var pixel: CGFloat = 4

    /// The pixel grid to render this frame (used by the dino). Set each tick.
    var grid: [String] = DinoPixelArt.stand

    /// When non-nil, the main sprite is drawn from this image (the human's
    /// illustration frames) instead of `grid`, scaled into a
    /// `spriteCols`×`spriteRows`-cell rect. The controller sets one or the other.
    var image: NSImage?
    var spriteCols = 44
    var spriteRows = 44
    /// Procedural "life" applied to the image sprite, pivoting at the feet
    /// (bottom-centre): a horizontal flip, a small lean (radians) and a
    /// squash/stretch. Lets a few illustration frames read as a living gait.
    var flipImage = false
    var lean: CGFloat = 0
    var stretchX: CGFloat = 1
    var stretchY: CGFloat = 1

    // Props (nil = hidden). Positions are in strip coordinates, like `posX`.
    var preyGrid: [String]?
    var preyX: CGFloat = 0
    var preyFacingRight = false
    var foodGrid: [String]?
    var foodX: CGFloat = 0
    var foodY: CGFloat = 0

    /// Text shown in the bubble above the pet; `nil`/empty hides the bubble.
    var bubbleText: String?
    var bubbleStyle: BubbleStyle = .typing

    /// A throw-effect prop drawn on top of the pet (spinning dazed stars, an
    /// impact dust puff). Position is in window coordinates, like `posX`.
    var fxGrid: [String]?
    var fxX: CGFloat = 0
    var fxY: CGFloat = 0

    /// Grid char → colour. Set by the controller per character (see
    /// `CharacterArt.palette`); defaults to the dino so the view renders
    /// sensibly even before the first `rebuildWindow`.
    var palette: [Character: NSColor] = DinoPixelArt.art.palette

    // MARK: - Grab & throw interaction (driven by the controller)

    /// Whether the pet can be grabbed/thrown right now ("Catch & throw" on).
    var grabEnabled = false
    /// Reported in window coordinates, mirroring the `keyboard.onText` pattern.
    var onGrab: ((NSPoint) -> Void)?
    var onDrag: ((NSPoint) -> Void)?
    var onRelease: ((CGVector) -> Void)?   // fling velocity in points/second
    var onPoke: (() -> Void)?

    private var dragging = false
    private var grabStart = NSPoint.zero
    private var samples: [(NSPoint, TimeInterval)] = []   // recent drag samples for fling velocity
    private var hitImage: NSImage?                        // cached alpha source for image hit-testing
    private var hitRep: NSBitmapImageRep?

    override var isOpaque: Bool { false }
    // Grab the pet without making this window key, so the app you're working in
    // keeps focus (important: the pet is a toy, not a focus-stealer).
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        if let preyGrid { drawGrid(preyGrid, originX: preyX, originY: 0, facingRight: preyFacingRight) }
        if let image {
            drawSpriteImage(image, originX: posX, originY: posY + bob)
        } else {
            drawGrid(grid, originX: posX, originY: posY + bob, facingRight: facingRight)
        }
        if let foodGrid { drawGrid(foodGrid, originX: foodX, originY: foodY, facingRight: facingRight) }
        if let fxGrid { drawGrid(fxGrid, originX: fxX, originY: fxY, facingRight: true) }
        if let text = bubbleText, !text.isEmpty { drawBubble(text) }
    }

    /// Draws an illustration frame into the sprite rect with smooth scaling,
    /// mirrored horizontally when facing left.
    private func drawSpriteImage(_ image: NSImage, originX: CGFloat, originY: CGFloat) {
        let w = CGFloat(spriteCols) * pixel, h = CGFloat(spriteRows) * pixel
        let rect = NSRect(x: originX, y: originY, width: w, height: h)
        let pivotX = originX + w / 2, pivotY = originY      // sway / squash from the feet
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current?.imageInterpolation = .high
        let t = NSAffineTransform()
        t.translateX(by: pivotX, yBy: pivotY)
        if lean != 0 { t.rotate(byRadians: lean) }
        t.scaleX(by: (flipImage ? -1 : 1) * stretchX, yBy: stretchY)
        t.translateX(by: -pivotX, yBy: -pivotY)
        t.concat()
        image.draw(in: rect)
        NSGraphicsContext.restoreGraphicsState()
    }

    // MARK: - Sprite

    private func drawGrid(_ grid: [String], originX: CGFloat, originY: CGFloat, facingRight: Bool) {
        let rows = grid.count
        let cols = grid.map { $0.count }.max() ?? 0

        // Snap every cell edge to the device-pixel grid so cells tile seamlessly
        // and stay crisp even when `pixel` is fractional (any size scale).
        let s = window?.backingScaleFactor ?? 2
        func snap(_ v: CGFloat) -> CGFloat { (v * s).rounded() / s }

        for (r, line) in grid.enumerated() {
            let chars = Array(line)
            for c in 0..<chars.count {
                guard let color = palette[chars[c]] else { continue }
                let drawCol = facingRight ? c : (cols - 1 - c)
                let x0 = snap(originX + CGFloat(drawCol) * pixel)
                let x1 = snap(originX + CGFloat(drawCol + 1) * pixel)
                // Grid row 0 is the top; AppKit's y axis points up, so flip it.
                let y0 = snap(originY + CGFloat(rows - 1 - r) * pixel)
                let y1 = snap(originY + CGFloat(rows - r) * pixel)
                color.setFill()
                NSBezierPath(rect: NSRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)).fill()
            }
        }
    }

    // MARK: - Speech / sleep / quote bubble

    private func drawBubble(_ text: String) {
        // Size from the current frame so the bubble sits above any character's
        // head (the dino and the human have different grid dimensions).
        let cols = grid.map { $0.count }.max() ?? 0
        let spriteW = CGFloat(cols) * pixel
        let spriteH = CGFloat(grid.count) * pixel
        let fontSize = min(16, max(11, pixel * 4))

        let font: NSFont
        let textColor: NSColor
        switch bubbleStyle {
        case .sleep:
            font = .systemFont(ofSize: fontSize, weight: .medium)
            textColor = NSColor(srgbRed: 0.45, green: 0.5, blue: 0.55, alpha: 1)
        case .quote:
            font = .systemFont(ofSize: fontSize, weight: .regular)
            textColor = NSColor(srgbRed: 0.13, green: 0.30, blue: 0.16, alpha: 1)
        case .typing:
            font = .systemFont(ofSize: fontSize, weight: .semibold)
            textColor = NSColor(srgbRed: 0.106, green: 0.369, blue: 0.125, alpha: 1)
        }

        let para = NSMutableParagraphStyle()
        para.alignment = .center
        para.lineBreakMode = .byWordWrapping
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font, .foregroundColor: textColor, .paragraphStyle: para,
        ]
        let str = NSAttributedString(string: text, attributes: attrs)

        // Wrap quotes; keep short status text on one line.
        let maxTextW = min(max(bounds.width - 16, 80), 240)
        let bounding = str.boundingRect(with: NSSize(width: maxTextW, height: 400),
                                        options: [.usesLineFragmentOrigin, .usesFontLeading])
        let textW = ceil(bounding.width)
        let textH = ceil(bounding.height)

        let padX: CGFloat = 12, padY: CGFloat = 7
        let bw = max(textW + padX * 2, 28)
        let bh = textH + padY * 2
        let gap: CGFloat = 7

        // Centre over the sprite, then clamp so it never spills off the strip.
        let centreX = posX + spriteW / 2
        var bx = centreX - bw / 2
        bx = max(3, min(bx, bounds.width - bw - 3))
        let by = spriteH + gap

        let rect = NSRect(x: bx, y: by, width: bw, height: bh)
        let radius = min(bh / 2, 14)
        let body = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)

        // Soft drop shadow for a polished look.
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.18)
        shadow.shadowBlurRadius = 4
        shadow.shadowOffset = NSSize(width: 0, height: -1)
        shadow.set()
        NSColor.white.withAlphaComponent(0.96).setFill()
        body.fill()
        NSGraphicsContext.restoreGraphicsState()

        let stroke: NSColor
        switch bubbleStyle {
        case .sleep: stroke = NSColor(white: 0.7, alpha: 0.7)
        case .quote: stroke = NSColor(srgbRed: 0.30, green: 0.55, blue: 0.33, alpha: 0.9)
        case .typing: stroke = NSColor(srgbRed: 0.263, green: 0.627, blue: 0.278, alpha: 0.9)
        }
        stroke.setStroke()
        body.lineWidth = 1
        body.stroke()

        // Little tail pointing down at the dino (a speech bubble nib).
        let tailX = min(max(centreX, bx + radius + 4), bx + bw - radius - 4)
        let tail = NSBezierPath()
        tail.move(to: NSPoint(x: tailX - 5, y: by + 1))
        tail.line(to: NSPoint(x: tailX + 5, y: by + 1))
        tail.line(to: NSPoint(x: tailX, y: by - 6))
        tail.close()
        NSColor.white.withAlphaComponent(0.96).setFill()
        tail.fill()

        str.draw(with: NSRect(x: rect.minX + padX, y: rect.minY + padY, width: bw - padX * 2, height: textH),
                 options: [.usesLineFragmentOrigin, .usesFontLeading])
    }

    // MARK: - Grab gestures

    /// Whether `p` (window coordinates) lands on a non-transparent sprite cell,
    /// dilated by `slop` points so the pet is still grabbable at tiny sizes.
    /// The controller also calls this from its cursor probe to decide when the
    /// window should stop ignoring the mouse.
    func opaqueCell(at p: NSPoint, slop: CGFloat = 3) -> Bool {
        if let image { return opaqueImage(image, at: p, slop: slop) }
        let rows = grid.count
        let cols = grid.map { $0.count }.max() ?? 0
        guard rows > 0, cols > 0, pixel > 0 else { return false }
        let originX = posX, originY = posY + bob
        let s = max(0, Int((slop / pixel).rounded()))
        let cx = Int(floor((p.x - originX) / pixel))
        let ry = Int(floor((p.y - originY) / pixel))
        for dy in -s...s {
            for dx in -s...s {
                let scx = cx + dx, sry = ry + dy
                guard scx >= 0, scx < cols, sry >= 0, sry < rows else { continue }
                let r = rows - 1 - sry                       // grid row 0 is the top
                let c = facingRight ? scx : (cols - 1 - scx) // mirror like drawGrid
                let line = Array(grid[r])
                guard c >= 0, c < line.count else { continue }
                if palette[line[c]] != nil { return true }
            }
        }
        return false
    }

    /// Per-pixel hit test for the image character: samples the frame's alpha so
    /// clicks on the transparent area around her still pass through to the Dock.
    private func opaqueImage(_ image: NSImage, at p: NSPoint, slop: CGFloat) -> Bool {
        let w = CGFloat(spriteCols) * pixel, h = CGFloat(spriteRows) * pixel
        guard w > 0, h > 0 else { return false }
        let originX = posX, originY = posY + bob
        guard let rep = bitmap(for: image) else {            // fallback: bounding box
            return NSRect(x: originX, y: originY, width: w, height: h).insetBy(dx: -slop, dy: -slop).contains(p)
        }
        var fx = (p.x - originX) / w
        let fy = (p.y - originY) / h                          // 0 bottom .. 1 top
        if flipImage { fx = 1 - fx }
        if fx < -0.05 || fx > 1.05 || fy < -0.05 || fy > 1.05 { return false }
        let cx = Int(min(max(fx, 0), 0.999) * CGFloat(rep.pixelsWide))
        let cy = Int((1 - min(max(fy, 0), 0.999)) * CGFloat(rep.pixelsHigh))   // rep y is top-down
        let r = max(2, rep.pixelsWide / 36)                   // a few px of grab tolerance
        for dy in [-r, 0, r] {
            for dx in [-r, 0, r] {
                let sx = min(max(cx + dx, 0), rep.pixelsWide - 1)
                let sy = min(max(cy + dy, 0), rep.pixelsHigh - 1)
                if let c = rep.colorAt(x: sx, y: sy), c.alphaComponent > 0.25 { return true }
            }
        }
        return false
    }

    private func bitmap(for image: NSImage) -> NSBitmapImageRep? {
        if hitImage === image, let r = hitRep { return r }
        guard let tiff = image.tiffRepresentation, let r = NSBitmapImageRep(data: tiff) else { return nil }
        hitImage = image; hitRep = r
        return r
    }

    override func mouseDown(with event: NSEvent) {
        let p = event.locationInWindow
        guard grabEnabled, opaqueCell(at: p) else { super.mouseDown(with: event); return }
        dragging = true
        grabStart = p
        samples = [(p, event.timestamp)]
        onGrab?(p)
    }

    override func mouseDragged(with event: NSEvent) {
        guard dragging else { super.mouseDragged(with: event); return }
        let p = event.locationInWindow
        samples.append((p, event.timestamp))
        if samples.count > 6 { samples.removeFirst() }
        onDrag?(p)
    }

    override func mouseUp(with event: NSEvent) {
        guard dragging else { super.mouseUp(with: event); return }
        dragging = false
        let p = event.locationInWindow
        if hypot(p.x - grabStart.x, p.y - grabStart.y) < 6 {   // a tap, not a throw
            samples = []
            onPoke?()
            return
        }
        samples.append((p, event.timestamp))
        // Fling velocity from the motion over the last ~120 ms (points/second).
        let now = event.timestamp
        let recent = samples.filter { now - $0.1 <= 0.12 }
        let pts = recent.count >= 2 ? recent : samples
        var v = CGVector.zero
        if let a = pts.first, let b = pts.last, b.1 > a.1 {
            let dt = CGFloat(b.1 - a.1)
            v = CGVector(dx: (b.0.x - a.0.x) / dt, dy: (b.0.y - a.0.y) / dt)
        }
        samples = []
        onRelease?(v)
    }
}
