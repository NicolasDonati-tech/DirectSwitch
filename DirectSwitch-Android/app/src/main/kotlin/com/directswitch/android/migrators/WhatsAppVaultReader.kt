//
//  WhatsAppVaultReader.kt
//  DirectSwitch-Android
//
//  Created by Nicolas Donati.
//  Copyright © 2026 Nicolas Donati. Tutti i diritti riservati.
//

package com.directswitch.android.migrators

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Environment
import android.provider.OpenableColumns
import android.webkit.MimeTypeMap
import androidx.core.content.FileProvider
import com.directswitch.android.DirectSwitchLog
import com.directswitch.android.protocol.ManifestItem
import com.directswitch.android.protocol.TransferCategory
import java.io.File
import java.io.InputStream
import java.util.Locale
import java.util.zip.ZipInputStream

enum class WhatsAppAttachmentKind {
    NONE,
    AUDIO_VOICE,
    IMAGE,
    VIDEO,
    DOCUMENT
}

data class WhatsAppParsedMessage(
    val index: Int,
    val timestampLabel: String,
    val sender: String,
    val body: String,
    val attachmentFileName: String? = null,
    val attachmentFile: File? = null,
    val attachmentKind: WhatsAppAttachmentKind = WhatsAppAttachmentKind.NONE,
    val isSystemNotice: Boolean = false
)

data class WhatsAppImportedChatSummary(
    val chatId: String,
    val title: String,
    val chatDir: File,
    val messagesCount: Int,
    val mediaCount: Int,
    val voiceNotesCount: Int,
    val lastPreview: String,
    val updatedEpochMillis: Long
)

/**
 * Gestore e Parser Nativo per le Chat WhatsApp provenienti da iPhone (`_chat.txt` + allegati `.opus`/foto/video)
 * e da Android (`Chat WhatsApp con *.txt`), progettato per funzionare su telefoni Android GIÀ CONFIGURATI
 * senza usare `Android Switch` e senza formattare il telefono.
 */
object WhatsAppVaultReader {

    private const val EXTRACTED_ROOT_DIR = "whatsapp_vault_extracted"

    // Formato iOS: [16/11/26, 15:30:12] Mario Rossi: Messaggio
    private val iosHeaderRegex = Regex(
        """^\[(\d{1,4}[/.-]\d{1,2}[/.-]\d{1,4},?\s+\d{1,2}:\d{2}(?::\d{2})?(?:\s*[APMapm]{2})?)\]\s*(.*)$"""
    )

    // Formato Android: 16/11/26, 15:30 - Mario Rossi: Messaggio
    private val androidHeaderRegex = Regex(
        """^(\d{1,4}[/.-]\d{1,2}[/.-]\d{1,4},?\s+\d{1,2}:\d{2}(?::\d{2})?(?:\s*[APMapm]{2})?)\s+-\s+(.*)$"""
    )

    // Tag allegato iOS: <allegato: 00000005-AUDIO-2026-11-16.opus> oppure <attached: ...>
    private val iosAttachmentRegex = Regex(
        """<(?:allegato|attached|adjunto|pièce jointe|anhang)\s*:\s*([^>]+)>""",
        RegexOption.IGNORE_CASE
    )

    // Tag allegato Android: IMG-20261116-WA0001.jpg (file allegato) / (file attached)
    private val androidAttachmentRegex = Regex(
        """([^\r\n/\\]+\.[a-zA-Z0-9]{2,5})\s*\((?:file allegato|file attached|archivo adjunto|fichier joint|datei angehängt)\)""",
        RegexOption.IGNORE_CASE
    )

    private fun extractedRoot(context: Context): File =
        File(context.filesDir, EXTRACTED_ROOT_DIR).apply { mkdirs() }

