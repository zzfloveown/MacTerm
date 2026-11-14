import Domain
import Foundation
import SFTPCore
import SwiftUI
import TransferCore

struct FileWorkspace: View {
    let host: SSHHost
    @ObservedObject var transfers: TransferQueue
    @State private var local = FileManager.default.homeDirectoryForCurrentUser.path
    @State private var remote = "/"
    @State private var localFiles: [String] = []
    @State private var remoteFiles: [SFTPEntry] = []
    @State private var loadedRemote: String?
    @State private var loadedLocal: String?
    @State private var rename = ""
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
                Button("上传 →") { copy(upload: true) }.disabled(localSelected == nil || loadedLocal != local || loadedRemote != remote || active)
                Button("← 下载") { copy(upload: false) }.disabled(remoteSelected == nil || loadedLocal != local || loadedRemote != remote || active)
                Button("删除远程文件", role: .destructive) { confirming = true }
                    .disabled(remoteSelected == nil || loadedLocal != local || loadedRemote != remote || active)
                Spacer()
                if active { ProgressView().controlSize(.small) }
            }
            HSplitView {
                pane("本地", path: $local, selection: $localSelected, items: localFiles) {
                    Task { await refreshLocal() }
                }
                pane("远程 SFTP", path: $remote, selection: $remoteSelected, items: remoteFiles.map(\.name), metadata: remoteFiles) {
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
            if let entry = remoteFiles.first(where: { $0.name == remoteSelected }), loadedRemote == remote {
                HStack {
                    TextField("新名称", text: $rename)
                    Button("重命名") {
                        let from = join(remote, entry.name), to = join(remote, rename)
                        Task {
                            do { try await client.rename(from, to: to, on: host); rename = ""; await refreshRemote() }
                            catch { message = error.localizedDescription }
                        }
                    }.disabled(rename.isEmpty || rename.contains("/") || [".", ".."].contains(rename))
                    if let permissions = entry.permissions {
                        Text(String(permissions & 0o777, radix: 8)).monospacedDigit()
                    }
                }
            }
            if !message.isEmpty { Text(message).foregroundStyle(.secondary).textSelection(.enabled) }
        }.task { await refreshLocal(); await refreshRemote() }
            .confirmationDialog("删除选中的远端文件？", isPresented: $confirming, titleVisibility: .visible) {
                Button("确认删除", role: .destructive) {
                    guard let remoteSelected else { return }
                    guard loadedRemote == remote else { return }
                    let directory = remoteFiles.first { $0.name == remoteSelected }?.isDirectory == true
                    let path = join(remote, remoteSelected)
                    Task {
                        do {
                            if directory { try await client.deleteDirectory(path, on: host) }
                            else { try await client.deleteFile(path, on: host) }
                            await refreshRemote()
                        }
                        catch { message = error.localizedDescription }
                    }
                }
            }
    }

    private func pane(_ title: String, path: Binding<String>, selection: Binding<String?>,
                      items: [String], metadata: [SFTPEntry] = [], load: @escaping () -> Void) -> some View {
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
                    let entry = metadata.first { $0.name == name }
                    HStack {
                        Label(name, systemImage: entry?.isDirectory == true ? "folder" : "doc")
                        Spacer()
                        if let size = entry?.size, entry?.isDirectory == false {
                            Text(ByteCountFormatter.string(fromByteCount: Int64(clamping: size), countStyle: .file))
                                .foregroundStyle(.secondary)
                        }
                        if let modified = entry?.modified {
                            Text(modified.formatted(date: .numeric, time: .shortened)).foregroundStyle(.secondary)
                        }
                    }.tag(name).onTapGesture(count: 2) {
                        guard entry?.isDirectory != false else { return }
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
            if path == local { localFiles = files; loadedLocal = path }
        } catch { if path == local { localFiles = []; loadedLocal = nil; message = error.localizedDescription } }
    }

    private func refreshRemote() async {
        remoteSelected = nil
        let path = remote
        do {
            let files = try await client.entries(path, on: host)
            if remote == path { remoteFiles = files.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }; loadedRemote = path; message = "" }
        } catch { if path == remote { remoteFiles = []; loadedRemote = nil; message = error.localizedDescription } }
    }

    private func copy(upload: Bool) {
        guard let name = upload ? localSelected : remoteSelected else { return }
        let localPath = URL(fileURLWithPath: join(local, name))
        let remotePath = join(remote, name)
        active = true
        Task {
            defer { active = false }
            do {
                try await transfers.enqueue(.init(host: host, local: localPath, remote: remotePath, upload: upload))
                message = "已加入传输队列"
            } catch { message = error.localizedDescription }
        }
    }
}

struct TransferPage: View {
    @ObservedObject var transfers: TransferQueue

    var body: some View {
        VStack {
            if !transfers.failure.isEmpty { Text(transfers.failure).foregroundStyle(.red) }
            List(transfers.records) { item in
                VStack(alignment: .leading) {
                    HStack {
                        Text(item.name)
                        Spacer()
                        Text(item.state)
                        if ["待传输", "进行中"].contains(item.state) {
                            Button("暂停") { Task { await transfers.pause(item.id) } }
                        }
                        if ["已暂停", "失败"].contains(item.state), item.job != nil {
                            Button("继续") { Task { await transfers.resume(item.id) } }
                        }
                        if ["待传输", "进行中", "已暂停"].contains(item.state) {
                            Button("取消") { Task { await transfers.cancel(item.id) } }
                        }
                    }.buttonStyle(.borderless)
                    if let progress = transfers.progress[item.id], progress.total > 0 {
                        ProgressView(value: Double(progress.completed), total: Double(progress.total))
                    }
                    if let detail = item.detail { Text(detail).font(.caption).foregroundStyle(.secondary) }
                }
            }
        }.task { await transfers.load() }
    }
}
