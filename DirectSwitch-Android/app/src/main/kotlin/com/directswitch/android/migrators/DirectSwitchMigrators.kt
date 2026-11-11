//
//  DirectSwitchMigrators.kt
//  DirectSwitch-Android
//
//  Created by Nicolas Donati.
//  Copyright © 2026 Nicolas Donati. Tutti i diritti riservati.
//

package com.directswitch.android.migrators

import android.Manifest
import android.app.role.RoleManager
import android.content.ContentProviderOperation
import android.content.ContentUris
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.media.MediaScannerConnection
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.StatFs
import android.provider.CalendarContract
import android.provider.ContactsContract
import android.provider.MediaStore
import android.provider.OpenableColumns
import android.provider.Settings
import android.provider.Telephony
import androidx.core.content.ContextCompat
import com.directswitch.android.DirectSwitchLog
import com.directswitch.android.protocol.CalendarEventRecord
import com.directswitch.android.protocol.ContactTransferRecord
import com.directswitch.android.protocol.DirectSwitchJson
import com.directswitch.android.protocol.ManifestItem
import com.directswitch.android.protocol.PhoneNormalizer
import com.directswitch.android.protocol.SmsTransferRecord
import com.directswitch.android.protocol.TransferCategory
import kotlinx.serialization.encodeToString
import java.io.ByteArrayInputStream
import java.io.File
import java.io.InputStream
import java.util.TimeZone

/** Riepilogo dei contenuti rilevati localmente sul dispositivo prima del trasferimento. */
data class LocalDeviceScanSummary(
    val contactsCount: Int,
    val photosCount: Int,
    val photosBytes: Long,
    val videosCount: Int,
    val videosBytes: Long,
    val calendarEventsCount: Int,
    val smsCount: Int,
    val documentsCount: Int = 0,
    val whatsappArchivesCount: Int = 0,
    val freeStorageBytes: Long,
    val totalStorageBytes: Long
)

/** Calcola spazio libero e totale sul volume dati del dispositivo. */
object StorageCapacityChecker {
    fun getFreeAndTotalBytes(context: Context): Pair<Long, Long> {
        return try {
            val stat = StatFs(context.filesDir.absolutePath)
            stat.availableBytes to stat.totalBytes
        } catch (_: Throwable) {
            val fallback = StatFs(Environment.getDataDirectory().absolutePath)
            fallback.availableBytes to fallback.totalBytes
        }
    }
}

/** Gestisce lo stato locale del Pass Cross-OS Pro e il rilevamento informativo di CloudSave. */
object CloudSaveEntitlementDetector {
    private const val PREFS_NAME = "directswitch_license_prefs"
    private const val KEY_PRO_UNLOCKED = "cross_os_pro_unlocked"

    fun isLocalProUnlocked(context: Context): Boolean {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        return prefs.getBoolean(KEY_PRO_UNLOCKED, true)
    }

    fun setLocalProUnlocked(context: Context, unlocked: Boolean) {
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .putBoolean(KEY_PRO_UNLOCKED, unlocked)
            .apply()
    }

    /**
     * Solo per il cross-sell nell'interfaccia: l'installazione di CloudSave NON equivale
     * a un abbonamento CloudSave Pro e quindi NON sblocca il Pass Cross-OS.
     */
    fun isCloudSaveInstalled(context: Context): Boolean {
        return try {
            context.packageManager.getPackageInfo("com.cloudsave.android", 0)
            true
        } catch (_: PackageManager.NameNotFoundException) {
            false
        }
    }

    /**
     * Abbonamento CloudSave Pro verificato. Finché non esiste una verifica firmata lato server
     * restituisce sempre `false`, per non concedere lo sblocco senza ricevuta verificata.
     */
    @Suppress("UNUSED_PARAMETER")
    fun hasVerifiedCloudSaveProEntitlement(context: Context): Boolean = false
}

/**
 * Salva documenti ricevuti, esportazioni WhatsApp e archivi SMS nella cartella PUBBLICA
 * `Download/DirectSwitch/<subFolder>` tramite `MediaStore.Downloads` (Android 10–16, zero permessi extra)
 * o su `Environment.DIRECTORY_DOWNLOADS` con scansione media su Android 8–9.
 *
 * A differenza di `getExternalFilesDir` (`/Android/data/...`, nascosto su Android 11+), i file salvati
 * qui compaiono immediatamente nell'app "File" / "Download" di sistema senza mai sovrascrivere omonimi.
 */
object PublicDownloadsSaver {
    fun saveBytes(
        context: Context,
        subFolder: String,
        fileName: String,
        mimeType: String,
        bytes: ByteArray
    ): Boolean = ByteArrayInputStream(bytes).use { stream ->
        saveStream(context, subFolder, fileName, mimeType, stream)
    }

    fun saveStream(
        context: Context,
        subFolder: String,
        fileName: String,
        mimeType: String,
        inputStream: InputStream
    ): Boolean {
        return try {
            val safeSub = subFolder
                .replace(Regex("[^a-zA-Z0-9 _-]"), "")
                .trim()
                .ifEmpty { "Documenti" }
            val safeName = File(fileName).name
                .replace(Regex("[\\\\/:*?\"<>|]"), "_")
                .ifBlank { "file_${System.currentTimeMillis()}" }

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                val resolver = context.contentResolver
                val relPath = "${Environment.DIRECTORY_DOWNLOADS}/DirectSwitch/$safeSub"
                val values = ContentValues().apply {
                    put(MediaStore.MediaColumns.DISPLAY_NAME, safeName)
                    put(MediaStore.MediaColumns.MIME_TYPE, mimeType)
                    put(MediaStore.MediaColumns.RELATIVE_PATH, relPath)
                    put(MediaStore.MediaColumns.IS_PENDING, 1)
                }
                val uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values) ?: return false
                val written = resolver.openOutputStream(uri)?.use { out ->
                    inputStream.copyTo(out, bufferSize = 256 * 1024)
                    true
                } ?: false
                if (!written) {
                    resolver.delete(uri, null, null)
                    return false
                }
                val done = ContentValues().apply {
                    put(MediaStore.MediaColumns.IS_PENDING, 0)
                }
                resolver.update(uri, done, null, null)
                true
            } else {
                @Suppress("DEPRECATION")
                val downloadsRoot = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
                val targetDir = File(File(downloadsRoot, "DirectSwitch"), safeSub)
                if (!targetDir.exists() && !targetDir.mkdirs()) return false
                val destFile = uniqueDestinationFile(targetDir, safeName)
                destFile.outputStream().use { out ->
                    inputStream.copyTo(out, bufferSize = 256 * 1024)
                }
                MediaScannerConnection.scanFile(
                    context,
                    arrayOf(destFile.absolutePath),
                    arrayOf(mimeType),
                    null
                )
                true
            }
        } catch (t: Throwable) {
            DirectSwitchLog.warn("Salvataggio in Download/DirectSwitch fallito", t)
            false
        }
    }

    private fun uniqueDestinationFile(dir: File, fileName: String): File {
        var candidate = File(dir, fileName)
        if (!candidate.exists()) return candidate
        val dot = fileName.lastIndexOf('.')
        val base = if (dot > 0) fileName.substring(0, dot) else fileName
        val ext = if (dot > 0) fileName.substring(dot) else ""
        var counter = 1
        while (candidate.exists()) {
            candidate = File(dir, "${base}_($counter)$ext")
            counter++
        }
        return candidate
    }
}

