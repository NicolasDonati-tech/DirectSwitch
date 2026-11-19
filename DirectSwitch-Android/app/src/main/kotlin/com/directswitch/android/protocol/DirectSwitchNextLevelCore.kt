//
//  DirectSwitchNextLevelCore.kt
//  DirectSwitch-Android
//
//  Created by Nicolas Donati.
//  Copyright © 2026 Nicolas Donati. Tutti i diritti riservati.
//

package com.directswitch.android.protocol

import android.content.Context
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import java.io.File
import java.io.RandomAccessFile
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/** Tipo di canale di trasporto locale attivo (Cavo USB-C > Wi-Fi Diretto P2P > Wi-Fi Locale). */
@Serializable
enum class TransferConnectionMedium {
    USB_CABLE,
    PEER_TO_PEER_WIFI,
    LOCAL_WIFI;

    fun badgeLabel(): String = when (this) {
        USB_CABLE -> "Cavo USB-C diretto"
        PEER_TO_PEER_WIFI -> "Wi-Fi Diretto P2P"
        LOCAL_WIFI -> "Wi-Fi Locale"
    }
}

/** Filtri rapidi per Foto e Video e opzioni Salva-Spazio. */
@Serializable
data class MediaTransferFilterOptions(
    val photosLastYearOnly: Boolean = false,
    val selectedPhotoAlbums: List<String> = emptyList(),
    val videosLastYearOnly: Boolean = false,
    val maxVideoBytes: Long = 0L,
    val compactVideo1080pHevc: Boolean = false
) {
    val isDefault: Boolean
        get() = !photosLastYearOnly && selectedPhotoAlbums.isEmpty() && !videosLastYearOnly && maxVideoBytes == 0L && !compactVideo1080pHevc
}

/** Dettaglio di un file saltato durante la copia per il report interattivo e il pulsante "Riprova solo i mancanti". */
@Serializable
data class SkippedTransferItemRecord(
    val id: String,
    val fileName: String,
    val category: TransferCategory,
    val sizeBytes: Long,
    val reason: String
)

/** Checkpoint salvato su disco per riprendere trasferimenti grandi anche dopo chiusura app o riavvio. */
@Serializable
data class TransferCheckpointRecord(
    val sessionId: String,
    val qrPayloadJson: String,
    val receiverName: String,
    val receiverPlatform: DevicePlatform,
    val scope: ActiveTransferScope,
    val completedItemIds: List<String>,
    val uploadedBytes: Long,
    val totalItems: Int,
    val totalBytes: Long,
    val skippedItems: List<SkippedTransferItemRecord> = emptyList(),
    val filterOptions: MediaTransferFilterOptions = MediaTransferFilterOptions(),
    val savedAtEpochMillis: Long
) {
    fun completionPercent(): Int {
        if (totalBytes > 0L) {
            return TransferDisplayFormatting.percentageInt(uploadedBytes.toDouble() / totalBytes.toDouble(), false)
        }
        if (totalItems > 0) {
            return TransferDisplayFormatting.percentageInt(completedItemIds.size.toDouble() / totalItems.toDouble(), false)
        }
        return 0
    }
}

/** Persistenza atomica su disco del checkpoint di ripresa (auto-scadenza 24 ore). */
object TransferCheckpointStore {
    private const val FILE_NAME = "transfer_checkpoint_v1.json"
    private const val MAX_AGE_MS = 24L * 60L * 60L * 1000L

    fun defaultFile(context: Context): File = File(context.filesDir, FILE_NAME)

    fun save(file: File, record: TransferCheckpointRecord) {
        runCatching {
            file.parentFile?.mkdirs()
            val tmp = File(file.parentFile, "${file.name}.tmp")
            tmp.writeText(DirectSwitchJson.instance.encodeToString(record), Charsets.UTF_8)
            if (!tmp.renameTo(file)) {
                tmp.copyTo(file, overwrite = true)
                tmp.delete()
            }
        }
    }

    fun save(context: Context, record: TransferCheckpointRecord) = save(defaultFile(context), record)

    fun load(file: File, nowEpochMillis: Long = System.currentTimeMillis()): TransferCheckpointRecord? {
        if (!file.exists()) return null
        val parsed = runCatching {
            DirectSwitchJson.instance.decodeFromString<TransferCheckpointRecord>(file.readText(Charsets.UTF_8))
        }.getOrNull() ?: return null
        if (nowEpochMillis - parsed.savedAtEpochMillis > MAX_AGE_MS) {
            clear(file)
            return null
        }
        if (parsed.sessionId.isBlank() || parsed.qrPayloadJson.isBlank()) return null
        return parsed
    }

    fun load(context: Context): TransferCheckpointRecord? = load(defaultFile(context))

    fun clear(file: File) {
        runCatching { if (file.exists()) file.delete() }
    }

