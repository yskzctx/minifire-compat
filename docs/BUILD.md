# 构建

需要 JDK 17、Android SDK 34、Build Tools 34.0.0、NDK 26.3.11579264、CMake 3.22.1。框架须支持现代 API 101 或以上。

设置 JAVA_HOME 与 ANDROID_HOME，或在未跟踪的 local.properties 填写 sdk.dir。执行：

```powershell
.\gradlew.bat :app:assembleRelease :app:lintRelease
.\tools\test-java.ps1
```

产物在 app/build/outputs/apk/release/app-release-unsigned.apk。安装包签名在发布工作区单独完成；仓库不包含私钥。已安装的同包名应用只能使用相同签名覆盖。

验证签名后的 APK：

```powershell
uv run --with androguard==4.1.4 --with pyelftools python tests/verify_modern_apk.py path/to/signed.apk
```

native_core_cases.lua 与 native_core_adapter.cpp 用真实 Lua 5.1／lua-protobuf 测试登录过滤器；需额外准备官方游戏的协议描述符。游戏的 APK、SDK、Lua 源码、角色数据、协议样本和 Windows 编译依赖不在仓库中分发。完整发布工作区中已运行 21 项原生逻辑测试与 5 项 ELF 校验测试。
