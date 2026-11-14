import Domain
import Foundation
import SFTPCore
import StorageCore
import SwiftUI
import TransferCore

struct FileWorkspace: View {
    let host: SSHHost
    let store: Store
    @State private var local = FileManager.default.homeDirectoryForCurrentUser.path
    @State private var remote = "/"
    @State private var localFiles: [String] = []
    @State private var remoteFiles: [String] = []
    @State private var localSelected: String?
    @State private var remoteSelected: String?
    @State private var message = ""
    @State private var confirming = false
    @State private var folder = ""
    @State private var active = false
    let client = SFTPClient()

    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Button("刷新") { Task { await refreshLocal(); await refreshRemote() } }
                Button("上传 →") { copy(upload: true) }.disabled(localSelected == nil || active)
                Button("← 下载") { copy(upload: false) }.disabled(remoteSelected == nil || active)
                Button("删除远程文件", role: .destructive) { confirming = true }
                    .disabled(remoteSelected == nil || active)
                Spacer()
                if active { ProgressView().controlSize(.small) }
            }
            HSplitView {
                pane("本地", path: $local, selection: $localSelected, items: localFiles) {
                    Task { await refreshLocal() }
                }
                pane("远程 SFTP", path: $remote, selection: $remoteSelected, items: remoteFiles) {
                    Task { await refreshRemote() }
                }
            }
            HStack {
                TextField("新远程目录名称", text: $folder)
                Button("创建目录") {
                    let path = join(remote, folder)
                    Task {
                        do { try await client.createDirectory(path, on: host); folder = ""; await refreshRemote() }
                        catch { message = error.localizedDescription }
                    }
                }.disabled(folder.isEmpty || folder.contains("/") || [".", ".."].contains(folder) || active)
            }
            if !message.isEmpty { Text(message).foregroundStyle(.secondary).textSelection(.enabled) }
        }.task { await refreshLocal() }
            .confirmationDialog("删除选中的远端文件？", isPresented: $confirming, titleVisibility: .visible) {
                Button("确认删除", role: .destructive) {
                    guard let remoteSelected else { return }
                    let path = join(remote, remoteSelected)
                    Task {
                        do { try await client.deleteFile(path, on: host); await refreshRemote() }
                        catch { message = error.localizedDescription }
                    }
                }
            }
    }

    private func pane(_ title: String, path: Binding<String>, selection: Binding<String?>,
                      items: [String], load: @escaping () -> Void) -> some View {
        VStack(alignment: .leading) {
            Text(title).font(.headline)
            HStack {
                Button("上级", systemImage: "arrow.up") {
                    path.wrappedValue = URL(fileURLWithPath: path.wrappedValue).deletingLastPathComponent().path
                    load()
                }.labelStyle(.iconOnly)
                TextField("绝对路径", text: path).onSubmit(load)
                Button("打开") { load() }
            }
            List(selection: selection) {
                ForEach(items, id: \.self) { name in
                    Text(name).tag(name).onTapGesture(count: 2) {
                        path.wrappedValue = join(path.wrappedValue, name)
                        load()
                    }
                }
            }
        }.padding(8).frame(minWidth: 280)
    }

    private func join(_ folder: String, _ name: String) -> String {
        folder == "/" ? "/" + name : folder + "/" + name
    }

    private func refreshLocal() async {
        localSelected = nil
        let path = local
        do {
            let files = try await Task.detached {
                try FileManager.default.contentsOfDirectory(atPath: path).sorted()
            }.value
            if path == local { localFiles = files }
        } catch { localFiles = []; message = error.localizedDescription }
    }

    private func refreshRemote() async {
        remoteSelected = nil
        let path = remote
        do {
            let files = try await client.list(path, on: host)
            if remote == path { remoteFiles = files; message = "" }
        } catch { remoteFiles = []; message = error.localizedDescription }
    }

    private func copy(upload: Bool) {
        guard let name = upload ? localSelected : remoteSelected else { return }
        let localPath = URL(fileURLWithPath: join(local, name))
        let remotePath = join(remote, name)
        active = true
        Task {
            defer { active = false }
            do {
                try await TransferService(store: store).copy(local: localPath, remote: remotePath, upload: upload, host: host)
                if upload { await refreshRemote() } else { await refreshLocal() }
                message = "传输已完成"
            } catch { message = error.localizedDescription }
        }
    }
}

struct TransferPage: View {
    let store: Store
    @State private var items: [TransferRecord] = []
    @State private var failure = ""

    var body: some View {
        VStack {
            HStack {
                Text("传输记录").font(.title2)
                Spacer()
                Button("刷新") { Task { await refresh() } }
            }
            if !failure.isEmpty { Text(failure).foregroundStyle(.red) }
            List(items) { item in
                HStack { Text(item.name); Spacer(); Text(item.state); Text(item.createdAt.formatted()) }
            }
        }.task { await refresh() }
    }

    private func refresh() async {
        do { items = try await store.transfers() }
        catch { failure = error.localizedDescription }
    }
}
