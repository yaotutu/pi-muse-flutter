package com.pimuse.pi_muse_flutter

import okhttp3.Call
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.Protocol
import okhttp3.Request
import okhttp3.Response
import okhttp3.ResponseBody.Companion.toResponseBody
import okio.Buffer
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.IOException

class SmsHistoryImportTest {
    private val intake = SmsIntake("http://127.0.0.1:12330/".toHttpUrl(), "synthetic-token")

    @Test
    fun identityAndPayloadPreserveBodyDirectionAndTime() {
        val sms = row(1, " 原文\n line  ")
        val item = sms.prepare(installation)!!
        assertEquals(item, sms.prepare(installation))
        assertEquals(sms.body, item.payload.content)
        assertEquals(sms.address, item.payload.title)
        assertEquals("2023-11-14T22:13:20.000Z", item.payload.receivedAt)
        val sent = sms.copy(sent = true).prepare(installation)!!
        assertEquals("发给：${sms.address}", sent.payload.title)
        assertNotEquals(item.key, sent.key)
        for (changed in listOf(sms.copy(id = 2), sms.copy(body = "edited"), sms.copy(date = 1L), sms.copy(address = "new"))) {
            assertNotEquals(item.key.externalId, changed.prepare(installation)!!.key.externalId)
        }
        assertNotEquals(item.key.externalId, sms.prepare("other install")!!.key.externalId)
        assertNotEquals(intake.originKey, SmsIntake("http://127.0.0.1:12331/".toHttpUrl(), "synthetic-token").originKey)
        assertEquals(intake.originKey, SmsIntake("http://127.0.0.1:12330/".toHttpUrl(), "new-token").originKey)
        for (bad in listOf("", "﻿ ", "a\u0000b", "\uD800", "x".repeat(20_001))) {
            assertNull(sms.copy(body = bad).prepare(installation))
        }
    }

    @Test
    fun scanHasNoTotalCapUsesFixedUpperAndDoesNotReimportOldRows() {
        val source = Source((1L..1_201L).map { row(it, if (it == 70L) " " else "test") })
        val batchSizes = mutableListOf<Int>()
        val run = Run { req ->
            val items = posted(req)
            batchSizes.add(items.length())
            if (batchSizes.size == 1) source.rows[1_202] = row(1_202)
            receipt(req, items)
        }
        assertEquals(HistoryState.COMPLETE, import(source, run))
        assertEquals(listOf(499, 500, 201), batchSizes)
        assertEquals(1_200L, run.saved.accepted)
        assertEquals(1L, run.saved.failed)
        assertEquals(1_201L, run.saved.through)
        assertTrue(run.saved.complete)
        // 已经扫描过的低 ID 也可能后来变成可导入状态。
        source.rows[70] = row(70).copy(sent = true)
        assertEquals(HistoryState.COMPLETE, import(source, run))
        assertEquals(listOf(499, 500, 201, 1, 1), batchSizes)
        assertEquals(2L, run.saved.accepted)
        assertEquals(1_200L, run.saved.skipped)
        assertEquals(HistoryState.COMPLETE, import(source, run))
        assertEquals(listOf(499, 500, 201, 1, 1), batchSizes)
        assertEquals(0L, run.saved.accepted)
        assertEquals(1_202L, run.saved.skipped)
    }

    @Test
    fun encodedUtf8AndJsonEscapesAreIncludedInByteLimit() {
        val source = Source((1L..40L).map { row(it, "汉\n🤔".repeat(4_800)) })
        val sizes = mutableListOf<Long>()
        val run = Run { req ->
            val body = req.body!!
            sizes.add(body.contentLength())
            assertTrue(body.contentLength() <= HISTORY_BATCH_BYTES)
            assertEquals(body.contentLength(), Buffer().apply(body::writeTo).size)
            val items = posted(req)
            assertEquals(source.rows[1]!!.body, items.getJSONObject(0).getString("content"))
            receipt(req, items)
        }
        assertEquals(HistoryState.COMPLETE, import(source, run))
        assertTrue(sizes.size > 1)
        assertEquals(40L, run.saved.accepted)
    }

