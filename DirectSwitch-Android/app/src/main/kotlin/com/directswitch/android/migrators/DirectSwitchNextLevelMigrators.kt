//
//  DirectSwitchNextLevelMigrators.kt
//  DirectSwitch-Android
//
//  Created by Nicolas Donati.
//  Copyright © 2026 Nicolas Donati. Tutti i diritti riservati.
//

package com.directswitch.android.migrators

import android.Manifest
import android.content.ContentUris
import android.content.ContentValues
import android.content.Context
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.CallLog
import android.provider.MediaStore
import androidx.core.content.ContextCompat
import com.directswitch.android.DirectSwitchLog
import com.directswitch.android.protocol.CallLogTransferRecord
import com.directswitch.android.protocol.DirectSwitchJson
import com.directswitch.android.protocol.ManifestItem
import com.directswitch.android.protocol.MediaTransferFilterOptions
import com.directswitch.android.protocol.TransferCategory
import kotlinx.serialization.encodeToString
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/** Filtri rapidi per Foto e Video (Ultimo anno, Album selezionati, Soglia MB video). */
object AndroidMediaFilterHelper {
    fun listPhotoAlbumNames(context: Context): List<String> {
        if (!MediaExifScannerAndImporter.hasPhotoPermission(context)) return emptyList()
        val albums = linkedSetOf<String>()
        val projection = arrayOf(MediaStore.Images.Media.BUCKET_DISPLAY_NAME)
        runCatching {
            context.contentResolver.query(
                MediaStore.Images.Media.EXTERNAL_CONTENT_URI,
                projection,
                null,
                null,
                "${MediaStore.Images.Media.DATE_MODIFIED} DESC"
            )?.use { cursor ->
                val idx = cursor.getColumnIndex(MediaStore.Images.Media.BUCKET_DISPLAY_NAME)
                if (idx >= 0) {
                    while (cursor.moveToNext()) {
                        val name = cursor.getString(idx)?.trim().orEmpty()
                        if (name.isNotEmpty()) albums.add(name)
                        if (albums.size >= 40) break
                    }
                }
            }
        }
        return albums.sortedBy { it.lowercase() }
    }

    fun matchesFilter(
        item: ManifestItem,
        options: MediaTransferFilterOptions,
        nowEpochMillis: Long = System.currentTimeMillis()
    ): Boolean {
        val oneYearCutoff = nowEpochMillis - 365L * 86_400_000L
        if (item.category == TransferCategory.PHOTOS) {
            if (options.photosLastYearOnly && item.capturedEpochMillis > 0L && item.capturedEpochMillis < oneYearCutoff) {
                return false
            }
            if (options.selectedPhotoAlbums.isNotEmpty()) {
                val allowed = options.selectedPhotoAlbums.map { it.trim().lowercase() }.toSet()
                val album = item.relativeAlbumOrFolder.trim().lowercase()
                if (album !in allowed) return false
            }
        } else if (item.category == TransferCategory.VIDEOS) {
            if (options.videosLastYearOnly && item.capturedEpochMillis > 0L && item.capturedEpochMillis < oneYearCutoff) {
                return false
            }
            if (options.maxVideoBytes > 0L && item.sizeBytes > options.maxVideoBytes) {
                return false
            }
        }
        return true
    }
}

