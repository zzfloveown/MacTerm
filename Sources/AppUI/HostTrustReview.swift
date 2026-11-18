import Domain
import SSHCore
import SwiftUI

struct HostTrustReview: View {
    let host: SSHHost
    var onUpdated: () -> Void = {}
    @Environment(\.dismiss) private var dismiss
    @State private var review: SSHHostTrustReview?
    @State private var selectedFingerprint = ""
    @State private var verified = false
    @State private var busy = false
    @State private var failure = ""
    @State private var confirming = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("检查主机指纹").font(.title2.bold())
            LabeledContent("服务器", value: host.label)
            LabeledContent("连接目标", value: "\(host.address):\(host.port)")
            Text("修改登录密码不会改变主机指纹。重装系统或更换 SSH 主机密钥后，请通过云服务器控制台核对新指纹。")
                .foregroundStyle(.secondary)
            if busy { ProgressView(review == nil ? "正在获取主机公钥…" : "正在更新信任记录…") }
            if let review {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("已保存的指纹").font(.headline)
                        Text(review.savedFingerprints).font(.system(.callout, design: .monospaced)).textSelection(.enabled)
                        Text("当前获取的指纹（尚未验证身份）").font(.headline)
                        Picker("选择已核对的公钥", selection: $selectedFingerprint) {
                            ForEach(review.candidates) { candidate in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(candidate.algorithm)
                                    Text(candidate.fingerprint).font(.system(.callout, design: .monospaced))
                                }.tag(candidate.fingerprint)
                            }
                        }.pickerStyle(.radioGroup)
                        if let candidate = review.candidates.first(where: { $0.fingerprint == selectedFingerprint }) {
                            Text(candidate.fingerprint).font(.system(.callout, design: .monospaced)).textSelection(.enabled)
                        }
                        Text("服务器提供的公钥可能被冒充。请从云服务器控制台或管理员处取得同类型的 SHA256 指纹，核对一致后再更新。更新只信任所选公钥，不会关闭 SSH 指纹校验。")
                            .foregroundStyle(.secondary)
                        Toggle("我已通过服务器控制台或管理员核对所选指纹", isOn: $verified)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            if !failure.isEmpty { Text(failure).foregroundStyle(.red).textSelection(.enabled) }
            HStack {
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction).disabled(busy)
                Spacer()
                Button("更新已核对的指纹", role: .destructive) { confirming = true }
                    .disabled(review == nil || selectedFingerprint.isEmpty || !verified || busy)
            }
        }
        .padding(24)
        .frame(width: 660, height: 570)
        .task { await inspect() }
        .onChange(of: selectedFingerprint) { _, _ in verified = false }
        .confirmationDialog("确认替换此目标的已保存指纹？", isPresented: $confirming, titleVisibility: .visible) {
            Button("确认更新指纹", role: .destructive) { Task { await update() } }
            Button("取消", role: .cancel) {}
        } message: {
            Text("目标：\(host.address):\(host.port)\n将信任所选公钥：\(selectedFingerprint)\n影响此账户使用该地址和端口的 SSH 连接。更新后仍严格校验主机身份。")
        }
    }

    @MainActor private func inspect() async {
        busy = true
        defer { busy = false }
        do {
            let result = try await SSHHostTrust.inspect(host)
            review = result
            selectedFingerprint = result.candidates.first?.fingerprint ?? ""
        } catch { failure = error.localizedDescription }
    }

    @MainActor private func update() async {
        guard let review, verified else { return }
        busy = true
        failure = ""
        defer { busy = false }
        do {
            try await SSHHostTrust.update(review, fingerprint: selectedFingerprint)
            onUpdated()
            dismiss()
        } catch {
            failure = error.localizedDescription
            verified = false
        }
    }
}
