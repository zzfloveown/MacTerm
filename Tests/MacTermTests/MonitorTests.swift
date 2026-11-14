import Domain
import Foundation
import StorageCore
import XCTest
@testable import MonitorCore

final class MonitorTests: XCTestCase {
    func testHistoryAndRulesPersistWithRetention() async throws {
        let store = try Store()
        let host = UUID()
        let now = Date(timeIntervalSince1970: 1_000_000)
        let old = MonitorPoint(time: now.addingTimeInterval(-86_401), cpu: 0.1, memory: nil, incoming: nil, outgoing: nil)
        let latest = MonitorPoint(time: now, cpu: 0.5, memory: 0.75, incoming: 12, outgoing: 4)
        try await store.save(old, for: host)
        try await store.save(latest, for: host)
        let points = try await store.monitorPoints(for: host, since: .distantPast)
        XCTAssertEqual(points.map(\.time), [now])
        XCTAssertTrue(MonitorPoint.csv(points).contains("0.5,0.75,12.0,4.0"))
        let rule = MonitorAlertRule(metric: .cpu, enabled: true, limit: 91, duration: 15)
        try await store.save([rule], for: host)
        let rules = try await store.alertRules(for: host)
        XCTAssertEqual(rules.first { $0.metric == .cpu }?.limit, 91)
        let event = MonitorAlertEvent(metric: .cpu, date: now, message: "trigger")
        try await store.save(event, for: host)
        let events = try await store.alertEvents(for: host)
        XCTAssertEqual(events.map(\.id), [event.id])
    }

    func testProcessPreservesArguments() {
        let result = LinuxProcess.parse("  123 ops 5.5 0.2 17 /bin/test argument with spaces\ninvalid")
        XCTAssertEqual(result.map(\.pid), [123])
        XCTAssertEqual(result.first?.command, "/bin/test argument with spaces")
        XCTAssertEqual(result.first?.elapsed, 17)
    }
}