/**
 * Motore Contatti con Smart Merge E.164: legge la rubrica e unisce i contatti in arrivo
 * senza MAI generare doppioni su un telefono già configurato.
 */
object ContactsSmartMerger {

    fun hasReadPermission(context: Context): Boolean =
        ContextCompat.checkSelfPermission(context, Manifest.permission.READ_CONTACTS) == PackageManager.PERMISSION_GRANTED

    fun hasWritePermission(context: Context): Boolean =
        ContextCompat.checkSelfPermission(context, Manifest.permission.WRITE_CONTACTS) == PackageManager.PERMISSION_GRANTED

    fun readAllContacts(context: Context): List<ContactTransferRecord> {
        if (!hasReadPermission(context)) return emptyList()
        val resolver = context.contentResolver
        val namesById = LinkedHashMap<String, String>()
        val phonesById = HashMap<String, MutableList<String>>()
        val emailsById = HashMap<String, MutableList<String>>()

        resolver.query(
            ContactsContract.Contacts.CONTENT_URI,
            arrayOf(ContactsContract.Contacts._ID, ContactsContract.Contacts.DISPLAY_NAME_PRIMARY),
            null,
            null,
            "${ContactsContract.Contacts.DISPLAY_NAME_PRIMARY} ASC"
        )?.use { cursor ->
            val idIdx = cursor.getColumnIndexOrThrow(ContactsContract.Contacts._ID)
            val nameIdx = cursor.getColumnIndexOrThrow(ContactsContract.Contacts.DISPLAY_NAME_PRIMARY)
            while (cursor.moveToNext()) {
                val id = cursor.getString(idIdx) ?: continue
                val name = cursor.getString(nameIdx)?.trim().orEmpty()
                if (name.isNotEmpty()) {
                    namesById[id] = name
                }
            }
        }

        resolver.query(
            ContactsContract.CommonDataKinds.Phone.CONTENT_URI,
            arrayOf(
                ContactsContract.CommonDataKinds.Phone.CONTACT_ID,
                ContactsContract.CommonDataKinds.Phone.NUMBER
            ),
            null,
            null,
            null
        )?.use { cursor ->
            val idIdx = cursor.getColumnIndexOrThrow(ContactsContract.CommonDataKinds.Phone.CONTACT_ID)
            val numIdx = cursor.getColumnIndexOrThrow(ContactsContract.CommonDataKinds.Phone.NUMBER)
            while (cursor.moveToNext()) {
                val id = cursor.getString(idIdx) ?: continue
                val num = cursor.getString(numIdx)?.trim().orEmpty()
                if (num.isNotEmpty()) {
                    phonesById.getOrPut(id) { mutableListOf() }.add(num)
                }
            }
        }

        resolver.query(
            ContactsContract.CommonDataKinds.Email.CONTENT_URI,
            arrayOf(
                ContactsContract.CommonDataKinds.Email.CONTACT_ID,
                ContactsContract.CommonDataKinds.Email.ADDRESS
            ),
            null,
            null,
            null
        )?.use { cursor ->
            val idIdx = cursor.getColumnIndexOrThrow(ContactsContract.CommonDataKinds.Email.CONTACT_ID)
            val emailIdx = cursor.getColumnIndexOrThrow(ContactsContract.CommonDataKinds.Email.ADDRESS)
            while (cursor.moveToNext()) {
                val id = cursor.getString(idIdx) ?: continue
                val mail = cursor.getString(emailIdx)?.trim().orEmpty()
                if (mail.isNotEmpty()) {
                    emailsById.getOrPut(id) { mutableListOf() }.add(mail)
                }
            }
        }

        return namesById.mapNotNull { (id, name) ->
            val phones = phonesById[id]?.distinct().orEmpty()
            val emails = emailsById[id]?.distinct().orEmpty()
            if (phones.isEmpty() && emails.isEmpty()) null
            else ContactTransferRecord(
                id = id,
                displayName = name,
                phones = phones,
                emails = emails
            )
        }
    }

    /**
     * Inserisce solo i contatti non ancora presenti (confronto per numero normalizzato E.164 o email).
     * Restituisce `Pair(inseriti, duplicatiSaltati)`.
     */
    fun mergeIncomingContacts(
        context: Context,
        incoming: List<ContactTransferRecord>
    ): Pair<Int, Int> {
        if (!hasWritePermission(context) || incoming.isEmpty()) return 0 to 0

        val existing = readAllContacts(context)
        val existingPhoneKeys = existing
            .flatMap { it.phones }
            .map { PhoneNormalizer.normalizeKey(it) }
            .filter { it.isNotEmpty() }
            .toHashSet()
        val existingEmails = existing
            .flatMap { it.emails }
            .map { it.lowercase() }
            .toHashSet()

        var inserted = 0
        var skipped = 0

        for (contact in incoming) {
            val normalizedPhones = contact.phones
                .map { PhoneNormalizer.normalizeKey(it) }
                .filter { it.isNotEmpty() }
            val normalizedEmails = contact.emails.map { it.lowercase() }

            val alreadyExists = normalizedPhones.any { it in existingPhoneKeys } ||
                normalizedEmails.any { it in existingEmails }

            if (alreadyExists) {
                skipped++
                continue
            }

            if (insertSingleContact(context, contact)) {
                inserted++
                existingPhoneKeys.addAll(normalizedPhones)
                existingEmails.addAll(normalizedEmails)
            }
        }
        return inserted to skipped
    }

