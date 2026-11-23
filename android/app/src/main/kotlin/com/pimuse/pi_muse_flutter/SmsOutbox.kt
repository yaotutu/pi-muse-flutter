package com.pimuse.pi_muse_flutter

import android.content.ContentValues
import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import org.json.JSONObject
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

// UPLOADING 持久化在发请求之前，进程重启后先核对这条短信。
internal enum class SmsRowState { QUEUED, UPLOADING, CHECKED_ABSENT, FAILED }

internal data class PendingSms(val payload: SmsPayload, val state: SmsRowState)

internal class SmsOutbox(context: Context) : SQLiteOpenHelper(
    context.applicationContext, "sms-outbox.db", null, 1,
) {
    override fun onCreate(db: SQLiteDatabase) {
        db.execSQL(
            """CREATE TABLE pending_sms (
               external_id TEXT NOT NULL UNIQUE,
               payload BLOB NOT NULL,
               state TEXT NOT NULL
            )""",
        )
    }

    override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) = Unit

    fun add(payload: SmsPayload) {
        val data = ContentValues().apply {
            put("external_id", payload.externalId)
            put("payload", encrypt(payload.externalId, payload.json().toString()))
            put("state", SmsRowState.QUEUED.name)
        }
        writableDatabase.insertWithOnConflict("pending_sms", null, data, SQLiteDatabase.CONFLICT_IGNORE)
    }

    fun next(): PendingSms? = readableDatabase.query(
        "pending_sms", arrayOf("external_id", "payload", "state"),
        "state IN (?, ?)", arrayOf(SmsRowState.QUEUED.name, SmsRowState.UPLOADING.name),
        null, null, "rowid", "1",
    ).use { cursor ->
        if (!cursor.moveToFirst()) return null
        val text = decrypt(cursor.getString(0), cursor.getBlob(1))
        PendingSms(SmsPayload.decode(JSONObject(text)), SmsRowState.valueOf(cursor.getString(2)))
    }

    // 只重提用户点击时已经完整核对过的记录。
    fun retryCheckedAbsent() {
        writableDatabase.update(
            "pending_sms", ContentValues().apply { put("state", SmsRowState.QUEUED.name) },
            "state = ?", arrayOf(SmsRowState.CHECKED_ABSENT.name),
        )
    }

    fun hasWork(): Boolean = readableDatabase.query(
        "pending_sms", arrayOf("external_id"), "state IN (?, ?)",
        arrayOf(SmsRowState.QUEUED.name, SmsRowState.UPLOADING.name), null, null, null, "1",
    ).use { it.moveToFirst() }

    fun setState(id: String, state: SmsRowState) {
        writableDatabase.update(
            "pending_sms", ContentValues().apply { put("state", state.name) },
            "external_id = ?", arrayOf(id),
        )
    }

    fun remove(id: String) {
        writableDatabase.delete("pending_sms", "external_id = ?", arrayOf(id))
    }

    fun counts(): Map<SmsRowState, Int> = buildMap {
        readableDatabase.rawQuery("SELECT state, COUNT(*) FROM pending_sms GROUP BY state", null)
            .use { cursor ->
                while (cursor.moveToNext()) put(SmsRowState.valueOf(cursor.getString(0)), cursor.getInt(1))
            }
    }

    private fun encrypt(id: String, text: String): ByteArray {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, key())
        cipher.updateAAD(id.toByteArray())
        return cipher.iv + cipher.doFinal(text.toByteArray())
    }

    private fun decrypt(id: String, bytes: ByteArray): String {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(128, bytes.copyOfRange(0, 12)))
        cipher.updateAAD(id.toByteArray())
        return cipher.doFinal(bytes, 12, bytes.size - 12).decodeToString()
    }

    private fun key(): SecretKey {
        val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        val alias = "pi-muse-sms-outbox"
        (store.getKey(alias, null) as? SecretKey)?.let { return it }
        return KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore").run {
            init(
                KeyGenParameterSpec.Builder(alias, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                    .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                    .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                    .build(),
            )
            generateKey()
        }
    }
}
