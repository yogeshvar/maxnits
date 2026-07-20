import AppKit
import Metal
import QuartzCore

/// The two overlay windows that do the actual brightness work:
///
/// - An "igniter": a 1x1 px window rendering a pixel brighter than SDR white,
///   which makes macOS switch the display into EDR mode and unlock headroom.
/// - A "booster": a fullscreen window whose layer uses multiply compositing,
///   so the WindowServer multiplies everything beneath it by a constant
///   factor above 1.0 — mapped into the unlocked EDR range.
@MainActor
final class OverlayWindowController {
    enum Kind {
        case igniter
        case booster
    }

    private let window: NSWindow
    private let overlayView: ConstantEDRView
    private let kind: Kind

    init(screen: NSScreen, kind: Kind = .igniter) {
        self.kind = kind

        let frame: NSRect
        switch kind {
        case .igniter:
            // Tucked into the top-right corner of the screen.
            frame = NSRect(x: screen.frame.maxX - 1, y: screen.frame.maxY - 1, width: 1, height: 1)
        case .booster:
            frame = screen.frame
        }

        window = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        switch kind {
        case .igniter:
            window.level = .screenSaver
        case .booster:
            // Above everything, including the menu bar.
            window.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
        }
        window.collectionBehavior = [.stationary, .canJoinAllSpaces, .ignoresCycle, .fullScreenAuxiliary]
        window.ignoresMouseEvents = true
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        // Keep the overlay out of screenshots and screen recordings.
        window.sharingType = .none

        overlayView = ConstantEDRView(
            frame: NSRect(origin: .zero, size: frame.size),
            multiplyCompositing: kind == .booster
        )
        window.contentView = overlayView
        window.orderFrontRegardless()
        overlayView.render()
    }

    /// The constant color the overlay renders. For the booster this is the
    /// brightness multiplier applied to everything beneath it.
    func setValue(_ value: Double) {
        overlayView.value = value
    }

    /// Keep the window matched to its screen and re-render (cheap; called
    /// periodically so EDR stays active across display changes).
    func refresh(screen: NSScreen) {
        if kind == .booster, window.frame != screen.frame {
            window.setFrame(screen.frame, display: true)
        }
        overlayView.render()
    }

    func close() {
        window.close()
    }
}

/// Renders a single constant extended-range color into an EDR-enabled
/// CAMetalLayer. The drawable is one pixel; the layer stretches it.
private final class ConstantEDRView: NSView {
    var value: Double = 2.0 {
        didSet {
            if abs(value - oldValue) > 0.001 { render() }
        }
    }

    private let metalLayer = CAMetalLayer()
    private let device = MTLCreateSystemDefaultDevice()
    private lazy var commandQueue = device?.makeCommandQueue()

    init(frame frameRect: NSRect, multiplyCompositing: Bool) {
        super.init(frame: frameRect)
        wantsLayer = true
        metalLayer.device = device
        metalLayer.pixelFormat = .rgba16Float
        metalLayer.colorspace = CGColorSpace(name: CGColorSpace.extendedLinearSRGB)
        metalLayer.wantsExtendedDynamicRangeContent = true
        metalLayer.isOpaque = false
        metalLayer.drawableSize = CGSize(width: 1, height: 1)
        if multiplyCompositing {
            metalLayer.compositingFilter = "multiply"
        }
        layer = metalLayer
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func render() {
        guard let commandQueue,
              let drawable = metalLayer.nextDrawable(),
              let commandBuffer = commandQueue.makeCommandBuffer() else {
            return
        }

        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = drawable.texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = MTLClearColor(red: value, green: value, blue: value, alpha: 1.0)

        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return }
        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}
