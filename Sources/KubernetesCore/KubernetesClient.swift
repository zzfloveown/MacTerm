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

    public func namespaces(context: String) async throws -> [String] {
        let text = try await run(["--context=\(context)", "get", "namespaces", "-o", "name"])
        return text.split(whereSeparator: \.isNewline).map { String($0.split(separator: "/").last ?? $0) }
    }

    public func list(_ resource: Resource, context: String, namespace: String) async throws -> String {
        var args = ["--context=\(context)", "get", resource.rawValue]
        if !resource.clusterScoped { args.append("--namespace=\(namespace)") }
        if resource == .secrets {
            args += ["-o", "custom-columns=NAME:.metadata.name,TYPE:.type"]
        }
        return try await run(args)
    }

    public func logs(pod: String, container: String, context: String, namespace: String) async throws -> String {
        var args = try target(pod, container: container, context: context, namespace: namespace)
        args += ["logs", "--tail=200", pod]
        if !container.isEmpty { args.append("--container=\(container)") }
        return try await run(args)
    }

    public func scale(deployment: String, replicas: Int, context: String, namespace: String) async throws -> String {
        guard (0...10_000).contains(replicas) else { throw CocoaError(.fileReadInvalidFileName) }
        let args = try target(deployment, container: "", context: context, namespace: namespace)
        return try await run(args + ["scale", "deployment/" + deployment, "--replicas=\(replicas)"])
    }

    public func shellArguments(pod: String, container: String, context: String, namespace: String) throws -> [String] {
        try validateConfiguration()
        var args = try target(pod, container: container, context: context, namespace: namespace)
        args = ["--kubeconfig=\(config)"] + args
        args += ["exec", "-it", pod]
        if !container.isEmpty { args.append("--container=\(container)") }
        return args + ["--", "/bin/sh"]
    }

    private func target(_ name: String, container: String, context: String, namespace: String) throws -> [String] {
        let valid: (String) -> Bool = { $0.range(of: #"^[a-z0-9][a-z0-9.-]*\z"#, options: .regularExpression) != nil }
        guard valid(name), valid(namespace), container.isEmpty || valid(container), !context.isEmpty else {
            throw CocoaError(.fileReadInvalidFileName)
        }
        return ["--context=\(context)", "--namespace=\(namespace)"]
    }

    private func validateConfiguration() throws {
        guard binary.hasPrefix("/"), config.hasPrefix("/"),
              FileManager.default.isExecutableFile(atPath: binary), FileManager.default.isReadableFile(atPath: config) else {
            throw CocoaError(.fileReadInvalidFileName)
        }
    }

    private func run(_ arguments: [String]) async throws -> String {
        try validateConfiguration()
        let result = try await ProcessRunner.run(binary, ["--kubeconfig=\(config)", "--request-timeout=10s"] + arguments)
        guard result.status == 0 else {
            throw NSError(domain: "MacTerm.Kubernetes", code: Int(result.status),
                          userInfo: [NSLocalizedDescriptionKey: "kubectl 执行失败。请检查配置、连接和集群权限。"])
        }
        return result.text
    }
}