    private fun insertSingleContact(context: Context, record: ContactTransferRecord): Boolean {
        return try {
            val ops = ArrayList<ContentProviderOperation>()
            ops.add(
                ContentProviderOperation.newInsert(ContactsContract.RawContacts.CONTENT_URI)
                    .withValue(ContactsContract.RawContacts.ACCOUNT_TYPE, null)
                    .withValue(ContactsContract.RawContacts.ACCOUNT_NAME, null)
                    .build()
            )
            ops.add(
                ContentProviderOperation.newInsert(ContactsContract.Data.CONTENT_URI)
                    .withValueBackReference(ContactsContract.Data.RAW_CONTACT_ID, 0)
                    .withValue(
                        ContactsContract.Data.MIMETYPE,
                        ContactsContract.CommonDataKinds.StructuredName.CONTENT_ITEM_TYPE
                    )
                    .withValue(ContactsContract.CommonDataKinds.StructuredName.DISPLAY_NAME, record.displayName)
                    .build()
            )
            for (phone in record.phones) {
                ops.add(
                    ContentProviderOperation.newInsert(ContactsContract.Data.CONTENT_URI)
                        .withValueBackReference(ContactsContract.Data.RAW_CONTACT_ID, 0)
                        .withValue(
                            ContactsContract.Data.MIMETYPE,
                            ContactsContract.CommonDataKinds.Phone.CONTENT_ITEM_TYPE
                        )
                        .withValue(ContactsContract.CommonDataKinds.Phone.NUMBER, phone)
                        .withValue(
                            ContactsContract.CommonDataKinds.Phone.TYPE,
                            ContactsContract.CommonDataKinds.Phone.TYPE_MOBILE
                        )
                        .build()
                )
            }
            for (email in record.emails) {
                ops.add(
                    ContentProviderOperation.newInsert(ContactsContract.Data.CONTENT_URI)
                        .withValueBackReference(ContactsContract.Data.RAW_CONTACT_ID, 0)
                        .withValue(
                            ContactsContract.Data.MIMETYPE,
                            ContactsContract.CommonDataKinds.Email.CONTENT_ITEM_TYPE
                        )
                        .withValue(ContactsContract.CommonDataKinds.Email.ADDRESS, email)
                        .withValue(
                            ContactsContract.CommonDataKinds.Email.TYPE,
                            ContactsContract.CommonDataKinds.Email.TYPE_OTHER
                        )
                        .build()
                )
            }
            context.contentResolver.applyBatch(ContactsContract.AUTHORITY, ops)
            true
        } catch (t: Throwable) {
            DirectSwitchLog.warn("Import contatto fallito", t)
            false
        }
    }
}

/** Elemento locale pronto per l'invio streaming cifrato (Media, Documento o Vault WhatsApp). */
data class LocalMediaEntry(
    val manifestItem: ManifestItem,
    val contentUri: Uri
)

/**
 * Scanner e Importatore Media (Foto & Video HD/4K) con preservazione data di scatto, Album e anti-duplicati.
 */
object MediaExifScannerAndImporter {

