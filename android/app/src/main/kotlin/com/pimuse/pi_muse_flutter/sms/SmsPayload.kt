package com.pimuse.pi_muse_flutter.sms

import org.json.JSONObject
import java.nio.ByteBuffer
import java.security.MessageDigest
import java.text.SimpleDateFormat
import java.util.Date
import java.util.GregorianCalendar
import java.util.Locale
import java.util.TimeZone

internal data class SmsPayload(
    val externalId: String,
    val title: String?,
    val content: String,
    val receivedAt: String,
) {
    fun json(): JSONObject = JSONObject().apply {
        put("source", "sms")
        put("externalId", externalId)
        title?.let { put("title", it) }
        put("content", content)
        put("receivedAt", receivedAt)
    }

    fun hasKey(item: JSONObject): Boolean =
        item.optString("source") == "sms" && item.optString("externalId") == externalId

    fun matches(item: JSONObject): Boolean =
        hasKey(item) && item.optString("queue") == "realtime" &&
            item.optString("id").isNotEmpty() && item.optString("acceptedAt").isNotEmpty() &&
            item.optString("content") == content && nullableTitle(item) == title &&
            sameInstant(item.optString("receivedAt"), receivedAt)

    companion object {
        fun capture(
            installation: String,
            sender: String?,
            parts: List<String>,
            timestamp: Long,
            pdus: List<ByteArray>,
        ): SmsPayload? {
            val content = parts.joinToString("")
            if (content.isBlank() || pdus.size != parts.size || pdus.any { it.isEmpty() }) return null
            check(validWireText(content))
            val digest = MessageDigest.getInstance("SHA-256")
            digest.update(installation.toByteArray())
            for (pdu in pdus) {
                digest.update(ByteBuffer.allocate(Int.SIZE_BYTES).putInt(pdu.size).array())
                digest.update(pdu)
            }
            val fingerprint = digest.digest().joinToString("") { "%02x".format(it) }
            val receivedAt = utcTimestamp(timestamp)
            return SmsPayload(
                "flutter-sms-$fingerprint",
                sender?.takeIf { it.isNotBlank() && it.length <= 500 && validWireText(it) },
                content,
                receivedAt,
            )
        }

        fun decode(data: JSONObject) = SmsPayload(
            data.getString("externalId"),
            nullableTitle(data),
            data.getString("content"),
            data.getString("receivedAt"),
        )

        private fun nullableTitle(data: JSONObject) =
            if (data.isNull("title")) null else data.getString("title")

        // Android 24 与 25 无 java.time。服务端输出 UTC 毫秒精度。
        private fun sameInstant(actual: String, expected: String): Boolean {
            if (actual == expected) return true
            return actual.endsWith("Z") && !actual.contains('.') &&
                actual.dropLast(1) + ".000Z" == expected
        }

        fun utcTimestamp(timestamp: Long): String =
            SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", Locale.ROOT).apply {
                calendar = GregorianCalendar(TimeZone.getTimeZone("UTC"), Locale.ROOT).apply {
                    gregorianChange = Date(Long.MIN_VALUE)
                }
            }.format(Date(timestamp))

        fun validWireText(text: String): Boolean {
            var index = 0
            while (index < text.length) {
                val char = text[index++]
                if (char == '\u0000' || char.isLowSurrogate()) return false
                if (char.isHighSurrogate() && (index == text.length || !text[index++].isLowSurrogate())) {
                    return false
                }
            }
            return true
        }
    }
}