/** Migratore Audio, Memo Vocali e Registrazioni (`MediaStore.Audio` + `Download/DirectSwitch/Audio_e_Memo`). */
object AudioAndMemoMigrator {
    fun requiredReadPermission(): String =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            Manifest.permission.READ_MEDIA_AUDIO
        } else {
            Manifest.permission.READ_EXTERNAL_STORAGE
        }

    fun hasReadPermission(context: Context): Boolean =
        ContextCompat.checkSelfPermission(context, requiredReadPermission()) == PackageManager.PERMISSION_GRANTED

    fun scanAudioAndVoiceMemos(context: Context, maxItems: Int = 3000): List<LocalMediaEntry> {
        if (!hasReadPermission(context)) return emptyList()
        val out = mutableListOf<LocalMediaEntry>()
        val projection = mutableListOf(
            MediaStore.Audio.Media._ID,
            MediaStore.Audio.Media.DISPLAY_NAME,
            MediaStore.Audio.Media.SIZE,
            MediaStore.Audio.Media.DATE_MODIFIED,
            MediaStore.Audio.Media.MIME_TYPE
        ).apply {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                add(MediaStore.Audio.Media.RELATIVE_PATH)
            }
        }.toTypedArray()

        runCatching {
            context.contentResolver.query(
                MediaStore.Audio.Media.EXTERNAL_CONTENT_URI,
                projection,
                "${MediaStore.Audio.Media.SIZE} > 0",
                null,
                "${MediaStore.Audio.Media.DATE_MODIFIED} DESC"
            )?.use { cursor ->
                val idIdx = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media._ID)
                val nameIdx = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.DISPLAY_NAME)
                val sizeIdx = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.SIZE)
                val modIdx = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.DATE_MODIFIED)
                val mimeIdx = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.MIME_TYPE)
                val relIdx = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    cursor.getColumnIndex(MediaStore.Audio.Media.RELATIVE_PATH)
                } else -1

                while (cursor.moveToNext() && out.size < maxItems) {
                    val id = cursor.getLong(idIdx)
                    val name = cursor.getString(nameIdx)?.trim().orEmpty()
                    val size = cursor.getLong(sizeIdx)
                    if (name.isEmpty() || size <= 0L) continue
                    val modMs = cursor.getLong(modIdx) * 1000L
                    val mime = cursor.getString(mimeIdx) ?: "audio/mpeg"
                    val relPath = if (relIdx >= 0) cursor.getString(relIdx)?.trim('/').orEmpty() else "Audio_e_Memo"
                    val folder = relPath.ifEmpty { "Audio_e_Memo" }
                    val uri = ContentUris.withAppendedId(MediaStore.Audio.Media.EXTERNAL_CONTENT_URI, id)
                    val item = ManifestItem(
                        id = "audio_$id",
                        category = TransferCategory.AUDIO,
                        fileName = name,
                        relativeAlbumOrFolder = folder,
                        sizeBytes = size,
                        capturedEpochMillis = modMs,
                        dedupKey = "audio_${name.lowercase()}_$size",
                        mimeType = mime
                    )
                    out.add(LocalMediaEntry(manifestItem = item, contentUri = uri))
                }
            }
        }.onFailure { DirectSwitchLog.warn("Scansione audio/memo vocali fallita", it) }
        return out
    }

    fun saveIncomingAudioFile(context: Context, item: ManifestItem, sourceFile: File): Boolean {
        val safeName = item.fileName.replace(Regex("[\\\\/:*?\"<>|]"), "_").ifBlank { "audio_${System.currentTimeMillis()}.m4a" }
        val mime = item.mimeType.takeIf { it.startsWith("audio/") } ?: "audio/mpeg"
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val savedMediaStore = runCatching {
                val values = ContentValues().apply {
                    put(MediaStore.Audio.Media.DISPLAY_NAME, safeName)
                    put(MediaStore.Audio.Media.MIME_TYPE, mime)
                    put(MediaStore.Audio.Media.RELATIVE_PATH, "${Environment.DIRECTORY_MUSIC}/DirectSwitch")
                    put(MediaStore.Audio.Media.IS_PENDING, 1)
                }
                val uri = context.contentResolver.insert(MediaStore.Audio.Media.EXTERNAL_CONTENT_URI, values)
                    ?: return@runCatching false
                context.contentResolver.openOutputStream(uri)?.use { out ->
                    sourceFile.inputStream().use { it.copyTo(out) }
                }
                values.clear()
                values.put(MediaStore.Audio.Media.IS_PENDING, 0)
                context.contentResolver.update(uri, values, null, null)
                true
            }.getOrDefault(false)
            if (savedMediaStore) return true
        }
        return runCatching {
            PublicDownloadsSaver.saveBytes(
                context = context,
                subFolder = "Audio_e_Memo",
                fileName = safeName,
                mimeType = mime,
                bytes = sourceFile.readBytes()
            )
        }.getOrDefault(false)
    }
}

/** Migratore Cronologia Chiamate (Android <-> Android nativo + archivio HTML/JSON leggibile). */
object CallLogMigrator {
    fun hasReadPermission(context: Context): Boolean =
        ContextCompat.checkSelfPermission(context, Manifest.permission.READ_CALL_LOG) == PackageManager.PERMISSION_GRANTED

    fun hasWritePermission(context: Context): Boolean =
        ContextCompat.checkSelfPermission(context, Manifest.permission.WRITE_CALL_LOG) == PackageManager.PERMISSION_GRANTED

