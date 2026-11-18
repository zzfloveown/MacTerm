# 数据库

GRDB 迁移 initial 创建 ssh_hosts、transfer_tasks、app_settings。后续迁移创建 monitor_history、monitor_alert_rules、monitor_alert_events、ssh_tunnels 和 terminal_commands。隧道配置按主机 ID 索引并保存转发模式、监听和目标端口及重连选择，不保存凭据或运行状态。终端快捷命令历史按主机 ID 保存经校验的单行命令（保留最近 100 条），不记录凭据或命令输出，并在移除服务器时一并级联清理。服务器分组作为服务器配置字段兼容已有记录。传输记录保存任务状态、方向、端点和可选覆盖标记（旧记录默认不覆盖），支持按任务清理记录。配置 JSON 备份包含服务器资料、隧道配置和界面字体，恢复时为服务器和隧道分配新 UUID 并重映射关联；数据库在单个事务中导入两类记录。旧版无隧道字段的备份按空配置导入。密码通过 Keychain 保存，私钥仅引用绝对路径。

后续仍需建立独立的主机组、指纹、密钥、会话、SFTP 收藏、Docker Endpoint 和 Kubernetes Context 表。

服务器 JSON payload 新增可选 authenticationMethod 字段（privateKey / password），随服务器配置和备份保存，不包含密码。字段缺失时解码为 nil 保留旧认证行为；无需改动表结构或已有迁移。
