import Foundation

/// The line-based text protocol spoken over the daemon's Unix domain socket,
/// plus the well-known filesystem locations both sides agree on.
enum IPCProtocol {
    private static let supportDirectory: URL = {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/MaxNits", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    /// Path to the control socket. `sockaddr_un.sun_path` is limited to 104
    /// bytes on Darwin; fall back to a short `/tmp` path for unusually long
    /// home directories rather than failing to bind.
    static var socketPath: String {
        let preferred = supportDirectory.appendingPathComponent("daemon.sock").path
        if preferred.utf8.count < 100 {
            return preferred
        }
        return "/tmp/maxnits-\(getuid()).sock"
    }

    static var lockPath: String {
        supportDirectory.appendingPathComponent("daemon.lock").path
    }

    static var logPath: String {
        supportDirectory.appendingPathComponent("daemon.log").path
    }
}

enum Command: Equatable {
    case on
    case off
    case set(Int)
    case up(Int)
    case down(Int)
    case status
    case quit

    /// Decodes a single received line (already trimmed of the trailing newline).
    init?(line: String) {
        let parts = line.split(separator: " ")
        guard let head = parts.first else { return nil }
        switch head.uppercased() {
        case "ON": self = .on
        case "OFF": self = .off
        case "SET":
            guard parts.count > 1, let n = Int(parts[1]) else { return nil }
            self = .set(n)
        case "UP":
            guard parts.count > 1, let n = Int(parts[1]) else { return nil }
            self = .up(n)
        case "DOWN":
            guard parts.count > 1, let n = Int(parts[1]) else { return nil }
            self = .down(n)
        case "STATUS": self = .status
        case "QUIT": self = .quit
        default: return nil
        }
    }

    /// The line to send over the wire for this command.
    var wireFormat: String {
        switch self {
        case .on: return "ON"
        case .off: return "OFF"
        case .set(let n): return "SET \(n)"
        case .up(let n): return "UP \(n)"
        case .down(let n): return "DOWN \(n)"
        case .status: return "STATUS"
        case .quit: return "QUIT"
        }
    }
}
