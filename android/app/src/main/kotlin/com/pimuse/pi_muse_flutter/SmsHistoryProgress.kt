package com.pimuse.pi_muse_flutter

import android.content.ContentValues
import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper
import java.util.UUID

// 只记录本次进度、稳定散列和回执身份。短信原文始终留在系统短信库。
internal class SmsHistoryProgress(context: Context) : SQLiteOpenHelper(
    context.applicationContext, "sms-history.db", null, 1,
) {
    override fun onCreate(db: SQLiteDatabase) {
        db.execSQL("CREATE TABLE progress (id INTEGER PRIMARY KEY, origin TEXT NOT NULL, checkpoint TEXT NOT NULL)")
        db.execSQL("CREATE TABLE confirmed (external_id TEXT PRIMARY KEY NOT NULL)")
        db.execSQL("CREATE TABLE installation (id INTEGER PRIMARY KEY, value TEXT NOT NULL)")
    }

    override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) = Unit

    fun installation(): String {
        val db = writableDatabase
        return db.rawQuery("SELECT value FROM installation WHERE id = 1", null).use { cursor ->
            if (cursor.moveToFirst()) cursor.getString(0) else null
        } ?: UUID.randomUUID().toString().also { value ->
            db.execSQL("INSERT INTO installation (id, value) VALUES (1, ?)", arrayOf(value))
        }
    }

    fun restore(origin: String): HistoryCheckpoint = readableDatabase.rawQuery(
        "SELECT origin, checkpoint FROM progress WHERE id = 1", null,
    ).use { cursor ->
        if (!cursor.moveToFirst()) return HistoryCheckpoint()
        HistoryCheckpoint.decode(cursor.getString(1)).forConnection(cursor.getString(0) == origin)
    }

    fun wasConfirmed(externalId: String): Boolean = readableDatabase.rawQuery(
        "SELECT 1 FROM confirmed WHERE external_id = ?", arrayOf(externalId),
    ).use { it.moveToFirst() }

    fun save(origin: String, checkpoint: HistoryCheckpoint, confirmed: List<String>) {
        val db = writableDatabase
        db.beginTransaction()
        try {
            db.insertWithOnConflict("progress", null, ContentValues().apply {
                put("id", 1)
                put("origin", origin)
                put("checkpoint", checkpoint.encode())
            }, SQLiteDatabase.CONFLICT_REPLACE).also { check(it != -1L) }
            if (confirmed.isNotEmpty()) db.compileStatement(
                "INSERT OR IGNORE INTO confirmed (external_id) VALUES (?)",
            ).use { statement ->
                for (externalId in confirmed) {
                    statement.bindString(1, externalId)
                    statement.executeInsert()
                }
            }
            db.setTransactionSuccessful()
        } finally {
            db.endTransaction()
        }
    }
}
