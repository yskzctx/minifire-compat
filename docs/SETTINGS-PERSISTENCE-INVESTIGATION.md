# 设置重置问题：证据、诊断与验收门槛

2026-11-03。用户报告：清除后台后重新进入，灵敏度等配置重置；2.0.1 已存在，并非仅 2.1.0；之前原 LSP 未见此问题，但用户报告原 LSP 经常出现封号。当前 ADB 无设备，用户要求先只在电脑分析。

**状态：尚未确认根因，尚未修复。** 暂停进一步驻留缩减实验。既有“登录成功”反馈不等于设置、缓存重登、重启或账号安全全部验收。

后续已按用户指定参照实际 0.4.0 APK：其登录原生库与 0.4.1 字节相同；旧/新过滤器 870 组 Lua/Protobuf 差分验证通过，业务差异限于版本声明及其缓存识别。详见 [0.4.0 对照证据](LEGACY-0.4.0-PARITY.md)。此结论缩小了排查范围，不构成设置重置已修复的证据。

另完成 [初始化与安全复核](INITIALIZATION-AND-SAFETY-AUDIT.md)：指定客户端 luaopen_pb 机器码的四次 CPU 仿真表明，编码入口修改前后注册地址一致，初始化不会覆盖该入口。外部 Lua API 使用记录接口代替；未验证完整启动或并发。固定入口非原子写入的限制仍明确保留，本轮未新增 Hook 或运行时改动。

## 本轮确认的内容

1. 当前登录过滤器只处理两个登录消息，没有读写或删除设置文件。与归档的 0.4.1 过滤器相比，主要业务差异是目标版本 1.0.78 → 1.0.79，并增加 1.0.79 缓存组合识别。不能仅凭“没有删除文件”就排除模块的间接影响，也不能据此擅自改回旧声明。
2. 游戏 BattleSetController 使用共享 `BattleSet` 和按角色区分的 `BattleSetWithUID` 缓存；缓存不存在、旧格式检查失败或按角色数据缺失时，有恢复默认配置的分支。灵敏度包括在此设置系统内。
3. 设置页面返回处理会进入 `keepSetConfig`，再到设置缓存写入与 `BattleAllSetting.SaveSetting`。原生 Cache.SetString 与 Cache.Save 是分开的函数；后者单独转入 Unity 保存入口。不能因此断言某一次页面保存必定遗漏最终落盘。
4. `BattleAllSetting.SaveSetting` 的完整受保护原生实现尚未还原。BattleSetController 的反编译也有局部分支警告，未将有警告的输出当成完整可靠源码执行。
5. Unity 文档说明 PlayerPrefs.Save 会写入修改后的偏好，而移动平台进程被终止时不能依赖 OnApplicationQuit。它支持“保存时机是一个候选原因”，不证明本用户的具体故障。

参考：[PlayerPrefs.Save](https://docs.unity3d.com/2022.3/Documentation/ScriptReference/PlayerPrefs.Save.html)、[OnApplicationQuit](https://docs.unity3d.com/2022.3/Documentation/ScriptReference/MonoBehaviour.OnApplicationQuit.html)、[Android PlayerPrefs 存储位置](https://docs.unity3d.com/2022.3/Documentation/ScriptReference/PlayerPrefs.html)。

## 不采用的猜测性修补

不清理应用数据，不自动恢复/覆盖云端设置，不补写某个缓存魔数，不禁用游戏的格式检查，不更改用户灵敏度数值。未确认故障点前，不增加 PlayerPrefs/文件 API Hook 或周期性强制 Save，也不把登录版本改回 1.0.78 当成已验证修复。

## 已准备的只读取证

`tools/settings_probe.py` 通过 ADB 和 Root 读取 Unity 偏好文件的所有者、权限、时间、大小、设置缓存元素数量及只针对 BattleSet 元素的摘要。完整 XML、手机号、令牌、原始键名和灵敏度值不传回电脑。XML 全部元素挤在一行时也只匹配独立设置元素；不能安全完整匹配时不生成摘要。

结果仅写入 git 忽略的 `device-data/settings-probes/`。没有设备时直接退出；不推送脚本、不安装软件、不操控屏幕、不写手机文件、不结束或重启游戏。3 项电脑测试覆盖包名拒绝、输出字段白名单以及与凭据同一行的 XML 隔离，均通过；尚未实测手机端命令。

设备方便时由助手执行只读命令，用户仅操作游戏：

```text
uv run python tools/settings_probe.py --phase after_adjust
uv run python tools/settings_probe.py --phase after_close
uv run python tools/settings_probe.py --phase before_reopen
uv run python tools/settings_probe.py --phase after_reopen
```

对比至少区分：设置未写入磁盘；关进程后文件改变/丢失；文件一直保留但重登加载后重写；文件未变而游戏读取了不同角色/格式。摘要变化只能证明设置元素变化，不能单独证明具体原因或恢复了哪个数值。

## 修复后的必要回归

| 场景 | 当前状态 | 验收内容 |
|---|---|---|
| 原 LSP / Root 同设备同客户端对照 | 待实测 | 同角色、同一客户端/资源版本、同退出方式；不能用几周前不同版本代替 |
| 设置页返回后重开 | 待实测 | 灵敏度及至少一个其他设置保留 |
| Home 后清后台重开 | 待实测 | 文件摘要/时间与游戏显示共同确认 |
| 缓存登录、退出重登 | 待实测 | 同一角色的设置不被默认值或其他角色覆盖 |
| 手机重启后直接进入 | 待实测 | 无需先开控制应用，账号和设置均保留 |
| 模块覆盖升级与回退 | 待实测 | 不清游戏数据，配置保留 |
| 未知库/权限失败 | 桌面已有部分守卫测试；设备待测 | 拒绝修改时不删除或重写游戏配置 |
| 真实对局、日志及退出 | 待本修复版实测 | 设置稳定、日志不泄露凭据；不以电脑构建替代 |

不能承诺“没有任何隐藏 bug”或“不会封号”。能承诺的是保持成功包可回退、列明已知问题、补充针对性测试，并只对有证据的故障点修改，不把未验收的候选称为修复完成。
