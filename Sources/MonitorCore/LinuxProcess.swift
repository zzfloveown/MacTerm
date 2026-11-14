import Domain
import Foundation

public struct LinuxProcess: Identifiable, Sendable {
    public var id: Int { pid }
    public let pid: Int
    public let user: String
    public let cpu: Double
    public let memory: Double
    public let elapsed: Int
    public let command: String

    static func parse(_ output: String) -> [LinuxProcess] {
        output.split(whereSeparator: \.isNewline).compactMap { line in
            let fields = line.split(maxSplits: 5, whereSeparator: \.isWhitespace)
            guard fields.count == 6, let pid = Int(fields[0]),
                  let cpu = Double(fields[2]), let memory = Double(fields[3]),
                  let elapsed = Int(fields[4]) else { return nil }
            return LinuxProcess(pid: pid, user: String(fields[1]), cpu: cpu,
                                memory: memory, elapsed: elapsed, command: String(fields[5]))
        }
    }
}

extension MonitorEngine {
    public func processList(_ host: SSHHost) async throws -> [LinuxProcess] {
        let result = try await transport.execute(on: host, arguments: ["env", "LC_ALL=C", "ps", "-ww", "-eo",
            "pid=,user=,pcpu=,pmem=,etimes=,args=", "--sort=-pcpu"])
        return LinuxProcess.parse(result)
    }

    public func terminate(_ process: LinuxProcess, on host: SSHHost) async throws {
        guard process.pid > 1 else { throw MacTermError("仅可结束 PID 大于 1 的进程。") }
        let script = """
        row=$(LC_ALL=C ps -ww -p "$1" -o user=,args=) || exit 1
        row=${row#"${row%%[! ]*}"}
        case "$row" in *' '*) ;; *) exit 1 ;; esac
        actual_user=${row%% *}
        command=${row#"$actual_user"}
        command=${command#"${command%%[! ]*}"}
        [ "$actual_user" = "$2" ] && [ "$command" = "$3" ] || exit 1
        kill -TERM "$1"
        """
        _ = try await transport.execute(on: host, arguments: ["sh", "-c", script, "macterm",
                                                               String(process.pid), process.user, process.command])
    }
}
