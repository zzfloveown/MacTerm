import ConnectionCore
import Domain
import Foundation
import SSHCore
import StorageCore
import SwiftUI

struct HostEditor: View {
    @State var host: SSHHost
    var save: (SSHHost) async throws -> Void
    @State private var failure = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            TextField("名称", text: $host.name)
            TextField("主机名或 IP", text: $host.address)
            TextField("SSH 用户名", text: $host.user)
            TextField("端口", value: $host.port, format: .number.grouping(.never))
            TextField("私钥绝对路径", text: $host.identity)
            TextField("跳板机（可用逗号分隔）", text: $host.jump)
            if !failure.isEmpty { Text(failure).foregroundStyle(.red) }
            HStack {
                Button("取消") { dismiss() }
                Spacer()
                Button("保存") {
                    Task {
                        do {
                            try OpenSSHArguments.validate(host)
                            try await save(host)
                            dismiss()
                        } catch { failure = error.localizedDescription }
                    }
                }.keyboardShortcut(.defaultAction)
            }
        }.padding(24).frame(width: 470)
    }
}

struct KeyPage: View {
    let host: SSHHost?
    let store: Store
    let updated: () async -> Void
    @State private var busy = false
    @State private var publicKey = ""
    @State private var password = ""
    @State private var status = ""

    var body: some View {
        Form {
            if let host {
                LabeledContent("服务器", value: host.label)
                LabeledContent("私钥引用", value: host.identity.isEmpty ? "OpenSSH 默认身份或 Agent" : host.identity)
                HStack {
                    Button("生成 Ed25519 密钥") { generate(host) }
                    Button("查看公钥") { query { try await SSHKeyService.publicKey(at: host.identity) } }
                        .disabled(host.identity.isEmpty)
                    Button("查看已验证指纹") { query { try await SSHKeyService.fingerprints(host) } }
                }.disabled(busy)
                if !publicKey.isEmpty { Text(publicKey).font(.system(.caption, design: .monospaced)).textSelection(.enabled) }
                SecureField("存入 Keychain 的凭据", text: $password)
                HStack {
                    Button("保存凭据") {
                        perform { try CredentialVault.store(Data(password.utf8), for: host.id) }
                        password = ""
                    }.disabled(password.isEmpty)
                    Button("删除凭据") { perform { try CredentialVault.delete(host.id) } }
                }
                Text("终端密码直接在 OpenSSH 提示符中输入。").foregroundStyle(.secondary)
                if !status.isEmpty { Text(status) }
            } else { Text("请在侧边栏选择服务器") }
        }.formStyle(.grouped)
    }

    private func generate(_ host: SSHHost) {
        query {
            let url = try await SSHKeyService.generate(in: Store.applicationSupport())
            var updatedHost = host
            updatedHost.identity = url.path
            try await store.save(updatedHost)
            await updated()
            return try await SSHKeyService.publicKey(at: url.path)
        }
    }

    private func query(_ action: @escaping () async throws -> String) {
        busy = true
        status = ""
        Task {
            defer { busy = false }
            do { publicKey = try await action() }
            catch { status = error.localizedDescription }
        }
    }

    private func perform(_ action: () throws -> Void) {
        do { try action(); status = "Keychain 已更新" }
        catch { status = error.localizedDescription }
    }
}
