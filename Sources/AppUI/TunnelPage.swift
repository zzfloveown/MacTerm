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
    @State private var tasks: [UUID: Task<Void, Never>] = [:]
    @State private var statuses: [UUID: String] = [:]
    @State private var adHocID = UUID()
    @State private var status = ""
    @State private var reconnect = false
    @State private var deletingProfile: SSHTunnelProfile?

    private var currentKey: UUID { selectedProfile ?? adHocID }
    private var isCurrentRunning: Bool { tasks[currentKey] != nil }

    var body: some View {
        Form {
            if let host {
                SwiftUI.Section("当前服务器") {
                    LabeledContent("SSH 服务器", value: "\(host.label) (\(host.user)@\(host.address):\(host.port))")
                    LabeledContent("运行中隧道", value: "\(tasks.count) 条")
                }
                if !profiles.isEmpty {
                    SwiftUI.Section("已保存隧道") {
                        ForEach(profiles) { profile in
                            HStack(spacing: 10) {
                                Circle()
                                    .fill(tasks[profile.id] != nil ? Color.green : Color.secondary.opacity(0.4))
                                    .frame(width: 8, height: 8)
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 6) {
                                        Text(profile.name).font(.headline)
                                        Text(profile.mode.rawValue)
                                            .font(.caption2)
                                            .padding(.horizontal, 6).padding(.vertical, 2)
                                            .background(.blue.opacity(0.12), in: Capsule())
                                        if profile.reconnect {
                                            Text("自动重试").font(.caption2).foregroundStyle(.secondary)
                                        }
                                    }
                                    Text(summary(for: profile))
                                        .font(.caption.monospaced())
                                        .foregroundStyle(.secondary)
                                    if let profileStatus = statuses[profile.id], !profileStatus.isEmpty {
                                        Text(profileStatus).font(.caption2).foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                if tasks[profile.id] != nil {
                                    Button("停止") { tasks[profile.id]?.cancel() }
                                } else {
                                    Button("启动") {
                                        start(id: profile.id, on: host, mode: profile.mode, port: profile.listenPort,
                                              destination: profile.destination, destinationPort: profile.destinationPort,
                                              reconnect: profile.reconnect)
                                    }
                                }
                                Button("编辑") {
                                    selectedProfile = profile.id
                                    apply(profile)
                                }.disabled(tasks[profile.id] != nil)
                                Button("删除", role: .destructive) {
                                    deletingProfile = profile
                                }.disabled(tasks[profile.id] != nil)
                            }
                        }
                    }
                }
                SwiftUI.Section("隧道配置与转发") {
                    HStack {
                        Picker("配置项", selection: $selectedProfile) {
                            Text("新建 / 临时配置").tag(Optional<UUID>.none)
                            ForEach(profiles) { profile in
                                Text(profile.name).tag(Optional(profile.id))
                            }
                        }
                        Button("重置表单") { resetProfile() }.disabled(isCurrentRunning)
                        Button("保存配置") { saveProfile(host) }.disabled(isCurrentRunning || name.isEmpty)
                    }
                    TextField("配置名称", text: $name).disabled(isCurrentRunning)
                    Picker("转发方式", selection: $mode) {
                        ForEach(SSHTunnelMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }.disabled(isCurrentRunning)
                    TextField("回环监听端口", value: $port, format: .number.grouping(.never)).disabled(isCurrentRunning)
                    if mode != .dynamic {
                        TextField("目的地址", text: $destination).disabled(isCurrentRunning)
                        TextField("目的端口", value: $destinationPort, format: .number.grouping(.never)).disabled(isCurrentRunning)
                    }
                    Toggle("连接断开后重试", isOn: $reconnect).disabled(isCurrentRunning)
                    HStack {
                        Button("启动当前转发") {
                            start(id: currentKey, on: host, mode: mode, port: port,
                                  destination: destination, destinationPort: destinationPort,
                                  reconnect: reconnect)
                        }.disabled(isCurrentRunning).buttonStyle(.borderedProminent)
                        Button("停止当前转发") { tasks[currentKey]?.cancel() }.disabled(!isCurrentRunning)
                    }
                    if let currentStatus = statuses[currentKey], !currentStatus.isEmpty {
                        Text(currentStatus).foregroundStyle(.secondary)
                    }
                    if !status.isEmpty { Text(status).foregroundStyle(.secondary) }
                }
            } else {
                ContentUnavailableView("请在侧边栏选择服务器", systemImage: "point.3.connected.trianglepath.dotted")
            }
        }
        .formStyle(.grouped)
        .task(id: host?.id) {
            selectedProfile = nil
            resetProfile()
            status = ""
            await loadProfiles()
        }
        .onChange(of: selectedProfile) { _, selection in
            if let selection, let profile = profiles.first(where: { $0.id == selection }) { apply(profile) }
        }
        .confirmationDialog("删除此隧道配置？", isPresented: Binding(
            get: { deletingProfile != nil }, set: { if !$0 { deletingProfile = nil } }
        ), titleVisibility: .visible, presenting: deletingProfile) { profile in
            Button("确认删除", role: .destructive) {
                deleteProfile(profile.id)
            }
        } message: { profile in
            Text("\(profile.name) (\(summary(for: profile)))")
        }
    }

    private func summary(for profile: SSHTunnelProfile) -> String {
        switch profile.mode {
        case .local:
            return "127.0.0.1:\(profile.listenPort) → \(profile.destination):\(profile.destinationPort)"
        case .remote:
            return "远端 127.0.0.1:\(profile.listenPort) → \(profile.destination):\(profile.destinationPort)"
        case .dynamic:
            return "SOCKS5 127.0.0.1:\(profile.listenPort)"
        }
    }

    private func start(id: UUID, on host: SSHHost, mode: SSHTunnelMode, port: Int,
                       destination: String, destinationPort: Int, reconnect: Bool) {
        guard tasks[id] == nil else { return }
        statuses[id] = "正在建立隧道"
        tasks[id] = Task {
            defer { tasks[id] = nil }
            while !Task.isCancelled {
                do {
                    try await OpenSSHTransport().forward(on: host, mode: mode, port: port,
                        destination: destination, destinationPort: destinationPort) {
                        Task { @MainActor in
                            if tasks[id] != nil { statuses[id] = "隧道已建立（端口 \(port)）" }
                        }
                    }
                    statuses[id] = "隧道已退出"
                } catch is CancellationError {
                    break
                } catch { statuses[id] = error.localizedDescription }
                guard reconnect, !Task.isCancelled else { return }
                statuses[id] = (statuses[id] ?? "") + " 五秒后重试。"
                do { try await Task.sleep(for: .seconds(5)) } catch { break }
            }
            statuses[id] = "隧道已停止"
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

    private func deleteProfile(_ id: UUID) {
        tasks[id]?.cancel()
        Task {
            do {
                try await store.deleteTunnel(id)
                if selectedProfile == id { resetProfile() }
                statuses[id] = nil
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
