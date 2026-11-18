import ConnectionCore
import Domain
import Foundation

public struct SFTPEntry: Identifiable, Sendable {
    public var id: String { name }
    public let name: String
    public let size: UInt64?
    public let permissions: UInt32?
    public let modified: Date?
    public var isDirectory: Bool { permissions.map { ($0 & 0o170000) == 0o040000 } ?? false }

    public init(name: String, size: UInt64?, permissions: UInt32?, modified: Date?) {
        self.name = name
        self.size = size
        self.permissions = permissions
        self.modified = modified
    }
}

extension SFTPClient {
    /// 通过 OpenSSH 的 SFTP 子系统读取二进制目录项，保留精确文件名和属性。
    public func entries(_ directory: String, on host: SSHHost) async throws -> [SFTPEntry] {
        try Self.validateProtocolPath(directory)
        return try await withChannel(host) { channel in
            var opened = try channel.request(11, payload: Data.field(Data(directory.utf8)), expecting: 102)
            let handle = try opened.field()
            var entries: [SFTPEntry] = []
            while true {
                do {
                    var response = try channel.request(12, payload: Data.field(handle), expecting: 104)
                    let count = try response.word()
                    guard count > 0, count <= 50_000, entries.count + Int(count) <= 250_000 else {
                        throw SFTPDirectoryError.invalidReply
                    }
                    for _ in 0..<count {
                        let name = try response.field()
                        _ = try response.field()
                        let attrs = try response.attributes()
                        guard let decoded = String(data: name, encoding: .utf8),
                              !decoded.isEmpty, !decoded.contains("/"), !decoded.utf8.contains(0),
                              decoded != ".", decoded != ".." else { continue }
                        entries.append(SFTPEntry(name: decoded, size: attrs.size,
                                                permissions: attrs.mode, modified: attrs.modified))
                    }
                } catch SFTPDirectoryError.status(1) { break }
            }
            _ = try channel.request(4, payload: Data.field(handle), expecting: 101)
            return entries
        }
    }

    public func setPermissions(_ mode: UInt32, at path: String, on host: SSHHost) async throws {
        guard path.hasPrefix("/"), !path.utf8.contains(0), mode <= 0o777 else {
            throw SFTPDirectoryError.invalidPath
        }
        try await withChannel(host) { channel in
            _ = try channel.request(9, payload: Data.field(Data(path.utf8)) + Data.word(4) + Data.word(mode), expecting: 101)
        }
    }

    public func createDirectory(_ path: String, on host: SSHHost) async throws {
        try await mutate(14, paths: [path], suffix: Data.word(0), on: host)
    }

    public func rename(_ original: String, to destination: String, on host: SSHHost) async throws {
        try await mutate(18, paths: [original, destination], on: host)
    }

    public func deleteFile(_ path: String, on host: SSHHost) async throws {
        try await mutate(13, paths: [path], on: host)
    }

    public func deleteDirectory(_ path: String, on host: SSHHost) async throws {
        try await mutate(15, paths: [path], on: host)
    }

    private func mutate(_ kind: UInt8, paths: [String], suffix: Data = Data(), on host: SSHHost) async throws {
        try paths.forEach(Self.validateProtocolPath)
        let payload = paths.reduce(into: Data()) { $0.append(Data.field(Data($1.utf8))) } + suffix
        try await withChannel(host) { channel in
            _ = try channel.request(kind, payload: payload, expecting: 101)
        }
    }

    static func validateProtocolPath(_ path: String) throws {
        guard path.hasPrefix("/"), path.utf8.count <= 16_384, !path.utf8.contains(0) else {
            throw SFTPDirectoryError.invalidPath
        }
    }

    func withChannel<T: Sendable>(_ host: SSHHost, _ body: @escaping @Sendable (SFTPChannel) throws -> T) async throws -> T {
        let args = try OpenSSHArguments.common(host, interactive: false)
        let channel = SFTPChannel()
        return try await withTaskCancellationHandler {
            try await Task.detached(priority: .utility) {
                try channel.connect(args + ["-T", "-s", "--", host.address, "sftp"])
                defer { channel.finish() }
                do {
                    let value = try body(channel)
                    try channel.checkCancellation()
                    return value
                } catch {
                    try channel.checkCancellation()
                    throw error
                }
            }.value
        } onCancel: {
            channel.cancel()
        }
    }
}

enum SFTPDirectoryError: LocalizedError {
    case invalidPath, invalidReply, status(UInt32)

    var errorDescription: String? {
        switch self {
        case .invalidPath: "无效的 SFTP 路径或权限。"
        case .invalidReply: "SFTP 子系统返回无效数据或连接断开。"
        case .status(let code): "SFTP 操作失败（协议状态 \(code)）。"
        }
    }
}