    fun hasPhotoPermission(context: Context): Boolean =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            ContextCompat.checkSelfPermission(context, Manifest.permission.READ_MEDIA_IMAGES) == PackageManager.PERMISSION_GRANTED
        } else {
            ContextCompat.checkSelfPermission(context, Manifest.permission.READ_EXTERNAL_STORAGE) == PackageManager.PERMISSION_GRANTED
        }

    fun hasVideoPermission(context: Context): Boolean =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            ContextCompat.checkSelfPermission(context, Manifest.permission.READ_MEDIA_VIDEO) == PackageManager.PERMISSION_GRANTED
        } else {
            ContextCompat.checkSelfPermission(context, Manifest.permission.READ_EXTERNAL_STORAGE) == PackageManager.PERMISSION_GRANTED
        }

    fun hasMediaPermissions(context: Context): Boolean =
        hasPhotoPermission(context) || hasVideoPermission(context)

    fun scanMediaEntries(
        context: Context,
        includePhotos: Boolean = true,
        includeVideos: Boolean = true
    ): List<LocalMediaEntry> {
        val entries = mutableListOf<LocalMediaEntry>()
        if (includePhotos && hasPhotoPermission(context)) {
            entries.addAll(queryCollection(context, MediaStore.Images.Media.EXTERNAL_CONTENT_URI, TransferCategory.PHOTOS))
        }
        if (includeVideos && hasVideoPermission(context)) {
            entries.addAll(queryCollection(context, MediaStore.Video.Media.EXTERNAL_CONTENT_URI, TransferCategory.VIDEOS))
        }
        return entries
    }

    private fun queryCollection(
        context: Context,
        collectionUri: Uri,
        category: TransferCategory
    ): List<LocalMediaEntry> {
        val out = mutableListOf<LocalMediaEntry>()
        val projection = arrayOf(
            MediaStore.MediaColumns._ID,
            MediaStore.MediaColumns.DISPLAY_NAME,
            MediaStore.MediaColumns.SIZE,
            MediaStore.MediaColumns.DATE_TAKEN,
            MediaStore.MediaColumns.BUCKET_DISPLAY_NAME,
            MediaStore.MediaColumns.MIME_TYPE
        )
        try {
            context.contentResolver.query(
                collectionUri,
                projection,
                null,
                null,
                "${MediaStore.MediaColumns.DATE_TAKEN} DESC"
            )?.use { cursor ->
                val idCol = cursor.getColumnIndexOrThrow(MediaStore.MediaColumns._ID)
                val nameCol = cursor.getColumnIndexOrThrow(MediaStore.MediaColumns.DISPLAY_NAME)
                val sizeCol = cursor.getColumnIndexOrThrow(MediaStore.MediaColumns.SIZE)
                val dateCol = cursor.getColumnIndexOrThrow(MediaStore.MediaColumns.DATE_TAKEN)
                val bucketCol = cursor.getColumnIndexOrThrow(MediaStore.MediaColumns.BUCKET_DISPLAY_NAME)
                val mimeCol = cursor.getColumnIndexOrThrow(MediaStore.MediaColumns.MIME_TYPE)

                while (cursor.moveToNext()) {
                    val id = cursor.getLong(idCol)
                    val name = cursor.getString(nameCol) ?: "media_$id"
                    val size = cursor.getLong(sizeCol)
                    if (size <= 0L) continue
                    val dateTaken = cursor.getLong(dateCol)
                    val album = cursor.getString(bucketCol) ?: "Camera"
                    val mime = cursor.getString(mimeCol)
                        ?: if (category == TransferCategory.VIDEOS) "video/mp4" else "image/jpeg"
                    val contentUri = ContentUris.withAppendedId(collectionUri, id)
                    val dedupKey = "${name.lowercase()}_${size}_$dateTaken"

                    out.add(
                        LocalMediaEntry(
                            manifestItem = ManifestItem(
                                id = "${category.name.lowercase()}_$id",
                                category = category,
                                fileName = name,
                                relativeAlbumOrFolder = album,
                                sizeBytes = size,
                                capturedEpochMillis = dateTaken,
                                dedupKey = dedupKey,
                                mimeType = mime
                            ),
                            contentUri = contentUri
                        )
                    )
                }
            }
        } catch (t: Throwable) {
            DirectSwitchLog.warn("Scansione collezione media fallita", t)
        }
        return out
    }

    fun buildExistingDedupKeys(context: Context): Set<String> {
        return scanMediaEntries(context, includePhotos = true, includeVideos = true)
            .map { it.manifestItem.dedupKey }
            .toHashSet()
    }

    fun importMediaStream(
        context: Context,
        item: ManifestItem,
        plainInputStream: InputStream
    ): Boolean {
        return try {
            val resolver = context.contentResolver
            val isVideo = item.category == TransferCategory.VIDEOS
            val safeAlbum = item.relativeAlbumOrFolder
                .replace(Regex("[^a-zA-Z0-9 _-]"), "")
                .trim()
                .ifEmpty { "DirectSwitch" }

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                val baseRelPath = if (isVideo) {
                    "${Environment.DIRECTORY_MOVIES}/DirectSwitch/$safeAlbum"
                } else {
                    "${Environment.DIRECTORY_PICTURES}/DirectSwitch/$safeAlbum"
                }
                val collection = if (isVideo) {
                    MediaStore.Video.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
                } else {
                    MediaStore.Images.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
                }
                val values = ContentValues().apply {
                    put(MediaStore.MediaColumns.DISPLAY_NAME, item.fileName)
                    put(MediaStore.MediaColumns.MIME_TYPE, item.mimeType)
                    put(MediaStore.MediaColumns.RELATIVE_PATH, baseRelPath)
                    if (item.capturedEpochMillis > 0L) {
                        put(MediaStore.MediaColumns.DATE_TAKEN, item.capturedEpochMillis)
                    }
                    put(MediaStore.MediaColumns.IS_PENDING, 1)
                }
                val uri = resolver.insert(collection, values) ?: return false
                val ok = resolver.openOutputStream(uri)?.use { out ->
                    plainInputStream.copyTo(out, bufferSize = 256 * 1024)
                    true
                } ?: false
                if (!ok) {
                    resolver.delete(uri, null, null)
                    return false
                }
                val doneValues = ContentValues().apply {
                    put(MediaStore.MediaColumns.IS_PENDING, 0)
                }
                resolver.update(uri, doneValues, null, null)
                true
            } else {
                @Suppress("DEPRECATION")
                val publicRoot = Environment.getExternalStoragePublicDirectory(
                    if (isVideo) Environment.DIRECTORY_MOVIES else Environment.DIRECTORY_PICTURES
                )
                val albumDir = File(File(publicRoot, "DirectSwitch"), safeAlbum)
                albumDir.mkdirs()
                val destFile = File(albumDir, item.fileName)
                destFile.outputStream().use { out ->
                    plainInputStream.copyTo(out, bufferSize = 256 * 1024)
                }
                if (item.capturedEpochMillis > 0L) {
                    destFile.setLastModified(item.capturedEpochMillis)
                }
                MediaScannerConnection.scanFile(
                    context,
                    arrayOf(destFile.absolutePath),
                    arrayOf(item.mimeType),
                    null
                )
                true
            }
        } catch (t: Throwable) {
            DirectSwitchLog.warn("Import media fallito", t)
            false
        }
    }
}

/** Migrazione e deduplicazione degli eventi del Calendario (`CalendarContract`). */
object CalendarMigrator {
    fun hasReadPermission(context: Context): Boolean =
        ContextCompat.checkSelfPermission(context, Manifest.permission.READ_CALENDAR) == PackageManager.PERMISSION_GRANTED

    fun hasWritePermission(context: Context): Boolean =
        ContextCompat.checkSelfPermission(context, Manifest.permission.WRITE_CALENDAR) == PackageManager.PERMISSION_GRANTED

