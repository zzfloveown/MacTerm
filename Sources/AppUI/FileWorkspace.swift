import AppKit
import CoreTransferable
import Domain
import Foundation
import SFTPCore
import StorageCore
import SwiftUI
import TransferCore
import UniformTypeIdentifiers

struct FileWorkspace: View {
    let host: SSHHost
    @ObservedObject var transfers: TransferQueue
    @State private var local = FileManager.default.homeDirectoryForCurrentUser.path
    @State private var remote = "/"
    @State private var localFiles: [SFTPEntry] = []
    @State private var remoteFiles: [SFTPEntry] = []
    @State private var localFilter = ""
    @State private var remoteFilter = ""
    @State private var loadedRemote: String?
    @State private var loadedLocal: String?
    @State private var rename = ""
    @State private var permissions = ""
    @State private var synchronized = false
    @State private var allowOverwrite = false
    @State private var pendingOverwrite: PendingTransfer?
    @State private var fileToDelete: SFTPEntry?
    @State private var editing: RemoteEdit?
    @State private var localSelected: String?
    @State private var remoteSelected: String?
    @State private var message = ""
    @State private var folder = ""
    @State private var active = false
    let client = SFTPClient()

    private struct PendingTransfer: Identifiable {
        let id = UUID()
        let local: URL
        let remote: String
        let upload: Bool
        let directory: Bool
        var targetLabel: String { upload ? remote : local.path }
    }

    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Button("刷新", systemImage: "arrow.clockwise") { Task { await refreshLocal(); await refreshRemote() } }
                Button("上传 →") { copy(upload: true) }.disabled(localSelected == nil || loadedLocal != local || loadedRemote != remote || active)
                Button("← 下载") { copy(upload: false) }.disabled(remoteSelected == nil || loadedLocal != local || loadedRemote != remote || active)
                Button("删除远程文件", role: .destructive) {
                    fileToDelete = remoteFiles.first { $0.name == remoteSelected }
                }.disabled(remoteSelected == nil || loadedRemote != remote || active)
                Toggle("同步导航", isOn: $synchronized).toggleStyle(.checkbox)
                Toggle("允许覆盖同名文件", isOn: $allowOverwrite).toggleStyle(.checkbox)
                Spacer()
                if active { ProgressView().controlSize(.small) }
            }
            HSplitView {
                pane("本地", path: $local, filter: $localFilter, selection: $localSelected,
                     metadata: filtered(localFiles, query: localFilter), isRemote: false) {
                    Task { await refreshLocal() }
                }.dropDestination(for: RemoteFileDrag.self) { items, _ in
                    guard loadedLocal == local, loadedRemote == remote else { return false }
                    let accepted = items.filter { $0.host == host.id && $0.directory == remote }
                    for item in accepted where remoteFiles.contains(where: { $0.name == item.name }) {
                        requestTransfer(local: URL(fileURLWithPath: join(local, item.name)), remote: join(remote, item.name),
                                        upload: false, directory: remoteFiles.first { $0.name == item.name }?.isDirectory == true)
                    }
                    return !accepted.isEmpty
                }
                pane("远程 SFTP", path: $remote, filter: $remoteFilter, selection: $remoteSelected,
                     metadata: filtered(remoteFiles, query: remoteFilter), isRemote: true) {
                    Task { await refreshRemote() }
                }.dropDestination(for: URL.self) { items, _ in
                    guard loadedRemote == remote else { return false }
                    let files = items.filter(\.isFileURL)
                    for file in files {
                        let directory = (try? file.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
                        requestTransfer(local: file, remote: join(remote, file.lastPathComponent), upload: true, directory: directory)
                    }
                    return !files.isEmpty
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
                    Button("编辑文本") { edit(entry) }.disabled(entry.isDirectory || active)
                    TextField("新名称或远端绝对路径", text: $rename)
                    Button("重命名") {
                        let from = join(remote, entry.name), to = rename.hasPrefix("/") ? rename : join(remote, rename)
                        Task {
                            do { try await client.rename(from, to: to, on: host); rename = ""; await refreshRemote() }
                            catch { message = error.localizedDescription }
                        }
                    }.disabled(rename.isEmpty || (!rename.hasPrefix("/") && rename.contains("/")) || [".", ".."].contains(rename))
                    if let permissions = entry.permissions {
                        Text(String(permissions & 0o777, radix: 8)).monospacedDigit()
                    }
                    TextField("权限", text: $permissions).frame(width: 65)
                    Button("修改权限") {
                        guard let mode = UInt32(permissions, radix: 8) else { return }
                        let destination = join(remote, entry.name)
                        Task {
                            do { try await client.setPermissions(mode, at: destination, on: host); await refreshRemote() }
                            catch { message = error.localizedDescription }
                        }
                    }.disabled(UInt32(permissions, radix: 8).map { $0 > 0o777 } ?? true)
                }
            }
            if !message.isEmpty { Text(message).foregroundStyle(.secondary).textSelection(.enabled) }
        }.task { await refreshLocal(); await refreshRemote() }
            .sheet(item: $editing) { item in
                RemoteEditor(edit: item, client: client, host: host) { await refreshRemote() }
            }
            .confirmationDialog("删除远端项目？", isPresented: Binding(
                get: { fileToDelete != nil }, set: { if !$0 { fileToDelete = nil } }
            ), titleVisibility: .visible, presenting: fileToDelete) { entry in
                Button("确认删除", role: .destructive) {
                    guard let directory = loadedRemote, directory == remote else { return }
                    let path = join(directory, entry.name)
                    Task {
                        do {
                            if entry.isDirectory { try await client.deleteDirectory(path, on: host) }
                            else { try await client.deleteFile(path, on: host) }
                            await refreshRemote()
                        } catch { message = error.localizedDescription }
                    }
                }
            } message: { Text($0.name) }
            .confirmationDialog("确认覆盖目标文件？", isPresented: Binding(
                get: { pendingOverwrite != nil }, set: { if !$0 { pendingOverwrite = nil } }
            ), titleVisibility: .visible, presenting: pendingOverwrite) { item in
                Button("确认覆盖并传输", role: .destructive) {
                    schedule(local: item.local, remote: item.remote, upload: item.upload,
                             directory: item.directory, overwrite: true)
                }
            } message: { Text($0.targetLabel) }
    }

    private func filtered(_ items: [SFTPEntry], query: String) -> [SFTPEntry] {
        guard !query.isEmpty else { return items }
        return items.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    private func pane(_ title: String, path: Binding<String>, filter: Binding<String>, selection: Binding<String?>,
                      metadata: [SFTPEntry], isRemote: Bool, load: @escaping () -> Void) -> some View {
        VStack(alignment: .leading) {
            HStack {
                Text(title).font(.headline)
                Spacer()
                Text("\(metadata.count) 项").font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Button("上级", systemImage: "arrow.up") {
                    let parent = URL(fileURLWithPath: path.wrappedValue).deletingLastPathComponent().path
                    navigate(parent, name: nil, isRemote: isRemote, path: path, load: load)
                }.labelStyle(.iconOnly)
                Button(isRemote ? "根目录" : "主目录", systemImage: isRemote ? "externaldrive" : "house") {
                    let target = isRemote ? "/" : FileManager.default.homeDirectoryForCurrentUser.path
                    path.wrappedValue = target
                    load()
                }.labelStyle(.iconOnly)
                TextField("绝对路径", text: path).onSubmit(load)
                Button("打开") { load() }
            }
            TextField("筛选文件名", text: filter)
                .textFieldStyle(.roundedBorder)
                .controlSize(.small)
            List(selection: selection) {
                ForEach(metadata) { entry in
                    let name = entry.name
                    let row = HStack {
                        Label(name, systemImage: entry.isDirectory ? "folder.fill" : "doc")
                        Spacer()
                        if let size = entry.size, !entry.isDirectory {
                            Text(ByteCountFormatter.string(fromByteCount: Int64(clamping: size), countStyle: .file))
                                .foregroundStyle(.secondary)
                        }
                        if let modified = entry.modified {
                            Text(modified.formatted(date: .numeric, time: .shortened)).foregroundStyle(.secondary)
                        }
                    }.tag(name).onTapGesture(count: 2) {
                        guard entry.isDirectory else { return }
                        navigate(join(path.wrappedValue, name), name: name, isRemote: isRemote, path: path, load: load)
                    }
                    if isRemote {
                        row.draggable(RemoteFileDrag(host: host.id, directory: path.wrappedValue, name: name))
                    } else {
                        row.draggable(URL(fileURLWithPath: join(path.wrappedValue, name)))
                    }
                }
            }
        }.padding(8).frame(minWidth: 280)
    }

    private func edit(_ entry: SFTPEntry) {
        let path = join(remote, entry.name)
        Task {
            active = true
            defer { active = false }
            do {
                let file = try await client.readText(at: path, on: host)
                editing = RemoteEdit(path: path, original: file)
            } catch { message = error.localizedDescription }
        }
    }

    private func join(_ folder: String, _ name: String) -> String {
        folder == "/" ? "/" + name : folder + "/" + name
    }

    private func refreshLocal() async {
        localSelected = nil
        let path = local
        do {
            let files = try await Task.detached { () -> [SFTPEntry] in
                let manager = FileManager.default
                let names = try manager.contentsOfDirectory(atPath: path)
                return names.map { name in
                    let full = path == "/" ? "/" + name : path + "/" + name
                    let attrs = try? manager.attributesOfItem(atPath: full)
                    let isDir = (attrs?[.type] as? FileAttributeType) == .typeDirectory
                    let posix = (attrs?[.posixPermissions] as? NSNumber)?.uint32Value ?? (isDir ? 0o755 : 0o644)
                    let mode: UInt32 = (isDir ? 0o040000 : 0o100000) | (posix & 0o777)
                    let size = (attrs?[.size] as? NSNumber)?.uint64Value
                    let modified = attrs?[.modificationDate] as? Date
                    return SFTPEntry(name: name, size: size, permissions: mode, modified: modified)
                }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
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

    private func navigate(_ destination: String, name: String?, isRemote: Bool, path: Binding<String>, load: () -> Void) {
        path.wrappedValue = destination
        load()
        guard synchronized else { return }
        if isRemote {
            local = name.map { join(local, $0) } ?? URL(fileURLWithPath: local).deletingLastPathComponent().path
            Task { await refreshLocal() }
        } else {
            remote = name.map { join(remote, $0) } ?? URL(fileURLWithPath: remote).deletingLastPathComponent().path
            Task { await refreshRemote() }
        }
    }

    private func copy(upload: Bool) {
        guard let name = upload ? localSelected : remoteSelected else { return }
        let localPath = URL(fileURLWithPath: join(local, name))
        let remotePath = join(remote, name)
        let isDirectory = upload
            ? localFiles.first { $0.name == name }?.isDirectory == true
            : remoteFiles.first { $0.name == name }?.isDirectory == true
        requestTransfer(local: localPath, remote: remotePath, upload: upload, directory: isDirectory)
    }

    private func requestTransfer(local: URL, remote: String, upload: Bool, directory: Bool) {
        let name = local.lastPathComponent
        let targetExists = upload
            ? remoteFiles.contains { $0.name == name }
            : localFiles.contains { $0.name == name }
        if allowOverwrite && (targetExists || directory) {
            pendingOverwrite = PendingTransfer(local: local, remote: remote, upload: upload, directory: directory)
        } else {
            schedule(local: local, remote: remote, upload: upload, directory: directory, overwrite: false)
        }
    }

    private func schedule(local: URL, remote: String, upload: Bool, directory: Bool, overwrite: Bool) {
        Task {
            active = true
            defer { active = false }
            do {
                if directory {
                    try await enqueueTree(local, remote: remote, upload: upload, overwrite: overwrite)
                } else {
                    try await transfers.enqueue(.init(host: host, local: local, remote: remote,
                                                      upload: upload, overwrite: overwrite))
                }
                message = overwrite ? "已按覆盖策略加入传输队列" : "已加入传输队列"
            } catch { message = error.localizedDescription }
        }
    }

    private func enqueueTree(_ source: URL, remote: String, upload: Bool, overwrite: Bool) async throws {
        let tree: (directories: [String], files: [String])
        if upload {
            tree = try await Task.detached { try LocalTransferTree.scan(source) }.value
            for relative in tree.directories {
                let targetDir = relative.isEmpty ? remote : join(remote, relative)
                do {
                    try await client.createDirectory(targetDir, on: host)
                } catch where overwrite {
                    continue
                }
            }
        } else {
            tree = try await client.directoryTree(remote, on: host)
            let directories = tree.directories
            try await Task.detached {
                for relative in directories {
                    let folder = relative.isEmpty ? source : source.appendingPathComponent(relative)
                    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: overwrite,
                                                            attributes: [.posixPermissions: 0o700])
                }
            }.value
        }
        let jobs = tree.files.map { relative in
            TransferJob(host: host, local: source.appendingPathComponent(relative),
                        remote: join(remote, relative), upload: upload, overwrite: overwrite)
        }
        try await transfers.enqueue(jobs)
    }
}

private struct RemoteFileDrag: Codable, Transferable {
    let host: UUID
    let directory: String
    let name: String

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .init(exportedAs: "com.macterm.app.remote-file"))
    }
}

