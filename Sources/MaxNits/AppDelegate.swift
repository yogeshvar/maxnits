import AppKit
import ServiceManagement

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private enum DefaultsKey {
        static let boost = "boost"
        static let boostEnabled = "boostEnabled"
        static let pauseOnBattery = "pauseOnBattery"
    }

    private let controller = BrightnessController()
    private let hud = HUDController()

    private var statusItem: NSStatusItem!
    private var statusInfoItem: NSMenuItem!
    private var toggleItem: NSMenuItem!
    private var pauseOnBatteryItem: NSMenuItem!
    private var launchAtLoginItem: NSMenuItem!
    private var slider: NSSlider!

    private var boostPercent: Int {
        Int((controller.boost * 100).rounded())
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let defaults = UserDefaults.standard
        if defaults.object(forKey: DefaultsKey.boost) != nil {
            controller.boost = defaults.double(forKey: DefaultsKey.boost)
        }
        controller.pauseOnBattery = defaults.bool(forKey: DefaultsKey.pauseOnBattery)

        controller.onPauseStateChange = { [weak self] paused in
            guard let self else { return }
            if paused {
                self.hud.showPaused(reason: PowerMonitor.pauseReason)
            } else {
                self.hud.showResumed(percent: self.boostPercent)
            }
            self.updateStatusIcon()
        }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        updateStatusIcon()

        let menu = NSMenu()
        menu.delegate = self

        statusInfoItem = NSMenuItem(title: controller.statusDescription, action: nil, keyEquivalent: "")
        statusInfoItem.isEnabled = false
        menu.addItem(statusInfoItem)
        menu.addItem(.separator())

        toggleItem = NSMenuItem(title: "Boost Brightness", action: #selector(toggleBoost), keyEquivalent: "b")
        toggleItem.target = self
        menu.addItem(toggleItem)

        menu.addItem(sliderMenuItem())
        menu.addItem(.separator())

        pauseOnBatteryItem = NSMenuItem(title: "Pause on Battery", action: #selector(togglePauseOnBattery), keyEquivalent: "")
        pauseOnBatteryItem.target = self
        pauseOnBatteryItem.toolTip = "Battery Guard: automatically pause the boost when unplugged. Low Power Mode always pauses."
        menu.addItem(pauseOnBatteryItem)

        launchAtLoginItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        launchAtLoginItem.target = self
        menu.addItem(launchAtLoginItem)

        menu.addItem(.separator())
        let quitItem = NSMenuItem(title: "Quit MaxNits", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quitItem)

        statusItem.menu = menu

        // Restore the boost if it was on last time.
        if defaults.bool(forKey: DefaultsKey.boostEnabled) {
            controller.enable()
            updateStatusIcon()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller.disable()
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        statusInfoItem.title = controller.statusDescription
        toggleItem.state = controller.isEnabled ? .on : .off
        pauseOnBatteryItem.state = controller.pauseOnBattery ? .on : .off
        launchAtLoginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        slider.doubleValue = controller.boost
    }

    // MARK: - Actions

    @objc private func toggleBoost() {
        if controller.isEnabled {
            controller.disable()
            hud.showOff()
        } else {
            controller.enable()
            if controller.isPausedByPower {
                hud.showPaused(reason: PowerMonitor.pauseReason)
            } else {
                hud.showBoost(percent: boostPercent)
            }
        }
        UserDefaults.standard.set(controller.isEnabled, forKey: DefaultsKey.boostEnabled)
        updateStatusIcon()
    }

    @objc private func sliderChanged(_ sender: NSSlider) {
        controller.boost = sender.doubleValue
        UserDefaults.standard.set(controller.boost, forKey: DefaultsKey.boost)
        if controller.isEnabled && !controller.isPausedByPower {
            hud.showBoost(percent: boostPercent)
        }
    }

    @objc private func togglePauseOnBattery() {
        controller.pauseOnBattery.toggle()
        UserDefaults.standard.set(controller.pauseOnBattery, forKey: DefaultsKey.pauseOnBattery)
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            // Registration only works when running from a proper .app bundle.
            let alert = NSAlert()
            alert.messageText = "Couldn't change Launch at Login"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }

    // MARK: - UI helpers

    private func sliderMenuItem() -> NSMenuItem {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 220, height: 30))
        slider = NSSlider(value: controller.boost, minValue: 0.0, maxValue: 1.0,
                          target: self, action: #selector(sliderChanged(_:)))
        slider.frame = NSRect(x: 20, y: 4, width: 180, height: 22)
        slider.isContinuous = true
        container.addSubview(slider)

        let item = NSMenuItem()
        item.view = container
        return item
    }

    private func updateStatusIcon() {
        let symbol: String
        if controller.isEnabled {
            symbol = controller.isPausedByPower ? "sun.min" : "sun.max.fill"
        } else {
            symbol = "sun.max"
        }
        statusItem.button?.image = NSImage(
            systemSymbolName: symbol,
            accessibilityDescription: "MaxNits"
        )
    }
}
