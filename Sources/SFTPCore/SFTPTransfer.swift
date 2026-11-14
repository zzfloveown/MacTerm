import Darwin
import Domain
import Foundation

public struct TransferProgress: Sendable {
    public let completed: UInt64
    public let total: UInt64
}

extension SFTPClient {
    /// 使用独占的临时文件，恢复前逐块校验已有内容，完整传输后再发布目标文件。
    public func transfer(local: URL, remote: String, on host: SSHHost, upload: Bool, id: UUID,
                         progress: @escaping @Sendable (TransferProgress) -> Void) async throws {
        try Self.validateProtocolPath(remote)
        try await withChannel(host) { channel in
            let suffix = ".macterm-" + id.uuidString.lowercased() + ".part"
            if upload {
                try channel.upload(local, to: remote, partial: remote + suffix, progress: progress)
            } else {
                try channel.download(remote, to: local, partial: local.appendingPathExtension(String(suffix.dropFirst())),
                                     progress: progress)
            }
        }
    }
}

extension SFTPChannel {
    func upload(_ path: URL, to final: String, partial: String,
                progress: (TransferProgress) -> Void) throws {
        let current = try localAttributes(path)
        try requireAbsent(final)
        let file = try FileHandle(forReadingFrom: path)
        defer { try? file.close() }
        let prior = try remoteAttributes(partial)
        let temporarySize = try prior.map(regularSize) ?? 0
        guard temporarySize <= current.size else { throw ResumeError.changed }
        let handle = try open(partial, flags: prior == nil ? 0x2b : 0x03)
        var closed = false
        defer { if !closed { try? close(handle) } }
        guard try regularSize(attributes(handle, kind: 8)) == temporarySize else { throw ResumeError.changed }
        try verifyPrefix(length: temporarySize, local: file, remote: handle)
        var offset = temporarySize
        progress(TransferProgress(completed: offset, total: current.size))
        while offset < current.size {
            try checkCancellation()
            let data = try readLocal(file, length: chunkSize(current.size - offset))
            _ = try request(6, payload: Data.field(handle) + Data.offset(offset) + Data.field(data), expecting: 101)
            offset += UInt64(data.count)
            progress(TransferProgress(completed: offset, total: current.size))
        }
        guard try localAttributes(path) == current else { throw ResumeError.changed }
        try file.seek(toOffset: 0)
        try verifyPrefix(length: current.size, local: file, remote: handle)
        guard try regularSize(attributes(handle, kind: 8)) == current.size,
              try localAttributes(path) == current else { throw ResumeError.changed }
        try close(handle)
        closed = true
        try requireAbsent(final)
        _ = try request(18, payload: pathField(partial) + pathField(final), expecting: 101)
    }

    func download(_ path: String, to final: URL, partial: URL,
                  progress: (TransferProgress) -> Void) throws {
        let manager = FileManager.default
        guard !manager.fileExists(atPath: final.path) else { throw ResumeError.exists }
        guard let current = try remoteAttributes(path) else { throw SFTPDirectoryError.status(2) }
        let size = try regularSize(current)
        let handle = try open(path, flags: 1)
        defer { try? close(handle) }
        let snapshot = try attributes(handle, kind: 8)
        guard try regularSize(snapshot) == size, snapshot.modified == current.modified else { throw ResumeError.changed }
        let file = try openLocalPartial(partial)
        defer { try? file.close() }
        let temporarySize = try file.seekToEnd()
        guard temporarySize <= size else { throw ResumeError.changed }
        try file.seek(toOffset: 0)
        try verifyPrefix(length: temporarySize, local: file, remote: handle)
        var offset = temporarySize
        progress(TransferProgress(completed: offset, total: size))
        while offset < size {
            try checkCancellation()
            let data = try readRemote(handle, offset: offset, length: chunkSize(size - offset))
            try file.write(contentsOf: data)
            offset += UInt64(data.count)
            progress(TransferProgress(completed: offset, total: size))
        }
        try file.seek(toOffset: 0)
        try verifyPrefix(length: size, local: file, remote: handle)
        let updated = try attributes(handle, kind: 8)
        guard try regularSize(updated) == size, updated.modified == snapshot.modified else { throw ResumeError.changed }
        try file.synchronize()
        // link 在同一目录原子发布，并拒绝覆盖已存在的目标。
        try manager.linkItem(at: partial, to: final)
        try? manager.removeItem(at: partial)
    }

