//
//  DirectSwitchNextLevelCore.swift
//  DirectSwitch-iOS
//
//  Created by Nicolas Donati.
//  Copyright © 2026 Nicolas Donati. Tutti i diritti riservati.
//

import Foundation
import Combine

/// Tipo di collegamento locale attivo rilevato (priorità: Cavo USB-C > Wi-Fi P2P AWDL > Wi-Fi Locale).
enum TransferConnectionMedium: String, Codable, Equatable, Sendable {
    case usbCable
    case peerToPeerWifi
    case localWifi

    var badgeLabel: String {
        switch self {
        case .usbCable: return "Cavo USB-C diretto"
        case .peerToPeerWifi: return "Wi-Fi Diretto P2P (AWDL)"
        case .localWifi: return "Wi-Fi Locale"
        }
    }

    var systemImage: String {
        switch self {
        case .usbCable: return "cable.connector"
        case .peerToPeerWifi: return "antenna.radiowaves.left.and.right"
        case .localWifi: return "wifi"
        }
    }
}

/// Filtri rapidi applicabili a Foto e Video prima o durante il salvataggio spazio.
struct MediaTransferFilterOptions: Codable, Equatable, Sendable {
    var photosLastYearOnly: Bool = false
    var selectedPhotoAlbums: [String] = []
    var videosLastYearOnly: Bool = false
    /// Se > 0 esclude i video più pesanti della soglia indicata (es. 500_000_000 = 500 MB).
    var maxVideoBytes: Int64 = 0
    /// Se true transcodifica al volo i video > 40 MB in HEVC 1080p (-55% spazio sul ricevente).
    var compactVideo1080pHevc: Bool = false
    /// Se false (predefinito), esclude a priori le foto/video solo su iCloud non scaricati localmente
    /// mostrando direttamente solo i file realmente idonei al trasferimento (zero sorprese di file illeggibili).
    var includeICloudOnlyMedia: Bool = false

    enum CodingKeys: String, CodingKey {
        case photosLastYearOnly, selectedPhotoAlbums, videosLastYearOnly
        case maxVideoBytes, compactVideo1080pHevc, includeICloudOnlyMedia
    }

    init(
        photosLastYearOnly: Bool = false,
        selectedPhotoAlbums: [String] = [],
        videosLastYearOnly: Bool = false,
        maxVideoBytes: Int64 = 0,
        compactVideo1080pHevc: Bool = false,
        includeICloudOnlyMedia: Bool = false
    ) {
        self.photosLastYearOnly = photosLastYearOnly
        self.selectedPhotoAlbums = selectedPhotoAlbums
        self.videosLastYearOnly = videosLastYearOnly
        self.maxVideoBytes = maxVideoBytes
        self.compactVideo1080pHevc = compactVideo1080pHevc
        self.includeICloudOnlyMedia = includeICloudOnlyMedia
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        photosLastYearOnly = try c.decodeIfPresent(Bool.self, forKey: .photosLastYearOnly) ?? false
        selectedPhotoAlbums = try c.decodeIfPresent([String].self, forKey: .selectedPhotoAlbums) ?? []
        videosLastYearOnly = try c.decodeIfPresent(Bool.self, forKey: .videosLastYearOnly) ?? false
        maxVideoBytes = try c.decodeIfPresent(Int64.self, forKey: .maxVideoBytes) ?? 0
        compactVideo1080pHevc = try c.decodeIfPresent(Bool.self, forKey: .compactVideo1080pHevc) ?? false
        includeICloudOnlyMedia = try c.decodeIfPresent(Bool.self, forKey: .includeICloudOnlyMedia) ?? false
    }

    var isDefault: Bool {
        !photosLastYearOnly && selectedPhotoAlbums.isEmpty && !videosLastYearOnly && maxVideoBytes == 0 && !compactVideo1080pHevc && !includeICloudOnlyMedia
    }
}

/// Elemento saltato o non disponibile durante il trasferimento, mostrato nel report interattivo con opzione Riprova.
struct SkippedTransferItemRecord: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let fileName: String
    let category: TransferCategory
    let sizeBytes: Int64
    let reason: String
}

/// Checkpoint persistente su disco per riprendere trasferimenti grandi anche dopo riavvio o chiusura dell'app.
struct TransferCheckpointRecord: Codable, Equatable, Sendable {
    let sessionId: String
    let qrPayloadJson: String
    let receiverName: String
    let receiverPlatform: DevicePlatform
    let scope: ActiveTransferScope
    let completedItemIds: [String]
    let uploadedBytes: Int64
    let totalItems: Int
    let totalBytes: Int64
    let skippedItems: [SkippedTransferItemRecord]
    let filterOptions: MediaTransferFilterOptions
    let savedAtEpochMillis: Int64

    var completionPercent: Int {
        if totalBytes > 0 {
            return TransferDisplayFormatting.percentageInt(
                fraction: Double(uploadedBytes) / Double(totalBytes),
                isCompleted: false
            )
        }
        if totalItems > 0 {
            return TransferDisplayFormatting.percentageInt(
                fraction: Double(completedItemIds.count) / Double(totalItems),
                isCompleted: false
            )
        }
        return 0
    }
}

/// Gestore atomico su disco del checkpoint di ripresa (auto-scadenza dopo 24 ore).
enum TransferCheckpointStore {
    private static let maxAgeMillis: Int64 = 24 * 60 * 60 * 1000

    static func defaultFileURL() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = appSupport.appendingPathComponent("DirectSwitch", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("transfer_checkpoint_v1.json")
    }

    static func save(_ record: TransferCheckpointRecord, to fileURL: URL? = nil) {
        let target = fileURL ?? defaultFileURL()
        try? FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(record) else { return }
        try? data.write(to: target, options: .atomic)
    }

