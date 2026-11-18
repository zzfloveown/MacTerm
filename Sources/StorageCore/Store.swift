import Domain
import Foundation
import GRDB

public struct TransferRecord: Codable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var state: String
    public var createdAt: Date
    public var job: TransferJob?
    public var detail: String?

    public init(id: UUID = UUID(), name: String, state: String, createdAt: Date = Date(), job: TransferJob? = nil) {
        self.id = id
        self.name = name
        self.state = state
        self.createdAt = createdAt
        self.job = job
    }
}

public struct TransferJob: Codable, Equatable, Sendable {
    public let host: SSHHost
    public let local: URL
    public let remote: String
    public let upload: Bool
    public var overwrite: Bool

    public init(host: SSHHost, local: URL, remote: String, upload: Bool, overwrite: Bool = false) {
        self.host = host
        self.local = local
        self.remote = remote
        self.upload = upload
        self.overwrite = overwrite
    }

    private enum CodingKeys: String, CodingKey {
        case host, local, remote, upload, overwrite
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        host = try values.decode(SSHHost.self, forKey: .host)
        local = try values.decode(URL.self, forKey: .local)
        remote = try values.decode(String.self, forKey: .remote)
        upload = try values.decode(Bool.self, forKey: .upload)
        overwrite = try values.decodeIfPresent(Bool.self, forKey: .overwrite) ?? false
    }
}

public struct TerminalCommandEntry: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var hostID: UUID
    public var command: String
    public var createdAt: Date

    public init(id: UUID = UUID(), hostID: UUID, command: String, createdAt: Date = Date()) {
        self.id = id
        self.hostID = hostID
        self.command = command
        self.createdAt = createdAt
    }
}

