# 部署

CI 在 macos-15 ARM64 Runner 上测试并生成 ad-hoc 签名的 MacTerm.app 和 MacTerm.dmg。打包脚本确认二进制架构，验证 app 签名和磁盘镜像。

正式标签使用 v主版本.次版本.补丁。发布工作流要求 GitHub Secrets MAC_CERTIFICATE（Base64 的 Developer ID Application p12）、MAC_CERTIFICATE_PASSWORD、MAC_SIGN_IDENTITY、APPLE_ID、APPLE_TEAM_ID、APPLE_APP_PASSWORD。通过 notarytool 公证后对 DMG staple 并校验。正式产物当前上传到 Actions；企业分发需要授权的内网 HTTPS 端点和访问控制。企业证书及凭据限 GitHub Secrets。正式发布资格和公证结果待验证。

[Apple Developer ID 文档](https://developer.apple.com/developer-id/)
