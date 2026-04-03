import AppKit

// --- Eye drawing ---

func drawEyes(size: NSSize, mouseScreen: NSPoint, buttonScreenFrame: NSRect, blinkProgress: CGFloat) -> NSImage {
    let image = NSImage(size: size)
    image.lockFocus()

    let eyeRadius: CGFloat = size.height / 2 - 1
    let pupilRadius: CGFloat = eyeRadius * 0.38

    // Fixed gap between eyes instead of anchoring to the edges
    let centerY = size.height / 2
    let spacing: CGFloat = 3   // gap between the two eyes
    let leftCenter  = NSPoint(x: size.width / 2 - eyeRadius - spacing / 2, y: centerY)
    let rightCenter = NSPoint(x: size.width / 2 + eyeRadius + spacing / 2, y: centerY)

    for localCenter in [leftCenter, rightCenter] {
        let screenCenter = NSPoint(
            x: buttonScreenFrame.minX + localCenter.x,
            y: buttonScreenFrame.minY + localCenter.y
        )

        let dx = mouseScreen.x - screenCenter.x
        let dy = mouseScreen.y - screenCenter.y
        let dist = sqrt(dx * dx + dy * dy)
        let maxOffset = eyeRadius - pupilRadius - 1

        let offset: NSPoint
        if dist > 0.1 {
            let scale = min(maxOffset / dist, 1.0)
            offset = NSPoint(x: dx * scale, y: dy * scale)
        } else {
            offset = .zero
        }

        // Blink effect: squish eye height vertically
        // blinkProgress 0 = fully open, 1 = fully closed
        let yScale = 1.0 - blinkProgress
        let visibleEyeH = max(eyeRadius * 2 * yScale, 0.5)

        let eyeRect = NSRect(
            x: localCenter.x - eyeRadius,
            y: localCenter.y - visibleEyeH / 2,
            width: eyeRadius * 2,
            height: visibleEyeH
        )
        let eyePath = NSBezierPath(ovalIn: eyeRect)
        NSColor.white.setFill()
        eyePath.fill()
        NSColor.black.withAlphaComponent(0.7).setStroke()
        eyePath.lineWidth = 1
        eyePath.stroke()

        // Only draw the pupil when the eye is not nearly closed
        if blinkProgress < 0.85 {
            let pupilScale = 1.0 - blinkProgress * 0.8
            let pr = pupilRadius * pupilScale
            let px = localCenter.x + offset.x - pr
            let py = localCenter.y + offset.y * yScale - pr
            let pupilRect = NSRect(x: px, y: py, width: pr * 2, height: pr * 2)
            NSColor.black.setFill()
            NSBezierPath(ovalIn: pupilRect).fill()
        }
    }

    image.unlockFocus()
    image.isTemplate = false
    return image
}

// --- Blink state machine ---

enum BlinkState {
    case open
    case closing
    case opening
}

// --- App ---

final class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var timer: Timer?

    var blinkState: BlinkState = .open
    var blinkProgress: CGFloat = 0.0   // 0 = fully open, 1 = fully closed

    // ~90ms per direction at 30fps
    let blinkSpeed: CGFloat = 1.0 / 2.7

    // Poisson process: average one blink every 10s → per-frame probability
    let blinkProbPerFrame: Double = 1.0 - exp(-1.0 / (10.0 * 30.0))

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        guard let button = statusItem.button else { return }
        button.imageScaling = .scaleProportionallyDown

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "macEyes", action: nil, keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu

        updateEyes()

        // Refresh at ~30 fps
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    func tick() {
        // Advance blink state machine
        switch blinkState {
        case .open:
            if Double.random(in: 0..<1) < blinkProbPerFrame {
                blinkState = .closing
            }
        case .closing:
            blinkProgress += blinkSpeed
            if blinkProgress >= 1.0 {
                blinkProgress = 1.0
                blinkState = .opening
            }
        case .opening:
            blinkProgress -= blinkSpeed
            if blinkProgress <= 0.0 {
                blinkProgress = 0.0
                blinkState = .open
            }
        }

        updateEyes()
    }

    func updateEyes() {
        guard let button = statusItem.button,
              let window = button.window else { return }

        let buttonScreenFrame = window.convertToScreen(button.frame)
        let iconSize = NSSize(width: 34, height: 16)
        let mouse = NSEvent.mouseLocation

        // The image is centered within the button — compute the actual image origin in screen coordinates
        let imageScreenFrame = NSRect(
            x: buttonScreenFrame.midX - iconSize.width / 2,
            y: buttonScreenFrame.midY - iconSize.height / 2,
            width: iconSize.width,
            height: iconSize.height
        )

        let image = drawEyes(
            size: iconSize,
            mouseScreen: mouse,
            buttonScreenFrame: imageScreenFrame,
            blinkProgress: blinkProgress
        )
        button.image = image
    }
}

// --- Entry point ---

let app = NSApplication.shared
app.setActivationPolicy(.accessory)   // no Dock icon
let delegate = AppDelegate()
app.delegate = delegate
app.run()
