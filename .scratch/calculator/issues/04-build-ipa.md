# 04: Windows 到真机 IPA 交付

**What to build:** 用户推送私有仓库后手动触发 Build IPA，由标准 macOS runner 自动生成工程、测试、打包和检查 IPA，然后下载并在已有 TrollStore 上验收完整流程。

**Blocked by:** 01 / 个人授权与单 App 隐藏恢复；02 / 计算器与安全 PIN 入口；03 / 独立三态管理与恢复全部。

**Status:** ready-for-agent

- [ ] workflow_dispatch，无 Apple 密码或付费证书，产物保留 3 天。
- [ ] 检查 Payload、最低 iOS 16.0、arm64 真机架构、Mach-O 平台和签名内 entitlement。
- [ ] README 提供可复制 PowerShell 命令、下载和真机验收步骤。
- [ ] 编译、TrollStore 安装、个人授权分别记录，不以打包成功代替真机通过。

实施记录：工程描述、构建脚本、产物检查和文档已实现；等待首次 Actions 和用户真机反馈。
