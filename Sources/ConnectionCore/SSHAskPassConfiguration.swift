import Darwin
import Domain
import Foundation

/// 为 OpenSSH 建立不含凭据的一次性 askpass 环境；秘密仍只在 Keychain 和管道中流动。
public enum SSHAskPassConfiguration {
    public static func makeEnvironment(hostID: UUID, helper: URL) throws -> [String: String] {
        guard helper.isFileURL, FileManager.default.isExecutableFile(atPath: helper.path) else {
            throw MacTermError("Keychain 认证助手不可用。")
        }
        let token = FileManager.default.temporaryDirectory
            .appendingPathComponent("macterm-askpass-\(UUID().uuidString)", isDirectory: false)
        let descriptor = open(token.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
        guard descriptor >= 0 else { throw MacTermError("无法创建 SSH 一次性认证令牌。") }
        let contents = Data(hostID.uuidString.utf8)
        let written = contents.withUnsafeBytes { bytes in
            Darwin.write(descriptor, bytes.baseAddress, bytes.count)
        }
        let closeStatus = close(descriptor)
        guard written == contents.count, closeStatus == 0 else {
            _ = unlink(token.path)
            throw MacTermError("无法写入 SSH 一次性认证令牌。")
        }
        return ["SSH_ASKPASS": helper.path,
                "SSH_ASKPASS_REQUIRE": "force",
                "DISPLAY": ProcessInfo.processInfo.environment["DISPLAY"] ?? "MacTerm:0",
                "MACTERM_ASKPASS_TOKEN": token.path]
    }
}