    static func load(from fileURL: URL? = nil, nowEpochMillis: Int64 = Int64(Date().timeIntervalSince1970 * 1000.0)) -> TransferCheckpointRecord? {
        let target = fileURL ?? defaultFileURL()
        guard let data = try? Data(contentsOf: target),
              let record = try? JSONDecoder().decode(TransferCheckpointRecord.self, from: data) else {
            return nil
        }
        if nowEpochMillis - record.savedAtEpochMillis > maxAgeMillis {
            clear(at: target)
            return nil
        }
        guard !record.sessionId.isEmpty, !record.qrPayloadJson.isEmpty else { return nil }
        return record
    }

    static func clear(at fileURL: URL? = nil) {
        let target = fileURL ?? defaultFileURL()
        try? FileManager.default.removeItem(at: target)
    }
}

/// Proposta interattiva dell'Assistente "Salva-Spazio" quando il ricevente ha meno GB liberi del necessario.
enum SpaceReliefActionKind: String, Codable, Equatable, Sendable {
    case overflowOlderToCloudSave
    case compactVideosHevc1080p
    case excludeHeavyVideos300Mb
    case lastYearMediaOnly
}

struct SpaceReliefOption: Identifiable, Equatable, Sendable {
    var id: String { kind.rawValue }
    let kind: SpaceReliefActionKind
    let title: String
    let subtitle: String
    let estimatedSavingsBytes: Int64
    let estimatedFinalBytes: Int64
    let fitsAvailableSpace: Bool
}

struct SpaceReliefOffer: Equatable, Sendable {
    let receiverName: String
    let totalNeededBytes: Int64
    let availableFreeBytes: Int64
    let shortfallBytes: Int64
    let options: [SpaceReliefOption]
}

enum SpaceReliefPlanner {
    static let safetyMarginBytes: Int64 = 250 * 1024 * 1024
    static let heavyVideoThresholdBytes: Int64 = 300 * 1024 * 1024

    static func evaluate(
        receiverName: String,
        availableFreeBytes: Int64,
        items: [ManifestItem],
        nowEpochMillis: Int64 = Int64(Date().timeIntervalSince1970 * 1000.0)
    ) -> SpaceReliefOffer? {
        let totalNeeded = items.reduce(Int64(0)) { $0 + max(0, $1.sizeBytes) }
        let usableFree = max(0, availableFreeBytes - safetyMarginBytes)
        guard totalNeeded > usableFree, totalNeeded > 0 else { return nil }

        let shortfall = totalNeeded - usableFree
        let oneYearCutoff = nowEpochMillis - Int64(365) * 86_400_000

        let videoBytes = items.filter { $0.category == .VIDEOS }.reduce(Int64(0)) { $0 + max(0, $1.sizeBytes) }
        let heavyVideoBytes = items.filter { $0.category == .VIDEOS && $0.sizeBytes > heavyVideoThresholdBytes }
            .reduce(Int64(0)) { $0 + max(0, $1.sizeBytes) }
        let olderMediaBytes = items.filter {
            ($0.category == .PHOTOS || $0.category == .VIDEOS) &&
            $0.capturedEpochMillis > 0 &&
            $0.capturedEpochMillis < oneYearCutoff
        }.reduce(Int64(0)) { $0 + max(0, $1.sizeBytes) }

        var options: [SpaceReliefOption] = []
        if olderMediaBytes > 0 {
            let finalBytes = max(0, totalNeeded - olderMediaBytes)
            options.append(
                SpaceReliefOption(
                    kind: .overflowOlderToCloudSave,
                    title: "Ultimo anno sul nuovo telefono + resto cifrato su CloudSave",
                    subtitle: "Copia \(TransferDisplayFormatting.formatBytes(finalBytes)) ora e parcheggia \(TransferDisplayFormatting.formatBytes(olderMediaBytes)) su CloudSave (zero perdite)",
                    estimatedSavingsBytes: olderMediaBytes,
                    estimatedFinalBytes: finalBytes,
                    fitsAvailableSpace: finalBytes <= usableFree
                )
            )
        } else if heavyVideoBytes > 0 {
            let finalBytes = max(0, totalNeeded - heavyVideoBytes)
            options.append(
                SpaceReliefOption(
                    kind: .overflowOlderToCloudSave,
                    title: "Copia tutto tranne video > 300 MB + parcheggiali su CloudSave",
                    subtitle: "Copia \(TransferDisplayFormatting.formatBytes(finalBytes)) ora e salva \(TransferDisplayFormatting.formatBytes(heavyVideoBytes)) cifrati su CloudSave",
                    estimatedSavingsBytes: heavyVideoBytes,
                    estimatedFinalBytes: finalBytes,
                    fitsAvailableSpace: finalBytes <= usableFree
                )
            )
        }
        if videoBytes > 50 * 1024 * 1024 {
            let saved = Int64(Double(videoBytes) * 0.55)
            let finalBytes = max(0, totalNeeded - saved)
            options.append(
                SpaceReliefOption(
                    kind: .compactVideosHevc1080p,
                    title: "Comprimi video al volo (HEVC 1080p)",
                    subtitle: "Risparmia circa \(TransferDisplayFormatting.formatBytes(saved)) mantenendo ottima qualità",
                    estimatedSavingsBytes: saved,
                    estimatedFinalBytes: finalBytes,
                    fitsAvailableSpace: finalBytes <= usableFree
                )
            )
        }
        if heavyVideoBytes > 0 {
            let finalBytes = max(0, totalNeeded - heavyVideoBytes)
            options.append(
                SpaceReliefOption(
                    kind: .excludeHeavyVideos300Mb,
                    title: "Escludi video più grandi di 300 MB",
                    subtitle: "Risparmia \(TransferDisplayFormatting.formatBytes(heavyVideoBytes)) subito",
                    estimatedSavingsBytes: heavyVideoBytes,
                    estimatedFinalBytes: finalBytes,
                    fitsAvailableSpace: finalBytes <= usableFree
                )
            )
        }
        if olderMediaBytes > 0 {
            let finalBytes = max(0, totalNeeded - olderMediaBytes)
            options.append(
                SpaceReliefOption(
                    kind: .lastYearMediaOnly,
                    title: "Copia solo Foto e Video dell'ultimo anno",
                    subtitle: "Risparmia \(TransferDisplayFormatting.formatBytes(olderMediaBytes)) sul nuovo telefono",
                    estimatedSavingsBytes: olderMediaBytes,
                    estimatedFinalBytes: finalBytes,
                    fitsAvailableSpace: finalBytes <= usableFree
                )
            )
        }

        return SpaceReliefOffer(
            receiverName: receiverName,
            totalNeededBytes: totalNeeded,
            availableFreeBytes: availableFreeBytes,
            shortfallBytes: shortfall,
            options: options
        )
    }
}

