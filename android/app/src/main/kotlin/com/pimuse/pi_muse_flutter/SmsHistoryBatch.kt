package com.pimuse.pi_muse_flutter

import org.json.JSONArray
import org.json.JSONException
import org.json.JSONObject
import java.io.ByteArrayOutputStream
import java.security.MessageDigest

internal const val HISTORY_BATCH_ITEMS = 500
internal const val HISTORY_BATCH_BYTES = 1024 * 1024
internal const val HISTORY_READ_PAGE = 20
private const val HISTORY_SOURCE = "sms"

internal fun historyDigest(text: String): String {
    val hex = "0123456789abcdef"
    return buildString(64) {
        for (byte in MessageDigest.getInstance("SHA-256").digest(text.toByteArray(Charsets.UTF_8))) {
            val value = byte.toInt() and 0xff
            append(hex[value ushr 4])
            append(hex[value and 15])
        }
    }
}

internal data class DeviceSms(
    val id: Long,
    val sent: Boolean,
    val address: String?,
    val body: String?,
    val date: Long?,
) {
    fun prepare(installation: String): HistoryItem? {
        val content = body?.takeIf { it.isInformationText(20_000) } ?: return null
        val timestamp = date?.takeIf { it in -62135596800000L..253402300799999L } ?: return null
        val peer = address?.takeUnless { it.isEmpty() }
        if (peer != null && !peer.isInformationText(500)) return null
        val title = if (sent) "发给：${peer ?: "未知收件人"}" else peer
        if (title != null && title.length > 500) return null
        val receivedAt = SmsPayload.utcTimestamp(timestamp)
        val fingerprint = historyFingerprint(title, content, receivedAt)
        val direction = if (sent) "sent" else "inbox"
        val externalId = "flutter-sms-history-${historyDigest("v1:$installation:$id:$direction:$fingerprint")}"
        return HistoryItem(HistoryKey(id, externalId, fingerprint), SmsPayload(externalId, title, content, receivedAt))
    }
}

// 服务端按 JavaScript trim 判断空白，但正文和标题本身原样保留。
private fun String.isInformationText(limit: Int): Boolean = length in 1..limit && SmsPayload.validWireText(this) && any {
    it !in '\u0009'..'\u000d' && it !in ' '..' ' &&
        it !in "       　﻿"
}

private fun historyFingerprint(title: String?, content: String, receivedAt: String): String =
    historyDigest("${title?.length ?: -1}:${title.orEmpty()}${content.length}:$content$receivedAt")

internal data class HistoryKey(val id: Long, val externalId: String, val fingerprint: String) {
    fun matches(item: JSONObject): Boolean {
        val expectedAt = item.stringField("receivedAt")
        val at = if (expectedAt.endsWith('Z') && '.' !in expectedAt) expectedAt.dropLast(1) + ".000Z" else expectedAt
        val title = if (item.has("title")) item.stringField("title") else null
        val content = item.stringField("content")
        val queue = item.stringField("queue")
        if (item.stringField("id").isEmpty() || item.stringField("acceptedAt").isEmpty() ||
            at.isEmpty() || content.isEmpty() || queue !in setOf("archive", "realtime")
        ) throw JSONException("Invalid information item")
        return queue == "archive" && fingerprint == historyFingerprint(title, content, at)
    }

    fun json(): JSONArray = JSONArray().put(id).put(externalId).put(fingerprint)

    companion object {
        fun decode(value: JSONArray) = HistoryKey(value.getLong(0), value.getString(1), value.getString(2))
    }
}

internal fun JSONObject.stringField(name: String): String = get(name) as? String
    ?: throw JSONException("Invalid string field")

internal fun JSONObject.historyExternalId(): String? {
    val source = stringField("source")
    val key = stringField("externalId")
    if (source.isEmpty() || key.isEmpty()) throw JSONException("Invalid information key")
    return key.takeIf { source == HISTORY_SOURCE }
}

internal data class HistoryItem(val key: HistoryKey, val payload: SmsPayload)

internal class HistoryBatch {
    private val bytes = ByteArrayOutputStream().apply { write("{\"items\":[".toByteArray()) }
    private val keys = mutableListOf<HistoryKey>()
    val records: List<HistoryKey> get() = keys.toList()
    val full: Boolean get() = keys.size == HISTORY_BATCH_ITEMS
    val empty: Boolean get() = keys.isEmpty()

    fun add(item: HistoryItem): Boolean {
        if (full) return false
        val encoded = item.payload.json().toString().toByteArray(Charsets.UTF_8)
        val delimiter = if (empty) 0 else 1
        if (bytes.size() + delimiter + encoded.size + 2 > HISTORY_BATCH_BYTES) return false
        if (!empty) bytes.write(','.code)
        bytes.write(encoded)
        keys.add(item.key)
        return true
    }

    fun body(): ByteArray = bytes.toByteArray() + "]}".toByteArray()
}