    fun readEvents(context: Context): List<CalendarEventRecord> {
        if (!hasReadPermission(context)) return emptyList()
        val out = mutableListOf<CalendarEventRecord>()
        val projection = arrayOf(
            CalendarContract.Events._ID,
            CalendarContract.Events.TITLE,
            CalendarContract.Events.DESCRIPTION,
            CalendarContract.Events.EVENT_LOCATION,
            CalendarContract.Events.DTSTART,
            CalendarContract.Events.DTEND,
            CalendarContract.Events.ALL_DAY,
            CalendarContract.Events.RRULE
        )
        try {
            context.contentResolver.query(
                CalendarContract.Events.CONTENT_URI,
                projection,
                "${CalendarContract.Events.DELETED} = 0",
                null,
                "${CalendarContract.Events.DTSTART} DESC"
            )?.use { cursor ->
                val idIdx = cursor.getColumnIndexOrThrow(CalendarContract.Events._ID)
                val titleIdx = cursor.getColumnIndexOrThrow(CalendarContract.Events.TITLE)
                val descIdx = cursor.getColumnIndexOrThrow(CalendarContract.Events.DESCRIPTION)
                val locIdx = cursor.getColumnIndexOrThrow(CalendarContract.Events.EVENT_LOCATION)
                val startIdx = cursor.getColumnIndexOrThrow(CalendarContract.Events.DTSTART)
                val endIdx = cursor.getColumnIndexOrThrow(CalendarContract.Events.DTEND)
                val allDayIdx = cursor.getColumnIndexOrThrow(CalendarContract.Events.ALL_DAY)
                val rruleIdx = cursor.getColumnIndexOrThrow(CalendarContract.Events.RRULE)

                while (cursor.moveToNext()) {
                    val id = cursor.getLong(idIdx).toString()
                    val title = cursor.getString(titleIdx)?.trim().orEmpty()
                    if (title.isEmpty()) continue
                    val dtStart = cursor.getLong(startIdx)
                    val dtEnd = cursor.getLong(endIdx).let { if (it > 0L) it else dtStart + 3_600_000L }
                    out.add(
                        CalendarEventRecord(
                            id = id,
                            title = title,
                            description = cursor.getString(descIdx),
                            location = cursor.getString(locIdx),
                            startEpochMillis = dtStart,
                            endEpochMillis = dtEnd,
                            allDay = cursor.getInt(allDayIdx) == 1,
                            rrule = cursor.getString(rruleIdx)
                        )
                    )
                }
            }
        } catch (t: Throwable) {
            DirectSwitchLog.warn("Lettura calendario fallita", t)
        }
        return out
    }

    fun importEventsDeduplicated(context: Context, incoming: List<CalendarEventRecord>): Int {
        if (!hasWritePermission(context) || incoming.isEmpty()) return 0
        val primaryCalId = findWritableCalendarId(context) ?: return 0
        val existingKeys = readEvents(context)
            .map { "${it.title.lowercase()}_${it.startEpochMillis}" }
            .toHashSet()

        var imported = 0
        for (ev in incoming) {
            val key = "${ev.title.lowercase()}_${ev.startEpochMillis}"
            if (key in existingKeys) continue
            try {
                val values = ContentValues().apply {
                    put(CalendarContract.Events.CALENDAR_ID, primaryCalId)
                    put(CalendarContract.Events.TITLE, ev.title)
                    put(CalendarContract.Events.DESCRIPTION, ev.description)
                    put(CalendarContract.Events.EVENT_LOCATION, ev.location)
                    put(CalendarContract.Events.DTSTART, ev.startEpochMillis)
                    put(CalendarContract.Events.DTEND, ev.endEpochMillis)
                    put(CalendarContract.Events.ALL_DAY, if (ev.allDay) 1 else 0)
                    put(CalendarContract.Events.EVENT_TIMEZONE, TimeZone.getDefault().id)
                    if (!ev.rrule.isNullOrBlank()) {
                        put(CalendarContract.Events.RRULE, ev.rrule)
                    }
                }
                if (context.contentResolver.insert(CalendarContract.Events.CONTENT_URI, values) != null) {
                    imported++
                    existingKeys.add(key)
                }
            } catch (t: Throwable) {
                DirectSwitchLog.warn("Inserimento evento calendario fallito", t)
            }
        }
        return imported
    }

    private fun findWritableCalendarId(context: Context): Long? {
        context.contentResolver.query(
            CalendarContract.Calendars.CONTENT_URI,
            arrayOf(CalendarContract.Calendars._ID, CalendarContract.Calendars.CALENDAR_ACCESS_LEVEL),
            "${CalendarContract.Calendars.CALENDAR_ACCESS_LEVEL} >= ?",
            arrayOf(CalendarContract.Calendars.CAL_ACCESS_CONTRIBUTOR.toString()),
            null
        )?.use { cursor ->
            if (cursor.moveToFirst()) {
                return cursor.getLong(0)
            }
        }
        return null
    }
}

/**
 * Scanner e Importatore SMS di sistema:
 * - Memorizza il pacchetto dell'app Messaggi predefinita precedente prima di richiedere `ROLE_SMS`,
 *   così a fine trasferimento l'utente la ripristina con 1 tocco.
 * - Esporta sempre una copia consultabile JSON + HTML nella cartella pubblica `Download/DirectSwitch/SMS_Archivio`.
 */
object SmsSystemScanner {
    private const val SMS_PREFS = "directswitch_sms_role_prefs"
    private const val KEY_PREV_SMS_PKG = "previous_default_sms_pkg"

    fun hasReadPermission(context: Context): Boolean =
        ContextCompat.checkSelfPermission(context, Manifest.permission.READ_SMS) == PackageManager.PERMISSION_GRANTED

    fun isDefaultSmsApp(context: Context): Boolean {
        return try {
            Telephony.Sms.getDefaultSmsPackage(context) == context.packageName
        } catch (_: Throwable) {
            false
        }
    }

    /** Salva il pacchetto dell'attuale app SMS predefinita prima di acquisire `ROLE_SMS`. */
    fun rememberPreviousDefaultSmsPackage(context: Context) {
        try {
            val current = Telephony.Sms.getDefaultSmsPackage(context)
            if (!current.isNullOrBlank() && current != context.packageName) {
                context.getSharedPreferences(SMS_PREFS, Context.MODE_PRIVATE)
                    .edit()
                    .putString(KEY_PREV_SMS_PKG, current)
                    .apply()
            }
        } catch (_: Throwable) {
        }
    }

