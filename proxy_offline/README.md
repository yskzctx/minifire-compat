# 进程外改包实验

`transform.py` 从本地安卓版资源包读取 `md.ApiLoginRequest`、`md.Login` 和 `cmdpkg.CmdPacket` 的 protobuf 描述文件，提供两个纯字节转换函数。只处理已知的登录命令、系统值、渠道值和版本；其他命令原样返回。合成样例中不使用真实手机号、验证码或令牌。

本目录目前**不是可运行的透明代理或 Root 模块**。它没有接入网络，不能解密 HTTPS、重算 `Util.EncryptToSHA1ForLogin` 签名，也不知道 `TcpSocketClient` 的完整流帧格式。当前从 Lua 脚本可确认：中控 HTTPS 请求在 protobuf 编码后签名；大厅登录消息被封装进 `cmdpkg.CmdPacket` 后交给 TCP 客户端。游戏外改包必须分别完成这两条链路，才能替代游戏内 Hook。

手机上最终的网络方案应只转发游戏 UID 的目标连接，并在不认识协议或校验失败时原样放行；不能把本实验的 protobuf 成功当成登录成功。测试命令：

```powershell
uv run --with UnityPy --with protobuf --with pytest python -m pytest -q proxy_offline/test_transform.py
```
