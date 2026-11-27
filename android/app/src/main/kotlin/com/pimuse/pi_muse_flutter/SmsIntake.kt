package com.pimuse.pi_muse_flutter

import android.content.Context
import com.it_nomads.fluttersecurestorage.FlutterSecureStorage
import com.it_nomads.fluttersecurestorage.FlutterSecureStorageConfig
import com.it_nomads.fluttersecurestorage.SecurePreferencesCallback
import okhttp3.Call
import okhttp3.ConnectionPool
import okhttp3.HttpUrl
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull
import okhttp3.MediaType
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody
import okhttp3.Response
import okio.BufferedSink
import org.json.JSONArray
import org.json.JSONException
import org.json.JSONObject
import java.io.IOException
import java.util.concurrent.CompletableFuture
import java.util.concurrent.TimeUnit

internal enum class IntakeResult { ACCEPTED, CONFLICT, INVALID, ABSENT, AUTH, PAUSED, UNKNOWN }

internal class SmsIntake(origin: HttpUrl, private val token: String) {
    private val endpoint = origin.newBuilder().encodedPath("/api/information/items").build()
    private val archiveEndpoint = origin.newBuilder().encodedPath("/api/information/archive/items").build()
    val originKey = historyDigest(origin.toString())

    fun submission(payload: SmsPayload): Call = submit(
        endpoint,
        JSONObject().put("items", JSONArray().put(payload.json())).toString().toByteArray(),
    )

    fun archiveSubmission(batch: HistoryBatch): Call = submit(archiveEndpoint, batch.body())

    private fun submit(url: HttpUrl, body: ByteArray): Call =
        uploadClient.newCall(request(url).post(object : RequestBody() {
            override fun contentType(): MediaType = jsonType
            override fun contentLength(): Long = body.size.toLong()
            override fun isOneShot(): Boolean = true
            override fun writeTo(sink: BufferedSink) { sink.write(body) }
        }).build())

    fun archiveReadPage(cursor: String?): Call {
        // 去重键跨队列共享；必须识别同键但落在实时队列的冲突。
        val url = endpoint.newBuilder().addQueryParameter("limit", HISTORY_READ_PAGE.toString())
        cursor?.let { url.addQueryParameter("cursor", it) }
        return client.newCall(request(url.build()).get().build())
    }

    fun readback(payload: SmsPayload, execute: (Call) -> Response): IntakeResult {
        val seen = mutableSetOf<String>()
        var cursor: String? = null
        do {
            // 去重键在实时和归档间共用，所以核对时读取两个队列。
            val url = endpoint.newBuilder().addQueryParameter("limit", "20")
            cursor?.let { url.addQueryParameter("cursor", it) }
            execute(client.newCall(request(url.build()).get().build())).use { response ->
                if (response.code == 401) return IntakeResult.AUTH
                if (response.code != 200) return IntakeResult.UNKNOWN
                val data = response.json()
                val items = data.getJSONArray("items")
                for (index in 0 until items.length()) {
                    val item = items.getJSONObject(index)
                    if (item.getString("source").isEmpty() || item.getString("externalId").isEmpty()) {
                        return IntakeResult.UNKNOWN
                    }
                    if (payload.hasKey(item)) {
                        if (payload.matches(item)) return IntakeResult.ACCEPTED
                        // 缺少回执字段时无法确认冲突，留待下次核对。
                        if (item.getString("content").isEmpty() || item.getString("id").isEmpty() ||
                            item.getString("receivedAt").isEmpty() || item.getString("acceptedAt").isEmpty() ||
                            item.getString("queue") !in setOf("realtime", "archive")
                        ) return IntakeResult.UNKNOWN
                        return IntakeResult.CONFLICT
                    }
                }
                cursor = if (data.has("nextCursor")) data.getString("nextCursor") else null
                if (cursor != null && (cursor.isNullOrBlank() || !seen.add(cursor))) return IntakeResult.UNKNOWN
            }
        } while (cursor != null)
        return IntakeResult.ABSENT
    }

    private fun request(url: HttpUrl): Request.Builder = Request.Builder().url(url)
        .header("Authorization", "Bearer $token").header("Accept", "application/json")

    companion object {
        private val jsonType = "application/json; charset=utf-8".toMediaType()
        private val client = OkHttpClient.Builder()
            .callTimeout(20, TimeUnit.SECONDS)
            .followRedirects(false)
            .followSslRedirects(false)
            .retryOnConnectionFailure(false)
            .build()
        // 每次提交使用新连接，避免复用已被服务端关闭的空闲连接。
        private val uploadClient = client.newBuilder()
            .connectionPool(ConnectionPool(0, 1, TimeUnit.SECONDS))
            .build()

        fun submissionResult(response: Response, payload: SmsPayload): IntakeResult {
            if (response.code == 401) return IntakeResult.AUTH
            val data = response.json()
            return when (response.code) {
                200 -> {
                    val items = data.getJSONArray("items")
                    if (items.length() == 1 && payload.matches(items.getJSONObject(0))) {
                        IntakeResult.ACCEPTED
                    } else {
                        IntakeResult.UNKNOWN
                    }
                }
                400 -> when (data.optString("code")) {
                    "INVALID_REQUEST", "INVALID_INPUT" -> IntakeResult.INVALID
                    else -> IntakeResult.UNKNOWN
                }
                409 -> when (data.optString("code")) {
                    "SESSION_PAUSED" -> IntakeResult.PAUSED
                    "CONFLICT" -> IntakeResult.CONFLICT
                    else -> IntakeResult.UNKNOWN
                }
                else -> IntakeResult.UNKNOWN
            }
        }

        // 与 Flutter 共用唯一已提交的安全存储记录。禁用插件的错误自动清除。
        fun restore(context: Context): SmsIntake? {
            val storage = FlutterSecureStorage(context)
            val data = awaitStorage<Void> { callback ->
                storage.initialize(FlutterSecureStorageConfig(emptyMap()), callback)
            }.let {
                awaitStorage<String> { callback -> storage.read(storage.addPrefixToKey("pi-muse-connection"), callback) }
            } ?: return null
            val record = JSONObject(data)
            val origin = record.getString("address").toHttpUrlOrNull() ?: return null
            val token = record.getString("token")
            if (origin.encodedPath != "/" || origin.query != null || origin.fragment != null ||
                origin.encodedUsername.isNotEmpty() || origin.encodedPassword.isNotEmpty() ||
                token.isEmpty() || token.any { it !in '!'..'~' }
            ) return null
            return SmsIntake(origin, token)
        }

        fun archiveResponse(response: Response): JSONObject = response.json()

        private fun Response.json(): JSONObject {
            val responseBody = body ?: throw JSONException("missing response")
            // 列表每页至多 20 条；归档回执还会回显请求条目。限制异常响应的内存占用。
            if (responseBody.source().request(3L * 1024 * 1024 + 1)) throw IOException("response too large")
            return JSONObject(responseBody.string())
        }

        private fun <T> awaitStorage(start: (SecurePreferencesCallback<T>) -> Unit): T? {
            val result = CompletableFuture<T?>()
            start(object : SecurePreferencesCallback<T> {
                override fun onSuccess(value: T?) { result.complete(value) }
                override fun onError(error: Exception) { result.completeExceptionally(error) }
            })
            return result.get(10, TimeUnit.SECONDS)
        }
    }
}
