import Domain
import ConnectionCore
import SSHCore
import StorageCore
import SwiftUI

struct TunnelPage: View {
    let host: SSHHost?
    let store: Store
    @State private var profiles: [SSHTunnelProfile] = []
    @State private var selectedProfile: UUID?
    @State private var name = ""
    @State private var mode: SSHTunnelMode = .local
    @State private var port = 8080
    @State private var destination = "127.0.0.1"
    @State private var destinationPort = 80
    @State private var task: Task<Void, Never>?
    @State private var status = ""
    @State private var reconnect = false

    var body: some View {
        Form {
            if let host {
                LabeledContent("SSH 服务器", value: host.label)
                HStack {
                    Picker("已保存配置", selection: $selectedProfile) {
                        Text("临时配置").tag(Optional<UUID>.none)
                        ForEach(profiles) { profile in
                            Text(profile.name).tag(Optional(profile.id))
                        }
                    }
                    Button("新配置") { resetProfile() }.disabled(task != nil)
                    Button("保存配置") { saveProfile(host) }.disabled(task != nil || name.isEmpty)
                    Button("删除配置", role: .destructive) { deleteProfile() }
                        .disabled(task != nil || selectedProfile == nil)
                }
                TextField("配置名称", text: $name).disabled(task != nil)
                Picker("转发方式", selection: $mode) {
                    ForEach(SSHTunnelMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }.disabled(task != nil)
                TextField("回环监听端口", value: $port, format: .number.grouping(.never)).disabled(task != nil)
                if mode != .dynamic {
                    TextField("目的地址", text: $destination).disabled(task != nil)
                    TextField("目的端口", value: $destinationPort, format: .number.grouping(.never)).disabled(task != nil)
                }
                Toggle("连接断开后重试", isOn: $reconnect).disabled(task != nil)
                HStack {
                    Button("启动转发") { start(host) }.disabled(task != nil)
                    Button("停止") { task?.cancel() }.disabled(task == nil)
                }
                if !status.isEmpty { Text(status) }
            } else { Text("请在侧边栏选择服务器") }
        }
        .formStyle(.grouped)
        .task(id: host?.id) { await loadProfiles() }
        .onChange(of: selectedProfile) { _, selection in
            if let selection, let profile = profiles.first(where: { $0.id == selection }) { apply(profile) }
        }
        .onDisappear { task?.cancel() }
    }

    private func start(_ host: SSHHost) {
        let mode = mode, port = port, destination = destination, destinationPort = destinationPort
        let reconnect = reconnect
        status = "正在建立隧道"
        task = Task {
            defer { task = nil }
            while !Task.isCancelled {
                do {
                    try await OpenSSHTransport().forward(on: host, mode: mode, port: port,
                        destination: destination, destinationPort: destinationPort) {
                        Task { @MainActor in
                            if task != nil { status = "隧道已建立" }
                        }
                    }
                    status = "隧道已退出"
                } catch is CancellationError {
                    break
                } catch { status = error.localizedDescription }
                guard reconnect, !Task.isCancelled else { return }
                status += " 五秒后重试。"
                do { try await Task.sleep(for: .seconds(5)) } catch { break }
            }
            status = "隧道已停止"
        }
    }

    private func loadProfiles() async {
        guard let host else { profiles = []; selectedProfile = nil; return }
        do {
            profiles = try await store.tunnels(hostID: host.id)
            if let selectedProfile, let profile = profiles.first(where: { $0.id == selectedProfile }) {
                apply(profile)
            }
        } catch { status = error.localizedDescription }
    }

    private func saveProfile(_ host: SSHHost) {
        guard (1...65535).contains(port),
              mode == .dynamic || (1...65535).contains(destinationPort) else {
            status = "请使用 1 至 65535 之间的端口。"
            return
        }
        if mode != .dynamic {
            do { try OpenSSHArguments.validate(SSHHost(address: destination, user: "check", port: destinationPort)) }
            catch { status = "目的地址格式无效。"; return }
        }
        let profile = SSHTunnelProfile(id: selectedProfile ?? UUID(), hostID: host.id, name: name,
            mode: mode, listenPort: port, destination: destination,
            destinationPort: destinationPort, reconnect: reconnect)
        Task {
            do {
                try await store.save(profile)
                selectedProfile = profile.id
                await loadProfiles()
                status = "隧道配置已保存"
            } catch { status = error.localizedDescription }
        }
    }

    private func deleteProfile() {
        guard let selectedProfile else { return }
        Task {
            do {
                try await store.deleteTunnel(selectedProfile)
                resetProfile()
                await loadProfiles()
                status = "隧道配置已删除"
            } catch { status = error.localizedDescription }
        }
    }

    private func apply(_ profile: SSHTunnelProfile) {
        name = profile.name
        mode = profile.mode
        port = profile.listenPort
        destination = profile.destination
        destinationPort = profile.destinationPort
        reconnect = profile.reconnect
    }

    private func resetProfile() {
        selectedProfile = nil
        name = ""
        mode = .local
        port = 8080
        destination = "127.0.0.1"
        destinationPort = 80
        reconnect = false
    }
}
