import CoreTransferable
import Domain
import StorageCore
import SwiftUI
import TerminalCore
import UniformTypeIdentifiers

struct TerminalSession: Identifiable {
    var id = UUID()
    var host: SSHHost?
    var executable: String?
    var command: [String] = []
    var title: String?
    var dynamicTitle: String?
    var exitStatus: String?
    var pendingInput: (id: UUID, text: String)?
    var attempt = UUID()

    var displayTitle: String { title ?? host?.label ?? dynamicTitle ?? "终端" }
}

enum SplitMode: String, CaseIterable {
    case none = "单窗口", horizontal = "左右分屏", vertical = "上下分屏"
}

struct TerminalWorkspace: View {
    let store: Store
    let selectedHost: SSHHost?
    @Binding var sessions: [TerminalSession]
    @Binding var current: UUID?
    @Binding var split: SplitMode
    let fontSize: Double
    @State private var secondaryID: UUID?
    @State private var showingCommands = false
    @State private var commandText = ""
    @State private var broadcastSplit = false
    @State private var commandHistory: [TerminalCommandEntry] = []
    @State private var commandError = ""
    @AppStorage("terminalCursor") private var cursor = TerminalCursor.block
    @AppStorage("terminalScrollback") private var scrollback = 5000
    @AppStorage("terminalAutoReconnect") private var automaticReconnect = false

    private var activeSession: TerminalSession? { sessions.first { $0.id == current } }
    private var activeHost: SSHHost? { activeSession?.host ?? selectedHost }
    private var resolvedSecondaryID: UUID? {
        guard split != .none else { return nil }
        if let secondaryID, secondaryID != current, sessions.contains(where: { $0.id == secondaryID }) {
            return secondaryID
        }
        return sessions.first { $0.id != current }?.id
    }

    var body: some View {
        VStack(spacing: 0) {
            if sessions.isEmpty {
                ContentUnavailableView {
                    Label("打开服务器终端", systemImage: "terminal")
                } description: {
                    Text(selectedHost.map { "可立即连接 \($0.label)（\($0.user)@\($0.address):\($0.port)）。" } ?? "在侧边栏或工作台选择服务器以打开 SSH 终端。")
                } actions: {
                    if let selectedHost {
                        Button("连接 \(selectedHost.label)", systemImage: "terminal") {
                            let tab = TerminalSession(host: selectedHost)
                            sessions.append(tab)
                            current = tab.id
                        }.buttonStyle(.borderedProminent)
                    }
                }
            } else {
                HStack(spacing: 8) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(sessions) { item in
                                HStack(spacing: 5) {
                                    Circle()
                                        .fill(item.exitStatus == nil ? Color.green : Color.orange)
                                        .frame(width: 7, height: 7)
                                    Button(item.displayTitle) { current = item.id }
                                        .fontWeight(current == item.id ? .bold : .regular)
                                        .help(item.dynamicTitle ?? item.exitStatus ?? "SSH 终端")
                                    Button("关闭标签", systemImage: "xmark") { close(item.id) }
                                        .labelStyle(.iconOnly)
                                        .font(.caption2)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(current == item.id ? Color.blue.opacity(0.12) : Color.secondary.opacity(0.08),
                                            in: RoundedRectangle(cornerRadius: 6))
                                .buttonStyle(.borderless)
                                .draggable(TerminalTabDrag(id: item.id))
                                .dropDestination(for: TerminalTabDrag.self) { values, _ in
                                    guard let source = values.first?.id,
                                          let from = sessions.firstIndex(where: { $0.id == source }),
                                          let to = sessions.firstIndex(where: { $0.id == item.id }),
                                          from != to else { return false }
                                    let tab = sessions.remove(at: from)
                                    sessions.insert(tab, at: to)
                                    return true
                                }
                            }
                        }
                    }
                    if let host = activeHost {
                        Button("新建终端", systemImage: "plus") {
                            let tab = TerminalSession(host: host)
                            sessions.append(tab)
                            current = tab.id
                        }.labelStyle(.iconOnly).help("为 \(host.label) 新建终端标签")
                    }
                    Picker("分屏", selection: $split) {
                        ForEach(SplitMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }.labelsHidden().fixedSize()
                    if split != .none, sessions.count > 1 {
                        Picker("副分屏", selection: Binding(
                            get: { resolvedSecondaryID ?? sessions[0].id },
                            set: { secondaryID = $0 }
                        )) {
                            ForEach(sessions.filter { $0.id != current }) { item in
                                Text(item.displayTitle).tag(item.id)
                            }
                        }.labelsHidden().frame(maxWidth: 140)
                    }
                    Button("命令历史", systemImage: "clock.arrow.circlepath") {
                        showingCommands.toggle()
                    }.help("打开快捷命令与历史记录")
                    Button("重新连接", systemImage: "arrow.clockwise") {
                        if let index = sessions.firstIndex(where: { $0.id == current }) {
                            sessions[index].attempt = UUID()
                            sessions[index].exitStatus = nil
                        }
                    }.labelStyle(.iconOnly).help("重新建立当前终端会话")
                }.padding(8)

                if showingCommands {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            TextField("输入单行命令发送到终端（不记录凭据与输出）", text: $commandText)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(.callout, design: .monospaced))
                                .onSubmit { sendQuickCommand(commandText) }
                            if split != .none, resolvedSecondaryID != nil {
                                Toggle("同步发往副分屏", isOn: $broadcastSplit).toggleStyle(.checkbox)
                            }
                            Button("发送") { sendQuickCommand(commandText) }
                                .disabled(commandText.trimmingCharacters(in: .whitespaces).isEmpty)
                            if !commandHistory.isEmpty, let hostID = activeHost?.id {
                                Button("清空历史", role: .destructive) {
                                    Task {
                                        try? await store.clearCommandHistory(for: hostID)
                                        await loadCommandHistory()
                                    }
                                }
                            }
                        }
                        if !commandError.isEmpty {
                            Text(commandError).font(.caption).foregroundStyle(.red)
                        }
                        if !commandHistory.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 6) {
                                    ForEach(commandHistory) { entry in
                                        HStack(spacing: 4) {
                                            Button(entry.command) { sendQuickCommand(entry.command) }
                                                .font(.system(.caption, design: .monospaced))
                                            Button("移除", systemImage: "xmark") {
                                                Task {
                                                    try? await store.deleteCommand(entry.id)
                                                    await loadCommandHistory()
                                                }
                                            }.labelStyle(.iconOnly).font(.caption2)
                                        }
                                        .padding(.horizontal, 8).padding(.vertical, 3)
                                        .background(.quaternary.opacity(0.6), in: Capsule())
                                        .buttonStyle(.borderless)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 6)
                    Divider()
                }

