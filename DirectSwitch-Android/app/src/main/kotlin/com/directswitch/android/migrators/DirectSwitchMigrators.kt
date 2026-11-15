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
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.media.MediaScannerConnection
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.StatFs
import android.os.storage.StorageManager
import android.provider.CalendarContract
import android.provider.ContactsContract
import android.provider.DocumentsContract
import android.provider.MediaStore
import android.provider.OpenableColumns
import android.provider.Settings
import android.provider.Telephony
import android.webkit.MimeTypeMap
import androidx.core.content.ContextCompat
import androidx.documentfile.provider.DocumentFile
import com.directswitch.android.DirectSwitchLog
import com.directswitch.android.protocol.CalendarEventRecord
import com.directswitch.android.protocol.ContactTransferRecord
import com.directswitch.android.protocol.DirectSwitchJson
import com.directswitch.android.protocol.InstalledAppRecord
import com.directswitch.android.protocol.ManifestItem
import com.directswitch.android.protocol.PhoneNormalizer
import com.directswitch.android.protocol.SmsTransferRecord
import com.directswitch.android.protocol.TransferCategory
import kotlinx.serialization.encodeToString
import java.io.ByteArrayInputStream
import java.io.File
import java.io.InputStream
import java.util.TimeZone

/** Riepilogo dei file e delle cartelle rilevate per singolo percorso relativo. */
data class DocumentFolderSummary(
    val folderPath: String,
    val fileCount: Int,
    val totalBytes: Long
)

/** Riepilogo di una intera posizione di archiviazione sul telefono (es. Memoria interna, Scheda SD, Posizione SAF). */
data class DocumentLocationSummary(
    val locationId: String = "",
    val locationName: String,
    val folderCount: Int,
    val fileCount: Int,
    val totalBytes: Long,
    val isAccessible: Boolean,
    val isSelected: Boolean = true,
    val isRemovableSaf: Boolean = false
)

/** Esito del controllo pre-trasferimento sulle posizioni e cartelle presenti sul telefono. */
data class DocumentPrecheckReport(
    val totalFiles: Int,
    val totalBytes: Long,
    val hasAllFilesAccess: Boolean,
    val persistedFoldersCount: Int,
    val folderSummaries: List<DocumentFolderSummary>,
    val locationSummaries: List<DocumentLocationSummary> = emptyList()
)

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
    val documentsBytes: Long = 0L,
    val documentFoldersCount: Int = 0,
    val hasAllFilesAccess: Boolean = false,
    val documentFolderSummaries: List<DocumentFolderSummary> = emptyList(),
    val documentLocationSummaries: List<DocumentLocationSummary> = emptyList(),
    val whatsappArchivesCount: Int = 0,
    val installedAppsCount: Int = 0,
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
 * Ricrea esattamente la gerarchia di cartelle originale sul nuovo Android:
 * - Se è attivo l'accesso completo ai file (Android 11+ `MANAGE_EXTERNAL_STORAGE`) o Android 8–9,
 *   salva direttamente nel percorso reale `/storage/emulated/0/<cartella_originale>/<sottocartelle>`.
 * - In modalità Scoped Storage (Android 10–16 senza accesso completo), mappa nativamente `Download/...`
 *   in `MediaStore.Downloads` e `Documents/...` o cartelle personalizzate in `MediaStore.Files` (`Documents/...`)
 *   preservando ogni sottocartella ed evitando duplicati a parità di nome e dimensione.
 */
object PublicDownloadsSaver {
    fun sanitizedRelativeSegments(rawFolder: String): List<String> =
        rawFolder.replace('\\', '/')
            .split('/')
            .map { seg ->
                seg.replace(Regex("[\\\\/:*?\"<>|]"), "_").trim()
            }
            .filter { it.isNotEmpty() && it != "." && it != ".." }

    fun saveBytes(
        context: Context,
        subFolder: String,
        fileName: String,
        mimeType: String,
        bytes: ByteArray,
        expectedSizeBytes: Long = bytes.size.toLong()
    ): Boolean = ByteArrayInputStream(bytes).use { stream ->
        saveStream(context, subFolder, fileName, mimeType, stream, expectedSizeBytes)
    }

