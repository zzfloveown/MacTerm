# 安全

- 交互 SSH 由 OpenSSH 管理首次信任和指纹变更校验。非交互请求要求既有信任。
- 私钥引用不含私钥内容。Keychain 凭据按服务器 ID 隔离。目前交互登录使用 OpenSSH 提示符，未读取 Keychain 来认证。
- 进程适配器直接传递 argv。远端命令参数逐一进行 POSIX shell 引用。SFTP 对命令语法敏感的路径字符采用拒绝策略。
- Kubernetes Secret 列表只显示名称与类型。使用受信任的 kubeconfig，kubectl 可能按该文件执行本地凭据插件。
- 公共源代码、Actions 日志和产物应排除企业地址与凭据。远端文件和容器删除要求确认。
- 后续审计覆盖依赖漏洞扫描、主机信任隔离、临时输出上限、SFTP 覆盖和权限、传输中断以及 Docker/Kubernetes 的授权边界。
