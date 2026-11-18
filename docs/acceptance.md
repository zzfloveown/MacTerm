# 验收记录

## 已通过

- 提交 fc6805b 通过 macos-15 ARM64 Debug 和 Release 编译、单元测试、SSH/SFTP 集成、签名校验、DMG 挂载与应用进程启动。[云端构建](https://github.com/zzfloveown/MacTerm/actions/runs/43623046200)
- 该构建已生成 MacTerm.dmg 和 MacTerm.app.zip。[ARM64 产物](https://github.com/zzfloveown/MacTerm/actions/runs/43623046200/artifacts/14125550194)
- macOS Runner 的 OpenSSH 集成覆盖错误指纹拒绝、SSH 参数往返、双跳 ProxyJump、本地转发、远端转发、SOCKS5、端口冲突和取消。SFTP 覆盖中文文件名、目录项属性、权限、重命名、上传下载、字节校验、双向续传、拒绝损坏分片和失效文本版本。
- Linux Runner 使用真实回环 sshd 运行应用同一采集脚本，并测得 Linux PTY 与 Docker 服务查询成功。[Linux 测试](https://github.com/zzfloveown/MacTerm/actions/runs/43715883322/job/132817198352)
- 临时 containerd/nerdctl 与 kind Kubernetes 的 CLI 合约测试通过。覆盖 nerdctl 查询和数据卷、Node 和 Namespace、Secret 名称与类型、Pod 日志和执行、Deployment 缩容。[容器测试](https://github.com/zzfloveown/MacTerm/actions/runs/43715883322/job/132817198357)
- 提交 94044e0 的 ARM64 云端构建通过，14 项单元测试零失败（3 项依赖 SSH fixture 的测试在普通单测任务跳过，随后专用 SSH/SFTP 集成任务 3/3 通过）；Release 构建、SSHAskPass 助手签名、DMG 校验和镜像内应用启动通过。[Actions](https://github.com/zzfloveown/MacTerm/actions/runs/43715883322)
- 最新 ARM64 构建（提交 d4dd2e4）通过单元测试、SSH/SFTP 集成（含双向覆盖传输与临时文件清理）、Linux 与容器集成任务；验证包内含 AppIcon.icns、10 个 macOS 图标尺寸，DMG 校验及包内应用启动通过。[Actions](https://github.com/zzfloveown/MacTerm/actions/runs/44262840023)
- 含 MacTerm.app.zip 与 MacTerm.dmg 的交付产物：[下载 ARM64 构建产物](https://github.com/zzfloveown/MacTerm/actions/runs/44262840023/artifacts/14408583228)

## 新增功能

- 主机配置现支持用户逐台启用 Keychain 密码自动提交。ARM64 CI 已通过单次令牌、其他提示不泄露密码及旧配置兼容测试。
- 安装包将包含独立 SSHAskPass 原生助手，主机密钥首次确认及私钥/交互挑战使用原生安全输入框；需在 macOS GUI 实机确认系统对话框与终端体验。
- SSH 隧道配置现可按主机保存本地/远程/SOCKS5 模式、端口、目标和重连选项；GRDB 保存、读取和删除服务器时级联清理测试已通过。
- 配置备份包含 SSH 隧道并兼容旧版文件，导入时重新映射主机/隧道 UUID 且在单一事务中保存；往返与旧格式单测已通过。
- 监控页显示用户态、系统态、空闲及 I/O Wait；ARM64 单元测试验证了真实计数差值计算。
- MacTerm 图标现由原生 AppKit 绘制并进入 ICNS 包，CI 从 DMG 解包检查 16 到 1024 像素共 10 个标准尺寸。
- 工作台提供服务器、终端和活动传输统计卡，以及单击进入 SSH、SFTP、监控、Docker 和隧道页面的快捷操作。
- 服务器详情页提供连接属性、跳板机/密钥/认证状态、复制连接地址和终端/SFTP/监控/Docker/隧道入口；删除前显示关联数据清理说明。应用界面锁定浅色外观，终端维持独立深色配色。
- SFTP 支持二次确认后覆盖同名文件、任务级 `.part` 临时文件清理与已完成记录清理；终端支持单行快捷命令历史与分屏指定标签；隧道支持多条并发保持；监控、Docker 和 Kubernetes 页面提供可视化进度条与资源名称快捷点选。

## 待完成

- macOS 14 实机窗口、中文输入、键盘交互、终端全屏工具、通知显示、暂停恢复并发和生产形态下资源管理页面验收。
- 正式发布仓库尚无 Developer ID 或公证 Secrets。安装包目前使用 ad-hoc 签名。Developer ID 签名、Apple 公证、Gatekeeper 和企业分发需要实际验收。
- 完整功能缺口见 [路线图](roadmap.md)。
