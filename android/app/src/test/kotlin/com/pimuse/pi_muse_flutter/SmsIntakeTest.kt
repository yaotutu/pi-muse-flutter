package com.pimuse.pi_muse_flutter

import okhttp3.Call
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.Protocol
import okhttp3.Request
import okhttp3.Response
import okhttp3.ResponseBody.Companion.toResponseBody
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class SmsIntakeTest {
    private val parts = listOf("前半段 ", "\nsecond half  ")
    private val pdus = listOf(byteArrayOf(1, 2), byteArrayOf(3))
    private val at = 1_700_000_000_000L
    private val payload = SmsPayload.capture("fixture", "+15551234567", parts, at, pdus)!!
    private val intake = SmsIntake("http://127.0.0.1:12330/".toHttpUrl(), "synthetic-token")

    @Test
    fun multipartUsesOriginalTextAndStableIdentity() {
        assertEquals(parts.joinToString(""), payload.content)
        assertEquals("+15551234567", payload.title)
        assertEquals("2023-11-14T22:13:20.000Z", payload.receivedAt)
        assertEquals(payload, SmsPayload.decode(payload.json()))
        assertEquals(payload, SmsPayload.capture("fixture", payload.title, parts, at, pdus))
        assertNotEquals(payload.externalId, SmsPayload.capture("fixture", payload.title, parts, at, pdus.reversed())!!.externalId)
        assertNull(SmsPayload.capture("fixture", null, parts, at, emptyList()))
        assertNull(SmsPayload.capture("fixture", null, listOf(" "), at, listOf(pdus.first())))
    }

    @Test
    fun submissionOnlyConfirmsMatchingReceipt() {
        val request = intake.submission(payload).request()
        assertEquals("POST", request.method)
        assertEquals("/api/information/items", request.url.encodedPath)
        assertTrue(request.body!!.isOneShot())
        accepted().put("receivedAt", "2023-11-14T22:13:20Z").let { item ->
            response(request, 200, page(item)).use {
                assertEquals(IntakeResult.ACCEPTED, SmsIntake.submissionResult(it, payload))
            }
        }
        response(request, 200, page(accepted().put("content", "different"))).use {
            assertEquals(IntakeResult.UNKNOWN, SmsIntake.submissionResult(it, payload))
        }
        for ((code, error, expected) in listOf(
            Triple(401, "UNAUTHORIZED", IntakeResult.AUTH),
            Triple(409, "DISABLED", IntakeResult.DISABLED),
            Triple(409, "SESSION_PAUSED", IntakeResult.PAUSED),
            Triple(409, "CONFLICT", IntakeResult.CONFLICT),
            Triple(400, "INVALID_REQUEST", IntakeResult.INVALID),
            Triple(400, "INVALID_INPUT", IntakeResult.INVALID),
            Triple(503, "UNAVAILABLE", IntakeResult.UNKNOWN),
        )) {
            response(request, code, JSONObject().put("code", error)).use {
                assertEquals(expected, SmsIntake.submissionResult(it, payload))
            }
        }
    }

    @Test
    fun readbackFollowsPagesWithoutResubmitting() {
        val cursors = mutableListOf<String?>()
        val result = intake.readback(payload) { call ->
            val cursor = checkRead(call)
            cursors.add(cursor)
            val data = if (cursor == null) page().put("nextCursor", "second") else page(accepted())
            response(call.request(), 200, data)
        }
        assertEquals(listOf(null, "second"), cursors)
        assertEquals(IntakeResult.ACCEPTED, result)
    }

    @Test
    fun readbackDistinguishesConflictCompleteAbsenceAndIncompleteLookup() {
        assertEquals(IntakeResult.CONFLICT, intake.readback(payload) {
            response(it.request(), 200, page(accepted().put("queue", "archive")))
        })
        assertEquals(IntakeResult.ABSENT, intake.readback(payload) {
            response(it.request(), 200, page())
        })
        assertEquals(IntakeResult.UNKNOWN, intake.readback(payload) {
            response(it.request(), 200, page().put("nextCursor", "stuck"))
        })
        assertEquals(IntakeResult.UNKNOWN, intake.readback(payload) {
            if (checkRead(it) == null) response(it.request(), 200, page().put("nextCursor", "second"))
            else response(it.request(), 503, JSONObject())
        })
    }

    private fun checkRead(call: Call): String? {
        val request = call.request()
        assertEquals("GET", request.method)
        assertEquals("Bearer synthetic-token", request.header("Authorization"))
        assertFalse(request.url.queryParameterNames.contains("queue"))
        return request.url.queryParameter("cursor")
    }

    private fun accepted(): JSONObject = payload.json()
        .put("id", "item_fixture").put("queue", "realtime")
        .put("acceptedAt", "2023-11-14T22:13:21.000Z").put("status", "pending")

    private fun page(vararg items: JSONObject): JSONObject =
        JSONObject().put("items", JSONArray(items.toList()))

    private fun response(request: Request, code: Int, data: JSONObject): Response = Response.Builder()
        .request(request).protocol(Protocol.HTTP_1_1).code(code).message("fixture")
        .body(data.toString().toResponseBody()).build()
}