    /**
     * Indicizza ed estrae automaticamente un archivio `.zip` o `.txt` WhatsApp appena ricevuto via Wi-Fi
     * o importato tramite "Condividi con DirectSwitch" / selettore file.
     */
    fun ingestReceivedArchive(context: Context, rawFileName: String, sourceFile: File): Boolean {
        if (!sourceFile.exists() || sourceFile.length() <= 0L) return false
        val lower = rawFileName.lowercase(Locale.ROOT)
        if (!lower.endsWith(".zip") && !lower.endsWith(".txt")) return false
        return try {
            sourceFile.inputStream().use { stream ->
                ingestStream(context, rawFileName, stream)
            }
        } catch (t: Throwable) {
            DirectSwitchLog.warn("Indicizzazione archivio WhatsApp fallita", t)
            false
        }
    }

    fun importFromContentUris(context: Context, uris: List<Uri>): Int {
        var imported = 0
        for (uri in uris) {
            try {
                val displayName = queryDisplayName(context, uri) ?: "Chat_WhatsApp_${System.currentTimeMillis()}.zip"
                val ok = context.contentResolver.openInputStream(uri)?.use { input ->
                    ingestStream(context, displayName, input)
                } ?: false
                if (ok) imported++
            } catch (t: Throwable) {
                DirectSwitchLog.warn("Importazione URI WhatsApp fallita", t)
            }
        }
        return imported
    }

    private fun ingestStream(context: Context, rawFileName: String, input: InputStream): Boolean {
        val cleanTitle = cleanChatTitleFromFileName(rawFileName)
        val safeFolderId = cleanTitle
            .replace(Regex("[^a-zA-Z0-9 _-]"), "_")
            .trim()
            .ifBlank { "Chat_${System.currentTimeMillis()}" }
        val targetDir = File(extractedRoot(context), safeFolderId)
        targetDir.mkdirs()
        File(targetDir, ".title").writeText(cleanTitle, Charsets.UTF_8)

        val lower = rawFileName.lowercase(Locale.ROOT)
        return if (lower.endsWith(".zip")) {
            extractZipSafely(input, targetDir)
        } else {
            val destTxt = File(targetDir, "_chat.txt")
            destTxt.outputStream().use { out -> input.copyTo(out, 128 * 1024) }
            destTxt.length() > 0L
        }
    }

    private fun extractZipSafely(input: InputStream, targetDir: File): Boolean {
        val canonicalRoot = targetDir.canonicalPath + File.separator
        var extractedAny = false
        ZipInputStream(input.buffered()).use { zis ->
            var entry = zis.nextEntry
            while (entry != null) {
                if (!entry.isDirectory) {
                    val leafName = File(entry.name).name
                        .replace(Regex("[\\\\/:*?\"<>|]"), "_")
                        .trim()
                    if (leafName.isNotEmpty() && !leafName.startsWith("._") && leafName != ".DS_Store") {
                        val outFile = File(targetDir, leafName)
                        if (outFile.canonicalPath.startsWith(canonicalRoot)) {
                            outFile.outputStream().use { out ->
                                zis.copyTo(out, 128 * 1024)
                            }
                            extractedAny = true
                        }
                    }
                }
                zis.closeEntry()
                entry = zis.nextEntry
            }
        }
        return extractedAny
    }

