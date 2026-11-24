package com.pimuse.pi_muse_flutter

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.os.CancellationSignal
import okhttp3.Call
import okhttp3.Response
import java.util.concurrent.Executors

// 进程内只有一个历史导入器。Activity 重建不会让新旧实例并行写入。
internal object SmsHistory {
    private val lock = Any()
    private val worker = Executors.newSingleThreadExecutor()
    private var foreground: Any? = null
    private var generation = 0L
    private var job: Job? = null
    private var cancelOperation: (() -> Unit)? = null
    private var initialized = false
    private var state = HistoryState.IDLE
    private var checkpoint = HistoryCheckpoint()

    fun hasPermission(context: Context): Boolean =
        context.checkSelfPermission(Manifest.permission.READ_SMS) == PackageManager.PERMISSION_GRANTED

    fun entered(owner: Any) {
        val cancel = synchronized(lock) {
            val previous = foreground
            foreground = owner
            if (previous != null && previous !== owner) pauseLocked() else null
        }
        cancel?.invoke()
    }

    fun left(owner: Any) {
        val cancel = synchronized(lock) {
            if (foreground !== owner) return
            foreground = null
            pauseLocked()
        }
        cancel?.invoke()
    }

    fun pause(owner: Any) {
        val cancel = synchronized(lock) {
            if (foreground !== owner) return
            pauseLocked()
        }
        cancel?.invoke()
    }

    fun connectionChanged() {
        val cancel = synchronized(lock) {
            generation++
            initialized = false
            state = HistoryState.CONNECTION
            cancelOperation
        }
        cancel?.invoke()
    }

    fun start(context: Context, owner: Any) {
        synchronized(lock) {
            if (foreground !== owner || job != null || !hasPermission(context)) return
            val next = Job(context, owner, ++generation)
            job = next
            state = if (checkpoint.pending?.retryReady == false) HistoryState.CHECKING else HistoryState.RUNNING
            worker.execute { execute(next) }
        }
    }

    // 在单独的短任务队列读状态，不等待历史工作队列完成网络或 provider I/O。
    fun snapshot(context: Context): Map<String, Any> {
        val loadEpoch = synchronized(lock) { generation.takeIf { !initialized && job == null } }
        if (loadEpoch != null) {
            val loaded = runCatching {
                SmsIntake.restore(context)?.let { intake ->
                    if (context.getDatabasePath("sms-history.db").exists()) {
                        SmsHistoryProgress(context).use { it.restore(intake.originKey) }
                    } else HistoryCheckpoint()
                }
            }
            synchronized(lock) {
                if (generation == loadEpoch && !initialized && job == null) {
                    initialized = true
                    val saved = loaded.getOrNull()
                    checkpoint = saved ?: HistoryCheckpoint()
                    state = if (loaded.isFailure) HistoryState.ERROR else saved?.savedState ?: HistoryState.CONNECTION
                }
            }
        }
        val permission = hasPermission(context)
        var cancel: (() -> Unit)? = null
        val result = synchronized(lock) {
            if (!permission && job?.epoch == generation) cancel = pauseLocked()
            val shown = when {
                !permission -> when (checkpoint.savedState) {
                    HistoryState.IDLE, HistoryState.COMPLETE -> checkpoint.savedState
                    else -> HistoryState.PERMISSION
                }
                state == HistoryState.PERMISSION -> checkpoint.savedState
                else -> state
            }
            mapOf(
                "permission" to permission,
                "busy" to (job != null),
                "retryReady" to (checkpoint.pending?.retryReady == true && initialized),
                "state" to shown.name.lowercase(),
                "accepted" to checkpoint.accepted,
                "skipped" to checkpoint.skipped,
                "failed" to checkpoint.failed,
            )
        }
        cancel?.invoke()
        return result
    }

    private fun pauseLocked(): (() -> Unit)? {
        if (job?.epoch != generation) return null
        generation++
        state = HistoryState.PAUSED
        return cancelOperation
    }

    private fun execute(current: Job) {
        val done = try {
            checkActive(current)
            val intake = SmsIntake.restore(current.context)
            if (intake == null) {
                HistoryState.CONNECTION
            } else {
                SmsHistoryProgress(current.context).use { progress ->
                    val saved = progress.restore(intake.originKey)
                    val installation = progress.installation()
                    synchronized(lock) {
                        checkActive(current)
                        initialized = true
                        checkpoint = saved
                    }
                    val run = ImportRun(current, progress, intake.originKey)
                    val source = SmsHistoryProvider(current.context.contentResolver, run)
                    SmsHistoryImport(source, installation, intake, run).import(saved)
                }
            }
        } catch (_: Stopped) {
            HistoryState.PAUSED
        } catch (_: SecurityException) {
            if (hasPermission(current.context)) HistoryState.ERROR else HistoryState.PERMISSION
        } catch (_: Exception) {
            HistoryState.ERROR
        }
        synchronized(lock) {
            if (job === current) {
                if (current.epoch == generation) {
                    initialized = true
                    state = if (hasPermission(current.context)) done else HistoryState.PERMISSION
                }
                job = null
            }
        }
    }

    private fun checkActive(current: Job) = synchronized(lock) {
        if (current.epoch != generation || foreground !== current.owner) throw Stopped()
        if (!hasPermission(current.context)) throw SecurityException()
    }

    private class ImportRun(
        val current: Job,
        val progress: SmsHistoryProgress,
        val originKey: String,
    ) : HistoryRun, HistoryQueryGuard {
        override fun checkActive() = SmsHistory.checkActive(current)

        override fun state(state: HistoryState) = synchronized(lock) {
            checkActive()
            SmsHistory.state = state
        }

        override fun save(checkpoint: HistoryCheckpoint, confirmed: List<String>) {
            synchronized(lock) {
                checkActive()
                progress.save(originKey, checkpoint, confirmed)
                SmsHistory.checkpoint = checkpoint
            }
        }

        override fun wasConfirmed(externalId: String): Boolean = progress.wasConfirmed(externalId)

        override fun <T> request(call: Call, read: (Response) -> T): T = guarded(call::cancel) {
            call.execute().use(read)
        }

        override fun <T> query(signal: CancellationSignal, read: () -> T): T = guarded(signal::cancel, read)

        private fun <T> guarded(cancel: () -> Unit, read: () -> T): T {
            synchronized(lock) {
                checkActive()
                cancelOperation = cancel
            }
            try {
                val value = read()
                checkActive()
                return value
            } finally {
                synchronized(lock) { cancelOperation = null }
            }
        }
    }

    private data class Job(val context: Context, val owner: Any, val epoch: Long)
    private class Stopped : RuntimeException()
}
