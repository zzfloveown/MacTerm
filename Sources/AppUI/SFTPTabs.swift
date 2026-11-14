import Domain
import SwiftUI
import TransferCore

/// 切换文件标签时保留各连接的目录和选中项。
struct SFTPTabs: View {
    let selectedHost: SSHHost?
    @ObservedObject var transfers: TransferQueue
    @State private var tabs: [Tab] = []
    @State private var current: UUID?

    private struct Tab: Identifiable {
        let id = UUID()
        let host: SSHHost
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                ScrollView(.horizontal) {
                    HStack {
                        ForEach(tabs) { tab in
                            HStack(spacing: 4) {
                                Button(tab.host.label) { current = tab.id }.fontWeight(current == tab.id ? .bold : .regular)
                                Button("关闭文件标签", systemImage: "xmark") { close(tab.id) }.labelStyle(.iconOnly)
                            }.buttonStyle(.borderless)
                        }
                    }
                }
                Button("新建文件标签", systemImage: "plus") {
                    if let selectedHost { open(selectedHost) }
                }.disabled(selectedHost == nil)
            }
            if tabs.isEmpty {
                ContentUnavailableView("打开 SFTP 连接", systemImage: "folder",
                                       description: Text("在侧边栏选择服务器，然后新建文件标签。"))
            } else {
                ZStack {
                    ForEach(tabs) { tab in
                        FileWorkspace(host: tab.host, transfers: transfers)
                            .opacity(tab.id == current ? 1 : 0)
                            .allowsHitTesting(tab.id == current)
                            .accessibilityHidden(tab.id != current)
                    }
                }
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func open(_ host: SSHHost) {
        let tab = Tab(host: host)
        tabs.append(tab)
        current = tab.id
    }

    private func close(_ id: UUID) {
        tabs.removeAll { $0.id == id }
        if current == id { current = tabs.last?.id }
    }
}
