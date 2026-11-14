import Foundation
import Infrastructure

public enum Resource: String, CaseIterable, Identifiable, Sendable {
    case nodes, pods, deployments, statefulsets, daemonsets, services, configmaps, secrets, events, namespaces
    public var id: String { rawValue }
    var clusterScoped: Bool { self == .nodes || self == .namespaces }
}

public struct KubernetesClient: Sendable {
    public let binary: String
    public let config: String

    public init(binary: String, config: String) {
        self.binary = binary
        self.config = config
    }

    public func contexts() async throws -> String {
        try await run(["config", "get-contexts", "-o", "name"])
    }

    public func list(_ resource: Resource, context: String, namespace: String) async throws -> String {
        var args = ["--context=\(context)", "get", resource.rawValue]
        if !resource.clusterScoped { args.append("--namespace=\(namespace)") }
        if resource == .secrets {
            args += ["-o", "custom-columns=NAME:.metadata.name,TYPE:.type"]
        }
        return try await run(args)
    }

    private func run(_ arguments: [String]) async throws -> String {
        guard binary.hasPrefix("/"), config.hasPrefix("/") else {
            throw CocoaError(.fileReadInvalidFileName)
        }
        let result = try await ProcessRunner.run(binary, ["--kubeconfig=\(config)", "--request-timeout=10s"] + arguments)
        guard result.status == 0 else {
            throw NSError(domain: "MacTerm.Kubernetes", code: Int(result.status),
                          userInfo: [NSLocalizedDescriptionKey: "kubectl 执行失败。请检查配置、连接和集群权限。"])
        }
        return result.text
    }
}
