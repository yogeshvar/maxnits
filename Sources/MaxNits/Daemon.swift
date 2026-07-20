import AppKit

/// The long-running background process: owns the brightness engine and the
/// on-screen HUD, and drives both from commands received over the IPC
/// socket. This replaces the old menu-bar `AppDelegate` — there is no menu,
/// no status item, no dropdown; the only UI is the transient HUD bezel.
@MainActor
enum Daemon {
    private enum DefaultsKey {
        static let boost = "boost"
        static let boostEnabled = "boostEnabled"
    }

    static func run() -> Never {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)

        if isatty(fileno(stdout)) != 0 {
            print("MaxNits daemon running — Ctrl+C to stop, or `maxnits quit` from another terminal.")
        }

        let controller = BrightnessController()
        let hud = HUDController()

        let defaults = UserDefaults.standard
        if defaults.object(forKey: DefaultsKey.boost) != nil {
            controller.boost = defaults.double(forKey: DefaultsKey.boost)
        }

        let serverBox = ServerBox()
        guard let server = IPCServer(handler: { command in
            handle(command, controller: controller, hud: hud, defaults: defaults, serverBox: serverBox)
        }) else {
            FileHandle.standardError.write(Data("Another MaxNits daemon is already running.\n".utf8))
            exit(1)
        }
        serverBox.server = server
        server.start()

        // Restore the boost if it was on last time.
        if defaults.bool(forKey: DefaultsKey.boostEnabled) {
            controller.enable()
        }

        app.run()
        fatalError("NSApplication.run() returned unexpectedly")
    }

    private static func percent(_ controller: BrightnessController) -> Int {
        Int((controller.boost * 100).rounded())
    }

    @MainActor
    private final class ServerBox {
        var server: IPCServer?
    }

    private static func handle(
        _ command: Command,
        controller: BrightnessController,
        hud: HUDController,
        defaults: UserDefaults,
        serverBox: ServerBox
    ) -> String {
        switch command {
        case .on:
            controller.enable()
            defaults.set(true, forKey: DefaultsKey.boostEnabled)
            hud.showBoost(percent: percent(controller))
            return "OK ON \(percent(controller))"

        case .off:
            controller.disable()
            defaults.set(false, forKey: DefaultsKey.boostEnabled)
            hud.showOff()
            return "OK OFF"

        case .set(let n):
            let clamped = max(0, min(100, n))
            controller.boost = Double(clamped) / 100.0
            defaults.set(controller.boost, forKey: DefaultsKey.boost)
            if !controller.isEnabled {
                controller.enable()
                defaults.set(true, forKey: DefaultsKey.boostEnabled)
            }
            hud.showBoost(percent: percent(controller))
            return "OK SET \(percent(controller))"

        case .up(let amount):
            if !controller.isEnabled {
                controller.enable()
                defaults.set(true, forKey: DefaultsKey.boostEnabled)
            }
            controller.boost = min(1.0, controller.boost + Double(amount) / 100.0)
            defaults.set(controller.boost, forKey: DefaultsKey.boost)
            hud.showBoost(percent: percent(controller))
            return "OK UP \(percent(controller))"

        case .down(let amount):
            guard controller.isEnabled else {
                return "OK DOWN \(percent(controller))"
            }
            controller.boost = max(0.0, controller.boost - Double(amount) / 100.0)
            defaults.set(controller.boost, forKey: DefaultsKey.boost)
            hud.showBoost(percent: percent(controller))
            return "OK DOWN \(percent(controller))"

        case .status:
            let state = controller.isEnabled ? "ON" : "OFF"
            return "STATUS \(state) \(percent(controller)) \(controller.statusDescription)"

        case .quit:
            controller.disable()
            defaults.set(false, forKey: DefaultsKey.boostEnabled)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                serverBox.server?.stop()
                exit(0)
            }
            return "OK BYE"
        }
    }
}
