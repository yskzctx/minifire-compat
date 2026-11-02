# 迷枪苹果区兼容：单入口 Hook 候选

2.0.0 是新实现，借用现有 Zygisk Next 的公开 Zygisk API 加载一个 ARM64 模块库。不是把之前失败的双库/加载器 Hook 方案重新打包。无需 LSPosed 游戏作用域；必须启用 Zygisk Next，并允许它对目标应用加载模块。

只安装一个业务 Hook：已核对 `libtolua.so` 中 protobuf 注册表指向的 `pb.encode` 函数。工作线程通过已加载库枚举查找游戏 Lua 库，验证 GNU Build ID、可执行范围和编码入口 32 字节原始指令后安装。不会 Hook `dlopen`、`android_dlopen_ext`、`luaopen_pb`、`pb.decode`、Java 方法、网络读写或证书验证。找到并安装后，工作线程结束。

改写直接复用原 LSP 版 `login_filter.cpp`：仅 `md.ApiLoginRequest` 和 `md.Login`，将平台改为 2、渠道改为 888、已知登录版本统一为 1.0.79。兼容 1.0.77/78/79 的已知缓存组合。账号、令牌、验证码不改；资源版本请求不改；其他消息直接进入原编码器。当前固定客户端是官方 ARM64 1.0.77 所用的 Lua 库，SHA256 为 `7f61316eb49e95e416b2a96b744b3eb0cc94d9347bf3c3f5c5cf983bb18a05a6`。其他渠道只有包名选择能力，不代表 SDK/协议已适配。

## 使用

1. 在 Root 管理器覆盖安装 ZIP。升级自 1.0.x 时，安装脚本先停止旧转发器并清理其自有路由和证书挂载；清理失败则中止安装，不假装迁移成功。
2. 重启手机，确保 Zygisk Next 正常启用。旧 LSP 兼容模块不能同时对游戏生效。
3. 从 Root 管理器打开 WebUI，选择目标包，开启账号兼容，彻底退出后重新打开游戏。保留选包、唯一开关、复制和导出日志。
4. 每次开机不需要打开 WebUI；加载由 Zygisk Next 在应用启动时触发。开关状态保存在 Root 模块中。关闭后已运行游戏的改写立即停止，已安装的跳板直到游戏退出才释放；开启或切换目标后需重开游戏。

## 痕迹与限制

一个编码函数 Hook 会在游戏运行期间保留，必要登录请求每次经过它。不能声称只 Hook 一次然后完全无痕；它仍有 Zygisk 加载、模块 ELF、跳板可执行内存和函数入口修改。一个 Hook 比多个入口范围更小，但不能推出反检测一定更好。详见 `COMPARISON.md`。

本版不启动代理、不创建 CA、不挂载证书目录、不设置 iptables/eBPF/VPN/全局 SELinux 规则，因此 BoxProxy 不会再抢走本模块用于改写的网络入口；BoxProxy 自身的分流仍能影响游戏连通性。未做与用户手机 BoxProxy 的实机共存验收。

## 日志

Root companion 打开 Root 私有 `state/hooks.jsonl`，只把追加日志的文件描述符和只读开关文件描述符交给所选进程。游戏没有 Root 路径读写权限。事件含 PID、阶段、错误码、消息类型编号、改写前后平台/渠道和版本是否改写；不记录手机号、验证码、令牌或 protobuf 正文。另输出同样的 `MinifireCompatM` 系统日志。Root 启动脚本只运行一个标签日志收集器，保存 `system-module.log` 及两个最多 1 MiB 的滚动备份；游戏受 SELinux 限制无法直接追加文件时，仍可由 Root 收集，不修改 SELinux 策略。刷新分别读取每个文件最近 1500 行和最多 1500 条即时本模块系统日志，来源分别标明，不混淆为总行数上限。导出文件在 `Download/MinifireMinimal-日期-进程号.txt`。

关键阶段：`target_selected` → `waiting_game_library` → `game_library_found` → `client_profile_verified` → `hook_installed` → `encoder_called` → `terminal_login_rewritten` / `lobby_login_rewritten`。未知库/指令拒绝、Root companion 错误和安装失败都有独立事件。文件超过 1 MiB 时暂停文件追加，系统标签日志仍保留；Root UI 可识别文件已达到上限。文件日志保留跨启动历史，不能把历史事件当成当前进程成功。

电脑的原生编译、Lua/protobuf 测试和脚本测试不代表真机 Hook 安装或跨区登录成功。2.0.0 尚需用户手机验收；原 0.4.1 的成功不能代替本版验收。

## 构建

`powershell -File minimal-root/build.ps1`，NDK 26.3.11579264 / API26 / ARM64，静态 C++ 运行库、ELF LOAD 至少 16KiB 对齐。单个发行库位于 `zygisk/arm64-v8a.so`；Dobby 静态链接，保留 Apache 2.0 许可证，Zygisk 公开头文件保留 ISC 许可证。未分发 Zygisk Next 本体。
