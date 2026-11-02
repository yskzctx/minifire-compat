# 可选研究：Java 桥接能否替代当前编码 Hook

2026-11-02。主线保留用户已确认成功的 2.0.1 原始发行包。本研究不安装新模块、不替换成功包、不要求新的登录或验证码。

## 本轮实际核对的静态证据

| 位置 | 看到的行为 | 能证明什么 |
|---|---|---|
| `MiniLoginUnityConnector.doUnityCall(CallInfo)` | 调用 `CallInfo.toJsData()`，取 GameObject 名和方法名，再调用 `UnityPlayer.UnitySendMessage(String,String,String)` | SDK 返回确实经过一个可定位的 Java→Unity 桥接入口 |
| `MiniLoginUnityConnector.sendMessageToNative(String)` | JSON 构建 `CallInfo`，交给 `MiniLoginController.handleRequest` | 这是 Unity→Android SDK 的反向请求桥接，不等于游戏网络发送入口 |
| `CallInfo.toJsData()` | 调用 `JsonUtils.toJson(this)` | 桥接数据是 SDK 结构的 JSON |
| `CallInfo.Request` | `fun`、`param`、`reqId` 及其访问方法 | 外层结构没有直接呈现游戏 protobuf 的平台字段；`param` 仍需按实际功能解释 |
| `CallInfo.Response` | `code`、`msg`、`result` 及其访问方法 | 返回结果字符串可能包含登录凭据；研究时只核对字段结构，不能把正文打进日志 |
| `MNWSDKService.mobileLogin(CallInfo)` | 读取 `mobile`、`areaCode`、`verifyCode`，构造 `loginType=OWN_PHONE` 的 SDK 请求 | 负责手机号验证与 SDK 登录，没有在该方法中定位到 `PhoneOs` / `Phone_Os` / `ChannelID` 的游戏登录改写 |
| 既有签名调用图 | 游戏 SHA1 登录辅助方法及 `BasePackage.Marshal` 位于 Unity IL2CPP 方法图 | 不能假设整个游戏中控/大厅协议必经 Java HTTP 库 |

证据来源是同一工作区保存的官方客户端 DEX 反汇编和调用图：`work/analysis/dex/`、`work/analysis/sign-call-map.json`。这次复查了上述方法内容，不将类名存在当作跨区功能已实现。

## 当前结论

值得保留的候选是 **Java SDK→Unity 的消息桥接**。若能证明某个非凭据字段控制后续中控和大厅使用的平台配置，可以只在该入口改配置，再由游戏原链路完成编码、签名和发送；此时未必需要外部转发。

目前缺少“Java 桥接字段 → Unity 接收方法 → 两段 protobuf 登录字段”的完整数据流证明。单改手机号 SDK 请求、假装 iOS SDK、替换已有凭据，均没有可用证据，不能代替当前已成功的方案。

Java 内部取请求、外部改写转发也有前提：Java 必须真实经过关键请求，拿到可处理的内容，并能把合法结果交还原回调。现在只有 SDK 桥接的证据，没有两段游戏网络均经过 Java 的证据。仅把代码放到 Java 里不会自动消除签名、证书或进程注入问题。

## 继续研究的门槛

1. 静态定位 Unity 对应接收对象和方法，确认 SDK 返回结构如何成为游戏登录字段；不修改手机号、令牌或验证码。
2. 用离线样本证明候选配置同时覆盖中控初次登录、缓存重登、大厅登录，且不影响资源版本。
3. 只有上述证据成立才建立独立可选分支；保留 2.0.1 的下载、安装包哈希和回退路径。
4. 设备验证只记录字段名、固定阶段和计数，不记录 SDK JSON/凭据正文；通过后仍不能用“Java”或“Hook 更少”推断检测概率。

不依赖 LSPosed 游戏作用域仍是条件。Zygisk 加载 DEX 不等于已经具备任意 Java 方法 Hook 能力；为了改一处 Java 方法再引入新的 ART Hook 引擎，可能增加整体组件与维护量。应比较实际加载内容和验证结果，不预先宣布纯 Java 更隐蔽。
