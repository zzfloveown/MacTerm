import DockerCore
import Domain
import KubernetesCore
import SwiftUI
import UniformTypeIdentifiers

struct ContainerPage: View {
    enum Kind: String, CaseIterable {
        case container = "容器", image = "镜像", network = "网络", volume = "数据卷"
        var cli: String {
            switch self {
            case .container: "container"
            case .image: "image"
            case .network: "network"
            case .volume: "volume"
            }
        }
    }

    let host: SSHHost
    var openTerminal: ([String], String) -> Void
    let client = ContainerClient()
    @State private var engine: ContainerEngine?
    @State private var output = ""
    @State private var target = ""
    @State private var kind: Kind = .container
    @State private var busy = false
    @State private var removing: Removal?

    struct Removal {
        let kind: Kind
        let target: String
    }

    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Picker("资源", selection: $kind) {
                    ForEach(Kind.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.segmented)
                Button("刷新") { refresh() }
                Button("资源统计") { run(["stats", "--no-stream"]) }
                if busy { ProgressView().controlSize(.small) }
                Text(engine?.rawValue ?? host.label).foregroundStyle(.secondary)
            }.disabled(busy)
            HStack {
                TextField(kind.rawValue + "名称或 ID", text: $target)
                switch kind {
                case .container:
                    Button("启动") { run(["start", target]) }
                    Button("停止") { run(["stop", target]) }
                    Button("重启") { run(["restart", target]) }
                    Button("日志") { run(["logs", "--tail", "200", target], includeStderr: true) }
                    Button("终端") {
                        if let engine { openTerminal([engine.rawValue, "exec", "-it", target, "/bin/sh"], target) }
                    }.disabled(engine == nil)
                case .image:
                    Button("拉取") { run(["pull", target], refreshAfter: true) }
                case .network, .volume:
                    Button("创建") { run([kind.cli, "create", target], refreshAfter: true) }
                }
                Button("删除", role: .destructive) { removing = Removal(kind: kind, target: target) }
            }.disabled(busy || !validTarget)
            CommandOutput(text: output)
        }
        .task { refresh() }
        .onChange(of: kind) { _, _ in target = ""; refresh() }
        .confirmationDialog("删除资源？", isPresented: Binding(
            get: { removing != nil }, set: { if !$0 { removing = nil } }
        ), titleVisibility: .visible, presenting: removing) { item in
            Button("确认删除", role: .destructive) { run([item.kind.cli, "rm", item.target], refreshAfter: true) }
        } message: { Text($0.kind.rawValue + " " + $0.target) }
    }

    private var validTarget: Bool {
        let pattern = kind == .image ? #"^[a-zA-Z0-9][a-zA-Z0-9_.:/@-]*\z"# : #"^[a-zA-Z0-9][a-zA-Z0-9_.-]*\z"#
        return target.range(of: pattern, options: .regularExpression) != nil
    }

    private var listArguments: [String] { kind == .container ? ["ps", "-a"] : [kind.cli, "ls"] }

    private func refresh() { run(listArguments) }

    private func run(_ args: [String], refreshAfter: Bool = false, includeStderr: Bool = false) {
        guard !busy else { return }
        busy = true
        let listing = listArguments
        Task {
            defer { busy = false }
            do {
                let detected: ContainerEngine
                if let engine { detected = engine }
                else { detected = try await client.detect(on: host) }
                engine = detected
                var result = try await client.execute(args, engine: detected, on: host, includeStderr: includeStderr)
                if refreshAfter {
                    result += "\n" + (try await client.execute(listing, engine: detected, on: host))
                }
                output = result
            } catch { output = error.localizedDescription }
        }
    }
}

struct KubernetesPage: View {
    var openTerminal: (String, [String], String) -> Void
    @AppStorage("kubectlPath") private var binary = "/opt/homebrew/bin/kubectl"
    @AppStorage("kubeconfigPath") private var config = ""
    @State private var context = ""
    @State private var contexts: [String] = []
    @State private var namespace = "default"
    @State private var namespaceItems: [String] = []
    @State private var resource: Resource = .pods
    @State private var output = ""
    @State private var busy = false
    @State private var target = ""
    @State private var container = ""
    @State private var replicas = 1
    @State private var confirmScale = false
    @State private var picking = false

