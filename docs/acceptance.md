# 验收记录

## 已通过

- 提交 fc6805b 通过 macos-15 ARM64 Debug 和 Release 编译、单元测试、SSH/SFTP 集成、签名校验、DMG 挂载与应用进程启动。[云端构建](https://github.com/zzfloveown/MacTerm/actions/runs/43623046200)
- 该构建已生成 MacTerm.dmg 和 MacTerm.app.zip。[ARM64 产物](https://github.com/zzfloveown/MacTerm/actions/runs/43623046200/artifacts/14125550194)
- macOS Runner 的 OpenSSH 集成覆盖错误指纹拒绝、SSH 参数往返、双跳 ProxyJump、本地转发、远端转发、SOCKS5、端口冲突和取消。SFTP 覆盖中文文件名、目录项属性、权限、重命名、上传下载、字节校验、双向续传、拒绝损坏分片和失效文本版本。
- Linux Runner 使用真实回环 sshd 运行应用同一采集脚本，并测得 Linux PTY 与 Docker 服务查询成功。[Linux 测试](https://github.com/zzfloveown/MacTerm/actions/runs/43623046200/job/132532743379)
- 临时 containerd/nerdctl 与 kind Kubernetes 的 CLI 合约测试通过。覆盖 nerdctl 查询和数据卷、Node 和 Namespace、Secret 名称与类型、Pod 日志和执行、Deployment 缩容。[容器测试](https://github.com/zzfloveown/MacTerm/actions/runs/43623046200/job/132532743364)

## 待完成

- macOS 14 实机窗口、中文输入、键盘交互、终端全屏工具、通知显示、暂停恢复并发和生产形态下资源管理页面验收。
- 正式发布仓库尚无 Developer ID 或公证 Secrets。安装包目前使用 ad-hoc 签名。Developer ID 签名、Apple 公证、Gatekeeper 和企业分发需要实际验收。
- 完整功能缺口见 [路线图](roadmap.md)。
