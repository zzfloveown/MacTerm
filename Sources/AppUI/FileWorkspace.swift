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
    @State private var localFiles: [String] = []
    @State private var remoteFiles: [SFTPEntry] = []
    @State private var loadedRemote: String?
    @State private var loadedLocal: String?
    @State private var rename = ""
    @State private var permissions = ""
    @State private var synchronized = false
    @State private var fileToDelete: SFTPEntry?
    @State private var editing: RemoteEdit?
    @State private var localSelected: String?
    @State private var remoteSelected: String?
    @State private var message = ""
    @State private var folder = ""
    @State private var active = false
    let client = SFTPClient()

    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Button("刷新") { Task { await refreshLocal(); await refreshRemote() } }
                Button("上传 →") { copy(upload: true) }.disabled(localSelected == nil || loadedLocal != local || loadedRemote != remote || active)
                Button("← 下载") { copy(upload: false) }.disabled(remoteSelected == nil || loadedLocal != local || loadedRemote != remote || active)
                Button("删除远程文件", role: .destructive) {
                    fileToDelete = remoteFiles.first { $0.name == remoteSelected }
                }.disabled(remoteSelected == nil || loadedRemote != remote || active)
                Toggle("同步导航", isOn: $synchronized).toggleStyle(.checkbox)
                Spacer()
                if active { ProgressView().controlSize(.small) }
            }
            HSplitView {
                pane("本地", path: $local, selection: $localSelected, items: localFiles, isRemote: false) {
                    Task { await refreshLocal() }
                }.dropDestination(for: RemoteFileDrag.self) { items, _ in
                    guard loadedLocal == local, loadedRemote == remote else { return false }
                    let accepted = items.filter { $0.host == host.id && $0.directory == remote }
                    for item in accepted where remoteFiles.contains(where: { $0.name == item.name }) {
                        schedule(local: URL(fileURLWithPath: join(local, item.name)), remote: join(remote, item.name),
                                 upload: false, directory: remoteFiles.first { $0.name == item.name }?.isDirectory == true)
                    }
                    return !accepted.isEmpty
                }
                pane("远程 SFTP", path: $remote, selection: $remoteSelected, items: remoteFiles.map(\.name),
                     metadata: remoteFiles, isRemote: true) {
                    Task { await refreshRemote() }
                }.dropDestination(for: URL.self) { items, _ in
                    guard loadedRemote == remote else { return false }
                    let files = items.filter(\.isFileURL)
                    for file in files {
                        let directory = (try? file.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
                        schedule(local: file, remote: join(remote, file.lastPathComponent), upload: true, directory: directory)
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
    }

    private func pane(_ title: String, path: Binding<String>, selection: Binding<String?>,
                      items: [String], metadata: [SFTPEntry] = [], isRemote: Bool, load: @escaping () -> Void) -> some View {
        VStack(alignment: .leading) {
            Text(title).font(.headline)
            HStack {
                Button("上级", systemImage: "arrow.up") {
                    let parent = URL(fileURLWithPath: path.wrappedValue).deletingLastPathComponent().path
                    navigate(parent, name: nil, isRemote: isRemote, path: path, load: load)
                }.labelStyle(.iconOnly)
                TextField("绝对路径", text: path).onSubmit(load)
                Button("打开") { load() }
            }
            List(selection: selection) {
                ForEach(items, id: \.self) { name in
                    let entry = metadata.first { $0.name == name }
                    let row = HStack {
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
            ? (try? localPath.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            : remoteFiles.first { $0.name == name }?.isDirectory == true
        schedule(local: localPath, remote: remotePath, upload: upload, directory: isDirectory)
    }

    private func schedule(local: URL, remote: String, upload: Bool, directory: Bool) {
        Task {
            active = true
            defer { active = false }
            do {
                if directory {
                    try await enqueueTree(local, remote: remote, upload: upload)
                } else {
                    try await transfers.enqueue(.init(host: host, local: local, remote: remote, upload: upload))
                }
                message = "已加入传输队列"
            } catch { message = error.localizedDescription }
        }
    }

    private func enqueueTree(_ source: URL, remote: String, upload: Bool) async throws {
        let tree: (directories: [String], files: [String])
        if upload {
            tree = try await Task.detached { try LocalTransferTree.scan(source) }.value
            for relative in tree.directories {
                try await client.createDirectory(relative.isEmpty ? remote : join(remote, relative), on: host)
            }
        } else {
            tree = try await client.directoryTree(remote, on: host)
            let directories = tree.directories
            try await Task.detached {
                for relative in directories {
                    let folder = relative.isEmpty ? source : source.appendingPathComponent(relative)
                    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false,
                                                            attributes: [.posixPermissions: 0o700])
                }
            }.value
        }
        let jobs = tree.files.map { relative in
            TransferJob(host: host, local: source.appendingPathComponent(relative), remote: join(remote, relative), upload: upload)
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
                        if let rate = transfers.speed[item.id] {
                            Text(rate.formatted(.number.precision(.fractionLength(0))) + " B/s")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    if let detail = item.detail { Text(detail).font(.caption).foregroundStyle(.secondary) }
                }
            }
        }.task { await transfers.load() }
    }
}