/// SQLite 写入由 GRDB 串行管理，运行时数据与凭据分开保存。
public actor Store {
    let queue: DatabaseQueue

    public init(url: URL? = nil) throws {
        if let url {
            queue = try DatabaseQueue(path: url.path)
        } else {
            queue = try DatabaseQueue()
        }
        var migrator = DatabaseMigrator()
        migrator.registerMigration("initial") { db in
            try db.execute(sql: """
                CREATE TABLE ssh_hosts(id TEXT PRIMARY KEY NOT NULL, label TEXT NOT NULL, payload BLOB NOT NULL);
                CREATE TABLE transfer_tasks(id TEXT PRIMARY KEY NOT NULL, created_at REAL NOT NULL, payload BLOB NOT NULL);
                CREATE TABLE app_settings(key TEXT PRIMARY KEY NOT NULL, value BLOB NOT NULL);
                """)
        }
        migrator.registerMigration("monitorHistory") { db in
            try db.execute(sql: """
                CREATE TABLE monitor_history (
                    host_id TEXT NOT NULL,
                    sampled_at REAL NOT NULL,
                    payload BLOB NOT NULL,
                    PRIMARY KEY(host_id, sampled_at)
                );
                CREATE INDEX monitor_history_retention ON monitor_history(sampled_at);
                """)
        }
        migrator.registerMigration("monitorAlerts") { db in
            try db.execute(sql: """
                CREATE TABLE monitor_alert_rules(host_id TEXT PRIMARY KEY NOT NULL, payload BLOB NOT NULL);
                CREATE TABLE monitor_alert_events(
                    id TEXT PRIMARY KEY NOT NULL, host_id TEXT NOT NULL, created_at REAL NOT NULL, payload BLOB NOT NULL
                );
                CREATE INDEX monitor_alert_events_host ON monitor_alert_events(host_id, created_at);
                """)
        }
        migrator.registerMigration("persistentSSHTunnels") { db in
            try db.execute(sql: """
                CREATE TABLE ssh_tunnels (
                    id TEXT PRIMARY KEY NOT NULL,
                    host_id TEXT NOT NULL,
                    payload BLOB NOT NULL
                );
                CREATE INDEX ssh_tunnels_host ON ssh_tunnels(host_id);
                """)
        }
        migrator.registerMigration("terminalCommandHistory") { db in
            try db.execute(sql: """
                CREATE TABLE terminal_commands (
                    id TEXT PRIMARY KEY NOT NULL,
                    host_id TEXT NOT NULL,
                    created_at REAL NOT NULL,
                    payload BLOB NOT NULL
                );
                CREATE INDEX terminal_commands_host ON terminal_commands(host_id, created_at);
                """)
        }
        try migrator.migrate(queue)
    }

    public static func applicationSupport() throws -> URL {
        let folder = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                 appropriateFor: nil, create: true)
            .appendingPathComponent("MacTerm", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        return folder
    }

    public func hosts() throws -> [SSHHost] {
        try queue.read { db in
            try Data.fetchAll(db, sql: "SELECT payload FROM ssh_hosts ORDER BY label COLLATE NOCASE")
                .map { try JSONDecoder().decode(SSHHost.self, from: $0) }
        }
    }

    public func save(_ host: SSHHost) throws {
        try save([host])
    }

    public func save(_ hosts: [SSHHost]) throws {
        try saveConfiguration(hosts: hosts, tunnels: [])
    }

    /// 在同一数据库事务中导入主机及其隧道，避免只写入一半备份。
    public func saveConfiguration(hosts: [SSHHost], tunnels: [SSHTunnelProfile]) throws {
        try queue.write { db in
            let encoder = JSONEncoder()
            for host in hosts {
                let payload = try encoder.encode(host)
                try db.execute(sql: """
                    INSERT INTO ssh_hosts VALUES (?, ?, ?)
                    ON CONFLICT(id) DO UPDATE SET label = excluded.label, payload = excluded.payload
                    """, arguments: [host.id.uuidString, host.label, payload])
            }
            for tunnel in tunnels {
                let payload = try encoder.encode(tunnel)
                try db.execute(sql: """
                    INSERT INTO ssh_tunnels VALUES (?, ?, ?)
                    ON CONFLICT(id) DO UPDATE SET host_id = excluded.host_id, payload = excluded.payload
                    """, arguments: [tunnel.id.uuidString, tunnel.hostID.uuidString, payload])
            }
        }
    }

    public func delete(_ id: UUID) throws {
        try queue.write { db in
            try db.execute(sql: "DELETE FROM ssh_tunnels WHERE host_id = ?", arguments: [id.uuidString])
            try db.execute(sql: "DELETE FROM terminal_commands WHERE host_id = ?", arguments: [id.uuidString])
            try db.execute(sql: "DELETE FROM monitor_history WHERE host_id = ?", arguments: [id.uuidString])
            try db.execute(sql: "DELETE FROM monitor_alert_rules WHERE host_id = ?", arguments: [id.uuidString])
            try db.execute(sql: "DELETE FROM monitor_alert_events WHERE host_id = ?", arguments: [id.uuidString])
            try db.execute(sql: "DELETE FROM ssh_hosts WHERE id = ?", arguments: [id.uuidString])
        }
    }

    public func tunnels(hostID: UUID) throws -> [SSHTunnelProfile] {
        try queue.read { db in
            try Data.fetchAll(db, sql: "SELECT payload FROM ssh_tunnels WHERE host_id = ? ORDER BY rowid",
                              arguments: [hostID.uuidString])
                .map { try JSONDecoder().decode(SSHTunnelProfile.self, from: $0) }
        }
    }

    public func tunnels() throws -> [SSHTunnelProfile] {
        try queue.read { db in
            try Data.fetchAll(db, sql: "SELECT payload FROM ssh_tunnels ORDER BY rowid")
                .map { try JSONDecoder().decode(SSHTunnelProfile.self, from: $0) }
        }
    }

    public func save(_ tunnel: SSHTunnelProfile) throws {
        try save([tunnel])
    }

    public func save(_ tunnels: [SSHTunnelProfile]) throws {
        try saveConfiguration(hosts: [], tunnels: tunnels)
    }

    public func deleteTunnel(_ id: UUID) throws {
        try queue.write { db in
            try db.execute(sql: "DELETE FROM ssh_tunnels WHERE id = ?", arguments: [id.uuidString])
        }
    }

    public func save(_ record: TransferRecord) throws {
        try save([record])
    }

    public func save(_ records: [TransferRecord]) throws {
        try queue.write { db in
            let encoder = JSONEncoder()
            for record in records {
                let payload = try encoder.encode(record)
                try db.execute(sql: """
                    INSERT INTO transfer_tasks VALUES (?, ?, ?)
                    ON CONFLICT(id) DO UPDATE SET payload = excluded.payload
                    """, arguments: [record.id.uuidString, record.createdAt.timeIntervalSince1970, payload])
            }
        }
    }

    public func transfers() throws -> [TransferRecord] {
        try queue.read { db in
            try Data.fetchAll(db, sql: "SELECT payload FROM transfer_tasks ORDER BY created_at DESC")
                .map { try JSONDecoder().decode(TransferRecord.self, from: $0) }
        }
    }

    public func deleteTransfer(_ id: UUID) throws {
        try deleteTransfers([id])
    }

    public func deleteTransfers(_ ids: [UUID]) throws {
        guard !ids.isEmpty else { return }
        try queue.write { db in
            for id in ids {
                try db.execute(sql: "DELETE FROM transfer_tasks WHERE id = ?", arguments: [id.uuidString])
            }
        }
    }

    /// 仅保存用户在终端工具栏显式发送的单行无控制字符命令，不记录凭据或命令输出。
    public func recordCommand(_ command: String, for hostID: UUID, at date: Date = Date()) throws {
        let trimmed = command.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed.count <= 512,
              !trimmed.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
            throw MacTermError("快捷命令需为不超过 512 个字符的非空单行文本。")
        }
        try queue.write { db in
            let existing = try Data.fetchAll(db, sql: """
                SELECT payload FROM terminal_commands WHERE host_id = ? ORDER BY created_at DESC
                """, arguments: [hostID.uuidString])
                .map { try JSONDecoder().decode(TerminalCommandEntry.self, from: $0) }
            for item in existing where item.command == trimmed {
                try db.execute(sql: "DELETE FROM terminal_commands WHERE id = ?", arguments: [item.id.uuidString])
            }
            let entry = TerminalCommandEntry(hostID: hostID, command: trimmed, createdAt: date)
            let payload = try JSONEncoder().encode(entry)
            try db.execute(sql: "INSERT INTO terminal_commands VALUES (?, ?, ?, ?)",
                           arguments: [entry.id.uuidString, hostID.uuidString, date.timeIntervalSince1970, payload])
            try db.execute(sql: """
                DELETE FROM terminal_commands
                WHERE host_id = ? AND id NOT IN (
                    SELECT id FROM terminal_commands WHERE host_id = ? ORDER BY created_at DESC LIMIT 100
                )
                """, arguments: [hostID.uuidString, hostID.uuidString])
        }
    }

    public func commandHistory(for hostID: UUID) throws -> [TerminalCommandEntry] {
        try queue.read { db in
            try Data.fetchAll(db, sql: """
                SELECT payload FROM terminal_commands WHERE host_id = ? ORDER BY created_at DESC
                """, arguments: [hostID.uuidString])
                .map { try JSONDecoder().decode(TerminalCommandEntry.self, from: $0) }
        }
    }

    public func deleteCommand(_ id: UUID) throws {
        try queue.write { db in
            try db.execute(sql: "DELETE FROM terminal_commands WHERE id = ?", arguments: [id.uuidString])
        }
    }

    public func clearCommandHistory(for hostID: UUID) throws {
        try queue.write { db in
            try db.execute(sql: "DELETE FROM terminal_commands WHERE host_id = ?", arguments: [hostID.uuidString])
        }
    }
}
