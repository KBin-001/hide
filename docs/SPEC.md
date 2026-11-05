# 计算器规格

## Problem Statement

用户使用 Windows、没有本地 Mac，希望实际获得可由 GitHub Actions 编译、经已有 TrollStore 安装的自用 iPhone 工具。日常入口应为正常计算器，管理入口受 PIN 保护，并通过系统授权对自己选择的 App 独立限制使用或隐藏图标。

## Solution

提供 SwiftUI iOS 16.0 项目、固定应用标识、Keychain PIN、系统 App 选择器、三态管理和恢复出口。先用同一控制器验证授权→单 App 隐藏→恢复，再扩展为计算器入口与逐 App 上锁。构建、安装、系统授权分别验收。

## User Stories

1. As an 自用用户, I want a 中文计算器显示名称, so that 日常从桌面打开方便。
2. As an 自用用户, I want a 原创计算器图标, so that 入口容易识别。
3. As an 首次使用者, I want a 设置并确认数字 PIN 的流程, so that 管理入口由自己控制。
4. As an 自用用户, I want a 正常加减乘除计算器, so that 不进入管理时也能使用。
5. As an 自用用户, I want a AC 后输入 PIN 再按等号的入口, so that 可以主动进入管理。
6. As an 自用用户, I want a 保留前导零的 PIN 输入, so that 设置的 PIN 能准确匹配。
7. As an 自用用户, I want a Keychain 安全存储, so that PIN 不出现在源码、普通配置与日志。
8. As an 自用用户, I want a 退出或后台后回到计算器的流程, so that 再次打开需要重新进入管理。
9. As an 自用用户, I want a 系统个人授权按钮, so that 自己决定屏幕使用时间访问权限。
10. As an 测试者, I want a 可复制的授权错误详情, so that 能反馈具体失败原因。
11. As an 自用用户, I want a 系统 App 选择器, so that 选择自己的第三方 App。
12. As an 测试者, I want a 单 App 隐藏和恢复链路, so that 最先确认系统能力。
13. As an 自用用户, I want a 逐 App 正常状态, so that 解除本工具对指定 App 的限制。
14. As an 自用用户, I want a 逐 App 上锁状态, so that 保留图标并由系统限制页阻止使用。
15. As an 自用用户, I want a 逐 App 隐藏状态, so that 系统隐藏图标并阻止启动。
16. As an 自用用户, I want a 切换单个 App 不影响其他 App 的行为, so that 可以独立管理。
17. As an 自用用户, I want a 保存选择与状态的能力, so that 重开后继续管理。
18. As an 自用用户, I want a 恢复后不会在后台重隐的行为, so that 能切去使用恢复的 App。
19. As an 自用用户, I want a 取消选择时恢复的行为, so that 不遗留无法管理的限制。
20. As an 自用用户, I want a 恢复全部并退出的入口, so that 可以安全停用工具。
21. As an 自用用户, I want a 系统设置中的授权撤销入口, so that 忘记 PIN 也能撤销访问。
22. As an Windows 开发者, I want a 自动生成 Xcode 项目的工作流, so that 不需要先打开 Xcode。
23. As an Windows 开发者, I want a 无 Apple 凭据的 IPA 构建, so that 可以手动运行标准 macOS runner。
24. As an 测试者, I want a 检查实际 IPA 内容和签名的报告, so that 确认打包没有丢失权限。
25. As an 自用用户, I want a 保留三天的构建产物, so that 能下载并在真机安装。
26. As an 测试者, I want a 区分编译、安装和授权的验收记录, so that 不误认为打包成功就能控制 App。

## Implementation Decisions

- Swift + SwiftUI，最低 iOS 16.0，固定 Bundle ID 和 Keychain group；无扩展、远程服务或网络依赖。
- 个人授权使用 Family Controls；App 选择只消费 application tokens，不处理分类或网站限制。
- 单一策略控制器负责完整状态快照、持久化和限制集合；系统适配器写入本工具命名 ManagedSettings store。
- 上锁集合写 shield，隐藏集合将 token 转为 Application 后写 blockedApplications；正常/取消选择撤销本工具对应限制。
- 每次修改保留其他 App 的请求状态；过渡先去除不再需要的限制再增加新限制。
- 普通提交先保存再写系统；恢复全部优先释放限制，即使写盘失败也阻止后续编辑并提示重试。
- 启动与生命周期刷新不重施加限制；持久化的是请求状态，系统实际效果需要真机验收。
- PIN 随机加盐摘要仅存本机 Keychain；读取失败不当成首次安装，不覆盖现有安全设置。
- Actions 生成工程、运行核心测试、真机 arm64 构建、ad-hoc 签名、包装 IPA、解包校验后上传三天。

## Testing Decisions

- 用户已确认四个切片、依赖与测试边界。
- 以策略控制器对外行为为主要测试边界，用测试 token 和持久化/系统适配器替身观察集合变化；不验证私有内部调用顺序。
- 覆盖单 App 隐藏恢复、状态独立、取消选择、持久化重载无自动施加、文件损坏、保存失败、安全恢复及每类 50 个限制。
- 计算器测四则运算、小数、重复等号、除零恢复和 PIN 原始数字序列。
- IPA 校验真实二进制及签名，不能只检查源 entitlement 文件。
- 本项目从空目录创建，无已有测试先例。Keychain、系统授权、图标隐藏、shield 与生命周期由真机人工验收；核心测试和编译由 macOS CI 执行。

## Out of Scope

服务器、账户、登录、统计、订阅、清理屏幕使用时间历史、隐藏系统授权入口、私有 API、越权枚举 App、无沙盒权限、证书分发、自动重新限制、App Store 发布及保证任意 iOS 小版本均兼容 TrollStore。

## Further Notes

尚未配置远程 tracker，用户要求先本地完成、由用户创建仓库，因此规格与逐票文档本地交付。未来要发布 tracker 可运行 `/setup-matt-pocock-skills`。安装与授权必须等待用户真机反馈，不能用编译或 entitlement 存在替代。
