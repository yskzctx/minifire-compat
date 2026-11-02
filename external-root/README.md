# 迷枪苹果区兼容：进程外实现

本目录为新的独立进程实现。它不依赖 LSPosed、Zygisk Next 或 Android VPN API，也不向游戏或 Hunter 加载 Hook 库。`daemon/` 是安卓 ARM64 Go 可执行程序，`service.sh`、`controller.sh` 负责 Root 生命周期，`route.sh` 只为游戏 UID 建立 IPv4/IPv6 NAT 规则。

**验证范围：电脑上的真实本地 TLS/TCP 连接、协议改写与签名核对、安卓交叉构建，以及 Root 脚本的模拟测试。尚未在用户手机上确认跨区登录或对局。** 这是首个具备实际网络转发和 Root 控制流程的进程外试装包，不能把主机结果当作服务器已接受或真机已通过。

1.0.1：关闭开关主动取消准备任务并清理；安装查询、材料准备、证书准备与挂载均有时限；材料准备显示分阶段进度；路由或证书清理失败不再伪报成功并保留恢复记录；取消首次证书生成后可重新准备。上游 TLS 显式读取 Android 原始 APEX 与旧系统证书目录，仍核验服务器证书。增加启动版本接口普通/gzip 双向原样保留测试。用户已反馈此前资源报错来自代理分流，本版没有将其记作版本号修复。

版本边界：`/api/user/login` 与大厅登录声明使用苹果版本；`/api/comm/version/new` 的安卓请求和安卓响应保持原字节，包括资源版本、渠道、URL、哈希和更新要求。`md.ApiLoginResponse` 没有版本字段；启动 `md.ApiVersionResponse` 含资源配置，不能把苹果资源配置中的版本文字替换成安卓版本后就认为可用。本版不进行无协议依据的全局版本替换。

## 运行方式

1. Root 管理器覆盖安装本 ZIP 并重启。模块 ID 沿用 `minifire_compat_zygisk`，安装脚本删除先前版本的 Zygisk 注入库。首次迁移到此实现默认关闭。
2. 关闭旧 LSPosed 兼容模块的游戏作用域。在新模块 WebUI 开启唯一的账号兼容开关，等到“已准备，等待打开游戏”。
3. 彻底退出游戏后重新打开。开启状态会保存，后续重启由模块启动服务，无需再打开 WebUI。
4. 角色或连接不符合预期时，返回 WebUI 刷新诊断，并导出到 Download。关闭开关会停止代理、删除本模块创建的 UID 路由和撤销可确认属于本模块的证书挂载。游戏已缓存的信任状态随游戏进程退出消失。

## 请求处理

- 从已安装 APK 的 `libil2cpp.so` 和元数据文件读取固定签名输入，核对已知二进制 SHA-256 和材料 SHA-256；无需读取游戏内存。当前仅支持已核对的官方 ARM64 1.0.77 二进制。未知客户端会在接管网络前停止准备。
- 每台设备本地生成 ECDSA P-256 CA 与登录域名证书。CA/私钥与签名材料不包含在发行 ZIP、日志或导出文件中。
- 只在确认游戏的挂载命名空间与 init、控制进程、zygote 不共享后，在该命名空间挂载包含原证书和本地 CA 的证书目录；不修改全局证书目录、不增加全局 SELinux 规则。无法确认隔离或挂载失败时自动关闭。
- 按游戏 UID 接管 TCP 443，解析 ClientHello。`login.minifire.cn` 交给本地 TLS 服务，其余域名连接按 `SO_ORIGINAL_DST` 原样隧道转发，保留端到端 TLS。
- 只处理 `/api/user/login`。候选 SHA1(body || material || UTF8(unique)) 必须首先匹配原请求的 `sign`；通过后才把平台、渠道和版本改为已验证的字段配置并重新签名。签名、头字段或配置不符合时保留原请求，记录未改写原因。候选公式尚无真实游戏请求验证。
- 中控响应中的大厅端口在响应返回游戏前加入该 UID 的转发规则。大厅连接保持原目的地址，按已定位的 `SP + uint32LE(length)` 编解码；只改 `Cmd=10000` 且字段/版本匹配的登录正文，更新长度，其他消息和未知协议保留原字节。
- 仍需真机确认：游戏网络库是否使用这些证书目录、证书/公钥固定是否存在、真实签名头和公式是否匹配、SP 编码之后是否还有额外传输处理，以及游戏实际接受的版本声明。

