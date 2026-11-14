import ConnectionCore
import Domain
import Infrastructure

public enum ForwardMode: String, CaseIterable, Sendable {
    case local = "本地转发", remote = "远程转发", dynamic = "SOCKS5"
}

extension OpenSSHTransport {
    /// 转发仅绑定回环接口，前台进程在调用任务取消时终止。
    public func forward(on host: Host, mode: ForwardMode, port: Int, destination: String, destinationPort: Int) async throws {
        guard (1...65535).contains(port) else { throw MacTermError("本地或远端监听端口无效。") }
        var mapping = "127.0.0.1:\(port)"
        if mode != .dynamic {
            try OpenSSHArguments.validate(Host(address: destination, user: "check", port: destinationPort))
            let target = destination.contains(":") ? "[\(destination)]" : destination
            mapping += ":\(target):\(destinationPort)"
        }
        let option: String
        switch mode {
        case .local: option = "-L"
        case .remote: option = "-R"
        case .dynamic: option = "-D"
        }
        let args = try OpenSSHArguments.common(host, interactive: false)
        let result = try await ProcessRunner.run("/usr/bin/ssh",
            args + ["-o", "ExitOnForwardFailure=yes", "-N", "-T", option, mapping, "--", host.address])
        if result.status != 0 {
            throw MacTermError("隧道退出（\(result.status)）。请检查端口占用、认证及转发权限。")
        }
    }
}
