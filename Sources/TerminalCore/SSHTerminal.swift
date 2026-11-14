import ConnectionCore
import Domain
import SwiftTerm
import SwiftUI

/// 用 SwiftTerm 的原生 PTY 桥接 OpenSSH，交互式认证由 OpenSSH 处理。
public struct SSHTerminal: NSViewRepresentable {
    private let args: [String]
    private let fontSize: Double

    public init(host: Host, fontSize: Double = 13, command: [String] = []) throws {
        args = try OpenSSHArguments.common(host, interactive: true)
            + ["-tt", "--", host.address]
            + (command.isEmpty ? [] : [command.map(OpenSSHArguments.shellQuote).joined(separator: " ")])
        self.fontSize = fontSize
    }

    public func makeNSView(context: Context) -> LocalProcessTerminalView {
        let view = LocalProcessTerminalView(frame: .zero)
        view.nativeBackgroundColor = .black
        view.nativeForegroundColor = .white
        view.font = .monospacedSystemFont(ofSize: fontSize, weight: .regular)
        view.startProcess(executable: "/usr/bin/ssh", args: args)
        return view
    }

    public func updateNSView(_ view: LocalProcessTerminalView, context: Context) {
        view.font = .monospacedSystemFont(ofSize: fontSize, weight: .regular)
    }

    public static func dismantleNSView(_ view: LocalProcessTerminalView, coordinator: Void) {
        view.terminate()
    }
}
