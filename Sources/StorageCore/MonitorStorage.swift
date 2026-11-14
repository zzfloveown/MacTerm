import Domain
import Foundation
import GRDB

extension Store {
    public func save(_ point: MonitorPoint, for host: UUID) throws {
        let timestamp = point.time.timeIntervalSince1970
        let payload = try JSONEncoder().encode(point)
        let prune = timestamp - 86_400
        try queue.write { db in
            try db.execute(sql: "INSERT OR REPLACE INTO monitor_history(host_id, sampled_at, payload) VALUES (?, ?, ?)",
                           arguments: [host.uuidString, timestamp, payload])
            try db.execute(sql: "DELETE FROM monitor_history WHERE sampled_at < ?", arguments: [prune])
        }
    }

    public func monitorPoints(for host: UUID, since start: Date) throws -> [MonitorPoint] {
        try queue.read { db in
            let payloads = try Data.fetchAll(db, sql: """
                SELECT payload FROM monitor_history WHERE host_id = ? AND sampled_at >= ? ORDER BY sampled_at
                """, arguments: [host.uuidString, start.timeIntervalSince1970])
            let decoder = JSONDecoder()
            return try payloads.map { try decoder.decode(MonitorPoint.self, from: $0) }
        }
    }
}

extension Store {
    public func alertRules(for host: UUID) throws -> [MonitorAlertRule] {
        try queue.read { db in
            guard let data = try Data.fetchOne(db, sql: "SELECT payload FROM monitor_alert_rules WHERE host_id = ?",
                                               arguments: [host.uuidString]) else { return MonitorAlertRule.defaults }
            let saved = try JSONDecoder().decode([MonitorAlertRule].self, from: data)
            return MonitorAlertRule.defaults.map { fallback in
                saved.first { $0.metric == fallback.metric } ?? fallback
            }
        }
    }

    public func save(_ rules: [MonitorAlertRule], for host: UUID) throws {
        let payload = try JSONEncoder().encode(rules)
        try queue.write { db in
            try db.execute(sql: "INSERT OR REPLACE INTO monitor_alert_rules VALUES (?, ?)",
                           arguments: [host.uuidString, payload])
        }
    }

    public func alertEvents(for host: UUID) throws -> [MonitorAlertEvent] {
        try queue.read { db in
            let rows = try Data.fetchAll(db, sql: """
                SELECT payload FROM monitor_alert_events WHERE host_id = ? ORDER BY created_at DESC LIMIT 500
                """, arguments: [host.uuidString])
            return try rows.map { try JSONDecoder().decode(MonitorAlertEvent.self, from: $0) }
        }
    }

    public func save(_ event: MonitorAlertEvent, for host: UUID) throws {
        let payload = try JSONEncoder().encode(event)
        let timestamp = event.date.timeIntervalSince1970
        try queue.write { db in
            try db.execute(sql: "INSERT INTO monitor_alert_events VALUES (?, ?, ?, ?)",
                           arguments: [event.id.uuidString, host.uuidString, timestamp, payload])
            try db.execute(sql: """
                DELETE FROM monitor_alert_events WHERE host_id = ? AND id NOT IN
                (SELECT id FROM monitor_alert_events WHERE host_id = ? ORDER BY created_at DESC LIMIT 500)
                """, arguments: [host.uuidString, host.uuidString])
        }
    }
}
