import AppKit

@main
struct MaxNitsApp {
    @MainActor
    static func main() {
        let arguments = Array(CommandLine.arguments.dropFirst())

        // `maxnits --status` prints EDR info for each display and exits.
        // Useful for checking whether a display can actually go above SDR brightness.
        if arguments.contains("--status") {
            for screen in NSScreen.screens {
                let current = screen.maximumExtendedDynamicRangeColorComponentValue
                let potential = screen.maximumPotentialExtendedDynamicRangeColorComponentValue
                print("\(screen.localizedName): current EDR headroom \(String(format: "%.2f", current))x, potential \(String(format: "%.2f", potential))x")
            }
            exit(0)
        }

        // `maxnits --test` enables the boost for 6 seconds, reports whether
        // EDR engaged, then restores and exits. Handy sanity check.
        if arguments.contains("--test") {
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

        if arguments.contains("-h") || arguments.contains("--help") {
            _ = CLIClient.run([])
            exit(0)
        }

        guard let first = arguments.first else {
            Daemon.run()
        }

        switch first {
        case "daemon":
            Daemon.run()
        case "enable-login":
            exit(LoginItem.enable())
        case "disable-login":
            exit(LoginItem.disable())
        default:
            exit(CLIClient.run(arguments))
        }
    }
}
