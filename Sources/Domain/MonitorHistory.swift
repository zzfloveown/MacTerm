import Foundation

public struct MonitorPoint: Codable, Identifiable, Sendable {
    public var id: Date { time }
    public let time: Date
    public let cpu: Double?
    public let memory: Double?
    public let incoming: Double?
    public let outgoing: Double?

    public init(time: Date, cpu: Double?, memory: Double?, incoming: Double?, outgoing: Double?) {
        self.time = time
        self.cpu = cpu
        self.memory = memory
        self.incoming = incoming
        self.outgoing = outgoing
    }

    public static func csv(_ points: [MonitorPoint]) -> String {
        var lines = ["time,cpu_ratio,memory_ratio,receive_bytes_per_second,transmit_bytes_per_second"]
        for point in points {
            let metrics = [point.cpu, point.memory, point.incoming, point.outgoing].map { value in
                value.map { String($0) } ?? ""
            }
            lines.append(([point.time.ISO8601Format()] + metrics).joined(separator: ","))
        }
        return lines.joined(separator: "\n") + "\n"
    }
}
