import ConnectionCore
import Domain
import StorageCore
import SwiftUI
import TerminalCore
import UniformTypeIdentifiers

struct SettingsPage: View {
    let store: Store
    @Binding var fontSize: Double
    let onRestore: () async -> Void
    @AppStorage("terminalCursor") private var cursor = TerminalCursor.block
    @AppStorage("terminalScrollback") private var scrollback = 5000
    @AppStorage("terminalAutoReconnect") private var automaticReconnect = false
    @State private var exporting = false
    @State private var importing = false
    @State private var restore: AppConfigurationBackup?
    @State private var document: BackupDocument?
    @State private var status = ""

    var body: some View {
        Form {
            Slider(value: $fontSize, in: 9...26, step: 1) { Text("终端字体大小 \(Int(fontSize))") }
            Picker("终端光标", selection: $cursor) {
                ForEach(TerminalCursor.allCases) { Text($0.rawValue).tag($0) }
            }
            Stepper("滚动缓冲区 \(scrollback) 行", value: $scrollback, in: 1000...30_000, step: 1000)
            Toggle("SSH 异常断开后自动重连", isOn: $automaticReconnect)
            SwiftUI.Section("服务器配置备份") {
                Text("备份包含服务器地址、用户、私钥路径和 SSH 隧道配置，不包含密码或私钥内容。请将文件保存在受信任的位置。")
                    .foregroundStyle(.secondary)
                HStack {
                    Button("导出配置") {
                        Task {
                            do {
                                let hosts = try await store.hosts()
                                let backup = AppConfigurationBackup(hosts: hosts, tunnels: try await store.tunnels(),
                                                                    fontSize: fontSize)
                                document = BackupDocument(data: try JSONEncoder().encode(backup))
                                exporting = true
                            } catch { status = error.localizedDescription }
                        }
                    }
                    Button("导入配置") { importing = true }
                }
            }
            if !status.isEmpty { Text(status).textSelection(.enabled) }
        }.formStyle(.grouped)
            .fileExporter(isPresented: $exporting, document: document, contentType: .json,
                          defaultFilename: "MacTerm-configuration.json") {
                if case .failure(let error) = $0 { status = error.localizedDescription }
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
                do {
                    let url = try result.get()
                    let access = url.startAccessingSecurityScopedResource()
                    defer { if access { url.stopAccessingSecurityScopedResource() } }
                    let file = try FileHandle(forReadingFrom: url)
                    defer { try? file.close() }
                    let data = try file.read(upToCount: 5_000_001) ?? Data()
                    guard data.count <= 5_000_000 else { throw MacTermError("备份文件超过 5 MB。") }
                    let backup = try JSONDecoder().decode(AppConfigurationBackup.self, from: data)
                    guard backup.version == 1, (9...26).contains(backup.fontSize),
                          Set(backup.hosts.map(\.id)).count == backup.hosts.count,
                          Set(backup.tunnels.map(\.id)).count == backup.tunnels.count else {
                        throw MacTermError("备份版本或数据无效。")
                    }
                    try backup.hosts.forEach(OpenSSHArguments.validate)
                    for tunnel in backup.tunnels {
                        guard !tunnel.name.isEmpty, (1...65535).contains(tunnel.listenPort),
                              tunnel.mode == .dynamic || (1...65535).contains(tunnel.destinationPort),
                              backup.hosts.contains(where: { $0.id == tunnel.hostID }) else {
                            throw MacTermError("备份中的 SSH 隧道配置无效。")
                        }
                        if tunnel.mode != .dynamic {
                            try OpenSSHArguments.validate(SSHHost(address: tunnel.destination, user: "check",
                                                                  port: tunnel.destinationPort))
                        }
                    }
                    restore = backup
                } catch { status = error.localizedDescription }
            }
            .confirmationDialog("合并备份的服务器配置？", isPresented: Binding(
                get: { restore != nil }, set: { if !$0 { restore = nil } }
            ), titleVisibility: .visible, presenting: restore) { backup in
                Button("合并 \(backup.hosts.count) 台服务器") {
                    Task {
                        do {
                            // 备份来自外部文件，按新 UUID 导入，防止覆盖现有身份或关联凭据。
                            let identifiers = Dictionary(uniqueKeysWithValues: backup.hosts.map { ($0.id, UUID()) })
                            let hosts = backup.hosts.map { host in
                                var copy = host
                                copy.id = identifiers[host.id]!
                                return copy
                            }
                            let tunnels = backup.tunnels.map { tunnel in
                                var copy = tunnel
                                copy.id = UUID()
                                copy.hostID = identifiers[tunnel.hostID]!
                                return copy
                            }
                            try await store.saveConfiguration(hosts: hosts, tunnels: tunnels)
                            fontSize = backup.fontSize
                            await onRestore()
                            status = "服务器配置已合并。"
                        } catch { status = error.localizedDescription }
                    }
                }
            }
    }
}

private struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    let data: Data

    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