/// Cancellazione sicura dei file sensibili temporanei (es. CSV password esportati da Safari/Chrome):
/// sovrascrive i byte con zeri prima di rimuovere il file dal disco.
enum SecureTempFileShredder {
    @discardableResult
    static func shredAndDelete(url: URL) -> Bool {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return false }
        if let attrs = try? fm.attributesOfItem(atPath: url.path),
           let fileSize = attrs[.size] as? Int, fileSize > 0,
           let handle = try? FileHandle(forWritingTo: url) {
            let chunkSize = min(fileSize, 65_536)
            let zeroChunk = Data(repeating: 0, count: chunkSize)
            var remaining = fileSize
            while remaining > 0 {
                let toWrite = min(remaining, chunkSize)
                handle.write(toWrite == chunkSize ? zeroChunk : Data(repeating: 0, count: toWrite))
                remaining -= toWrite
            }
            try? handle.synchronize()
            try? handle.close()
        }
        return (try? fm.removeItem(at: url)) != nil
    }
}

/// Lingue supportate in DirectSwitch (`Sistema` + Italiano / English / Français).
enum DirectSwitchLanguage: String, CaseIterable, Identifiable, Codable, Sendable {
    case system = "sys"
    case italian = "it"
    case english = "en"
    case french = "fr"

    var id: String { rawValue }

    var shortCode: String {
        switch self {
        case .system: return "AUTO"
        case .italian: return "IT"
        case .english: return "EN"
        case .french: return "FR"
        }
    }

    var displayName: String {
        switch self {
        case .system: return "Sistema / Auto"
        case .italian: return "Italiano"
        case .english: return "English"
        case .french: return "Français"
        }
    }

    var effectiveIsoCode: String {
        if self != .system { return rawValue }
        let code = Locale.preferredLanguages.first?.prefix(2).lowercased() ?? "it"
        if ["it", "en", "fr"].contains(code) { return code }
        return "it"
    }
}

@MainActor
final class DirectSwitchLocalizationStore: ObservableObject {
    static let shared = DirectSwitchLocalizationStore()
    private static let storageKey = "directswitch_preferred_language"

    @Published var language: DirectSwitchLanguage {
        didSet {
            UserDefaults.standard.set(language.rawValue, forKey: Self.storageKey)
        }
    }

    var effectiveCode: String { language.effectiveIsoCode }

    private init() {
        let raw = UserDefaults.standard.string(forKey: Self.storageKey) ?? DirectSwitchLanguage.system.rawValue
        self.language = DirectSwitchLanguage(rawValue: raw) ?? .system
    }

    func text(_ key: String, fallbackItalian: String) -> String {
        Self.translate(key, languageCode: language.effectiveIsoCode, fallbackItalian: fallbackItalian)
    }

    func tr(_ italian: String) -> String {
        Self.translatePhrase(italian, languageCode: language.effectiveIsoCode)
    }

    func tr(_ italian: String, en: String, fr: String) -> String {
        switch language.effectiveIsoCode {
        case "en": return en
        case "fr": return fr
        default: return italian
        }
    }

    func translateEta(_ rawEta: String?) -> String? {
        Self.translateEta(rawEta, languageCode: language.effectiveIsoCode)
    }

    nonisolated static func translateEta(_ rawEta: String?, languageCode code: String) -> String? {
        guard let rawEta, !rawEta.isEmpty else { return nil }
        guard code != "it" else { return rawEta }
        if rawEta.hasPrefix("Calcolo tempo") {
            return code == "en" ? "Calculating remaining time…" : "Calcul du temps restant…"
        }
        if rawEta.hasPrefix("Meno di un minuto") {
            return code == "en" ? "Less than 1 minute remaining" : "Moins d'une minute restante"
        }
        if rawEta.hasPrefix("Circa "), let range = rawEta.range(of: " min") {
            let numStr = String(rawEta[rawEta.index(rawEta.startIndex, offsetBy: 6)..<range.lowerBound])
            return code == "en" ? "About \(numStr) min left" : "Environ \(numStr) min restantes"
        }
        return rawEta
    }

    nonisolated static func translate(_ key: String, languageCode: String, fallbackItalian: String) -> String {
        guard languageCode == "en" || languageCode == "fr" else { return fallbackItalian }
        let table: [String: [String: String]] = [
            "home_subtitle": [
                "en": "Direct phone-to-phone transfer without resetting",
                "fr": "Transfert direct de téléphone à téléphone sans réinitialiser"
            ],
            "home_receive_title": [
                "en": "This is the new phone",
                "fr": "Ceci est le nouveau téléphone"
            ],
            "home_send_title": [
                "en": "This is the old phone",
                "fr": "Ceci est l'ancien téléphone"
            ],
            "nav_receive": ["en": "Receive data", "fr": "Recevoir"],
            "nav_connected": ["en": "Connected", "fr": "Connecté"],
            "nav_connect": ["en": "Send", "fr": "Envoyer"],
            "nav_select": ["en": "What to copy", "fr": "Quoi copier"],
            "nav_preparing": ["en": "Preparing", "fr": "Préparation"],
            "nav_copying": ["en": "Copying data", "fr": "Copie en cours"],
            "nav_done": ["en": "Completed", "fr": "Terminé"],
            "nav_apps_ready": ["en": "Apps ready", "fr": "Apps prêtes"],
            "btn_finish": ["en": "Done", "fr": "Terminé"],
            "checklist_title": [
                "en": "Post-migration checklist",
                "fr": "Liste de vérification finale"
            ]
        ]
        return table[key]?[languageCode] ?? fallbackItalian
    }

