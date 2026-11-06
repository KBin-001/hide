# iOS 16 屏幕使用时间与卡死调研

## 公开 API 的边界

- `shield.applications` 接受 `ApplicationToken`，请求系统在打开目标 App 时显示限制页。`application.blockedApplications` 接受 `Application`，文档描述其作用是隐藏应用并阻止启动。两个设置都没有逐 App 的效果回执。读回配置、桌面图标、Spotlight 结果及实际启动行为应分别记录。Apple 的属性文档没有说明 Spotlight 的具体行为。 [ShieldSettings](https://developer.apple.com/documentation/managedsettings/shieldsettings) · [blockedApplications](https://developer.apple.com/documentation/managedsettings/applicationsettings/blockedapplications-swift.property)
- Apple 同时公开了 `Application(token:)` 和 `Application(bundleIdentifier:)`。`bundleIdentifier` 的文档明确说明，普通应用进程读取这个属性会得到 `nil`，提供限制页配置的扩展中才可读取目标的 ID。文档没有承诺这两种构造方式在 iOS 16.3 的 `blockedApplications` 路径上效果相同。可以用一个来源独立可核对的 Bundle ID 做单目标对照，不能从选择器 token 推导 ID，也不能把对照的预期结果当成已验证的修复。 [token 初始化器](https://developer.apple.com/documentation/managedsettings/application/init%28token%3A%29) · [Bundle ID 初始化器](https://developer.apple.com/documentation/managedsettings/application/init%28bundleidentifier%3A%29) · [bundleIdentifier 属性](https://developer.apple.com/documentation/managedsettings/application/bundleidentifier)
- Family Controls 的活动名称和图标可由系统 `Label` 显示。文档没有提供面向 iOS 16 主应用的异步元数据读取接口。管理列表可以先画本地稳定名称、别名与请求状态，系统选择器继续负责识别和选择目标 App。 [Displaying Activity Labels](https://developer.apple.com/documentation/familycontrols/displayingactivitylabels) · [FamilyActivityPicker](https://developer.apple.com/documentation/familycontrols/familyactivitypicker)

## 参考实现

- MIT 许可的 `flutter_family_controls` 将 iOS 16+ 上的授权、系统选择器和 shield 作为分开的操作，要求真机验证。它公开的是限制启动路径，没有声明支持隐藏图标。可参考它的能力划分，不需要引入 Flutter。 [项目说明](https://github.com/kyam28/flutter_family_controls/tree/d7596ed72200f8935cb0baae0c46eed3a9b7a55e) · [MIT 许可证](https://github.com/kyam28/flutter_family_controls/blob/d7596ed72200f8935cb0baae0c46eed3a9b7a55e/LICENSE)
- 公开可读的 `HideYourApps` 在 SpringBoard 进程中拦截 `SBIconListModel` 的图标加入操作，按 Bundle ID 过滤。包声明依赖 MobileSubstrate。这能解释为什么越狱插件可以直接干预桌面，源码没有表明它会阻止启动或过滤 Spotlight。它依赖私有 SpringBoard 接口，也没有在仓库根目录发现明确的复制许可，因此仅作技术比较。 [实现](https://github.com/menushka/HideYourApps/blob/e3f1c41efa5858ae0a818884387e3e71b4a85317/Tweak.xm) · [注入范围](https://github.com/menushka/HideYourApps/blob/e3f1c41efa5858ae0a818884387e3e71b4a85317/HideYourApps.plist) · [包依赖](https://github.com/menushka/HideYourApps/blob/e3f1c41efa5858ae0a818884387e3e71b4a85317/control)

## 真机定位顺序

1. 用一个第三方 App 重现，依次验证「正常 → 上锁 → 正常 → 隐藏 → 正常」。每次等待提交完成，记下桌面是否可见、Spotlight 是否可见、实际启动结果。每轮验证都再次进管理页，独立确认页面可滚动、可恢复和可退出。
2. 导出时间线，分别核对授权、命名 store 初始化、shield 和 blocked 写入的开始与结束。恢复候选的正常提交流程不额外读回配置，避免将读回等待计入提交。系统写入慢时依然应可返回计算器。授权和提交都完成后仍能正常启动目标 App，应作为独立的系统效果失败处理。
3. 若仍卡死，保留本轮 IPA 和对应的 dSYM，按 Mach-O UUID 匹配 `.ips`。使用同一 OS 版本的系统符号解析共享缓存帧。iOS 16 支持设备侧挂起报告，若之后可以连接 Mac，用 Instruments 的 Hangs 和 Time Profiler 复测。 [Apple watchdog 诊断](https://developer.apple.com/documentation/xcode/addressing-watchdog-terminations) · [符号化](https://developer.apple.com/documentation/xcode/adding-identifiable-symbol-names-to-a-crash-report) · [响应性调试](https://developer.apple.com/documentation/xcode/improving-app-responsiveness)
4. 滚动先测仅打开管理页的静态基线，再测改变状态时的列表。用稳定 UUID 和轻量列表行，按需展开诊断，避免在视图体里做文件读取、规则提交或应用元数据查询。有真机测量环境时再判断滚动掉帧的剩余来源。 [SwiftUI 性能](https://developer.apple.com/documentation/xcode/understanding-and-improving-swiftui-performance) · [Apple 挂起与卡顿说明](https://developer.apple.com/documentation/xcode/understanding-user-interface-responsiveness)
