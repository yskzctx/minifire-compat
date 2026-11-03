# 迷枪苹果区兼容

**已知问题：用户反馈 Root 模块清后台重开会重置灵敏度等设置，并确认 2.0.1 已存在，根因和修复尚待实机确认。见[设置持久化调查](docs/SETTINGS-PERSISTENCE-INVESTIGATION.md)。登录成功不等于设置持久化已验收。**

当前保留 **Root 单入口 Hook 2.0.1** 作为登录成功的基线。2026-11-02 用户明确反馈“这次终于成功了”，本轮上下文为安卓登录苹果角色成功；没有追加确认本版对局或重启测试。

[下载成功反馈版 2.0.1](https://github.com/yskzctx/minifire-compat/releases/download/v2.0.1-minimal-pre.1/Minifire-Minimal-Hook-2.0.1-candidate.zip) · [使用和构建](minimal-root/README.md) · [与原 LSP 比较](minimal-root/COMPARISON.md)

已发布安装包保持原始字节，不重新打包或改写成功版本；SHA256：`51382311c68c344f8f0dba0689948e9b26a2c1ff2af7a38a8575eea666a6ad2e`。因此文件名和包内文案仍包含原来的候选标识，验收记录另行更新。

原 LSP 模块保留：[0.4.1 稳定安装包](https://github.com/yskzctx/minifire-compat/releases/download/v0.4.1/Minifire-Compat-0.4.1.apk)、[原版说明](docs/LSP-LEGACY.md)、`app/` 与相应发行标签。0.4.2 LSP 候选亦保留。两种兼容模块不要同时对游戏生效。

失败 Root/透明代理发行版已从 GitHub 移除；本地永久删除被自动审批拦截，尚未完成。详见[清理记录](docs/CLEANUP-2026-11-02.md)。`external-root/`、`zygisk-root/`、`proxy_offline/` 当前仍是失败历史源码，不作为可用产品或推荐构建入口。

[纯 Java 可选研究](docs/JAVA-OPTIONAL-RESEARCH.md)与已成功方案分开。当前定位到 SDK→Unity 的 Java 桥接，但尚无它能控制两段游戏登录字段的完整证明，不把纯 Java 或较少 Hook 等同于更低检测概率。

[18 项 Native 暴露面审查与最小修订](docs/NATIVE-EXPOSURE-REVIEW.md)：2.0.2 仅为审计诊断候选，2.0.1 成功安装包保持原样。不承诺更低检测率。

[2.1.0 固定 ELF 跳板候选](docs/FIXED-TRAMPOLINE-2.1.0.md)：不再链接 Dobby，原函数跳板放在模块已有 RX 段；仍需修改目标入口且有短暂 RWX 窗口。候选未做手机验收，不替代 2.0.1 成功原包。
