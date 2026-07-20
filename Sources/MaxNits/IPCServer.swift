import Foundation
import Network

/// Listens on a Unix domain socket and dispatches decoded commands to a
/// handler on the main actor. One request/response per connection — traffic
/// is rare (a handful of commands a day), so there's no need for anything
/// fancier.
@MainActor
final class IPCServer {
    private let listener: NWListener
    private let lockFileDescriptor: Int32
    private let handler: (Command) -> String

    /// Returns nil if another daemon already holds the lock (i.e. one is
    /// already running), so callers can exit cleanly instead of racing it.
    init?(handler: @escaping (Command) -> String) {
        let lockFD = open(IPCProtocol.lockPath, O_CREAT | O_RDWR, 0o600)
        guard lockFD >= 0 else {
            FileHandle.standardError.write(Data("Failed to open lock file\n".utf8))
            return nil
        }
        guard flock(lockFD, LOCK_EX | LOCK_NB) == 0 else {
            close(lockFD)
            return nil
        }

        // A previous unclean exit can leave a stale socket file behind;
        // since we hold the lock, we're the only daemon and it's safe to
        // remove it before binding.
        unlink(IPCProtocol.socketPath)

        let params = NWParameters.tcp
        params.requiredLocalEndpoint = NWEndpoint.unix(path: IPCProtocol.socketPath)
        guard let listener = try? NWListener(using: params) else {
            close(lockFD)
            return nil
        }

        self.lockFileDescriptor = lockFD
        self.handler = handler
        self.listener = listener

        listener.newConnectionHandler = { [weak self] connection in
            Task { @MainActor in
                self?.accept(connection)
            }
        }
    }

    func start() {
        listener.start(queue: .main)
    }

    func stop() {
        listener.cancel()
        unlink(IPCProtocol.socketPath)
        flock(lockFileDescriptor, LOCK_UN)
        close(lockFileDescriptor)
    }

    private func accept(_ connection: NWConnection) {
        connection.start(queue: .main)
        receiveLine(on: connection, buffer: Data())
    }

    private func receiveLine(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 256) { [weak self] data, _, isComplete, error in
            Task { @MainActor in
                guard let self else { return }
                var buffer = buffer
                if let data, !data.isEmpty {
                    buffer.append(data)
                }
                if let newlineIndex = buffer.firstIndex(of: 0x0A) {
                    let line = String(data: buffer[..<newlineIndex], encoding: .utf8)?
                        .trimmingCharacters(in: .whitespaces) ?? ""
                    let reply = Command(line: line).map(self.handler) ?? "ERR unknown command"
                    connection.send(content: Data((reply + "\n").utf8), completion: .contentProcessed { _ in
                        connection.cancel()
                    })
                    return
                }
                if isComplete || error != nil {
                    connection.cancel()
                    return
                }
                self.receiveLine(on: connection, buffer: buffer)
            }
        }
    }
}