    @Test
    fun archiveReceiptConfirmsOnlyExactItemsAndAccountedDuplicates() {
        val source = Source(listOf(row(1), row(2)))
        val ok = Run { req -> receipt(req, JSONArray().put(posted(req).getJSONObject(0)), skipped = 1) }
        assertEquals(HistoryState.COMPLETE, import(source, ok))
        assertEquals(1L, ok.saved.accepted)
        assertEquals(1L, ok.saved.skipped)
        val badBodies: List<(JSONObject) -> JSONObject> = listOf(
            { data -> data.put("skippedCount", 0) },
            { data -> data.put("skippedCount", "1") },
            { data -> data.getJSONArray("items").getJSONObject(0).put("queue", "realtime"); data },
            { data -> data.getJSONArray("items").getJSONObject(0).put("content", "wrong"); data },
            { data ->
                val items = data.getJSONArray("items")
                items.put(items.getJSONObject(0))
                data.put("skippedCount", 0)
            },
        )
        for (bad in badBodies) {
            val run = Run { req ->
                val data = page(posted(req).getJSONObject(0).accepted()).put("skippedCount", 1)
                response(req, 200, bad(data))
            }
            assertEquals(HistoryState.CHECKING, import(source, run))
            assertEquals(0L, run.saved.accepted)
            assertEquals(0L, run.saved.skipped)
            assertFalse(run.saved.pending!!.retryReady)
        }
    }

    @Test
    fun checksPartialReadbackAtomicallyAndRetriesOnlyOnSeparateStartWithSameOriginal() {
        val rows = listOf(row(1), row(2), row(3), row(4), row(5))
        val source = Source(rows)
        val run = Run { throw IOException("synthetic timeout") }
        assertEquals(HistoryState.NETWORK, import(source, run))
        assertEquals(listOf("POST"), run.methods)
        assertFalse(run.saved.encode().contains(rows[0].body!!))
        assertFalse(run.saved.encode().contains(rows[0].address!!))
        assertEquals(run.saved, HistoryCheckpoint.decode(run.saved.encode()))
        run.reply = { req ->
            assertRead(req, null)
            // 其他来源即使使用同 ID，也不属于本批。
            response(req, 200, page(rows[0].accepted(), rows[1].accepted().put("source", "other")).put("nextCursor", "second"))
        }
        assertEquals(HistoryState.CHECKING, import(source, run, budget = 1))
        assertEquals("second", run.saved.pending!!.cursor)
        assertEquals(0L, run.saved.accepted)
        assertFalse(run.saved.pending!!.retryReady)
        run.reply = { req ->
            assertRead(req, "second")
            response(req, 503, JSONObject())
        }
        assertEquals(HistoryState.CHECKING, import(source, run))
        assertEquals(0L, run.saved.accepted)
        assertFalse(run.saved.pending!!.retryReady)
        run.reply = { req ->
            assertRead(req, "second")
            response(req, 200, page(rows[4].accepted()))
        }
        assertEquals(HistoryState.CHECKING, import(source, run))
        assertEquals(listOf("POST", "GET", "GET", "GET"), run.methods)
        assertEquals(2L, run.saved.accepted)
        assertTrue(run.saved.pending!!.retryReady)
        assertEquals(listOf(2L, 3L, 4L), run.saved.pending!!.records.map { it.id })
        source.rows.remove(3L)
        source.rows[4] = row(4, "changed since attempt")
        run.reply = { req ->
            val items = posted(req)
            assertEquals(1, items.length())
            assertEquals(rows[1].prepare(installation)!!.key.externalId, items.getJSONObject(0).getString("externalId"))
            receipt(req, items)
        }
        assertEquals(HistoryState.COMPLETE, import(source, run))
        assertEquals(3L, run.saved.accepted)
        assertEquals(2L, run.saved.failed)
        assertNull(run.saved.pending)
    }

    @Test
    fun addressChangeKeepsPendingRecordsButDiscardsOldReadbackConclusion() {
        val key = row(1).prepare(installation)!!.key
        val checkpoint = HistoryCheckpoint(
            through = 1, upper = 7, accepted = 2,
            pending = HistoryPending(listOf(key), cursor = "old-cursor", matched = setOf(key.externalId), retryReady = true),
        )
        assertEquals(checkpoint, checkpoint.forConnection(true))
        assertEquals(checkpoint.copy(pending = HistoryPending(listOf(key))), checkpoint.forConnection(false))
    }

    @Test
    fun authenticationConflictAndMalformedCursorNeverAuthorizeRetry() {
        val sms = row(1)
        val source = Source(listOf(sms))
        val run = Run { req -> response(req, 401, JSONObject()) }
        assertEquals(HistoryState.AUTH, import(source, run))
        run.reply = { req -> response(req, 200, page(sms.accepted().put("queue", "realtime"))) }
        assertEquals(HistoryState.CONFLICT, import(source, run))
        assertFalse(run.saved.pending!!.retryReady)
        run.reply = { req -> response(req, 200, page().put("nextCursor", "stuck")) }
        assertEquals(HistoryState.CHECKING, import(source, run))
        assertFalse(run.saved.pending!!.retryReady)
        assertEquals(0L, run.saved.accepted)
        assertEquals(1, run.methods.count { it == "POST" })
    }

