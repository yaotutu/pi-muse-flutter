package com.pimuse.pi_muse_flutter.appupdate

import android.content.Context
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.content.pm.Signature
import android.os.Build
import android.os.SystemClock
import okhttp3.Call
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.OkHttpClient
import okhttp3.Request
import java.io.File
import java.security.MessageDigest
import java.util.concurrent.TimeUnit

internal class ApkDownload(
    private val context: Context,
    private val version: String,
    private val assetName: String,
    private val size: Long,
    private val sha256: String,
    private val downloadUrl: String? = null,
) {
    @Volatile private var cancelled = false
    @Volatile private var call: Call? = null

    init {
        require(Regex("[0-9]{1,9}\\.[0-9]{1,9}\\.[0-9]{1,9}").matches(version))
        require(assetName in assetNames)
        require(size in 1..MAX_BYTES)
        require(Regex("[0-9a-f]{64}").matches(sha256))
        if (downloadUrl != null) {
            val parsed = downloadUrl.toHttpUrl()
            require(parsed.scheme == "http" || parsed.scheme == "https")
            require(parsed.username.isEmpty() && parsed.password.isEmpty())
            require(parsed.query == null && parsed.fragment == null)
            require(parsed.encodedPath == "/updates/android/apk/v$version/$assetName")
        }
    }

    fun cancel() {
        cancelled = true
        call?.cancel()
    }

    fun fetch(onProgress: (Long) -> Unit): File {
        val directory = File(context.cacheDir, "app-updates").apply { mkdirs() }
        // 同一进程的下载在一条工作线程上串行执行，清理旧包与中断残留。
        directory.listFiles()?.filter { it.name.startsWith("update-") }?.forEach { it.delete() }
        val pending = File.createTempFile("update-", ".apk", directory)
        var verified = false
        try {
            transfer(pending, onProgress)
            verifyPackage(pending)
            check(!cancelled)
            verified = true
            return pending
        } finally {
            if (!verified) pending.delete()
        }
    }

    private fun transfer(file: File, onProgress: (Long) -> Unit) {
        val mirrorUrl = downloadUrl?.toHttpUrl()
        var url = mirrorUrl
            ?: "https://github.com/yaotutu/pi-muse-flutter/releases/download/v$version/$assetName".toHttpUrl()
        repeat(4) {
            val request = Request.Builder().url(url).header("Accept-Encoding", "identity").build()
            val currentCall = client.newCall(request)
            call = currentCall
            check(!cancelled)
            currentCall.execute().use { response ->
                if (response.isRedirect) {
                    check(mirrorUrl == null)
                    val next = url.resolve(checkNotNull(response.header("Location")))
                    check(next != null && next.isHttps && next.port == 443 &&
                        next.username.isEmpty() && next.password.isEmpty() && next.fragment == null &&
                        next.host in assetHosts)
                    url = next
                } else {
                    check(response.code == 200)
                    val body = checkNotNull(response.body)
                    check(body.contentLength() in listOf(-1L, size))
                    val digest = MessageDigest.getInstance("SHA-256")
                    var written = 0L
                    var lastProgress = 0L
                    file.outputStream().buffered().use { sink ->
                        body.byteStream().use { source ->
                            val buffer = ByteArray(64 * 1024)
                            while (true) {
                                check(!cancelled)
                                val count = source.read(buffer)
                                if (count == -1) break
                                written += count
                                check(written <= size)
                                sink.write(buffer, 0, count)
                                digest.update(buffer, 0, count)
                                val now = SystemClock.elapsedRealtime()
                                if (now - lastProgress >= 250 || written == size) {
                                    onProgress(written)
                                    lastProgress = now
                                }
                            }
                        }
                    }
                    check(written == size && digest.digest().joinToString("") { "%02x".format(it) } == sha256)
                    return
                }
            }
        }
        error("Too many redirects")
    }

    @Suppress("DEPRECATION")
    private fun verifyPackage(file: File) {
        val manager = context.packageManager
        val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            PackageManager.GET_SIGNING_CERTIFICATES
        } else {
            PackageManager.GET_SIGNATURES
        }
        val installed = manager.getPackageInfo(context.packageName, flags)
        val candidate = checkNotNull(manager.getPackageArchiveInfo(file.path, flags))
        check(candidate.packageName == context.packageName)
        check(candidate.versionName == version && candidate.buildNumber() > installed.buildNumber())
        val installedSigners = installed.signers()
        check(installedSigners.isNotEmpty() && candidate.signers() == installedSigners)
    }

    @Suppress("DEPRECATION")
    private fun PackageInfo.buildNumber(): Long =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) longVersionCode else versionCode.toLong()

    @Suppress("DEPRECATION")
    private fun PackageInfo.signers(): Set<Signature> =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            signingInfo?.apkContentsSigners.orEmpty().toSet()
        } else {
            signatures.orEmpty().toSet()
        }

    private companion object {
        const val MAX_BYTES = 256L * 1024 * 1024
        val assetNames = setOf(
            "app-release.apk",
            "app-arm64-v8a-release.apk",
            "app-armeabi-v7a-release.apk",
            "app-x86_64-release.apk",
        )
        val assetHosts = setOf("release-assets.githubusercontent.com", "objects.githubusercontent.com")
        val client = OkHttpClient.Builder()
            .callTimeout(10, TimeUnit.MINUTES)
            .readTimeout(30, TimeUnit.SECONDS)
            .followRedirects(false)
            .retryOnConnectionFailure(false)
            .build()
    }
}
