# 进程外改包实验

`transform.py` 从本地安卓版资源包读取 `md.ApiLoginRequest`、`md.Login` 和 `cmdpkg.CmdPacket` 的 protobuf 描述文件，提供两个纯字节转换函数。只处理已知的登录命令、系统值、渠道值和版本；其他命令原样返回。构造器的 `target_version` 独立于安卓来源版本，默认 1.0.79；其他目标版本仅能证明离线字节转换，不代表苹果服务器接受。合成样例中不使用真实手机号、验证码或令牌。

本目录目前**不是可运行的透明代理或 Root 模块**。它没有接入网络，不能解密 HTTPS、重算 `Util.EncryptToSHA1ForLogin` 签名，也不知道 `TcpSocketClient` 的完整流帧格式。当前从 Lua 脚本可确认：中控 HTTPS 请求在 protobuf 编码后签名；大厅登录消息被封装进 `cmdpkg.CmdPacket` 后交给 TCP 客户端。游戏外改包必须分别完成这两条链路，才能替代游戏内 Hook。

手机上最终的网络方案应只转发游戏 UID 的目标连接，并在不认识协议或校验失败时原样放行；不能把本实验的 protobuf 成功当成登录成功。测试命令：

## 最小注入边界

用户允许在必要时短暂加载目标进程以取得可复用的应用层签名材料，但不希望每次启动游戏都持续注入。实现前必须先证明材料确实固定、可在进程外重算签名；缓存要按游戏版本及材料指纹失效，并且不得记录手机号、验证码、令牌或原始请求。1.0.77 本地 `libil2cpp.so` 的方法表将 `Util.EncryptToSHA1ForLogin` 定位到 RVA `0x1dbbb48`。静态代码按顺序处理请求体、一个 16 字节字符串字面量和 `unique`；该字面量的 SHA-256 是 `7ae28f2f44dcfe16e83b9de24e02593199710fb309dffe0136902aa431949b24`。这证明存在固定输入，**尚不能证明它就是密钥或确认完整签名算法**。辅助方法的一部分本地机器码受保护，不能仅凭这段反汇编生成网络签名。

TLS 流量密钥只适用于对应连接，不能作为跨重启的缓存。若最终采用 HTTPS 解密代理，需要另行验证游戏的证书校验方式；如果采用短暂提取会话密钥的方式，每个新连接仍会需要新密钥，达不到“偶尔注入一次”的目标。

## 响应中的材料

本地资源的 protobuf 描述文件显示，中控 `ApiLoginResponseEntity` 含 `Token`、`OpenID` 和大厅地址；大厅 `LoginRsp` 含 `RefreshToken` 标志。Lua 流程将中控 `Token` 用于后续登录，并在大厅要求刷新时调用 `api/auth/refreshtoken`，保存返回的新 HTTP `Token`。这些是会话凭据的更新证据；没有字段或调用证据表明它们可用于解密未来 TLS 连接，或替代 `EncryptToSHA1ForLogin` 的签名材料。后续若做实机观察，应只记录字段是否出现和失效时间，不保存原始令牌值。

```powershell
uv run --with UnityPy --with protobuf --with pytest python -m pytest -q proxy_offline/test_transform.py
```
