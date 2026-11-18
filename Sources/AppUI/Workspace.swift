import AppKit
import Domain
import StorageCore
import SwiftUI
import TransferCore

enum Section: String, CaseIterable, Identifiable {
    case dashboard = "工作台", terminal = "SSH 终端", files = "SFTP 文件", hosts = "服务器管理"
    case monitor = "服务器监控", tunnels = "SSH 隧道", docker = "Docker 管理", kubernetes = "Kubernetes 管理"
    case keys = "密钥管理", transfers = "传输任务", alerts = "告警中心", settings = "系统设置"
    var id: Self { self }
    var icon: String {
        switch self {
        case .dashboard: "rectangle.grid.2x2"
        case .terminal: "terminal"
        case .files: "folder"
        case .hosts: "server.rack"
        case .monitor: "waveform.path"
        case .tunnels: "point.3.connected.trianglepath.dotted"
        case .docker: "shippingbox"
        case .kubernetes: "square.stack.3d.up"
        case .keys: "key"
        case .transfers: "arrow.up.arrow.down"
        case .alerts: "bell"
        case .settings: "gear"
        }
    }
}

public struct Workspace: View {
    let store: Store
    let monitors: MonitorRegistry
    @ObservedObject var transfers: TransferQueue
    @State private var hosts: [SSHHost] = []
    @State private var hostID: UUID?
    @State private var section: Section? = .dashboard
    @State private var editing: SSHHost?
    @State private var importing = false
    @State private var failure = ""
    @State private var sessions: [TerminalSession] = []
    @State private var current: UUID?
    @State private var split: SplitMode = .none
    @SceneStorage("recentSSHHosts") private var recentSSHHosts = ""
    @AppStorage("terminalFontSize") private var fontSize = 13.0

    public init(store: Store, transfers: TransferQueue, monitors: MonitorRegistry) {
        self.store = store
        self.transfers = transfers
        self.monitors = monitors
    }

    var host: SSHHost? { hosts.first { $0.id == hostID } }

    private var hostGroups: [String] { Set(hosts.map { $0.group ?? "服务器" }).sorted() }

