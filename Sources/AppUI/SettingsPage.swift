import ConnectionCore
import Domain
import StorageCore
import SwiftUI
import UniformTypeIdentifiers

struct SettingsPage: View {
    let store: Store
    @Binding var fontSize: Double
    let onRestore: () async -> Void
    @State private var exporting = false
    @State private var importing = false
    @State private var restore: ConfigurationBackup?
    @State private var document: BackupDocument?
    @State private var status = ""

    var body: some View {
        Form {
            Slider(value: $fontSize, in: 9...26, step: 1) { Text("终端字体大小 \(Int(fontSize))") }
            SwiftUI.Section("服务器配置备份") {
                Text("备份包含服务器地址、用户和私钥路径。请将文件保存在受信任的位置。")
                    .foregroundStyle(.secondary)
                HStack {
                    Button("导出配置") {
                        Task {
                            do {
                                let backup = ConfigurationBackup(hosts: try await store.hosts(), fontSize: fontSize)
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
                    let backup = try JSONDecoder().decode(ConfigurationBackup.self, from: data)
                    guard backup.version == 1, (9...26).contains(backup.fontSize),
                          Set(backup.hosts.map(\.id)).count == backup.hosts.count else {
                        throw MacTermError("备份版本或数据无效。")
                    }
                    try backup.hosts.forEach(OpenSSHArguments.validate)
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
                            let hosts = backup.hosts.map { host in
                                var copy = host
                                copy.id = UUID()
                                return copy
                            }
                            try await store.save(hosts)
                            fontSize = backup.fontSize
                            await onRestore()
                            status = "服务器配置已合并。"
                        } catch { status = error.localizedDescription }
                    }
                }
            }
    }
}

private struct ConfigurationBackup: Codable {
    var version = 1
    let hosts: [SSHHost]
    let fontSize: Double
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
