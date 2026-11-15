# 数据库

GRDB 迁移 initial 创建 ssh_hosts、transfer_tasks、app_settings。后续迁移创建 monitor_history、monitor_alert_rules、monitor_alert_events 和 ssh_tunnels。隧道配置按主机 ID 索引并保存转发模式、监听和目标端口及重连选择，不保存凭据或运行状态。服务器分组作为服务器配置字段兼容已有记录。传输记录保存任务状态、方向和端点。配置 JSON 备份包含服务器资料、隧道配置和界面字体，恢复时为服务器和隧道分配新 UUID 并重映射关联。旧版无隧道字段的备份按空配置导入。密码通过 Keychain 保存，私钥仅引用绝对路径。

后续仍需建立独立的主机组、指纹、密钥、会话、终端历史、SFTP 收藏、隧道、Docker Endpoint 和 Kubernetes Context 表。
