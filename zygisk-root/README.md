# 不占用 LSPosed 游戏作用域的候选方案

基于本仓库 `v0.4.2` 登录过滤器与 Build-ID 校验独立构建。加载方式为 Zygisk API 4，Hook 引擎为静态链接 Dobby 1.2。安装后在支持模块 WebUI 的 Root 管理器打开「迷枪苹果区兼容」，可分别控制游戏和 Hunter，并查看模块日志。游戏默认开启、Hunter 默认关闭；配置保存在模块目录 `game_enabled` 和 `hunter_enabled`。切换后完全退出目标应用并重新打开生效。

游戏仅匹配 `com.miniworldroyale.sparkgame` 主进程；Hunter 仅匹配 `com.zhenxi.hunter` 与 `com.zhenxi.hunter:hunter_main_process`。两者加载完全相同的本模块 ARM64 库和加载器 Hook，进入同一套经过 Build-ID 校验的 `libtolua.so` 过滤流程。若 Hunter 没有加载相同的游戏库，日志只会显示模块加载及加载器 Hook，不会产生登录过滤事件。其他进程立即卸载。本模块不会为 Hunter 添加额外隐藏逻辑。

本模块与旧的 LSPosed 兼容模块不能同时对游戏请求生效。安装后需要在 LSPosed 管理器取消游戏作用域，并保持 Root/Zygisk 提供器工作。模块使用最新版已知的登录版本声明 `1.0.79`，但未知游戏库会被 Build-ID 校验拒绝。官方安卓版 1.0.79 的库尚未取得。

**当前仅通过电脑编译与静态检查。** 手机不在电脑旁，尚未安装、验证 Root 提供器及 WebUI 兼容性、确认原苹果角色、对局、重启或金融应用行为。不能把本 ZIP 当作已验证成品安装。待手机可连接后需先实测，再决定是否替换正在使用的 LSPosed 版。当前手机 LSPosed 作用域也尚未变更。

第三方依赖：Zygisk API v4 头文件来自 [官方示例](https://github.com/topjohnwu/zygisk-module-sample/tree/7bb941ac8edfcffd1d23761e401c45ca95409dc1)，ISC 许可证在头文件；Dobby 1.2 静态库来自 [Maven Central](https://central.sonatype.com/artifact/io.github.vvb2060.ndk/dobby/1.2)，Apache 2.0 许可证全文见 `LICENSE-APACHE-2.0.txt`。
