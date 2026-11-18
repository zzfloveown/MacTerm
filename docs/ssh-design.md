# SSH 设计

终端用 SwiftTerm PTY 执行系统 ssh。首次连接由 OpenSSH 显示指纹并请求确认，后台任务启用严格指纹校验。应用使用账户的 known_hosts，可查看已保存指纹。受限 SSH Config 导入只读取显式 Host 和受支持字段。应用不执行 Include、Match 和 ProxyCommand，ProxyJump 接受校验后的多个跳点。

控制套接字按服务器 UUID 和连接参数隔离，已打开的交互连接可供后台任务复用。终端提供标签重开、手动重连、可选的异常断开后重连、副分屏目标选择、搜索以及按主机持久化的单行快捷命令历史（不记录凭据与输出，支持同步发往副分屏）。重开使用新的 SSH 连接。持久的远端 shell 可由用户用 tmux 保持。主机默认手动认证；用户可为单个主机开启 Keychain 密码提交。一次性令牌只包含主机 UUID，密码经 SSHAskPass 标准输出管道提交。首次主机密钥确认、私钥口令和交互挑战由助手显示原生安全输入对话框。应用仍使用 OpenSSH 用户 known_hosts 信任库，独立信任库尚未实现。

转发使用独立 OpenSSH ControlMaster 和 ExitOnForwardFailure，确认控制套接字后显示已建立。支持多条隧道并行运行、回环 Local、Remote、Dynamic 转发及可选自动重试，切换主机或页面不会中断运行中的隧道。远端转发绑定最终受服务器 GatewayPorts 策略控制。