    /**
     * Scansiona anche eventuali `.zip` WhatsApp già presenti in `shared_vault` o `Download/WhatsApp_Vault`
     * e restituisce l'elenco completo delle conversazioni pronte alla lettura.
     */
    fun listImportedConversations(context: Context): List<WhatsAppImportedChatSummary> {
        syncFromLocalVaultFolders(context)
        val root = extractedRoot(context)
        val chatDirs = root.listFiles()?.filter { it.isDirectory }.orEmpty()
        val summaries = mutableListOf<WhatsAppImportedChatSummary>()

        for (dir in chatDirs) {
            val txtFile = findChatTranscriptFile(dir) ?: continue
            val parsed = parseTranscriptText(txtFile.readText(Charsets.UTF_8), dir)
            if (parsed.isEmpty()) continue
            val titleFile = File(dir, ".title")
            val title = if (titleFile.exists()) {
                titleFile.readText(Charsets.UTF_8).trim().ifBlank { cleanChatTitleFromFileName(dir.name) }
            } else {
                cleanChatTitleFromFileName(dir.name)
            }
            val mediaCount = parsed.count { it.attachmentKind != WhatsAppAttachmentKind.NONE && it.attachmentFile != null }
            val voiceCount = parsed.count { it.attachmentKind == WhatsAppAttachmentKind.AUDIO_VOICE && it.attachmentFile != null }
            val lastMsg = parsed.lastOrNull()
            val preview = when {
                lastMsg == null -> ""
                lastMsg.body.isNotBlank() -> lastMsg.body.replace('\n', ' ').take(80)
                lastMsg.attachmentFileName != null -> "📎 ${lastMsg.attachmentFileName}"
                else -> ""
            }
            summaries.add(
                WhatsAppImportedChatSummary(
                    chatId = dir.name,
                    title = title,
                    chatDir = dir,
                    messagesCount = parsed.size,
                    mediaCount = mediaCount,
                    voiceNotesCount = voiceCount,
                    lastPreview = preview,
                    updatedEpochMillis = txtFile.lastModified()
                )
            )
        }
        return summaries.sortedByDescending { it.updatedEpochMillis }
    }

    fun loadConversationMessages(chatDir: File): List<WhatsAppParsedMessage> {
        val txtFile = findChatTranscriptFile(chatDir) ?: return emptyList()
        return try {
            parseTranscriptText(txtFile.readText(Charsets.UTF_8), chatDir)
        } catch (t: Throwable) {
            DirectSwitchLog.warn("Lettura conversazione WhatsApp fallita", t)
            emptyList()
        }
    }

    /**
     * Parser puro (testabile anche da JUnit senza Context Android) per trascrizioni WhatsApp iOS e Android.
     */
    fun parseTranscriptText(rawText: String, attachmentsDir: File? = null): List<WhatsAppParsedMessage> {
        if (rawText.isBlank()) return emptyList()
        val messages = mutableListOf<WhatsAppParsedMessage>()

        var currentTimestamp = ""
        var currentSender = ""
        val currentBody = StringBuilder()
        var hasOpenMessage = false

        fun flushCurrent() {
            if (!hasOpenMessage) return
            val fullBodyRaw = currentBody.toString().trim()
            val (cleanText, detectedFileName) = extractAttachmentNameAndCleanBody(fullBodyRaw, attachmentsDir)
            val resolvedFile = if (detectedFileName != null && attachmentsDir != null) {
                resolveAttachmentFile(attachmentsDir, detectedFileName)
            } else {
                null
            }
            val kind = classifyAttachmentKind(detectedFileName)
            messages.add(
                WhatsAppParsedMessage(
                    index = messages.size,
                    timestampLabel = currentTimestamp,
                    sender = currentSender,
                    body = cleanText,
                    attachmentFileName = detectedFileName,
                    attachmentFile = resolvedFile,
                    attachmentKind = kind,
                    isSystemNotice = currentSender.isBlank()
                )
            )
        }

        for (rawLine in rawText.lineSequence()) {
            // Rimuove marcatori invisibili LRM/RLM/BOM inseriti da WhatsApp su iPhone prima di `[` o `<allegato:`
            val cleanLine = rawLine.trimStart('\uFEFF', '\u200E', '\u200F', '\u202A', '\u202B', '\u202C')
            val iosMatch = iosHeaderRegex.matchEntire(cleanLine)
            val androidMatch = if (iosMatch == null) androidHeaderRegex.matchEntire(cleanLine) else null
            val activeMatch = iosMatch ?: androidMatch

            if (activeMatch != null) {
                flushCurrent()
                currentTimestamp = activeMatch.groupValues[1].trim()
                val remainder = activeMatch.groupValues[2].trimStart('\u200E', '\u200F')
                val colonIdx = remainder.indexOf(": ")
                if (colonIdx > 0 && colonIdx <= 64) {
                    currentSender = remainder.substring(0, colonIdx).trim()
                    currentBody.clear()
                    currentBody.append(remainder.substring(colonIdx + 2).trimStart('\u200E', '\u200F'))
                } else {
                    currentSender = ""
                    currentBody.clear()
                    currentBody.append(remainder)
                }
                hasOpenMessage = true
            } else if (hasOpenMessage) {
                currentBody.append('\n').append(rawLine.trim('\u200E', '\u200F'))
            }
        }
        flushCurrent()
        return messages
    }

