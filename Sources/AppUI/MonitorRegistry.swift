import AlertCore
import Combine
import Domain
import Foundation
import MonitorCore
import StorageCore
import UserNotifications

/// 每个服务器共享一项采集任务，窗口切换不会重复启动采集。
@MainActor
public final class MonitorRegistry: ObservableObject {
    private let store: Store
    private let engine = MonitorEngine()
    private var sessions: [UUID: HostMonitor] = [:]

    public init(store: Store) { self.store = store }

    func session(for host: SSHHost) -> HostMonitor {
        if let session = sessions[host.id] { return session }
        let session = HostMonitor(store: store, engine: engine)
        sessions[host.id] = session
        Task {
            do {
                try await session.loadAlerts(for: host.id)
                if session.hasActiveRules { session.start(host, interval: 5) }
            } catch { session.report(error) }
        }
        return session
    }

    func remove(_ id: UUID) { sessions.removeValue(forKey: id)?.stop() }
}

@MainActor
final class HostMonitor: ObservableObject {
    @Published private(set) var sample: Sample?
    @Published private(set) var previous: Sample?
    @Published private(set) var latest: MonitorPoint?
    @Published private(set) var status = ""
    @Published private(set) var running = false
    @Published private(set) var events: [MonitorAlertEvent] = []
    private var rules: [MonitorAlertRule] = []
    private var alertStates: [AlertMetric: Threshold] = [:]
    private var configured = false
    var hasActiveRules: Bool { rules.contains(where: \.enabled) }
    let store: Store
    let engine: MonitorEngine
    private var task: Task<Void, Never>?

    init(store: Store, engine: MonitorEngine) {
        self.store = store
        self.engine = engine
    }

    func report(_ error: Error) { status = error.localizedDescription }

    func setRules(_ newRules: [MonitorAlertRule]) {
        let existing = Dictionary(uniqueKeysWithValues: rules.map { ($0.metric, $0) })
        for rule in newRules {
            if let previous = existing[rule.metric], previous.enabled == rule.enabled,
               previous.limit == rule.limit, previous.duration == rule.duration { continue }
            alertStates[rule.metric] = nil
        }
        rules = newRules
        configured = true
    }

    func loadAlerts(for host: UUID) async throws {
        guard !configured else { return }
        let loaded = try await store.alertRules(for: host)
        let history = try await store.alertEvents(for: host)
        if !configured { setRules(loaded); events = history }
    }

    func start(_ host: SSHHost, interval: Int) {
        guard task == nil else { return }
        running = true
        task = Task {
            await collect(host, interval: interval)
            // 关闭连接需要在未取消的任务中执行。
            let engine = engine
            await Task.detached { await engine.close(host) }.value
            running = false
            task = nil
        }
    }

    func stop() {
        task?.cancel()
    }

    private func collect(_ host: SSHHost, interval: Int) async {
        while !Task.isCancelled {
            do {
                let next = try await engine.sample(host)
                try Task.checkCancellation()
                previous = sample
                sample = next
                let rates = previous.map { previous in
                    next.network.keys.filter { $0 != "lo" }.compactMap { next.rates(since: previous, interface: $0) }
                } ?? []
                let point = MonitorPoint(time: next.time, cpu: previous.flatMap { next.utilization(since: $0) },
                                         memory: next.usedMemory,
                                         incoming: rates.isEmpty ? nil : rates.reduce(0) { $0 + $1.receive },
                                         outgoing: rates.isEmpty ? nil : rates.reduce(0) { $0 + $1.transmit })
                try await store.save(point, for: host.id)
                latest = point
                status = ""
                await evaluate(host, point: point, sample: next, unavailable: false)
            } catch is CancellationError { return }
            catch {
                sample = nil
                previous = nil
                status = error.localizedDescription
                await evaluate(host, point: nil, sample: nil, unavailable: true)
            }
            do { try await Task.sleep(for: .seconds(interval)) } catch { return }
        }
    }

    private func evaluate(_ host: SSHHost, point: MonitorPoint?, sample: Sample?, unavailable: Bool) async {
        let time = point?.time ?? Date()
        for rule in rules where rule.enabled {
            let value: Double?
            switch rule.metric {
            case .cpu: value = point?.cpu.map { $0 * 100 }
            case .memory: value = point?.memory.map { $0 * 100 }
            case .disk: value = sample?.maxVolumeUse.map { $0 * 100 }
            case .swap: value = sample?.usedSwap.map { $0 * 100 }
            case .load: value = sample?.load.split(separator: " ").first.flatMap { Double($0) }
            case .network: value = point.flatMap { point in
                guard let incoming = point.incoming, let outgoing = point.outgoing else { return nil }
                return (incoming + outgoing) / 1_048_576
            }
            case .disconnected: value = unavailable ? 1 : 0
            }
            guard let value else { continue }
            var threshold = alertStates[rule.metric] ?? Threshold()
            let event = threshold.update(value, limit: rule.limit, duration: rule.duration, at: time)
            alertStates[rule.metric] = threshold
            guard let event else { continue }
            let saved = MonitorAlertEvent(metric: rule.metric, date: time,
                                          message: rule.metric.rawValue + "告警" + event.rawValue)
            do {
                try await store.save(saved, for: host.id)
                events.insert(saved, at: 0)
                if events.count > 500 { events.removeLast() }
                let content = UNMutableNotificationContent()
                content.title = "MacTerm"
                content.body = saved.message
                try? await UNUserNotificationCenter.current().add(
                    UNNotificationRequest(identifier: saved.id.uuidString, content: content, trigger: nil)
                )
            } catch { status = error.localizedDescription }
        }
    }
}
