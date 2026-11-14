# SSH 设计

终端用 SwiftTerm PTY 执行系统 ssh。交互路径由 OpenSSH 提示用户确认首次指纹、输入密码及处理 keyboard-interactive。后台任务采用 BatchMode 和严格主机指纹校验。OpenSSH 使用账户的 known_hosts。应用显式传递目标和端口，禁用任意外部 SSH 配置及 Agent 转发。ProxyJump 支持经过校验的逗号分隔跳点。后续补充受限 SSH Config 导入、应用内指纹记录与认证代理、连接共享和会话恢复。

转发使用 ssh -N 和 ExitOnForwardFailure。客户端指定回环监听，远端转发的最终绑定由服务端 GatewayPorts 策略控制。