    fun createDefaultSmsRoleIntent(context: Context): Intent? {
        rememberPreviousDefaultSmsPackage(context)
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                val roleManager = context.getSystemService(RoleManager::class.java)
                if (roleManager != null && roleManager.isRoleAvailable(RoleManager.ROLE_SMS)) {
                    roleManager.createRequestRoleIntent(RoleManager.ROLE_SMS)
                } else null
            } else {
                Intent(Telephony.Sms.Intents.ACTION_CHANGE_DEFAULT).apply {
                    putExtra(Telephony.Sms.Intents.EXTRA_PACKAGE_NAME, context.packageName)
                }
            }
        } catch (t: Throwable) {
            DirectSwitchLog.warn("Intent ruolo SMS non creato", t)
            null
        }
    }

    /**
     * Crea l'Intent per restituire il ruolo di app SMS predefinita all'app Messaggi originale dell'utente
     * (es. Google Messaggi o Samsung Messaggi) al termine dell'importazione.
     */
    fun createRestorePreviousSmsAppIntent(context: Context): Intent {
        val saved = context.getSharedPreferences(SMS_PREFS, Context.MODE_PRIVATE)
            .getString(KEY_PREV_SMS_PKG, null)
        val fallbackPkg = saved
            ?: listOf("com.google.android.apps.messaging", "com.samsung.android.messaging")
                .firstOrNull { pkg ->
                    runCatching { context.packageManager.getPackageInfo(pkg, 0); true }.getOrDefault(false)
                }
        return if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q && !fallbackPkg.isNullOrBlank()) {
            Intent(Telephony.Sms.Intents.ACTION_CHANGE_DEFAULT).apply {
                putExtra(Telephony.Sms.Intents.EXTRA_PACKAGE_NAME, fallbackPkg)
            }
        } else {
            Intent(Settings.ACTION_MANAGE_DEFAULT_APPS_SETTINGS)
        }
    }

    fun countSms(context: Context): Int {
        if (!hasReadPermission(context)) return 0
        return try {
            context.contentResolver.query(
                Telephony.Sms.CONTENT_URI,
                arrayOf(Telephony.Sms._ID),
                null,
                null,
                null
            )?.use { it.count } ?: 0
        } catch (t: Throwable) {
            DirectSwitchLog.warn("Conteggio SMS fallito", t)
            0
        }
    }

    fun readAllSms(context: Context, maxMessages: Int = 5000): List<SmsTransferRecord> {
        if (!hasReadPermission(context)) return emptyList()
        val out = mutableListOf<SmsTransferRecord>()
        val projection = arrayOf(
            Telephony.Sms._ID,
            Telephony.Sms.ADDRESS,
            Telephony.Sms.BODY,
            Telephony.Sms.DATE,
            Telephony.Sms.TYPE
        )
        try {
            context.contentResolver.query(
                Telephony.Sms.CONTENT_URI,
                projection,
                null,
                null,
                "${Telephony.Sms.DATE} DESC"
            )?.use { cursor ->
                val idIdx = cursor.getColumnIndexOrThrow(Telephony.Sms._ID)
                val addrIdx = cursor.getColumnIndexOrThrow(Telephony.Sms.ADDRESS)
                val bodyIdx = cursor.getColumnIndexOrThrow(Telephony.Sms.BODY)
                val dateIdx = cursor.getColumnIndexOrThrow(Telephony.Sms.DATE)
                val typeIdx = cursor.getColumnIndexOrThrow(Telephony.Sms.TYPE)

                while (cursor.moveToNext() && out.size < maxMessages) {
                    val address = cursor.getString(addrIdx)?.trim().orEmpty()
                    val body = cursor.getString(bodyIdx).orEmpty()
                    if (address.isEmpty() && body.isEmpty()) continue
                    out.add(
                        SmsTransferRecord(
                            id = cursor.getLong(idIdx).toString(),
                            address = address.ifEmpty { "Sconosciuto" },
                            body = body,
                            dateEpochMillis = cursor.getLong(dateIdx),
                            messageType = cursor.getInt(typeIdx)
                        )
                    )
                }
            }
        } catch (t: Throwable) {
            DirectSwitchLog.warn("Lettura SMS fallita", t)
        }
        return out
    }

    fun importSmsIntoSystemOrArchive(context: Context, incoming: List<SmsTransferRecord>): Int {
        if (incoming.isEmpty()) return 0

        var archiveOk = false
        try {
            val jsonBytes = DirectSwitchJson.instance.encodeToString(incoming).toByteArray(Charsets.UTF_8)
            val jsonSaved = PublicDownloadsSaver.saveBytes(
                context = context,
                subFolder = "SMS_Archivio",
                fileName = "SMS_Archivio_DirectSwitch.json",
                mimeType = "application/json",
                bytes = jsonBytes
            )
            val html = buildString {
                append("<!DOCTYPE html><html lang='it'><head><meta charset='utf-8'>")
                append("<meta name='viewport' content='width=device-width,initial-scale=1'>")
                append("<title>Archivio SMS DirectSwitch (${incoming.size})</title>")
                append("<style>body{font-family:sans-serif;background:#f4f7f9;padding:16px} .msg{background:#fff;border-radius:12px;padding:12px;margin-bottom:10px;box-shadow:0 1px 4px rgba(0,0,0,0.06)} .meta{font-size:12px;color:#008f7a;font-weight:bold}</style></head><body>")
                append("<h2>SMS Trasferiti con DirectSwitch (${incoming.size})</h2>")
                for (sms in incoming) {
                    val dir = if (sms.messageType == 2) "Inviato a" else "Ricevuto da"
                    val safeAddr = sms.address.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
                    val safeBody = sms.body.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
                    append("<div class='msg'><div class='meta'>$dir $safeAddr</div><div>$safeBody</div></div>")
                }
                append("</body></html>")
            }
            val htmlSaved = PublicDownloadsSaver.saveBytes(
                context = context,
                subFolder = "SMS_Archivio",
                fileName = "SMS_Archivio_DirectSwitch.html",
                mimeType = "text/html",
                bytes = html.toByteArray(Charsets.UTF_8)
            )
            archiveOk = jsonSaved || htmlSaved
        } catch (t: Throwable) {
            DirectSwitchLog.warn("Scrittura archivio SMS fallita", t)
        }

        if (!isDefaultSmsApp(context)) {
            return if (archiveOk) incoming.size else 0
        }

        val existingKeys = readAllSms(context, maxMessages = 10000)
            .map { "${PhoneNormalizer.normalizeKey(it.address)}_${it.dateEpochMillis}_${it.body.hashCode()}" }
            .toHashSet()

        var inserted = 0
        var alreadyPresent = 0
        for (sms in incoming) {
            val key = "${PhoneNormalizer.normalizeKey(sms.address)}_${sms.dateEpochMillis}_${sms.body.hashCode()}"
            if (key in existingKeys) {
                alreadyPresent++
                continue
            }
            try {
                val values = ContentValues().apply {
                    put(Telephony.Sms.ADDRESS, sms.address)
                    put(Telephony.Sms.BODY, sms.body)
                    put(Telephony.Sms.DATE, sms.dateEpochMillis)
                    put(Telephony.Sms.TYPE, sms.messageType)
                    put(Telephony.Sms.READ, 1)
                    put(Telephony.Sms.SEEN, 1)
                }
                if (context.contentResolver.insert(Telephony.Sms.CONTENT_URI, values) != null) {
                    inserted++
                    existingKeys.add(key)
                }
            } catch (t: Throwable) {
                DirectSwitchLog.warn("Inserimento SMS fallito", t)
            }
        }
        return if (archiveOk) incoming.size else inserted + alreadyPresent
    }
}

