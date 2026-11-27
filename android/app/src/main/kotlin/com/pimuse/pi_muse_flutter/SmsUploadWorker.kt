package com.pimuse.pi_muse_flutter

import android.content.Context
import androidx.work.Worker
import androidx.work.WorkerParameters
import okhttp3.Call
import okhttp3.Response
import org.json.JSONException
import java.io.IOException
import java.util.concurrent.ExecutionException
import java.util.concurrent.TimeoutException

class SmsUploadWorker(context: Context, parameters: WorkerParameters) : Worker(context, parameters) {
    private val context = applicationContext
    @Volatile private var call: Call? = null

    override fun doWork(): Result = synchronized(drainLock) {
        val epoch = SmsSync.start(context) ?: return Result.success()
        try {
            drain(epoch)
        } catch (_: InterruptedException) {
            Thread.currentThread().interrupt()
            retry(epoch)
        } catch (_: Exception) {
            SmsSync.report(context, epoch, "local_error")
            Result.success()
        }
    }

    override fun onStopped() {
        call?.cancel()
        super.onStopped()
    }

    private fun drain(epoch: Long): Result {
        var row = SmsSync.next(context, epoch) ?: return Result.success()
        val intake = try {
            SmsIntake.restore(context)
        } catch (_: TimeoutException) {
            return retry(epoch)
        } catch (_: ExecutionException) {
            null
        } catch (_: JSONException) {
            null
        }
        if (intake == null) {
            SmsSync.report(context, epoch, "connection")
            return Result.success()
        }
        while (!isStopped && SmsSync.current(context, epoch)) {
            val payload = row.payload
            val id = payload.externalId
            if (row.state == SmsRowState.QUEUED) {
                if (payload.content.length > 20_000) {
                    SmsSync.mark(context, epoch, id, SmsRowState.FAILED)
                } else {
                    if (!SmsSync.mark(context, epoch, id, SmsRowState.UPLOADING)) break
                    val result = transport {
                        execute(epoch, intake.submission(payload)).use { SmsIntake.submissionResult(it, payload) }
                    }
                    when (result) {
                        IntakeResult.ACCEPTED -> SmsSync.accepted(context, epoch, id)
                        IntakeResult.CONFLICT, IntakeResult.INVALID -> SmsSync.mark(context, epoch, id, SmsRowState.FAILED)
                        IntakeResult.AUTH, IntakeResult.PAUSED -> {
                            // 已明确拒收，恢复排队状态，等待连接更新或手动重试。
                            SmsSync.mark(context, epoch, id, SmsRowState.QUEUED)
                            SmsSync.report(context, epoch, result.name.lowercase())
                            return Result.success()
                        }
                        else -> {
                            val checked = reconcile(epoch, intake, payload)
                            if (checked != null) return checked
                        }
                    }
                }
            } else {
                val checked = reconcile(epoch, intake, payload)
                if (checked != null) return checked
            }
            row = SmsSync.next(context, epoch) ?: break
        }
        return Result.success()
    }

    private fun reconcile(epoch: Long, intake: SmsIntake, payload: SmsPayload): Result? {
        val result = transport {
            intake.readback(payload) { request -> execute(epoch, request) }
        }
        when (result) {
            IntakeResult.ACCEPTED -> SmsSync.accepted(context, epoch, payload.externalId)
            IntakeResult.CONFLICT -> SmsSync.mark(context, epoch, payload.externalId, SmsRowState.FAILED)
            IntakeResult.ABSENT -> SmsSync.mark(context, epoch, payload.externalId, SmsRowState.CHECKED_ABSENT)
            IntakeResult.AUTH -> {
                SmsSync.report(context, epoch, "auth")
                return Result.success()
            }
            else -> return retry(epoch)
        }
        return null
    }

    private fun retry(epoch: Long): Result {
        if (isStopped || !SmsSync.current(context, epoch)) return Result.success()
        SmsSync.report(context, epoch, "network")
        return Result.retry()
    }

    private fun execute(epoch: Long, request: Call): Response {
        call?.let(SmsSync::release)
        call = request
        if (isStopped || !SmsSync.track(context, epoch, request)) throw IOException("sync paused")
        return request.execute()
    }

    private fun transport(request: () -> IntakeResult): IntakeResult = try {
        request()
    } catch (_: IOException) {
        IntakeResult.UNKNOWN
    } catch (_: JSONException) {
        IntakeResult.UNKNOWN
    } finally {
        call?.let(SmsSync::release)
        call = null
    }

    private companion object {
        val drainLock = Any()
    }
}
