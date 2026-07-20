import Foundation

/// Manages a classic LaunchAgent plist that starts the daemon at login.
/// Uses `launchctl`/`~/Library/LaunchAgents` rather than `SMAppService`,
/// which is finicky for a build-from-source tool that doesn't necessarily
/// live in `/Applications` or carry a Developer ID signature.
enum LoginItem {
    private static let label = "io.github.yogeshvar.MaxNits"

    private static var plistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }

    static func enable() -> Int32 {
        guard let exePath = Bundle.main.executablePath else {
            print("Couldn't resolve MaxNits' own executable path.")
            return 1
        }

        let plist: [String: Any] = [
            "Label": label,
            "ProgramArguments": [exePath, "daemon"],
            "RunAtLoad": true,
            "StandardOutPath": IPCProtocol.logPath,
            "StandardErrorPath": IPCProtocol.logPath,
        ]

        do {
            let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            try FileManager.default.createDirectory(
                at: plistURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: plistURL)
        } catch {
            print("Couldn't write LaunchAgent: \(error.localizedDescription)")
            return 1
        }

        let uid = getuid()
        _ = runLaunchctl(["bootstrap", "gui/\(uid)", plistURL.path])
        print("MaxNits will now start automatically at login.")
        return 0
    }

    static func disable() -> Int32 {
        let uid = getuid()
        _ = runLaunchctl(["bootout", "gui/\(uid)/\(label)"])
        try? FileManager.default.removeItem(at: plistURL)
        print("MaxNits will no longer start automatically at login.")
        return 0
    }

    @discardableResult
    private static func runLaunchctl(_ arguments: [String]) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus
        } catch {
            return -1
        }
    }
}
