import AppKit

/// Boosts perceived brightness by activating EDR (via tiny "igniter" overlay
/// windows) and multiplying everything on screen by a factor above 1.0 (via
/// fullscreen multiply-compositing "booster" overlays).
///
/// Both overlays are ordinary windows owned by this process, so quitting or
/// crashing always returns the display to normal.
@MainActor
final class BrightnessController {
    /// A display is considered EDR-active once its reported headroom exceeds this.
    private static let hdrActiveThreshold: CGFloat = 1.05
    /// Re-render the booster only when the multiplier moved more than this.
    private static let valueTolerance: Double = 0.005

    private(set) var isEnabled = false

    /// True while the boost is temporarily suspended by Battery Guard.
    private(set) var isPausedByPower = false

    /// Called when Battery Guard pauses or resumes the boost.
    var onPauseStateChange: ((Bool) -> Void)?

    /// Battery Guard: when true, the boost pauses on battery power or in
    /// Low Power Mode and resumes automatically on AC power.
    var batteryGuard: Bool = false {
        didSet {
            if isEnabled { tick() }
        }
    }

    /// 0.0 ... 1.0 — how much of the available EDR headroom to use.
    var boost: Double = 1.0 {
        didSet {
            if isEnabled && !isPausedByPower { apply() }
        }
    }

    private var igniters: [CGDirectDisplayID: OverlayWindowController] = [:]
    private var boosters: [CGDirectDisplayID: OverlayWindowController] = [:]
    private var appliedValues: [CGDirectDisplayID: Double] = [:]
    private var refreshTimer: Timer?
    private var screenObserver: NSObjectProtocol?

    /// Human-readable status for the menu.
    var statusDescription: String {
        guard let screen = brightestCapableScreen() else {
            return "No EDR-capable display found"
        }
        if isEnabled && isPausedByPower {
            return "Paused — \(PowerMonitor.pauseReason)"
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
        tick()

        // Headroom appears asynchronously after the igniter first renders,
        // and it changes when the user moves the system brightness slider —
        // poll and adjust as needed.
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
                self?.tick()
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
        isPausedByPower = false
        suspendBoost()
    }

    // MARK: - Internals

    private func tick() {
        guard isEnabled else { return }

        let shouldPause = PowerMonitor.shouldPause(batteryGuard: batteryGuard)
        if shouldPause != isPausedByPower {
            isPausedByPower = shouldPause
            if shouldPause {
                suspendBoost()
            }
            onPauseStateChange?(shouldPause)
        }
        guard !isPausedByPower else { return }

        refreshOverlays()
        apply()
    }

    /// Close all overlay windows without touching `isEnabled`.
    private func suspendBoost() {
        for overlay in igniters.values {
            overlay.close()
        }
        for overlay in boosters.values {
            overlay.close()
        }
        igniters.removeAll()
        boosters.removeAll()
        appliedValues.removeAll()
    }

    /// Keep one igniter and one booster per EDR-capable screen.
    private func refreshOverlays() {
        var seen = Set<CGDirectDisplayID>()
        for screen in NSScreen.screens {
            guard let displayId = screen.displayId else { continue }
            seen.insert(displayId)
            guard screen.maximumPotentialExtendedDynamicRangeColorComponentValue > Self.hdrActiveThreshold else { continue }
            if igniters[displayId] == nil {
                igniters[displayId] = OverlayWindowController(screen: screen, kind: .igniter)
            }
            if boosters[displayId] == nil {
                let booster = OverlayWindowController(screen: screen, kind: .booster)
                booster.setValue(1.0)
                boosters[displayId] = booster
            }
            igniters[displayId]?.refresh(screen: screen)
            boosters[displayId]?.refresh(screen: screen)
        }
        for (displayId, overlay) in igniters where !seen.contains(displayId) {
            overlay.close()
            igniters.removeValue(forKey: displayId)
        }
        for (displayId, overlay) in boosters where !seen.contains(displayId) {
            overlay.close()
            boosters.removeValue(forKey: displayId)
            appliedValues.removeValue(forKey: displayId)
        }
    }

    /// Update each booster's multiplier from the current headroom and boost level.
    private func apply() {
        for screen in NSScreen.screens {
            guard let displayId = screen.displayId,
                  let booster = boosters[displayId] else { continue }
            let headroom = Double(screen.maximumExtendedDynamicRangeColorComponentValue)
            // Multiplying by more than the headroom would clip; stay within it.
            let value = 1.0 + max(headroom - 1.0, 0) * boost
            if let applied = appliedValues[displayId], abs(applied - value) < Self.valueTolerance {
                continue
            }
            booster.setValue(value)
            appliedValues[displayId] = value
        }
    }

    private func brightestCapableScreen() -> NSScreen? {
        NSScreen.screens
            .filter { $0.maximumPotentialExtendedDynamicRangeColorComponentValue > 1.0 }
            .max { $0.maximumPotentialExtendedDynamicRangeColorComponentValue < $1.maximumPotentialExtendedDynamicRangeColorComponentValue }
            ?? NSScreen.main
    }
}

extension NSScreen {
    var displayId: CGDirectDisplayID? {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }
}
