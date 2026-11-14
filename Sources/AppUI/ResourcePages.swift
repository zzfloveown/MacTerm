import DockerCore
import Domain
import KubernetesCore
import SwiftUI

struct ContainerPage: View {
    let host: Host
    let client = ContainerClient()
    @State private var engine: ContainerEngine?
    @State private var output = ""
    @State private var target = ""
    @State private var busy = false
    @State private var remove = false

    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Button("容器") { run(["ps", "-a"]) }
                Button("镜像") { run(["images"]) }
                Button("网络") { run(["network", "ls"]) }
                Button("数据卷") { run(["volume", "ls"]) }
                Button("资源统计") { run(["stats", "--no-stream"]) }
                Spacer()
                if busy { ProgressView().controlSize(.small) }
                Text(engine?.rawValue ?? host.label).foregroundStyle(.secondary)
            }.disabled(busy)
            HStack {
                TextField("容器名称或 ID", text: $target)
                Button("启动") { action("start") }
                Button("停止") { action("stop") }
                Button("重启") { action("restart") }
                Button("日志") { run(["logs", "--tail", "200", target]) }
                Button("删除", role: .destructive) { remove = true }
            }.disabled(busy || !validTarget)
            CommandOutput(text: output)
        }.confirmationDialog("删除容器 \(target)？", isPresented: $remove, titleVisibility: .visible) {
            Button("确认删除", role: .destructive) { action("rm") }
        }
    }

    private var validTarget: Bool {
        target.range(of: "^[a-zA-Z0-9][a-zA-Z0-9_.-]*$", options: .regularExpression) != nil
    }

    private func action(_ operation: String) { if validTarget { run([operation, target]) } }

    private func run(_ args: [String]) {
        busy = true
        Task {
            defer { busy = false }
            do {
                let detected: ContainerEngine
                if let engine { detected = engine }
                else { detected = try await client.detect(on: host) }
                engine = detected
                output = try await client.execute(args, engine: detected, on: host)
            } catch { output = error.localizedDescription }
        }
    }
}

struct KubernetesPage: View {
    @State private var binary = "/opt/homebrew/bin/kubectl"
    @State private var config = ""
    @State private var context = ""
    @State private var namespace = "default"
    @State private var resource: Resource = .pods
    @State private var output = ""
    @State private var busy = false

    var body: some View {
        VStack(alignment: .leading) {
            TextField("kubectl 绝对路径", text: $binary)
            HStack {
                TextField("已授权 kubeconfig 的绝对路径", text: $config)
                Button("列出 Context") { request(contexts: true) }.disabled(busy || config.isEmpty)
            }
            HStack {
                TextField("Context", text: $context)
                TextField("Namespace", text: $namespace)
                Picker("资源", selection: $resource) {
                    ForEach(Resource.allCases) { Text($0.rawValue).tag($0) }
                }.fixedSize()
                Button("查询") { request(contexts: false) }.disabled(busy || config.isEmpty || context.isEmpty)
            }
            CommandOutput(text: output)
        }
    }

    private func request(contexts: Bool) {
        let client = KubernetesClient(binary: binary, config: config)
        let selectedContext = context
        let selectedNamespace = namespace
        let selectedResource = resource
        busy = true
        Task {
            defer { busy = false }
            do {
                if contexts { output = try await client.contexts() }
                else { output = try await client.list(selectedResource, context: selectedContext, namespace: selectedNamespace) }
            } catch { output = error.localizedDescription }
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
