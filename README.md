# 计算器

自用 Swift + SwiftUI iPhone App，最低 iOS 16.0。固定 Bundle ID：`com.personal.calculatorvault`。没有服务器、登录、统计、订阅或网络请求。

当前优先验证 iPhone 15 Pro / iOS 26.4.2。CI 使用 Xcode 26.4.1 和 iOS 26.4 模拟器。该设备上，SideStore 独立安装保留了基本 App 签名，但安装后没有 Family Controls 权限。iOS 26 的授权和限制真机验收需要 Apple 开发签名，且 App ID 与设备所用描述文件均须包含 Family Controls 能力。用当前 TrollStore 打包流程生成的 IPA 可以用于历史 TrollStore 测试。[Apple 支持的能力](https://developer.apple.com/help/account/reference/supported-capabilities-ios) · [真机诊断](docs/VALIDATION.md)

1.0.1：启动不再创建 Family Controls / ManagedSettings 对象，Keychain 查询在后台执行，并显式声明 SwiftUI 场景生命周期。计算部分复用 [Nick Lockwood Expression](https://github.com/nicklockwood/Expression)（MIT，固定源码版本并随包保留许可证）；本工具仅保留按键状态、PIN 入口和管理适配。旧版在 iPhone 13 Pro / iOS 16.3 已收到黑屏后退出的反馈；新版已通过 iOS 18.5 模拟器完整 UI 流程，iOS 16.3 真机仍需复验。

1.0.3 已在 iPhone 13 Pro / iOS 16.3 上安装运行，曾在重开 App 后弹出系统授权并成功。该设备上选「隐藏」后仍能看到小红书。管理页的「导出诊断日志」可将调用时间线保存为文本文件。

首次启动设置 4–12 位数字 PIN。之后按 **AC → PIN → =** 进入管理页；PIN 的前导零有效。普通加减乘除、连续运算、重复等号、小数、百分数和正负号可用（连续运算按输入顺序计算）。PIN 不作为常量写入项目，随机盐和 PIN 摘要仅存 Keychain，访问级别为本机解锁后可用，不同步。请记住 PIN，没有后门 PIN；卸载不保证删除 Keychain。

退出管理页或进入后台后恢复计算器。系统授权弹窗的临时 inactive 不会关闭管理页；任务切换预览遮挡内容。退出管理页不会撤销限制，**恢复全部并退出** 才会撤销。

管理页的「更改 PIN」要求输入当前 PIN。忘记时，在计算器长按 **AC → 重置 PIN（验证设备身份）**，通过面容 ID 或设备锁屏密码验证后即可设置新 PIN。重置 PIN 会保留管理列表和现有 App 限制。

1.1.2 / build 13 已通过 [Build IPA 42350060673](https://github.com/KBin-001/hide/actions/runs/42350060673)。下载该运行的 **Calculator-TrollStore** artifact，解压后用 TrollStore 覆盖安装。产物保留 3 天。

## 1.1.1：应用目录

“选择 App”提供 170 项本地目录，按 10 类展示，支持中文名称、别名（如 WeChat、Twitter、XHS）和 Bundle ID 搜索及多选，不需要为常用应用填写标识。QQ、微信、抖音、小红书、微博、B 站、X 及影音、购物、出行、办公等应用的完整对照和来源见 [应用目录](docs/APP-CATALOG.md)。没有独立的 App 快捷添加按钮；少见应用仍可在「诊断 → 手动添加（高级）」补充。

目录并非已安装检测；公开接口不能将系统匿名 token 转为 Bundle ID。目录添加用于标识隐藏路径，原系统选择器保留为「系统选择器（上锁）」。新添加项默认正常，隐藏仍需要系统授权。来源记录不保证其他版本/地区或改包应用的身份相同，也不代表 170 项的隐藏效果均通过真机验收。

1.1.1 / build 12 已通过完整 [Build IPA 42340039582](https://github.com/KBin-001/hide/actions/runs/42340039582)：25 项核心测试、模拟器搜索/多选保存及恢复流程、arm64 Release 编译、签名和 IPA 校验通过。下载该运行的 **Calculator-TrollStore** artifact，解压后使用 TrollStore 覆盖安装；不要先卸载。产物保留 3 天。新版仍需真机逐项确认其他 App 的隐藏与恢复效果。

## 授权与恢复

2026-11-07，用户在 iPhone 13 Pro / iOS 16.3 上确认：重启手机后，1.0.9 的 QQ Bundle ID 测试两轮隐藏、恢复成功，日志读回分别为 1 和 0。这个结果只确认 QQ 的标识路径，不代表其他 App、原系统选择器 token 路径或其他 iOS 版本均已验证。

- 从「选择 App」按名称多选添加，默认正常；可逐项隐藏、恢复正常或恢复并移除。批次校验和单次原子保存失败时不会留下半批记录。目录和请求状态本地保存，冷启动不会自动重施加限制。
- 「恢复全部并退出」清理目录与系统选择器两条路径，包括旧 QQ 测试存储；即使一处保存失败仍尝试另一处恢复。失败时保留页面以便重试。
- 「诊断 → 清空管理列表」先恢复本工具的限制，系统读回一致后再清除已选 App 和备注。此操作保留 PIN 与 iOS 屏幕使用时间历史。
- 系统选择器的上锁使用 token，目录的隐藏使用 Bundle ID。两处对同一 App 的限制可能叠加，需要都恢复正常。两入口的上锁、隐藏请求合计最多 50 项；不能自动判定 token 是否对应同一 Bundle ID，按两条记录保守计数。
- 本地保存请求、系统配置读回和实际图标/启动行为是不同证据。其他 App 的标识与效果仍需真机逐项确认。

授权按阶段独立计时，每阶段超过 30 秒显示慢响应提示；进度推进或最终成功会清除旧提示，并接纳迟到结果。一直无响应时，先导出日志并从 App 切换器彻底关闭计算器，再到「设置 → 屏幕使用时间 → 有屏幕使用时间访问权限的 App」仅关闭计算器的权限。重新打开计算器后进入管理页，点一次「连接系统授权」。撤销权限会解除计算器施加的限制，系统选择器中的 App 需要重选。iOS 没有公开接口强制重置授权服务。[Apple 的个人授权说明](https://developer.apple.com/videos/play/wwdc2022/110336/)

## Windows 推送

项目由 `project.yml` 完整描述；Actions 自动生成 Xcode 工程，无需本地 Mac、Xcode、Apple ID 密码或付费开发者证书。生成的 `.xcodeproj` 忽略提交。先在 GitHub 网页创建一个**空的私有仓库**，不要自动添加 README。把下面的仓库地址替换为你的地址：

```powershell
Set-Location 'C:\Users\27468\Documents\Calculator'
git init -b main
git add .
git commit -m "Create personal calculator and IPA workflow"
git remote add origin https://github.com/YOUR_NAME/YOUR_PRIVATE_REPO.git
git push -u origin main
```

以后更新：

```powershell
Set-Location 'C:\Users\27468\Documents\Calculator'
git add .
git commit -m "Update calculator"
git push
```

保持 Bundle ID、entitlement 中的标识与 Keychain group 不变，使用 TrollStore 覆盖安装；不要先卸载，以保留容器管理数据。私有仓库的标准 macOS runner 消耗你的 GitHub Actions 配额。

## 手动打包和安装

1. 仓库 → Actions → **Build IPA** → Run workflow → main → Run workflow。
2. 工作流先运行核心行为测试，再编译 `generic/platform=iOS` 的 arm64 Release，临时 ad-hoc 签名，包装 `Payload/Calculator.app`。
3. 成功后在运行详情底部下载 **Calculator-TrollStore** artifact（保留 **3 天**）。解压外层 artifact ZIP，里面才是 `Calculator.ipa`、`Calculator.ipa.sha256`、`verification.json`。
4. 将 IPA 传到手机的“文件”，共享到已安装的 TrollStore，选择 Install；后续版本选择覆盖。此 IPA 用于 TrollStore，不是普通签名侧载或 App Store 分发包。
5. 在桌面打开“计算器”，设置 PIN，按 AC → PIN → = 进入管理页。

可在 PowerShell 核对下载的 SHA-256：

```powershell
Get-FileHash -Algorithm SHA256 .\Calculator.ipa
Get-Content .\Calculator.ipa.sha256
```

只比较两者的散列值，文件路径显示可以不同。不要把 artifact ZIP 当成 IPA 安装。

## 先验收最小链路

1. 管理页点击「连接系统授权」，完成系统认证，确认「屏幕使用时间」显示「已授权」。如果显示「签名缺少权限」，当前已安装签名的 XML 权限里没有 Family Controls，须换用具备该权限的签名。其他失败可展开「诊断」，选择「导出诊断日志」。
2. “选择 App”打开系统 FamilyActivityPicker，展开分类，只勾选一个非关键第三方 App，保存。只管理单个 App token；分类和网站不会施加限制。
3. 先把这个 App 设为「正常」，再按「上锁 → 正常 → 隐藏 → 正常」验证。每一步都检查桌面、系统搜索和实际启动，分别记下是否出现系统限制页。[真机记录表](docs/VALIDATION.md)
4. 回到计算器 → AC → PIN → =，将它改成“正常”。如果旧条目只有编号，可以在「选择 App」里取消勾选要恢复的具体 App，再保存。确认图标回来且能打开，再切过去使用。再次后台/重开后不应重新隐藏。
5. 完成上述链路后再选第二个 App。A 隐藏、B 上锁；只将 A 改正常，确认 B 仍有图标、点击仍显示系统限制页。再切换隐藏 ↔ 上锁，确认没有遗留另一种限制。
6. 重开管理页确认所选 App 和请求状态保留；取消选择某 App 会撤销本工具对它的限制。最后点“恢复全部并退出”，所有 App 应恢复。
7. 错误 PIN 加等号应继续普通计算；进入管理页后退后台，再打开应是计算器。通过系统设置撤销屏幕使用时间权限后，管理页应反映未授权；重新授权不会自动重新施加保存的限制。

上锁使用 `shield.applications`。隐藏同时提交 `application.blockedApplications` 和 `shield.applications`，上锁与隐藏合计最多 50 个 App。1.0.7 优先写入本工具的默认 store，每项读回不匹配时才尝试旧命名 store。恢复清理两个 store 中由本工具使用的设置。日志记录每项配置的写入和读回数量；实际图标与限制页仍需真机检查。冷启动后手动连接系统授权，已记录的授权只用于提示。若等待超时，先导出日志，再从 App 切换器彻底关闭计算器，重开后手动连接。

“恢复全部”即使文件保存失败也先提交撤销请求，然后在管理页显示错误并禁止进一步状态编辑，直到重试保存成功。若忘记 PIN，优先到 iOS 设置 → 屏幕使用时间 → 具有屏幕使用时间访问权限的 App 中撤销本工具授权；不同版本文案可能不同。正常卸载/停用前先恢复全部。

## 三个独立验收点

| 验收点 | 当前交付状态 | 证据 |
|---|---|---|
| iPhone 编译与产物检查 | 1.1.2 已通过 | 26 项核心测试、模拟器改 PIN、目录搜索/保存及恢复流程、arm64 编译、IPA 与签名校验通过。[Build IPA 成功记录](https://github.com/KBin-001/hide/actions/runs/42350060673) |
| TrollStore 真机安装并运行 | 1.0.9 已确认，1.1.2 待覆盖安装验证 | 用户设备 iPhone 13 Pro / iOS 16.3 |
| 个人授权、隐藏、恢复、上锁 | 1.0.9 重启后授权成功，QQ 标识隐藏及恢复两轮成功；其他 App 和上锁仍待逐项验证 | 新目录沿用成功的标识路径。[验收记录](docs/VALIDATION.md) |

Actions 对**解压后的实际 IPA**检查：唯一 `Payload/*.app`、显示名和固定 ID、Info.plist 最低系统 16.0、iPhoneOS 平台/iPhone 设备族、arm64 架构、Mach-O iOS 平台及最低版本、codesign 完整性、签名内 Family Controls/Keychain entitlement 和无额外权限。检查失败不上传成功产物。验证报告仍把安装、授权、隐藏效果标为待真机验证。

TrollStore 会重新签名并保留 entitlement，但这不保证 Family Controls 服务接受个人授权。本项目不使用私有 API、平台化、无沙盒权限或清理使用记录的方式绕过授权失败。Apple 正常分发路径需要审批 Family Controls entitlement；本包是单独的 TrollStore 测试路径。iOS 的屏幕使用时间历史和系统授权入口始终保留，它们是否存在不是隐藏成功指标。

TrollStore 也不是支持所有 iOS 16 小版本；按其官方说明，支持至 16.6.1，另含 16.7 RC（20H18），不含正式 16.7.x。你已有的 TrollStore 是否可用仍需按具体系统确认。

## 开发与文档

- 核心对外行为测试：`swift test`（工作流自动执行）；覆盖 App 隔离、隐藏恢复、删除选择、持久化加载、限制数量、写入失败和计算器行为。新增 XCTest UI 流程通过云端模拟器打开实际 App，验证 PIN 设置、普通计算、管理入口和后台返回，并保存截图与 xcresult；模拟器不验收 Family Controls 授权或 TrollStore 行为。
- macOS 手动重现：`brew install xcodegen`，`python3 scripts/generate_icon.py`，`xcodegen generate`，`swift test`，`bash scripts/build_ipa.sh`。
- 原创图标由仓库内纯 Python 脚本绘制，PNG 与 asset catalog 已随项目提供；Actions 会重新生成，无外部图像依赖。
- 规格：`docs/SPEC.md`；本地逐票工单：`.scratch/calculator/issues/`；验收记录：`docs/VALIDATION.md`。尚未创建或发布远程 issue；以后需要配置 tracker 可运行 `/setup-matt-pocock-skills`。

参考：[Apple blockedApplications](https://developer.apple.com/documentation/managedsettings/applicationsettings/blockedapplications-swift.property)、[个人授权与命名 store](https://developer.apple.com/videos/play/wwdc2022/110336/)、[Family Controls entitlement](https://developer.apple.com/documentation/familycontrols/requesting-the-family-controls-entitlement)、[TrollStore 官方说明](https://github.com/opa334/TrollStore)、[XcodeGen](https://github.com/yonaskolb/XcodeGen)、[GitHub 标准 runner](https://docs.github.com/en/actions/reference/runners/github-hosted-runners)。