    fun clear(context: Context) = clear(defaultFile(context))
}

enum class SpaceReliefActionKind {
    OVERFLOW_OLDER_TO_CLOUDSAVE,
    EXCLUDE_HEAVY_VIDEOS_300MB,
    LAST_YEAR_MEDIA_ONLY,
    EXCLUDE_ALL_VIDEOS
}

data class SpaceReliefOption(
    val kind: SpaceReliefActionKind,
    val title: String,
    val subtitle: String,
    val estimatedSavingsBytes: Long,
    val estimatedFinalBytes: Long,
    val fitsAvailableSpace: Boolean
)

data class SpaceReliefOffer(
    val receiverName: String,
    val totalNeededBytes: Long,
    val availableFreeBytes: Long,
    val shortfallBytes: Long,
    val options: List<SpaceReliefOption>
)

/** Calcola proposte concrete per rientrare nello spazio libero del telefono ricevente. */
object SpaceReliefPlanner {
    private const val SAFETY_MARGIN_BYTES = 250L * 1024L * 1024L
    const val HEAVY_VIDEO_THRESHOLD_BYTES = 300L * 1024L * 1024L

    fun evaluate(
        receiverName: String,
        availableFreeBytes: Long,
        items: List<ManifestItem>,
        nowEpochMillis: Long = System.currentTimeMillis()
    ): SpaceReliefOffer? {
        val totalNeeded = items.sumOf { it.sizeBytes.coerceAtLeast(0L) }
        val usableFree = (availableFreeBytes - SAFETY_MARGIN_BYTES).coerceAtLeast(0L)
        if (totalNeeded <= usableFree || totalNeeded <= 0L) return null

        val shortfall = totalNeeded - usableFree
        val oneYearCutoff = nowEpochMillis - 365L * 86_400_000L

        val heavyVideoBytes = items
            .filter { it.category == TransferCategory.VIDEOS && it.sizeBytes > HEAVY_VIDEO_THRESHOLD_BYTES }
            .sumOf { it.sizeBytes.coerceAtLeast(0L) }
        val olderMediaBytes = items
            .filter {
                (it.category == TransferCategory.PHOTOS || it.category == TransferCategory.VIDEOS) &&
                    it.capturedEpochMillis > 0L && it.capturedEpochMillis < oneYearCutoff
            }
            .sumOf { it.sizeBytes.coerceAtLeast(0L) }
        val allVideoBytes = items
            .filter { it.category == TransferCategory.VIDEOS }
            .sumOf { it.sizeBytes.coerceAtLeast(0L) }

        val options = buildList {
            if (olderMediaBytes > 0L) {
                val finalBytes = (totalNeeded - olderMediaBytes).coerceAtLeast(0L)
                add(
                    SpaceReliefOption(
                        kind = SpaceReliefActionKind.OVERFLOW_OLDER_TO_CLOUDSAVE,
                        title = "Ultimo anno sul nuovo telefono + resto cifrato su CloudSave",
                        subtitle = "Copia ${TransferDisplayFormatting.formatBytes(finalBytes)} ora e parcheggia ${TransferDisplayFormatting.formatBytes(olderMediaBytes)} su CloudSave (zero perdite)",
                        estimatedSavingsBytes = olderMediaBytes,
                        estimatedFinalBytes = finalBytes,
                        fitsAvailableSpace = finalBytes <= usableFree
                    )
                )
            } else if (heavyVideoBytes > 0L) {
                val finalBytes = (totalNeeded - heavyVideoBytes).coerceAtLeast(0L)
                add(
                    SpaceReliefOption(
                        kind = SpaceReliefActionKind.OVERFLOW_OLDER_TO_CLOUDSAVE,
                        title = "Copia tutto tranne video > 300 MB + parcheggiali su CloudSave",
                        subtitle = "Copia ${TransferDisplayFormatting.formatBytes(finalBytes)} ora e salva ${TransferDisplayFormatting.formatBytes(heavyVideoBytes)} cifrati su CloudSave",
                        estimatedSavingsBytes = heavyVideoBytes,
                        estimatedFinalBytes = finalBytes,
                        fitsAvailableSpace = finalBytes <= usableFree
                    )
                )
            }
            if (heavyVideoBytes > 0L) {
                val finalBytes = (totalNeeded - heavyVideoBytes).coerceAtLeast(0L)
                add(
                    SpaceReliefOption(
                        kind = SpaceReliefActionKind.EXCLUDE_HEAVY_VIDEOS_300MB,
                        title = "Escludi video più grandi di 300 MB",
                        subtitle = "Risparmia ${TransferDisplayFormatting.formatBytes(heavyVideoBytes)} subito",
                        estimatedSavingsBytes = heavyVideoBytes,
                        estimatedFinalBytes = finalBytes,
                        fitsAvailableSpace = finalBytes <= usableFree
                    )
                )
            }
            if (olderMediaBytes > 0L) {
                val finalBytes = (totalNeeded - olderMediaBytes).coerceAtLeast(0L)
                add(
                    SpaceReliefOption(
                        kind = SpaceReliefActionKind.LAST_YEAR_MEDIA_ONLY,
                        title = "Copia solo Foto e Video dell'ultimo anno",
                        subtitle = "Risparmia ${TransferDisplayFormatting.formatBytes(olderMediaBytes)} sul nuovo telefono",
                        estimatedSavingsBytes = olderMediaBytes,
                        estimatedFinalBytes = finalBytes,
                        fitsAvailableSpace = finalBytes <= usableFree
                    )
                )
            }
            if (allVideoBytes > 0L && allVideoBytes > heavyVideoBytes) {
                val finalBytes = (totalNeeded - allVideoBytes).coerceAtLeast(0L)
                add(
                    SpaceReliefOption(
                        kind = SpaceReliefActionKind.EXCLUDE_ALL_VIDEOS,
                        title = "Copia prima foto, contatti e file (escludi video)",
                        subtitle = "Risparmia ${TransferDisplayFormatting.formatBytes(allVideoBytes)} per questo passaggio",
                        estimatedSavingsBytes = allVideoBytes,
                        estimatedFinalBytes = finalBytes,
                        fitsAvailableSpace = finalBytes <= usableFree
                    )
                )
            }
        }

        return SpaceReliefOffer(
            receiverName = receiverName,
            totalNeededBytes = totalNeeded,
            availableFreeBytes = availableFreeBytes,
            shortfallBytes = shortfall,
            options = options
        )
    }
}

