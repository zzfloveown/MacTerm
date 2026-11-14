import Domain
import Foundation
import GRDB

public struct TransferRecord: Codable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var state: String
    public var createdAt: Date

    public init(id: UUID = UUID(), name: String, state: String, createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.state = state
        self.createdAt = createdAt
    }
}

/// SQLite 写入由 GRDB 串行管理，运行时数据与凭据分开保存。
public actor Store {
    private let queue: DatabaseQueue

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
        let payload = try JSONEncoder().encode(host)
        try queue.write { db in
            try db.execute(sql: """
                INSERT INTO ssh_hosts VALUES (?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET label = excluded.label, payload = excluded.payload
                """, arguments: [host.id.uuidString, host.label, payload])
        }
    }

    public func delete(_ id: UUID) throws {
        try queue.write { db in
            try db.execute(sql: "DELETE FROM ssh_hosts WHERE id = ?", arguments: [id.uuidString])
        }
    }

    public func save(_ record: TransferRecord) throws {
        let payload = try JSONEncoder().encode(record)
        try queue.write { db in
            try db.execute(sql: """
                INSERT INTO transfer_tasks VALUES (?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET payload = excluded.payload
                """, arguments: [record.id.uuidString, record.createdAt.timeIntervalSince1970, payload])
        }
    }

    public func transfers() throws -> [TransferRecord] {
        try queue.read { db in
            try Data.fetchAll(db, sql: "SELECT payload FROM transfer_tasks ORDER BY created_at DESC")
                .map { try JSONDecoder().decode(TransferRecord.self, from: $0) }
        }
    }
}