    fun readCallLogs(context: Context, maxRecords: Int = 2000): List<CallLogTransferRecord> {
        if (!hasReadPermission(context)) return emptyList()
        val out = mutableListOf<CallLogTransferRecord>()
        val projection = arrayOf(
            CallLog.Calls._ID,
            CallLog.Calls.NUMBER,
            CallLog.Calls.CACHED_NAME,
            CallLog.Calls.TYPE,
            CallLog.Calls.DATE,
            CallLog.Calls.DURATION
        )
        runCatching {
            context.contentResolver.query(
                CallLog.Calls.CONTENT_URI,
                projection,
                null,
                null,
                "${CallLog.Calls.DATE} DESC"
            )?.use { cursor ->
                val idIdx = cursor.getColumnIndexOrThrow(CallLog.Calls._ID)
                val numIdx = cursor.getColumnIndexOrThrow(CallLog.Calls.NUMBER)
                val nameIdx = cursor.getColumnIndexOrThrow(CallLog.Calls.CACHED_NAME)
                val typeIdx = cursor.getColumnIndexOrThrow(CallLog.Calls.TYPE)
                val dateIdx = cursor.getColumnIndexOrThrow(CallLog.Calls.DATE)
                val durIdx = cursor.getColumnIndexOrThrow(CallLog.Calls.DURATION)

                while (cursor.moveToNext() && out.size < maxRecords) {
                    val number = cursor.getString(numIdx)?.trim().orEmpty()
                    if (number.isEmpty()) continue
                    out.add(
                        CallLogTransferRecord(
                            id = "call_${cursor.getLong(idIdx)}",
                            number = number,
                            cachedName = cursor.getString(nameIdx)?.trim()?.takeIf { it.isNotEmpty() },
                            callType = cursor.getInt(typeIdx),
                            dateEpochMillis = cursor.getLong(dateIdx),
                            durationSeconds = cursor.getLong(durIdx).coerceAtLeast(0L)
                        )
                    )
                }
            }
        }.onFailure { DirectSwitchLog.warn("Lettura cronologia chiamate fallita", it) }
        return out
    }

    fun importCallLogsWithArchive(context: Context, incoming: List<CallLogTransferRecord>): Int {
        if (incoming.isEmpty()) return 0

        val jsonSaved = runCatching {
            PublicDownloadsSaver.saveBytes(
                context = context,
                subFolder = "Chiamate",
                fileName = "Chiamate_DirectSwitch.json",
                mimeType = "application/json",
                bytes = DirectSwitchJson.instance.encodeToString(incoming).toByteArray(Charsets.UTF_8)
            )
        }.getOrDefault(false)

        val df = SimpleDateFormat("dd/MM/yyyy HH:mm", Locale.ITALY)
        val htmlSaved = runCatching {
            val html = buildString {
                append("<!DOCTYPE html><html lang='it'><head><meta charset='utf-8'><meta name='viewport' content='width=device-width,initial-scale=1'>")
                append("<title>Cronologia Chiamate (${incoming.size})</title>")
                append("<style>body{font-family:sans-serif;background:#f4f7f9;padding:16px}.row{background:#fff;border-radius:12px;padding:12px;margin-bottom:8px;box-shadow:0 1px 4px rgba(0,0,0,0.06)}.meta{font-size:12px;color:#007aff;font-weight:bold}</style></head><body>")
                append("<h2>Cronologia Chiamate DirectSwitch (${incoming.size})</h2>")
                for (c in incoming) {
                    val label = when (c.callType) {
                        2 -> "Effettuata"
                        3 -> "Persa"
                        5 -> "Rifiutata"
                        else -> "Ricevuta"
                    }
                    val who = (if (!c.cachedName.isNullOrBlank()) "${c.cachedName} (${c.number})" else c.number)
                        .replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
                    append("<div class='row'><div class='meta'>$label • ${df.format(Date(c.dateEpochMillis))} • ${c.durationSeconds}s</div><div>$who</div></div>")
                }
                append("</body></html>")
            }
            PublicDownloadsSaver.saveBytes(
                context = context,
                subFolder = "Chiamate",
                fileName = "Chiamate_DirectSwitch.html",
                mimeType = "text/html",
                bytes = html.toByteArray(Charsets.UTF_8)
            )
        }.getOrDefault(false)

        if (!hasWritePermission(context)) {
            return if (jsonSaved || htmlSaved) incoming.size else 0
        }

        val existingKeys = readCallLogs(context, maxRecords = 5000)
            .map { "${it.number}_${it.dateEpochMillis}_${it.callType}" }
            .toHashSet()
        var inserted = 0
        for (c in incoming) {
            val key = "${c.number}_${c.dateEpochMillis}_${c.callType}"
            if (key in existingKeys) continue
            runCatching {
                val values = ContentValues().apply {
                    put(CallLog.Calls.NUMBER, c.number)
                    put(CallLog.Calls.TYPE, c.callType)
                    put(CallLog.Calls.DATE, c.dateEpochMillis)
                    put(CallLog.Calls.DURATION, c.durationSeconds)
                    if (!c.cachedName.isNullOrBlank()) {
                        put(CallLog.Calls.CACHED_NAME, c.cachedName)
                    }
                    put(CallLog.Calls.NEW, 0)
                }
                if (context.contentResolver.insert(CallLog.Calls.CONTENT_URI, values) != null) {
                    inserted++
                    existingKeys.add(key)
                }
            }
        }
        return if (inserted > 0) inserted else if (jsonSaved || htmlSaved) incoming.size else 0
    }
}
