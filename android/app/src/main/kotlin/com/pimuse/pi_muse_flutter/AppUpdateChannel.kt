package com.pimuse.pi_muse_flutter

import android.content.Intent
import android.content.pm.ApplicationInfo
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors

/** 只有本通道刚校验通过的安装包可以交给 Android 安装器。 */
internal class AppUpdateChannel(private val activity: MainActivity, messenger: BinaryMessenger) {
    private val context = activity.applicationContext
    private val channel = MethodChannel(messenger, "pi_muse/app_update")
    private var active: ApkDownload? = null
    private var verifiedApk: File? = null
    private val debuggable = context.applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE != 0

    init {
        channel.setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "device" -> {
                        val info = context.packageManager.getPackageInfo(context.packageName, 0)
                        result.success(mapOf("version" to info.versionName, "supported" to !debuggable))
                    }
                    "download" -> {
                        check(!debuggable && active == null)
                        val task = ApkDownload(
                            context,
                            requireNotNull(call.argument<String>("version")),
                            requireNotNull(call.argument<String>("assetName")),
                            requireNotNull(call.argument<Number>("size")).toLong(),
                            requireNotNull(call.argument<String>("sha256")),
                            call.argument<String>("downloadUrl"),
                        )
                        verifiedApk = null
                        active = task
                        executor.execute {
                            val file = runCatching {
                                task.fetch { bytes -> activity.runOnUiThread {
                                    if (active === task) channel.invokeMethod("progress", bytes)
                                } }
                            }.getOrNull()
                            activity.runOnUiThread {
                                if (active !== task) {
                                    file?.delete()
                                    result.success(false)
                                } else {
                                    active = null
                                    verifiedApk = file
                                    if (file != null) result.success(true)
                                    else result.error("download", null, null)
                                }
                            }
                        }
                    }
                    "cancel" -> {
                        cancel()
                        result.success(null)
                    }
                    "install" -> result.success(install())
                    "openInstallSettings" -> {
                        check(verifiedApk?.isFile == true && Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
                        activity.startActivity(Intent(
                            Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                            Uri.fromParts("package", context.packageName, null),
                        ))
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            } catch (_: Exception) {
                result.error("update", null, null)
            }
        }
    }

    private fun cancel() {
        active?.cancel()
        active = null
    }

    fun close() {
        cancel()
        channel.setMethodCallHandler(null)
    }

    private fun install(): Boolean {
        val file = checkNotNull(verifiedApk)
        check(file.isFile)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            !context.packageManager.canRequestPackageInstalls()) return false
        val uri = FileProvider.getUriForFile(activity, "${context.packageName}.apk_provider", file)
        activity.startActivity(
            Intent(Intent.ACTION_VIEW).setDataAndType(uri, "application/vnd.android.package-archive")
                .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION),
        )
        return true
    }

    private companion object {
        val executor = Executors.newSingleThreadExecutor()
    }
}
