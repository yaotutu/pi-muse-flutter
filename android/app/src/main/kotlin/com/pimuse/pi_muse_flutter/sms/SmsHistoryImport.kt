package com.pimuse.pi_muse_flutter.sms

import okhttp3.Call
import okhttp3.Response
import org.json.JSONArray
import org.json.JSONException
import org.json.JSONObject
import java.io.IOException

internal enum class HistoryState {
    IDLE, RUNNING, PAUSED, COMPLETE, PERMISSION, AUTH, CONNECTION, NETWORK, CHECKING, CONFLICT, ERROR,
}

internal data class HistoryPending(
    val records: List<HistoryKey>,
    val cursor: String? = null,
    val matched: Set<String> = emptySet(),
    val retryReady: Boolean = false,
) {
    fun json(): JSONObject = JSONObject().apply {
        put("records", JSONArray(records.map { it.json() }))
        cursor?.let { put("cursor", it) }
        put("matched", JSONArray(matched.toList()))
        put("retryReady", retryReady)
    }

    companion object {
        fun decode(data: JSONObject): HistoryPending {
            val records = data.getJSONArray("records")
            val matched = data.getJSONArray("matched")
            return HistoryPending(
                List(records.length()) { HistoryKey.decode(records.getJSONArray(it)) },
                if (data.has("cursor")) data.getString("cursor") else null,
                List(matched.length()) { matched.getString(it) }.toSet(),
                data.getBoolean("retryReady"),
            )
        }
    }
}

internal data class HistoryCheckpoint(
    val through: Long = 0,
    val upper: Long? = null,
    val accepted: Long = 0,
    val skipped: Long = 0,
    val failed: Long = 0,
    val pending: HistoryPending? = null,
    val complete: Boolean = false,
) {
    val savedState: HistoryState get() = when {
        pending != null -> HistoryState.CHECKING
        complete -> HistoryState.COMPLETE
        upper != null -> HistoryState.PAUSED
        else -> HistoryState.IDLE
    }

    // 改地址还是同一逻辑连接，但旧地址的分页游标和缺失结论不能沿用。
    fun forConnection(sameOrigin: Boolean): HistoryCheckpoint =
        if (sameOrigin || pending == null) this else copy(pending = HistoryPending(pending.records))

    fun encode(): String = JSONObject().apply {
        put("through", through)
        upper?.let { put("upper", it) }
        put("accepted", accepted)
        put("skipped", skipped)
        put("failed", failed)
        pending?.let { put("pending", it.json()) }
        put("complete", complete)
    }.toString()

    companion object {
        fun decode(raw: String): HistoryCheckpoint {
            val data = JSONObject(raw)
            return HistoryCheckpoint(
                data.getLong("through"),
                if (data.has("upper")) data.getLong("upper") else null,
                data.getLong("accepted"),
                data.getLong("skipped"),
                data.getLong("failed"),
                data.optJSONObject("pending")?.let(HistoryPending::decode),
                data.getBoolean("complete"),
            )
        }
    }
}

internal interface HistorySmsSource {
    fun upper(): Long
    fun scan(after: Long, upper: Long, visit: (DeviceSms) -> Boolean)
    fun reread(ids: List<Long>, visit: (DeviceSms) -> Unit)
}

internal interface HistoryRun {
    fun checkActive()
    fun state(state: HistoryState)
    fun save(checkpoint: HistoryCheckpoint, confirmed: List<String> = emptyList())
    fun wasConfirmed(externalId: String): Boolean
    fun <T> request(call: Call, read: (Response) -> T): T
}