    nonisolated static func translatePhrase(_ italian: String, languageCode: String) -> String {
        guard languageCode == "en" || languageCode == "fr" else { return italian }
        guard let pair = DirectSwitchPhraseTable.dictionary[italian] else { return italian }
        return languageCode == "en" ? pair.en : pair.fr
    }
}

private enum DirectSwitchPhraseTable {
    static let dictionary: [String: (en: String, fr: String)] = [
        // Navigazione & Pulsanti comuni
        "Indietro": ("Back", "Retour"),
        "Chiudi": ("Close", "Fermer"),
        "Annulla": ("Cancel", "Annuler"),
        "Fine": ("Done", "Terminé"),
        "Torna alla Home": ("Back to Home", "Retour à l'accueil"),
        "Torna alla scelta delle voci": ("Back to item selection", "Retour au choix des éléments"),
        "Continua": ("Continue", "Continuer"),
        "Conferma e collega": ("Confirm & connect", "Confirmer et connecter"),
        "Collegamento in corso...": ("Connecting...", "Connexion en cours..."),
        "Avvio in corso...": ("Starting...", "Démarrage..."),
        "Cambia": ("Change", "Changer"),
        "Ricarica": ("Reload", "Recharger"),
        "Aggiorna": ("Refresh", "Actualiser"),
        "Ricontrolla": ("Recheck", "Vérifier"),
        "Aggiungi": ("Add", "Ajouter"),
        "Azzera": ("Reset", "Effacer"),
        "Ignora": ("Dismiss", "Ignorer"),
        "Cerca": ("Search", "Rechercher"),
        "Seleziona": ("Select", "Sélectionner"),
        "Selezionata": ("Selected", "Sélectionnée"),
        "Seleziona tutto": ("Select all", "Tout sélectionner"),
        "Deseleziona tutto": ("Deselect all", "Tout désélectionner"),
        "Riprova copia": ("Retry copy", "Réessayer la copie"),
        "Riprendi ora": ("Resume now", "Reprendre"),
        "Copia solo novità": ("Copy new items only", "Copier les nouveautés"),
        "Svuota elenco": ("Clear list", "Vider la liste"),

        // Home
        "Invia": ("Send", "Envoyer"),
        "Ricevi": ("Receive", "Recevoir"),
        "Copia i tuoi dati senza formattare: trasferisce rubrica, foto con album, video originali, calendari, audio, file e chat WhatsApp direttamente tra due telefoni già configurati, via Wi-Fi P2P o cavo USB-C senza passare dal cloud.": (
            "Copy your data without resetting: transfers contacts, photos with albums, original videos, calendars, audio, files and WhatsApp chats directly between two already set up phones via Wi-Fi P2P or USB-C cable without the cloud.",
            "Copiez vos données sans réinitialiser : transfère contacts, photos avec albums, vidéos originales, calendriers, audio, fichiers et discussions WhatsApp directement entre deux téléphones déjà configurés via Wi-Fi P2P ou câble USB-C sans cloud."
        ),
        "Invia i dati da questo telefono direttamente senza cavo all'altro telefono (iPhone o Android) dove hai aperto 'Ricevi', tutto gratuito e senza formattare.": (
            "Send data directly from this phone to the other phone (iPhone or Android) where you opened 'Receive', completely free and without factory reset.",
            "Envoyez les données depuis ce téléphone directement vers l'autre téléphone (iPhone ou Android) où vous avez ouvert « Recevoir », gratuitement et sans réinitialisation."
        ),
        "Mostra il codice monouso a 6 cifre (come 'Passa a iOS') o il codice QR per ricevere i dati dal tuo altro iPhone o Android senza cancellare nulla.": (
            "Show a one-time 6-digit code (like Move to iOS) or QR code to receive data from your other iPhone or Android without erasing anything.",
            "Affichez un code unique à 6 chiffres (comme Migrer vers iOS) ou un code QR pour recevoir les données depuis votre autre iPhone ou Android sans rien effacer."
        ),

        // Ricevi & Collegamento
        "Codice di ricezione": ("Receive code", "Code de réception"),
        "QR di ricezione": ("Receive QR", "QR de réception"),
        "Come ricevere i dati": ("How to receive data", "Comment recevoir les données"),
        "Codice a 6 cifre": ("6-digit code", "Code à 6 chiffres"),
        "Codice QR": ("QR Code", "Code QR"),
        "In attesa di collegamento...": ("Waiting for connection...", "En attente de connexion..."),
        "Non si avvia il trasferimento? Attiva «Rete locale»": ("Transfer not starting? Enable Local Network", "Le transfert ne démarre pas ? Activez « Réseau local »"),
        "Abilita Foto e Contatti per salvare i dati": ("Enable Photos & Contacts to save data", "Activez Photos et Contacts pour enregistrer"),
        "Apri Impostazioni DirectSwitch": ("Open DirectSwitch Settings", "Ouvrir les réglages DirectSwitch"),
        "Posizioni di destinazione (fuori da DirectSwitch)": ("Destination locations (outside DirectSwitch)", "Emplacements de destination (hors DirectSwitch)"),
        "Salvataggio nelle posizioni originali": ("Save to original locations", "Enregistrer aux emplacements d'origine"),
        "Seleziona posizione (Su iPhone / iCloud)": ("Choose location (On My iPhone / iCloud)", "Choisir un emplacement (Sur mon iPhone / iCloud)"),
        "Aggiungi altra posizione (Su iPhone / iCloud)": ("Add another location (On My iPhone / iCloud)", "Ajouter un autre emplacement (Sur mon iPhone / iCloud)"),
        "Aggiungi altra posizione": ("Add another location", "Ajouter un autre emplacement"),
        "Posizione base per nuove cartelle": ("Default folder for new folders", "Dossier par défaut pour nouveaux dossiers"),
        "Cambia posizione base": ("Change default folder", "Changer le dossier par défaut"),
        "Collegato!": ("Connected!", "Connecté !"),
        "Prosegui sull'altro telefono": ("Continue on the other phone", "Continuez sur l'autre téléphone"),
        "Canale sicuro pronto": ("Secure channel ready", "Canal sécurisé prêt"),
        "In attesa che scegli le voci sull'altro telefono…": ("Waiting for you to choose items on the other phone…", "En attente de votre sélection sur l'autre téléphone…"),
        "Cartella di salvataggio documenti": ("Document destination folder", "Dossier de destination des documents"),

        // Invia - Passo 1
        "Come inviare i dati": ("How to send data", "Comment envoyer les données"),
        "Dispositivi rilevati": ("Detected devices", "Appareils détectés"),
        "Rilevamento automatico": ("Auto-discovery", "Détection automatique"),
        "Ricerca dell'altro telefono...": ("Searching for the other phone...", "Recherche de l'autre téléphone..."),
        "Non trova il telefono? Verifica «Rete locale» in Impostazioni": ("Phone not found? Check Local Network in Settings", "Téléphone introuvable ? Vérifiez « Réseau local » dans Réglages"),
        "Inquadra codice QR": ("Scan QR code", "Scanner le code QR"),
        "Chiudi fotocamera": ("Close camera", "Fermer la caméra"),
        "Oppure inquadra il codice QR": ("Or scan the QR code", "Ou scannez le code QR"),
        "Inserisci codice manuale": ("Enter manual code", "Saisir un code manuel"),
        "Nascondi codice manuale": ("Hide manual code", "Masquer le code manuel"),
        "Incolla il codice completo qui": ("Paste the full code here", "Collez le code complet ici"),

        // Invia - Passo 2 Categorie
        "Passo 2 di 3": ("Step 2 of 3", "Étape 2 sur 3"),
        "Stato collegamento": ("Connection status", "État de la connexion"),
        "Cosa inviare": ("What to send", "Que transférer"),
        "Spunta ogni voce per aprire la configurazione del passaggio al nuovo telefono.": (
            "Select each item to configure what will be copied to the new phone.",
            "Cochez chaque élément pour configurer le transfert vers le nouveau téléphone."
        ),
        "Rubrica contatti": ("Contacts", "Contacts"),
        "Foto, Live Photos e Album": ("Photos, Live Photos & Albums", "Photos, Live Photos et Albums"),
        "Video originali": ("Original Videos", "Vidéos originales"),
        "Calendari": ("Calendars", "Calendriers"),
        "Promemoria": ("Reminders", "Rappels"),
        "Documenti e Posizioni File": ("Documents & File Locations", "Documents et Emplacements"),
        "Audio, Memo Vocali & Note": ("Audio, Voice Memos & Notes", "Audio, Mémos vocaux et Notes"),
        "App scaricate": ("Downloaded Apps", "Apps téléchargées"),
        "Chat WhatsApp": ("WhatsApp Chats", "Discussions WhatsApp"),
        "Gratuito • Codice QR": ("Free • QR Code", "Gratuit • Code QR"),
        "Memo vocali, MP3, Note": ("Voice memos, MP3, Notes", "Mémos vocaux, MP3, Notes"),
        "Triage Batteria Critica": ("Critical Battery Triage", "Mode Batterie Critique"),
        "Salva prima Password, Documenti, Audio e Foto Preferite (auto ≤ 15%).": (
            "Copies Passwords, Documents, Audio & Favorite Photos first (auto ≤ 15%).",
            "Copie d'abord Mots de passe, Documents, Audio et Photos favorites (auto ≤ 15%)."
        ),
        "Recupero Delta attivo": ("Delta Catch-Up active", "Récupération Delta active"),
        "Copia le voci selezionate": ("Copy selected items", "Copier les éléments sélectionnés"),
        "Copia solo le novità (Delta)": ("Copy new items only (Delta)", "Copier uniquement les nouveautés (Delta)"),
        "Vai al passaggio Chat WhatsApp": ("Go to WhatsApp Chat Transfer", "Passer au transfert WhatsApp"),
        "Avvio preparazione...": ("Starting preparation...", "Lancement de la préparation..."),

        // Dropdowns & Filtri
        "Include numeri con etichette, foto profilo, email, indirizzi, compleanni ed eventuale unione duplicati.": (
            "Includes labeled phone numbers, profile photos, emails, addresses, birthdays and smart duplicate merge.",
            "Inclut numéros étiquetés, photos de profil, e-mails, adresses, anniversaires et fusion intelligente des doublons."
        ),
        "Filtri rapidi Foto": ("Quick Photo Filters", "Filtres rapides Photos"),
        "Tutte le foto": ("All photos", "Toutes les photos"),
        "Solo ultimo anno": ("Last year only", "Dernière année"),
        "Includi anche iCloud": ("Include iCloud-only", "Inclure aussi iCloud"),
        "Filtri e Salva-Spazio Video": ("Video Filters & Space Saver", "Filtres Vidéo et Économie d'espace"),
        "Tutti i video": ("All videos", "Toutes les vidéos"),
        "Solo ≤ 500 MB": ("Only ≤ 500 MB", "Seulement ≤ 500 Mo"),
        "Modalità Salva-Spazio HEVC 1080p (-55%)": ("Space-Saver HEVC 1080p (-55%)", "Économie d'espace HEVC 1080p (-55%)"),
        "Ottimizza al volo i video pesanti (> 40 MB) senza toccare gli originali su questo iPhone.": (
            "Optimizes large videos (> 40 MB) on the fly without altering originals on this iPhone.",
            "Optimise les vidéos volumineuses (> 40 Mo) à la volée sans modifier les originaux sur cet iPhone."
        ),
        "Aggiornamento alla data odierna in corso...": ("Refreshing up to today...", "Actualisation jusqu'à aujourd'hui..."),
        "Se spento trasferisce sia storico sia eventi futuri (-10/+10 anni).": (
            "When off, transfers both past history and future events (-10/+10 years).",
            "Si désactivé, transfère l'historique et les événements futurs (-10/+10 ans)."
        ),
        "Se spento trasferisce tutte le liste complete anche con scadenze future.": (
            "When off, transfers all complete lists including future due dates.",
            "Si désactivé, transfère toutes les listes complètes y compris les échéances futures."
        ),
        "Aggiungi e spunta le posizioni": ("Add and check file locations", "Ajouter et cocher les emplacements"),
        "Caricamento posizione e cartelle in corso…": ("Loading location and folders…", "Chargement de l'emplacement et des dossiers…"),
        "Seleziona iCloud Drive, Su iPhone, Chrome o un'altra posizione": (
            "Select iCloud Drive, On My iPhone, Chrome or another location",
            "Sélectionnez iCloud Drive, Sur mon iPhone, Chrome ou un autre emplacement"
        ),
        "Tocca per aggiungere posizione e preparare tutto": ("Tap to add location and prepare files", "Touchez pour ajouter l'emplacement et tout préparer"),
        "Rimuovi posizioni aggiunte": ("Remove added locations", "Supprimer les emplacements ajoutés"),
        "Seleziona Memo Vocali, Audio o Note esportate": ("Select Voice Memos, Audio or exported Notes", "Sélectionner Mémos vocaux, Audio ou Notes"),
        "Supporta .m4a, .mp3, .wav, .aac, .txt, .md e PDF esportati da Memo Vocali o Note.": (
            "Supports .m4a, .mp3, .wav, .aac, .txt, .md and PDF exported from Voice Memos or Notes.",
            "Prend en charge .m4a, .mp3, .wav, .aac, .txt, .md et PDF exportés depuis Dictaphone ou Notes."
        ),
        "Scegli Memo Vocali / Audio / Note": ("Choose Voice Memos / Audio / Notes", "Choisir Mémos vocaux / Audio / Notes"),
        "Aggiungi altri file": ("Add more files", "Ajouter d'autres fichiers"),
        "Trasferisci Password (Safari / Chrome CSV)": ("Transfer Passwords (Safari / Chrome CSV)", "Transférer Mots de passe (CSV Safari / Chrome)"),
        "Esporta le password in .csv da Password/Safari o Chrome, selezionalo qui: il file temporaneo viene cifrato in transito e sovrascritto a zeri a fine copia.": (
            "Export passwords as .csv from Passwords/Safari or Chrome, select it here: encrypted in transit and securely zero-wiped after transfer.",
            "Exportez les mots de passe en .csv depuis Mots de passe/Safari ou Chrome : chiffré en transit et effacé par écrasement à la fin."
        ),
        "Seleziona file .csv Password": ("Select Password .csv file", "Sélectionner le fichier .csv Mots de passe"),
        "Aggiungi un altro file CSV Password": ("Add another Password CSV file", "Ajouter un autre CSV Mots de passe"),
        "Categorie estese stile iPhone": ("Extended iPhone-style categories", "Catégories étendues style iPhone"),
        "Cerca altre app su App Store": ("Search more apps on App Store", "Rechercher d'autres apps sur l'App Store"),
        "Ripristina solo rilevate": ("Reset to detected only", "Réinitialiser aux détectées"),
        "Rileva altre app anche da Album e Metadati Foto": ("Detect more apps from Photo Albums & Metadata", "Détecter plus d'apps depuis les albums photo"),
        "Passaggio guidato gratuito tramite Codice QR": ("Free guided transfer via QR Code", "Transfert guidé gratuit par Code QR"),

        // Preparazione & Trasferimento
        "Sto preparando la ricezione…": ("Preparing to receive…", "Préparation de la réception…"),
        "Sto preparando il trasferimento…": ("Preparing transfer…", "Préparation du transfert…"),
        "Preparazione spazio di archiviazione e verifica elementi in arrivo...": (
            "Preparing storage and checking incoming items...",
            "Préparation du stockage et vérification des éléments entrants..."
        ),
        "Preparazione rapida e conteggio delle voci selezionate prima di partire dallo 0%.": (
            "Quick preparation and counting selected items before starting from 0%.",
            "Préparation rapide et comptage des éléments sélectionnés avant de démarrer à 0 %."
        ),
        "Tra pochi istanti inizierà la copia sincronizzata dallo 0%.": (
            "Synchronized copy from 0% will start in a moment.",
            "La copie synchronisée à partir de 0 % va démarrer dans un instant."
        ),
        "Trasferimento completato": ("Transfer completed", "Transfert terminé"),
        "Le voci selezionate sono pronte su questo iPhone": ("Selected items are ready on this iPhone", "Les éléments sélectionnés sont prêts sur cet iPhone"),
        "Copia su questo iPhone...": ("Copying to this iPhone...", "Copie sur cet iPhone..."),
        "Copia delle voci selezionate...": ("Copying selected items...", "Copie des éléments sélectionnés..."),
        "Tieni entrambi i telefoni vicini fino al termine": ("Keep both phones nearby until finished", "Gardez les deux téléphones à proximité jusqu'à la fin"),
        "I file già copiati sono al sicuro e non verranno duplicati": ("Already copied files are safe and won't be duplicated", "Les fichiers déjà copiés sont en sécurité et ne seront pas dupliqués"),
        "Foto trasferite": ("Photos transferred", "Photos transférées"),
        "Video trasferiti": ("Videos transferred", "Vidéos transférées"),
        "Documenti e File": ("Documents & Files", "Documents et Fichiers"),
        "Foto e Video": ("Photos & Videos", "Photos et Vidéos"),
        "Foto, Video e File": ("Photos, Videos & Files", "Photos, Vidéos et Fichiers"),
        "Live Photos animate": ("Animated Live Photos", "Live Photos animées"),
        "Calendari importati": ("Calendars imported", "Calendriers importés"),
        "Promemoria importati": ("Reminders imported", "Rappels importés"),
        "Messaggi salvati": ("Messages saved", "Messages enregistrés"),
        "Cronologia chiamate salvata": ("Call history saved", "Historique d'appels enregistré"),
        "Elenco App ricevute": ("Received Apps list", "Liste des apps reçues"),
        "App inviate al nuovo telefono": ("Apps sent to new phone", "Apps envoyées au nouveau téléphone"),
        "Doppioni già presenti ignorati": ("Existing duplicates skipped", "Doublons déjà présents ignorés"),
        "Elementi non scaricabili da iCloud / illeggibili": ("Unavailable / unreadable items", "Éléments indisponibles / illisibles"),
        "Trasferisci un'altra voce a questo telefono": ("Transfer another item to this phone", "Transférer un autre élément vers ce téléphone"),
        "Riprendi trasferimento da dove era rimasto": ("Resume transfer where it left off", "Reprendre le transfert là où il s'est arrêté"),
        "Ricollega con nuovo codice / QR (salta già copiati)": ("Reconnect with new code / QR (skips copied)", "Reconnecter avec nouveau code / QR (ignore déjà copiés)"),

        // Next-level cards (Salva-Spazio, Audit, Checklist, CloudSave, Canali)
        "Cavo USB-C diretto": ("Direct USB-C Cable", "Câble USB-C direct"),
        "Wi-Fi Diretto P2P (AWDL)": ("Direct P2P Wi-Fi (AWDL)", "Wi-Fi Direct P2P (AWDL)"),
        "Wi-Fi Locale": ("Local Wi-Fi", "Wi-Fi Local"),
        "Assistente Salva-Spazio": ("Space Saver Assistant", "Assistant Gain d'espace"),
        "Scegli una soluzione rapida con 1 tocco per ripartire subito:": ("Pick a 1-tap quick fix to resume immediately:", "Choisissez une solution rapide en 1 geste pour repartir :"),
        "Rientra ✓": ("Fits ✓", "Compatible ✓"),
        "Tocca per vedere i dettagli e riprovare solo i mancanti": ("Tap to view details and retry missing items only", "Touchez pour voir les détails et réessayer les manquants"),
        "Checklist finale prima di chiudere": ("Final checklist before finishing", "Liste finale avant de fermer"),
        "Condividi ricevuta migrazione": ("Share migration receipt", "Partager le reçu de migration"),
        "Audit Anti-Lockout & Reset": ("Anti-Lockout & Reset Audit", "Audit Anti-Verrouillage & Reset"),
        "NON FORMATTARE ANCORA": ("DO NOT RESET YET", "NE PAS RÉINITIALISER"),
        "VERIFICA ELEMENTI SECONDARI": ("CHECK SECONDARY ITEMS", "VÉRIFIER LES ÉLÉMENTS SECONDAIRES"),
        "PRONTO PER RESET / PERMUTA ✓": ("READY FOR RESET / TRADE-IN ✓", "PRÊT POUR RESET / REPRISE ✓"),
        "Condividi Certificato Pronto per Reset": ("Share Ready-for-Reset Certificate", "Partager le certificat Prêt pour Reset"),
        "Ponte Overflow verso CloudSave": ("CloudSave Overflow Bridge", "Pont Overflow vers CloudSave"),
        "Controllo posizioni sul telefono": ("Phone locations check", "Vérification des emplacements"),
        "Seleziona posizione": ("Select location", "Sélectionner un emplacement"),
        "Continua comunque": ("Continue anyway", "Continuer quand même"),
        "Invia escludendo Documenti": ("Send without Documents", "Envoyer sans Documents")
    ]
}