    private fun extractAttachmentNameAndCleanBody(
        rawBody: String,
        attachmentsDir: File?
    ): Pair<String, String?> {
        val normalized = rawBody.replace("\u200E", "").replace("\u200F", "").trim()

        iosAttachmentRegex.find(normalized)?.let { m ->
            val fileName = m.groupValues[1].trim()
            val cleaned = normalized.removeRange(m.range).trim()
            return cleaned to fileName
        }

        androidAttachmentRegex.find(normalized)?.let { m ->
            val fileName = m.groupValues[1].trim()
            val cleaned = normalized.removeRange(m.range).trim()
            return cleaned to fileName
        }

        // Fallback: se una riga coincide esattamente col nome di un file presente nella cartella estratta
        if (attachmentsDir != null && !normalized.contains('\n') && normalized.contains('.')) {
            val candidate = File(attachmentsDir, normalized)
            if (candidate.exists() && candidate.isFile) {
                return "" to candidate.name
            }
        }

        return normalized to null
    }

    private fun resolveAttachmentFile(dir: File, fileName: String): File? {
        val exact = File(dir, fileName)
        if (exact.exists() && exact.isFile) return exact
        return dir.listFiles()?.firstOrNull { it.isFile && it.name.equals(fileName, ignoreCase = true) }
    }

    private fun classifyAttachmentKind(fileName: String?): WhatsAppAttachmentKind {
        if (fileName.isNullOrBlank()) return WhatsAppAttachmentKind.NONE
        return when (fileName.substringAfterLast('.', "").lowercase(Locale.ROOT)) {
            "opus", "ogg", "m4a", "mp3", "aac", "wav", "amr" -> WhatsAppAttachmentKind.AUDIO_VOICE
            "jpg", "jpeg", "png", "webp", "heic", "gif" -> WhatsAppAttachmentKind.IMAGE
            "mp4", "mov", "3gp", "mkv", "webm" -> WhatsAppAttachmentKind.VIDEO
            else -> WhatsAppAttachmentKind.DOCUMENT
        }
    }

    /**
     * Esporta con 1 tocco tutte le Foto e i Video contenuti nella chat WhatsApp direttamente nella Galleria Android.
     */
    fun saveAllChatMediaToGallery(context: Context, chatDir: File): Int {
        val files = chatDir.listFiles()?.filter { it.isFile }.orEmpty()
        var savedCount = 0
        for (file in files) {
            val kind = classifyAttachmentKind(file.name)
            if (kind != WhatsAppAttachmentKind.IMAGE && kind != WhatsAppAttachmentKind.VIDEO) continue
            val cat = if (kind == WhatsAppAttachmentKind.VIDEO) TransferCategory.VIDEOS else TransferCategory.PHOTOS
            val ext = file.extension.lowercase(Locale.ROOT)
            val mime = MimeTypeMap.getSingleton().getMimeTypeFromExtension(ext)
                ?: if (cat == TransferCategory.VIDEOS) "video/mp4" else "image/jpeg"
            val item = ManifestItem(
                id = "wa_gal_${file.name.hashCode()}",
                category = cat,
                fileName = file.name,
                relativeAlbumOrFolder = "WhatsApp_DirectSwitch",
                sizeBytes = file.length(),
                capturedEpochMillis = file.lastModified(),
                dedupKey = "wa_${file.name.lowercase()}_${file.length()}",
                mimeType = mime
            )
            val ok = runCatching {
                file.inputStream().use { stream ->
                    MediaExifScannerAndImporter.importMediaStream(context, item, stream)
                }
            }.getOrDefault(false)
            if (ok) savedCount++
        }
        return savedCount
    }

