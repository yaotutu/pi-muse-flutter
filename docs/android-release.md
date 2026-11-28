# Android 发布与更新

首次安装从 [Flutter Releases](https://github.com/yaotutu/pi-muse-flutter/releases) 获取通用 `app-release.apk`。知道设备架构时可选 `arm64-v8a`、`armeabi-v7a` 或 `x86_64` 拆分包。覆盖更新要求应用 ID 和签名一致。调试版与正式版使用不同签名。卸载调试版会清除该安装的本机数据。

## 开发交付

在 Flutter 仓库按 [AGENTS.md](../AGENTS.md) 完成检查与相关验收。已验收的功能或修复只暂存本任务文件，提交前核对工作区和暂存区差异，推送前 `git fetch origin main` 并 `git rebase origin/main`。普通 `main` 推送触发既有发布流程。非交互 HTTPS 推送需要使用当前已授权的 GitHub CLI 凭据时，可临时执行下列命令。

```sh
GIT_TERMINAL_PROMPT=0 git -c credential.helper= -c 'credential.helper=!gh auth git-credential' push origin HEAD:main
```

保持应用 ID `com.pimuse.pi_muse_flutter`、签名和 CI 配置稳定。`pubspec.yaml` 的版本由发布工作流调用 `tools/bump-version.js` 维护。手动发版或变更签名、应用 ID、版本和流水线需要明确授权。

## 工作流与签名

[发布工作流](../.github/workflows/release.yml)在 `main` 推送后递增补丁版本和 Android 构建号，构建一个通用包和三个拆分包。分析、测试及 APK 包名、版本、ABI 和签名检查通过后，工作流推送版本提交和标签。APK 先上传至草稿，核对大小和 SHA-256 后才公开。手动运行工作流使用所选提交的当前版本，把 APK 留为 Actions 产物。

安装端需要匿名读取仓库 Releases 和 APK。工作流需要写入 `main`、标签和 Releases 的权限。发布签名通过 Actions secrets 提供，字段为 `ANDROID_KEYSTORE_BASE64`、`ANDROID_KEYSTORE_PASSWORD`、`ANDROID_KEY_ALIAS` 和 `ANDROID_KEY_PASSWORD`。妥善备份正式 keystore 和密码。本地开发使用 Debug APK。

## 手机更新验证

应用连接 Pi Muse 服务端时优先从服务端更新镜像检查和下载，未连接时使用 GitHub Releases。正式包下载经过大小、SHA-256、应用 ID、版本与签名校验，由用户在 Android 安装器里确认安装。

需要确认手机可更新时，核对对应公开 Release 的标签和 APK 资产。使用服务端镜像的设备还需核对目标实例的镜像版本和对应 APK。分别报告源码推送、流水线结果、公开发布和设备安装状态。