@MainActor
func dsTr(_ italian: String) -> String {
    DirectSwitchLocalizationStore.shared.tr(italian)
}

@MainActor
func dsTr(_ italian: String, en: String, fr: String) -> String {
    DirectSwitchLocalizationStore.shared.tr(italian, en: en, fr: fr)
}

/// Elementi della checklist guidata post-migrazione ("Non dimenticare nulla prima di formattare il vecchio telefono").
struct PostMigrationChecklistItem: Identifiable, Equatable, Sendable {
    let id: String
    let icon: String
    let title: String
    let subtitle: String
}

enum MigrationReceiptBuilder {
    static func defaultChecklist(
        hasWhatsApp: Bool,
        hasApps: Bool,
        hasSkipped: Bool,
        languageCode: String = "it"
    ) -> [PostMigrationChecklistItem] {
        let isEn = languageCode == "en"
        let isFr = languageCode == "fr"
        func pick(_ it: String, _ en: String, _ fr: String) -> String {
            isEn ? en : (isFr ? fr : it)
        }
        var items: [PostMigrationChecklistItem] = [
            PostMigrationChecklistItem(
                id: "verify_media_contacts",
                icon: "checkmark.seal.fill",
                title: pick(
                    "Verifica Rubrica, Foto e Video sul nuovo telefono",
                    "Verify Contacts, Photos & Videos on the new phone",
                    "Vérifiez Contacts, Photos et Vidéos sur le nouveau téléphone"
                ),
                subtitle: pick(
                    "Apri Contatti e Foto prima di formattare o vendere il vecchio telefono.",
                    "Open Contacts and Photos before resetting or selling your old phone.",
                    "Ouvrez Contacts et Photos avant de réinitialiser ou vendre l'ancien téléphone."
                )
            ),
            PostMigrationChecklistItem(
                id: "banking_spid_2fa",
                icon: "lock.shield.fill",
                title: pick(
                    "Attiva App Bancarie, SPID e Authenticator",
                    "Activate Banking Apps, Digital ID & Authenticator",
                    "Activez les apps bancaires, l'identité numérique et Authenticator"
                ),
                subtitle: pick(
                    "Trasferisci i codici 2FA/OTP finché hai ancora accesso al vecchio dispositivo.",
                    "Transfer 2FA/OTP codes while you still have access to the old device.",
                    "Transférez vos codes 2FA/OTP tant que vous avez accès à l'ancien appareil."
                )
            ),
            PostMigrationChecklistItem(
                id: "mail_accounts",
                icon: "envelope.fill",
                title: pick(
                    "Collega gli account Mail / Google / iCloud",
                    "Sign in to Mail / Google / iCloud accounts",
                    "Connectez vos comptes Mail / Google / iCloud"
                ),
                subtitle: pick(
                    "Accedi alle caselle email nelle Impostazioni del nuovo telefono.",
                    "Sign in to your email accounts in the new phone's Settings.",
                    "Connectez vos boîtes e-mail dans les Réglages du nouveau téléphone."
                )
            )
        ]
        if hasApps {
            items.append(
                PostMigrationChecklistItem(
                    id: "apps_download",
                    icon: "arrow.down.app.fill",
                    title: pick(
                        "Completa il download delle app selezionate",
                        "Finish downloading selected apps",
                        "Terminez le téléchargement des apps sélectionnées"
                    ),
                    subtitle: pick(
                        "Controlla che tutte le app principali siano state installate dallo Store.",
                        "Make sure all your essential apps have been installed from the Store.",
                        "Vérifiez que toutes vos apps principales sont installées depuis le Store."
                    )
                )
            )
        }
        if hasWhatsApp {
            items.append(
                PostMigrationChecklistItem(
                    id: "whatsapp_qr",
                    icon: "bubble.left.and.bubble.right.fill",
                    title: pick(
                        "Trasferisci le chat WhatsApp via Codice QR",
                        "Transfer WhatsApp chats via QR Code",
                        "Transférez les discussions WhatsApp via Code QR"
                    ),
                    subtitle: pick(
                        "Assicurati che la cronologia chat sia visibile sul nuovo telefono.",
                        "Make sure your chat history appears on the new phone.",
                        "Assurez-vous que l'historique des discussions s'affiche sur le nouveau téléphone."
                    )
                )
            )
        }
        if hasSkipped {
            items.append(
                PostMigrationChecklistItem(
                    id: "skipped_review",
                    icon: "exclamationmark.triangle.fill",
                    title: pick(
                        "Controlla gli elementi saltati",
                        "Review skipped items",
                        "Vérifiez les éléments ignorés"
                    ),
                    subtitle: pick(
                        "Usa «Riprova solo i mancanti» per recuperare eventuali file iCloud.",
                        "Use 'Retry missing only' to recover any skipped files.",
                        "Utilisez « Réessayer les manquants » pour récupérer les fichiers ignorés."
                    )
                )
            )
        }
        return items
    }

