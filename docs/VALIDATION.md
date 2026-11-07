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

用户随后提供 1.0.2 真机截图：30 秒超时停在“初始化系统授权中心”，状态始终未读取，没有系统授权弹窗。该进度对应 AuthorizationCenter.shared 尚未返回，尚未进入 requestAuthorization(for: .individual)。因此不能把延长授权等待、反复点击或放开选择器当作修复。公开资料尚未给出足以证明本设备根因的依据；需要初始化时刻的设备实时日志，区分系统服务等待、签名/应用身份及其他初始化问题。Windows 侧尚未检测到 USB iPhone，已询问用户是否可连接并信任电脑。下一步使用独立的开源 pymobiledevice3 工具抓取相关日志；工具不进入 App 或 IPA。

## 1.0.3 真机日志

2026-11-06，iPhone 13 Pro / iOS 16.3（20D47）。1.0.3 build 4 成功进入管理页并导出文本。安装后二进制的签名 XML 中 `family_controls=true`，存在 DER 槽位，应用身份为 `TROLLTROLL.com.personal.calculatorvault`，包内无 `embedded.mobileprovision`。

手机处于前台且受保护数据可用。点击授权后工作线程立即写入 `center.shared.begin`，约 32 秒后主线程记录超时，随后仍能操作导出。日志缺少 `center.shared.end` 和 `request.individual.begin`，当前证据定位到共享实例的访问。具体阻塞原因待确认，包括设备端服务状态与安装身份的影响。下一项对照是在同一台设备上用 App Store 安装、支持 iOS 16 的屏幕使用时间应用触发个人授权，观察是否出现系统弹窗或可进入 App 选择器。[Apple AuthorizationCenter 文档](https://developer.apple.com/documentation/familycontrols/authorizationcenter) · [Jomo 兼容性](https://apps.apple.com/cn/app/jomo-screen-time-blocker/id1609960918)

## 1.0.4 退出看门狗与恢复候选

2026-11-06 15:28:16（北京时间），iPhone 13 Pro / iOS 16.3（20D47）。报告是 `process-exit` 看门狗，系统等了 5 秒。报告中的 Calculator Mach-O UUID 与实际 1.0.4 IPA 匹配。采样时主线程等待 Mach 消息，SwiftUI AsyncRenderer 正等主线程持有的互斥锁。应用自身栈帧仅匹配到 `_main`，其余相关偏移在同一系统共享缓存中。没有该系统构建的符号，无法把等待归到某个具体 API，也无法从这份退出报告确定卡顿最先发生在哪个页面。

候选改动移除管理列表每行的系统 token 标签，使用本地备注和系统图标占位。后台串行加载与提交，首次选择正常 App 只写本地。记录 `policy.store.begin`、`policy.shield.begin/end`、`policy.blocked.begin/end`，可区分等待发生在哪个边界。写入返回只表示调用结束，仍需观察桌面、搜索和启动结果。

同一设备复现时，若卡住，记录发生在 PIN 前还是进入管理页后；能操作时导出「诊断」中的日志。若独立上锁有效而隐藏仍失败，再对比 Apple 公共 API 的 token 和已独立核实的 Bundle ID 两种初始化方式。[Apple 看门狗排查](https://developer.apple.com/documentation/xcode/addressing-watchdog-terminations) · [恢复规格](SCREEN-TIME-RECOVERY-SPEC.md)

## 1.0.5 真机记录表

[Build IPA 42190327170](https://github.com/KBin-001/hide/actions/runs/42190327170) 验证源码 `b131268`。12 项核心测试和 1 项模拟器 UI 测试通过。核心测试覆盖旧记录读取、备注和中断恢复。UI 测试从空记录启动，覆盖前后台和冷启动重进、模拟限制请求超时、退出后迟到结果与再次恢复。等待中确认导出按钮可用。真机实际导出、旧记录页面重进、隐藏、上锁、恢复和长列表滚动仍待复验。

已下载 1.0.5 / build 6 IPA，复核 SHA-256、arm64、最低 iOS 16.0 以及云端签名报告。IPA 与 dSYM 的 Mach-O UUID 均为 `6D1FAB7B-6F26-3159-9B77-D457C3A112D8`。[IPA artifact](https://github.com/KBin-001/hide/actions/runs/42190327170/artifacts/13489906408) · [dSYM artifact](https://github.com/KBin-001/hide/actions/runs/42190327170/artifacts/13489781709)

用 TrollStore 覆盖安装 1.0.5（build 6）。进入管理页后，从同一条记录逐项操作。等待「正在提交」结束再切到桌面。每项实际点开一次目标 App。系统搜索仍显示图标时，分别记录点击搜索结果的行为和点击桌面图标的行为。

| 请求状态 | 桌面可见 | 搜索可见 | 实际打开或系统限制页 | 重进管理页 |
| --- | --- | --- | --- | --- |
| 正常（基线） | 待测 | 待测 | 待测 | 待测 |
| 上锁 | 待测 | 待测 | 待测 | 待测 |
| 正常（解除上锁） | 待测 | 待测 | 待测 | 待测 |
| 隐藏 | 待测 | 待测 | 待测 | 待测 |
| 正常（解除隐藏） | 待测 | 待测 | 待测 | 待测 |

- 冷启动复验时，退出到桌面，从 App 切换器关闭计算器，再重新打开。记录能否输入 PIN、进入管理页、查看授权并恢复。授权后若找不到限制效果，在「诊断」展开并导出日志，同时保留上表观察结果。
- 若再次有 `.ips`，保留同一构建的 IPA 和 `Calculator-Debug-Symbols` artifact。打包时校验了 dSYM 和 App Mach-O 的 UUID，系统共享缓存帧还需对应 iOS 构建的符号。
- 滚动对照使用同一台 iPhone、同一组至少 15 条记录，并固定 iOS 字体和减少动态效果设置。管理页加载后，从列表顶部连续滑到底部再返回，重复三次，记录可感知停顿。再操作一次条目菜单、退出和导出。VoiceOver 检查一条备注名及其模式能否读出。设备可连接 Instruments 时，用 SwiftUI 和 Hangs 对比相同手势的记录。

## 1.0.5 真机反馈与手动连接对照

2026-11-06，iPhone 13 Pro / iOS 16.3。1.0.5 能进管理页，读到一条旧记录，恢复全部调用约 20 毫秒返回，随后可再次进管理页并导出日志。冷启动自动确认卡在 `center.shared.begin`，后续未出现 `center.shared.end` 或 `request.individual.begin`；同进程前后台切换也未解除等待。该记录无法确认本次授权状态。

同份导出包含 1.0.4 的历史手动请求。该次 `shared` 约 4 毫秒返回，系统随后返回 `Approved`；提交一项 shield 和一项 blocked 后，立即读回为 0 / 0。这是独立于授权等待的限制生效问题。立即读回无法证明系统最终处理结果，但与当次可见且能启动的真机反馈一致。

1.0.6 仅改变首次连接的触发与提示。冷启动后由前台点按触发，已保存授权仅提示此前状态。框架调用、签名和策略保持相同，便于对照。若手动连接仍停在共享实例初始化，优先收集系统服务证据，不把延长等待或模拟授权当成修复。[Apple 授权接口](https://developer.apple.com/documentation/familycontrols/authorizationcenter/requestauthorization%28for%3A%29)

## 1.0.6 真机反馈与限制存储对照

2026-11-06，iPhone 13 Pro / iOS 16.3。1.0.6 两个进程均返回 `Approved`，其中首次弹出系统授权。已选择一条 App 记录。隐藏提交 `shield=1 blocked=1`，上锁提交 `shield=1 blocked=0`，两次均从系统 setter 返回。用户确认 QQ 仍未隐藏、仍可打开。1.0.6 未读取系统存储，因此不能把 `error=false` 当成策略生效回执。

1.0.7 优先向应用自己的默认存储提交同一条设置，读回不匹配时对照旧命名存储，并只在确认迁移后清除另一处的同类设置。正常和恢复操作清理两处，命名和默认写入均在原独立队列中。日志分别显示 `kind=shield/blocked` 与 `store=defaultStore/legacy`，仅记录数量及匹配结果。真机先测 QQ 上锁，恢复正常后再测隐藏。若两个存储都读回为空，下一步应收集 iOS 系统服务日志或同设备使用 Apple 正常签名应用作对照。若仅隐藏失败，再单独对比已核实 Bundle ID 和 token 两种初始化方式。[Apple 存储名称说明](https://developer.apple.com/documentation/managedsettings/managedsettingsstore/name)

1.0.7 首次真机日志于 2026-11-06 18:06–18:07（北京时间）导出。安装后签名仍报告 Family Controls entitlement，管理记录读取成功且有 0 项。手动连接到 `center.shared.begin` 后约 32 秒超时，导出时仍没有 `center.shared.end` 或 `request.individual.begin`。此次没有限制写入，默认与旧命名存储对照尚未运行。与 1.0.6 成功会话相比，授权实现和签名配置相同，现有日志不足以解释间歇差异。下一次使用同一 IPA，完全关闭进程后重试一次；若仍卡住，优先收集同机对照或复现时间段的系统日志。

同机对照已完成授权弹窗这一步。用户彻底关闭并重开计算器后，1.0.7 仍卡在授权；App Store 安装的 Jomo 进入相应页面即可弹出授权。该对照表明设备能为另一应用呈现授权，缩小范围至计算器的调用、应用身份或安装环境。Jomo 实际上锁效果和 TrollStore 路径的失败原因仍待验证。下一步采集一次授权复现期间的设备系统日志，核对 Screen Time 服务有无连接或授权拒绝记录。

## 另一台设备的 LiveContainer 对照

2026-11-06，北京时间。经 Windows USB 直接读取，设备为 iPhone 15 Pro（iPhone16,1）、iOS 26.4.2（23E261），已配对且启用开发者模式。手机安装记录显示 LiveContainer 3.8.0 为用户应用。系统返回的宿主权限没有 `com.apple.developer.family-controls`，计算器没有独立注册。LiveContainer 官方说明其宿主不会采用容器内 App 的权限。[LiveContainer 的权限限制](https://github.com/LiveContainer/LiveContainer#limitations)

从当前画面和计算器 1.0.7 自有诊断日志确认，`AuthorizationCenter.shared` 约 2 毫秒返回，随后的 `requestAuthorization(for: .individual)` 约 4 毫秒返回 `NSCocoaErrorDomain 4099`。20:07 用户再次点按，直接读取到新请求同样返回 4099。这是 LiveContainer 宿主环境下的系统连接失败；该环境缺少验证 Family Controls 所需的权限。iOS 16.3 上的 TrollStore 记录是共享实例初始化超时，两者不能合并为同一次故障。界面读取与报错展示已在此设备验证。隐藏、上锁和实际授权仍以原设备的独立安装为验收路径。[TrollStore 支持范围](https://github.com/opa334/TrollStore#compatibility)

## iOS 26.4.2 上的 SideStore 独立安装

2026-11-06 20:20（北京时间），同一台 iPhone 15 Pro。通过 Windows USB 查询到独立注册的计算器 1.0.7。安装后 Bundle ID 被加上团队后缀。系统安装记录返回的权限字典中没有 `com.apple.developer.family-controls`，从计算器容器直接读取的诊断也显示 `provisioning_file=true`、`xml_entitlements=read`、`der_slot=true`、`family_controls=missing`。多次请求均完成授权中心初始化，并在调用个人授权后约 1 毫秒收到 `NSCocoaErrorDomain 4099`。

1.0.8 根据安装后的签名做预检，确认缺少 Family Controls 时先显示具体原因。签名读取结果不明确时交由 iOS 判断。CI 改用 iOS 26.4 模拟器，工程保留 iOS 16.0 的部署下限。授权、上锁和隐藏仍需在 iPhone 15 Pro 上使用包含 Family Controls 的 Apple 开发签名逐项验证。Apple 的能力表仅在 Apple Developer Program 栏为 Family Controls 开发能力标注支持。[Apple 支持的能力](https://developer.apple.com/help/account/reference/supported-capabilities-ios)

## iOS 16.3 的限制写入失败已在系统日志确认

2026-11-07 北京时间 00:22:03 采集的系统诊断与 1.0.7 App 日志对齐。00:21:30 个人授权返回 `Approved`，00:21:35 从空列表新选一个 App，随后分别提交隐藏、上锁和隐藏。00:21:48 的上锁只提交一个 `shield.applications` token。默认和旧命名 store 都读回 0，00:21:38 和 00:21:50 的隐藏也在两处分别读回 0。

每次非空写入，系统的 `ManagedSettingsAgent` 都记录 `Failed to detokenize … authenticationFailure`，计算器进程对应记录 `CryptoKit.CryptoKitError Code=3`。失败发生在系统验证选择器提供的 token 时，复现使用的是本次授权后刚选的新 token。日志还显示 ManagedSettings 查找 `TROLLTROLL` 身份的既有记录未找到，但该行不能证明密码学失败的根因。两个 store 的表现一致。系统归档和过滤结果仅在本地忽略目录保留。

同机已确认 Jomo 能弹出授权，实际用它上锁同一个 QQ 仍可作为签名与安装路径的对照。若继续做代码实验，公开的 `Application(bundleIdentifier:)` 可以单独对照 `blockedApplications` 的隐藏路径。`shield.applications` 仍需要 `ApplicationToken`，应独立追踪。[Apple 应用标识初始化器](https://developer.apple.com/documentation/managedsettings/application/init%28bundleidentifier%3A%29) · [Apple ShieldSettings](https://developer.apple.com/documentation/managedsettings/shieldsettings)

1.0.9 加入单目标对照。在原 iPhone 13 Pro 上先把原 QQ 条目切到「正常」，验证 QQ 能打开。获得系统授权后，在「诊断」点「测试隐藏 QQ（Bundle ID）」。它用 Apple App Store 元数据核实的 QQ 标识 `com.tencent.mqq`，只在独立诊断 store 写入 `blockedApplications`，以隔离之前报错的 token。检查桌面、系统搜索和实际启动。回计算器点「结束 QQ 测试并恢复」，也可用「恢复全部并退出」。导出的日志在 `kind=blocked.bundle_id` 下记录两次读回。只有真机能验证隐藏效果。

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

## 2026-11-07：重启后 QQ Bundle ID 路径成功及 1.1.0 候选

用户报告重启后连接成功，QQ 可以隐藏和恢复。诊断文件 (6) 同时包含重启前后两个会话：重启前 `center.shared.begin` 后长期无返回；重启后启动 uptime 约 44 秒，初始化约 31.14 秒返回，个人授权随后约 1.22 秒返回 Approved。旧 30 秒总计时在请求阶段显示超时，之后仍成功。此证据支持分阶段提示和接纳迟到结果，不足以确定阻塞的内部根因或保证每次重启均能修复。

成功会话中两次 QQ 隐藏读回 1，恢复读回 0，均匹配请求；用户确认可见效果。沿用成功的命名 store `calculator-qq-id-probe`，1.1.0 将其用于可持久化的 Bundle ID 列表，保留旧测试设置的恢复覆盖。初始化与冷启动不读写该系统 store；仅操作限制及恢复时访问。

候选本地验证：Swift 6.2.3 / Linux，22 项 XCTest 通过，覆盖分阶段计时、超时后阶段推进、迟到成功、请求去重、标识校验、重复添加、多 App 隔离、持久化后不重施加、删除释放、保存失败紧急恢复及跨入口数量上限。已解析全部 Swift 源码并检查 diff 空白。尚未运行本候选的 macOS/iOS 编译、UI 测试、IPA 校验或真机回归；1.0.9 的成功不能替代 1.1.0 的验收。

新版真机验收：添加 QQ（初始正常）→ 隐藏 → 正常，至少两轮；加入第二个已核实 ID，分别隐藏、只恢复 QQ、删除另一项；冷启动确认列表保留且不自动重新提交；最后确认恢复全部覆盖两个入口。授权慢响应时确认可导出日志、查看恢复说明、等待迟到成功且不叠加请求。
