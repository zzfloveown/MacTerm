import Domain
import SSHCore
import SwiftUI

struct TunnelPage: View {
    let host: SSHHost?
    @State private var mode: ForwardMode = .local
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
                Picker("转发方式", selection: $mode) {
                    ForEach(ForwardMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
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
        }.formStyle(.grouped).onDisappear { task?.cancel() }
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
}
