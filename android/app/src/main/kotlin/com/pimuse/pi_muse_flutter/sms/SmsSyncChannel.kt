package com.pimuse.pi_muse_flutter.sms

import android.Manifest
import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import android.provider.Settings
import com.pimuse.pi_muse_flutter.MainActivity
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

internal const val SMS_PERMISSION_REQUEST = 4027
internal const val SMS_HISTORY_PERMISSION_REQUEST = 4028

internal class SmsSyncChannel(private val activity: MainActivity, messenger: BinaryMessenger) {
    private val context = activity.applicationContext
    private val channel = MethodChannel(messenger, "pi_muse/sms_sync")
    private val historyOwner = Any()
    private var permissionResult: MethodChannel.Result? = null
    private var historyPermissionResult: MethodChannel.Result? = null

    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "status" -> respond(result) { SmsSync.snapshot(context) }
                "openAppSettings" -> {
                    try {
                        activity.startActivity(Intent(
                            Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                            Uri.fromParts("package", context.packageName, null),
                        ))
                        result.success(null)
                    } catch (_: ActivityNotFoundException) {
                        result.error("app_settings_unavailable", null, null)
                    }
                }
                "resume" -> respond(result) {
                    SmsSync.enqueue(context)
                    Unit
                }
                "connectionChanged" -> {
                    SmsHistory.connectionChanged()
                    respond(result) { SmsSync.connectionChanged(context) }
                }
                "historyStatus" -> historyStatus(result)
                "requestHistoryPermission" -> requestHistoryPermission(result)
                "startHistory" -> {
                    SmsHistory.start(context, historyOwner)
                    result.success(null)
                }
                "pauseHistory" -> {
                    SmsHistory.pause(historyOwner)
                    result.success(null)
                }
                "retry" -> respond(result) {
                    SmsSync.enqueue(context, explicit = true)
                    Unit
                }
                "enable" -> if (SmsSync.hasPermission(context)) {
                    updateEnabled(result, true)
                } else if (permissionResult == null && historyPermissionResult == null) {
                    permissionResult = result
                    activity.requestPermissions(arrayOf(Manifest.permission.RECEIVE_SMS), SMS_PERMISSION_REQUEST)
                } else {
                    result.error("permission_pending", null, null)
                }
                "disable" -> updateEnabled(result, false)
                else -> result.notImplemented()
            }
        }
    }

    fun onPermissionResult() {
        val result = permissionResult ?: return
        permissionResult = null
        if (SmsSync.hasPermission(context)) updateEnabled(result, true) else result.success(false)
    }

    fun onResume() = SmsHistory.entered(historyOwner)

    fun onPause() = SmsHistory.left(historyOwner)

    fun onHistoryPermissionResult() {
        historyPermissionResult?.success(SmsHistory.hasPermission(context))
        historyPermissionResult = null
    }

    fun close() {
        onPause()
        permissionResult?.success(false)
        permissionResult = null
        historyPermissionResult?.success(false)
        historyPermissionResult = null
        channel.setMethodCallHandler(null)
    }

    private fun requestHistoryPermission(result: MethodChannel.Result) {
        when {
            SmsHistory.hasPermission(context) -> result.success(true)
            permissionResult != null || historyPermissionResult != null -> result.error("permission_pending", null, null)
            else -> {
                historyPermissionResult = result
                activity.requestPermissions(arrayOf(Manifest.permission.READ_SMS), SMS_HISTORY_PERMISSION_REQUEST)
            }
        }
    }

    private fun historyStatus(result: MethodChannel.Result) {
        historyStatusExecutor.execute {
            try {
                result.success(SmsHistory.snapshot(context))
            } catch (_: Exception) {
                result.error("sms_history_status", null, null)
            }
        }
    }

    private fun updateEnabled(result: MethodChannel.Result, enabled: Boolean) = respond(result) {
        SmsSync.setEnabled(context, enabled)
        true
    }

    private fun respond(result: MethodChannel.Result, action: () -> Any) {
        executor.execute {
            try {
                val value = action()
                result.success(if (value == Unit) null else value)
            } catch (_: Exception) {
                SmsSync.localFailure(context)
                result.error("sms_storage", null, null)
            }
        }
    }

    private companion object {
        val executor = Executors.newSingleThreadExecutor()
        val historyStatusExecutor = Executors.newSingleThreadExecutor()
    }
}
