package com.pimuse.pi_muse_flutter

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import androidx.work.Constraints
import androidx.work.ExistingWorkPolicy
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.Operation
import androidx.work.WorkManager
import okhttp3.Call
import java.util.UUID

internal object SmsSync {
    private const val workName = "pi-muse-sms-sync"
    private const val enabledKey = "enabled"
    private const val statusKey = "status"
    private const val lastSuccessKey = "last_success"
    private const val installationKey = "installation"
    private val connectionStatuses = setOf("auth", "connection")
    private val serverStatuses = setOf("disabled", "paused")
    private val blockedStatuses = connectionStatuses + serverStatuses
    private var database: SmsOutbox? = null
    private var generation = 0L
    private var active: Call? = null

    private fun prefs(context: Context) = context.getSharedPreferences("sms_sync", Context.MODE_PRIVATE)

    private fun outbox(context: Context): SmsOutbox =
        database ?: SmsOutbox(context).also { database = it }

    fun hasPermission(context: Context): Boolean =
        context.checkSelfPermission(Manifest.permission.RECEIVE_SMS) == PackageManager.PERMISSION_GRANTED

    fun isEnabled(context: Context): Boolean = prefs(context).getBoolean(enabledKey, false)

    @Synchronized
    fun setEnabled(context: Context, enabled: Boolean) {
        generation++
        active?.cancel()
        check(prefs(context).edit().putBoolean(enabledKey, enabled).commit())
        if (enabled) {
            enqueue(context)
        } else {
            WorkManager.getInstance(context).cancelUniqueWork(workName)
        }
    }

    @Synchronized
    fun capture(context: Context, sender: String?, parts: List<String>, at: Long, pdus: List<ByteArray>): Operation? {
        if (!isEnabled(context) || !hasPermission(context)) return null
        val prefs = prefs(context)
        val installation = prefs.getString(installationKey, null) ?: UUID.randomUUID().toString().also {
            check(prefs.edit().putString(installationKey, it).commit())
        }
        val payload = SmsPayload.capture(installation, sender, parts, at, pdus) ?: return null
        outbox(context).add(payload)
        return enqueue(context)
    }

    @Synchronized
    fun localFailure(context: Context) {
        if (prefs(context).getString(statusKey, null) !in blockedStatuses) setStatus(context, "local_error")
    }

    @Synchronized
    fun snapshot(context: Context): Map<String, Any> {
        val prefs = prefs(context)
        val enabled = isEnabled(context)
        val permission = hasPermission(context)
        val counts = if (database != null || context.getDatabasePath("sms-outbox.db").exists()) {
            outbox(context).counts()
        } else {
            emptyMap()
        }
        return mapOf(
            "enabled" to enabled,
            "permission" to permission,
            "pending" to counts.values.sum(),
            "checking" to (counts[SmsRowState.UPLOADING] ?: 0),
            "canRetry" to (counts[SmsRowState.CHECKED_ABSENT] ?: 0),
            "failed" to (counts[SmsRowState.FAILED] ?: 0),
            "status" to (prefs.getString(statusKey, null) ?: "idle"),
            "lastSuccess" to prefs.getLong(lastSuccessKey, 0),
        )
    }

    @Synchronized
    fun connectionChanged(context: Context) {
        generation++
        active?.cancel()
        if (prefs(context).getString(statusKey, null) in connectionStatuses) {
            setStatus(context, "idle")
        }
        enqueue(context)
    }

    @Synchronized
    fun enqueue(context: Context, explicit: Boolean = false): Operation? {
        if (!isEnabled(context) || !hasPermission(context)) return null
        val status = prefs(context).getString(statusKey, null)
        if (status in connectionStatuses) return null
        if (explicit) {
            outbox(context).retryCheckedAbsent()
            setStatus(context, "idle")
        } else if (status in serverStatuses) {
            return null
        }
        if (!outbox(context).hasWork()) return null
        val request = OneTimeWorkRequestBuilder<SmsUploadWorker>()
            .setConstraints(Constraints.Builder().setRequiredNetworkType(NetworkType.CONNECTED).build())
            .build()
        return WorkManager.getInstance(context)
            .enqueueUniqueWork(workName, ExistingWorkPolicy.APPEND_OR_REPLACE, request)
    }

    @Synchronized
    fun start(context: Context): Long? = generation.takeIf {
        isEnabled(context) && hasPermission(context) &&
            prefs(context).getString(statusKey, null) !in blockedStatuses
    }

    @Synchronized
    fun current(context: Context, epoch: Long): Boolean =
        generation == epoch && isEnabled(context) && hasPermission(context)

    @Synchronized
    fun next(context: Context, epoch: Long): PendingSms? =
        if (current(context, epoch)) outbox(context).next() else null

    @Synchronized
    fun track(context: Context, epoch: Long, call: Call): Boolean {
        if (!current(context, epoch)) return false
        active = call
        return true
    }

    @Synchronized
    fun release(call: Call) {
        if (active === call) active = null
    }

    @Synchronized
    fun mark(context: Context, epoch: Long, id: String, state: SmsRowState): Boolean {
        if (!current(context, epoch)) return false
        outbox(context).setState(id, state)
        return true
    }

    @Synchronized
    fun accepted(context: Context, epoch: Long, id: String) {
        if (!current(context, epoch)) return
        outbox(context).remove(id)
        prefs(context).edit().putLong(lastSuccessKey, System.currentTimeMillis()).putString(statusKey, "idle").apply()
    }

    @Synchronized
    fun report(context: Context, epoch: Long, status: String) {
        if (current(context, epoch)) setStatus(context, status)
    }

    private fun setStatus(context: Context, status: String) {
        prefs(context).edit().putString(statusKey, status).apply()
    }
}