    fun saveStream(
        context: Context,
        subFolder: String,
        fileName: String,
        mimeType: String,
        inputStream: InputStream,
        expectedSizeBytes: Long = -1L
    ): Boolean {
        return try {
            val segments = sanitizedRelativeSegments(subFolder)
            val normalizedSegments = segments.ifEmpty { listOf(Environment.DIRECTORY_DOCUMENTS) }
            val safeName = File(fileName).name
                .replace(Regex("[\\\\/:*?\"<>|]"), "_")
                .ifBlank { "file_${System.currentTimeMillis()}" }

            val canWriteDirectRoot = DocumentsAndWhatsAppScanner.hasAllFilesAccess(context) ||
                Build.VERSION.SDK_INT < Build.VERSION_CODES.Q

            if (canWriteDirectRoot) {
                val volumes = DocumentsAndWhatsAppScanner.discoverStorageVolumes(context)
                val firstSeg = normalizedSegments.firstOrNull().orEmpty()
                val matchedSecondary = volumes.firstOrNull { vol ->
                    !vol.isPrimary &&
                        vol.relativePrefix.equals(firstSeg, ignoreCase = true) &&
                        vol.rootDir.canWrite()
                }
                @Suppress("DEPRECATION")
                val baseRoot = matchedSecondary?.rootDir ?: Environment.getExternalStorageDirectory()
                val segmentsToWrite = if (matchedSecondary != null && normalizedSegments.size > 1) {
                    normalizedSegments.drop(1)
                } else {
                    normalizedSegments
                }
                var targetDir = baseRoot
                for (seg in segmentsToWrite) {
                    targetDir = File(targetDir, seg)
                }
                if (!targetDir.exists() && !targetDir.mkdirs()) {
                    // Fallback a MediaStore su Android 10+ se la scrittura diretta non fosse ammessa su quel volume
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                        return saveViaMediaStore(context, normalizedSegments, safeName, mimeType, inputStream, expectedSizeBytes)
                    }
                    return false
                }
                val exactExisting = File(targetDir, safeName)
                if (exactExisting.exists() && expectedSizeBytes > 0L && exactExisting.length() == expectedSizeBytes) {
                    return true
                }
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
                return true
            }

            saveViaMediaStore(context, normalizedSegments, safeName, mimeType, inputStream, expectedSizeBytes)
        } catch (t: Throwable) {
            DirectSwitchLog.warn("Salvataggio file nella cartella originale fallito", t)
            false
        }
    }

    private fun saveViaMediaStore(
        context: Context,
        segments: List<String>,
        safeName: String,
        mimeType: String,
        inputStream: InputStream,
        expectedSizeBytes: Long
    ): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return false
        val resolver = context.contentResolver
        val firstLower = segments.firstOrNull()?.lowercase().orEmpty()
        val tailPath = segments.drop(1).joinToString("/")

        val (collectionUri, relPath) = when {
            firstLower == "download" || firstLower == "downloads" -> {
                val p = if (tailPath.isEmpty()) Environment.DIRECTORY_DOWNLOADS else "${Environment.DIRECTORY_DOWNLOADS}/$tailPath"
                MediaStore.Downloads.EXTERNAL_CONTENT_URI to p
            }
            firstLower == "documents" || firstLower == "documenti" -> {
                val p = if (tailPath.isEmpty()) Environment.DIRECTORY_DOCUMENTS else "${Environment.DIRECTORY_DOCUMENTS}/$tailPath"
                MediaStore.Files.getContentUri("external") to p
            }
            firstLower == "whatsapp_vault" || firstLower == "sms_archivio" || firstLower == "password_esportate" -> {
                val full = segments.joinToString("/")
                MediaStore.Downloads.EXTERNAL_CONTENT_URI to "${Environment.DIRECTORY_DOWNLOADS}/$full"
            }
            else -> {
                val full = segments.joinToString("/")
                MediaStore.Files.getContentUri("external") to "${Environment.DIRECTORY_DOCUMENTS}/$full"
            }
        }

        // Evita duplicati identici nella stessa cartella MediaStore
        if (expectedSizeBytes > 0L && mediaStoreFileExists(context, collectionUri, relPath, safeName, expectedSizeBytes)) {
            return true
        }

        val values = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, safeName)
            put(MediaStore.MediaColumns.MIME_TYPE, mimeType)
            put(MediaStore.MediaColumns.RELATIVE_PATH, relPath)
            put(MediaStore.MediaColumns.IS_PENDING, 1)
        }
        val uri = resolver.insert(collectionUri, values) ?: return false
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
        return true
    }

    private fun mediaStoreFileExists(
        context: Context,
        collectionUri: Uri,
        relPath: String,
        displayName: String,
        expectedSizeBytes: Long
    ): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return false
        return try {
            val normalizedRel = if (relPath.endsWith("/")) relPath else "$relPath/"
            context.contentResolver.query(
                collectionUri,
                arrayOf(MediaStore.MediaColumns._ID),
                "${MediaStore.MediaColumns.DISPLAY_NAME} = ? AND ${MediaStore.MediaColumns.RELATIVE_PATH} = ? AND ${MediaStore.MediaColumns.SIZE} = ?",
                arrayOf(displayName, normalizedRel, expectedSizeBytes.toString()),
                null
            )?.use { c -> c.moveToFirst() } ?: false
        } catch (_: Throwable) {
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
                .ifEmpty { if (isVideo) "Video" else "Foto" }

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                val baseRelPath = when {
                    safeAlbum.equals("Camera", ignoreCase = true) -> "${Environment.DIRECTORY_DCIM}/Camera"
                    isVideo -> "${Environment.DIRECTORY_MOVIES}/$safeAlbum"
                    else -> "${Environment.DIRECTORY_PICTURES}/$safeAlbum"
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
                var uri = resolver.insert(collection, values)
                if (uri == null) {
                    val dot = item.fileName.lastIndexOf('.')
                    val stem = if (dot > 0) item.fileName.substring(0, dot) else item.fileName
                    val ext = if (dot > 0) item.fileName.substring(dot) else ""
                    values.put(MediaStore.MediaColumns.DISPLAY_NAME, "${stem}_${System.currentTimeMillis() % 10000}$ext")
                    uri = resolver.insert(collection, values)
                }
                val targetUri = uri ?: return false
                val ok = resolver.openOutputStream(targetUri)?.use { out ->
                    plainInputStream.copyTo(out, bufferSize = 256 * 1024)
                    true
                } ?: false
                if (!ok) {
                    resolver.delete(targetUri, null, null)
                    return false
                }
                val doneValues = ContentValues().apply {
                    put(MediaStore.MediaColumns.IS_PENDING, 0)
                }
                resolver.update(targetUri, doneValues, null, null)
                true
            } else {
                @Suppress("DEPRECATION")
                val publicRoot = Environment.getExternalStoragePublicDirectory(
                    if (isVideo) Environment.DIRECTORY_MOVIES else Environment.DIRECTORY_PICTURES
                )
                val targetPublicRoot = if (safeAlbum.equals("Camera", ignoreCase = true)) {
                    @Suppress("DEPRECATION")
                    Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DCIM)
                } else {
                    publicRoot
                }
                val albumDir = File(targetPublicRoot, safeAlbum)
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
 * Scanner completo e pre-check cartelle per Documenti, File e Archivi WhatsApp su Android 8–16 (`targetSdk = 36`):
 * 1. Supporta l'accesso completo opzionale a tutte le cartelle (`MANAGE_EXTERNAL_STORAGE` su Android 11+) per leggere
 *    ogni file mantenendo l'alberatura esatta `/storage/emulated/0/<cartella>/<sottocartelle>`.
 * 2. Supporta intere cartelle scelte con il selettore SAF (`OpenDocumentTree`) persistendo i permessi tra riavvii.
 * 3. Interroga `MediaStore.Files` estraendo il reale percorso `RELATIVE_PATH` / `DATA` invece di appiattire in "Documenti".
 * 4. Include i file condivisi o selezionati nel Vault interno (`shared_vault`).
 */
object DocumentsAndWhatsAppScanner {
    private const val PREFS_NAME = "directswitch_docs_prefs"
    private const val KEY_TREE_URIS = "persisted_doc_tree_uris"
    private const val KEY_DESELECTED_LOCATIONS = "deselected_doc_location_ids"

    private val mediaGalleryExtensions = setOf(
        "jpg", "jpeg", "png", "heic", "heif", "webp", "gif", "bmp", "dng", "raw",
        "mp4", "mov", "m4v", "3gp", "mkv", "avi", "webm"
    )

    private val supportedDocExtensions = setOf(
        "pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx", "odt", "ods", "odp", "rtf",
        "txt", "csv", "md", "json", "xml", "html", "htm", "epub", "mobi",
        "pages", "numbers", "key", "zip", "rar", "7z", "tar", "gz",
        "ics", "vcf", "m4a", "mp3", "wav", "aac", "flac", "ogg", "opus", "apk", "dwg", "svg"
    )

    fun hasAllFilesAccess(context: Context): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            Environment.isExternalStorageManager()
        } else {
            ContextCompat.checkSelfPermission(
                context,
                Manifest.permission.READ_EXTERNAL_STORAGE
            ) == PackageManager.PERMISSION_GRANTED
        }
    }

    fun openAllFilesAccessSettings(context: Context) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            val specific = Intent(
                Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION,
                Uri.parse("package:${context.packageName}")
            ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            val fallback = Intent(Settings.ACTION_MANAGE_ALL_FILES_ACCESS_PERMISSION)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            if (runCatching { context.startActivity(specific) }.isFailure) {
                runCatching { context.startActivity(fallback) }
            }
        } else {
            val appSettings = Intent(
                Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                Uri.parse("package:${context.packageName}")
            ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            runCatching { context.startActivity(appSettings) }
        }
    }

    private fun sharedVaultDir(context: Context): File =
        File(context.filesDir, "shared_vault").apply { mkdirs() }

    fun savePickedFolderTree(context: Context, treeUri: Uri): Boolean {
        return runCatching {
            val flags = Intent.FLAG_GRANT_READ_URI_PERMISSION
            runCatching {
                context.contentResolver.takePersistableUriPermission(treeUri, flags)
            }
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            val current = prefs.getStringSet(KEY_TREE_URIS, emptySet()).orEmpty().toMutableSet()
            current.add(treeUri.toString())
            val deselected = prefs.getStringSet(KEY_DESELECTED_LOCATIONS, emptySet()).orEmpty().toMutableSet()
            deselected.remove("saf:$treeUri")
            prefs.edit()
                .putStringSet(KEY_TREE_URIS, current)
                .putStringSet(KEY_DESELECTED_LOCATIONS, deselected)
                .apply()
            true
        }.getOrDefault(false)
    }

    fun getPersistedFolderTreeUris(context: Context): List<Uri> {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val rawSet = prefs.getStringSet(KEY_TREE_URIS, emptySet()).orEmpty()
        return rawSet.mapNotNull { runCatching { Uri.parse(it) }.getOrNull() }
    }

    fun isLocationSelected(context: Context, locationId: String): Boolean {
        if (locationId.isBlank()) return true
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val deselected = prefs.getStringSet(KEY_DESELECTED_LOCATIONS, emptySet()).orEmpty()
        return locationId !in deselected
    }

    fun setLocationSelected(context: Context, locationId: String, selected: Boolean) {
        if (locationId.isBlank()) return
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val deselected = prefs.getStringSet(KEY_DESELECTED_LOCATIONS, emptySet()).orEmpty().toMutableSet()
        if (selected) {
            deselected.remove(locationId)
        } else {
            deselected.add(locationId)
        }
        prefs.edit().putStringSet(KEY_DESELECTED_LOCATIONS, deselected).apply()
    }

    fun removePersistedFolderTree(context: Context, locationId: String) {
        if (!locationId.startsWith("saf:")) return
        val rawUri = locationId.removePrefix("saf:")
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val current = prefs.getStringSet(KEY_TREE_URIS, emptySet()).orEmpty().toMutableSet()
        current.remove(rawUri)
        val deselected = prefs.getStringSet(KEY_DESELECTED_LOCATIONS, emptySet()).orEmpty().toMutableSet()
        deselected.remove(locationId)
        prefs.edit()
            .putStringSet(KEY_TREE_URIS, current)
            .putStringSet(KEY_DESELECTED_LOCATIONS, deselected)
            .apply()
        runCatching {
            context.contentResolver.releasePersistableUriPermission(
                Uri.parse(rawUri),
                Intent.FLAG_GRANT_READ_URI_PERMISSION
            )
        }
    }

    fun clearPickedDocumentsAndFolders(context: Context) {
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .remove(KEY_TREE_URIS)
            .remove(KEY_DESELECTED_LOCATIONS)
            .apply()
        runCatching { sharedVaultDir(context).deleteRecursively() }
        sharedVaultDir(context)
    }

    /**
     * Importa nel Vault di invio uno o più `Uri` provenienti da `ACTION_SEND` (es. "Esporta chat" di WhatsApp)
     * o dal file picker di sistema (`OpenMultipleDocuments`), cercando di preservare la sottocartella reale se disponibile.
     */
    fun importSharedUrisIntoVault(context: Context, uris: List<Uri>): Int {
        if (uris.isEmpty()) return 0
        val vault = sharedVaultDir(context)
        val resolver = context.contentResolver
        var imported = 0

        for (uri in uris) {
            try {
                val (rawName, relDirHint) = queryDisplayNameAndRelativeFolder(context, uri)
                val effectiveName = rawName
                    ?: uri.lastPathSegment?.substringAfterLast('/')
                    ?: "allegato_${System.currentTimeMillis()}"
                val safeName = File(effectiveName).name
                    .replace(Regex("[\\\\/:*?\"<>|]"), "_")
                    .ifBlank { "file_${System.currentTimeMillis()}" }

                val relSegments = relDirHint?.let { PublicDownloadsSaver.sanitizedRelativeSegments(it) }.orEmpty()
                var destParent = vault
                for (seg in relSegments) {
                    destParent = File(destParent, seg)
                }
                destParent.mkdirs()

                val dest = File(destParent, safeName)
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

    private fun queryDisplayNameAndRelativeFolder(context: Context, uri: Uri): Pair<String?, String?> {
        var displayName: String? = null
        var relFolder: String? = null
        runCatching {
            val cols = buildList {
                add(OpenableColumns.DISPLAY_NAME)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    add(MediaStore.MediaColumns.RELATIVE_PATH)
                }
            }.toTypedArray()
            context.contentResolver.query(uri, cols, null, null, null)?.use { cursor ->
                if (cursor.moveToFirst()) {
                    val nameIdx = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                    if (nameIdx >= 0) displayName = cursor.getString(nameIdx)
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                        val relIdx = cursor.getColumnIndex(MediaStore.MediaColumns.RELATIVE_PATH)
                        if (relIdx >= 0) {
                            relFolder = cursor.getString(relIdx)?.trim('/')?.takeIf { it.isNotBlank() }
                        }
                    }
                }
            }
        }
        if (relFolder.isNullOrBlank() && uri.authority == "com.android.externalstorage.documents") {
            runCatching {
                val docId = android.provider.DocumentsContract.getDocumentId(uri)
                val colon = docId.indexOf(':')
                if (colon >= 0) {
                    val inner = docId.substring(colon + 1)
                    val slash = inner.lastIndexOf('/')
                    if (slash > 0) {
                        relFolder = inner.substring(0, slash)
                    }
                }
            }
        }
        return displayName to relFolder
    }

    internal data class AccessibleStorageVolume(
        val locationLabel: String,
        val rootDir: File,
        val relativePrefix: String,
        val isPrimary: Boolean
    )

    private data class ScannedLocationEntry(
        val entry: LocalMediaEntry,
        val locationId: String,
        val locationName: String
    )

    internal fun discoverStorageVolumes(context: Context): List<AccessibleStorageVolume> {
        val result = mutableListOf<AccessibleStorageVolume>()
        val seenCanonical = HashSet<String>()

        @Suppress("DEPRECATION")
        val primaryDir = Environment.getExternalStorageDirectory()
        if (primaryDir != null && primaryDir.exists()) {
            val canonical = runCatching { primaryDir.canonicalPath }.getOrElse { primaryDir.absolutePath }
            if (seenCanonical.add(canonical)) {
                result.add(
                    AccessibleStorageVolume(
                        locationLabel = "Memoria interna",
                        rootDir = primaryDir,
                        relativePrefix = "",
                        isPrimary = true
                    )
                )
            }
        }

        val usedPrefixes = mutableSetOf<String>()
        val storageManager = runCatching { context.getSystemService(StorageManager::class.java) }.getOrNull()
        if (storageManager != null) {
            for (vol in storageManager.storageVolumes) {
                if (vol.isPrimary) continue
                if (vol.state != Environment.MEDIA_MOUNTED && vol.state != Environment.MEDIA_MOUNTED_READ_ONLY) continue
                val rootDir = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) vol.directory else null
                if (rootDir == null || !rootDir.exists() || !rootDir.isDirectory) continue
                val canonical = runCatching { rootDir.canonicalPath }.getOrElse { rootDir.absolutePath }
                if (!seenCanonical.add(canonical)) continue
                val desc = runCatching { vol.getDescription(context)?.trim() }.getOrNull()
                    ?.takeIf { !it.isNullOrBlank() } ?: "Scheda SD"
                val basePrefix = PublicDownloadsSaver.sanitizedRelativeSegments(desc)
                    .joinToString("_")
                    .ifBlank { "Scheda_SD" }
                var uniquePrefix = basePrefix
                var suffix = 2
                while (!usedPrefixes.add(uniquePrefix.lowercase())) {
                    uniquePrefix = "${basePrefix}_$suffix"
                    suffix++
                }
                result.add(
                    AccessibleStorageVolume(
                        locationLabel = desc,
                        rootDir = rootDir,
                        relativePrefix = uniquePrefix,
                        isPrimary = false
                    )
                )
            }
        }

        for (extAppDir in ContextCompat.getExternalFilesDirs(context, null)) {
            val path = extAppDir?.absolutePath ?: continue
            val markerIdx = path.indexOf("/Android/data/")
            if (markerIdx <= 0) continue
            val volRoot = File(path.substring(0, markerIdx))
            if (!volRoot.exists() || !volRoot.isDirectory) continue
            val canonical = runCatching { volRoot.canonicalPath }.getOrElse { volRoot.absolutePath }
            if (!seenCanonical.add(canonical)) continue
            val basePrefix = if (usedPrefixes.isEmpty()) "Scheda_SD" else "Scheda_SD_${usedPrefixes.size + 1}"
            usedPrefixes.add(basePrefix.lowercase())
            result.add(
                AccessibleStorageVolume(
                    locationLabel = "Scheda SD / USB",
                    rootDir = volRoot,
                    relativePrefix = basePrefix,
                    isPrimary = false
                )
            )
        }
        return result
    }

    private fun extractSafRootPrefix(treeUri: Uri, rootDoc: DocumentFile): Pair<String, String> {
        val docId = runCatching { DocumentsContract.getTreeDocumentId(treeUri) }.getOrNull().orEmpty()
        val rawName = rootDoc.name?.trim().orEmpty()
        return when {
            docId == "primary:" -> "" to "Memoria interna (autorizzata)"
            docId.startsWith("primary:") -> {
                val sub = PublicDownloadsSaver.sanitizedRelativeSegments(docId.removePrefix("primary:")).joinToString("/")
                val clean = sub.ifBlank {
                    PublicDownloadsSaver.sanitizedRelativeSegments(rawName).joinToString("/").ifBlank { "Posizione_Interna" }
                }
                clean to "Posizione: $clean"
            }
            docId.endsWith(":") -> {
                val cleanVol = PublicDownloadsSaver.sanitizedRelativeSegments(rawName)
                    .joinToString("_")
                    .ifBlank { "Scheda_SD" }
                cleanVol to (rawName.ifBlank { "Scheda SD / USB" })
            }
            else -> {
                val clean = PublicDownloadsSaver.sanitizedRelativeSegments(rawName)
                    .joinToString("/")
                    .ifBlank { "Posizione_Esterna" }
                clean to "Posizione: ${rawName.ifBlank { clean }}"
            }
        }
    }

    private fun volumeLocationId(vol: AccessibleStorageVolume): String =
        if (vol.isPrimary) "vol:primary" else "vol:${vol.relativePrefix.lowercase()}"

    fun inspectPreTransferDocuments(
        context: Context,
        includeDocuments: Boolean = true,
        includeWhatsAppVault: Boolean = false
    ): DocumentPrecheckReport {
        val detailed = scanDetailedEntries(
            context = context,
            includeDocuments = includeDocuments,
            includeWhatsAppVault = includeWhatsAppVault
        )
        val allDocEntries = detailed.filter { it.entry.manifestItem.category == TransferCategory.DOCUMENTS }
        val selectedDocEntries = allDocEntries.filter { isLocationSelected(context, it.locationId) }

        val groupedFolders = selectedDocEntries.groupBy {
            it.entry.manifestItem.relativeAlbumOrFolder.ifBlank { Environment.DIRECTORY_DOCUMENTS }
        }
        val summaries = groupedFolders.map { (folder, list) ->
            DocumentFolderSummary(
                folderPath = folder,
                fileCount = list.size,
                totalBytes = list.sumOf { it.entry.manifestItem.sizeBytes }
            )
        }.sortedWith(compareByDescending<DocumentFolderSummary> { it.fileCount }.thenBy { it.folderPath.lowercase() })

        val hasFullAccess = hasAllFilesAccess(context)
        val volumes = discoverStorageVolumes(context)
        val persistedTrees = getPersistedFolderTreeUris(context)
        val byLocationId = allDocEntries.groupBy { it.locationId }

        val locations = mutableListOf<DocumentLocationSummary>()
        val coveredIds = HashSet<String>()

        for (vol in volumes) {
            val locId = volumeLocationId(vol)
            val matching = byLocationId[locId].orEmpty()
            val displayLabel = if (vol.isPrimary && !hasFullAccess) {
                "Memoria interna (accesso parziale)"
            } else {
                vol.locationLabel
            }
            coveredIds.add(locId)
            locations.add(
                DocumentLocationSummary(
                    locationId = locId,
                    locationName = displayLabel,
                    folderCount = matching.map { it.entry.manifestItem.relativeAlbumOrFolder.lowercase() }.distinct().size,
                    fileCount = matching.size,
                    totalBytes = matching.sumOf { it.entry.manifestItem.sizeBytes },
                    isAccessible = hasFullAccess,
                    isSelected = isLocationSelected(context, locId),
                    isRemovableSaf = false
                )
            )
        }

        for (treeUri in persistedTrees) {
            val locId = "saf:$treeUri"
            if (!coveredIds.add(locId)) continue
            val rootDoc = runCatching { DocumentFile.fromTreeUri(context, treeUri) }.getOrNull()
            val locLabel = if (rootDoc != null) {
                extractSafRootPrefix(treeUri, rootDoc).second
            } else {
                "Posizione esterna"
            }
            val matching = byLocationId[locId].orEmpty()
            locations.add(
                DocumentLocationSummary(
                    locationId = locId,
                    locationName = locLabel,
                    folderCount = matching.map { it.entry.manifestItem.relativeAlbumOrFolder.lowercase() }.distinct().size,
                    fileCount = matching.size,
                    totalBytes = matching.sumOf { it.entry.manifestItem.sizeBytes },
                    isAccessible = rootDoc?.canRead() ?: true,
                    isSelected = isLocationSelected(context, locId),
                    isRemovableSaf = true
                )
            )
        }

        for ((locId, list) in byLocationId) {
            if (!coveredIds.add(locId)) continue
            val firstName = list.firstOrNull()?.locationName ?: "Archivio DirectSwitch"
            locations.add(
                DocumentLocationSummary(
                    locationId = locId,
                    locationName = firstName,
                    folderCount = list.map { it.entry.manifestItem.relativeAlbumOrFolder.lowercase() }.distinct().size,
                    fileCount = list.size,
                    totalBytes = list.sumOf { it.entry.manifestItem.sizeBytes },
                    isAccessible = true,
                    isSelected = isLocationSelected(context, locId),
                    isRemovableSaf = locId.startsWith("saf:")
                )
            )
        }

        return DocumentPrecheckReport(
            totalFiles = selectedDocEntries.size,
            totalBytes = selectedDocEntries.sumOf { it.entry.manifestItem.sizeBytes },
            hasAllFilesAccess = hasFullAccess,
            persistedFoldersCount = persistedTrees.size,
            folderSummaries = summaries,
            locationSummaries = locations
        )
    }

    fun buildExistingDocumentDedupKeys(context: Context): Set<String> {
        return scanDocumentAndWhatsAppEntries(
            context = context,
            includeDocuments = true,
            includeWhatsAppVault = true,
            respectSelectionFilter = false
        ).map { entry ->
            val relNorm = PublicDownloadsSaver.sanitizedRelativeSegments(entry.manifestItem.relativeAlbumOrFolder)
                .joinToString("/")
                .lowercase()
            "${relNorm}/${entry.manifestItem.fileName.lowercase()}_${entry.manifestItem.sizeBytes}"
        }.toHashSet()
    }

    fun scanDocumentAndWhatsAppEntries(
        context: Context,
        includeDocuments: Boolean,
        includeWhatsAppVault: Boolean,
        respectSelectionFilter: Boolean = true
    ): List<LocalMediaEntry> {
        val detailed = scanDetailedEntries(context, includeDocuments, includeWhatsAppVault)
        return if (respectSelectionFilter) {
            detailed.filter {
                it.entry.manifestItem.category == TransferCategory.WHATSAPP_VAULT ||
                    isLocationSelected(context, it.locationId)
            }.map { it.entry }
        } else {
            detailed.map { it.entry }
        }
    }

    private fun scanDetailedEntries(
        context: Context,
        includeDocuments: Boolean,
        includeWhatsAppVault: Boolean
    ): List<ScannedLocationEntry> {
        if (!includeDocuments && !includeWhatsAppVault) return emptyList()
        val out = mutableListOf<ScannedLocationEntry>()
        var idxCounter = 0L

        fun classifyFile(lowerName: String, ext: String, allowAnyNonHidden: Boolean): TransferCategory? {
            if (lowerName.startsWith(".") || ext == "tmp" || ext == "nomedia" || ext == "part") return null
            val isWhatsAppExport = lowerName.contains("whatsapp") && (ext == "zip" || ext == "txt")
            return when {
                isWhatsAppExport && includeWhatsAppVault -> TransferCategory.WHATSAPP_VAULT
                !isWhatsAppExport && includeDocuments && (allowAnyNonHidden || ext in supportedDocExtensions) ->
                    TransferCategory.DOCUMENTS
                else -> null
            }
        }

        fun normalizeFolderOrFallback(rawFolder: String?, cat: TransferCategory): String {
            if (cat == TransferCategory.WHATSAPP_VAULT) return "WhatsApp_Vault"
            val clean = PublicDownloadsSaver.sanitizedRelativeSegments(rawFolder.orEmpty()).joinToString("/")
            return clean.ifEmpty { Environment.DIRECTORY_DOCUMENTS }
        }

        // 1. Vault esplicito (importazioni Share Sheet / .zip WhatsApp)
        val vaultRoot = sharedVaultDir(context)
        vaultRoot.walkTopDown().forEach { file ->
            if (!file.isFile || file.length() <= 0L) return@forEach
            val lowerName = file.name.lowercase()
            val ext = file.extension.lowercase()
            val cat = classifyFile(lowerName, ext, allowAnyNonHidden = true) ?: return@forEach
            val relParent = file.parentFile?.relativeToOrNull(vaultRoot)?.path
                ?.replace('\\', '/')
                ?.takeIf { it.isNotBlank() && it != "." }
            val folder = normalizeFolderOrFallback(relParent, cat)
            idxCounter++
            val canonicalDedup = "${folder.lowercase()}/${lowerName}_${file.length()}_${file.lastModified()}"
            out.add(
                ScannedLocationEntry(
                    entry = LocalMediaEntry(
                        manifestItem = ManifestItem(
                            id = "${cat.name.lowercase()}_vault_$idxCounter",
                            category = cat,
                            fileName = file.name,
                            relativeAlbumOrFolder = folder,
                            sizeBytes = file.length(),
                            capturedEpochMillis = file.lastModified(),
                            dedupKey = canonicalDedup,
                            mimeType = mimeForExtension(ext)
                        ),
                        contentUri = Uri.fromFile(file)
                    ),
                    locationId = "vault:shared",
                    locationName = "Archivio DirectSwitch"
                )
            )
        }

        // 2. Intere posizioni autorizzate con SAF (`OpenDocumentTree`, es. USB, Cloud, Schede SD, Memoria interna)
        for (treeUri in getPersistedFolderTreeUris(context)) {
            val rootDoc = runCatching { DocumentFile.fromTreeUri(context, treeUri) }.getOrNull() ?: continue
            if (!rootDoc.exists() || !rootDoc.canRead()) continue
            val (rootPrefix, locLabel) = extractSafRootPrefix(treeUri, rootDoc)
            val safLocId = "saf:$treeUri"

            fun walkTree(dir: DocumentFile, currentRelFolder: String) {
                for (child in dir.listFiles()) {
                    val childName = child.name?.trim().orEmpty()
                    if (childName.isEmpty() || childName.startsWith(".")) continue
                    if (child.isDirectory) {
                        val nextRel = if (currentRelFolder.isBlank()) childName else "$currentRelFolder/$childName"
                        walkTree(child, nextRel)
                    } else if (child.isFile) {
                        val size = child.length()
                        if (size <= 0L) continue
                        val lower = childName.lowercase()
                        val ext = childName.substringAfterLast('.', "").lowercase()
                        val cat = classifyFile(lower, ext, allowAnyNonHidden = true) ?: continue
                        val mod = child.lastModified()
                        val folder = normalizeFolderOrFallback(currentRelFolder, cat)
                        idxCounter++
                        out.add(
                            ScannedLocationEntry(
                                entry = LocalMediaEntry(
                                    manifestItem = ManifestItem(
                                        id = "${cat.name.lowercase()}_saf_$idxCounter",
                                        category = cat,
                                        fileName = childName,
                                        relativeAlbumOrFolder = folder,
                                        sizeBytes = size,
                                        capturedEpochMillis = mod,
                                        dedupKey = "${folder.lowercase()}/${lower}_${size}_$mod",
                                        mimeType = child.type ?: mimeForExtension(ext)
                                    ),
                                    contentUri = child.uri
                                ),
                                locationId = safLocId,
                                locationName = locLabel
                            )
                        )
                    }
                }
            }
            walkTree(rootDoc, rootPrefix)
        }

        // 3. Scansione automatica di TUTTE le posizioni montate (Memoria interna + Scheda SD / USB) con Accesso completo ai file
        if (hasAllFilesAccess(context)) {
            val excludedRootDirs = setOf("android", "lost.dir", ".thumbnails", ".trash")
            val galleryRoots = setOf("dcim", "pictures", "movies")
            for (vol in discoverStorageVolumes(context)) {
                val volLocId = volumeLocationId(vol)
                val storagePathPrefix = vol.rootDir.absolutePath.trimEnd('/') + "/"
                val visitedCanonicalDirs = HashSet<String>()

                fun walkStorageDir(dir: File, depth: Int) {
                    if (depth > 32 || !dir.isDirectory || !dir.canRead()) return
                    val canonical = runCatching { dir.canonicalPath }.getOrElse { dir.absolutePath }
                    if (!visitedCanonicalDirs.add(canonical)) return
                    val children = dir.listFiles() ?: return
                    for (entry in children) {
                        val name = entry.name
                        if (name.startsWith(".")) continue
                        if (entry.isDirectory) {
                            if (depth == 0 && name.lowercase() in excludedRootDirs) continue
                            walkStorageDir(entry, depth + 1)
                        } else if (entry.isFile) {
                            val size = entry.length()
                            if (size <= 0L) continue
                            val parentPath = entry.parentFile?.absolutePath ?: continue
                            val rawLocalRel = if (parentPath.startsWith(storagePathPrefix)) {
                                parentPath.removePrefix(storagePathPrefix)
                            } else {
                                ""
                            }
                            val firstSegLower = rawLocalRel.substringBefore('/').lowercase()
                            val ext = entry.extension.lowercase()
                            if (vol.isPrimary && firstSegLower in galleryRoots && ext in mediaGalleryExtensions) continue

                            val combinedRel = when {
                                vol.relativePrefix.isNotBlank() && rawLocalRel.isNotBlank() -> "${vol.relativePrefix}/$rawLocalRel"
                                vol.relativePrefix.isNotBlank() -> vol.relativePrefix
                                rawLocalRel.isNotBlank() -> rawLocalRel
                                else -> Environment.DIRECTORY_DOCUMENTS
                            }
                            val cat = classifyFile(
                                name.lowercase(),
                                ext,
                                allowAnyNonHidden = !(vol.isPrimary && firstSegLower in galleryRoots)
                            ) ?: continue
                            val folder = normalizeFolderOrFallback(combinedRel, cat)
                            idxCounter++
                            out.add(
                                ScannedLocationEntry(
                                    entry = LocalMediaEntry(
                                        manifestItem = ManifestItem(
                                            id = "${cat.name.lowercase()}_fs_$idxCounter",
                                            category = cat,
                                            fileName = name,
                                            relativeAlbumOrFolder = folder,
                                            sizeBytes = size,
                                            capturedEpochMillis = entry.lastModified(),
                                            dedupKey = "${folder.lowercase()}/${name.lowercase()}_${size}_${entry.lastModified()}",
                                            mimeType = mimeForExtension(ext)
                                        ),
                                        contentUri = Uri.fromFile(entry)
                                    ),
                                    locationId = volLocId,
                                    locationName = vol.locationLabel
                                )
                            )
                        }
                    }
                }
                walkStorageDir(vol.rootDir, 0)
            }
        } else {
            // 4. Fallback Scoped Storage (senza MANAGE_EXTERNAL_STORAGE): legge MediaStore.Files mantenendo RELATIVE_PATH reale!
            try {
                val filesUri = MediaStore.Files.getContentUri("external")
                val projection = buildList {
                    add(MediaStore.Files.FileColumns._ID)
                    add(MediaStore.Files.FileColumns.DISPLAY_NAME)
                    add(MediaStore.Files.FileColumns.SIZE)
                    add(MediaStore.Files.FileColumns.DATE_MODIFIED)
                    add(MediaStore.Files.FileColumns.MIME_TYPE)
                    add(MediaStore.Files.FileColumns.MEDIA_TYPE)
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                        add(MediaStore.Files.FileColumns.RELATIVE_PATH)
                    } else {
                        @Suppress("DEPRECATION")
                        add(MediaStore.Files.FileColumns.DATA)
                    }
                }.toTypedArray()

                val selection = "${MediaStore.Files.FileColumns.MEDIA_TYPE} != ? AND ${MediaStore.Files.FileColumns.MEDIA_TYPE} != ?"
                val selectionArgs = arrayOf(
                    MediaStore.Files.FileColumns.MEDIA_TYPE_IMAGE.toString(),
                    MediaStore.Files.FileColumns.MEDIA_TYPE_VIDEO.toString()
                )
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
                    val relCol = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                        cursor.getColumnIndex(MediaStore.Files.FileColumns.RELATIVE_PATH)
                    } else -1
                    @Suppress("DEPRECATION")
                    val dataCol = if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
                        cursor.getColumnIndex(MediaStore.Files.FileColumns.DATA)
                    } else -1

                    @Suppress("DEPRECATION")
                    val extPrefix = Environment.getExternalStorageDirectory()?.absolutePath?.trimEnd('/')?.plus("/")

                    while (cursor.moveToNext()) {
                        val id = cursor.getLong(idCol)
                        val name = cursor.getString(nameCol)?.trim().orEmpty()
                        val size = cursor.getLong(sizeCol)
                        if (name.isEmpty() || size <= 0L) continue
                        val lower = name.lowercase()
                        val ext = name.substringAfterLast('.', "").lowercase()
                        if (ext in mediaGalleryExtensions) continue
                        val cat = classifyFile(lower, ext, allowAnyNonHidden = false) ?: continue

                        val rawRel: String? = if (relCol >= 0) {
                            cursor.getString(relCol)?.trim('/')
                        } else if (dataCol >= 0 && extPrefix != null) {
                            val fullPath = cursor.getString(dataCol)
                            val parentPath = fullPath?.let { File(it).parentFile?.absolutePath }
                            if (parentPath?.startsWith(extPrefix) == true) parentPath.removePrefix(extPrefix) else null
                        } else null

                        val folder = normalizeFolderOrFallback(rawRel, cat)
                        val modMillis = cursor.getLong(dateCol) * 1000L
                        val mime = cursor.getString(mimeCol) ?: mimeForExtension(ext)
                        idxCounter++
                        out.add(
                            ScannedLocationEntry(
                                entry = LocalMediaEntry(
                                    manifestItem = ManifestItem(
                                        id = "${cat.name.lowercase()}_ms_$id",
                                        category = cat,
                                        fileName = name,
                                        relativeAlbumOrFolder = folder,
                                        sizeBytes = size,
                                        capturedEpochMillis = modMillis,
                                        dedupKey = "${folder.lowercase()}/${lower}_${size}_$modMillis",
                                        mimeType = mime
                                    ),
                                    contentUri = ContentUris.withAppendedId(filesUri, id)
                                ),
                                locationId = "vol:primary",
                                locationName = "Memoria interna (accesso parziale)"
                            )
                        )
                    }
                }
            } catch (t: Throwable) {
                DirectSwitchLog.warn("Scansione MediaStore.Files fallita", t)
            }
        }

        // Deduplica per percorso relativo esatto + nome file + dimensione byte (stesso nome in cartelle diverse resta distinto!)
        return out.distinctBy { item ->
            val f = item.entry.manifestItem.relativeAlbumOrFolder.lowercase()
            "${f}/${item.entry.manifestItem.fileName.lowercase()}_${item.entry.manifestItem.sizeBytes}"
        }
    }

    private fun mimeForExtension(ext: String): String {
        val lower = ext.lowercase()
        val systemMime = runCatching { MimeTypeMap.getSingleton().getMimeTypeFromExtension(lower) }.getOrNull()
        if (!systemMime.isNullOrBlank()) return systemMime
        return when (lower) {
            "pdf" -> "application/pdf"
            "zip" -> "application/zip"
            "txt" -> "text/plain"
            "csv" -> "text/csv"
            "vcf" -> "text/vcard"
            "ics" -> "text/calendar"
            "m4a" -> "audio/mp4"
            "mp3" -> "audio/mpeg"
            "opus" -> "audio/ogg"
            else -> "application/octet-stream"
        }
    }
}

