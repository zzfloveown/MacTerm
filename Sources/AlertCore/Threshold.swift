import Foundation

/// 从第一次超限开始计时，连续超限只触发一次，恢复后可以再次触发。
public struct Threshold: Sendable {
    public enum Event: String, Sendable { case triggered = "触发", recovered = "恢复" }
    private var since: Date?
    private var active = false
    public init() {}

    public mutating func update(_ value: Double, limit: Double, duration: TimeInterval, at date: Date) -> Event? {
        if value < limit {
            since = nil
            guard active else { return nil }
            active = false
            return .recovered
        }
        if since == nil { since = date }
        guard let since, !active, date.timeIntervalSince(since) >= duration else { return nil }
        active = true
        return .triggered
    }
}
