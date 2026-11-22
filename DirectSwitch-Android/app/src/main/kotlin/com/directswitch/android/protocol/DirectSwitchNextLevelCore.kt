//
//  DirectSwitchNextLevelCore.kt
//  DirectSwitch-Android
//
//  Created by Nicolas Donati.
//  Copyright © 2026 Nicolas Donati. Tutti i diritti riservati.
//

package com.directswitch.android.protocol

import android.content.Context
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import java.io.File
import java.io.RandomAccessFile
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
    SYSTEM("sys", "AUTO", "Sistema / Auto"),
    ITALIAN("it", "IT", "Italiano"),
    ENGLISH("en", "EN", "English"),
    FRENCH("fr", "FR", "Français");

    fun effectiveIsoCode(): String {
        if (this != SYSTEM) return code
        val sys = Locale.getDefault().language.lowercase()
        return if (sys in setOf("it", "en", "fr")) sys else "it"
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
    var activeLanguage by mutableStateOf(DirectSwitchLanguage.SYSTEM)

    fun init(context: Context) {
        activeLanguage = DirectSwitchLanguage.load(context)
    }

    fun setLanguage(context: Context, lang: DirectSwitchLanguage) {
        activeLanguage = lang
        DirectSwitchLanguage.save(context, lang)
    }

    fun effectiveCode(): String = activeLanguage.effectiveIsoCode()

    private val keyTranslations: Map<String, Map<String, String>> = mapOf(
        "home_subtitle" to mapOf(
            "en" to "Direct phone-to-phone transfer without resetting",
            "fr" to "Transfert direct de téléphone à téléphone sans réinitialiser"
        ),
        "home_receive_title" to mapOf(
            "en" to "This is the new phone",
            "fr" to "Ceci est le nouveau téléphone"
        ),
        "home_send_title" to mapOf(
            "en" to "This is the old phone",
            "fr" to "Ceci est l'ancien téléphone"
        ),
        "nav_receive" to mapOf("en" to "Receive data", "fr" to "Recevoir"),
        "nav_connected" to mapOf("en" to "Connected", "fr" to "Connecté"),
        "nav_connect" to mapOf("en" to "Connect phone", "fr" to "Connecter"),
        "nav_select" to mapOf("en" to "What to copy", "fr" to "Quoi copier"),
        "nav_preparing" to mapOf("en" to "Preparing", "fr" to "Préparation"),
        "nav_copying" to mapOf("en" to "Copying data", "fr" to "Copie en cours"),
        "nav_done" to mapOf("en" to "Completed", "fr" to "Terminé"),
        "btn_finish" to mapOf("en" to "Done", "fr" to "Terminé"),
        "checklist_title" to mapOf(
            "en" to "Post-migration checklist",
            "fr" to "Liste de vérification finale"
        )
    )

    private val phraseTranslations: Map<String, Pair<String, String>> = mapOf(
        // Navigazione & Pulsanti comuni
        "Indietro" to ("Back" to "Retour"),
        "Chiudi" to ("Close" to "Fermer"),
        "Annulla" to ("Cancel" to "Annuler"),
        "Fine" to ("Done" to "Terminé"),
        "Torna alla Home" to ("Back to Home" to "Retour à l'accueil"),
        "Continua" to ("Continue" to "Continuer"),
        "Collega" to ("Connect" to "Connecter"),
        "Collegamento in corso..." to ("Connecting..." to "Connexion en cours..."),
        "Avvio preparazione..." to ("Starting preparation..." to "Lancement de la préparation..."),
        "Cambia" to ("Change" to "Changer"),
        "Ricarica" to ("Reload" to "Recharger"),
        "Aggiorna" to ("Refresh" to "Actualiser"),
        "Ricontrolla" to ("Recheck" to "Vérifier"),
        "Ignora" to ("Dismiss" to "Ignorer"),
        "Riprendi ora" to ("Resume now" to "Reprendre"),
        "Copia solo novità" to ("Copy new items only" to "Copier les nouveautés"),
        "Copia tutto" to ("Copy all" to "Tout copier"),
        "Seleziona tutto" to ("Select all" to "Tout sélectionner"),
        "Deseleziona tutto" to ("Deselect all" to "Tout désélectionner"),
        "Seleziona tutte" to ("Select all" to "Tout sélectionner"),
        "Deseleziona" to ("Deselect" to "Désélectionner"),
        "Mostra tutte" to ("Show all" to "Tout afficher"),
        "Nascondi" to ("Hide" to "Masquer"),
        "Installata" to ("Installed" to "Installée"),
        "Concedi permesso" to ("Grant permission" to "Autoriser"),
        "Impostazioni" to ("Settings" to "Paramètres"),

        // Home
        "Invia" to ("Send" to "Envoyer"),
        "Ricevi" to ("Receive" to "Recevoir"),
        "Copia i tuoi dati senza formattare: trasferisce rubrica, foto, video 4K, calendari, SMS, chiamate, audio, documenti e chat WhatsApp direttamente tra due telefoni già configurati, via Wi-Fi locale o Hotspot 5GHz senza passare dal cloud." to (
            "Copy your data without resetting: transfers contacts, photos, 4K videos, calendars, SMS, call logs, audio, documents and WhatsApp chats directly between two already set up phones via local Wi-Fi or 5GHz Hotspot without the cloud." to
                "Copiez vos données sans réinitialiser : transfère contacts, photos, vidéos 4K, calendriers, SMS, appels, audio, documents et discussions WhatsApp directement entre deux téléphones déjà configurés via Wi-Fi local ou partage 5 GHz sans cloud."
        ),
        "Invia i dati da questo telefono direttamente senza cavo all'altro telefono (Android o iPhone) dove hai aperto 'Ricevi'." to (
            "Send data wirelessly from this phone directly to the other phone (Android or iPhone) where you opened 'Receive'." to
                "Envoyez les données sans fil depuis ce téléphone vers l'autre téléphone (Android ou iPhone) où vous avez ouvert « Recevoir »."
        ),
        "Mostra il codice monouso a 6 cifre (come 'Passa a iOS') o il codice QR per ricevere i dati dal tuo altro telefono senza cancellare nulla." to (
            "Show a one-time 6-digit code (like Move to iOS) or QR code to receive data from your other phone without erasing anything." to
                "Affichez un code unique à 6 chiffres (comme Migrer vers iOS) ou un code QR pour recevoir les données depuis votre autre téléphone sans rien effacer."
        ),

        // Ricevi
        "Passo 1 di 2" to ("Step 1 of 2" to "Étape 1 sur 2"),
        "Come collegare i telefoni" to ("How to connect phones" to "Comment connecter les téléphones"),
        "Inserisci il codice monouso" to ("Enter the one-time code" to "Saisissez le code unique"),
        "Inquadra il codice QR" to ("Scan the QR code" to "Scannez le code QR"),
        "Apri DirectSwitch sul vecchio telefono e tocca Invia" to ("Open DirectSwitch on the old phone and tap Send" to "Ouvrez DirectSwitch sur l'ancien téléphone et touchez Envoyer"),
        "Codice a 6 cifre" to ("6-digit code" to "Code à 6 chiffres"),
        "Codice QR" to ("QR Code" to "Code QR"),
        "In attesa di collegamento..." to ("Waiting for connection..." to "En attente de connexion..."),
        "Hotspot diretto 5GHz" to ("Direct 5GHz Hotspot" to "Point d'accès direct 5 GHz"),
        "Usa senza rete Wi-Fi di casa" to ("Use without home Wi-Fi" to "Utiliser sans réseau Wi-Fi"),
        "Salva SMS nell'app Messaggi" to ("Save SMS in Messages app" to "Enregistrer les SMS dans Messages"),
        "Tocca per abilitare l'importazione nativa" to ("Tap to enable native import" to "Touchez pour activer l'importation native"),
        "Ricrea posizioni e cartelle originali" to ("Recreate original folders" to "Recréer les dossiers d'origine"),
        "Autorizza «Accesso a tutti i file» per salvare intere posizioni nelle identiche cartelle di origine" to (
            "Grant 'All files access' to save entire locations into identical original folders" to
                "Autorisez « Accès à tous les fichiers » pour enregistrer les emplacements dans leurs dossiers d'origine"
        ),
        "Collegato!" to ("Connected!" to "Connecté !"),
        "Prosegui sull'altro telefono" to ("Continue on the other phone" to "Continuez sur l'autre téléphone"),

        // Invia - Collega
        "Passo 1 di 3" to ("Step 1 of 3" to "Étape 1 sur 3"),
        "Collega il nuovo telefono" to ("Connect the new phone" to "Connecter le nouveau téléphone"),
        "Seleziona il telefono rilevato o inquadra il codice QR" to ("Select a nearby phone or scan the QR code" to "Sélectionnez un téléphone détecté ou scannez le code QR"),
        "Telefoni vicini" to ("Nearby phones" to "Téléphones à proximité"),
        "Ricerca sulla rete Wi-Fi..." to ("Searching on Wi-Fi..." to "Recherche sur le réseau Wi-Fi..."),
        "Assicurati che 'Ricevi' sia aperto sull'altro telefono" to ("Make sure 'Receive' is open on the other phone" to "Vérifiez que « Recevoir » est ouvert sur l'autre téléphone"),
        "iPhone pronto a ricevere" to ("iPhone ready to receive" to "iPhone prêt à recevoir"),
        "Android pronto a ricevere" to ("Android ready to receive" to "Android prêt à recevoir"),
        "Oppure usa la fotocamera" to ("Or use the camera" to "Ou utilisez l'appareil photo"),
        "Chiudi fotocamera" to ("Close camera" to "Fermer la caméra"),
        "Inquadra codice QR" to ("Scan QR code" to "Scanner le code QR"),
        "Incolla codice di collegamento" to ("Paste pairing code" to "Coller le code de liaison"),
        "Nascondi inserimento manuale" to ("Hide manual input" to "Masquer la saisie manuelle"),
        "Incolla qui il codice" to ("Paste code here" to "Collez le code ici"),

        // Invia - Categorie
        "Passo 2 di 3" to ("Step 2 of 3" to "Étape 2 sur 3"),
        "Stato collegamento" to ("Connection status" to "État de la connexion"),
        "Cosa inviare" to ("What to send" to "Que transférer"),
        "Spunta ogni voce per aprire la configurazione del passaggio al nuovo telefono." to (
            "Select each item to configure what will be copied to the new phone." to
                "Cochez chaque élément pour configurer le transfert vers le nouveau téléphone."
        ),
        "Rubrica contatti" to ("Contacts" to "Contacts"),
        "Foto e Album" to ("Photos & Albums" to "Photos et Albums"),
        "Video originali" to ("Original Videos" to "Vidéos originales"),
        "Calendari" to ("Calendars" to "Calendriers"),
        "Messaggi SMS" to ("SMS Messages" to "Messages SMS"),
        "Cronologia Chiamate" to ("Call History" to "Historique d'appels"),
        "Audio e Memo Vocali" to ("Audio & Voice Memos" to "Audio et Mémos vocaux"),
        "Documenti e Posizioni File" to ("Documents & File Locations" to "Documents et Emplacements"),
        "Chat WhatsApp" to ("WhatsApp Chats" to "Discussions WhatsApp"),
        "App scaricate" to ("Downloaded Apps" to "Apps téléchargées"),
        "Gratuito • Codice QR" to ("Free • QR Code" to "Gratuit • Code QR"),
        "App, Account Mail e Impostazioni" to ("Apps, Email Accounts & Settings" to "Apps, Comptes Mail et Paramètres"),
        "Modalità Delta attiva (solo novità)" to ("Delta mode active (new items only)" to "Mode Delta actif (nouveautés uniquement)"),
        "Copia le voci selezionate" to ("Copy selected items" to "Copier les éléments sélectionnés"),
        "Vai al passaggio Chat WhatsApp" to ("Go to WhatsApp Chat Transfer" to "Passer au transfert WhatsApp"),
        "Include numeri con etichette, foto profilo, email, indirizzi e compleanni con unione duplicati." to (
            "Includes labeled phone numbers, profile photos, emails, addresses and birthdays with duplicate merge." to
                "Inclut numéros étiquetés, photos de profil, e-mails, adresses et anniversaires avec fusion des doublons."
        ),
        "Filtri rapidi Foto" to ("Quick Photo Filters" to "Filtres rapides Photos"),
        "Tutte le foto" to ("All photos" to "Toutes les photos"),
        "Solo ultimo anno" to ("Last year only" to "Dernière année"),
        "Filtri rapidi Video" to ("Quick Video Filters" to "Filtres rapides Vidéo"),
        "Tutti i video" to ("All videos" to "Toutes les vidéos"),
        "Solo ≤ 500 MB" to ("Only ≤ 500 MB" to "Seulement ≤ 500 Mo"),
        "Aggiornamento alla data odierna in corso..." to ("Refreshing up to today..." to "Actualisation jusqu'à aujourd'hui..."),
        "Se spento copia sia lo storico sia eventuali voci future." to (
            "When off, copies both history and any future entries." to
                "Si désactivé, copie l'historique et les entrées futures."
        ),
        "Aggiungi e spunta le posizioni" to ("Add and check locations" to "Ajouter et cocher les emplacements"),
        "Spunta una o più posizioni da copiare" to ("Check one or more locations to copy" to "Cochez un ou plusieurs emplacements à copier"),
        "Aggiungi altra posizione (Drive / SD / USB / Cartella)" to ("Add another location (Drive / SD / USB / Folder)" to "Ajouter un autre emplacement (Drive / SD / USB / Dossier)"),
        "Rimuovi posizioni aggiunte" to ("Remove added locations" to "Supprimer les emplacements ajoutés"),
        "Aggiungi altre app dal Catalogo Esteso" to ("Add more apps from Extended Catalog" to "Ajouter d'autres apps du catalogue étendu"),
        "Trasferisci Password (Chrome / Gestore Password CSV)" to ("Transfer Passwords (Chrome / Password Manager CSV)" to "Transférer Mots de passe (CSV Chrome / Gestionnaire)"),
        "Seleziona file .csv Password" to ("Select Password .csv file" to "Sélectionner le fichier .csv Mots de passe"),
        "Aggiungi altro file .csv Password" to ("Add another Password .csv file" to "Ajouter un autre CSV Mots de passe"),
        "Controllo posizioni sul telefono" to ("Phone locations check" to "Vérification des emplacements"),
        "Autorizza accesso completo" to ("Grant full access" to "Autoriser l'accès complet"),
        "Autorizza posizione" to ("Authorize location" to "Autoriser l'emplacement"),
        "Continua lo stesso" to ("Continue anyway" to "Continuer quand même"),

        // Preparazione & Trasferimento
        "Sto preparando la ricezione…" to ("Preparing to receive…" to "Préparation de la réception…"),
        "Sto preparando il trasferimento…" to ("Preparing transfer…" to "Préparation du transfert…"),
        "Trasferimento completato" to ("Transfer completed" to "Transfert terminé"),
        "I tuoi dati sono pronti su questo telefono" to ("Your data is ready on this phone" to "Vos données sont prêtes sur ce téléphone"),
        "Tutti i dati selezionati sono stati copiati" to ("All selected data has been copied" to "Toutes les données sélectionnées ont été copiées"),
        "Copia su questo telefono..." to ("Copying to this phone..." to "Copie sur ce téléphone..."),
        "Copia dei dati in corso..." to ("Copying data..." to "Copie des données en cours..."),
        "Tieni entrambi i telefoni vicini fino al termine" to ("Keep both phones nearby until finished" to "Gardez les deux téléphones à proximité jusqu'à la fin"),
        "Contatti uniti" to ("Contacts merged" to "Contacts fusionnés"),
        "Foto, Video e File" to ("Photos, Videos & Files" to "Photos, Vidéos et Fichiers"),
        "Calendari importati" to ("Calendars imported" to "Calendriers importés"),
        "Promemoria salvati" to ("Reminders saved" to "Rappels enregistrés"),
        "Messaggi salvati" to ("Messages saved" to "Messages enregistrés"),
        "Chiamate salvate" to ("Call logs saved" to "Appels enregistrés"),
        "Date EXIF ricostruite" to ("EXIF dates restored" to "Dates EXIF restaurées"),
        "Live / Motion Photo preservate" to ("Live / Motion Photos preserved" to "Live / Motion Photos préservées"),
        "Audio convertiti compatibili iOS" to ("Audio converted for iOS" to "Audio convertis pour iOS"),
        "Doppioni ignorati" to ("Duplicates skipped" to "Doublons ignorés"),
        "File non disponibili saltati" to ("Unavailable files skipped" to "Fichiers indisponibles ignorés"),
        "Account Mail e Cloud" to ("Email & Cloud Accounts" to "Comptes Mail et Cloud"),
        "Aggiungi account Mail / Google" to ("Add Mail / Google account" to "Ajouter un compte Mail / Google"),
        "Cartelle ricreate su questo telefono" to ("Folders recreated on this phone" to "Dossiers recréés sur ce téléphone"),
        "Ripristina la tua app Messaggi predefinita" to ("Restore your default Messages app" to "Restaurer votre app Messages par défaut"),
        "Ripristina app Messaggi" to ("Restore Messages app" to "Restaurer l'app Messages"),

        // Next-level
        "Cavo USB-C diretto" to ("Direct USB-C Cable" to "Câble USB-C direct"),
        "Wi-Fi Diretto P2P" to ("Direct P2P Wi-Fi" to "Wi-Fi Direct P2P"),
        "Wi-Fi Locale" to ("Local Wi-Fi" to "Wi-Fi Local"),
        "Assistente Salva-Spazio" to ("Space Saver Assistant" to "Assistant Gain d'espace"),
        "Scegli una soluzione rapida con 1 tocco per ripartire subito:" to ("Pick a 1-tap quick fix to resume immediately:" to "Choisissez une solution rapide en 1 geste pour repartir :"),
        "Rientra ✓" to ("Fits ✓" to "Compatible ✓"),
        "Tocca per vedere i dettagli e riprovare solo i mancanti" to ("Tap to view details and retry missing items only" to "Touchez pour voir les détails et réessayer les manquants"),
        "Triage Batteria Critica" to ("Critical Battery Triage" to "Mode Batterie Critique"),

        // Practical Pro (#1–#5): Guardia Termica, Smart Clean, HEIC, Riconciliazione, AP Isolation
        "Raffreddamento termico (45s)" to ("Thermal cooldown (45s)" to "Refroidissement thermique (45s)"),
        "Limite termico (1 flusso)" to ("Thermal limit (1 stream)" to "Limite thermique (1 flux)"),
        "Raffreddamento termico in corso (pausa automatica 45s)..." to (
            "Thermal cooldown in progress (automatic 45s pause)..." to
            "Refroidissement thermique en cours (pause automatique 45s)..."
        ),
        "Temperatura elevata — 1 flusso alla volta" to (
            "High temperature — 1 stream at a time" to
            "Température élevée — 1 flux à la fois"
        ),
        "Ho attivato l'Hotspot • Riprova collegamento" to (
            "Hotspot enabled • Retry connection" to
            "Partage de connexion activé • Réessayer"
        ),
        "Smart Clean & Compatibilità Pro" to ("Smart Clean & Pro Compatibility" to "Smart Clean & Compatibilité Pro"),
        "Unisci contatti duplicati (+39)" to ("Merge duplicate contacts (+39)" to "Fusionner les contacts en double (+39)"),
        "Fonde numeri e note in memoria senza toccare il vecchio telefono" to (
            "Merges phone numbers and notes in memory without modifying the old phone" to
            "Fusionne numéros et notes en mémoire sans modifier l'ancien téléphone"
        ),
        "Salta foto duplicate esatte (SHA-256)" to ("Skip exact duplicate photos (SHA-256)" to "Ignorer les photos identiques (SHA-256)"),
        "Evita di copiare file identici pixel-per-pixel" to (
            "Avoids copying identical pixel-for-pixel files" to
            "Évite de copier des fichiers identiques pixel par pixel"
        ),
        "Escludi vecchi screenshot (> 12 mesi)" to ("Exclude old screenshots (> 12 months)" to "Exclure les anciennes captures (> 12 mois)"),
        "Libera spazio evitando schermate datate" to (
            "Saves storage by skipping outdated screenshots" to
            "Libère de l'espace en évitant les captures anciennes"
        ),
        "Massima compatibilità HEIC → JPEG" to ("Maximum compatibility HEIC → JPEG" to "Compatibilité maximale HEIC → JPEG"),
        "Converte foto iPhone in JPEG preservando data scatto, rotazione e GPS" to (
            "Converts iPhone photos to JPEG while preserving capture date, rotation, and GPS" to
            "Convertit les photos iPhone en JPEG en préservant date, rotation et GPS"
        ),
        "Converte foto HEIC mantenendo data scatto, rotazione e GPS" to (
            "Converts HEIC photos while preserving capture date, rotation, and GPS" to
            "Convertit les photos HEIC en préservant date, rotation et GPS"
        ),
        "Verifica SHA-256 Post-Migrazione: 100% Integro" to (
            "Post-Migration SHA-256 Verification: 100% Verified" to
            "Vérification SHA-256 Post-Migration : 100 % Intègre"
        )
    )

    fun text(key: String, lang: DirectSwitchLanguage, fallbackItalian: String): String {
        val iso = lang.effectiveIsoCode()
        if (iso == "it") return fallbackItalian
        return keyTranslations[key]?.get(iso) ?: fallbackItalian
    }

    fun tr(italian: String, lang: DirectSwitchLanguage = activeLanguage): String {
        val iso = lang.effectiveIsoCode()
        if (iso == "it") return italian
        val pair = phraseTranslations[italian] ?: return italian
        return if (iso == "en") pair.first else pair.second
    }

    fun tr(italian: String, en: String, fr: String, lang: DirectSwitchLanguage = activeLanguage): String {
        return when (lang.effectiveIsoCode()) {
            "en" -> en
            "fr" -> fr
            else -> italian
        }
    }

    fun translateEta(rawEta: String?, lang: DirectSwitchLanguage = activeLanguage): String? {
        if (rawEta.isNullOrBlank()) return null
        val iso = lang.effectiveIsoCode()
        if (iso == "it") return rawEta
        if (rawEta.startsWith("Calcolo tempo")) {
            return if (iso == "en") "Calculating remaining time…" else "Calcul du temps restant…"
        }
        if (rawEta.startsWith("Meno di un minuto")) {
            return if (iso == "en") "Less than 1 minute remaining" else "Moins d'une minute restante"
        }
        if (rawEta.startsWith("Circa ") && rawEta.contains(" min")) {
            val mins = rawEta.removePrefix("Circa ").substringBefore(" min").trim()
            return if (iso == "en") "About $mins min left" else "Environ $mins min restantes"
        }
        return rawEta
    }
}
