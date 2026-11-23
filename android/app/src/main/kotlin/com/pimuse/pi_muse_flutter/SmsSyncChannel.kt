package com.pimuse.pi_muse_flutter

import android.Manifest
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

internal const val SMS_PERMISSION_REQUEST = 4027

internal class SmsSyncChannel(private val activity: MainActivity, messenger: BinaryMessenger) {
    private val context = activity.applicationContext
    private val channel = MethodChannel(messenger, "pi_muse/sms_sync")
    private var permissionResult: MethodChannel.Result? = null

    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "status" -> respond(result) { SmsSync.snapshot(context) }
                "resume" -> respond(result) {
                    SmsSync.enqueue(context)
                    Unit
                }
                "connectionChanged" -> respond(result) { SmsSync.connectionChanged(context) }
                "retry" -> respond(result) {
                    SmsSync.enqueue(context, explicit = true)
                    Unit
                }
                "enable" -> if (SmsSync.hasPermission(context)) {
                    updateEnabled(result, true)
                } else if (permissionResult == null) {
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

    fun close() {
        permissionResult?.success(false)
        permissionResult = null
        channel.setMethodCallHandler(null)
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
    }
}
