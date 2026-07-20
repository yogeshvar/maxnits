import AppKit

/// A translucent HUD that appears in the center of the screen when the boost
/// state changes — like the native volume/brightness bezel, but ours.
@MainActor
final class HUDController {
    private static let size = NSSize(width: 200, height: 180)
    private static let visibleDuration: TimeInterval = 1.1
    private static let fadeDuration: TimeInterval = 0.35

    private let panel: NSPanel
    private let iconView: NSImageView
    private let label: NSTextField
    private var hideTimer: Timer?

    init() {
        panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: Self.size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        panel.isReleasedWhenClosed = false

        let effectView = NSVisualEffectView(frame: NSRect(origin: .zero, size: Self.size))
        effectView.material = .hudWindow
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        effectView.wantsLayer = true
        effectView.layer?.cornerRadius = 24
        effectView.layer?.masksToBounds = true

        iconView = NSImageView(frame: NSRect(x: 0, y: 62, width: Self.size.width, height: 90))
        iconView.imageAlignment = .alignCenter
        iconView.contentTintColor = .labelColor

        label = NSTextField(labelWithString: "")
        label.frame = NSRect(x: 0, y: 26, width: Self.size.width, height: 22)
        label.alignment = .center
        label.font = .systemFont(ofSize: 15, weight: .medium)
        label.textColor = .labelColor

        effectView.addSubview(iconView)
        effectView.addSubview(label)
        panel.contentView = effectView
    }

    func showBoost(percent: Int) {
        show(symbol: "sun.max.fill", text: "Boost \(percent)%")
    }

    func showOff() {
        show(symbol: "sun.min", text: "Boost Off")
    }

    func showPaused(reason: String) {
        show(symbol: "battery.75percent", text: "Paused — \(reason)")
    }

    func showResumed(percent: Int) {
        show(symbol: "sun.max.fill", text: "Resumed — Boost \(percent)%")
    }

    private func show(symbol: String, text: String) {
        let config = NSImage.SymbolConfiguration(pointSize: 58, weight: .regular)
        iconView.image = NSImage(systemSymbolName: symbol, accessibilityDescription: text)?
            .withSymbolConfiguration(config)
        label.stringValue = text

        if let screen = NSScreen.main {
            let origin = NSPoint(
                x: screen.frame.midX - Self.size.width / 2,
                y: screen.frame.midY - Self.size.height / 2
            )
            panel.setFrameOrigin(origin)
        }

        hideTimer?.invalidate()
        panel.alphaValue = 1
        panel.orderFrontRegardless()

        let timer = Timer(timeInterval: Self.visibleDuration, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.fadeOut()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        hideTimer = timer
    }

    private func fadeOut() {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.fadeDuration
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            Task { @MainActor in
                guard let self, self.panel.alphaValue == 0 else { return }
                self.panel.orderOut(nil)
            }
        }
    }
}
