# 验收记录

## ARM64 云端构建

- 基线提交 2b25038 在 GitHub macos-15 ARM64 Runner 上通过 Debug 和 Release 编译、四项单元测试、一项 SSH/SFTP 集成测试。代码签名检查和 DMG 校验通过。[构建日志](https://github.com/zzfloveown/MacTerm/actions/runs/43620033738)
- MacTerm-arm64 产物包含 MacTerm.dmg 和 MacTerm.app.zip。已下载并核对 App 内包含二进制、Info.plist 和依赖资源。[构建产物](https://github.com/zzfloveown/MacTerm/actions/runs/43620033738/artifacts/14123683848)
- 公开仓库私钥材料扫描通过。[安全扫描](https://github.com/zzfloveown/MacTerm/actions/runs/43620033849)

## 功能验收

- 回环 OpenSSH 集成覆盖命令参数往返、错误主机指纹拒绝、中文路径、SFTP 上传下载字节一致性、重命名与删除。测试服务运行于 macOS Runner。
- 单元测试覆盖 GRDB 迁移和服务器 CRUD、安全参数、SFTP 路径校验、CPU/内存/网络解析与计算。
- Linux 实机交互终端和实时监控、macOS 14 图形界面、SSH 转发联通、Docker、nerdctl 和 Kubernetes 实际环境待验收。
- 试用包采用 ad-hoc 签名。GitHub 仓库尚无 Developer ID 或公证 Secrets。正式签名、公证、Gatekeeper 启动与内网分发待验收。

后续实现和测试计划见 [路线图](roadmap.md)。