    func pathField(_ value: String) -> Data { Data.field(Data(value.utf8)) }

    func open(_ path: String, flags: UInt32) throws -> Data {
        var response = try request(3, payload: pathField(path) + Data.word(flags) + Data.word(4) + Data.word(0o600), expecting: 102)
        return try response.field()
    }

    func close(_ handle: Data) throws {
        _ = try request(4, payload: Data.field(handle), expecting: 101)
    }

    func attributes(_ value: Data, kind: UInt8) throws -> FileAttributes {
        var packet = try request(kind, payload: Data.field(value), expecting: 105)
        return try packet.attributes()
    }

    func remoteAttributes(_ path: String) throws -> FileAttributes? {
        do { return try attributes(Data(path.utf8), kind: 7) }
        catch SFTPDirectoryError.status(2) { return nil }
    }

    func requireAbsent(_ path: String) throws {
        if try remoteAttributes(path) != nil { throw ResumeError.exists }
    }

    func regularSize(_ attributes: FileAttributes) throws -> UInt64 {
        guard let mode = attributes.mode, mode & 0o170000 == 0o100000,
              let size = attributes.size else { throw ResumeError.notFile }
        return size
    }

    func localAttributes(_ path: URL) throws -> (size: UInt64, modified: Date) {
        let info = try FileManager.default.attributesOfItem(atPath: path.path)
        guard info[.type] as? FileAttributeType == .typeRegular,
              let size = info[.size] as? NSNumber, let modified = info[.modificationDate] as? Date else {
            throw ResumeError.notFile
        }
        return (size.uint64Value, modified)
    }

    func openLocalPartial(_ path: URL) throws -> FileHandle {
        let descriptor = path.withUnsafeFileSystemRepresentation { pointer in
            guard let pointer else { return Int32(-1) }
            return Darwin.open(pointer, O_CREAT | O_RDWR | O_NOFOLLOW | O_NONBLOCK, 0o600)
        }
        guard descriptor >= 0 else { throw ResumeError.notFile }
        var info = stat()
        guard fstat(descriptor, &info) == 0, UInt32(info.st_mode) & UInt32(S_IFMT) == UInt32(S_IFREG), info.st_nlink == 1 else {
            Darwin.close(descriptor)
            throw ResumeError.notFile
        }
        return FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
    }

    func chunkSize(_ remaining: UInt64) -> Int { Int(min(32_768, remaining)) }

    func readLocal(_ file: FileHandle, length: Int) throws -> Data {
        guard let data = try file.read(upToCount: length), data.count == length else { throw ResumeError.changed }
        return data
    }

    func readRemote(_ handle: Data, offset: UInt64, length: Int) throws -> Data {
        var packet = try request(5, payload: Data.field(handle) + Data.offset(offset) + Data.word(UInt32(length)), expecting: 103)
        let contents = try packet.field()
        guard !contents.isEmpty, contents.count <= length else { throw SFTPDirectoryError.invalidReply }
        return contents
    }

    func verifyPrefix(length: UInt64, local: FileHandle, remote: Data) throws {
        var offset: UInt64 = 0
        while offset < length {
            let data = try readRemote(remote, offset: offset, length: chunkSize(length - offset))
            guard try readLocal(local, length: data.count) == data else { throw ResumeError.changed }
            offset += UInt64(data.count)
        }
    }
}

typealias FileAttributes = (size: UInt64?, mode: UInt32?, modified: Date?)

extension Data {
    static func offset(_ value: UInt64) -> Data {
        word(UInt32(value >> 32)) + word(UInt32(truncatingIfNeeded: value))
    }
}

private enum ResumeError: LocalizedError {
    case changed, exists, notFile

    var errorDescription: String? {
        switch self {
        case .changed: "源文件已变化或部分文件校验失败。"
        case .exists: "目标已存在，请更换名称或移动现有文件。"
        case .notFile: "传输仅接受普通文件。"
        }
    }
}
