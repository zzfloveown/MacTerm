# 监控设计

通过 SSH 执行只读 Linux 采集，当前读取 /proc/stat、/proc/meminfo、/proc/net/dev、/proc/loadavg 和 df -PT。CPU 忽略重复计入的 guest，使用前八项的采样差值。网络速率使用字节计数差值和间隔。内存按总量减 MemAvailable 算使用量。进程使用 ps 只读刷新。

当前页面每次采样建立 SSH 命令进程，保存最多 300 个内存曲线点。后续建立每主机共享、可取消的采集任务、单调时钟、长连接、磁盘 I/O、温度、磁盘上的保留和清理策略及 CSV 导出。
