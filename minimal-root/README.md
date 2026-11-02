# 迷枪苹果区兼容：单入口 Hook 候选

2026-11-02 用户已确认 2.0.1 登录成功；原始成功 ZIP 保持不变。2.0.1 是新实现，借用现有 Zygisk Next 的公开 Zygisk API 加载一个 ARM64 模块库。不是把之前失败的双库/加载器 Hook 方案重新打包。无需 LSPosed 游戏作用域；必须启用 Zygisk Next，并允许它对目标应用加载模块。

只安装一个业务 Hook：已核对 `libtolua.so` 中 protobuf 注册表指向的 `pb.encode` 函数。工作线程通过已加载库枚举查找游戏 Lua 库，验证 GNU Build ID、可执行范围和编码入口 32 字节原始指令后安装。不会 Hook `dlopen`、`android_dlopen_ext`、`luaopen_pb`、`pb.decode`、Java 方法、网络读写或证书验证。找到并安装后，工作线程结束。

改写直接复用原 LSP 版 `login_filter.cpp`：仅 `md.ApiLoginRequest` 和 `md.Login`，将平台改为 2、渠道改为 888、已知登录版本统一为 1.0.79。兼容 1.0.77/78/79 的已知缓存组合。账号、令牌、验证码不改；资源版本请求不改；其他消息直接进入原编码器。当前固定客户端是官方 ARM64 1.0.77 所用的 Lua 库，SHA256 为 `7f61316eb49e95e416b2a96b744b3eb0cc94d9347bf3c3f5c5cf983bb18a05a6`。其他渠道只有包名选择能力，不代表 SDK/协议已适配。

## 使用

1. 在 Root 管理器覆盖安装 ZIP。升级自 1.0.x 时，安装脚本先停止旧转发器并清理其自有路由和证书挂载；清理失败则中止安装，不假装迁移成功。
2. 重启手机，确保 Zygisk Next 正常启用。旧 LSP 兼容模块不能同时对游戏生效。
3. 从 Root 管理器打开 WebUI，选择目标包，开启账号兼容，彻底退出后重新打开游戏。保留选包、唯一开关、复制和导出日志。
4. 每次开机不需要打开 WebUI；加载由 Zygisk Next 在应用启动时触发。开关状态保存在 Root 模块中。开关与目标变更统一在彻底重开游戏后生效，已运行游戏使用启动时的配置；跳板随游戏进程退出释放。

## 痕迹与限制

一个编码函数 Hook 会在游戏运行期间保留，必要登录请求每次经过它。不能声称只 Hook 一次然后完全无痕；它仍有 Zygisk 加载、模块 ELF、跳板可执行内存和函数入口修改。一个 Hook 比多个入口范围更小，但不能推出反检测一定更好。详见 `COMPARISON.md`。

本版不启动代理、不创建 CA、不挂载证书目录、不设置 iptables/eBPF/VPN/全局 SELinux 规则，因此 BoxProxy 不会再抢走本模块用于改写的网络入口；BoxProxy 自身的分流仍能影响游戏连通性。未做与用户手机 BoxProxy 的实机共存验收。

## 日志

2.0.1 将私有配置读取与 UID 核对全部放在 Root companion 中；应用启动回调只发送进程身份并接收“启用/不选中/失败”的数值响应，不再直接读模块私有配置、不接收私有文件 FD、不建立配置映射。Root 在私有 `state/hooks.jsonl` 记录所选游戏的握手进度：`root_selection_received` → `root_config_verified` → `app_config_received`，不依赖应用日志权限。普通应用主进程会参与一次短暂的选择握手，不被选中则卸载模块，不安装业务 Hook；这不等于 Zygisk 框架从未参与其他应用启动。

运行时模块事件输出到 `MinifireCompatM` 系统标签。Root 收集器只读取 main 缓冲区的本模块标签，保存 `system-module.log` 和两个最多 1 MiB 的滚动备份，遇到 EOF/异常退出每两秒重试，保存退出码与错误历史，不调整全局 logd 缓冲大小或 SELinux 策略。文件日志和系统日志来源分别标明；刷新分别读取每个文件最近 1500 行。导出文件位于 `Download/MinifireMinimal-日期-进程号.txt`。模块日志不包含手机号、验证码、令牌或请求正文。

关键运行时阶段：`target_selected` → `waiting_game_library` → `game_library_found` → `client_profile_verified` → `hook_installed` → `encoder_called` → `terminal_login_rewritten` / `lobby_login_rewritten`。未知库、指令拒绝和安装失败有独立事件。Root 握手记录达到 1 MiB 后暂停追加，滚动系统日志仍可查。当前游戏进程存在而无模块记录时，显示“未观察到模块加载”；只握手未见 Hook 时显示“模块启动未完成”，不再始终显示等待游戏。导出包含模块载荷是否存在、Root 模块禁用标记、ABI、游戏进程可执行文件和常见 Zygisk provider 版本信息。

用户 2.0.0 日志仅证实旧代理清理成功，以及 logcat EOF；不能确认模块是否被加载或私有配置访问是否被 SELinux 拒绝。本版修复代码中存在的静默退出路径与日志收集单次退出缺陷，不将可能原因写成已确认的设备根因。官方 Zygisk 说明确认应用回调不是完整 Root 环境，目录访问受 SELinux 限制：[公开接口说明](https://raw.githubusercontent.com/topjohnwu/zygisk-module-sample/master/module/jni/zygisk.hpp)。

电脑的原生编译、Lua/protobuf 测试和脚本测试不代表真机 Hook 安装或跨区登录成功。用户已确认本版跨区登录成功，来源为用户反馈；本轮没有独立 ADB 验证，也没有追加确认本版对局和重启。

## 构建

`powershell -File minimal-root/build.ps1`，NDK 26.3.11579264 / API26 / ARM64，静态 C++ 运行库、ELF LOAD 至少 16KiB 对齐。单个发行库位于 `zygisk/arm64-v8a.so`；Dobby 静态链接，依赖与许可证保存在 `vendor/`；保留 Apache 2.0 许可证，Zygisk 公开头文件保留 ISC 许可证。未分发 Zygisk Next 本体。
