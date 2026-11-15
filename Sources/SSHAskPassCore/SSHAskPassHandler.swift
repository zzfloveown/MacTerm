import Darwin
import Foundation

/// 限定 OpenSSH askpass 只回答一次明确的密码提示，并消费一次性令牌。
public enum SSHAskPassHandler {
    public static func credential(for prompt: String, tokenURL: URL,
                                  lookup: (UUID) throws -> Data?) throws -> Data? {
        let normalized = prompt.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        // 仅匹配 OpenSSH 的账号密码格式；服务器自定义的 "Password:" 可能是 OTP。
        guard normalized.hasSuffix("'s password:"),
              !normalized.contains("verification"), !normalized.contains("token"),
              !normalized.contains("passphrase") else { return nil }
        let descriptor = open(tokenURL.path, O_RDONLY | O_NOFOLLOW)
        guard descriptor >= 0 else { return nil }
        defer { close(descriptor) }
        var metadata = stat()
        guard fstat(descriptor, &metadata) == 0,
              (metadata.st_mode & S_IFMT) == S_IFREG,
              metadata.st_uid == getuid(),
              (metadata.st_mode & 0o077) == 0,
              metadata.st_size == 36 else { return nil }
        guard unlink(tokenURL.path) == 0 else { return nil }
        var bytes = [UInt8](repeating: 0, count: 36)
        let count = bytes.withUnsafeMutableBufferPointer { buffer in
            Darwin.read(descriptor, buffer.baseAddress, buffer.count)
        }
        guard count == bytes.count else { return nil }
        let data = Data(bytes)
        guard data.count == 36, let identifier = String(data: data, encoding: .utf8),
              let hostID = UUID(uuidString: identifier) else { return nil }
        return try lookup(hostID)
    }
}
