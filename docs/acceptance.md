# 验收记录

- 公开仓库创建、推送和私钥材料扫描通过。[安全扫描](https://github.com/zzfloveown/MacTerm/actions/runs/43619756573)
- ARM64 Runner 架构检查、SwiftPM Debug 与 Release 编译及四项单元测试通过。
- 回环 OpenSSH 集成通过。覆盖 SSH 命令参数往返、错误主机指纹拒绝、中文路径、SFTP 上传下载字节一致性、重命名与删除。该测试服务运行于 macOS Runner。[集成与构建日志](https://github.com/zzfloveown/MacTerm/actions/runs/43619685584)
- 回归修复包括 Swift 类型命名、临时 sshd 认证、hdiutil 参数和 macOS 标准签名资源目录。最终打包结果待核验。
- Linux 交互终端、Linux 实机监控、转发、Docker、Kubernetes、macOS 14 图形界面和企业公证仍待验收。正式发布仓库尚无签名公证 Secrets。
