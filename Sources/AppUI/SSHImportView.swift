import ConnectionCore
import Domain
import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct SSHImportView: View {
    @Binding var presenting: Bool
    let existing: [SSHHost]
    let save: ([SSHHost]) async throws -> Void
    @State private var result: SSHConfigImport?
    @State private var failure = ""
    @State private var saving = false

    var body: some View {
        Color.clear.frame(width: 0, height: 0)
            .fileImporter(isPresented: $presenting, allowedContentTypes: [.item]) { picked in
                do {
                    let url = try picked.get()
                    let access = url.startAccessingSecurityScopedResource()
                    defer { if access { url.stopAccessingSecurityScopedResource() } }
                    let file = try FileHandle(forReadingFrom: url)
                    defer { try? file.close() }
                    let data = try file.read(upToCount: 1_048_577) ?? Data()
                    guard data.count <= 1_048_576, let text = String(data: data, encoding: .utf8) else {
                        throw MacTermError("请选择小于 1 MiB 的 UTF-8 SSH 配置文件。")
                    }
                    result = SSHConfigImport.parse(text, currentUser: NSUserName(), home: FileManager.default.homeDirectoryForCurrentUser)
                } catch { failure = error.localizedDescription }
            }
            .sheet(isPresented: Binding(get: { result != nil }, set: { if !$0 { result = nil } })) {
                if let result {
                    preview(result)
                }
            }
            .alert("导入失败", isPresented: Binding(get: { !failure.isEmpty }, set: { if !$0 { failure = "" } })) {
                Button("好", role: .cancel) {}
            } message: { Text(failure) }
    }

    private func preview(_ result: SSHConfigImport) -> some View {
        let candidates = result.hosts.filter { candidate in
            !existing.contains { $0.address == candidate.address && $0.user == candidate.user && $0.port == candidate.port }
        }
        return VStack(alignment: .leading, spacing: 12) {
            Text("导入 SSH 配置").font(.headline)
            Text("可导入 \(candidates.count) 台，跳过 \(result.skipped + result.hosts.count - candidates.count) 项。")
            List(candidates) { host in
                LabeledContent(host.label, value: "\(host.user)@\(host.address):\(host.port)")
            }
            HStack {
                Button("取消") { self.result = nil }.disabled(saving)
                Spacer()
                Button("导入") {
                    saving = true
                    Task {
                        defer { saving = false }
                        do { try await save(candidates); self.result = nil }
                        catch { self.result = nil; failure = error.localizedDescription }
                    }
                }.disabled(candidates.isEmpty || saving).keyboardShortcut(.defaultAction)
            }
        }.padding().frame(width: 500, height: 320)
    }
}