    fun openAttachmentExternally(context: Context, file: File): Boolean {
        if (!file.exists()) return false
        return try {
            val uri = FileProvider.getUriForFile(context, "${context.packageName}.fileprovider", file)
            val ext = file.extension.lowercase(Locale.ROOT)
            val mime = MimeTypeMap.getSingleton().getMimeTypeFromExtension(ext) ?: "*/*"
            val viewIntent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, mime)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            context.startActivity(viewIntent)
            true
        } catch (t: Throwable) {
            DirectSwitchLog.warn("Apertura allegato WhatsApp fallita", t)
            false
        }
    }

    fun deleteImportedChat(chatSummary: WhatsAppImportedChatSummary) {
        runCatching { chatSummary.chatDir.deleteRecursively() }
    }

    private fun syncFromLocalVaultFolders(context: Context) {
        val candidateDirs = mutableListOf(File(context.filesDir, "shared_vault"))
        runCatching {
            @Suppress("DEPRECATION")
            val extRoot = Environment.getExternalStorageDirectory()
            if (extRoot != null) {
                candidateDirs.add(File(extRoot, "WhatsApp_Vault"))
                candidateDirs.add(File(File(extRoot, Environment.DIRECTORY_DOWNLOADS), "WhatsApp_Vault"))
            }
        }
        val existingIds = extractedRoot(context).listFiles()?.map { it.name.lowercase(Locale.ROOT) }?.toHashSet().orEmpty()
        for (dir in candidateDirs) {
            if (!dir.exists() || !dir.isDirectory || !dir.canRead()) continue
            dir.listFiles()?.forEach { f ->
                if (!f.isFile || f.length() <= 0L) return@forEach
                val lower = f.name.lowercase(Locale.ROOT)
                val looksLikeWa = (lower.endsWith(".zip") || lower.endsWith(".txt")) &&
                    (lower.contains("whatsapp") || lower.contains("chat") || dir.name.equals("WhatsApp_Vault", ignoreCase = true))
                if (!looksLikeWa) return@forEach
                val cleanTitle = cleanChatTitleFromFileName(f.name)
                val safeId = cleanTitle.replace(Regex("[^a-zA-Z0-9 _-]"), "_").trim().lowercase(Locale.ROOT)
                if (safeId.isNotEmpty() && safeId !in existingIds) {
                    ingestReceivedArchive(context, f.name, f)
                }
            }
        }
    }

    private fun findChatTranscriptFile(chatDir: File): File? {
        val exact = File(chatDir, "_chat.txt")
        if (exact.exists() && exact.length() > 0L) return exact
        return chatDir.listFiles()
            ?.filter { it.isFile && it.extension.equals("txt", ignoreCase = true) && it.length() > 0L }
            ?.maxByOrNull { it.length() }
    }

    fun cleanChatTitleFromFileName(rawName: String): String {
        val withoutExt = rawName
            .removeSuffix(".zip")
            .removeSuffix(".ZIP")
            .removeSuffix(".txt")
            .removeSuffix(".TXT")
        return withoutExt
            .replace(Regex("^(Chat WhatsApp con |WhatsApp Chat with |WhatsApp-Chat mit |Chat de WhatsApp con )", RegexOption.IGNORE_CASE), "")
            .trim()
            .ifBlank { "Chat WhatsApp" }
    }

    private fun queryDisplayName(context: Context, uri: Uri): String? {
        return runCatching {
            context.contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { c ->
                if (c.moveToFirst()) c.getString(0) else null
            }
        }.getOrNull() ?: uri.lastPathSegment?.substringAfterLast('/')
    }
}
