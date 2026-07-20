import Foundation
import Network

/// Synchronous client for the daemon's Unix domain socket. A bare CLI
/// invocation has no run loop driving async callbacks, but GCD services
/// background-queue callbacks independent of one — `DispatchSemaphore`
/// bridges the gap without needing `dispatchMain()`.
enum IPCClient {
    private static let queue = DispatchQueue(label: "maxnits.ipc.client")

    /// Sends one command, waiting up to `timeout` to connect and to receive
    /// a reply. Returns the daemon's reply line, or nil on any failure.
    static func send(_ command: Command, timeout: TimeInterval = 1.0) -> String? {
        let params = NWParameters.tcp
        let connection = NWConnection(to: .unix(path: IPCProtocol.socketPath), using: params)

        let readySemaphore = DispatchSemaphore(value: 0)
        var connected = false
        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                connected = true
                readySemaphore.signal()
            case .failed, .cancelled:
                readySemaphore.signal()
            default:
                break
            }
        }
        connection.start(queue: queue)
        _ = readySemaphore.wait(timeout: .now() + timeout)
        guard connected else {
            connection.cancel()
            return nil
        }

        let replySemaphore = DispatchSemaphore(value: 0)
        var replyLine: String?
        connection.send(content: Data((command.wireFormat + "\n").utf8), completion: .contentProcessed { _ in
            receiveLine(connection, buffer: Data()) { result in
                replyLine = result
                replySemaphore.signal()
            }
        })
        _ = replySemaphore.wait(timeout: .now() + timeout)
        connection.cancel()
        return replyLine
    }

    private static func receiveLine(_ connection: NWConnection, buffer: Data, completion: @escaping (String?) -> Void) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 256) { data, _, isComplete, error in
            var buffer = buffer
            if let data, !data.isEmpty {
                buffer.append(data)
            }
            if let newlineIndex = buffer.firstIndex(of: 0x0A) {
                let line = String(data: buffer[..<newlineIndex], encoding: .utf8)?
                    .trimmingCharacters(in: .whitespaces)
                completion(line)
                return
            }
            if isComplete || error != nil {
                completion(nil)
                return
            }
            receiveLine(connection, buffer: buffer, completion: completion)
        }
    }

    /// True if a daemon currently appears to be reachable.
    static func isDaemonRunning() -> Bool {
        send(.status, timeout: 0.3) != nil
    }

    /// Launches the daemon detached (it survives after this process exits)
    /// and waits for it to become reachable, retrying with backoff.
    @discardableResult
    static func spawnDaemonIfNeeded() -> Bool {
        if isDaemonRunning() { return true }

        guard let exePath = Bundle.main.executablePath else {
            FileHandle.standardError.write(Data("Couldn't resolve MaxNits' own executable path.\n".utf8))
            return false
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: exePath)
        process.arguments = ["daemon"]

        if !FileManager.default.fileExists(atPath: IPCProtocol.logPath) {
            FileManager.default.createFile(atPath: IPCProtocol.logPath, contents: nil)
        }
        if let log = FileHandle(forWritingAtPath: IPCProtocol.logPath) {
            log.seekToEndOfFile()
            process.standardOutput = log
            process.standardError = log
        }

        do {
            try process.run()
        } catch {
            FileHandle.standardError.write(Data("Failed to start MaxNits daemon: \(error.localizedDescription)\n".utf8))
            return false
        }
        // Deliberately not calling waitUntilExit() — once this client exits,
        // the unwaited child is reparented to launchd, which is what keeps
        // it running as a detached background process.

        for delayMs: UInt32 in [150, 300, 600, 1200, 1200] {
            usleep(delayMs * 1000)
            if isDaemonRunning() { return true }
        }
        return false
    }
}
