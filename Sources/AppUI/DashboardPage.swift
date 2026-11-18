import AppKit
import Domain
import SwiftUI

/// 工作台提供真实主机清单、传输状态和常用操作入口。
struct DashboardPage: View {
    let hosts: [SSHHost]
    let terminalCount: Int
    let transferCount: Int
    let restorable: Bool
    let onConnect: (SSHHost) -> Void
    let onOpen: (SSHHost, Section) -> Void
    let onNavigate: (Section) -> Void
    let onEdit: (SSHHost) -> Void
    let onRestore: () -> Void
    let onAdd: () -> Void
    @State private var query = ""
    @State private var selectedGroup = "全部"

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 12)]

    private var groups: [String] {
        ["全部"] + Set(hosts.map { $0.group ?? "服务器" }).sorted()
    }

    private var filteredHosts: [SSHHost] {
        hosts.filter { host in
            let matchesGroup = selectedGroup == "全部" || (host.group ?? "服务器") == selectedGroup
            let matchesQuery = query.isEmpty
                || host.label.localizedCaseInsensitiveContains(query)
                || host.address.localizedCaseInsensitiveContains(query)
                || host.user.localizedCaseInsensitiveContains(query)
                || (host.group ?? "").localizedCaseInsensitiveContains(query)
            return matchesGroup && matchesQuery
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("服务器工作台").font(.largeTitle.bold())
                        Text("连接、文件、监控和容器运维入口").foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("添加服务器", systemImage: "plus", action: onAdd)
                        .buttonStyle(.borderedProminent)
                    if restorable {
                        Button("恢复终端标签", systemImage: "arrow.uturn.backward", action: onRestore)
                    }
                }
                LazyVGrid(columns: columns, spacing: 12) {
                    summary("已保存服务器", value: hosts.count, icon: "server.rack", tint: .blue) {
                        onNavigate(.hosts)
                    }
                    summary("终端标签", value: terminalCount, icon: "terminal", tint: .teal) {
                        onNavigate(.terminal)
                    }
                    summary("传输任务", value: transferCount, icon: "arrow.up.arrow.down", tint: .orange) {
                        onNavigate(.transfers)
                    }
                }
                HStack(spacing: 12) {
                    Text("服务器").font(.title2.weight(.semibold))
                    if !hosts.isEmpty {
                        TextField("搜索名称、地址、用户或分组", text: $query)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 260)
                        if groups.count > 2 {
                            Picker("分组", selection: $selectedGroup) {
                                ForEach(groups, id: \.self) { Text($0).tag($0) }
                            }.fixedSize()
                        }
                    }
                    Spacer()
                    Text("\(filteredHosts.count) / \(hosts.count) 台").foregroundStyle(.secondary)
                }
                if hosts.isEmpty {
                    ContentUnavailableView {
                        Label("添加第一台服务器", systemImage: "server.rack")
                    } description: {
                        Text("保存连接信息后，即可打开 SSH 终端、SFTP、监控和容器管理。")
                    } actions: {
                        Button("添加服务器", systemImage: "plus", action: onAdd)
                            .buttonStyle(.borderedProminent)
                    }
                    .frame(minHeight: 260)
                } else if filteredHosts.isEmpty {
                    ContentUnavailableView("无匹配服务器", systemImage: "magnifyingglass",
                                           description: Text("请调整搜索关键词或分组筛选条件。"))
                        .frame(minHeight: 180)
                } else {
                    LazyVStack(spacing: 10) {
                        ForEach(filteredHosts) { host in serverCard(host) }
                    }
                }
            }
            .padding(24)
        }
    }

    private func summary(_ title: String, value: Int, icon: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon).font(.title2).foregroundStyle(tint)
                    .frame(width: 42, height: 42).background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 11))
                VStack(alignment: .leading, spacing: 3) {
                    Text(value.formatted()).font(.title2.bold().monospacedDigit())
                    Text(title).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .background(.background, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(.quaternary, lineWidth: 1))
        }.buttonStyle(.plain)
    }

    private func serverCard(_ host: SSHHost) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: "server.rack").font(.title2).foregroundStyle(.blue)
                    .frame(width: 42, height: 42).background(.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 11))
                VStack(alignment: .leading, spacing: 3) {
                    Text(host.label).font(.headline)
                    Text("\(host.user)@\(host.address):\(host.port)").font(.caption.monospaced()).foregroundStyle(.secondary)
                }
                Spacer()
                if !host.jump.isEmpty {
                    Label("跳板", systemImage: "arrow.triangle.branch")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                if let group = host.group, !group.isEmpty {
                    Text(group).font(.caption).padding(.horizontal, 8).padding(.vertical, 4)
                        .background(.quaternary, in: Capsule())
                }
            }
            Divider()
            HStack(spacing: 8) {
                Button("连接", systemImage: "terminal") { onConnect(host) }.buttonStyle(.borderedProminent)
                Button("文件", systemImage: "folder") { onOpen(host, .files) }
                Button("监控", systemImage: "waveform.path") { onOpen(host, .monitor) }
                Button("Docker", systemImage: "shippingbox") { onOpen(host, .docker) }
                Button("隧道", systemImage: "point.3.connected.trianglepath.dotted") { onOpen(host, .tunnels) }
                Button("密钥", systemImage: "key") { onOpen(host, .keys) }
                Spacer()
                Button("详情", systemImage: "info.circle") { onOpen(host, .hosts) }
                Button("编辑", systemImage: "pencil") { onEdit(host) }
            }
            .controlSize(.small)
        }
        .padding(14)
        .background(.background, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(.quaternary, lineWidth: 1))
        .contextMenu {
            Button("连接终端") { onConnect(host) }
            Button("打开 SFTP 文件") { onOpen(host, .files) }
            Button("打开服务器监控") { onOpen(host, .monitor) }
            Button("Docker 管理") { onOpen(host, .docker) }
            Button("SSH 隧道") { onOpen(host, .tunnels) }
            Button("密钥管理") { onOpen(host, .keys) }
            Divider()
            Button("复制连接地址") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString("\(host.user)@\(host.address):\(host.port)", forType: .string)
            }
            Button("编辑服务器") { onEdit(host) }
        }
    }
}
