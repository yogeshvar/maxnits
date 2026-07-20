import AppKit
import Carbon.HIToolbox
import ServiceManagement

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private enum DefaultsKey {
        static let boost = "boost"
        static let boostEnabled = "boostEnabled"
    }

    private static let boostStep = 0.1

    private let controller = BrightnessController()
    private let hud = HUDController()
    private let hotKeys = HotKeyManager()

    private var statusItem: NSStatusItem!
    private var statusInfoItem: NSMenuItem!
    private var toggleItem: NSMenuItem!
    private var launchAtLoginItem: NSMenuItem!
    private var slider: NSSlider!
    private var percentLabel: NSTextField!

    private var boostPercent: Int {
        Int((controller.boost * 100).rounded())
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let defaults = UserDefaults.standard
        if defaults.object(forKey: DefaultsKey.boost) != nil {
            controller.boost = defaults.double(forKey: DefaultsKey.boost)
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

        hotKeys.register(keyCode: UInt32(kVK_F2), modifiers: UInt32(cmdKey)) { [weak self] in
            self?.increaseBoost()
        }
        hotKeys.register(keyCode: UInt32(kVK_F1), modifiers: UInt32(cmdKey)) { [weak self] in
            self?.decreaseBoost()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller.disable()
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        statusInfoItem.title = controller.statusDescription
        toggleItem.state = controller.isEnabled ? .on : .off
        launchAtLoginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        slider.doubleValue = controller.boost
        percentLabel.stringValue = "\(boostPercent)%"
    }

    // MARK: - Actions

    @objc private func toggleBoost() {
        if controller.isEnabled {
            controller.disable()
            hud.showOff()
        } else {
            controller.enable()
            hud.showBoost(percent: boostPercent)
        }
        UserDefaults.standard.set(controller.isEnabled, forKey: DefaultsKey.boostEnabled)
        updateStatusIcon()
    }

    @objc private func sliderChanged(_ sender: NSSlider) {
        controller.boost = sender.doubleValue
        UserDefaults.standard.set(controller.boost, forKey: DefaultsKey.boost)
        percentLabel.stringValue = "\(boostPercent)%"
        if controller.isEnabled {
            hud.showBoost(percent: boostPercent)
        }
    }

    private func increaseBoost() {
        if !controller.isEnabled {
            controller.enable()
            UserDefaults.standard.set(true, forKey: DefaultsKey.boostEnabled)
        }
        controller.boost = min(1.0, controller.boost + Self.boostStep)
        UserDefaults.standard.set(controller.boost, forKey: DefaultsKey.boost)
        hud.showBoost(percent: boostPercent)
        updateStatusIcon()
    }

    private func decreaseBoost() {
        guard controller.isEnabled else { return }
        controller.boost = max(0.0, controller.boost - Self.boostStep)
        UserDefaults.standard.set(controller.boost, forKey: DefaultsKey.boost)
        hud.showBoost(percent: boostPercent)
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
        slider.frame = NSRect(x: 20, y: 4, width: 148, height: 22)
        slider.isContinuous = true
        container.addSubview(slider)

        percentLabel = NSTextField(labelWithString: "\(boostPercent)%")
        percentLabel.frame = NSRect(x: 174, y: 4, width: 34, height: 18)
        percentLabel.alignment = .right
        percentLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        percentLabel.textColor = .secondaryLabelColor
        container.addSubview(percentLabel)

        let item = NSMenuItem()
        item.view = container
        item.toolTip = "⌘F1 to dim, ⌘F2 to brighten — works anywhere, even when this menu is closed."
        return item
    }

    private func updateStatusIcon() {
        statusItem.button?.image = NSImage(
            systemSymbolName: controller.isEnabled ? "sun.max.fill" : "sun.max",
            accessibilityDescription: "MaxNits"
        )
    }
}