## 诊断

关键记录直接保存在 Root 模块私有 `state/` 目录，包含准备、命名空间、路由、TLS 选择、签名改写、中控业务结果与大厅登录改写。原始错误按允许的文件名单导出；不会遍历 state 目录或导出私钥/材料。

事件包括 `login_tls_selected`、`signature_verified`、`request_rewritten`、`signature_headers_unrecognized`、`signature_unverified`、`login_profile_unchanged_or_unsupported`、`terminal_business_response`、`lobby_endpoint_ready`、`lobby_login_rewritten`、`client_certificate_rejected`、`upstream_failed_certificate`、`original_destination_unavailable`。不记录手机号、验证码、账号令牌、完整签名或请求正文。

关闭后的 `cleanup_failed` 表示关闭标志已保存，但不能确认清理完成；请检查导出的 `cleanup.txt`，不要把这个状态当作已恢复。准备阶段的固定事件分别表示查找安装位置、读取原生库、读取元数据、核对指纹、准备证书和保存材料。材料准备默认 90 秒超时，安装查询各 15 秒、证书目录准备 30 秒、游戏命名空间挂载 15 秒。日志导出包含这些阶段及原始工具错误，保留此前事件。

## BoxProxy eBPF 共存

eBPF 模式仍可能抢先处理游戏连接，或处理本模块以 Root UID 0 发出的上游连接。代理核心中的 `DIRECT` 出站规则和 eBPF 捕获入口的 UID 排除不是同一个步骤。

- 建议通过 BoxProxy 当前版本的应用/UID 捕获设置，排除游戏 `com.miniworldroyale.sparkgame`，让本模块取得原始连接。黑白名单语义及自动生成配置应按所用版本核对，不直接套用 TUN 配置字段。
- 本模块的转发进程是 UID 0；只排除管理界面应用包名无法排除这个进程。上游即使经过 BoxProxy，也必须能正确连接真实目的地；不要因修复本模块而批量改写所有 Root 程序的代理设置。
- 游戏相关域名应使用可达的真实 DNS 地址。若本模块拿到 Fake-IP，脱离其映射代理后可能无法连接。具体 DNS 排除规则取决于当前内核与 BoxProxy 版本。
- 本模块已在自己的 NAT 链中排除 IPv4 回环地址和 IPv6 `::1`，只创建/清理 `MFC_OUT`、`MFC_TCP` 及对应游戏 UID 的跳转；不修改 BoxProxy 配置、BPF 程序、映射或其他链。
- 这不等同于已经通过 BoxProxy 实机共存验证。可先让游戏及这条上游链路完全绕过代理，确认兼容功能，再逐项恢复需要的分流。

依据：BoxProxy 当前上游 [eBPF 入口与 UID 设置](https://github.com/boxproxy/boxproxy/blob/main/boxctl/src/core_config/sing_box.rs)、[黑白名单映射](https://github.com/boxproxy/boxproxy/blob/main/boxctl/src/core_config/common.rs)。当前源码与旧版的内核/配置能力存在差异，不能据此认定用户手机正在运行相同版本。

## 构建

Windows：`powershell -File external-root/build.ps1`。需要 Go、Android NDK 26.3.11579264；使用 Android API 26 ARM64 外部链接与系统 DNS，ELF LOAD 对齐至少 16 KB。输出 ZIP 位于项目父目录的 `outputs/`。

Go 原生核心测试：在 `external-root/daemon` 执行 `go test ./...`。Root 脚本模拟与 WebUI 测试位于 `external-root/tests/`。Python 参考转发器位于 `proxy_offline/`，不需要在手机安装 Python。
