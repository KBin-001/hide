# 01: 个人授权与单 App 隐藏恢复

**What to build:** 用户从管理页请求个人授权，通过系统选择器选择一个第三方 App，隐藏它后再恢复，并获得可反馈的具体授权失败信息。

**Blocked by:** None (can start immediately).

**Status:** ready-for-agent

- [ ] 个人授权成功或失败状态可见，错误包含 domain、code 与系统提供的原因。
- [ ] 单 App 隐藏使用公开 blockedApplications；正常撤销本工具限制。
- [ ] 控制器行为测试覆盖隐藏恢复和保存失败。
- [ ] 真机确认图标隐藏与恢复，保留系统历史和授权入口。

实施记录：代码与测试已实现；macOS 编译/测试及真机效果待验收。