                if let status = activeSession?.exitStatus {
                    HStack {
                        Text(status).font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button("立即重连") {
                            if let index = sessions.firstIndex(where: { $0.id == current }) {
                                sessions[index].attempt = UUID()
                                sessions[index].exitStatus = nil
                            }
                        }.controlSize(.mini)
                    }.padding(.horizontal, 8).padding(.vertical, 4)
                }
                GeometryReader { geometry in
                    let second = resolvedSecondaryID
                    let width = geometry.size.width / ((second != nil && split == .horizontal) ? 2 : 1)
                    let height = geometry.size.height / ((second != nil && split == .vertical) ? 2 : 1)
                    ZStack(alignment: .topLeading) {
                        ForEach(sessions) { item in
                            let visible = item.id == current || item.id == second
                            Group {
                                if let host = item.host,
                                   let terminal = try? SSHTerminal(host: host, fontSize: fontSize, command: item.command,
                                                                   cursor: cursor, scrollback: scrollback,
                                                                   pendingInput: item.pendingInput,
                                                                   onTitle: { updateTitle(item.id, title: $0) },
                                                                   onExit: { onExit(item.id, attempt: item.attempt, code: $0) }) {
                                    terminal
                                } else if let executable = item.executable {
                                    SSHTerminal(executable: executable, arguments: item.command, fontSize: fontSize,
                                                cursor: cursor, scrollback: scrollback,
                                                pendingInput: item.pendingInput,
                                                onTitle: { updateTitle(item.id, title: $0) },
                                                onExit: { onExit(item.id, attempt: item.attempt, code: $0) })
                                } else { Text("终端配置无效") }
                            }
                            .id(item.attempt)
                            .frame(width: width, height: height)
                            .offset(x: item.id == second && split == .horizontal ? width : 0,
                                    y: item.id == second && split == .vertical ? height : 0)
                            .opacity(visible ? 1 : 0)
                            .allowsHitTesting(visible)
                            .accessibilityHidden(!visible)
                        }
                    }
                }
            }
        }
        .task(id: activeHost?.id) { await loadCommandHistory() }
    }

    private func sendQuickCommand(_ raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty,
              !trimmed.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
            commandError = "快捷命令不能包含换行或控制字符。"
            return
        }
        commandError = ""
        let payload = (id: UUID(), text: trimmed + "\n")
        if let index = sessions.firstIndex(where: { $0.id == current }) {
            sessions[index].pendingInput = payload
        }
        if broadcastSplit, let second = resolvedSecondaryID,
           let secondIndex = sessions.firstIndex(where: { $0.id == second }) {
            sessions[secondIndex].pendingInput = (id: UUID(), text: trimmed + "\n")
        }
        commandText = ""
        if let hostID = activeHost?.id {
            Task {
                do {
                    try await store.recordCommand(trimmed, for: hostID)
                    await loadCommandHistory()
                } catch { commandError = error.localizedDescription }
            }
        }
    }

    private func loadCommandHistory() async {
        guard let hostID = activeHost?.id else { commandHistory = []; return }
        commandHistory = (try? await store.commandHistory(for: hostID)) ?? []
    }

    private func updateTitle(_ id: UUID, title: String) {
        guard let index = sessions.firstIndex(where: { $0.id == id }) else { return }
        sessions[index].dynamicTitle = title
    }

    private func onExit(_ id: UUID, attempt: UUID, code: Int32?) {
        guard let index = sessions.firstIndex(where: { $0.id == id && $0.attempt == attempt }) else { return }
        sessions[index].exitStatus = code.map { "会话已断开（\($0)）" } ?? "会话已断开"
        guard automaticReconnect, code == 255, sessions[index].host != nil, sessions[index].command.isEmpty else { return }
        Task {
            try? await Task.sleep(for: .seconds(5))
            guard automaticReconnect,
                  let index = sessions.firstIndex(where: { $0.id == id && $0.attempt == attempt }) else { return }
            sessions[index].attempt = UUID()
            sessions[index].exitStatus = nil
        }
    }

    private func close(_ id: UUID) {
        sessions.removeAll { $0.id == id }
        if current == id { current = sessions.last?.id }
        if secondaryID == id { secondaryID = nil }
    }
}

private struct TerminalTabDrag: Codable, Transferable {
    let id: UUID

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .init(exportedAs: "com.macterm.app.terminal-tab"))
    }
}