private enum LocalTransferTree {
    static func scan(_ root: URL) throws -> (directories: [String], files: [String]) {
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey]
        let type = try root.resourceValues(forKeys: keys)
        guard type.isDirectory == true, type.isSymbolicLink != true,
              let children = FileManager.default.enumerator(at: root, includingPropertiesForKeys: Array(keys)) else {
            throw MacTermError("无法读取本地目录。")
        }
        var directories = [""]
        var files: [String] = []
        for case let child as URL in children {
            let info = try child.resourceValues(forKeys: keys)
            if info.isSymbolicLink == true { children.skipDescendants(); continue }
            let relative = child.pathComponents.dropFirst(root.pathComponents.count).joined(separator: "/")
            if info.isDirectory == true { directories.append(relative) }
            if info.isRegularFile == true { files.append(relative) }
            guard directories.count + files.count <= 100_000 else { throw MacTermError("目录超过递归扫描上限。") }
        }
        return (directories, files)
    }
}

struct TransferPage: View {
    @ObservedObject var transfers: TransferQueue
    @State private var cleaningItem: TransferRecord?

    private var completedCount: Int { transfers.records.filter { $0.state == "已完成" }.count }
    private var activeCount: Int { transfers.records.filter { ["待传输", "进行中", "已暂停"].contains($0.state) }.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("传输队列").font(.title2.weight(.semibold))
                Text("活动 \(activeCount) · 已完成 \(completedCount)")
                    .font(.callout).foregroundStyle(.secondary)
                Spacer()
                Button("清理已完成记录", systemImage: "checkmark.circle.badge.xmark") {
                    Task { await transfers.clearCompleted() }
                }.disabled(completedCount == 0)
            }
            if !transfers.failure.isEmpty { Text(transfers.failure).foregroundStyle(.red) }
            if transfers.records.isEmpty {
                ContentUnavailableView("暂无传输任务", systemImage: "arrow.up.arrow.down",
                                       description: Text("在 SFTP 文件页选择上传或下载后，任务将在此处显示进度并支持断点续传。"))
            } else {
                List(transfers.records) { item in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Image(systemName: item.job?.upload == false ? "arrow.down.circle.fill" : "arrow.up.circle.fill")
                                .foregroundStyle(item.job?.upload == false ? .teal : .blue)
                            Text(item.name).font(.headline)
                            if item.job?.overwrite == true {
                                Text("覆盖").font(.caption2).padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(.orange.opacity(0.15), in: Capsule())
                            }
                            Spacer()
                            Text(item.state)
                                .font(.caption.weight(.medium))
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(.quaternary, in: Capsule())
                            if ["待传输", "进行中"].contains(item.state) {
                                Button("暂停") { Task { await transfers.pause(item.id) } }
                            }
                            if ["已暂停", "失败"].contains(item.state), item.job != nil {
                                Button("继续") { Task { await transfers.resume(item.id) } }
                            }
                            if ["待传输", "进行中", "已暂停"].contains(item.state) {
                                Button("取消") { Task { await transfers.cancel(item.id) } }
                            }
                            if item.state == "已完成" {
                                Button("移除记录") { Task { await transfers.remove(item.id) } }
                            }
                            if ["已取消", "失败"].contains(item.state) {
                                Button("清理临时文件并移除", role: .destructive) { cleaningItem = item }
                            }
                        }.buttonStyle(.borderless)
                        if let job = item.job {
                            Text("\(job.host.label) · \(job.upload ? "\(job.local.path) → \(job.remote)" : "\(job.remote) → \(job.local.path)")")
                                .font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(1)
                        }
                        if let progress = transfers.progress[item.id], progress.total > 0 {
                            ProgressView(value: Double(progress.completed), total: Double(progress.total))
                            HStack {
                                Text("\(ByteCountFormatter.string(fromByteCount: Int64(clamping: progress.completed), countStyle: .file)) / \(ByteCountFormatter.string(fromByteCount: Int64(clamping: progress.total), countStyle: .file))")
                                Spacer()
                                if let rate = transfers.speed[item.id] {
                                    Text(ByteCountFormatter.string(fromByteCount: Int64(max(0, rate)), countStyle: .file) + "/s")
                                }
                            }.font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        }
                        if let detail = item.detail { Text(detail).font(.caption).foregroundStyle(.red) }
                    }.padding(.vertical, 4)
                }
            }
        }
        .task { await transfers.load() }
        .confirmationDialog("清理该任务的临时文件并移除记录？", isPresented: Binding(
            get: { cleaningItem != nil }, set: { if !$0 { cleaningItem = nil } }
        ), titleVisibility: .visible, presenting: cleaningItem) { item in
            Button("确认清理并移除", role: .destructive) {
                Task { await transfers.remove(item.id, cleanPartial: true) }
            }
            Button("仅移除记录") {
                Task { await transfers.remove(item.id, cleanPartial: false) }
            }
        } message: { item in
            Text(item.name)
        }
    }
}
