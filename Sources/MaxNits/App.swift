import AppKit
import Carbon.HIToolbox

@main
struct MaxNitsApp {
    @MainActor
    static func main() {
        // `maxnits --status` prints EDR info for each display and exits.
        // Useful for checking whether a display can actually go above SDR brightness.
        if CommandLine.arguments.contains("--status") {
            for screen in NSScreen.screens {
                let current = screen.maximumExtendedDynamicRangeColorComponentValue
                let potential = screen.maximumPotentialExtendedDynamicRangeColorComponentValue
                print("\(screen.localizedName): current EDR headroom \(String(format: "%.2f", current))x, potential \(String(format: "%.2f", potential))x")
            }
            exit(0)
        }

        // `maxnits --hotkeytest` registers ⌘F1/⌘F2 and reports whether the
        // registration itself succeeded (i.e. nothing else on the system
        // already claimed that combination), independent of actually
        // pressing the keys.
        if CommandLine.arguments.contains("--hotkeytest") {
            let manager = HotKeyManager()
            let okIncrease = manager.register(keyCode: UInt32(kVK_F2), modifiers: UInt32(cmdKey)) {
                print("⌘F2 fired")
            }
            let okDecrease = manager.register(keyCode: UInt32(kVK_F1), modifiers: UInt32(cmdKey)) {
                print("⌘F1 fired")
            }
            print("⌘F2 (increase) registered: \(okIncrease)")
            print("⌘F1 (decrease) registered: \(okDecrease)")
            exit(okIncrease && okDecrease ? 0 : 1)
        }

        // `maxnits --test` enables the boost for 6 seconds, reports whether
        // EDR engaged, then restores and exits. Handy sanity check.
        if CommandLine.arguments.contains("--test") {
            let app = NSApplication.shared
            app.setActivationPolicy(.accessory)
            let controller = BrightnessController()
            controller.enable()
            print("Boost enabled; watching EDR headroom for 6 seconds...")
            var ticks = 0
            Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { timer in
                Task { @MainActor in
                    ticks += 1
                    for screen in NSScreen.screens {
                        let headroom = screen.maximumExtendedDynamicRangeColorComponentValue
                        print("t=\(ticks)s \(screen.localizedName): headroom \(String(format: "%.2f", headroom))x")
                    }
                    if ticks >= 6 {
                        timer.invalidate()
                        controller.disable()
                        print("Restored. Test complete.")
                        exit(0)
                    }
                }
            }
            app.run()
        }

        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}
