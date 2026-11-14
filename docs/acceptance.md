# 验收记录

- 公开仓库创建、推送和私钥材料扫描通过。[运行 43619463016](https://github.com/zzfloveown/MacTerm/actions/runs/43619463016)
- ARM64 Runner 架构检查、SwiftPM 编译及四项单元测试通过。Release 二进制已成功链接，签名检查通过。首次打包在 hdiutil 参数处失败。已将参数更正为 -ov，等待重跑结果。[运行 43619353940](https://github.com/zzfloveown/MacTerm/actions/runs/43619353940)
- SSH/SFTP 首轮集成测试未完成认证。已更新临时 sshd 配置并加入独立连通性检查，等待重跑结果。[运行 43619462957](https://github.com/zzfloveown/MacTerm/actions/runs/43619462957)
- 待验收的产品功能见路线图。Linux 交互终端、SFTP、监控、转发、Docker、Kubernetes、macOS 14 图形界面和企业公证需分别记录实际运行结果。
