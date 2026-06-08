import Cocoa

/// How the bubble above the pet should look.
enum BubbleStyle { case typing, sleep, quote }

/// Draws the dinosaur sprite at `posX` (horizontal offset within the strip)
/// using the current grid, facing direction and pixel scale, plus optional
/// props (the prey it chases, the meat it eats) and a speech bubble above its
/// head (typed text, a quote, or "zzz" while asleep).
final class PetView: NSView {
    var posX: CGFloat = 0
    var bob: CGFloat = 0
    var facingRight = true
    var pixel: CGFloat = 4

    /// The pixel grid to render this frame. Set by the controller each tick.
    var grid: [String] = DinoPixelArt.stand

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

    private let palette: [Character: NSColor] = [
        "o": NSColor(srgbRed: 0.910, green: 0.392, blue: 0.165, alpha: 1), // orange body
        "O": NSColor(srgbRed: 0.969, green: 0.569, blue: 0.110, alpha: 1), // light orange
        "r": NSColor(srgbRed: 0.820, green: 0.318, blue: 0.282, alpha: 1), // red
        "d": NSColor(srgbRed: 0.659, green: 0.208, blue: 0.098, alpha: 1), // dark-red outline
        "y": NSColor(srgbRed: 0.980, green: 0.784, blue: 0.216, alpha: 1), // yellow belly
        "g": NSColor(srgbRed: 0.592, green: 0.671, blue: 0.271, alpha: 1), // green patch
        "b": NSColor(srgbRed: 0.176, green: 0.424, blue: 0.620, alpha: 1), // blue eye / feet
        "k": NSColor(srgbRed: 0.098, green: 0.098, blue: 0.098, alpha: 1), // black pupil / nostril
        "w": NSColor(srgbRed: 0.973, green: 0.973, blue: 0.973, alpha: 1), // eye white
        "C": NSColor(srgbRed: 0.588, green: 0.353, blue: 0.784, alpha: 1), // prey body (purple)
        "c": NSColor(srgbRed: 0.353, green: 0.196, blue: 0.510, alpha: 1), // prey outline
        "M": NSColor(srgbRed: 0.784, green: 0.220, blue: 0.239, alpha: 1), // meat
        "m": NSColor(srgbRed: 0.549, green: 0.129, blue: 0.149, alpha: 1), // meat edge
        "B": NSColor(srgbRed: 0.941, green: 0.910, blue: 0.831, alpha: 1), // bone
    ]

    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        if let preyGrid { drawGrid(preyGrid, originX: preyX, originY: 0, facingRight: preyFacingRight) }
        drawGrid(grid, originX: posX, originY: bob, facingRight: facingRight)
        if let foodGrid { drawGrid(foodGrid, originX: foodX, originY: foodY, facingRight: facingRight) }
        if let text = bubbleText, !text.isEmpty { drawBubble(text) }
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
        let spriteW = CGFloat(DinoPixelArt.width) * pixel
        let spriteH = CGFloat(DinoPixelArt.height) * pixel
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
}