    var body: some View {
        VStack(alignment: .leading) {
            TextField("kubectl 绝对路径", text: $binary)
            HStack {
                TextField("已授权 kubeconfig 的绝对路径", text: $config)
                Button("选择文件") { picking = true }
                Button("列出 Context") { loadContexts() }.disabled(busy || config.isEmpty)
            }
            HStack {
                if contexts.isEmpty { TextField("Context", text: $context) }
                else {
                    Picker("Context", selection: $context) {
                        ForEach(contexts, id: \.self) { Text($0).tag($0) }
                    }
                }
                if namespaceItems.isEmpty { TextField("Namespace", text: $namespace) }
                else {
                    Picker("Namespace", selection: $namespace) {
                        ForEach(namespaceItems, id: \.self) { Text($0).tag($0) }
                    }
                }
                Button("刷新 Namespace") {
                    let selected = context
                    request { client in
                        let names = try await client.namespaces(context: selected)
                        namespaceItems = names
                        if !names.contains(namespace) { namespace = names.first ?? "default" }
                        return names.joined(separator: "\n")
                    }
                }.disabled(!canQuery)
            }
            HStack {
                Picker("资源", selection: $resource) {
                    ForEach(Resource.allCases) { Text($0.rawValue).tag($0) }
                }.fixedSize()
                Button("查询") {
                    let selected = resource, context = context, namespace = namespace
                    request { try await $0.list(selected, context: context, namespace: namespace) }
                }.disabled(!canQuery)
                if busy { ProgressView().controlSize(.small) }
            }
            if resource == .pods || resource == .deployments {
                HStack {
                    TextField(resource == .pods ? "Pod 名称" : "Deployment 名称", text: $target)
                    if resource == .pods {
                        TextField("容器（可选）", text: $container)
                        Button("日志") {
                            let pod = target, container = container, context = context, namespace = namespace
                            request { try await $0.logs(pod: pod, container: container, context: context, namespace: namespace) }
                        }
                        Button("终端") { shell() }
                    } else {
                        TextField("副本数", value: $replicas, format: .number.grouping(.never)).frame(width: 90)
                        Button("扩缩容") { confirmScale = true }
                    }
                }.disabled(!canQuery)
            }
            CommandOutput(text: output)
        }
        .onChange(of: context) { _, _ in namespaceItems = []; target = "" }
        .onChange(of: config) { _, _ in contexts = []; namespaceItems = []; context = "" }
        .fileImporter(isPresented: $picking, allowedContentTypes: [.item]) {
            if case .success(let url) = $0 { config = url.path }
        }
        .confirmationDialog("将 \(target) 调整为 \(replicas) 个副本？", isPresented: $confirmScale, titleVisibility: .visible) {
            Button("确认扩缩容") {
                let name = target, count = replicas, context = context, namespace = namespace
                request { try await $0.scale(deployment: name, replicas: count, context: context, namespace: namespace) }
            }
        }
    }

    private var canQuery: Bool { !busy && !config.isEmpty && !context.isEmpty }

    private func loadContexts() {
        request { client in
            let names = try await client.contexts().split(whereSeparator: \.isNewline).map(String.init)
            contexts = names
            if !names.contains(context) { context = names.first ?? "" }
            return names.joined(separator: "\n")
        }
    }

    private func shell() {
        do {
            let client = KubernetesClient(binary: binary, config: config)
            let args = try client.shellArguments(pod: target, container: container, context: context, namespace: namespace)
            openTerminal(client.binary, args, target)
        } catch { output = error.localizedDescription }
    }

    private func request(_ action: @escaping (KubernetesClient) async throws -> String) {
        guard !busy else { return }
        let client = KubernetesClient(binary: binary, config: config)
        busy = true
        Task {
            defer { busy = false }
            do { output = try await action(client) }
            catch { output = error.localizedDescription }
        }
    }
}

struct CommandOutput: View {
    let text: String
    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            Text(text).font(.system(.body, design: .monospaced)).textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading).padding(8)
        }.background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 6))
    }
}
