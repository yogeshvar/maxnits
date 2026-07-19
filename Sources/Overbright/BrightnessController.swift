import AppKit
import CoreGraphics

/// Boosts perceived brightness by activating EDR (via tiny overlay windows) and
/// then scaling the display gamma tables above 1.0 so all SDR content maps into
/// the unlocked extended range.
///
/// Gamma tables set with CGSetDisplayTransferByTable are per-process and are
/// automatically restored by macOS when the process exits, so a crash can never
/// leave the display in a broken state.
@MainActor
final class BrightnessController {
    /// A display is considered EDR-active once its reported headroom exceeds this.
    private static let hdrActiveThreshold: CGFloat = 1.05
    /// Reapply gamma only when the target factor moved more than this.
    private static let factorTolerance: CGFloat = 0.01

    private(set) var isEnabled = false

    /// 0.0 ... 1.0 — how much of the available EDR headroom to use.
    var boost: Double = 1.0 {
        didSet {
            if isEnabled { apply() }
        }
    }

    private var overlays: [CGDirectDisplayID: OverlayWindowController] = [:]
    private var originalTables: [CGDirectDisplayID: GammaTable] = [:]
    private var appliedFactors: [CGDirectDisplayID: CGFloat] = [:]
    private var refreshTimer: Timer?
    private var screenObserver: NSObjectProtocol?

    /// Human-readable status for the menu.
    var statusDescription: String {
        guard let screen = brightestCapableScreen() else {
            return "No EDR-capable display found"
        }
        let headroom = screen.maximumExtendedDynamicRangeColorComponentValue
        let potential = screen.maximumPotentialExtendedDynamicRangeColorComponentValue
        if isEnabled && headroom > Self.hdrActiveThreshold {
            return String(format: "Boosting %@ (%.1fx headroom)", screen.localizedName, headroom)
        }
        if potential > Self.hdrActiveThreshold {
            return String(format: "%@: up to %.1fx available", screen.localizedName, potential)
        }
        return "Display has no brightness headroom"
    }

    func enable() {
        guard !isEnabled else { return }
        isEnabled = true
        refreshOverlays()
        apply()

        // Headroom appears asynchronously after the EDR overlay first renders,
        // and it changes when the user moves the system brightness slider —
        // poll and reapply as needed.
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer

        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isEnabled else { return }
                self.refreshOverlays()
                self.apply()
            }
        }
    }

    func disable() {
        guard isEnabled else { return }
        isEnabled = false
        refreshTimer?.invalidate()
        refreshTimer = nil
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
            self.screenObserver = nil
        }
        for overlay in overlays.values {
            overlay.close()
        }
        overlays.removeAll()
        originalTables.removeAll()
        appliedFactors.removeAll()
        CGDisplayRestoreColorSyncSettings()
    }

    // MARK: - Internals

    private func tick() {
        guard isEnabled else { return }
        refreshOverlays()
        for overlay in overlays.values {
            overlay.render()
        }
        apply()
    }

    /// Keep exactly one EDR-activating overlay per capable screen.
    private func refreshOverlays() {
        var seen = Set<CGDirectDisplayID>()
        for screen in NSScreen.screens {
            guard let displayId = screen.displayId else { continue }
            seen.insert(displayId)
            guard screen.maximumPotentialExtendedDynamicRangeColorComponentValue > Self.hdrActiveThreshold else { continue }
            if overlays[displayId] == nil {
                overlays[displayId] = OverlayWindowController(screen: screen)
            }
        }
        for (displayId, overlay) in overlays where !seen.contains(displayId) {
            overlay.close()
            overlays.removeValue(forKey: displayId)
            originalTables.removeValue(forKey: displayId)
            appliedFactors.removeValue(forKey: displayId)
        }
    }

    private func apply() {
        for screen in NSScreen.screens {
            guard let displayId = screen.displayId else { continue }
            let headroom = screen.maximumExtendedDynamicRangeColorComponentValue
            guard headroom > Self.hdrActiveThreshold else { continue }

            if originalTables[displayId] == nil {
                originalTables[displayId] = GammaTable(displayId: displayId)
            }
            guard let original = originalTables[displayId] else { continue }

            let factor = 1.0 + (headroom - 1.0) * CGFloat(boost)
            if let applied = appliedFactors[displayId], abs(applied - factor) < Self.factorTolerance {
                continue
            }
            original.scaled(by: factor, cappedAt: headroom).apply(to: displayId)
            appliedFactors[displayId] = factor
        }
    }

    private func brightestCapableScreen() -> NSScreen? {
        NSScreen.screens
            .filter { $0.maximumPotentialExtendedDynamicRangeColorComponentValue > 1.0 }
            .max { $0.maximumPotentialExtendedDynamicRangeColorComponentValue < $1.maximumPotentialExtendedDynamicRangeColorComponentValue }
            ?? NSScreen.main
    }
}

/// A captured RGB gamma lookup table for one display.
private struct GammaTable {
    var red: [CGGammaValue]
    var green: [CGGammaValue]
    var blue: [CGGammaValue]

    init?(displayId: CGDirectDisplayID) {
        let capacity = CGDisplayGammaTableCapacity(displayId)
        guard capacity > 0 else { return nil }
        var red = [CGGammaValue](repeating: 0, count: Int(capacity))
        var green = [CGGammaValue](repeating: 0, count: Int(capacity))
        var blue = [CGGammaValue](repeating: 0, count: Int(capacity))
        var sampleCount: UInt32 = 0
        guard CGGetDisplayTransferByTable(displayId, capacity, &red, &green, &blue, &sampleCount) == .success,
              sampleCount > 0 else {
            return nil
        }
        self.red = Array(red.prefix(Int(sampleCount)))
        self.green = Array(green.prefix(Int(sampleCount)))
        self.blue = Array(blue.prefix(Int(sampleCount)))
    }

    /// Multiply every entry by `factor`. Values above 1.0 are what push SDR
    /// content into the EDR range; `cap` avoids requesting more than the
    /// display can currently show.
    func scaled(by factor: CGFloat, cappedAt cap: CGFloat) -> GammaTable {
        var result = self
        let f = Float(factor)
        let limit = Float(cap)
        result.red = red.map { min($0 * f, limit) }
        result.green = green.map { min($0 * f, limit) }
        result.blue = blue.map { min($0 * f, limit) }
        return result
    }

    func apply(to displayId: CGDirectDisplayID) {
        var red = self.red
        var green = self.green
        var blue = self.blue
        CGSetDisplayTransferByTable(displayId, UInt32(red.count), &red, &green, &blue)
    }
}

extension NSScreen {
    var displayId: CGDirectDisplayID? {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }
}
