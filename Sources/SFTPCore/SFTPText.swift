import Domain
import Foundation

public struct RemoteText: Sendable {
    public let text: String
    fileprivate let bytes: Data
    fileprivate let mode: UInt32
}

extension SFTPClient {
    /// 文本编辑仅接受小型 UTF-8 普通文件。提交前回读内容，避免覆盖已修改版本。
    public func readText(at path: String, on host: SSHHost) async throws -> RemoteText {
        try Self.validateProtocolPath(path)
        return try await withChannel(host) { channel in try channel.readText(path) }
    }

    public func writeText(_ text: String, basedOn original: RemoteText, at path: String, on host: SSHHost) async throws {
        try Self.validateProtocolPath(path)
        let contents = Data(text.utf8)
        guard contents.count <= 1_048_576 else { throw MacTermError("远端文本编辑上限为 1 MiB。") }
        try await withChannel(host) { channel in
            let current = try channel.readText(path)
            guard current.bytes == original.bytes, current.mode == original.mode else {
                throw MacTermError("远端文件已变化。请重新打开后再编辑。")
            }
            let temporary = path + ".macterm-edit-" + UUID().uuidString.lowercased()
            let handle = try channel.open(temporary, flags: 0x2b)
            var open = true
            var published = false
            defer {
                if open { try? channel.close(handle) }
                if !published {
                    _ = try? channel.request(13, payload: channel.pathField(temporary), expecting: 101)
                }
            }
            var offset = 0
            while offset < contents.count {
                let end = min(contents.count, offset + 32_768)
                let payload = Data.field(handle) + Data.offset(UInt64(offset)) + Data.field(contents.subdata(in: offset..<end))
                _ = try channel.request(6, payload: payload, expecting: 101)
                offset = end
            }
            _ = try channel.request(10, payload: Data.field(handle) + Data.word(4) + Data.word(current.mode & 0o777),
                                    expecting: 101)
            try channel.close(handle)
            open = false

            let check = try channel.readText(path)
            guard check.bytes == original.bytes, check.mode == original.mode else {
                throw MacTermError("远端文件在保存期间已变化。")
            }
            let operation = Data.field(Data("posix-rename@openssh.com".utf8))
                + channel.pathField(temporary) + channel.pathField(path)
            _ = try channel.request(200, payload: operation, expecting: 101)
            published = true
        }
    }
}

private extension SFTPChannel {
    func readText(_ path: String) throws -> RemoteText {
        guard let attrs = try remoteAttributes(path), let mode = attrs.mode else {
            throw SFTPDirectoryError.status(2)
        }
        let size = try regularSize(attrs)
        guard size <= 1_048_576 else { throw MacTermError("远端文本编辑上限为 1 MiB。") }
        let handle = try open(path, flags: 1)
        defer { try? close(handle) }
        var data = Data()
        while UInt64(data.count) < size {
            data.append(try readRemote(handle, offset: UInt64(data.count), length: chunkSize(size - UInt64(data.count))))
        }
        let end = try attributes(handle, kind: 8)
        guard try regularSize(end) == size, end.modified == attrs.modified,
              !data.contains(0), let text = String(data: data, encoding: .utf8) else {
            throw MacTermError("文件已变化或内容不是 UTF-8 文本。")
        }
        return RemoteText(text: text, bytes: data, mode: mode)
    }
}
