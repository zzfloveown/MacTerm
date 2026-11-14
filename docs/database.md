# 数据库

GRDB 迁移 initial 建立 ssh_hosts、transfer_tasks、app_settings。前两张表以 UUID 为主键并以 Codable JSON 存储实体。迁移按添加版本推进。密码通过 Keychain 保存，私钥仅引用绝对路径。

待补 ssh_host_groups、ssh_host_keys、ssh_identity_keys、ssh_sessions、terminal_profiles、terminal_history、sftp_bookmarks、ssh_tunnels、monitor_history、monitor_alert_rules、monitor_alert_events、docker_endpoints、k8s_contexts，并完善索引、关联、备份和恢复。
