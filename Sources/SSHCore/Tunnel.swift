import ConnectionCore
import Domain
import Foundation
import Infrastructure

public enum ForwardMode: String, CaseIterable, Sendable {
    case local = "本地转发", remote = "远程转发", dynamic = "SOCKS5"
}

extension OpenSSHTransport {
    /// 使用独立的控制套接字确认监听建立，任务取消后清理转发进程。
    public func forward(on host: SSHHost, mode: ForwardMode, port: Int, destination: String,
                        destinationPort: Int, onReady: @escaping @Sendable () -> Void = {}) async throws {
        guard (1...65535).contains(port) else { throw MacTermError("监听端口无效。") }
        var mapping = "127.0.0.1:\(port)"
        if mode != .dynamic {
            try OpenSSHArguments.validate(SSHHost(address: destination, user: "check", port: destinationPort))
            let target = destination.contains(":") ? "[\(destination)]" : destination
            mapping += ":\(target):\(destinationPort)"
        }
        let option: String
        switch mode {
        case .local: option = "-L"
        case .remote: option = "-R"
        case .dynamic: option = "-D"
        }

        let directory = URL(fileURLWithPath: "/tmp", isDirectory: true)
            .appendingPathComponent("macterm-forward-" + UUID().uuidString.prefix(12), isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false,
                                                attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: directory) }
        let socket = directory.appendingPathComponent("s").path
        let base = try OpenSSHArguments.common(host, interactive: false, sharesConnection: false)
        let command = base + ["-M", "-S", socket, "-o", "ExitOnForwardFailure=yes",
                              "-N", "-T", option, mapping, "--", host.address]
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                let result = try await ProcessRunner.run("/usr/bin/ssh", command)
                guard result.status == 0 else {
                    throw MacTermError("隧道无法建立或已断开。请检查端口占用、认证及转发权限。")
                }
            }
            group.addTask {
                for _ in 0..<60 {
                    try Task.checkCancellation()
                    if FileManager.default.fileExists(atPath: socket) {
                        let result = try await ProcessRunner.run("/usr/bin/ssh",
                            ["-F", "/dev/null", "-S", socket, "-O", "check", "--", host.address])
                        if result.status == 0 {
                            onReady()
                            try await Task.sleep(for: .seconds(Int32.max))
                            return
                        }
                    }
                    try await Task.sleep(for: .milliseconds(200))
                }
                throw MacTermError("隧道建立超时。")
            }
            defer { group.cancelAll() }
            _ = try await group.next()
            try Task.checkCancellation()
        }
    }
}
