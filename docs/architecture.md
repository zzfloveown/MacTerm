# 架构

MacTermApp 构建 WindowGroup 和共享 Store。AppUI 管理窗口内工作区，使用 SwiftUI 与 Swift Charts。TerminalCore 通过 NSViewRepresentable 承载 SwiftTerm。Domain 定义可序列化模型和面向用户的错误。Infrastructure 调用系统进程。StorageCore 负责 GRDB 迁移和 Keychain。ConnectionCore 验证参数，SSHCore 提供可替换的 SSHTransport，SFTPCore 使用系统 sftp。MonitorCore、AlertCore、DockerCore、KubernetesCore 和 TransferCore 各自处理业务。当前功能页面放在 AppUI，后续可独立为功能 target。

GRDB 7.12.0 使用 MIT 许可证，需要 Swift 6.1，声明支持 macOS 10.15 起。SwiftTerm 1.19.0 使用 MIT 许可证，需要 Swift 6.0，声明支持 macOS 11 起，固定在 I/O 重构前的版本。较新 1.99 系列已有 macOS 15 PTY 输入缺陷报告，升级需要重新实测。ARM64 兼容性由 GitHub Actions 检验。

- [GRDB 版本和清单](https://github.com/groue/GRDB.swift/tree/v7.12.0)
- [SwiftTerm 版本和清单](https://github.com/migueldeicaza/SwiftTerm/tree/v1.19.0)
- [SwiftTerm PTY 缺陷报告](https://github.com/migueldeicaza/SwiftTerm/issues/833)
