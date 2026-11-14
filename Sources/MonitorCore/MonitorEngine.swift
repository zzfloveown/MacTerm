import Domain
import Foundation
import SSHCore

public struct Sample: Sendable {
    public let time: Date
    public let cpu: [String: [UInt64]]
    public let memory: [String: UInt64]
    public let network: [String: [UInt64]]
    public let load: String
    public let volumes: [String]

    public var usedMemory: Double? {
        guard let total = memory["MemTotal"], let available = memory["MemAvailable"],
              total > 0, available <= total else { return nil }
        return Double(total - available) / Double(total)
    }

    public var usedSwap: Double? {
        guard let total = memory["SwapTotal"], let free = memory["SwapFree"],
              total > 0, free <= total else { return nil }
        return Double(total - free) / Double(total)
    }

    /// CPU 只计算前八个计数，guest 已包含在 user 和 nice 中。
    public func utilization(since previous: Sample, core: String = "cpu") -> Double? {
        guard let a = cpu[core], let b = previous.cpu[core], a.count == 8, b.count == 8 else { return nil }
        let pairs = zip(a, b)
        guard pairs.allSatisfy({ $0.0 >= $0.1 }) else { return nil }
        let delta = pairs.map { Double($0.0 - $0.1) }
        let total = delta.reduce(0, +)
        guard total > 0 else { return nil }
        return (total - delta[3] - delta[4]) / total
    }

    public func rates(since previous: Sample, interface: String) -> (receive: Double, transmit: Double)? {
        let seconds = time.timeIntervalSince(previous.time)
        guard seconds > 0, let a = network[interface], let b = previous.network[interface],
              a[0] >= b[0], a[1] >= b[1] else { return nil }
        return (Double(a[0] - b[0]) / seconds, Double(a[1] - b[1]) / seconds)
    }

    public static func parse(_ text: String, time: Date = Date()) throws -> Sample {
        let sections = text.components(separatedBy: "\n__MACTERM__\n")
        guard sections.count == 5 else { throw MacTermError("Linux 监控数据不完整。") }
        var cpu: [String: [UInt64]] = [:]
        var memory: [String: UInt64] = [:]
        var network: [String: [UInt64]] = [:]
        for line in sections[0].split(separator: "\n") {
            let fields = line.split(whereSeparator: \.isWhitespace)
            if let key = fields.first, key.hasPrefix("cpu") {
                cpu[String(key)] = fields.dropFirst().prefix(8).compactMap { UInt64($0) }
            }
        }
        for line in sections[1].split(separator: "\n") {
            let fields = line.split(whereSeparator: \.isWhitespace)
            if fields.count >= 2, let value = UInt64(fields[1]) {
                memory[String(fields[0].dropLast())] = value
            }
        }
        for line in sections[2].split(separator: "\n") {
            let fields = line.split(separator: ":", maxSplits: 1)
            guard fields.count == 2 else { continue }
            let counters = fields[1].split(whereSeparator: \.isWhitespace)
            if counters.count >= 16, let rx = UInt64(counters[0]), let tx = UInt64(counters[8]) {
                network[fields[0].trimmingCharacters(in: .whitespaces)] = [rx, tx]
            }
        }
        guard cpu["cpu"]?.count == 8, memory["MemTotal"] != nil else {
            throw MacTermError("无法解析 Linux CPU 或内存计数器。")
        }
        return Sample(time: time, cpu: cpu, memory: memory, network: network,
                      load: sections[3].split(whereSeparator: \.isWhitespace).prefix(3).joined(separator: " "),
                      volumes: sections[4].split(separator: "\n").map(String.init))
    }
}

public struct MonitorEngine: Sendable {
    let transport: any SSHTransport

    public init(transport: any SSHTransport = OpenSSHTransport()) { self.transport = transport }

    public func sample(_ host: Host) async throws -> Sample {
        let script = """
        export LC_ALL=C
        for path in /proc/stat /proc/meminfo /proc/net/dev /proc/loadavg; do
            cat "$path" || exit 1
            printf '__MACTERM__\\n'
        done
        df -PT
        """
        let text = try await transport.execute(on: host, arguments: ["sh", "-c", script])
        return try Sample.parse(text)
    }

    public func processes(_ host: Host) async throws -> String {
        try await transport.execute(on: host, arguments: ["env", "LC_ALL=C", "ps", "-eo",
            "pid,user,comm,pcpu,pmem,etime,args", "--sort=-pcpu"])
    }
}