/**
 * Scanner compatibile Scoped Storage (Android 8–16, `targetSdk = 36`) per Documenti e Vault WhatsApp:
 * 1. Legge il Vault interno alimentato tramite condivisione diretta (`Intent.ACTION_SEND` da WhatsApp -> "Esporta chat")
 *    oppure tramite il selettore di sistema Storage Access Framework (`OpenMultipleDocuments`).
 * 2. Interroga `MediaStore.Files` per eventuali documenti/export visibili all'app.
 * 3. Su Android 8–9 scansiona anche `Download` e `Documents`.
 */
object DocumentsAndWhatsAppScanner {
    private val supportedDocExtensions = setOf(
        "pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx", "txt", "csv", "zip", "rar", "7z", "ics", "vcf"
    )

    private fun sharedVaultDir(context: Context): File =
        File(context.filesDir, "shared_vault").apply { mkdirs() }

    /**
     * Importa nel Vault di invio uno o più `Uri` provenienti da `ACTION_SEND` (es. "Esporta chat" di WhatsApp)
     * o dal file picker di sistema (`OpenMultipleDocuments`). Restituisce il numero di file aggiunti.
     */
    fun importSharedUrisIntoVault(context: Context, uris: List<Uri>): Int {
        if (uris.isEmpty()) return 0
        val vault = sharedVaultDir(context)
        val resolver = context.contentResolver
        var imported = 0

        for (uri in uris) {
            try {
                val rawName = queryDisplayName(context, uri)
                    ?: uri.lastPathSegment?.substringAfterLast('/')
                    ?: "allegato_${System.currentTimeMillis()}"
                val safeName = File(rawName).name
                    .replace(Regex("[\\\\/:*?\"<>|]"), "_")
                    .ifBlank { "file_${System.currentTimeMillis()}" }
                val dest = File(vault, safeName)
                val copied = resolver.openInputStream(uri)?.use { input ->
                    dest.outputStream().use { out ->
                        input.copyTo(out, bufferSize = 256 * 1024)
                    }
                    true
                } ?: false
                if (copied && dest.length() > 0L) {
                    imported++
                } else {
                    dest.delete()
                }
            } catch (t: Throwable) {
                DirectSwitchLog.warn("Import URI nel Vault fallito", t)
            }
        }
        return imported
    }

    private fun queryDisplayName(context: Context, uri: Uri): String? {
        return try {
            context.contentResolver.query(
                uri,
                arrayOf(OpenableColumns.DISPLAY_NAME),
                null,
                null,
                null
            )?.use { cursor ->
                if (cursor.moveToFirst()) cursor.getString(0) else null
            }
        } catch (_: Throwable) {
            null
        }
    }