    public var body: some View {
        NavigationSplitView {
            List(selection: $section) {
                SwiftUI.Section {
                    HStack(spacing: 10) {
                        Image(systemName: "terminal.fill")
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(LinearGradient(colors: [.teal, .blue], startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 34, height: 34)
                            .background(.blue.opacity(0.09), in: RoundedRectangle(cornerRadius: 9))
                        VStack(alignment: .leading, spacing: 1) {
                            Text("MacTerm").font(.headline)
                            Text("SERVER OPERATIONS").font(.system(size: 8, weight: .semibold, design: .rounded))
                                .tracking(0.7).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 5)
                    .accessibilityElement(children: .combine)
                }
                SwiftUI.Section("工作区") {
                    ForEach(Section.allCases) { item in
                        Label(item.rawValue, systemImage: item.icon).tag(item)
                    }
                }
                ForEach(hostGroups, id: \.self) { name in
                    SwiftUI.Section(name) {
                        ForEach(hosts.filter { ($0.group ?? "服务器") == name }) { item in
                            Button {
                                hostID = item.id
                                section = .hosts
                            } label: {
                                Label(item.label, systemImage: item.id == hostID ? "checkmark.circle.fill" : "server.rack")
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button("连接终端") { hostID = item.id; connect(item) }
                                Button("打开 SFTP 文件") { hostID = item.id; section = .files }
                                Button("服务器监控") { hostID = item.id; section = .monitor }
                                Button("Docker 管理") { hostID = item.id; section = .docker }
                                Button("SSH 隧道") { hostID = item.id; section = .tunnels }
                                Button("密钥管理") { hostID = item.id; section = .keys }
                                Divider()
                                Button("复制连接地址") {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString("\(item.user)@\(item.address):\(item.port)", forType: .string)
                                }
                                Button("编辑服务器") { editing = item }
                            }
                        }
                    }
                }
            }.navigationSplitViewColumnWidth(min: 190, ideal: 220)
        } detail: {
            let activeTransfers = transfers.records.filter { ["待传输", "进行中", "已暂停"].contains($0.state) }.count
            VStack(spacing: 0) {
                ZStack {
                    if section != .terminal && section != .tunnels && section != .files { page.padding() }
                    SFTPTabs(selectedHost: host, transfers: transfers).padding()
                        .opacity(section == .files ? 1 : 0)
                        .allowsHitTesting(section == .files)
                        .accessibilityHidden(section != .files)
                    TunnelPage(host: host, store: store)
                        .opacity(section == .tunnels ? 1 : 0)
                        .allowsHitTesting(section == .tunnels)
                        .accessibilityHidden(section != .tunnels)
                    TerminalWorkspace(store: store, selectedHost: host, sessions: $sessions,
                                      current: $current, split: $split, fontSize: fontSize)
                        .opacity(section == .terminal ? 1 : 0)
                        .allowsHitTesting(section == .terminal)
                        .accessibilityHidden(section != .terminal)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
                Divider()
                HStack(spacing: 16) {
                    Label(host.map { "\($0.label) (\($0.user)@\($0.address):\($0.port))" } ?? "未选择服务器",
                          systemImage: "server.rack")
                    Spacer()
                    if activeTransfers > 0 {
                        Button {
                            section = .transfers
                        } label: {
                            Label("\(activeTransfers) 项传输中", systemImage: "arrow.up.arrow.down")
                        }.buttonStyle(.plain)
                    }
                    Button {
                        section = .terminal
                    } label: {
                        Text("\(sessions.count) 个终端标签")
                    }.buttonStyle(.plain)
                }.font(.caption).foregroundStyle(.secondary).padding(8)
            }
            .navigationTitle(section?.rawValue ?? "MacTerm")
            .toolbar {
                Button("添加服务器", systemImage: "plus") { editing = SSHHost(authenticationMethod: .password) }
                    .keyboardShortcut("n", modifiers: .command)
                Button("导入 SSH 配置", systemImage: "square.and.arrow.down") { importing = true }
                    .keyboardShortcut("i", modifiers: [.command, .shift])
                Button("连接", systemImage: "terminal") {
                    if let host { connect(host) }
                }.disabled(host == nil).keyboardShortcut("t", modifiers: .command)
                Button("打开 SFTP", systemImage: "folder") { section = .files }
                    .disabled(host == nil).keyboardShortcut("f", modifiers: [.command, .option])
                Button("打开监控", systemImage: "waveform.path") { section = .monitor }
                    .disabled(host == nil).keyboardShortcut("m", modifiers: [.command, .option])
            }
        }
        .task { await refresh(); await transfers.load() }
        .onChange(of: sessions.map(\.id)) { _, _ in
            let recent = sessions.compactMap { item in item.command.isEmpty ? item.host?.id.uuidString : nil }
            recentSSHHosts = recent.joined(separator: ",")
        }
        .background {
            SSHImportView(presenting: $importing, existing: hosts) { imported in
                try await store.save(imported)
                await refresh()
            }
        }
        .sheet(item: $editing) { item in
            HostEditor(host: item) { updated in
                try await store.save(updated)
                await refresh()
                hostID = updated.id
                section = .hosts
            }
        }
        .alert("操作失败", isPresented: Binding(get: { !failure.isEmpty }, set: { if !$0 { failure = "" } })) {
            Button("好", role: .cancel) {}
        } message: { Text(failure) }
    }

    @ViewBuilder private var page: some View {
        switch section ?? .dashboard {
        case .dashboard:
            DashboardPage(hosts: hosts, terminalCount: sessions.count,
                          transferCount: transfers.records.filter { ["待传输", "进行中", "已暂停"].contains($0.state) }.count,
                          restorable: sessions.isEmpty && !restorableHosts.isEmpty,
                          onConnect: { hostID = $0.id; connect($0) },
                          onOpen: { selected, destination in hostID = selected.id; section = destination },
                          onNavigate: { section = $0 },
                          onEdit: { editing = $0 },
                          onRestore: restoreTerminals,
                          onAdd: { editing = SSHHost(authenticationMethod: .password) })
        case .hosts:
            if let host {
                HostDetailsPage(host: host,
                                onConnect: { connect(host) },
                                onOpen: { section = $0 },
                                onEdit: { editing = host },
                                onDelete: { delete(host) })
            } else { chooseHost }
        case .files: EmptyView()
        case .monitor:
            if let host { MonitorPage(host: host, monitor: monitors.session(for: host)).id(host.id) } else { chooseHost }
        case .docker:
            if let host { ContainerPage(host: host) { command, title in
                open(TerminalSession(host: host, command: command, title: title))
            }.id(host.id) } else { chooseHost }
        case .kubernetes:
            KubernetesPage { executable, args, title in
                open(TerminalSession(executable: executable, command: args, title: title))
            }
        case .transfers: TransferPage(transfers: transfers)
        case .keys: KeyPage(host: host, store: store, updated: { await refresh() }).id(host?.id)
        case .settings:
            SettingsPage(store: store, fontSize: $fontSize, onRestore: { await refresh() })
        case .tunnels: EmptyView()
        case .alerts:
            if let host { AlertPage(host: host, monitor: monitors.session(for: host)).id(host.id) } else { chooseHost }
        case .terminal: EmptyView()
        }
    }

    private var chooseHost: some View {
        ContentUnavailableView("请在侧边栏选择服务器", systemImage: "server.rack")
    }

    private var restorableHosts: [SSHHost] {
        recentSSHHosts.split(separator: ",").compactMap { id in
            hosts.first { $0.id.uuidString == id }
        }
    }

    private func restoreTerminals() {
        let restored = restorableHosts.map { TerminalSession(host: $0) }
        guard !restored.isEmpty else { return }
        sessions = restored
        current = restored.last?.id
        section = .terminal
    }

    private func connect(_ host: SSHHost) {
        open(TerminalSession(host: host))
    }

    private func open(_ tab: TerminalSession) {
        sessions.append(tab)
        current = tab.id
        section = .terminal
    }

    private func refresh() async {
        do { hosts = try await store.hosts() }
        catch { failure = error.localizedDescription }
    }

    private func delete(_ host: SSHHost) {
        Task {
            do {
                try CredentialVault.delete(host.id)
                try await store.delete(host.id)
                monitors.remove(host.id)
                hostID = nil
                await refresh()
            } catch { failure = error.localizedDescription }
        }
    }
}

private struct HostDetailsPage: View {
    let host: SSHHost
    let onConnect: () -> Void
    let onOpen: (Section) -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    @State private var copied = false
    @State private var confirmingDelete = false

    var body: some View {
        Form {
            SwiftUI.Section {
                HStack(spacing: 14) {
                    Image(systemName: "server.rack.fill")
                        .font(.system(size: 28)).foregroundStyle(.blue)
                        .frame(width: 62, height: 62)
                        .background(.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 15))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(host.label).font(.title2.bold())
                        Text("\(host.user)@\(host.address):\(host.port)").font(.callout.monospaced())
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let group = host.group, !group.isEmpty {
                        Text(group).font(.caption).padding(.horizontal, 10).padding(.vertical, 5)
                            .background(.quaternary, in: Capsule())
                    }
                }
                HostActionLayout {
                    Button("连接终端", systemImage: "terminal", action: onConnect).buttonStyle(.borderedProminent)
                    Button("SFTP 文件", systemImage: "folder") { onOpen(.files) }
                    Button("服务器监控", systemImage: "waveform.path") { onOpen(.monitor) }
                    Button("Docker", systemImage: "shippingbox") { onOpen(.docker) }
                    Button("SSH 隧道", systemImage: "point.3.connected.trianglepath.dotted") { onOpen(.tunnels) }
                    Button("密钥管理", systemImage: "key") { onOpen(.keys) }
                    Button("告警中心", systemImage: "bell") { onOpen(.alerts) }
                }
                .controlSize(.regular)
            }
            SwiftUI.Section("连接配置") {
                LabeledContent("主机", value: host.address)
                LabeledContent("SSH 用户", value: host.user)
                LabeledContent("端口", value: String(host.port))
                LabeledContent("跳板机", value: host.jump.isEmpty ? "无" : host.jump)
                LabeledContent("认证方式", value: host.authenticationMethod?.label ?? "自动（旧配置）")
                if host.authenticationMethod != .password {
                    LabeledContent("私钥", value: host.identity.isEmpty ? "SSH Agent 或默认密钥" : host.identity)
                }
                if host.authenticationMethod != .privateKey {
                    LabeledContent("密码认证", value: host.keychainAuthenticationEnabled ? "允许从 Keychain 提交" : "交互输入")
                }
                HStack {
                    Button("复制连接地址", systemImage: "doc.on.doc") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString("\(host.user)@\(host.address):\(host.port)", forType: .string)
                        copied = true
                    }
                    if copied { Text("已复制").font(.caption).foregroundStyle(.secondary) }
                    Spacer()
                    Button("编辑服务器", systemImage: "pencil", action: onEdit)
                }
            }
            SwiftUI.Section {
                Button("移除本地配置", systemImage: "trash", role: .destructive) { confirmingDelete = true }
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: 760)
        .confirmationDialog("移除此服务器配置？", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("确认移除", role: .destructive, action: onDelete)
        } message: {
            Text("将一并删除该服务器的 Keychain 凭据、命令历史、监控历史、告警规则和 SSH 隧道配置。")
        }
    }
}

/// 按按钮的完整文字宽度排布，空间不足时换行，不压缩标签。
private struct HostActionLayout: Layout {
    private let horizontalSpacing: CGFloat = 8
    private let verticalSpacing: CGFloat = 10

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrangement(subviews, width: proposal.width ?? .infinity).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let layout = arrangement(subviews, width: bounds.width)
        for (index, subview) in subviews.enumerated() {
            let origin = layout.origins[index]
            subview.place(at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y),
                          anchor: .topLeading, proposal: .unspecified)
        }
    }

    private func arrangement(_ subviews: Subviews, width: CGFloat) -> (size: CGSize, origins: [CGPoint]) {
        var origins: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var usedWidth: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + verticalSpacing
                rowHeight = 0
            }
            origins.append(CGPoint(x: x, y: y))
            usedWidth = max(usedWidth, x + size.width)
            rowHeight = max(rowHeight, size.height)
            x += size.width + horizontalSpacing
        }
        return (CGSize(width: usedWidth, height: y + rowHeight), origins)
    }
}