    static func buildReceiptText(
        peerName: String,
        isReceiver: Bool,
        connectionMedium: TransferConnectionMedium,
        completedFiles: Int,
        totalBytes: Int64,
        mergedContacts: Int,
        importedCalendars: Int,
        importedReminders: Int,
        importedSms: Int,
        importedCallLogs: Int,
        appsCount: Int,
        skippedCount: Int,
        languageCode: String = "it"
    ) -> String {
        let isEn = languageCode == "en"
        let isFr = languageCode == "fr"
        let df = DateFormatter()
        df.locale = Locale(identifier: isEn ? "en_US" : (isFr ? "fr_FR" : "it_IT"))
        df.dateStyle = .medium
        df.timeStyle = .short
        let peer = peerName.isEmpty ? (isEn ? "Connected device" : (isFr ? "Appareil connecté" : "Dispositivo collegato")) : peerName
        if isEn {
            let role = isReceiver ? "Received from" : "Sent to"
            return """
            DirectSwitch — Migration Receipt
            Date: \(df.string(from: Date()))
            \(role): \(peer)
            Connection: \(DirectSwitchLocalizationStore.translatePhrase(connectionMedium.badgeLabel, languageCode: "en"))
            ----------------------------------------
            Files transferred: \(completedFiles) (\(TransferDisplayFormatting.formatBytes(totalBytes)))
            Contacts merged: \(mergedContacts)
            Calendars imported: \(importedCalendars)
            Reminders imported: \(importedReminders)
            SMS saved: \(importedSms)
            Call logs saved: \(importedCallLogs)
            Apps in list: \(appsCount)
            Skipped items: \(skippedCount)
            ----------------------------------------
            Local AES-256-GCM encrypted transfer completed without cloud.
            """
        }
        if isFr {
            let role = isReceiver ? "Reçu de" : "Envoyé vers"
            return """
            DirectSwitch — Reçu de Migration
            Date : \(df.string(from: Date()))
            \(role) : \(peer)
            Connexion : \(DirectSwitchLocalizationStore.translatePhrase(connectionMedium.badgeLabel, languageCode: "fr"))
            ----------------------------------------
            Fichiers transférés : \(completedFiles) (\(TransferDisplayFormatting.formatBytes(totalBytes)))
            Contacts fusionnés : \(mergedContacts)
            Calendriers importés : \(importedCalendars)
            Rappels importés : \(importedReminders)
            SMS enregistrés : \(importedSms)
            Appels enregistrés : \(importedCallLogs)
            Apps dans la liste : \(appsCount)
            Éléments ignorés : \(skippedCount)
            ----------------------------------------
            Transfert local chiffré AES-256-GCM terminé sans cloud.
            """
        }
        let role = isReceiver ? "Ricevuto da" : "Inviato a"
        return """
        DirectSwitch — Ricevuta di Migrazione
        Data: \(df.string(from: Date()))
        \(role): \(peer)
        Connessione: \(connectionMedium.badgeLabel)
        ----------------------------------------
        File trasferiti: \(completedFiles) (\(TransferDisplayFormatting.formatBytes(totalBytes)))
        Contatti uniti: \(mergedContacts)
        Calendari importati: \(importedCalendars)
        Promemoria importati: \(importedReminders)
        SMS salvati: \(importedSms)
        Chiamate salvate: \(importedCallLogs)
        App in elenco: \(appsCount)
        Elementi saltati: \(skippedCount)
        ----------------------------------------
        Trasferimento locale cifrato AES-256-GCM completato senza cloud.
        """
    }
}
