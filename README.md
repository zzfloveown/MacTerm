# MacTerm

SwiftUI 原生 macOS 服务器管理客户端，最低系统 macOS 14，目标 Apple Silicon。项目处于开发阶段。当前范围与验收记录见 [路线图](docs/roadmap.md) 和 [验收](docs/acceptance.md)。

## 试用构建

下载 [已通过云端验收的 ARM64 构建](https://github.com/zzfloveown/MacTerm/actions/runs/43623046200/artifacts/14125550194)，压缩包包含 MacTerm.dmg 和 MacTerm.app.zip。该构建用于测试，企业发行流程见 [部署](docs/deployment.md)。

添加服务器后可打开终端。首次连接需核对带外取得的主机指纹。SFTP、监控、隧道和容器操作目前要求已验证的主机及可用的非交互身份（私钥或可访问的 SSH Agent）。Kubernetes 页面使用用户指定的 kubectl 和受信任的 kubeconfig。

[架构](docs/architecture.md) · [测试](docs/testing.md) · [安全](docs/security.md)
