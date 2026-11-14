import ConnectionCore
import Domain
import Foundation
import Infrastructure

public enum SSHKeyService {
    /// 生成用户持有的 Ed25519 密钥，目录仅对当前用户开放。
    public static func generate(in root: URL) async throws -> URL {
        let folder = root.appendingPathComponent("Keys", isDirectory: true)
        let manager = FileManager.default
        try manager.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let path = folder.appendingPathComponent("id_ed25519_" + UUID().uuidString.lowercased())
        let result = try await ProcessRunner.run("/usr/bin/ssh-keygen",
            ["-q", "-t", "ed25519", "-N", "", "-C", "MacTerm", "-f", path.path])
        guard result.status == 0 else { throw MacTermError("无法生成 SSH 密钥。") }
        return path
    }

    public static func fingerprints(_ host: SSHHost) async throws -> String {
        try OpenSSHArguments.validate(host)
        let address = host.port == 22 ? host.address : "[\(host.address)]:\(host.port)"
        let home = FileManager.default.homeDirectoryForCurrentUser
        var lines: [String] = []
        for file in [home.appendingPathComponent(".ssh/known_hosts"), home.appendingPathComponent(".ssh/known_hosts2")] {
            guard FileManager.default.fileExists(atPath: file.path) else { continue }
            let lookup = try await ProcessRunner.run("/usr/bin/ssh-keygen", ["-F", address, "-f", file.path])
            guard lookup.status == 0 else { continue }
            let fingerprint = try await ProcessRunner.run("/usr/bin/ssh-keygen", ["-lf", "-"], input: lookup.output)
            if fingerprint.status == 0 { lines.append(fingerprint.text) }
        }
        return lines.isEmpty ? "当前账户尚未保存此服务器的指纹。" : lines.joined()
    }

    public static func publicKey(at identity: String) async throws -> String {
        let path = identity + ".pub"
        return try await Task.detached {
            let url = URL(fileURLWithPath: path)
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            guard let data = try handle.read(upToCount: 16384),
                  let text = String(data: data, encoding: .utf8),
                  text.hasPrefix("ssh-") || text.hasPrefix("ecdsa-") || text.hasPrefix("sk-") else {
                throw MacTermError("无法读取对应的公钥文件。")
            }
            return text
        }.value
    }
}
