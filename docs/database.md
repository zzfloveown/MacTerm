# 数据库

GRDB 迁移 initial 创建 ssh_hosts、transfer_tasks、app_settings。后续迁移创建 monitor_history、monitor_alert_rules、monitor_alert_events，使用时间和主机索引。服务器分组作为服务器配置字段兼容已有记录。传输记录保存任务状态、方向和端点。配置 JSON 备份包含服务器资料和界面字体，恢复时按新 UUID 合并。密码通过 Keychain 保存，私钥仅引用绝对路径。

后续仍需建立独立的主机组、指纹、密钥、会话、终端历史、SFTP 收藏、隧道、Docker Endpoint 和 Kubernetes Context 表。
