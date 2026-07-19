import AppKit
import ServiceManagement

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let controller = BrightnessController()

    private var statusItem: NSStatusItem!
    private var statusInfoItem: NSMenuItem!
    private var toggleItem: NSMenuItem!
    private var launchAtLoginItem: NSMenuItem!
    private var slider: NSSlider!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

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
        let quitItem = NSMenuItem(title: "Quit Overbright", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller.disable()
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        statusInfoItem.title = controller.statusDescription
        toggleItem.state = controller.isEnabled ? .on : .off
        launchAtLoginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }

    // MARK: - Actions

    @objc private func toggleBoost() {
        if controller.isEnabled {
            controller.disable()
        } else {
            controller.enable()
        }
        updateStatusIcon()
    }

    @objc private func sliderChanged(_ sender: NSSlider) {
        controller.boost = sender.doubleValue
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
        let symbol = controller.isEnabled ? "sun.max.fill" : "sun.max"
        statusItem.button?.image = NSImage(
            systemSymbolName: symbol,
            accessibilityDescription: "Overbright"
        )
    }
}
