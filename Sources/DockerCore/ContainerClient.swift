import Domain
import SSHCore

public enum ContainerEngine: String, CaseIterable, Sendable { case docker, nerdctl }

public struct ContainerClient: Sendable {
    let transport: any SSHTransport
    public init(transport: any SSHTransport = OpenSSHTransport()) { self.transport = transport }

    public func detect(on host: SSHHost) async throws -> ContainerEngine {
        for engine in ContainerEngine.allCases {
            do {
                _ = try await transport.execute(on: host, arguments: [engine.rawValue, "info"])
                return engine
            } catch is CancellationError {
                throw CancellationError()
            } catch { continue }
        }
        throw MacTermError("Docker 和 nerdctl 均不可用。请检查连接、安装状态和管理权限。")
    }

    public func execute(_ arguments: [String], engine: ContainerEngine, on host: SSHHost) async throws -> String {
        try await transport.execute(on: host, arguments: [engine.rawValue] + arguments)
    }
}
