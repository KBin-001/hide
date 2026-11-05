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

## 真机授权阻塞与 1.0.2

用户已确认 1.0.1 可以进入计算器和 App 管理页；点击个人授权后完全没有系统确认框或 Face ID，一直显示正在请求。授权尚未通过，隐藏、恢复、上锁仍无法验收。

用户提供的 .ips 记录了 scene-create watchdog，启动墙钟等待 19.96 秒。报告中的 App Mach-O UUID 与已交付 1.0.1 不同，因此不能将这份旧二进制启动记录当成本次授权阻塞的堆栈。未将原始 .ips 或设备标识提交到仓库。

1.0.2（build 3）增加三阶段进度、30 秒等待上限和未完成请求去重。超时不能取消系统内部授权，也不能替代真正授权；迟到结果仍会更新。超时提示不会伪造 NSError 或把状态设为已批准。增加真实控制边界的模拟阻塞测试：请求不返回时能超时，未完成期间拒绝叠加，迟到结果和真实 NSError 被保留。

[1.0.2 成功运行 42029011624](https://github.com/KBin-001/hide/actions/runs/42029011624)，源码提交 5e1ad7d：7 项核心测试、1 项完整启动 UI 流程、arm64 真机编译与全部 IPA 检查通过。已下载实际 IPA 并核对版本 1.0.2 / build 3 与 SHA-256。真机授权仍未通过，需用户覆盖安装后反馈 30 秒超时显示的阶段。

## 编译耗时样本

依据下列 1.0.1 成功运行的 Actions 时间戳：真机 xcodebuild 约 49 秒；含签名、打包、IPA 校验的步骤约 54 秒；从 checkout 到产物上传约 447 秒（7 分 27 秒）。其中模拟器准备、构建与 UI 验证步骤约 337 秒，UI 用例本身约 31 秒。排队时间另计，这些是实测样本而非固定时长保证。

1.0.2 本轮：真机编译约 57 秒；含签名打包校验约 70 秒；checkout 至产物上传约 608 秒（10 分 8 秒），其中模拟器准备与 UI 测试约 478 秒。两轮差异主要来自云端模拟器与运行环境，不能把全部 CI 时间都算作 Swift 编译时间。

## 1.0.1 历史验证

[成功运行 42010959309](https://github.com/KBin-001/hide/actions/runs/42010959309)，源码提交 80ca22d，1.0.1 build 2。

- 5 项核心测试通过，0 failures。
- iPhone 16 Pro / iOS 18.5 模拟器，使用真实 Keychain 与 ad-hoc 签名，无 PIN 绕过或存储替身。UI 测试 31.274 秒、0 failures：首次启动显示设置页 → 保存随机测试 PIN → 7+3=10 → 输入 PIN 进入管理页 → Home → 回到计算器。
- 已查看测试导出的 PNG：显示完整计算器与结果 0。Launch-Test-Evidence artifact 保留截图和 xcresult。
- 真机 arm64 Release 编译及所有 IPA 检查通过，Family Controls entitlement 保留。
- Calculator-TrollStore artifact 已上传，保留至 2026-11-08 18:35（北京时间）。
- iPhone 13 Pro / iOS 16.3 的重新覆盖安装与启动、系统个人授权、真实 App 隐藏/恢复仍待用户反馈。模拟器未测试这些系统权限能力。

## 1.0.0 历史编译记录（不表示启动成功）

- [成功运行 42002897182](https://github.com/KBin-001/hide/actions/runs/42002897182)，源代码提交 8ef48f7；macos-15-arm64、Xcode 16.4、Swift 6.1.2、iPhoneOS SDK 18.5。
- XcodeGen 生成工程与 Xcode arm64 真机 Release 编译通过。
- swift test 的五组外部行为测试全部通过，0 failures。
- ad-hoc 签名、IPA 包装、实际 Payload 内容与签名完整性检查通过。
- 实际 Info.plist 最低系统版本 16.0、设备族仅 iPhone、Mach-O arm64 架构/iOS 平台/最低版本检查通过。
- codesign 从实际签名提取 Family Controls 和 Keychain entitlement 检查通过，无额外权限。
- Artifact Calculator-TrollStore 上传成功；保留至 2026-11-08 17:32（北京时间）。用户下载后的 SHA-256 比对待完成。

首次运行 42001910481 的五项测试与编译同样通过，但 IPA 设备族校验失败。根因是 XcodeGen 目标级 iOS 默认设备族覆盖了项目级 TARGETED_DEVICE_FAMILY。现已将仅 iPhone 设置移到目标级；保留原有严格 IPA 校验，新运行完整通过。没有删去校验绕过错误。

## 真机失败反馈与修复候选

用户反馈：iPhone 13 Pro，iOS 16.3，TrollStore 安装后能打开，但黑底显示中央 +/−，约 15 秒后退出。由此仅确认安装完成、启动失败，旧版不满足真机验收。未获取系统 .ips 崩溃报告，不能确定退出是否为 watchdog。

1.0.1（build 2）候选改动：移除启动和前台回调中的同步 Family Controls 查询；管理服务延迟至 PIN 解锁且由授权按钮显式连接；Keychain 初次查询移至后台；Info.plist 显式声明 SwiftUI 场景生命周期；计算求值复用固定版本 MIT Expression。增加实际模拟器 UI 启动测试，禁止只凭 swift test 和 IPA 校验判断可启动。

首次旧代码模拟器诊断运行因云端模拟器及 Xcode 启动耗时被取消，未执行到 App 断言；这不构成重现真机黑屏的证据。后续候选在模拟器显示 Keychain -34018 错误：测试脚本关闭了签名，现改为 ad-hoc 签名保留 Keychain entitlement；另一次 Intel runner 在模拟器初始化/构建超时，未执行 App 断言。最终使用标准 macos-15、与 Xcode SDK 匹配的 iOS 18.5 运行时，完整流程通过。额外诊断任务已停止，交付的是完整 Build IPA 工作流通过的产物。

## 等待用户真机反馈

- TrollStore 安装已由用户确认；1.0.1 的真机启动待再次验证（设备 iPhone 13 Pro / iOS 16.3）。
- Keychain 首次设置、覆盖更新后的 PIN 保留、错误读取时的提示。
- Family Controls 个人授权是否成功；失败时复制管理页诊断。
- 单第三方 App 隐藏→桌面图标消失/阻止启动→正常→图标恢复/可启动。
- A 隐藏、B 上锁时的隔离；隐藏与上锁互转无残留。
- 取消选择/恢复全部仅释放本工具限制，其他工具的限制仍由原工具控制。
- 后台与重开回到计算器，恢复的 App 不重隐，系统认证弹窗不关闭管理。
- 系统历史和授权入口保持存在；它们不作为图标隐藏验收指标。

测试者应先完成单 App 隐藏恢复，再扩大选择范围。反馈无需包含 PIN、应用 token 或私人 App 列表。
