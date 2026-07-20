import AppKit
import Metal
import MetalKit
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
    private let kind: Kind
    private var igniterView: IgniterView?
    private var boosterView: BoosterView?

    init(screen: NSScreen, kind: Kind) {
        self.kind = kind

        let frame: NSRect
        let styleMask: NSWindow.StyleMask
        switch kind {
        case .igniter:
            // Tucked into the top-right corner of the screen.
            frame = NSRect(x: screen.frame.maxX - 1, y: screen.frame.maxY - 1, width: 1, height: 1)
            styleMask = []
        case .booster:
            frame = screen.frame
            styleMask = [.fullSizeContentView, .borderless]
        }

        window = NSWindow(contentRect: frame, styleMask: styleMask, backing: .buffered, defer: false)
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
        window.animationBehavior = .none
        window.hidesOnDeactivate = false
        window.isReleasedWhenClosed = false
        // Keep the overlay out of screenshots and screen recordings.
        window.sharingType = .none

        switch kind {
        case .igniter:
            let view = IgniterView(frame: NSRect(origin: .zero, size: frame.size))
            window.contentView = view
            igniterView = view
            window.orderFrontRegardless()
            view.render()
        case .booster:
            let view = BoosterView(frame: NSRect(origin: .zero, size: frame.size))
            window.contentView = view
            boosterView = view
            // Fade in once the first frame has actually been composited, to
            // avoid a one-frame flash of an unmultiplied fullscreen window.
            window.alphaValue = 0
            window.orderFrontRegardless()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak window] in
                window?.animator().alphaValue = 1
            }
        }
    }

    /// The constant color the overlay renders. For the booster this is the
    /// brightness multiplier applied to everything beneath it.
    func setValue(_ value: Double) {
        boosterView?.clearValue = value
    }

    /// Keep the window matched to its screen (cheap; called periodically so
    /// the overlay stays correctly positioned/sized across display changes).
    func refresh(screen: NSScreen) {
        switch kind {
        case .igniter:
            let idealOrigin = NSPoint(x: screen.frame.maxX - 1, y: screen.frame.maxY - 1)
            if window.frame.origin != idealOrigin {
                window.setFrameOrigin(idealOrigin)
            }
            igniterView?.render()
        case .booster:
            if window.frame != screen.frame {
                window.setFrame(screen.frame, display: true)
            }
        }
    }

    func close() {
        window.close()
    }
}

/// Renders a single EDR-bright pixel once, just enough to make macOS switch
/// the display into Extended Dynamic Range mode.
private final class IgniterView: NSView {
    private let metalLayer = CAMetalLayer()
    private let device = MTLCreateSystemDefaultDevice()
    private lazy var commandQueue = device?.makeCommandQueue()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        metalLayer.device = device
        metalLayer.pixelFormat = .rgba16Float
        metalLayer.colorspace = CGColorSpace(name: CGColorSpace.extendedLinearSRGB)
        metalLayer.wantsExtendedDynamicRangeContent = true
        metalLayer.isOpaque = false
        metalLayer.drawableSize = CGSize(width: 1, height: 1)
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
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 2.0, green: 2.0, blue: 2.0, alpha: 1.0)

        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return }
        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}

/// Continuously renders a constant extended-range color over the whole
/// screen with multiply compositing, so the WindowServer scales everything
/// beneath it by `clearValue`.
///
/// A single manually-presented drawable is not reliably kept composited by
/// the WindowServer — this needs to keep re-presenting frames, so it's built
/// on MTKView's own draw loop rather than one-shot rendering.
private final class BoosterView: MTKView, MTKViewDelegate {
    var clearValue: Double = 1.0

    private var queue: MTLCommandQueue?

    init(frame frameRect: NSRect) {
        super.init(frame: frameRect, device: MTLCreateSystemDefaultDevice())
        guard let device else {
            fatalError("No Metal device")
        }
        queue = device.makeCommandQueue()
        delegate = self
        colorPixelFormat = .rgba16Float
        colorspace = CGColorSpace(name: CGColorSpace.extendedLinearSRGB)
        autoResizeDrawable = true
        preferredFramesPerSecond = 5
        isPaused = false
        enableSetNeedsDisplay = false
        layer?.isOpaque = false
        if let metalLayer = layer as? CAMetalLayer {
            metalLayer.wantsExtendedDynamicRangeContent = true
            metalLayer.isOpaque = false
            metalLayer.compositingFilter = "multiply"
        }
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard let queue,
              let pass = view.currentRenderPassDescriptor,
              let drawable = view.currentDrawable,
              let commandBuffer = queue.makeCommandBuffer() else {
            return
        }
        let v = clearValue
        pass.colorAttachments[0].clearColor = MTLClearColor(red: v, green: v, blue: v, alpha: 1.0)

        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return }
        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}
