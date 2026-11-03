# 迷枪苹果区兼容

**设置重置后续：2026-11-03 用户反馈重新卸载、安装游戏后似乎恢复正常，暂停本问题的模块修补。本轮没有修改运行时代码；根因未确认，尚无完整生命周期复测，不能归功于模块修复，也不把重装作为常规解决步骤。见[设置持久化调查](docs/SETTINGS-PERSISTENCE-INVESTIGATION.md)。**

当前正式发行 **2.1.0**，保留 **0.4.1、0.4.2、2.0.1**。2.1.0 按用户要求于 2026-11-03 从预发行改为正式发行，安装包字节不变，原标签和下载链接不变。正式发行不代表增加了设备验收。

**账号风险：用户反馈使用兼容方案期间出现过 12 小时封禁，具体模块版本和触发原因未确认。不保证账号安全或不会再次处罚。**

[2.1.0 正式发行](https://github.com/yskzctx/minifire-compat/releases/tag/v2.1.0-fixed-pre.1) · [2.1.0 实现与限制](docs/FIXED-TRAMPOLINE-2.1.0.md)

**Root 单入口 Hook 2.0.1** 作为历史登录成功基线保留。2026-11-02 用户明确反馈“这次终于成功了”，本轮上下文为安卓登录苹果角色成功；没有追加确认本版对局或重启测试。

[下载成功反馈版 2.0.1](https://github.com/yskzctx/minifire-compat/releases/download/v2.0.1-minimal-pre.1/Minifire-Minimal-Hook-2.0.1-candidate.zip) · [使用和构建](minimal-root/README.md) · [与原 LSP 比较](minimal-root/COMPARISON.md)

已发布安装包保持原始字节，不重新打包或改写成功版本；SHA256：`51382311c68c344f8f0dba0689948e9b26a2c1ff2af7a38a8575eea666a6ad2e`。因此文件名和包内文案仍包含原来的候选标识，验收记录另行更新。

原 LSP 模块保留：[0.4.1 稳定安装包](https://github.com/yskzctx/minifire-compat/releases/download/v0.4.1/Minifire-Compat-0.4.1.apk)、[原版说明](docs/LSP-LEGACY.md)、`app/` 与相应发行标签。0.4.2 LSP 候选亦保留。两种兼容模块不要同时对游戏生效。

失败 Root/透明代理发行版以及 2.0.2 审计候选已从 GitHub 移除；`external-root/`、`zygisk-root/`、`proxy_offline/` 已从当前仓库文件索引移除，旧源码仍可从 Git 历史取回。本机永久删除再次被自动审批拦截，尚未释放相应空间。详见[本次清理记录](docs/CLEANUP-2026-11-03.md)。

[纯 Java 可选研究](docs/JAVA-OPTIONAL-RESEARCH.md)与已成功方案分开。当前定位到 SDK→Unity 的 Java 桥接，但尚无它能控制两段游戏登录字段的完整证明，不把纯 Java 或较少 Hook 等同于更低检测概率。

[18 项 Native 暴露面审查记录](docs/NATIVE-EXPOSURE-REVIEW.md)：保留审查证据；2.0.2 发行已撤除，2.0.1 成功安装包保持原样。不承诺更低检测率。

[2.1.0 固定 ELF 跳板](docs/FIXED-TRAMPOLINE-2.1.0.md)：不再链接 Dobby，原函数跳板放在模块已有 RX 段；仍需修改目标入口且有短暂 RWX 窗口，尚未完成独立手机验收。2.0.1 原包继续保留供回退。
