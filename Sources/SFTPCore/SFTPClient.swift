import ConnectionCore
import Domain
import Foundation
import Infrastructure

public struct SFTPClient: Sendable {
    public init() {}

    public func list(_ directory: String, on host: SSHHost) async throws -> [String] {
        try await entries(directory, on: host).map(\.name)
    }

    public func upload(local: String, remote: String, on host: SSHHost) async throws {
        _ = try await batch("put \(Self.path(local)) \(Self.path(remote))", on: host)
    }

    public func download(remote: String, local: String, on host: SSHHost) async throws {
        _ = try await batch("get \(Self.path(remote)) \(Self.path(local))", on: host)
    }

    /// 批处理只允许绝对、无控制字符、无通配符的路径，防止命令和模式展开。
    static func path(_ path: String) throws -> String {
        guard path.hasPrefix("/"),
              !path.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
              !path.contains(where: { #""\*?[]{}"#.contains($0) }) else {
            throw MacTermError("SFTP 路径需为无控制字符、引号或通配符的绝对路径。")
        }
        return "\"\(path)\""
    }

    private func batch(_ command: String, on host: SSHHost) async throws -> String {
        let args = try OpenSSHArguments.common(host, interactive: false)
        let result = try await ProcessRunner.run("/usr/bin/sftp", args + ["-b", "-", "--", host.address],
                                                 input: Data((command + "\n").utf8))
        guard result.status == 0 else {
            throw MacTermError("SFTP 操作失败（\(result.status)）。请检查认证、路径及权限。")
        }
        return result.text
    }
}