/** Sovrascrive con zeri i file CSV password temporanei prima di cancellarli dal dispositivo. */
object SecureTempFileShredder {
    fun shredAndDelete(file: File): Boolean {
        if (!file.exists()) return false
        runCatching {
            val length = file.length()
            if (length > 0L) {
                RandomAccessFile(file, "rws").use { raf ->
                    val zeros = ByteArray(minOf(length, 65_536L).toInt())
                    var remaining = length
                    while (remaining > 0L) {
                        val toWrite = minOf(remaining, zeros.size.toLong()).toInt()
                        raf.write(zeros, 0, toWrite)
                        remaining -= toWrite
                    }
                }
            }
        }
        return runCatching { file.delete() }.getOrDefault(false)
    }
}

enum class DirectSwitchLanguage(val code: String, val shortCode: String, val displayName: String) {
    SYSTEM("sys", "AUTO", "Sistema"),
    ITALIAN("it", "IT", "Italiano"),
    ENGLISH("en", "EN", "English"),
    SPANISH("es", "ES", "Español"),
    FRENCH("fr", "FR", "Français"),
    GERMAN("de", "DE", "Deutsch");

    fun effectiveIsoCode(): String {
        if (this != SYSTEM) return code
        val sys = Locale.getDefault().language.lowercase()
        return if (sys in setOf("it", "en", "es", "fr", "de")) sys else "it"
    }

    companion object {
        private const val PREFS = "directswitch_lang_prefs"
        private const val KEY = "preferred_lang"

        fun load(context: Context): DirectSwitchLanguage {
            val saved = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString(KEY, SYSTEM.code)
            return entries.firstOrNull { it.code == saved } ?: SYSTEM
        }

        fun save(context: Context, lang: DirectSwitchLanguage) {
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putString(KEY, lang.code).apply()
        }
    }
}

object DirectSwitchL10n {
    private val translations: Map<String, Map<String, String>> = mapOf(
        "home_subtitle" to mapOf(
            "en" to "Direct phone-to-phone transfer without resetting",
            "es" to "Transferencia directa entre teléfonos sin formatear",
            "fr" to "Transfert direct de téléphone à téléphone sans réinitialiser",
            "de" to "Direkte Übertragung von Handy zu Handy ohne Zurücksetzen"
        ),
        "home_receive_title" to mapOf(
            "en" to "This is the new phone",
            "es" to "Este es el teléfono nuevo",
            "fr" to "Ceci est le nouveau téléphone",
            "de" to "Dies ist das neue Handy"
        ),
        "home_send_title" to mapOf(
            "en" to "This is the old phone",
            "es" to "Este es el teléfono antiguo",
            "fr" to "Ceci est l'ancien téléphone",
            "de" to "Dies ist das alte Handy"
        ),
        "nav_receive" to mapOf("en" to "Receive data", "es" to "Recibir datos", "fr" to "Recevoir", "de" to "Empfangen"),
        "nav_connect" to mapOf("en" to "Connect phone", "es" to "Conectar teléfono", "fr" to "Connecter", "de" to "Verbinden"),
        "nav_select" to mapOf("en" to "What to copy", "es" to "Qué copiar", "fr" to "Quoi copier", "de" to "Was kopieren"),
        "nav_preparing" to mapOf("en" to "Preparing", "es" to "Preparando", "fr" to "Préparation", "de" to "Vorbereitung"),
        "nav_copying" to mapOf("en" to "Copying data", "es" to "Copiando datos", "fr" to "Copie en cours", "de" to "Übertragung"),
        "nav_done" to mapOf("en" to "Completed", "es" to "Completado", "fr" to "Terminé", "de" to "Abgeschlossen"),
        "btn_finish" to mapOf("en" to "Done", "es" to "Listo", "fr" to "Terminé", "de" to "Fertig"),
        "checklist_title" to mapOf(
            "en" to "Post-migration checklist",
            "es" to "Lista de verificación final",
            "fr" to "Liste de vérification finale",
            "de" to "Checkliste nach der Übertragung"
        )
    )

