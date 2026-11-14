import Foundation

public enum AlertMetric: String, CaseIterable, Codable, Identifiable, Sendable {
    case cpu = "CPU", memory = "内存", disk = "磁盘", swap = "Swap", load = "Load"
    case network = "网络流量", disconnected = "连接失败"
    public var id: Self { self }
    public var maximum: Double {
        switch self {
        case .network: 10_000
        case .load: 1024
        case .disconnected: 1
        default: 100
        }
    }
    public var unit: String {
        switch self {
        case .load, .disconnected: ""
        case .network: " MiB/s"
        default: "%"
        }
    }
}

public struct MonitorAlertRule: Codable, Identifiable, Sendable {
    public var id: AlertMetric { metric }
    public let metric: AlertMetric
    public var enabled: Bool
    public var limit: Double
    public var duration: Double

    public init(metric: AlertMetric, enabled: Bool, limit: Double, duration: Double) {
        self.metric = metric
        self.enabled = enabled
        self.limit = limit
        self.duration = duration
    }

    public static let defaults = AlertMetric.allCases.map { metric in
        let limit: Double
        switch metric {
        case .network: limit = 100
        case .load: limit = 4
        case .disconnected: limit = 1
        default: limit = 85
        }
        return MonitorAlertRule(metric: metric, enabled: false, limit: limit, duration: 15)
    }
}

public struct MonitorAlertEvent: Codable, Identifiable, Sendable {
    public var id = UUID()
    public let metric: AlertMetric
    public let date: Date
    public let message: String

    public init(metric: AlertMetric, date: Date, message: String) {
        self.metric = metric
        self.date = date
        self.message = message
    }
}