    fun scanDocumentAndWhatsAppEntries(
        context: Context,
        includeDocuments: Boolean,
        includeWhatsAppVault: Boolean
    ): List<LocalMediaEntry> {
        if (!includeDocuments && !includeWhatsAppVault) return emptyList()
        val out = mutableListOf<LocalMediaEntry>()
        var idxCounter = 0L

        fun classifyCategory(lowerName: String, ext: String): TransferCategory? {
            val isWhatsAppExport = lowerName.contains("whatsapp") && (ext == "zip" || ext == "txt")
            val isDoc = (ext in supportedDocExtensions || lowerName.isNotEmpty()) && !isWhatsAppExport
            return when {
                isWhatsAppExport && includeWhatsAppVault -> TransferCategory.WHATSAPP_VAULT
                isDoc && includeDocuments && ext in supportedDocExtensions -> TransferCategory.DOCUMENTS
                else -> null
            }
        }

        // 1. Vault esplicito (condivisioni da WhatsApp / File Picker SAF: funziona sempre su Android 11–16)
        val vaultFiles = sharedVaultDir(context).listFiles()?.toList().orEmpty()
        for (file in vaultFiles) {
            if (!file.isFile || file.length() <= 0L) continue
            val lowerName = file.name.lowercase()
            val ext = file.extension.lowercase()
            val isWa = lowerName.contains("whatsapp") && (ext == "zip" || ext == "txt")
            val cat = when {
                isWa && includeWhatsAppVault -> TransferCategory.WHATSAPP_VAULT
                !isWa && includeDocuments -> TransferCategory.DOCUMENTS
                else -> null
            } ?: continue
            idxCounter++
            val dedupKey = "${lowerName}_${file.length()}_${file.lastModified()}"
            out.add(
                LocalMediaEntry(
                    manifestItem = ManifestItem(
                        id = "${cat.name.lowercase()}_vault_$idxCounter",
                        category = cat,
                        fileName = file.name,
                        relativeAlbumOrFolder = if (isWa) "WhatsApp_Vault" else "Documenti",
                        sizeBytes = file.length(),
                        capturedEpochMillis = file.lastModified(),
                        dedupKey = dedupKey,
                        mimeType = mimeForExtension(ext)
                    ),
                    contentUri = Uri.fromFile(file)
                )
            )
        }

        // 2. Query MediaStore.Files per documenti visibili all'app
        try {
            val filesUri = MediaStore.Files.getContentUri("external")
            val projection = arrayOf(
                MediaStore.Files.FileColumns._ID,
                MediaStore.Files.FileColumns.DISPLAY_NAME,
                MediaStore.Files.FileColumns.SIZE,
                MediaStore.Files.FileColumns.DATE_MODIFIED,
                MediaStore.Files.FileColumns.MIME_TYPE
            )
            val selection = "${MediaStore.Files.FileColumns.MEDIA_TYPE} = ?"
            val selectionArgs = arrayOf(MediaStore.Files.FileColumns.MEDIA_TYPE_NONE.toString())
            context.contentResolver.query(
                filesUri,
                projection,
                selection,
                selectionArgs,
                "${MediaStore.Files.FileColumns.DATE_MODIFIED} DESC"
            )?.use { cursor ->
                val idCol = cursor.getColumnIndexOrThrow(MediaStore.Files.FileColumns._ID)
                val nameCol = cursor.getColumnIndexOrThrow(MediaStore.Files.FileColumns.DISPLAY_NAME)
                val sizeCol = cursor.getColumnIndexOrThrow(MediaStore.Files.FileColumns.SIZE)
                val dateCol = cursor.getColumnIndexOrThrow(MediaStore.Files.FileColumns.DATE_MODIFIED)
                val mimeCol = cursor.getColumnIndexOrThrow(MediaStore.Files.FileColumns.MIME_TYPE)

                while (cursor.moveToNext()) {
                    val id = cursor.getLong(idCol)
                    val name = cursor.getString(nameCol)?.trim().orEmpty()
                    val size = cursor.getLong(sizeCol)
                    if (name.isEmpty() || size <= 0L) continue
                    val lower = name.lowercase()
                    val ext = name.substringAfterLast('.', "").lowercase()
                    val cat = classifyCategory(lower, ext) ?: continue
                    val modMillis = cursor.getLong(dateCol) * 1000L
                    val mime = cursor.getString(mimeCol) ?: mimeForExtension(ext)
                    idxCounter++
                    out.add(
                        LocalMediaEntry(
                            manifestItem = ManifestItem(
                                id = "${cat.name.lowercase()}_ms_$id",
                                category = cat,
                                fileName = name,
                                relativeAlbumOrFolder = if (cat == TransferCategory.WHATSAPP_VAULT) "WhatsApp_Vault" else "Documenti",
                                sizeBytes = size,
                                capturedEpochMillis = modMillis,
                                dedupKey = "${lower}_${size}_$modMillis",
                                mimeType = mime
                            ),
                            contentUri = ContentUris.withAppendedId(filesUri, id)
                        )
                    )
                }
            }
        } catch (t: Throwable) {
            DirectSwitchLog.warn("Scansione MediaStore.Files fallita", t)
        }

        // 3. Fallback Android 8–9 su cartelle pubbliche
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            @Suppress("DEPRECATION")
            val legacyRoots = listOfNotNull(
                Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS),
                Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOCUMENTS)
            )
            for (root in legacyRoots) {
                if (!root.exists() || !root.canRead()) continue
                root.walkTopDown().maxDepth(3).forEach { file ->
                    if (!file.isFile || file.length() <= 0L) return@forEach
                    val lowerName = file.name.lowercase()
                    val ext = file.extension.lowercase()
                    val cat = classifyCategory(lowerName, ext) ?: return@forEach
                    idxCounter++
                    val dedupKey = "${lowerName}_${file.length()}_${file.lastModified()}"
                    out.add(
                        LocalMediaEntry(
                            manifestItem = ManifestItem(
                                id = "${cat.name.lowercase()}_$idxCounter",
                                category = cat,
                                fileName = file.name,
                                relativeAlbumOrFolder = if (cat == TransferCategory.WHATSAPP_VAULT) "WhatsApp_Vault" else "Documenti",
                                sizeBytes = file.length(),
                                capturedEpochMillis = file.lastModified(),
                                dedupKey = dedupKey,
                                mimeType = mimeForExtension(ext)
                            ),
                            contentUri = Uri.fromFile(file)
                        )
                    )
                }
            }
        }

        return out.distinctBy { it.manifestItem.dedupKey }
    }

    private fun mimeForExtension(ext: String): String = when (ext) {
        "pdf" -> "application/pdf"
        "zip" -> "application/zip"
        "txt" -> "text/plain"
        "csv" -> "text/csv"
        "vcf" -> "text/vcard"
        "ics" -> "text/calendar"
        else -> "application/octet-stream"
    }
}

/** Aggrega i conteggi locali per la dashboard iniziale e di selezione categorie. */
object DeviceDataAnalyzer {
    fun scanSummary(context: Context): LocalDeviceScanSummary {
        val contacts = ContactsSmartMerger.readAllContacts(context).size
        val media = MediaExifScannerAndImporter.scanMediaEntries(context, includePhotos = true, includeVideos = true)
        val photos = media.filter { it.manifestItem.category == TransferCategory.PHOTOS }
        val videos = media.filter { it.manifestItem.category == TransferCategory.VIDEOS }
        val calendars = CalendarMigrator.readEvents(context).size
        val sms = SmsSystemScanner.countSms(context)
        val docsAndWa = DocumentsAndWhatsAppScanner.scanDocumentAndWhatsAppEntries(
            context,
            includeDocuments = true,
            includeWhatsAppVault = true
        )
        val docsCount = docsAndWa.count { it.manifestItem.category == TransferCategory.DOCUMENTS }
        val waCount = docsAndWa.count { it.manifestItem.category == TransferCategory.WHATSAPP_VAULT }
        val (freeBytes, totalBytes) = StorageCapacityChecker.getFreeAndTotalBytes(context)

        return LocalDeviceScanSummary(
            contactsCount = contacts,
            photosCount = photos.size,
            photosBytes = photos.sumOf { it.manifestItem.sizeBytes },
            videosCount = videos.size,
            videosBytes = videos.sumOf { it.manifestItem.sizeBytes },
            calendarEventsCount = calendars,
            smsCount = sms,
            documentsCount = docsCount,
            whatsappArchivesCount = waCount,
            freeStorageBytes = freeBytes,
            totalStorageBytes = totalBytes
        )
    }
}
