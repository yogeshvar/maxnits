import AppKit
import Metal
import QuartzCore

/// A 1x1 px borderless window that renders a single pixel brighter than SDR white.
/// Its only job is to make macOS switch the display into EDR mode, which unlocks
/// brightness headroom above the standard 600-nit SDR ceiling.
@MainActor
final class OverlayWindowController {
    private let window: NSWindow
    private let overlayView: EDRPixelView

    init(screen: NSScreen) {
        let size: CGFloat = 1
        // Tucked into the top-right corner of the screen.
        let frame = NSRect(
            x: screen.frame.maxX - size,
            y: screen.frame.maxY - size,
            width: size,
            height: size
        )

        window = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.level = .screenSaver
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.stationary, .canJoinAllSpaces, .ignoresCycle, .fullScreenAuxiliary]
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        // Keep the bright pixel out of screenshots and screen recordings.
        window.sharingType = .none

        overlayView = EDRPixelView(frame: NSRect(origin: .zero, size: frame.size))
        window.contentView = overlayView
        window.orderFrontRegardless()
        overlayView.render()
    }

    /// Re-render the EDR pixel (cheap; called periodically so EDR stays active
    /// across display sleep, reconfiguration, etc.).
    func render() {
        overlayView.render()
    }

    func close() {
        window.close()
    }
}

/// Renders one pixel with a color component value above 1.0 into an
/// EDR-enabled CAMetalLayer.
private final class EDRPixelView: NSView {
    /// Requested brightness of the pixel in extended range. Anything meaningfully
    /// above 1.0 activates EDR; the OS clamps it to the display's real headroom.
    private static let edrValue = 2.0

    private let metalLayer = CAMetalLayer()
    private let device = MTLCreateSystemDefaultDevice()
    private lazy var commandQueue = device?.makeCommandQueue()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        metalLayer.device = device
        metalLayer.pixelFormat = .rgba16Float
        metalLayer.colorspace = CGColorSpace(name: CGColorSpace.extendedLinearDisplayP3)
        metalLayer.wantsExtendedDynamicRangeContent = true
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
        let v = Self.edrValue
        pass.colorAttachments[0].clearColor = MTLClearColor(red: v, green: v, blue: v, alpha: 1.0)

        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return }
        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}