    @Test
    fun lossOfActivationDuringRequestLeavesDurableMarkerButDoesNotCommitLateReceipt() {
        val sms = row(1)
        val source = Source(listOf(sms))
        val run = Run { error("replace handler") }
        run.reply = { req ->
            assertTrue(run.saved.pending!!.records.isNotEmpty())
            run.active = false
            receipt(req, posted(req))
        }
        assertThrows(Inactive::class.java) { import(source, run) }
        assertEquals(0L, run.saved.accepted)
        assertFalse(run.saved.pending!!.retryReady)
        val restarted = Run(run.saved) { req ->
            assertRead(req, null)
            response(req, 200, page(sms.accepted()))
        }
        assertEquals(HistoryState.COMPLETE, import(source, restarted))
        assertEquals(listOf("GET"), restarted.methods)
        assertEquals(1L, restarted.saved.accepted)
    }

    private fun import(source: Source, run: Run, budget: Int = 24) =
        SmsHistoryImport(source, installation, intake, run, budget) { 0L }.import(run.saved)

    private fun row(id: Long, body: String = "Original synthetic SMS $id") =
        DeviceSms(id, false, "+15551234567", body, 1_700_000_000_000L)

    private fun posted(req: Request): JSONArray {
        assertEquals("POST", req.method)
        assertEquals("/api/information/archive/items", req.url.encodedPath)
        assertEquals("Bearer synthetic-token", req.header("Authorization"))
        val body = req.body!!
        assertTrue(body.isOneShot())
        return JSONObject(Buffer().apply(body::writeTo).readUtf8()).getJSONArray("items")
    }

    private fun assertRead(req: Request, cursor: String?) {
        assertEquals("GET", req.method)
        assertEquals("/api/information/items", req.url.encodedPath)
        assertEquals("Bearer synthetic-token", req.header("Authorization"))
        assertEquals(cursor, req.url.queryParameter("cursor"))
        assertEquals("20", req.url.queryParameter("limit"))
    }

    private fun receipt(req: Request, items: JSONArray, skipped: Int = 0): Response {
        for (index in 0 until items.length()) items.getJSONObject(index).accepted()
        return response(req, 200, JSONObject().put("items", items).put("skippedCount", skipped))
    }

    private fun JSONObject.accepted(): JSONObject =
        put("id", "info_fixture").put("queue", "archive").put("acceptedAt", "2023-11-14T22:14:00Z")

    private fun DeviceSms.accepted() = prepare(installation)!!.payload.json().accepted()

    private fun page(vararg items: JSONObject) = JSONObject().put("items", JSONArray(items.toList()))

    private fun response(req: Request, code: Int, json: JSONObject): Response = Response.Builder()
        .request(req).protocol(Protocol.HTTP_1_1).code(code).message("fixture")
        .body(json.toString().toResponseBody()).build()

    private class Source(initial: List<DeviceSms>) : HistorySmsSource {
        val rows = initial.associateBy { it.id }.toSortedMap()
        override fun upper(): Long = rows.lastKey()
        override fun scan(after: Long, upper: Long, visit: (DeviceSms) -> Boolean) {
            for ((id, sms) in rows) if (id > after && id <= upper && !visit(sms)) return
        }
        override fun reread(ids: List<Long>, visit: (DeviceSms) -> Unit) = ids.mapNotNull(rows::get).forEach(visit)
    }

    private class Inactive : RuntimeException()
    private class Run(initial: HistoryCheckpoint = HistoryCheckpoint(), var reply: (Request) -> Response) : HistoryRun {
        val methods = mutableListOf<String>()
        var active = true
        var saved = initial
        private val confirmations = mutableSetOf<String>()
        override fun checkActive() { if (!active) throw Inactive() }
        override fun state(state: HistoryState) = checkActive()
        override fun save(checkpoint: HistoryCheckpoint, confirmed: List<String>) {
            checkActive()
            saved = checkpoint
            confirmations.addAll(confirmed)
        }
        override fun wasConfirmed(externalId: String): Boolean = externalId in confirmations
        override fun <T> request(call: Call, read: (Response) -> T): T {
            checkActive()
            methods.add(call.request().method)
            return reply(call.request()).use(read)
        }
    }

    private companion object {
        const val installation = "synthetic-installation"
    }
}
