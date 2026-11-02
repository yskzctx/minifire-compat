# 进程外改包实验

`transform.py` 从本地安卓版资源包读取 `md.ApiLoginRequest`、`md.Login` 和 `cmdpkg.CmdPacket` 的 protobuf 描述文件，提供两个纯字节转换函数。只处理已知的登录命令、系统值、渠道值和版本；其他命令原样返回。构造器的 `target_version` 独立于安卓来源版本，默认 1.0.79；其他目标版本仅能证明离线字节转换，不代表苹果服务器接受。合成样例中不使用真实手机号、验证码或令牌。

本目录目前**不是可运行的透明代理或 Root 模块**。它没有接入网络或解密 HTTPS。当前从 Lua 脚本可确认：中控 HTTPS 请求在 protobuf 编码后签名；大厅登录消息被封装进 `cmdpkg.CmdPacket` 后交给 TCP 客户端。游戏外改包必须分别完成这两条链路，才能替代游戏内 Hook。

2026-11-02 电脑侧新增：`signature.py` 实现候选 SHA1(body || material || UTF8(unique))；`adapter.py` 必须先验证原请求签名才能改写并重新签名，核对失败保留原始请求。该公式尚无真实游戏请求验证。材料由调用者提供，不嵌入源码、安装包或日志。JSONL 日志使用固定事件与字段记录签名校验、改写、原样放行及请求关联 ID；不记录请求体、签名、材料、时间参数或账号凭据。日志写入失败保留可查询的错误类型和 errno，不中断请求处理。

静态调用映射进一步确认了 `BasePackage.Marshal` (0x1fdf2dc) 与 `BasePackage.UnmarshalHead` (0x1fdf5c0)，以及它们调用的 `BitConverter.GetBytes`、`BitConverter.ToUInt32` 和 `Array.Copy`。帧魔数的本地元数据字面量为 `SP`；六字节头布局为两字节魔数加四字节本机序长度，在 ARM64 样本上为小端。`framing.py` 实现此编解码层的分段/粘包处理和长度更新，未知协议、超长声明、转换失败或 EOF 半包均保留字节。尚未排除 `sendBytes` 在该编解码之后增加其他处理，因此不能把此格式直接认定为已验证的线上帧。

手机上最终的网络方案应只转发游戏 UID 的目标连接，并在不认识协议或校验失败时原样放行；不能把本实验的 protobuf 成功当成登录成功。测试命令：

## 最小注入边界

用户允许在必要时短暂加载目标进程以取得可复用的应用层签名材料，但不希望每次启动游戏都持续注入。实现前必须先证明材料确实固定、可在进程外重算签名；缓存要按游戏版本及材料指纹失效，并且不得记录手机号、验证码、令牌或原始请求。1.0.77 本地 `libil2cpp.so` 的方法表将 `Util.EncryptToSHA1ForLogin` 定位到 RVA `0x1dbbb48`。静态代码按顺序处理请求体、一个 16 字节字符串字面量和 `unique`；该字面量的 SHA-256 是 `7ae28f2f44dcfe16e83b9de24e02593199710fb309dffe0136902aa431949b24`。`signing_inspect.py` 可复查方法表、ELF 引用和字面量指纹，遇到不匹配则报错，不输出字面量内容。这证明存在固定输入，**尚不能证明它就是密钥或确认完整签名算法**。辅助方法的一部分本地机器码受保护，不能仅凭这段反汇编生成网络签名。

TLS 流量密钥只适用于对应连接，不能作为跨重启的缓存。若最终采用 HTTPS 解密代理，需要另行验证游戏的证书校验方式；如果采用短暂提取会话密钥的方式，每个新连接仍会需要新密钥，达不到“偶尔注入一次”的目标。

## 响应中的材料

本地资源的 protobuf 描述文件显示，中控 `ApiLoginResponseEntity` 含 `Token`、`OpenID` 和大厅地址；大厅 `LoginRsp` 含 `RefreshToken` 标志。Lua 流程将中控 `Token` 用于后续登录，并在大厅要求刷新时调用 `api/auth/refreshtoken`，保存返回的新 HTTP `Token`。这些是会话凭据的更新证据；没有字段或调用证据表明它们可用于解密未来 TLS 连接，或替代 `EncryptToSHA1ForLogin` 的签名材料。后续若做实机观察，应只记录字段是否出现和失效时间，不保存原始令牌值。

## 大厅 TCP 边界

按本地 1.0.77 `libil2cpp.so` 的方法表，`TcpSocketClient.ReadMessageBlocking` 位于 RVA `0x26b4bbc`，`writeMessage` 位于 `0x26b4ef4`。`sendBytes` 位于 RVA `0x26b52e8`，其本地机器码受保护。上述 SP 编解码已定位，但线上是否还有额外处理仍需确认。`lobby_packet` 接收完整 `cmdpkg.CmdPacket` 消息体，`FrameAdapter(protocol.lobby_packet)` 可处理已确认使用 SP 编码的字节流；尚未接入任何真实连接。

```powershell
uv run --with UnityPy --with protobuf --with pytest --with capstone --with pyelftools python -m pytest -q proxy_offline
```
