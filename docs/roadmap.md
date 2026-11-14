# 路线图

| 阶段 | 当前范围 | 后续验收与缺口 |
|---|---|---|
| P1 | SwiftPM、SwiftUI、GRDB、Keychain、服务器分组与配置备份 | 分离实体表，验证旧数据和多窗口配置一致性 |
| P2 | 多标签和分屏、SSH Config 导入、指纹查询、密钥生成、搜索、标签恢复 | 密码 Keychain 登录、终端自动重连、命令历史、macOS 14 真机交互测试 |
| P3 | 结构化列表、文件属性、拖拽、递归、文本编辑、持久化队列、校验续传 | 独立 SFTP 标签、覆盖选择、暂停实测、清理策略及 WAN 性能 |
| P4 | 共享采集、Linux 系统信息、进程管理、磁盘和网络统计、历史、CSV 和通知告警 | 专用长连接、CPU 分项、跨发行版及通知真机验收 |
| P5 | ProxyJump、三类转发、就绪检查、错误提示和重试 | 多跳、远端转发和 SOCKS5 的端到端验证，持久化隧道 |
| P6 | Docker/nerdctl 查询和操作、容器终端、kubectl 资源及 Pod 终端、Deployment 扩缩容 | 验证实际 nerdctl/containerd 与 Kubernetes 环境，补充操作测试 |
| P7 | ARM64 DMG、App ZIP、云端挂载启动和签名公证流程 | Developer ID 凭据、公证、macOS 14 终端和界面验收、受控内网 HTTPS 分发 |

下一轮优先完成真实 Kubernetes 与 nerdctl 集成验证，同时覆盖多跳转发和 GUI 交互。正式发布需要仓库签名公证 Secrets 和企业分发端点。
