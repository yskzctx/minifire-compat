# 迷枪苹果区兼容：固定 ELF 跳板候选

源码当前为 **2.1.0 固定跳板候选**。默认仍推荐保留用户已成功的 [2.0.1 原包](https://github.com/yskzctx/minifire-compat/releases/tag/v2.0.1-minimal-pre.1)；本版还没有手机验收。原 LSP 0.4.1 也继续保留。

本版通过 Zygisk Next 加载一个模块，不依赖 LSPosed 游戏作用域。唯一业务 Hook 仍位于已核对游戏私有 libtolua 的 pb.encode。直接复用 `app/src/main/cpp/login_filter.cpp`，只改 `md.ApiLoginRequest` 和 `md.Login` 的已知平台、渠道、版本字段。账号凭据、启动资源版本、签名和游戏发送流程保持原样。

与 2.0.1/2.0.2 相比，不再链接 Dobby，也不动态分配原函数的可执行跳板。跳板是模块现有 RX 段中的固定汇编，仅对已核对原入口有效。目标入口仍需修改，仍有短暂 RWX 写入窗口，不是无痕方案。详细收益、错误回退、并发限制和离线验收见[固定跳板说明](../docs/FIXED-TRAMPOLINE-2.1.0.md)。

## 使用

1. 在 Root 管理器覆盖安装候选 ZIP，保持 Zygisk Next 启用并重启。旧 LSP 兼容模块不要同时作用于游戏。
2. 从 Root 模块 WebUI 选择目标并开启。开关和目标变更需要彻底重开游戏；后续开机无需先开 WebUI。
3. 诊断应显示 `backend=fixed_elf_trampoline`，并依次看到 Root 握手、库指纹通过、`hook_installed`、`file_backed_trampoline_selected` 和登录改写事件。日志证明改写不等于服务器接受，最终核对角色。
4. 可复制或导出完整诊断到 Download。若候选不可用，可以覆盖装回保留的 2.0.1 并重启，不需要删除账号数据。

只支持已核对官方 ARM64 1.0.77 所用 Lua 库，SHA256 `7f61316eb49e95e416b2a96b744b3eb0cc94d9347bf3c3f5c5cf983bb18a05a6`。登录目标声明保持 1.0.79。选包不等于所有渠道适配；未知库、指令或权限状态会拒绝安装 Hook。

## 日志与剩余痕迹

Root companion 读取配置并记录握手，游戏不接收私有文件 FD 或配置映射。有限期安装线程完成后退出；Root 标签日志收集器保留持久记录，异常 EOF 自动恢复。日志不记录手机号、验证码、令牌或请求正文。

模块本身、目标入口差异、Root 进程与诊断字符串仍存在。Zygisk Next 如何映射模块、游戏检查什么、以及实际检测概率均未实测。不伪造 maps、JIT 名称、线程身份或校验返回值。

## 构建

`powershell -File minimal-root/build.ps1`，NDK 26.3.11579264、ARM64/API26，单个 payload，C++ 运行库静态链接，动态依赖仅系统 libc/libdl/liblog/libm。Zygisk 公共头与 ISC 许可保存在 vendor。历史 Dobby 文件保留在源码记录中，但不链接进本候选。发行门禁检查正常 ELF 权限、非执行栈、完整 RELRO、两个导出、静态 RX 跳板、无 Dobby 或 mmap/memfd_create 导入。
