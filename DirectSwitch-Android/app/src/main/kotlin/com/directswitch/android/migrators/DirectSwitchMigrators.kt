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
import android.util.Base64
import android.webkit.MimeTypeMap
import androidx.core.content.ContextCompat
import androidx.documentfile.provider.DocumentFile
import com.directswitch.android.DirectSwitchLog
import com.directswitch.android.protocol.CalendarEventRecord
import com.directswitch.android.protocol.ContactTransferRecord
import com.directswitch.android.protocol.DevicePlatform
import com.directswitch.android.protocol.DirectSwitchJson
import com.directswitch.android.protocol.InstalledAppRecord
import com.directswitch.android.protocol.LabeledValueRecord
import com.directswitch.android.protocol.ManifestItem
import com.directswitch.android.protocol.PhoneNormalizer
import com.directswitch.android.protocol.PostalAddressTransferRecord
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

    internal fun mediaStoreFileExists(
        context: Context,
        collectionUri: Uri,
        relPath: String,
        displayName: String,
        expectedSizeBytes: Long
    ): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return false
        return try {
            val normalizedRel = if (relPath.endsWith("/")) relPath else "$relPath/"
            val selection = if (expectedSizeBytes > 0L) {
                "${MediaStore.MediaColumns.DISPLAY_NAME} = ? AND ${MediaStore.MediaColumns.RELATIVE_PATH} = ? AND ${MediaStore.MediaColumns.SIZE} = ?"
            } else {
                "${MediaStore.MediaColumns.DISPLAY_NAME} = ? AND ${MediaStore.MediaColumns.RELATIVE_PATH} = ?"
            }
            val args = if (expectedSizeBytes > 0L) {
                arrayOf(displayName, normalizedRel, expectedSizeBytes.toString())
            } else {
                arrayOf(displayName, normalizedRel)
            }
            context.contentResolver.query(
                collectionUri,
                arrayOf(MediaStore.MediaColumns._ID),
                selection,
                args,
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

    private fun encodePhoneLabel(type: Int, customLabel: String?): String = when (type) {
        ContactsContract.CommonDataKinds.Phone.TYPE_MOBILE -> "mobile"
        ContactsContract.CommonDataKinds.Phone.TYPE_HOME -> "home"
        ContactsContract.CommonDataKinds.Phone.TYPE_WORK -> "work"
        ContactsContract.CommonDataKinds.Phone.TYPE_MAIN -> "main"
        ContactsContract.CommonDataKinds.Phone.TYPE_CUSTOM -> customLabel?.trim().takeIf { !it.isNullOrEmpty() } ?: "other"
        else -> "other"
    }

    private fun decodePhoneType(tag: String): Pair<Int, String?> = when (tag.lowercase()) {
        "mobile", "iphone" -> ContactsContract.CommonDataKinds.Phone.TYPE_MOBILE to null
        "home" -> ContactsContract.CommonDataKinds.Phone.TYPE_HOME to null
        "work" -> ContactsContract.CommonDataKinds.Phone.TYPE_WORK to null
        "main" -> ContactsContract.CommonDataKinds.Phone.TYPE_MAIN to null
        "other", "" -> ContactsContract.CommonDataKinds.Phone.TYPE_OTHER to null
        else -> ContactsContract.CommonDataKinds.Phone.TYPE_CUSTOM to tag
    }

    private fun encodeGenericLabel(type: Int, customLabel: String?): String = when (type) {
        ContactsContract.CommonDataKinds.Email.TYPE_HOME -> "home"
        ContactsContract.CommonDataKinds.Email.TYPE_WORK -> "work"
        ContactsContract.CommonDataKinds.Email.TYPE_CUSTOM -> customLabel?.trim().takeIf { !it.isNullOrEmpty() } ?: "other"
        else -> "other"
    }

    private fun decodeEmailType(tag: String): Pair<Int, String?> = when (tag.lowercase()) {
        "home" -> ContactsContract.CommonDataKinds.Email.TYPE_HOME to null
        "work" -> ContactsContract.CommonDataKinds.Email.TYPE_WORK to null
        "other", "" -> ContactsContract.CommonDataKinds.Email.TYPE_OTHER to null
        else -> ContactsContract.CommonDataKinds.Email.TYPE_CUSTOM to tag
    }

    private fun decodePostalType(tag: String): Pair<Int, String?> = when (tag.lowercase()) {
        "home" -> ContactsContract.CommonDataKinds.StructuredPostal.TYPE_HOME to null
        "work" -> ContactsContract.CommonDataKinds.StructuredPostal.TYPE_WORK to null
        "other", "" -> ContactsContract.CommonDataKinds.StructuredPostal.TYPE_OTHER to null
        else -> ContactsContract.CommonDataKinds.StructuredPostal.TYPE_CUSTOM to tag
    }

    private fun parseBirthday(raw: String): Triple<Int?, Int?, Int?>? {
        val clean = raw.trim()
        // Formati standard Android: YYYY-MM-DD oppure --MM-DD
        val fullMatch = Regex("""^(\d{4})-(\d{1,2})-(\d{1,2})""").find(clean)
        if (fullMatch != null) {
            val y = fullMatch.groupValues[1].toIntOrNull()
            val m = fullMatch.groupValues[2].toIntOrNull()
            val d = fullMatch.groupValues[3].toIntOrNull()
            if (m != null && d != null && m in 1..12 && d in 1..31) return Triple(y, m, d)
        }
        val noYearMatch = Regex("""^--(\d{1,2})-(\d{1,2})""").find(clean)
        if (noYearMatch != null) {
            val m = noYearMatch.groupValues[1].toIntOrNull()
            val d = noYearMatch.groupValues[2].toIntOrNull()
            if (m != null && d != null && m in 1..12 && d in 1..31) return Triple(null, m, d)
        }
        return null
    }

    fun readAllContacts(context: Context): List<ContactTransferRecord> {
        if (!hasReadPermission(context)) return emptyList()
        val resolver = context.contentResolver
        val namesById = LinkedHashMap<String, String>()
        val givenById = HashMap<String, String>()
        val familyById = HashMap<String, String>()
        val orgById = HashMap<String, Pair<String?, String?>>()
        val nickById = HashMap<String, String>()
        val birthdayById = HashMap<String, Triple<Int?, Int?, Int?>>()
        val labeledPhonesById = HashMap<String, MutableList<LabeledValueRecord>>()
        val labeledEmailsById = HashMap<String, MutableList<LabeledValueRecord>>()
        val urlsById = HashMap<String, MutableList<String>>()
        val addressesById = HashMap<String, MutableList<PostalAddressTransferRecord>>()
        val avatarById = HashMap<String, String>()

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
                ContactsContract.CommonDataKinds.Phone.NUMBER,
                ContactsContract.CommonDataKinds.Phone.TYPE,
                ContactsContract.CommonDataKinds.Phone.LABEL
            ),
            null,
            null,
            null
        )?.use { cursor ->
            val idIdx = cursor.getColumnIndexOrThrow(ContactsContract.CommonDataKinds.Phone.CONTACT_ID)
            val numIdx = cursor.getColumnIndexOrThrow(ContactsContract.CommonDataKinds.Phone.NUMBER)
            val typeIdx = cursor.getColumnIndexOrThrow(ContactsContract.CommonDataKinds.Phone.TYPE)
            val labelIdx = cursor.getColumnIndexOrThrow(ContactsContract.CommonDataKinds.Phone.LABEL)
            while (cursor.moveToNext()) {
                val id = cursor.getString(idIdx) ?: continue
                val num = cursor.getString(numIdx)?.trim().orEmpty()
                if (num.isNotEmpty()) {
                    val tag = encodePhoneLabel(cursor.getInt(typeIdx), cursor.getString(labelIdx))
                    labeledPhonesById.getOrPut(id) { mutableListOf() }.add(LabeledValueRecord(tag, num))
                }
            }
        }

        resolver.query(
            ContactsContract.CommonDataKinds.Email.CONTENT_URI,
            arrayOf(
                ContactsContract.CommonDataKinds.Email.CONTACT_ID,
                ContactsContract.CommonDataKinds.Email.ADDRESS,
                ContactsContract.CommonDataKinds.Email.TYPE,
                ContactsContract.CommonDataKinds.Email.LABEL
            ),
            null,
            null,
            null
        )?.use { cursor ->
            val idIdx = cursor.getColumnIndexOrThrow(ContactsContract.CommonDataKinds.Email.CONTACT_ID)
            val emailIdx = cursor.getColumnIndexOrThrow(ContactsContract.CommonDataKinds.Email.ADDRESS)
            val typeIdx = cursor.getColumnIndexOrThrow(ContactsContract.CommonDataKinds.Email.TYPE)
            val labelIdx = cursor.getColumnIndexOrThrow(ContactsContract.CommonDataKinds.Email.LABEL)
            while (cursor.moveToNext()) {
                val id = cursor.getString(idIdx) ?: continue
                val mail = cursor.getString(emailIdx)?.trim().orEmpty()
                if (mail.isNotEmpty()) {
                    val tag = encodeGenericLabel(cursor.getInt(typeIdx), cursor.getString(labelIdx))
                    labeledEmailsById.getOrPut(id) { mutableListOf() }.add(LabeledValueRecord(tag, mail))
                }
            }
        }

        // Lettura dettagli ricchi in una sola query su ContactsContract.Data (Nome/Cognome, Azienda, Compleanno, Indirizzi, Siti, Foto)
        val wantedMimeTypes = arrayOf(
            ContactsContract.CommonDataKinds.StructuredName.CONTENT_ITEM_TYPE,
            ContactsContract.CommonDataKinds.Organization.CONTENT_ITEM_TYPE,
            ContactsContract.CommonDataKinds.Nickname.CONTENT_ITEM_TYPE,
            ContactsContract.CommonDataKinds.Website.CONTENT_ITEM_TYPE,
            ContactsContract.CommonDataKinds.StructuredPostal.CONTENT_ITEM_TYPE,
            ContactsContract.CommonDataKinds.Event.CONTENT_ITEM_TYPE,
            ContactsContract.CommonDataKinds.Photo.CONTENT_ITEM_TYPE
        )
        val placeholders = wantedMimeTypes.joinToString(",") { "?" }
        runCatching {
            resolver.query(
                ContactsContract.Data.CONTENT_URI,
                arrayOf(
                    ContactsContract.Data.CONTACT_ID,
                    ContactsContract.Data.MIMETYPE,
                    ContactsContract.Data.DATA1,
                    ContactsContract.Data.DATA2,
                    ContactsContract.Data.DATA3,
                    ContactsContract.Data.DATA4,
                    ContactsContract.Data.DATA7,
                    ContactsContract.Data.DATA8,
                    ContactsContract.Data.DATA9,
                    ContactsContract.Data.DATA10,
                    ContactsContract.Data.DATA15
                ),
                "${ContactsContract.Data.MIMETYPE} IN ($placeholders)",
                wantedMimeTypes,
                null
            )?.use { c ->
                val cidIdx = c.getColumnIndexOrThrow(ContactsContract.Data.CONTACT_ID)
                val mimeIdx = c.getColumnIndexOrThrow(ContactsContract.Data.MIMETYPE)
                val d1Idx = c.getColumnIndexOrThrow(ContactsContract.Data.DATA1)
                val d2Idx = c.getColumnIndexOrThrow(ContactsContract.Data.DATA2)
                val d3Idx = c.getColumnIndexOrThrow(ContactsContract.Data.DATA3)
                val d4Idx = c.getColumnIndexOrThrow(ContactsContract.Data.DATA4)
                val d7Idx = c.getColumnIndexOrThrow(ContactsContract.Data.DATA7)
                val d8Idx = c.getColumnIndexOrThrow(ContactsContract.Data.DATA8)
                val d9Idx = c.getColumnIndexOrThrow(ContactsContract.Data.DATA9)
                val d10Idx = c.getColumnIndexOrThrow(ContactsContract.Data.DATA10)
                val d15Idx = c.getColumnIndexOrThrow(ContactsContract.Data.DATA15)

                while (c.moveToNext()) {
                    val cid = c.getString(cidIdx) ?: continue
                    when (c.getString(mimeIdx)) {
                        ContactsContract.CommonDataKinds.StructuredName.CONTENT_ITEM_TYPE -> {
                            val g = c.getString(d2Idx)?.trim().orEmpty()
                            val f = c.getString(d3Idx)?.trim().orEmpty()
                            if (g.isNotEmpty() && !givenById.containsKey(cid)) givenById[cid] = g
                            if (f.isNotEmpty() && !familyById.containsKey(cid)) familyById[cid] = f
                        }
                        ContactsContract.CommonDataKinds.Organization.CONTENT_ITEM_TYPE -> {
                            val company = c.getString(d1Idx)?.trim()?.takeIf { it.isNotEmpty() }
                            val title = c.getString(d4Idx)?.trim()?.takeIf { it.isNotEmpty() }
                            if (company != null || title != null) orgById[cid] = company to title
                        }
                        ContactsContract.CommonDataKinds.Nickname.CONTENT_ITEM_TYPE -> {
                            val nick = c.getString(d1Idx)?.trim()?.takeIf { it.isNotEmpty() }
                            if (nick != null) nickById[cid] = nick
                        }
                        ContactsContract.CommonDataKinds.Website.CONTENT_ITEM_TYPE -> {
                            val u = c.getString(d1Idx)?.trim()?.takeIf { it.isNotEmpty() }
                            if (u != null) urlsById.getOrPut(cid) { mutableListOf() }.add(u)
                        }
                        ContactsContract.CommonDataKinds.StructuredPostal.CONTENT_ITEM_TYPE -> {
                            val street = c.getString(d4Idx)?.trim().orEmpty()
                            val city = c.getString(d7Idx)?.trim().orEmpty()
                            val region = c.getString(d8Idx)?.trim().orEmpty()
                            val postcode = c.getString(d9Idx)?.trim().orEmpty()
                            val country = c.getString(d10Idx)?.trim().orEmpty()
                            if (street.isNotEmpty() || city.isNotEmpty() || postcode.isNotEmpty() || country.isNotEmpty()) {
                                val tag = encodeGenericLabel(c.getInt(d2Idx), c.getString(d3Idx))
                                addressesById.getOrPut(cid) { mutableListOf() }.add(
                                    PostalAddressTransferRecord(
                                        label = tag,
                                        street = street,
                                        city = city,
                                        state = region,
                                        postalCode = postcode,
                                        country = country
                                    )
                                )
                            }
                        }
                        ContactsContract.CommonDataKinds.Event.CONTENT_ITEM_TYPE -> {
                            if (c.getInt(d2Idx) == ContactsContract.CommonDataKinds.Event.TYPE_BIRTHDAY) {
                                val rawDate = c.getString(d1Idx).orEmpty()
                                parseBirthday(rawDate)?.let { birthdayById[cid] = it }
                            }
                        }
                        ContactsContract.CommonDataKinds.Photo.CONTENT_ITEM_TYPE -> {
                            if (!avatarById.containsKey(cid)) {
                                val blob = c.getBlob(d15Idx)
                                if (blob != null && blob.isNotEmpty() && blob.size <= 65_536) {
                                    avatarById[cid] = Base64.encodeToString(blob, Base64.NO_WRAP)
                                }
                            }
                        }
                    }
                }
            }
        }

        return namesById.mapNotNull { (id, name) ->
            val lPhones = labeledPhonesById[id]?.distinctBy { it.value }.orEmpty()
            val phones = lPhones.map { it.value }
            val lEmails = labeledEmailsById[id]?.distinctBy { it.value.lowercase() }.orEmpty()
            val emails = lEmails.map { it.value }
            val org = orgById[id]
            val bday = birthdayById[id]
            val urls = urlsById[id]?.distinct()
            val addrs = addressesById[id]
            if (phones.isEmpty() && emails.isEmpty() && org == null) null
            else ContactTransferRecord(
                id = id,
                displayName = name,
                phones = phones,
                emails = emails,
                organization = org?.first,
                givenName = givenById[id],
                familyName = familyById[id],
                nickname = nickById[id],
                jobTitle = org?.second,
                birthdayYear = bday?.first,
                birthdayMonth = bday?.second,
                birthdayDay = bday?.third,
                labeledPhones = lPhones.ifEmpty { null },
                labeledEmails = lEmails.ifEmpty { null },
                urls = urls?.ifEmpty { null },
                postalAddresses = addrs?.ifEmpty { null },
                avatarJpegBase64 = avatarById[id]
            )
        }
    }

    /**
     * Inserisce solo i contatti non ancora presenti (confronto per numero normalizzato E.164, email o nome).
     * Preserva nome/cognome separati, azienda, ruolo, compleanno, indirizzi, siti, etichette e foto contatto.
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
        val existingNameOnly = existing
            .filter { it.phones.isEmpty() && it.emails.isEmpty() }
            .map { it.displayName.trim().lowercase() }
            .toHashSet()

        var inserted = 0
        var skipped = 0

        for (contact in incoming) {
            val normalizedPhones = contact.phones
                .map { PhoneNormalizer.normalizeKey(it) }
                .filter { it.isNotEmpty() }
            val normalizedEmails = contact.emails.map { it.lowercase() }
            val normName = contact.displayName.trim().lowercase()

            val alreadyExists = if (normalizedPhones.isNotEmpty() || normalizedEmails.isNotEmpty()) {
                normalizedPhones.any { it in existingPhoneKeys } || normalizedEmails.any { it in existingEmails }
            } else {
                normName.isEmpty() || normName in existingNameOnly
            }

            if (alreadyExists) {
                skipped++
                continue
            }

            if (insertSingleContact(context, contact)) {
                inserted++
                existingPhoneKeys.addAll(normalizedPhones)
                existingEmails.addAll(normalizedEmails)
                if (normalizedPhones.isEmpty() && normalizedEmails.isEmpty() && normName.isNotEmpty()) {
                    existingNameOnly.add(normName)
                }
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
            val nameOp = ContentProviderOperation.newInsert(ContactsContract.Data.CONTENT_URI)
                .withValueBackReference(ContactsContract.Data.RAW_CONTACT_ID, 0)
                .withValue(
                    ContactsContract.Data.MIMETYPE,
                    ContactsContract.CommonDataKinds.StructuredName.CONTENT_ITEM_TYPE
                )
                .withValue(ContactsContract.CommonDataKinds.StructuredName.DISPLAY_NAME, record.displayName)
            if (!record.givenName.isNullOrBlank()) {
                nameOp.withValue(ContactsContract.CommonDataKinds.StructuredName.GIVEN_NAME, record.givenName)
            }
            if (!record.familyName.isNullOrBlank()) {
                nameOp.withValue(ContactsContract.CommonDataKinds.StructuredName.FAMILY_NAME, record.familyName)
            }
            ops.add(nameOp.build())

            val phonesToInsert = record.labeledPhones?.takeIf { it.isNotEmpty() }
                ?: record.phones.map { LabeledValueRecord("mobile", it) }
            for (lp in phonesToInsert) {
                val (pType, customLbl) = decodePhoneType(lp.label)
                val b = ContentProviderOperation.newInsert(ContactsContract.Data.CONTENT_URI)
                    .withValueBackReference(ContactsContract.Data.RAW_CONTACT_ID, 0)
                    .withValue(
                        ContactsContract.Data.MIMETYPE,
                        ContactsContract.CommonDataKinds.Phone.CONTENT_ITEM_TYPE
                    )
                    .withValue(ContactsContract.CommonDataKinds.Phone.NUMBER, lp.value)
                    .withValue(ContactsContract.CommonDataKinds.Phone.TYPE, pType)
                if (customLbl != null) b.withValue(ContactsContract.CommonDataKinds.Phone.LABEL, customLbl)
                ops.add(b.build())
            }

            val emailsToInsert = record.labeledEmails?.takeIf { it.isNotEmpty() }
                ?: record.emails.map { LabeledValueRecord("other", it) }
            for (le in emailsToInsert) {
                val (eType, customLbl) = decodeEmailType(le.label)
                val b = ContentProviderOperation.newInsert(ContactsContract.Data.CONTENT_URI)
                    .withValueBackReference(ContactsContract.Data.RAW_CONTACT_ID, 0)
                    .withValue(
                        ContactsContract.Data.MIMETYPE,
                        ContactsContract.CommonDataKinds.Email.CONTENT_ITEM_TYPE
                    )
                    .withValue(ContactsContract.CommonDataKinds.Email.ADDRESS, le.value)
                    .withValue(ContactsContract.CommonDataKinds.Email.TYPE, eType)
                if (customLbl != null) b.withValue(ContactsContract.CommonDataKinds.Email.LABEL, customLbl)
                ops.add(b.build())
            }

            if (!record.organization.isNullOrBlank() || !record.jobTitle.isNullOrBlank()) {
                val orgOp = ContentProviderOperation.newInsert(ContactsContract.Data.CONTENT_URI)
                    .withValueBackReference(ContactsContract.Data.RAW_CONTACT_ID, 0)
                    .withValue(
                        ContactsContract.Data.MIMETYPE,
                        ContactsContract.CommonDataKinds.Organization.CONTENT_ITEM_TYPE
                    )
                    .withValue(
                        ContactsContract.CommonDataKinds.Organization.TYPE,
                        ContactsContract.CommonDataKinds.Organization.TYPE_WORK
                    )
                if (!record.organization.isNullOrBlank()) {
                    orgOp.withValue(ContactsContract.CommonDataKinds.Organization.COMPANY, record.organization)
                }
                if (!record.jobTitle.isNullOrBlank()) {
                    orgOp.withValue(ContactsContract.CommonDataKinds.Organization.TITLE, record.jobTitle)
                }
                ops.add(orgOp.build())
            }

            if (!record.nickname.isNullOrBlank()) {
                ops.add(
                    ContentProviderOperation.newInsert(ContactsContract.Data.CONTENT_URI)
                        .withValueBackReference(ContactsContract.Data.RAW_CONTACT_ID, 0)
                        .withValue(
                            ContactsContract.Data.MIMETYPE,
                            ContactsContract.CommonDataKinds.Nickname.CONTENT_ITEM_TYPE
                        )
                        .withValue(ContactsContract.CommonDataKinds.Nickname.NAME, record.nickname)
                        .build()
                )
            }

            val bMonth = record.birthdayMonth
            val bDay = record.birthdayDay
            if (bMonth != null && bDay != null && bMonth in 1..12 && bDay in 1..31) {
                val bYear = record.birthdayYear
                val formattedDate = if (bYear != null && bYear > 1900) {
                    String.format(java.util.Locale.US, "%04d-%02d-%02d", bYear, bMonth, bDay)
                } else {
                    String.format(java.util.Locale.US, "--%02d-%02d", bMonth, bDay)
                }
                ops.add(
                    ContentProviderOperation.newInsert(ContactsContract.Data.CONTENT_URI)
                        .withValueBackReference(ContactsContract.Data.RAW_CONTACT_ID, 0)
                        .withValue(
                            ContactsContract.Data.MIMETYPE,
                            ContactsContract.CommonDataKinds.Event.CONTENT_ITEM_TYPE
                        )
                        .withValue(ContactsContract.CommonDataKinds.Event.START_DATE, formattedDate)
                        .withValue(
                            ContactsContract.CommonDataKinds.Event.TYPE,
                            ContactsContract.CommonDataKinds.Event.TYPE_BIRTHDAY
                        )
                        .build()
                )
            }

            record.urls?.forEach { url ->
                if (url.isNotBlank()) {
                    ops.add(
                        ContentProviderOperation.newInsert(ContactsContract.Data.CONTENT_URI)
                            .withValueBackReference(ContactsContract.Data.RAW_CONTACT_ID, 0)
                            .withValue(
                                ContactsContract.Data.MIMETYPE,
                                ContactsContract.CommonDataKinds.Website.CONTENT_ITEM_TYPE
                            )
                            .withValue(ContactsContract.CommonDataKinds.Website.URL, url)
                            .build()
                    )
                }
            }

            record.postalAddresses?.forEach { addr ->
                val (aType, customLbl) = decodePostalType(addr.label ?: "home")
                val ab = ContentProviderOperation.newInsert(ContactsContract.Data.CONTENT_URI)
                    .withValueBackReference(ContactsContract.Data.RAW_CONTACT_ID, 0)
                    .withValue(
                        ContactsContract.Data.MIMETYPE,
                        ContactsContract.CommonDataKinds.StructuredPostal.CONTENT_ITEM_TYPE
                    )
                    .withValue(ContactsContract.CommonDataKinds.StructuredPostal.STREET, addr.street)
                    .withValue(ContactsContract.CommonDataKinds.StructuredPostal.CITY, addr.city)
                    .withValue(ContactsContract.CommonDataKinds.StructuredPostal.REGION, addr.state)
                    .withValue(ContactsContract.CommonDataKinds.StructuredPostal.POSTCODE, addr.postalCode)
                    .withValue(ContactsContract.CommonDataKinds.StructuredPostal.COUNTRY, addr.country)
                    .withValue(ContactsContract.CommonDataKinds.StructuredPostal.TYPE, aType)
                if (customLbl != null) ab.withValue(ContactsContract.CommonDataKinds.StructuredPostal.LABEL, customLbl)
                ops.add(ab.build())
            }

            if (!record.avatarJpegBase64.isNullOrBlank()) {
                val imgBytes = runCatching { Base64.decode(record.avatarJpegBase64, Base64.DEFAULT) }.getOrNull()
                if (imgBytes != null && imgBytes.isNotEmpty()) {
                    ops.add(
                        ContentProviderOperation.newInsert(ContactsContract.Data.CONTENT_URI)
                            .withValueBackReference(ContactsContract.Data.RAW_CONTACT_ID, 0)
                            .withValue(
                                ContactsContract.Data.MIMETYPE,
                                ContactsContract.CommonDataKinds.Photo.CONTENT_ITEM_TYPE
                            )
                            .withValue(ContactsContract.CommonDataKinds.Photo.PHOTO, imgBytes)
                            .build()
                    )
                }
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

    internal fun resolveEffectiveTimestampMillis(
        dateTakenMillis: Long,
        dateModifiedSeconds: Long
    ): Long = when {
        dateTakenMillis > 0L -> dateTakenMillis
        dateModifiedSeconds > 0L -> dateModifiedSeconds * 1000L
        else -> 0L
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
            MediaStore.MediaColumns.DATE_MODIFIED,
            MediaStore.MediaColumns.BUCKET_DISPLAY_NAME,
            MediaStore.MediaColumns.MIME_TYPE
        )
        try {
            context.contentResolver.query(
                collectionUri,
                projection,
                null,
                null,
                "${MediaStore.MediaColumns.DATE_MODIFIED} DESC"
            )?.use { cursor ->
                val idCol = cursor.getColumnIndexOrThrow(MediaStore.MediaColumns._ID)
                val nameCol = cursor.getColumnIndexOrThrow(MediaStore.MediaColumns.DISPLAY_NAME)
                val sizeCol = cursor.getColumnIndexOrThrow(MediaStore.MediaColumns.SIZE)
                val dateCol = cursor.getColumnIndexOrThrow(MediaStore.MediaColumns.DATE_TAKEN)
                val modCol = cursor.getColumnIndexOrThrow(MediaStore.MediaColumns.DATE_MODIFIED)
                val bucketCol = cursor.getColumnIndexOrThrow(MediaStore.MediaColumns.BUCKET_DISPLAY_NAME)
                val mimeCol = cursor.getColumnIndexOrThrow(MediaStore.MediaColumns.MIME_TYPE)

                while (cursor.moveToNext()) {
                    val id = cursor.getLong(idCol)
                    val name = cursor.getString(nameCol) ?: "media_$id"
                    val size = cursor.getLong(sizeCol)
                    if (size <= 0L) continue
                    val rawDateTaken = cursor.getLong(dateCol)
                    val rawDateModifiedSec = cursor.getLong(modCol)
                    val dateTaken = resolveEffectiveTimestampMillis(rawDateTaken, rawDateModifiedSec)
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

    internal fun resolveRelativeMediaPath(
        rawAlbum: String,
        isVideo: Boolean,
        dcimDir: String = "DCIM",
        moviesDir: String = "Movies",
        picturesDir: String = "Pictures"
    ): String {
        val segments = PublicDownloadsSaver.sanitizedRelativeSegments(rawAlbum)
        if (segments.isEmpty()) {
            val fallback = if (isVideo) "Video" else "Foto"
            val root = if (isVideo) moviesDir else picturesDir
            return "$root/$fallback"
        }
        val first = segments.first()
        if (segments.size == 1 && (
                first.equals("iPhone_Camera", ignoreCase = true) ||
                    first.equals("Camera", ignoreCase = true) ||
                    first.equals("Camera Roll", ignoreCase = true) ||
                    first.equals("Recenti", ignoreCase = true) ||
                    first.equals("Recent", ignoreCase = true) ||
                    first.equals("Rullino", ignoreCase = true)
            )
        ) {
            return "$dcimDir/Camera"
        }
        if (first.equals("DCIM", ignoreCase = true)) {
            val rest = segments.drop(1).joinToString("/").ifEmpty { "Camera" }
            return "$dcimDir/$rest"
        }
        val safeSubpath = segments.joinToString("/")
        val root = if (isVideo) moviesDir else picturesDir
        return "$root/$safeSubpath"
    }

    fun importMediaStream(
        context: Context,
        item: ManifestItem,
        plainInputStream: InputStream
    ): Boolean {
        return try {
            val resolver = context.contentResolver
            val isVideo = item.category == TransferCategory.VIDEOS

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                val baseRelPath = resolveRelativeMediaPath(
                    rawAlbum = item.relativeAlbumOrFolder,
                    isVideo = isVideo,
                    dcimDir = Environment.DIRECTORY_DCIM,
                    moviesDir = Environment.DIRECTORY_MOVIES,
                    picturesDir = Environment.DIRECTORY_PICTURES
                )
                val collection = if (isVideo) {
                    MediaStore.Video.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
                } else {
                    MediaStore.Images.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
                }
                if (PublicDownloadsSaver.mediaStoreFileExists(
                        context = context,
                        collectionUri = collection,
                        relPath = baseRelPath,
                        displayName = item.fileName,
                        expectedSizeBytes = item.sizeBytes
                    )
                ) {
                    return true
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
                val relPath = resolveRelativeMediaPath(
                    rawAlbum = item.relativeAlbumOrFolder,
                    isVideo = isVideo
                )
                @Suppress("DEPRECATION")
                val albumDir = File(Environment.getExternalStorageDirectory(), relPath)
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
            val clean = PublicDownloadsSaver.sanitizedRelativeSegments(rawFolder.orEmpty()).joinToString("/")
            if (cat == TransferCategory.WHATSAPP_VAULT) {
                return if (clean.startsWith("Android/media/com.whatsapp", ignoreCase = true)) clean else "WhatsApp_Vault"
            }
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

            // 3B. Su Android -> Android con Accesso completo ai file, include anche la cartella locale WhatsApp
            // (`/Android/media/com.whatsapp/WhatsApp`) per consentire il ripristino locale di `msgstore` + Media senza Android Switch né Drive
            if (includeWhatsAppVault) {
                @Suppress("DEPRECATION")
                val primaryRoot = Environment.getExternalStorageDirectory()
                val waRoots = listOfNotNull(
                    primaryRoot?.let { File(it, "Android/media/com.whatsapp/WhatsApp") },
                    primaryRoot?.let { File(it, "Android/media/com.whatsapp.w4b/WhatsApp Business") }
                )
                val primaryPrefix = primaryRoot?.absolutePath?.trimEnd('/')?.plus("/") ?: ""
                for (waBase in waRoots) {
                    if (!waBase.exists() || !waBase.isDirectory || !waBase.canRead()) continue
                    waBase.walkTopDown().maxDepth(8).forEach { waFile ->
                        if (!waFile.isFile || waFile.length() <= 0L || waFile.name.startsWith(".")) return@forEach
                        val parentAbs = waFile.parentFile?.absolutePath ?: return@forEach
                        if (!parentAbs.startsWith(primaryPrefix)) return@forEach
                        val relFolder = PublicDownloadsSaver.sanitizedRelativeSegments(parentAbs.removePrefix(primaryPrefix)).joinToString("/")
                        val ext = waFile.extension.lowercase()
                        idxCounter++
                        out.add(
                            ScannedLocationEntry(
                                entry = LocalMediaEntry(
                                    manifestItem = ManifestItem(
                                        id = "whatsapp_vault_media_$idxCounter",
                                        category = TransferCategory.WHATSAPP_VAULT,
                                        fileName = waFile.name,
                                        relativeAlbumOrFolder = relFolder,
                                        sizeBytes = waFile.length(),
                                        capturedEpochMillis = waFile.lastModified(),
                                        dedupKey = "${relFolder.lowercase()}/${waFile.name.lowercase()}_${waFile.length()}_${waFile.lastModified()}",
                                        mimeType = mimeForExtension(ext)
                                    ),
                                    contentUri = Uri.fromFile(waFile)
                                ),
                                locationId = "vault:whatsapp_native",
                                locationName = "WhatsApp Locale"
                            )
                        )
                    }
                }
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
    sealed class PlayStoreTarget {
        data class ExactPackage(val packageName: String) : PlayStoreTarget()
        data class SearchByName(val query: String) : PlayStoreTarget()
    }

    data class InstalledAppsSnapshot(
        val packageNames: Set<String>,
        val normalizedLabels: Set<String>
    )

    private val alwaysIncludeCrossPlatformGoogleApps = setOf(
        "com.android.chrome",
        "com.google.android.apps.maps",
        "com.google.android.apps.photos",
        "com.google.android.youtube",
        "com.google.android.gm",
        "com.google.android.apps.docs",
        "com.google.android.apps.docs.editors.docs",
        "com.google.android.apps.docs.editors.sheets",
        "com.google.android.apps.docs.editors.slides",
        "com.google.android.apps.meetings",
        "com.google.android.apps.tachyon",
        "com.google.android.apps.translate",
        "com.google.android.keep",
        "com.google.android.calendar",
        "com.google.android.apps.youtube.music",
        "com.google.android.apps.authenticator2",
        "com.google.android.apps.bard"
    )

    private val excludedAndroidOsPackages = setOf(
        "com.android.vending",
        "com.google.android.gms",
        "com.google.android.gsf",
        "com.google.android.webview",
        "com.android.webview",
        "com.google.android.tts",
        "com.google.android.as",
        "com.google.android.projection.gearhead",
        "com.google.android.apps.wellbeing",
        "com.google.android.setupwizard",
        "com.google.android.apps.restore",
        "com.google.android.apps.turbo",
        "com.google.android.marvin.talkback",
        "com.google.android.gms.supervision",
        "com.google.android.inputmethod.latin",
        "com.google.android.dialer",
        "com.android.dialer",
        "com.google.android.contacts",
        "com.android.contacts",
        "com.google.android.apps.messaging",
        "com.android.messaging",
        "com.android.mms",
        "com.google.android.calculator",
        "com.android.calculator2",
        "com.google.android.deskclock",
        "com.android.deskclock",
        "com.android.settings",
        "com.android.systemui",
        "com.android.stk",
        "com.android.camera2",
        "com.google.android.googlecamera",
        "com.android.gallery3d",
        "com.google.android.apps.nbu.files",
        "com.android.documentsui",
        "com.google.android.documentsui",
        "com.google.android.apps.nexuslauncher",
        "com.google.android.apps.pixelmigrate",
        "com.sec.android.app.camera",
        "com.sec.android.gallery3d",
        "com.sec.android.app.launcher",
        "com.samsung.android.dialer",
        "com.samsung.android.messaging",
        "com.samsung.android.app.contacts",
        "com.samsung.android.calendar",
        "com.samsung.android.honeyboard",
        "com.samsung.android.scloud",
        "com.samsung.android.smartswitchassistant",
        "com.samsung.android.spay",
        "com.xiaomi.mipicks"
    )

    private val excludedSystemPrefixes = listOf(
        "com.sec.android.",
        "com.samsung.android.bixby",
        "com.samsung.android.app.routines",
        "com.samsung.android.mdx",
        "com.samsung.android.oneconnect.onboarding",
        "com.samsung.android.game.",
        "com.samsung.android.arzone",
        "com.google.android.ext.",
        "com.google.android.overlay.",
        "com.android.providers.",
        "com.miui.",
        "com.coloros.",
        "com.oppo.launcher",
        "com.qualcomm.",
        "com.heytap."
    )

    private val iosBundleToAndroidPackage: Map<String, String> = mapOf(
        "net.whatsapp.whatsapp" to "com.whatsapp",
        "net.whatsapp.whatsappsmb" to "com.whatsapp.w4b",
        "com.burbn.instagram" to "com.instagram.android",
        "ph.telegra.telegraph" to "org.telegram.messenger",
        "com.facebook.facebook" to "com.facebook.katana",
        "com.facebook.messenger" to "com.facebook.orca",
        "com.zhiliaoapp.musically" to "com.zhiliaoapp.musically",
        "com.google.ios.youtube" to "com.google.android.youtube",
        "com.google.ios.youtubemusic" to "com.google.android.apps.youtube.music",
        "com.google.gmail" to "com.google.android.gm",
        "com.google.maps" to "com.google.android.apps.maps",
        "com.google.chrome.ios" to "com.android.chrome",
        "com.google.drive" to "com.google.android.apps.docs",
        "com.google.photos" to "com.google.android.apps.photos",
        "com.google.googlemobile" to "com.google.android.googlequicksearchbox",
        "com.google.authenticator" to "com.google.android.apps.authenticator2",
        "com.google.calendar" to "com.google.android.calendar",
        "com.google.gemini" to "com.google.android.apps.bard",
        "com.spotify.client" to "com.spotify.music",
        "com.netflix.netflix" to "com.netflix.mediaclient",
        "com.amazon.aiv.aivapp" to "com.amazon.avod.thirdpartyclient",
        "com.disney.disneyplus" to "com.disney.disneyplus",
        "com.dazn.theapp" to "com.dazn",
        "com.amazon.amazon" to "com.amazon.mShop.android.shopping",
        "com.amazon.amazonit" to "com.amazon.mShop.android.shopping",
        "com.paypal.ppclient" to "com.paypal.android.p2pmobile",
        "com.yourcompany.ppclient" to "com.paypal.android.p2pmobile",
        "com.revolut.revolut" to "com.revolut.revolut",
        "com.satispay.satispay" to "com.satispay.customer",
        "com.satispay.consumer" to "com.satispay.customer",
        "com.satispay.customer.p2p" to "com.satispay.customer",
        "com.intesasanpaolo.ibiphone" to "com.latuabancaperandroid",
        "com.internet.unicredit.iphoneapp" to "com.unicredit",
        "it.poste.spim" to "com.posteitaliane.spim",
        "com.intesasanpaolo.isybank.mobile" to "com.intesasanpaolo.isybank.mobile",
        "com.fineco.fineco" to "com.fineco.it",
        "com.bbva.italy" to "com.bbva.italy",
        "it.bper.mobilebanking" to "it.gruppobper.ams.android.bper",
        "it.bancamediolanum.imedfullclient" to "com.mediolanum.android.fullbanca",
        "it.caitalia.apphub" to "it.caitalia.apphub",
        "com.hype.it" to "it.hype.app",
        "it.cartasi.mobile.iphone" to "it.icbpi.mobile",
        "it.bancomat.pay.user" to "it.bancomat.pay.user",
        "com.microsoft.office.outlook" to "com.microsoft.office.outlook",
        "com.microsoft.office.word" to "com.microsoft.office.word",
        "com.microsoft.skype.teams" to "com.microsoft.teams",
        "us.zoom.videomeetings" to "us.zoom.videomeetings",
        "com.atebits.tweetie2" to "com.twitter.android",
        "com.burbn.barcelona" to "com.instagram.barcelona",
        "com.linkedin.linkedin" to "com.linkedin.android",
        "com.toyopagroup.picaboo" to "com.snapchat.android",
        "pinterest" to "com.pinterest",
        "com.reddit.reddit" to "com.reddit.frontpage",
        "com.hammerandchisel.discord" to "com.discord",
        "tv.twitch" to "tv.twitch.android.app",
        "com.waze.iphone" to "com.waze",
        "com.ubercab.uberclient" to "com.ubercab",
        "it.subito.app" to "it.subito",
        "it.subito.iphone" to "it.subito",
        "com.subito.subito" to "it.subito",
        "fr.vinted" to "fr.vinted",
        "lt.manodrabuziai.fr" to "fr.vinted",
        "com.airbnb.app" to "com.airbnb.android",
        "com.openai.chat" to "com.openai.chatgpt",
        "ai.perplexity.app" to "com.perplexity.app.android",
        "com.shazam.shazam" to "com.shazam.android",
        "com.canva.canvaeditor" to "com.canva.editor",
        "com.ebay.iphone" to "com.ebay.mobile",
        "it.pagopa.app.io" to "it.pagopa.app.io",
        "it.ipzs.cieid" to "it.ipzs.cieid",
        "posteitaliane.posteapp.appposteid" to "posteitaliane.posteapp.appposteid",
        "it.poste.postebuy2" to "posteitaliane.posteapp.appposteid",
        "it.aruba.mobilepec" to "it.aruba.pec.mobile",
        "com.adobe.scan.ios" to "com.adobe.scan.android",
        "com.intsig.camscanner" to "com.intsig.camscanner",
        "com.promptu.prontotreno" to "com.lynxspa.prontotreno",
        "com.accenture.ntvapp" to "it.italotreno",
        "it.telepass" to "it.telepass.prod.TelepassPyng",
        "net.pluservice.mycicero" to "net.pluservice.myCicero",
        "net.easypark.app" to "net.easypark.android",
        "com.ryanair.cheapflights" to "com.ryanair.cheapflights",
        "com.booking.bookingapp" to "com.booking",
        "com.glovo.glovo" to "com.glovo",
        "com.deliveroo.orderapp" to "com.deliveroo.orderapp",
        "com.justeat.justeat" to "com.justeat.app.it",
        "com.einnovation.temu" to "com.einnovation.temu",
        "zzkko.com.zzkko" to "com.zzkko",
        "com.brave.ios.browser" to "com.brave.browser",
        "com.microsoft.msedge" to "com.microsoft.emmx",
        "ch.protonmail.protonmail" to "ch.protonmail.android",
        "ch.protonvpn.vpn" to "ch.protonvpn.android",
        "ch.protonmail.vpn" to "ch.protonvpn.android",
        "com.nordvpn.nordvpnapp" to "com.nordvpn.android",
        "com.nordvpn.nordvpn" to "com.nordvpn.android",
        "com.ookla.speedtest" to "org.zwanoo.android.speedtest",
        "com.teamviewer.rc" to "com.teamviewer.teamviewer.market.mobile",
        "com.lemon.lvoverseas" to "com.lemon.lvoverseas",
        "com.camerasideas.instashot" to "com.camerasideas.instashot",
        "com.niksoftware.snapseedforipad" to "com.niksoftware.snapseed",
        "com.adobe.lrmobilephone" to "com.adobe.lrmobile",
        "com.picsart.studio" to "com.picsart.studio",
        "co.visualsupply.cam" to "com.vsco.cam",
        "com.bigwinepot.nwdn.international" to "com.bigwinepot.nwdn.international",
        "com.dr1ven.eraser" to "com.photoroom.app",
        "com.frontrow.vlog" to "com.frontrow.vlog",
        "com.strava.stravaride" to "com.strava",
        "com.garmin.connect.mobile" to "com.garmin.android.apps.connectmobile",
        "com.gopro.gopro" to "com.gopro.smarty",
        "com.tplink.tapo" to "com.tplink.iot",
        "com.hikvision.ezviz" to "com.ezviz",
        "cloud.shelly.app" to "cloud.shelly.smartcontrol",
        "it.telecomitalia.119selfservice" to "it.telecomitalia.centodiciannove",
        "com.vodafone.my190" to "com.myvodafone.android",
        "it.wind.mywind" to "it.wind.myWind",
        "com.enel.energia" to "it.enel",
        "com.eni.eniautoletturagas" to "com.eni.enigaseluce",
        "it.rainet.ipad.raitv" to "it.rainet",
        "it.mediaset.video.iphone" to "it.fabbricadigitale.android.videomediaset",
        "it.sky.skygoitalia" to "it.sky.anywhere",
        "com.nowtv.it" to "com.nowtv.it",
        "org.whispersystems.signal" to "org.thoughtcrime.securesms",
        "com.viber" to "com.viber.voip",
        "com.duolingo.duolingomobile" to "com.duolingo",
        "com.getdropbox.dropbox" to "com.dropbox.android",
        "com.microsoft.skydrive" to "com.microsoft.skydrive",
        "com.microsoft.copilot" to "com.microsoft.copilot",
        "com.anthropic.claude" to "com.anthropic.claude"
    )

    private val normalizedNameToAndroidPackage: Map<String, String> = mapOf(
        "whatsapp" to "com.whatsapp",
        "whatsappmessenger" to "com.whatsapp",
        "wabusiness" to "com.whatsapp.w4b",
        "whatsappbusiness" to "com.whatsapp.w4b",
        "instagram" to "com.instagram.android",
        "telegram" to "org.telegram.messenger",
        "telegrammessenger" to "org.telegram.messenger",
        "facebook" to "com.facebook.katana",
        "messenger" to "com.facebook.orca",
        "tiktok" to "com.zhiliaoapp.musically",
        "youtube" to "com.google.android.youtube",
        "ytmusic" to "com.google.android.apps.youtube.music",
        "youtubemusic" to "com.google.android.apps.youtube.music",
        "gmail" to "com.google.android.gm",
        "googlemaps" to "com.google.android.apps.maps",
        "maps" to "com.google.android.apps.maps",
        "chrome" to "com.android.chrome",
        "googlechrome" to "com.android.chrome",
        "googledrive" to "com.google.android.apps.docs",
        "drive" to "com.google.android.apps.docs",
        "googlefoto" to "com.google.android.apps.photos",
        "googlephotos" to "com.google.android.apps.photos",
        "google" to "com.google.android.googlequicksearchbox",
        "authenticator" to "com.google.android.apps.authenticator2",
        "googleauthenticator" to "com.google.android.apps.authenticator2",
        "googlecalendar" to "com.google.android.calendar",
        "gemini" to "com.google.android.apps.bard",
        "googlegemini" to "com.google.android.apps.bard",
        "spotify" to "com.spotify.music",
        "netflix" to "com.netflix.mediaclient",
        "primevideo" to "com.amazon.avod.thirdpartyclient",
        "amazonprimevideo" to "com.amazon.avod.thirdpartyclient",
        "disney" to "com.disney.disneyplus",
        "disneyplus" to "com.disney.disneyplus",
        "dazn" to "com.dazn",
        "amazon" to "com.amazon.mShop.android.shopping",
        "amazonshopping" to "com.amazon.mShop.android.shopping",
        "paypal" to "com.paypal.android.p2pmobile",
        "revolut" to "com.revolut.revolut",
        "satispay" to "com.satispay.customer",
        "outlook" to "com.microsoft.office.outlook",
        "microsoftoutlook" to "com.microsoft.office.outlook",
        "teams" to "com.microsoft.teams",
        "microsoftteams" to "com.microsoft.teams",
        "zoom" to "us.zoom.videomeetings",
        "x" to "com.twitter.android",
        "twitter" to "com.twitter.android",
        "threads" to "com.instagram.barcelona",
        "linkedin" to "com.linkedin.android",
        "snapchat" to "com.snapchat.android",
        "pinterest" to "com.pinterest",
        "reddit" to "com.reddit.frontpage",
        "discord" to "com.discord",
        "twitch" to "tv.twitch.android.app",
        "waze" to "com.waze",
        "uber" to "com.ubercab",
        "subito" to "it.subito",
        "subitoit" to "it.subito",
        "vinted" to "fr.vinted",
        "airbnb" to "com.airbnb.android",
        "chatgpt" to "com.openai.chatgpt",
        "claude" to "com.anthropic.claude",
        "copilot" to "com.microsoft.copilot",
        "microsoftcopilot" to "com.microsoft.copilot",
        "shazam" to "com.shazam.android",
        "canva" to "com.canva.editor",
        "ebay" to "com.ebay.mobile",
        "io" to "it.pagopa.app.io",
        "appio" to "it.pagopa.app.io",
        "cieid" to "it.ipzs.cieid",
        "posteid" to "posteitaliane.posteapp.appposteid",
        "temu" to "com.einnovation.temu",
        "brave" to "com.brave.browser",
        "edge" to "com.microsoft.emmx",
        "microsoftedge" to "com.microsoft.emmx",
        "protonmail" to "ch.protonmail.android",
        "protonvpn" to "ch.protonvpn.android",
        "nordvpn" to "com.nordvpn.android",
        "speedtest" to "org.zwanoo.android.speedtest",
        "teamviewer" to "com.teamviewer.teamviewer.market.mobile",
        "capcut" to "com.lemon.lvoverseas",
        "booking" to "com.booking",
        "bookingcom" to "com.booking",
        "duolingo" to "com.duolingo",
        "dropbox" to "com.dropbox.android",
        "onedrive" to "com.microsoft.skydrive",
        "microsoftonedrive" to "com.microsoft.skydrive",
        "intesasanpaolomobile" to "com.latuabancaperandroid",
        "intesasanpaolo" to "com.latuabancaperandroid",
        "unicreditmobilebanking" to "com.unicredit",
        "unicredit" to "com.unicredit",
        "mobilebankingunicredit" to "com.unicredit",
        "posteitaliane" to "com.posteitaliane.spim",
        "bancoposta" to "com.posteitaliane.spim",
        "postepay" to "com.posteitaliane.spim",
        "isybank" to "com.intesasanpaolo.isybank.mobile",
        "fineco" to "com.fineco.it",
        "bbvaitalia" to "com.bbva.italy",
        "bperbanca" to "it.gruppobper.ams.android.bper",
        "bancamediolanum" to "com.mediolanum.android.fullbanca",
        "creditagricoleitalia" to "it.caitalia.apphub",
        "hype" to "it.hype.app",
        "nexipay" to "it.icbpi.mobile",
        "bancomat" to "it.bancomat.pay.user",
        "arubapec" to "it.aruba.pec.mobile",
        "adobescan" to "com.adobe.scan.android",
        "camscanner" to "com.intsig.camscanner",
        "microsoftword" to "com.microsoft.office.word",
        "trenitalia" to "com.lynxspa.prontotreno",
        "italotreno" to "it.italotreno",
        "telepass" to "it.telepass.prod.TelepassPyng",
        "mooneygo" to "net.pluservice.myCicero",
        "easypark" to "net.easypark.android",
        "ryanair" to "com.ryanair.cheapflights",
        "glovo" to "com.glovo",
        "deliveroo" to "com.deliveroo.orderapp",
        "justeat" to "com.justeat.app.it",
        "shein" to "com.zzkko",
        "inshot" to "com.camerasideas.instashot",
        "snapseed" to "com.niksoftware.snapseed",
        "lightroom" to "com.adobe.lrmobile",
        "picsart" to "com.picsart.studio",
        "vsco" to "com.vsco.cam",
        "remini" to "com.bigwinepot.nwdn.international",
        "photoroom" to "com.photoroom.app",
        "vnvideoeditor" to "com.frontrow.vlog",
        "strava" to "com.strava",
        "garminconnect" to "com.garmin.android.apps.connectmobile",
        "goproquik" to "com.gopro.smarty",
        "tplinktapo" to "com.tplink.iot",
        "ezviz" to "com.ezviz",
        "shellysmartcontrol" to "cloud.shelly.smartcontrol",
        "mytim" to "it.telecomitalia.centodiciannove",
        "myvodafone" to "com.myvodafone.android",
        "windtre" to "it.wind.myWind",
        "enelenergia" to "it.enel",
        "eniplenitude" to "com.eni.enigaseluce",
        "raiplay" to "it.rainet",
        "mediasetinfinity" to "it.fabbricadigitale.android.videomediaset",
        "skygo" to "it.sky.anywhere",
        "now" to "com.nowtv.it",
        "perplexity" to "com.perplexity.app.android",
        "signal" to "org.thoughtcrime.securesms",
        "viber" to "com.viber.voip"
    )

    internal fun normalizeAppLabel(label: String): String =
        java.text.Normalizer.normalize(label, java.text.Normalizer.Form.NFD)
            .replace(Regex("\\p{InCombiningDiacriticalMarks}+"), "")
            .lowercase()
            .replace(Regex("[^\\p{L}\\p{N}]"), "")

    internal fun isMirrorableAndroidPackage(packageName: String, isPureSystem: Boolean): Boolean {
        val pkgLower = packageName.trim().lowercase()
        if (pkgLower.isEmpty()) return false
        if (pkgLower in alwaysIncludeCrossPlatformGoogleApps) return true
        if (isPureSystem) return false
        if (pkgLower in excludedAndroidOsPackages) return false
        if (excludedSystemPrefixes.any { pkgLower.startsWith(it) }) return false
        if (pkgLower.startsWith("com.android.") && pkgLower != "com.android.chrome") return false
        return true
    }

    fun resolvePlayStoreTarget(
        record: InstalledAppRecord,
        peerPlatform: DevicePlatform? = null
    ): PlayStoreTarget {
        val rawPkg = record.packageName.trim()
        val pkgLower = rawPkg.lowercase()
        val normLabel = normalizeAppLabel(record.appName)
        val mapped = iosBundleToAndroidPackage[pkgLower] ?: normalizedNameToAndroidPackage[normLabel]
        if (mapped != null) {
            return PlayStoreTarget.ExactPackage(mapped)
        }
        val query = record.appName.trim().ifEmpty { rawPkg }
        val isFromIosOrScan = peerPlatform == DevicePlatform.IOS ||
            pkgLower.startsWith("scan.") ||
            record.appStoreId != null ||
            rawPkg.isEmpty()
        return if (isFromIosOrScan) {
            PlayStoreTarget.SearchByName(query)
        } else {
            PlayStoreTarget.ExactPackage(rawPkg)
        }
    }

    fun readInstalledAppsSnapshot(context: Context): InstalledAppsSnapshot {
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
            val pkgs = HashSet<String>()
            val labels = HashSet<String>()
            for (info in resolved) {
                val ai = info.activityInfo?.applicationInfo ?: continue
                val pkg = ai.packageName?.trim()?.lowercase()
                if (!pkg.isNullOrEmpty()) pkgs.add(pkg)
                val label = ai.loadLabel(pm)?.toString()?.let(::normalizeAppLabel)
                if (!label.isNullOrEmpty()) labels.add(label)
            }
            InstalledAppsSnapshot(packageNames = pkgs, normalizedLabels = labels)
        } catch (_: Throwable) {
            InstalledAppsSnapshot(emptySet(), emptySet())
        }
    }

    fun isAppInstalled(
        snapshot: InstalledAppsSnapshot,
        record: InstalledAppRecord,
        peerPlatform: DevicePlatform? = null
    ): Boolean {
        val target = resolvePlayStoreTarget(record, peerPlatform)
        if (target is PlayStoreTarget.ExactPackage &&
            snapshot.packageNames.contains(target.packageName.lowercase())
        ) {
            return true
        }
        val normName = normalizeAppLabel(record.appName)
        return normName.isNotEmpty() && snapshot.normalizedLabels.contains(normName)
    }

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
                if (!isMirrorableAndroidPackage(pkg, isPureSystem)) continue
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

    fun openAppOnPlayStore(
        context: Context,
        record: InstalledAppRecord,
        peerPlatform: DevicePlatform? = null
    ) {
        val (marketUri, webUri) = when (val target = resolvePlayStoreTarget(record, peerPlatform)) {
            is PlayStoreTarget.ExactPackage -> {
                val enc = Uri.encode(target.packageName)
                Uri.parse("market://details?id=$enc") to
                    Uri.parse("https://play.google.com/store/apps/details?id=$enc")
            }
            is PlayStoreTarget.SearchByName -> {
                val enc = Uri.encode(target.query)
                Uri.parse("market://search?q=$enc&c=apps") to
                    Uri.parse("https://play.google.com/store/search?q=$enc&c=apps")
            }
        }
        val marketIntent = Intent(Intent.ACTION_VIEW, marketUri).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        val webIntent = Intent(Intent.ACTION_VIEW, webUri).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
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
