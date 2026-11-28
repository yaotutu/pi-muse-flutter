package com.pimuse.pi_muse_flutter.attachments

import android.app.Activity
import android.content.ContentResolver
import android.content.Intent
import android.net.Uri
import android.os.CancellationSignal
import android.provider.OpenableColumns
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.IOException
import java.util.concurrent.Executors

internal const val ATTACHMENT_PICK_REQUEST_CODE = 0x5049

internal class AttachmentPicker(private val activity: Activity, messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, "pi_muse/attachments")
    private val resolver = activity.contentResolver
    private val reader = Executors.newSingleThreadExecutor()

    // 选择器与后台读取共用一次请求，待处理状态只在主线程读写。
    private var pending: Pick? = null

    init {
        channel.setMethodCallHandler(::onMethodCall)
    }

    private fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method != "pick") {
            result.notImplemented()
            return
        }
        if (pending != null) {
            result.error("busy", null, null)
            return
        }

        val args = call.arguments as? Map<*, *>
        val maxFiles = args?.get("maxFiles") as? Int
        val maxBytes = args?.get("maxBytes") as? Int
        if (activity.isFinishing || activity.isDestroyed ||
            maxFiles == null || maxFiles !in 1..4 || maxBytes == null || maxBytes !in 1..8_388_608
        ) {
            result.error("read_failed", null, null)
            return
        }

        val pick = Pick(result, maxFiles, maxBytes)
        pending = pick
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            // 供应方可能把 Markdown、JSON 或日志标为通用二进制类型，由 Dart 校验。
            type = "*/*"
            putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true)
        }
        try {
            // FlutterActivity 通过 onActivityResult 接收系统选择器的结果。
            activity.startActivityForResult(intent, ATTACHMENT_PICK_REQUEST_CODE)
        } catch (_: RuntimeException) {
            complete(pick, errorCode = "read_failed")
        }
    }

    fun onActivityResult(resultCode: Int, data: Intent?) {
        val pick = pending ?: return
        if (pick.reading) return
        when {
            activity.isFinishing || activity.isDestroyed -> complete(pick, errorCode = "read_failed")
            resultCode == Activity.RESULT_CANCELED -> complete(pick)
            resultCode != Activity.RESULT_OK -> complete(pick, errorCode = "read_failed")
            else -> {
                pick.reading = true
                reader.execute { readSelection(pick, data) }
            }
        }
    }

    fun close() {
        channel.setMethodCallHandler(null)
        reader.shutdownNow()
        pending?.let { pick ->
            pick.cancellation.cancel()
            complete(pick, errorCode = "read_failed")
        }
    }

    private fun readSelection(pick: Pick, data: Intent?) {
        try {
            val files = readFiles(pick, data)
            activity.runOnUiThread { complete(pick, files) }
        } catch (failure: PickFailure) {
            activity.runOnUiThread { complete(pick, errorCode = failure.code) }
        } catch (_: Exception) {
            activity.runOnUiThread { complete(pick, errorCode = "read_failed") }
        }
    }

    private fun complete(
        pick: Pick,
        files: List<Map<String, Any?>> = emptyList(),
        errorCode: String? = null,
    ) {
        if (pending !== pick) return
        pending = null
        val code = if (activity.isFinishing || activity.isDestroyed) "read_failed" else errorCode
        if (code == null) pick.result.success(files) else pick.result.error(code, null, null)
    }

    private fun readFiles(pick: Pick, data: Intent?): List<Map<String, Any?>> {
        val uris = linkedSetOf<Uri>()
        fun addUri(uri: Uri?) {
            if (uri == null || uri.scheme != ContentResolver.SCHEME_CONTENT) return
            if (uris.add(uri) && uris.size > pick.maxFiles) throw PickFailure("too_many")
        }

        data?.clipData?.let { clip ->
            for (index in 0 until clip.itemCount) addUri(clip.getItemAt(index).uri)
        }
        addUri(data?.data)
        if (uris.isEmpty()) throw IOException()

        val cancellation = pick.cancellation
        val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
        var remaining = pick.maxBytes
        return uris.map { uri ->
            cancellation.throwIfCanceled()
            val name = displayName(uri, cancellation)
            val mimeType = resolver.getType(uri)
            val bytes = readBytes(uri, remaining, buffer, cancellation)
            remaining -= bytes.size
            mapOf("name" to name, "mimeType" to mimeType, "bytes" to bytes)
        }
    }

    private fun displayName(uri: Uri, cancellation: CancellationSignal): String {
        return resolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null, cancellation)
            ?.use { cursor ->
                val column = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                if (column >= 0 && cursor.moveToFirst()) cursor.getString(column) else null
            }
            ?.takeIf { it.isNotBlank() }
            ?: "attachment"
    }

    private fun readBytes(
        uri: Uri,
        maxBytes: Int,
        buffer: ByteArray,
        cancellation: CancellationSignal,
    ): ByteArray {
        val descriptor = resolver.openAssetFileDescriptor(uri, "r", cancellation) ?: throw IOException()
        val output = ByteArrayOutputStream()
        descriptor.use { asset ->
            asset.createInputStream().use { input ->
                var remaining = maxBytes
                while (true) {
                    cancellation.throwIfCanceled()
                    // 只多探测一个字节，区分预算恰好用完和文件仍有数据。
                    val count = input.read(buffer, 0, minOf(buffer.size, remaining + 1))
                    if (count == -1) break
                    if (count == 0) throw IOException()
                    if (count > remaining) throw PickFailure("too_large")
                    output.write(buffer, 0, count)
                    remaining -= count
                }
            }
        }
        return output.toByteArray()
    }

    private class Pick(val result: MethodChannel.Result, val maxFiles: Int, val maxBytes: Int) {
        val cancellation = CancellationSignal()
        var reading = false
    }

    private class PickFailure(val code: String) : IOException()
}
