import Domain
import MonitorCore
import SwiftUI

struct LinuxProcessList: View {
    let host: SSHHost
    let engine: MonitorEngine
    @State private var items: [LinuxProcess] = []
    @State private var selection: Int?
    @State private var sorting: [KeyPathComparator<LinuxProcess>] = [.init(\.cpu, order: .reverse)]
    @State private var filter = ""
    @State private var confirming: LinuxProcess?
    @State private var failure = ""

    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Text("进程").font(.headline)
                TextField("搜索 PID、用户或命令", text: $filter)
                Button("刷新") { Task { await refresh() } }
                Button("结束进程", role: .destructive) {
                    confirming = items.first { $0.pid == selection && $0.pid > 1 }
                }.disabled(selection == nil || selection == 1)
            }
            Table(visible, selection: $selection, sortOrder: $sorting) {
                TableColumn("PID", value: \.pid) { Text(String($0.pid)) }.width(65)
                TableColumn("用户", value: \.user).width(80)
                TableColumn("CPU %", value: \.cpu) { Text($0.cpu.formatted()) }.width(65)
                TableColumn("内存 %", value: \.memory) { Text($0.memory.formatted()) }.width(65)
                TableColumn("秒", value: \.elapsed) { Text(String($0.elapsed)) }.width(70)
                TableColumn("启动命令", value: \.command)
            }.frame(minHeight: 240)
            if let row = items.first(where: { $0.pid == selection }) {
                Text(row.command).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
            }
            if !failure.isEmpty { Text(failure).foregroundStyle(.red) }
        }
        .confirmationDialog("向该进程发送 SIGTERM？", isPresented: Binding(
            get: { confirming != nil }, set: { if !$0 { confirming = nil } }
        ), titleVisibility: .visible, presenting: confirming) { process in
            Button("确认结束 PID \(process.pid)", role: .destructive) {
                Task {
                    do { try await engine.terminate(process, on: host); await refresh() }
                    catch { failure = error.localizedDescription }
                }
            }
        } message: { process in Text(process.command) }
    }

    private var visible: [LinuxProcess] {
        items.filter { filter.isEmpty || String($0.pid).contains(filter) || $0.user.localizedCaseInsensitiveContains(filter)
            || $0.command.localizedCaseInsensitiveContains(filter) }.sorted(using: sorting)
    }

    private func refresh() async {
        do {
            items = try await engine.processList(host)
            if !items.contains(where: { $0.pid == selection }) { selection = nil }
            failure = ""
        } catch { failure = error.localizedDescription }
    }
}
