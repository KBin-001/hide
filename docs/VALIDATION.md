# 验收记录

记录日期：2026-11-05（Asia/Shanghai）。本地环境：Windows，没有 Xcode、iOS SDK 或 Swift 编译器。已推送 GitHub 仓库并完成真实 macOS 构建，IPA 已上传。

## 已在本地执行

- project.yml 与 Build IPA workflow 经 YAML 解析器校验，无重复 key；检查固定 Bundle ID、iOS 16.0、源码目录存在、workflow_dispatch、标准 macos-15 和 3 天保留期。
- Info.plist 和 entitlement 经 plist 解析；显示名、Family Controls 布尔值、Keychain group 与签名标识一致，只有声明的五项 entitlement。
- 原创图标生成脚本运行成功；检查全部九个 asset 声明的 PNG 尺寸、RGB 无透明通道，并查看 1024px 图标。
- Python 图标/IPA 验证脚本通过 py_compile。
- 打包脚本通过 Git Bash 的 bash -n 语法检查。
- 人工检查源码：无 PIN 常量、PIN 日志、网络请求、后台策略重施加；恢复使用专属命名 store。

这些本地检查不等于 Swift 编译或系统能力验收；远程编译与测试证据如下。

## GitHub Actions 已通过

- [成功运行 42002897182](https://github.com/KBin-001/hide/actions/runs/42002897182)，源代码提交 8ef48f7；macos-15-arm64、Xcode 16.4、Swift 6.1.2、iPhoneOS SDK 18.5。
- XcodeGen 生成工程与 Xcode arm64 真机 Release 编译通过。
- swift test 的五组外部行为测试全部通过，0 failures。
- ad-hoc 签名、IPA 包装、实际 Payload 内容与签名完整性检查通过。
- 实际 Info.plist 最低系统版本 16.0、设备族仅 iPhone、Mach-O arm64 架构/iOS 平台/最低版本检查通过。
- codesign 从实际签名提取 Family Controls 和 Keychain entitlement 检查通过，无额外权限。
- Artifact Calculator-TrollStore 上传成功；保留至 2026-11-08 17:32（北京时间）。用户下载后的 SHA-256 比对待完成。

首次运行 42001910481 的五项测试与编译同样通过，但 IPA 设备族校验失败。根因是 XcodeGen 目标级 iOS 默认设备族覆盖了项目级 TARGETED_DEVICE_FAMILY。现已将仅 iPhone 设置移到目标级；保留原有严格 IPA 校验，新运行完整通过。没有删去校验绕过错误。

## 等待用户真机反馈

- TrollStore 安装和启动（具体设备、iOS 完整版本、TrollStore 版本）。
- Keychain 首次设置、覆盖更新后的 PIN 保留、错误读取时的提示。
- Family Controls 个人授权是否成功；失败时复制管理页诊断。
- 单第三方 App 隐藏→桌面图标消失/阻止启动→正常→图标恢复/可启动。
- A 隐藏、B 上锁时的隔离；隐藏与上锁互转无残留。
- 取消选择/恢复全部仅释放本工具限制，其他工具的限制仍由原工具控制。
- 后台与重开回到计算器，恢复的 App 不重隐，系统认证弹窗不关闭管理。
- 系统历史和授权入口保持存在；它们不作为图标隐藏验收指标。

测试者应先完成单 App 隐藏恢复，再扩大选择范围。反馈无需包含 PIN、应用 token 或私人 App 列表。
