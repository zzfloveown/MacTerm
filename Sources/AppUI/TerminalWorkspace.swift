import Domain
import SwiftUI
import TerminalCore

struct TerminalSession: Identifiable {
    var id = UUID()
    var host: SSHHost?
    var executable: String?
    var command: [String] = []
    var title: String?
    var exitStatus: String?
}

enum SplitMode: String, CaseIterable {
    case none = "单窗口", horizontal = "左右分屏", vertical = "上下分屏"
}

struct TerminalWorkspace: View {
    @Binding var sessions: [TerminalSession]
    @Binding var current: UUID?
    @Binding var split: SplitMode
    let fontSize: Double

    var body: some View {
        VStack(spacing: 0) {
            if sessions.isEmpty {
                ContentUnavailableView("打开服务器终端", systemImage: "terminal")
            } else {
                HStack {
                    ScrollView(.horizontal) {
                        HStack {
                            ForEach(sessions) { item in
                                HStack(spacing: 4) {
                                    Button(item.title ?? item.host?.label ?? "终端") { current = item.id }
                                        .fontWeight(current == item.id ? .bold : .regular)
                                        .help(item.exitStatus ?? "SSH 终端")
                                    Button("关闭标签", systemImage: "xmark") { close(item.id) }.labelStyle(.iconOnly)
                                }.buttonStyle(.borderless)
                            }
                        }
                    }
                    Picker("分屏", selection: $split) {
                        ForEach(SplitMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }.labelsHidden().fixedSize()
                    Button("重新连接", systemImage: "arrow.clockwise") {
                        if let index = sessions.firstIndex(where: { $0.id == current }) {
                            sessions[index].id = UUID()
                            sessions[index].exitStatus = nil
                            current = sessions[index].id
                        }
                    }.labelStyle(.iconOnly)
                }.padding(8)
                if let status = sessions.first(where: { $0.id == current })?.exitStatus {
                    Text(status).font(.caption).foregroundStyle(.secondary).padding(4)
                }
                GeometryReader { geometry in
                    let second = split == .none ? nil : sessions.first { $0.id != current }?.id
                    let width = geometry.size.width / ((second != nil && split == .horizontal) ? 2 : 1)
                    let height = geometry.size.height / ((second != nil && split == .vertical) ? 2 : 1)
                    ZStack(alignment: .topLeading) {
                        ForEach(sessions) { item in
                            let visible = item.id == current || item.id == second
                            Group {
                                if let host = item.host,
                                   let terminal = try? SSHTerminal(host: host, fontSize: fontSize, command: item.command,
                                                                  onExit: { onExit(item.id, code: $0) }) {
                                    terminal
                                } else if let executable = item.executable {
                                    SSHTerminal(executable: executable, arguments: item.command, fontSize: fontSize,
                                                onExit: { onExit(item.id, code: $0) })
                                } else { Text("终端配置无效") }
                            }
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
    }

    private func onExit(_ id: UUID, code: Int32?) {
        if let index = sessions.firstIndex(where: { $0.id == id }) {
            sessions[index].exitStatus = code.map { "会话已断开（\($0)）" } ?? "会话已断开"
        }
    }

    private func close(_ id: UUID) {
        sessions.removeAll { $0.id == id }
        if current == id { current = sessions.last?.id }
    }
}
