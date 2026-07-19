import AppKit

@main
struct OverbrightApp {
    @MainActor
    static func main() {
        // `overbright --status` prints EDR info for each display and exits.
        // Useful for checking whether a display can actually go above SDR brightness.
        if CommandLine.arguments.contains("--status") {
            for screen in NSScreen.screens {
                let current = screen.maximumExtendedDynamicRangeColorComponentValue
                let potential = screen.maximumPotentialExtendedDynamicRangeColorComponentValue
                print("\(screen.localizedName): current EDR headroom \(String(format: "%.2f", current))x, potential \(String(format: "%.2f", potential))x")
            }
            exit(0)
        }

        // `overbright --test` enables the boost for 6 seconds, reports whether
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
