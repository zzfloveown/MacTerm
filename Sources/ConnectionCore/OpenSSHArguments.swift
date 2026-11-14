import Domain
import Foundation

public enum OpenSSHArguments {
    /// 只接受主机名、IPv4 或无作用域 IPv6，阻止配置插值及参数歧义。
    public static func validate(_ host: SSHHost) throws {
        let user = #"^[A-Za-z0-9_][A-Za-z0-9_.-]*\z"#
        let address = #"^(?:[A-Za-z0-9][A-Za-z0-9.-]*|[a-fA-F0-9]*:[a-fA-F0-9:]+)\z"#
        let jump = #"^(?:[A-Za-z0-9_][A-Za-z0-9_.-]*@)?(?:[A-Za-z0-9][A-Za-z0-9.-]*|\[[a-fA-F0-9:]+\])(?::[0-9]{1,5})?\z"#
        guard host.user.range(of: user, options: .regularExpression) != nil,
              host.address.range(of: address, options: .regularExpression) != nil,
              (1...65535).contains(host.port),
              host.identity.isEmpty || (host.identity.hasPrefix("/") && !host.identity.contains("%") && !host.identity.utf8.contains(0)),
              host.jump.isEmpty || host.jump.split(separator: ",", omittingEmptySubsequences: false).allSatisfy({
                  $0.range(of: jump, options: .regularExpression) != nil
              }) else { throw MacTermError("请检查用户名、主机、端口、私钥绝对路径和跳板机。") }
    }

    public static func common(_ host: SSHHost, interactive: Bool) throws -> [String] {
        try validate(host)
        var args = ["-F", "/dev/null", "-o", "Port=\(host.port)",
                    "-o", "User=\(host.user)", "-o", "ConnectTimeout=10",
                    "-o", "ServerAliveInterval=15", "-o", "ServerAliveCountMax=2",
                    "-o", "StrictHostKeyChecking=\(interactive ? "ask" : "yes")",
                    "-o", "ForwardAgent=no", "-o", "BatchMode=\(interactive ? "no" : "yes")"]
        if let socket = SSHControlPath.forHost(host) {
            args += ["-o", "ControlPath=\(socket)", "-o", "ControlMaster=\(interactive ? "auto" : "no")"]
        }
        if !host.identity.isEmpty { args += ["-i", host.identity, "-o", "IdentitiesOnly=yes"] }
        if !host.jump.isEmpty { args += ["-J", host.jump] }
        return args
    }

    public static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
