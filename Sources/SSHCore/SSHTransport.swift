import ConnectionCore
import Domain
import Infrastructure

public protocol SSHTransport: Sendable {
    func execute(on host: SSHHost, arguments: [String]) async throws -> String
}

public struct OpenSSHTransport: SSHTransport {
    public init() {}

    public func execute(on host: SSHHost, arguments: [String]) async throws -> String {
        try await execute(on: host, arguments: arguments, includeStderr: false)
    }

    /// 渲染远端命令时独立转义每个参数，后台调用只允许已验证的主机。
    public func execute(on host: SSHHost, arguments: [String], includeStderr: Bool) async throws -> String {
        try await execute(on: host, arguments: arguments, includeStderr: includeStderr, monitoring: false)
    }

    public func monitor(on host: SSHHost, arguments: [String]) async throws -> String {
        try await execute(on: host, arguments: arguments, includeStderr: false, monitoring: true)
    }

    public func closeMonitoring(on host: SSHHost) async {
        if let args = OpenSSHArguments.closeMonitoring(host) {
            _ = try? await ProcessRunner.run("/usr/bin/ssh", args)
        }
    }

    private func execute(on host: SSHHost, arguments: [String], includeStderr: Bool, monitoring: Bool) async throws -> String {
        guard let command = arguments.first, !command.isEmpty, !command.hasPrefix("-"),
              arguments.allSatisfy({ !$0.utf8.contains(0) }) else {
            throw MacTermError("无效的远端命令。")
        }
        let remote = arguments.map(OpenSSHArguments.shellQuote).joined(separator: " ")
        let args: [String]
        if monitoring && !OpenSSHArguments.terminalConnectionExists(host) {
            args = try OpenSSHArguments.monitoring(host)
        } else {
            args = try OpenSSHArguments.common(host, interactive: false)
        }
        let result = try await ProcessRunner.run("/usr/bin/ssh", args + ["-T", "--", host.address, remote])
        guard result.status == 0 else {
            throw MacTermError("SSH 命令失败（\(result.status)）。请检查连接、主机指纹和非交互认证。")
        }
        return result.text + (includeStderr ? String(decoding: result.diagnostics, as: UTF8.self) : "")
    }
}