internal class SmsHistoryImport(
    private val source: HistorySmsSource,
    private val installation: String,
    private val intake: SmsIntake,
    private val run: HistoryRun,
    private val readPageBudget: Int = 32,
    private val now: () -> Long = System::nanoTime,
) {
    private lateinit var checkpoint: HistoryCheckpoint

    fun import(initial: HistoryCheckpoint): HistoryState {
        checkpoint = initial
        // 未确认写入只由显式继续触发核对；本轮新出现的未确认结果不自动重发。
        checkpoint.pending?.let { pending ->
            val stopped = if (pending.retryReady) retry(pending) else readback(pending)
            if (stopped != null) return stopped
        }
        run.state(HistoryState.RUNNING)
        run.checkActive()
        val upper = checkpoint.upper ?: source.upper().also {
            save(HistoryCheckpoint(upper = it))
        }
        while (checkpoint.through < upper) {
            run.checkActive()
            val batch = HistoryBatch()
            var last = checkpoint.through
            var failed = checkpoint.failed
            var skipped = checkpoint.skipped
            var visited = 0
            var exhausted = true
            source.scan(last, upper) { sms ->
                run.checkActive()
                check(sms.id > last && sms.id <= upper)
                val item = sms.prepare(installation)
                if (item == null) {
                    failed++
                } else if (run.wasConfirmed(item.key.externalId)) {
                    skipped++
                } else if (!batch.add(item)) {
                    // bytes 已满时保留当前 ID 给下一批；任何单条无法编码的记录独立计数。
                    if (!batch.empty) {
                        exhausted = false
                        return@scan false
                    }
                    failed++
                }
                last = sms.id
                visited++
                (visited < HISTORY_BATCH_ITEMS).also { exhausted = it }
            }
            val pending = if (batch.empty) null else HistoryPending(batch.records)
            save(checkpoint.copy(
                through = if (exhausted) upper else last, failed = failed, skipped = skipped, pending = pending,
            ))
            // 先提交安全检查点，即使进程在网络写入中被杀也必须先回读。
            if (pending != null) submit(batch)?.let { return it }
        }
        save(checkpoint.copy(upper = null, complete = true))
        return HistoryState.COMPLETE
    }

    private fun retry(pending: HistoryPending): HistoryState? {
        run.state(HistoryState.RUNNING)
        val expected = pending.records.associateBy { it.id }
        val batch = HistoryBatch()
        run.checkActive()
        source.reread(expected.keys.toList()) { sms ->
            run.checkActive()
            val item = sms.prepare(installation)
            if (item != null && expected[sms.id] == item.key) check(batch.add(item))
        }
        val records = batch.records
        save(checkpoint.copy(
            pending = records.takeIf { it.isNotEmpty() }?.let(::HistoryPending),
            failed = checkpoint.failed + pending.records.size - records.size,
        ))
        return if (batch.empty) null else submit(batch)
    }

    private fun submit(batch: HistoryBatch): HistoryState? {
        val expected = batch.records.associateBy { it.externalId }
        return try {
            run.request(intake.archiveSubmission(batch)) { response ->
                when (response.code) {
                    200 -> {
                        val data = SmsIntake.archiveResponse(response)
                        val items = data.getJSONArray("items")
                        val skipped = data.get("skippedCount") as? Number ?: throw JSONException("Invalid skippedCount")
                        if (items.length() > expected.size || skipped.toDouble() != (expected.size - items.length()).toDouble()) {
                            throw JSONException("Unaccounted archive items")
                        }
                        val returned = mutableSetOf<String>()
                        for (index in 0 until items.length()) {
                            val item = items.getJSONObject(index)
                            val id = item.historyExternalId()
                            val key = expected[id] ?: throw JSONException("Unexpected archive key")
                            if (!returned.add(key.externalId) || !key.matches(item)) {
                                throw JSONException("Invalid archive receipt")
                            }
                        }
                        // 所有输入键唯一；服务端只回显新接纳项，其余由准确的去重计数覆盖。
                        save(checkpoint.copy(
                            pending = null,
                            accepted = checkpoint.accepted + items.length(),
                            skipped = checkpoint.skipped + skipped.toInt(),
                        ), expected.keys.toList())
                        null
                    }
                    401 -> HistoryState.AUTH
                    409 -> if (SmsIntake.archiveResponse(response).optString("code") == "CONFLICT") {
                        HistoryState.CONFLICT
                    } else HistoryState.CHECKING
                    400, 413 -> HistoryState.ERROR
                    else -> HistoryState.CHECKING
                }
            }
        } catch (_: IOException) {
            HistoryState.NETWORK
        } catch (_: JSONException) {
            HistoryState.CHECKING
        }
    }

    private fun readback(initial: HistoryPending): HistoryState? {
        run.state(HistoryState.CHECKING)
        val expected = initial.records.associateBy { it.externalId }
        var pending = initial
        val cursors = mutableSetOf(pending.cursor)
        val started = now()
        repeat(readPageBudget) {
            if (it > 0 && now() - started >= 8_000_000_000L) return HistoryState.CHECKING
            val page = try {
                run.request(intake.archiveReadPage(pending.cursor)) { response ->
                    if (response.code == 401) return@request Page(stop = HistoryState.AUTH)
                    if (response.code != 200) return@request Page(stop = HistoryState.CHECKING)
                    val data = SmsIntake.archiveResponse(response)
                    val items = data.getJSONArray("items")
                    val next = if (data.has("nextCursor")) data.stringField("nextCursor") else null
                    if (items.length() > HISTORY_READ_PAGE || next != null &&
                        (next.isBlank() || next.length > 2048 || !cursors.add(next))
                    ) throw JSONException("Invalid information page")
                    val matched = pending.matched.toMutableSet()
                    for (index in 0 until items.length()) {
                        val item = items.getJSONObject(index)
                        val key = expected[item.historyExternalId()] ?: continue
                        if (!key.matches(item)) return@request Page(stop = HistoryState.CONFLICT)
                        matched.add(key.externalId)
                    }
                    Page(next, matched)
                }
            } catch (_: IOException) {
                return HistoryState.NETWORK
            } catch (_: JSONException) {
                return HistoryState.CHECKING
            }
            page.stop?.let { return it }
            val missing = pending.records.filterNot { it.externalId in page.matched }
            if (page.cursor == null || missing.isEmpty()) {
                // 匹配与缺失一起提交；页面中途失败或超预算不能让任何键变成可重发。
                save(checkpoint.copy(
                    accepted = checkpoint.accepted + page.matched.size,
                    pending = missing.takeIf { it.isNotEmpty() }?.let { HistoryPending(it, retryReady = true) },
                ), page.matched.toList())
                return if (missing.isEmpty()) null else HistoryState.CHECKING
            }
            pending = pending.copy(cursor = page.cursor, matched = page.matched)
            save(checkpoint.copy(pending = pending))
        }
        return HistoryState.CHECKING
    }

    private fun save(value: HistoryCheckpoint, confirmed: List<String> = emptyList()) {
        run.save(value, confirmed)
        checkpoint = value
    }

    private data class Page(
        val cursor: String? = null,
        val matched: Set<String> = emptySet(),
        val stop: HistoryState? = null,
    )
}
