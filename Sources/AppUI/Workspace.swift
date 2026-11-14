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
    @AppStorage("terminalFontSize") private var fontSize = 13.0

    public init(store: Store, transfers: TransferQueue, monitors: MonitorRegistry) {
        self.store = store
        self.transfers = transfers
        self.monitors = monitors
    }

    var host: SSHHost? { hosts.first { $0.id == hostID } }

    public var body: some View {
        NavigationSplitView {
            List(selection: $section) {
                SwiftUI.Section("工作区") {
                    ForEach(Section.allCases) { item in
                        Label(item.rawValue, systemImage: item.icon).tag(item)
                    }
                }
                SwiftUI.Section("服务器") {
                    ForEach(hosts) { item in
                        Button {
                            hostID = item.id
                            section = .hosts
                        } label: {
                            Label(item.label, systemImage: item.id == hostID ? "checkmark.circle.fill" : "server.rack")
                        }.buttonStyle(.plain)
                    }
                }
            }.navigationSplitViewColumnWidth(min: 190, ideal: 220)
        } detail: {
            VStack(spacing: 0) {
                ZStack {
                    if section != .terminal { page.padding() }
                    TerminalWorkspace(sessions: $sessions, current: $current, split: $split, fontSize: fontSize)
                        .opacity(section == .terminal ? 1 : 0)
                        .allowsHitTesting(section == .terminal)
                        .accessibilityHidden(section != .terminal)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
                Divider()
                HStack {
                    Label(host?.label ?? "未选择服务器", systemImage: "server.rack")
                    Spacer()
                    Text("\(sessions.count) 个终端标签")
                }.font(.caption).foregroundStyle(.secondary).padding(8)
            }
            .navigationTitle(section?.rawValue ?? "MacTerm")
            .toolbar {
                Button("添加服务器", systemImage: "plus") { editing = SSHHost() }
                Button("导入 SSH 配置", systemImage: "square.and.arrow.down") { importing = true }
                Button("连接", systemImage: "terminal") {
                    if let host { connect(host) }
                }.disabled(host == nil).keyboardShortcut("t", modifiers: .command)
            }
        }
        .task { await refresh(); await transfers.load() }
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
            List {
                ForEach(hosts) { item in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(item.label).font(.headline)
                            Text("\(item.user)@\(item.address):\(item.port)").foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("打开终端") { hostID = item.id; connect(item) }
                    }
                }
            }.overlay { if hosts.isEmpty { ContentUnavailableView("添加服务器以开始连接", systemImage: "server.rack") } }
        case .hosts:
            if let host {
                Form {
                    LabeledContent("名称", value: host.label)
                    LabeledContent("地址", value: host.address)
                    LabeledContent("用户", value: host.user)
                    LabeledContent("端口", value: String(host.port))
                    Button("编辑服务器") { editing = host }
                    Button("移除本地配置", role: .destructive) {
                        Task {
                            do { try await store.delete(host.id); monitors.remove(host.id); hostID = nil; await refresh() }
                            catch { failure = error.localizedDescription }
                        }
                    }
                }.formStyle(.grouped)
            } else { chooseHost }
        case .files:
            if let host { FileWorkspace(host: host, transfers: transfers).id(host.id) } else { chooseHost }
        case .monitor:
            if let host { MonitorPage(host: host, monitor: monitors.session(for: host)).id(host.id) } else { chooseHost }
        case .docker:
            if let host { ContainerPage(host: host).id(host.id) } else { chooseHost }
        case .kubernetes: KubernetesPage()
        case .transfers: TransferPage(transfers: transfers)
        case .keys: KeyPage(host: host, store: store, updated: { await refresh() }).id(host?.id)
        case .settings:
            Form { Slider(value: $fontSize, in: 9...26, step: 1) { Text("字体大小 \(Int(fontSize))") } }
                .formStyle(.grouped)
        case .tunnels: TunnelPage(host: host).id(host?.id)
        case .alerts:
            if let host { AlertPage(host: host, monitor: monitors.session(for: host)).id(host.id) } else { chooseHost }
        case .terminal: EmptyView()
        }
    }

    private var chooseHost: some View {
        ContentUnavailableView("请在侧边栏选择服务器", systemImage: "server.rack")
    }

    private func connect(_ host: SSHHost) {
        let tab = TerminalSession(host: host)
        sessions.append(tab)
        current = tab.id
        section = .terminal
    }

    private func refresh() async {
        do { hosts = try await store.hosts() }
        catch { failure = error.localizedDescription }
    }
}
