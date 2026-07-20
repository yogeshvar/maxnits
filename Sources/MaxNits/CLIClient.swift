import Foundation

/// Implements the user-facing subcommands by talking to the daemon over
/// `IPCClient`, spawning it first if necessary.
enum CLIClient {
    static func run(_ args: [String]) -> Int32 {
        guard let first = args.first else {
            printUsage()
            return 1
        }

        switch first {
        case "on":
            return sendAndPrint(.on, spawnIfNeeded: true)
        case "off":
            return sendAndPrint(.off, spawnIfNeeded: true)
        case "set":
            guard args.count > 1, let n = Int(args[1]) else {
                print("Usage: maxnits set <0-100>")
                return 1
            }
            return sendAndPrint(.set(n), spawnIfNeeded: true)
        case "up":
            let amount = args.count > 1 ? (Int(args[1]) ?? 10) : 10
            return sendAndPrint(.up(amount), spawnIfNeeded: true)
        case "down":
            let amount = args.count > 1 ? (Int(args[1]) ?? 10) : 10
            return sendAndPrint(.down(amount), spawnIfNeeded: true)
        case "status":
            return sendAndPrint(.status, spawnIfNeeded: false, notRunningMessage: "MaxNits is not running.", notRunningExitCode: 1)
        case "quit":
            return sendAndPrint(.quit, spawnIfNeeded: false, notRunningMessage: "MaxNits is not running.", notRunningExitCode: 0)
        default:
            printUsage()
            return 1
        }
    }

    private static func sendAndPrint(
        _ command: Command,
        spawnIfNeeded: Bool,
        notRunningMessage: String = "Couldn't reach the MaxNits daemon.",
        notRunningExitCode: Int32 = 1
    ) -> Int32 {
        if spawnIfNeeded {
            guard IPCClient.spawnDaemonIfNeeded() else {
                print("Couldn't start the MaxNits daemon — check \(IPCProtocol.logPath)")
                return 1
            }
        } else if !IPCClient.isDaemonRunning() {
            print(notRunningMessage)
            return notRunningExitCode
        }

        guard let reply = IPCClient.send(command) else {
            print("Couldn't reach the MaxNits daemon.")
            return 1
        }
        print(format(reply))
        return reply.hasPrefix("ERR") ? 1 : 0
    }

    private static func format(_ reply: String) -> String {
        let parts = reply.split(separator: " ", maxSplits: 1)
        guard let head = parts.first else { return reply }
        switch head {
        case "OK": return String(parts.count > 1 ? parts[1] : "").isEmpty ? "OK" : describeOK(String(parts[1]))
        case "STATUS": return parts.count > 1 ? String(parts[1]) : reply
        default: return reply
        }
    }

    private static func describeOK(_ rest: String) -> String {
        let fields = rest.split(separator: " ")
        guard let verb = fields.first else { return rest }
        switch verb {
        case "ON": return fields.count > 1 ? "Boost on — \(fields[1])%" : "Boost on"
        case "OFF": return "Boost off"
        case "SET": return fields.count > 1 ? "Boost set to \(fields[1])%" : rest
        case "UP": return fields.count > 1 ? "Boost \(fields[1])%" : rest
        case "DOWN": return fields.count > 1 ? "Boost \(fields[1])%" : rest
        case "BYE": return "MaxNits stopped."
        default: return rest
        }
    }

    private static func printUsage() {
        print("""
        Usage: maxnits <command>

        Commands:
          on              Turn the brightness boost on
          off             Turn the brightness boost off
          set <0-100>     Set the boost level directly
          up [amount]     Increase the boost (default 10%)
          down [amount]   Decrease the boost (default 10%)
          status          Show whether MaxNits is running and its current level
          quit            Stop the background daemon
          enable-login    Start MaxNits automatically at login
          disable-login   Stop starting MaxNits automatically at login

        Diagnostics:
          --status        Print raw EDR headroom per display
          --test          6-second boost self-test
        """)
    }
}
