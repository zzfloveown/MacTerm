import AppKit
import ConnectionCore
import Domain
import SwiftTerm
import SwiftUI

/// 用 SwiftTerm 的原生 PTY 桥接 OpenSSH，交互式认证由 OpenSSH 处理。
public struct SSHTerminal: NSViewRepresentable {
    private let executable: String
    private let args: [String]
    private let fontSize: Double
    private let onExit: (Int32?) -> Void

    public init(host: SSHHost, fontSize: Double = 13, command: [String] = [],
                onExit: @escaping (Int32?) -> Void = { _ in }) throws {
        executable = "/usr/bin/ssh"
        args = try OpenSSHArguments.common(host, interactive: true)
            + ["-tt", "--", host.address]
            + (command.isEmpty ? [] : [command.map(OpenSSHArguments.shellQuote).joined(separator: " ")])
        self.fontSize = fontSize
        self.onExit = onExit
    }

    public init(executable: String, arguments: [String], fontSize: Double = 13,
                onExit: @escaping (Int32?) -> Void = { _ in }) {
        self.executable = executable
        args = arguments
        self.fontSize = fontSize
        self.onExit = onExit
    }

    public func makeCoordinator() -> Coordinator { Coordinator(onExit: onExit) }

    public func makeNSView(context: Context) -> LocalProcessTerminalView {
        let view = SearchableTerminal(frame: .zero)
        view.nativeBackgroundColor = .black
        view.nativeForegroundColor = .white
        view.font = .monospacedSystemFont(ofSize: fontSize, weight: .regular)
        view.processDelegate = context.coordinator
        view.startProcess(executable: executable, args: args)
        return view
    }

    public func updateNSView(_ view: LocalProcessTerminalView, context: Context) {
        let font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        if view.font != font { view.font = font }
        context.coordinator.onExit = onExit
    }

    public static func dismantleNSView(_ view: LocalProcessTerminalView, coordinator: Coordinator) {
        view.processDelegate = nil
        view.terminate()
    }

    public final class Coordinator: LocalProcessTerminalViewDelegate {
        var onExit: (Int32?) -> Void
        init(onExit: @escaping (Int32?) -> Void) { self.onExit = onExit }

        public func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}
        public func setTerminalTitle(source: LocalProcessTerminalView, title: String) {}
        public func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
        public func processTerminated(source: TerminalView, exitCode: Int32?) {
            DispatchQueue.main.async { self.onExit(exitCode) }
        }
    }
}

private final class SearchableTerminal: LocalProcessTerminalView {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
           event.charactersIgnoringModifiers?.lowercased() == "f" {
            let action = NSMenuItem()
            action.tag = NSTextFinder.Action.showFindInterface.rawValue
            performTextFinderAction(action)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}
