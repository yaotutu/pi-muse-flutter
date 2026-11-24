## Android 安装

首次安装或不确定设备架构时，从 **Assets** 下载 `app-release.apk`。如果知道设备架构，可选择对应的较小安装包。

| 设备架构 | APK |
| --- | --- |
| 64 位 ARM（`arm64-v8a`） | `app-arm64-v8a-release.apk` |
| 32 位 ARM（`armeabi-v7a`） | `app-armeabi-v7a-release.apk` |
| 64 位 x86（`x86_64`） | `app-x86_64-release.apk` |

下载后在 Android 上打开 APK 并确认安装。已安装正式版时，可以在「设置 → 应用更新」检查更新。支持按架构选包的版本会优先下载匹配的 APK，缺少匹配包时使用通用包。如果设备上装的是开发调试版，请先卸载调试版。卸载会清除本机应用数据。

## Android installation

For a first install or if you are unsure which architecture your device uses, download `app-release.apk` from **Assets**. If you know your device's architecture, choose the smaller matching APK.

| Device architecture | APK |
| --- | --- |
| 64-bit ARM (`arm64-v8a`) | `app-arm64-v8a-release.apk` |
| 32-bit ARM (`armeabi-v7a`) | `app-armeabi-v7a-release.apk` |
| 64-bit x86 (`x86_64`) | `app-x86_64-release.apk` |

Open the downloaded APK on Android and confirm installation. If you already have a release build, check for updates in **Settings → App updates**. Versions with architecture-aware updates prefer the matching APK and fall back to the universal APK when needed. If you have a development debug build, uninstall it first. Uninstalling clears the app's local data.
