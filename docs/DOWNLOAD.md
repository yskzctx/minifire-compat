# 下载与解压排查

## 按用途选择文件

| 文件 | 用途与打开方式 |
| --- | --- |
| `Minifire-Compat-0.4.1.apk` | 安卓安装包，直接交给系统安装器安装，无需先解压。 |
| GitHub 的 `Source code (zip)` | 开发源码，可以用常规 ZIP 工具解压，随后按构建说明编译；不包含可直接安装的成品 APK。 |
| `Minifire-Compat-v0.4.1.bundle` | 本地 Git 仓库备份，不是 ZIP。使用 Git 克隆，不能改后缀后解压。此文件不在 GitHub Release 附件中。 |
| `Verification-v0.4.1.json` / `SHA256SUMS-v0.4.1.txt` | 验证记录和文件校验清单，直接用文本工具查看，不是压缩包。 |

[直接下载安装包](https://github.com/yskzctx/minifire-compat/releases/download/v0.4.1/Minifire-Compat-0.4.1.apk)

## 检查下载是否完整

0.4.1 APK 的大小为 **418,870 字节**，SHA-256 为：

```text
9b2b14b4bcda73ce17e8ff5020f5cf4a5039ad867a2c605db0808bed9db5ae86
```

如果下载到的是网页、空文件或被截断的文件，请重新从 Release 的 APK 附件下载，并核对大小与校验值。文件名后缀相同不代表文件内容正确。

## 已完成的复查

2026-10-06 从公开 GitHub 链接重新下载了 APK 和 `Source code (zip)`：两者均通过 ZIP 全文件 CRC 检查，Windows 的 Expand-Archive 解压成功；APK 签名 v2／v3 检查通过，字节内容与已验证的安装包一致。复查未发现服务器上的压缩文件损坏。

这不能确认某位用户下载到的文件完整，也不能证明其设备适配。安卓安装时的“解析软件包失败”或安装失败，应按安装问题单独排查；本版需要 Android 8.0 或以上、ARM64，以及支持现代 API 101 或以上的 LSPosed。

仍然失败时，请提供**文件名、实际大小、完整报错文字、解压软件或设备型号及 Android 版本**，据此复现。无需提供账号、验证码或令牌。

## Git 备份的恢复方法

```sh
git clone Minifire-Compat-v0.4.1.bundle minifire-compat
```
