package com.pimuse.pi_muse_flutter

import android.content.ContentResolver
import android.database.Cursor
import android.os.CancellationSignal
import android.provider.Telephony.Sms

internal class SmsHistoryProvider(
    private val resolver: ContentResolver,
    private val queryGuard: HistoryQueryGuard,
) : HistorySmsSource {
    override fun upper(): Long = query(arrayOf(Sms._ID), null, emptyArray(), "DESC") { cursor ->
        if (cursor.moveToFirst()) cursor.getLong(0) else 0L
    }

    override fun scan(after: Long, upper: Long, visit: (DeviceSms) -> Boolean) {
        var lower = after
        while (lower < upper) {
            // SMS provider 不保证支持 LIMIT；主键窗口让正文查询的结果本身有界。
            val end = lower + minOf(upper - lower, HISTORY_BATCH_ITEMS.toLong())
            val range = "${Sms._ID} > ? AND ${Sms._ID} <= ?"
            val result = query(columns, range, arrayOf(lower.toString(), end.toString())) { cursor ->
                var found = false
                while (cursor.moveToNext()) {
                    found = true
                    if (!visit(cursor.sms())) return@query ScanResult.STOP
                }
                if (found) ScanResult.FOUND else ScanResult.EMPTY
            }
            if (result == ScanResult.STOP || end == upper) return
            lower = when (result) {
                ScanResult.EMPTY -> {
                    // 删除短信后 ID 可能有大缺口；只投影主键跳到下一条可读记录。
                    val next = query(arrayOf(Sms._ID), range, arrayOf(end.toString(), upper.toString())) { cursor ->
                        if (cursor.moveToFirst()) cursor.getLong(0) else null
                    } ?: return
                    next - 1
                }
                else -> end
            }
        }
    }

    override fun reread(ids: List<Long>, visit: (DeviceSms) -> Unit) {
        if (ids.isEmpty()) return
        val placeholders = ids.joinToString(",") { "?" }
        query(columns, "${Sms._ID} IN ($placeholders)", ids.map(Long::toString).toTypedArray()) { cursor ->
            while (cursor.moveToNext()) visit(cursor.sms())
        }
    }

    private fun <T> query(
        projection: Array<String>,
        selection: String?,
        args: Array<String>,
        order: String = "ASC",
        read: (Cursor) -> T,
    ): T {
        val signal = CancellationSignal()
        return queryGuard.query(signal) {
            val where = "${Sms.TYPE} IN (?, ?)" + if (selection != null) " AND $selection" else ""
            val types = arrayOf(Sms.MESSAGE_TYPE_INBOX.toString(), Sms.MESSAGE_TYPE_SENT.toString())
            val cursor = resolver.query(Sms.CONTENT_URI, projection, where, types + args, "${Sms._ID} $order", signal)
                ?: error("SMS provider unavailable")
            cursor.use(read)
        }
    }

    private fun Cursor.sms() = DeviceSms(
        getLong(0), getInt(1) == Sms.MESSAGE_TYPE_SENT, getString(2), getString(3),
        if (isNull(4)) null else getLong(4),
    )

    private enum class ScanResult { STOP, FOUND, EMPTY }

    private companion object {
        val columns = arrayOf(Sms._ID, Sms.TYPE, Sms.ADDRESS, Sms.BODY, Sms.DATE)
    }
}

internal interface HistoryQueryGuard {
    fun <T> query(signal: CancellationSignal, read: () -> T): T
}