    fun text(key: String, lang: DirectSwitchLanguage, fallbackItalian: String): String {
        val iso = lang.effectiveIsoCode()
        if (iso == "it") return fallbackItalian
        return translations[key]?.get(iso) ?: fallbackItalian
    }
}

data class PostMigrationChecklistItem(
    val id: String,
    val title: String,
    val subtitle: String
)

object MigrationReceiptBuilder {
    fun defaultChecklist(hasWhatsApp: Boolean, hasApps: Boolean, hasSkipped: Boolean): List<PostMigrationChecklistItem> = buildList {
        add(
            PostMigrationChecklistItem(
                id = "verify_media_contacts",
                title = "Verifica Rubrica, Foto e Video sul nuovo telefono",
                subtitle = "Apri Contatti e Galleria prima di resettare il vecchio telefono."
            )
        )
        add(
            PostMigrationChecklistItem(
                id = "banking_spid_2fa",
                title = "Attiva App Bancarie, SPID e Authenticator",
                subtitle = "Configura i codici 2FA finché hai ancora il vecchio dispositivo acceso."
            )
        )
        add(
            PostMigrationChecklistItem(
                id = "mail_accounts",
                title = "Collega gli account Mail / Google / iCloud",
                subtitle = "Accedi alle caselle email nelle Impostazioni del nuovo telefono."
            )
        )
        if (hasApps) {
            add(
                PostMigrationChecklistItem(
                    id = "apps_download",
                    title = "Completa il download delle app selezionate",
                    subtitle = "Controlla che tutte le app principali siano state installate dallo Store."
                )
            )
        }
        if (hasWhatsApp) {
            add(
                PostMigrationChecklistItem(
                    id = "whatsapp_qr",
                    title = "Trasferisci le chat WhatsApp via Codice QR",
                    subtitle = "Verifica che la cronologia chat sia comparsa correttamente."
                )
            )
        }
        if (hasSkipped) {
            add(
                PostMigrationChecklistItem(
                    id = "skipped_review",
                    title = "Controlla gli elementi saltati",
                    subtitle = "Usa «Riprova solo i mancanti» per recuperare eventuali file non copiati."
                )
            )
        }
    }

    fun buildReceiptText(
        peerName: String,
        isReceiver: Boolean,
        connectionMedium: TransferConnectionMedium,
        completedFiles: Int,
        totalBytes: Long,
        mergedContacts: Int,
        importedCalendars: Int,
        importedReminders: Int,
        importedSms: Int,
        importedCallLogs: Int,
        appsCount: Int,
        skippedCount: Int
    ): String {
        val df = SimpleDateFormat("dd/MM/yyyy HH:mm", Locale.ITALY)
        val role = if (isReceiver) "Ricevuto da" else "Inviato a"
        return buildString {
            appendLine("DirectSwitch — Ricevuta di Migrazione")
            appendLine("Data: ${df.format(Date())}")
            appendLine("$role: ${peerName.ifBlank { "Dispositivo collegato" }}")
            appendLine("Connessione: ${connectionMedium.badgeLabel()}")
            appendLine("----------------------------------------")
            appendLine("File trasferiti: $completedFiles (${TransferDisplayFormatting.formatBytes(totalBytes)})")
            appendLine("Contatti uniti: $mergedContacts")
            appendLine("Calendari importati: $importedCalendars")
            appendLine("Promemoria salvati: $importedReminders")
            appendLine("SMS salvati: $importedSms")
            appendLine("Chiamate salvate: $importedCallLogs")
            appendLine("App in elenco: $appsCount")
            appendLine("Elementi saltati: $skippedCount")
            appendLine("----------------------------------------")
            append("Trasferimento locale cifrato AES-256-GCM completato senza cloud.")
        }
    }
}