/**
 * Scanner delle App installate dall'utente e Assistente Configurazione Account Mail / Cloud
 * (parità pratica con il catalogo app di Android Switch su telefoni già configurati).
 */
object InstalledAppsScanner {
    fun scanUserInstalledApps(context: Context): List<InstalledAppRecord> {
        return try {
            val pm = context.packageManager
            val mainIntent = Intent(Intent.ACTION_MAIN, null).apply {
                addCategory(Intent.CATEGORY_LAUNCHER)
            }
            val resolved = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                pm.queryIntentActivities(mainIntent, PackageManager.ResolveInfoFlags.of(0L))
            } else {
                @Suppress("DEPRECATION")
                pm.queryIntentActivities(mainIntent, 0)
            }
            val seen = HashSet<String>()
            val out = mutableListOf<InstalledAppRecord>()
            for (info in resolved) {
                val ai = info.activityInfo?.applicationInfo ?: continue
                val pkg = ai.packageName ?: continue
                if (pkg == context.packageName || !seen.add(pkg)) continue
                val isPureSystem = (ai.flags and ApplicationInfo.FLAG_SYSTEM) != 0 &&
                    (ai.flags and ApplicationInfo.FLAG_UPDATED_SYSTEM_APP) == 0
                if (isPureSystem) continue
                val label = ai.loadLabel(pm)?.toString()?.trim().orEmpty()
                if (label.isNotEmpty()) {
                    out.add(InstalledAppRecord(packageName = pkg, appName = label))
                }
            }
            out.sortedBy { it.appName.lowercase() }
        } catch (t: Throwable) {
            DirectSwitchLog.warn("Scansione app installate fallita", t)
            emptyList()
        }
    }

    fun openAppOnPlayStore(context: Context, record: InstalledAppRecord) {
        val marketIntent = Intent(
            Intent.ACTION_VIEW,
            Uri.parse("market://details?id=${Uri.encode(record.packageName)}")
        ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        val webIntent = Intent(
            Intent.ACTION_VIEW,
            Uri.parse("https://play.google.com/store/apps/details?id=${Uri.encode(record.packageName)}")
        ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        if (runCatching { context.startActivity(marketIntent) }.isFailure) {
            runCatching { context.startActivity(webIntent) }
        }
    }

    fun openAddAccountSettings(context: Context) {
        val addAcc = Intent(Settings.ACTION_ADD_ACCOUNT).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        val syncAcc = Intent(Settings.ACTION_SYNC_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        if (runCatching { context.startActivity(addAcc) }.isFailure) {
            runCatching { context.startActivity(syncAcc) }
        }
    }
}

/** Aggrega i conteggi locali e le cartelle rilevate per la dashboard iniziale e il controllo pre-trasferimento. */
object DeviceDataAnalyzer {
    fun scanSummary(context: Context): LocalDeviceScanSummary {
        val contacts = ContactsSmartMerger.readAllContacts(context).size
        val media = MediaExifScannerAndImporter.scanMediaEntries(context, includePhotos = true, includeVideos = true)
        val photos = media.filter { it.manifestItem.category == TransferCategory.PHOTOS }
        val videos = media.filter { it.manifestItem.category == TransferCategory.VIDEOS }
        val calendars = CalendarMigrator.readEvents(context).size
        val sms = SmsSystemScanner.countSms(context)
        val docPrecheck = DocumentsAndWhatsAppScanner.inspectPreTransferDocuments(
            context = context,
            includeDocuments = true,
            includeWhatsAppVault = true
        )
        val waEntries = DocumentsAndWhatsAppScanner.scanDocumentAndWhatsAppEntries(
            context = context,
            includeDocuments = false,
            includeWhatsAppVault = true
        )
        val appsCount = InstalledAppsScanner.scanUserInstalledApps(context).size
        val (freeBytes, totalBytes) = StorageCapacityChecker.getFreeAndTotalBytes(context)

        return LocalDeviceScanSummary(
            contactsCount = contacts,
            photosCount = photos.size,
            photosBytes = photos.sumOf { it.manifestItem.sizeBytes },
            videosCount = videos.size,
            videosBytes = videos.sumOf { it.manifestItem.sizeBytes },
            calendarEventsCount = calendars,
            smsCount = sms,
            documentsCount = docPrecheck.totalFiles,
            documentsBytes = docPrecheck.totalBytes,
            documentFoldersCount = docPrecheck.folderSummaries.size,
            hasAllFilesAccess = docPrecheck.hasAllFilesAccess,
            documentFolderSummaries = docPrecheck.folderSummaries,
            documentLocationSummaries = docPrecheck.locationSummaries,
            whatsappArchivesCount = waEntries.size,
            installedAppsCount = appsCount,
            freeStorageBytes = freeBytes,
            totalStorageBytes = totalBytes
        )
    }
}