final class SFTPChannel: @unchecked Sendable {
    private let process = Process()
    private let input = Pipe()
    private let output = Pipe()
    private let lock = NSLock()
    private var cancelled = false
    private var nextID: UInt32 = 0

    func connect(_ arguments: [String]) throws {
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
        process.arguments = arguments
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        lock.lock()
        do {
            if cancelled { throw CancellationError() }
            try process.run()
            lock.unlock()
        } catch {
            lock.unlock()
            throw error
        }
        do {
            try send(Data([1]) + Data.word(3))
            var version = Packet(try receive())
            guard try version.byte() == 2, try version.word() == 3 else { throw SFTPDirectoryError.invalidReply }
        } catch {
            finish()
            try checkCancellation()
            throw error
        }
    }

    func cancel() {
        lock.lock()
        defer { lock.unlock() }
        cancelled = true
        if process.isRunning { process.terminate() }
    }

    func checkCancellation() throws {
        lock.lock()
        defer { lock.unlock() }
        if cancelled { throw CancellationError() }
    }

    func finish() {
        try? input.fileHandleForWriting.close()
        lock.lock()
        if process.isRunning { process.terminate() }
        lock.unlock()
        process.waitUntilExit()
    }

    func request(_ kind: UInt8, payload: Data, expecting reply: UInt8) throws -> Packet {
        try checkCancellation()
        nextID &+= 1
        try send(Data([kind]) + Data.word(nextID) + payload)
        var packet = Packet(try receive())
        let type = try packet.byte()
        guard try packet.word() == nextID else { throw SFTPDirectoryError.invalidReply }
        if type == 101 {
            let status = try packet.word()
            guard status == 0 && reply == 101 else { throw SFTPDirectoryError.status(status) }
        } else if type != reply {
            throw SFTPDirectoryError.invalidReply
        }
        return packet
    }

    private func send(_ payload: Data) throws {
        try input.fileHandleForWriting.write(contentsOf: Data.word(UInt32(payload.count)) + payload)
    }

    private func receive() throws -> Data {
        var header = Packet(try read(4))
        let length = try header.word()
        guard (1...1_048_576).contains(length) else { throw SFTPDirectoryError.invalidReply }
        return try read(Int(length))
    }

    private func read(_ length: Int) throws -> Data {
        var bytes = Data()
        while bytes.count < length {
            guard let chunk = try output.fileHandleForReading.read(upToCount: length - bytes.count),
                  !chunk.isEmpty else { throw SFTPDirectoryError.invalidReply }
            bytes.append(chunk)
        }
        return bytes
    }
}

extension Data {
    static func word(_ value: UInt32) -> Data {
        var bigEndian = value.bigEndian
        return Swift.withUnsafeBytes(of: &bigEndian) { Data($0) }
    }

    static func field(_ value: Data) -> Data { word(UInt32(value.count)) + value }
}

struct Packet {
    var bytes: Data
    var cursor = 0
    init(_ bytes: Data) { self.bytes = bytes }

    mutating func byte() throws -> UInt8 {
        guard cursor < bytes.count else { throw SFTPDirectoryError.invalidReply }
        defer { cursor += 1 }
        return bytes[cursor]
    }

    mutating func word() throws -> UInt32 {
        var value: UInt32 = 0
        for _ in 0..<4 { value = (value << 8) | UInt32(try byte()) }
        return value
    }

    mutating func field() throws -> Data {
        let count = Int(try word())
        guard count <= bytes.count - cursor else { throw SFTPDirectoryError.invalidReply }
        defer { cursor += count }
        return bytes.subdata(in: cursor..<(cursor + count))
    }

    mutating func attributes() throws -> (size: UInt64?, mode: UInt32?, modified: Date?) {
        let flags = try word()
        guard flags & ~UInt32(0x8000000f) == 0 else { throw SFTPDirectoryError.invalidReply }
        var size: UInt64?
        var mode: UInt32?
        var modified: Date?
        if flags & 1 != 0 {
            let high = try word()
            size = (UInt64(high) << 32) | UInt64(try word())
        }
        if flags & 2 != 0 { _ = try word(); _ = try word() }
        if flags & 4 != 0 { mode = try word() }
        if flags & 8 != 0 {
            _ = try word()
            modified = Date(timeIntervalSince1970: TimeInterval(try word()))
        }
        if flags & 0x80000000 != 0 {
            let count = try word()
            guard count <= 128 else { throw SFTPDirectoryError.invalidReply }
            for _ in 0..<count { _ = try field(); _ = try field() }
        }
        return (size, mode, modified)
    }
}
