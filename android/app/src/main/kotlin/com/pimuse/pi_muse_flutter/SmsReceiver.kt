package com.pimuse.pi_muse_flutter

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.provider.Telephony
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

class SmsReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Telephony.Sms.Intents.SMS_RECEIVED_ACTION ||
            !SmsSync.isEnabled(context) || !SmsSync.hasPermission(context)
        ) return
        val application = context.applicationContext
        val pending = goAsync()
        captureExecutor.execute {
            try {
                @Suppress("DEPRECATION")
                val raw = intent.extras?.get("pdus") as? Array<*> ?: return@execute
                if (raw.isEmpty()) return@execute
                val pdus = raw.map { it as? ByteArray ?: return@execute }
                val messages = Telephony.Sms.Intents.getMessagesFromIntent(intent)
                if (messages.size != pdus.size) return@execute
                val first = messages.firstOrNull() ?: return@execute
                val sender = first.originatingAddress
                val parts = messages.map { message ->
                    if (message == null || message.originatingAddress != sender) return@execute
                    message.messageBody ?: return@execute
                }
                // 系统收到完整长短信后才广播，PDU 已按片段顺序排列。
                val work = SmsSync.capture(application, sender, parts, first.timestampMillis, pdus)
                work?.result?.get(3, TimeUnit.SECONDS)
            } catch (_: Exception) {
                SmsSync.localFailure(application)
            } finally {
                pending.finish()
            }
        }
    }

    private companion object {
        val captureExecutor = Executors.newSingleThreadExecutor()
    }
}
