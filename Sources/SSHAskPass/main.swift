import AppKit
import Foundation
import Security
import SSHAskPassCore

private func run() -> Int32 {
    guard CommandLine.arguments.count == 2,
          let tokenPath = ProcessInfo.processInfo.environment["MACTERM_ASKPASS_TOKEN"] else { return 1 }
    do {
        let prompt = CommandLine.arguments[1]
        let credential = try SSHAskPassHandler.credential(
            for: prompt, tokenURL: URL(fileURLWithPath: tokenPath), lookup: { hostID in
                var query: [String: Any] = [
                    kSecClass as String: kSecClassGenericPassword,
                    kSecAttrService as String: "com.macterm.app.ssh",
                    kSecAttrAccount as String: hostID.uuidString,
                    kSecReturnData as String: true,
                    kSecMatchLimit as String: kSecMatchLimitOne
                ]
                var result: CFTypeRef?
                let status = SecItemCopyMatching(query as CFDictionary, &result)
                query.removeAll(keepingCapacity: false)
                guard status == errSecSuccess else { return nil }
                return result as? Data
            })
        let value: Data
        if let credential, !credential.isEmpty {
            value = credential
        } else if let answer = promptUser(prompt) {
            value = Data(answer.utf8)
        } else { return 1 }
        FileHandle.standardOutput.write(value)
        FileHandle.standardOutput.write(Data([0x0A]))
        return 0
    } catch {
        return 1
    }
}

/// 非服务器密码提示（主机密钥、私钥口令及交互式挑战）交由用户逐次确认或输入。
private func promptUser(_ prompt: String) -> String? {
    NSApplication.shared.setActivationPolicy(.accessory)
    NSApplication.shared.activate(ignoringOtherApps: true)
    let alert = NSAlert()
    let normalized = prompt.lowercased()
    if normalized.contains("are you sure you want to continue connecting") {
        alert.messageText = "确认 SSH 主机密钥"
        alert.informativeText = prompt
        alert.addButton(withTitle: "取消连接")
        alert.addButton(withTitle: "确认并继续")
        return alert.runModal() == .alertSecondButtonReturn ? "yes" : "no"
    }
    alert.messageText = "SSH 需要身份验证"
    alert.informativeText = prompt
    alert.addButton(withTitle: "取消")
    alert.addButton(withTitle: "继续")
    let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
    field.placeholderString = "输入本次提示要求的凭据"
    alert.accessoryView = field
    guard alert.runModal() == .alertSecondButtonReturn else { return nil }
    return field.stringValue
}

exit(run())
