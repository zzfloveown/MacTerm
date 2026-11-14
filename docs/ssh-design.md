# SSH 设计

终端用 SwiftTerm PTY 执行系统 ssh。首次连接由 OpenSSH 显示指纹并请求确认，后台任务启用严格指纹校验。应用使用账户的 known_hosts，可查看已保存指纹。受限 SSH Config 导入只读取显式 Host 和受支持字段。应用不执行 Include、Match 和 ProxyCommand，ProxyJump 接受校验后的多个跳点。

控制套接字按服务器 UUID 和连接参数隔离，已打开的交互连接可供后台任务复用。终端提供标签重开、手动重连、可选的异常断开后重连和搜索。重开使用新的 SSH 连接。持久的远端 shell 可由用户用 tmux 保持。密码从 Keychain 认证及应用独立信任库仍需实现。

转发使用独立 OpenSSH ControlMaster 和 ExitOnForwardFailure，确认控制套接字后显示已建立。支持回环 Local、Remote、Dynamic 转发及可选自动重试。远端转发绑定最终受服务器 GatewayPorts 策略控制。
