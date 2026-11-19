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

    var isDefault: Bool {
        !photosLastYearOnly && selectedPhotoAlbums.isEmpty && !videosLastYearOnly && maxVideoBytes == 0 && !compactVideo1080pHevc
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

/// Lingue supportate in DirectSwitch (`Sistema` + IT / EN / ES / FR / DE).
enum DirectSwitchLanguage: String, CaseIterable, Identifiable, Codable, Sendable {
    case system = "sys"
    case italian = "it"
    case english = "en"
    case spanish = "es"
    case french = "fr"
    case german = "de"

    var id: String { rawValue }

    var shortCode: String {
        switch self {
        case .system: return "AUTO"
        case .italian: return "IT"
        case .english: return "EN"
        case .spanish: return "ES"
        case .french: return "FR"
        case .german: return "DE"
        }
    }

    var displayName: String {
        switch self {
        case .system: return "Sistema"
        case .italian: return "Italiano"
        case .english: return "English"
        case .spanish: return "Español"
        case .french: return "Français"
        case .german: return "Deutsch"
        }
    }

    var effectiveIsoCode: String {
        if self != .system { return rawValue }
        let code = Locale.preferredLanguages.first?.prefix(2).lowercased() ?? "it"
        if ["it", "en", "es", "fr", "de"].contains(code) { return code }
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

    private init() {
        let raw = UserDefaults.standard.string(forKey: Self.storageKey) ?? DirectSwitchLanguage.system.rawValue
        self.language = DirectSwitchLanguage(rawValue: raw) ?? .system
    }

    func text(_ key: String, fallbackItalian: String) -> String {
        Self.translate(key, languageCode: language.effectiveIsoCode, fallbackItalian: fallbackItalian)
    }

    nonisolated static func translate(_ key: String, languageCode: String, fallbackItalian: String) -> String {
        guard languageCode != "it" else { return fallbackItalian }
        let table: [String: [String: String]] = [
            "home_subtitle": [
                "en": "Direct phone-to-phone transfer without resetting",
                "es": "Transferencia directa entre teléfonos sin formatear",
                "fr": "Transfert direct de téléphone à téléphone sans réinitialiser",
                "de": "Direkte Übertragung von Handy zu Handy ohne Zurücksetzen"
            ],
            "home_receive_title": [
                "en": "This is the new phone",
                "es": "Este es el teléfono nuevo",
                "fr": "Ceci est le nouveau téléphone",
                "de": "Dies ist das neue Handy"
            ],
            "home_send_title": [
                "en": "This is the old phone",
                "es": "Este es el teléfono antiguo",
                "fr": "Ceci est l'ancien téléphone",
                "de": "Dies ist das alte Handy"
            ],
            "nav_receive": ["en": "Receive data", "es": "Recibir datos", "fr": "Recevoir", "de": "Empfangen"],
            "nav_connect": ["en": "Connect phone", "es": "Conectar teléfono", "fr": "Connecter", "de": "Verbinden"],
            "nav_select": ["en": "What to copy", "es": "Qué copiar", "fr": "Quoi copier", "de": "Was kopieren"],
            "nav_preparing": ["en": "Preparing", "es": "Preparando", "fr": "Préparation", "de": "Vorbereitung"],
            "nav_copying": ["en": "Copying data", "es": "Copiando datos", "fr": "Copie en cours", "de": "Übertragung"],
            "nav_done": ["en": "Completed", "es": "Completado", "fr": "Terminé", "de": "Abgeschlossen"],
            "btn_finish": ["en": "Done", "es": "Listo", "fr": "Terminé", "de": "Fertig"],
            "checklist_title": [
                "en": "Post-migration checklist",
                "es": "Lista de verificación final",
                "fr": "Liste de vérification finale",
                "de": "Checkliste nach der Übertragung"
            ]
        ]
        return table[key]?[languageCode] ?? fallbackItalian
    }
}

/// Elementi della checklist guidata post-migrazione ("Non dimenticare nulla prima di formattare il vecchio telefono").
struct PostMigrationChecklistItem: Identifiable, Equatable, Sendable {
    let id: String
    let icon: String
    let title: String
    let subtitle: String
}

enum MigrationReceiptBuilder {
    static func defaultChecklist(hasWhatsApp: Bool, hasApps: Bool, hasSkipped: Bool) -> [PostMigrationChecklistItem] {
        var items: [PostMigrationChecklistItem] = [
            PostMigrationChecklistItem(
                id: "verify_media_contacts",
                icon: "checkmark.seal.fill",
                title: "Verifica Rubrica, Foto e Video sul nuovo telefono",
                subtitle: "Apri Contatti e Foto prima di formattare o vendere il vecchio telefono."
            ),
            PostMigrationChecklistItem(
                id: "banking_spid_2fa",
                icon: "lock.shield.fill",
                title: "Attiva App Bancarie, SPID e Authenticator",
                subtitle: "Trasferisci i codici 2FA/OTP finché hai ancora accesso al vecchio dispositivo."
            ),
            PostMigrationChecklistItem(
                id: "mail_accounts",
                icon: "envelope.fill",
                title: "Collega gli account Mail / Google / iCloud",
                subtitle: "Accedi alle caselle email nelle Impostazioni del nuovo telefono."
            )
        ]
        if hasApps {
            items.append(
                PostMigrationChecklistItem(
                    id: "apps_download",
                    icon: "arrow.down.app.fill",
                    title: "Completa il download delle app selezionate",
                    subtitle: "Controlla che tutte le app principali siano state installate dallo Store."
                )
            )
        }
        if hasWhatsApp {
            items.append(
                PostMigrationChecklistItem(
                    id: "whatsapp_qr",
                    icon: "bubble.left.and.bubble.right.fill",
                    title: "Trasferisci le chat WhatsApp via Codice QR",
                    subtitle: "Assicurati che la cronologia chat sia visibile sul nuovo telefono."
                )
            )
        }
        if hasSkipped {
            items.append(
                PostMigrationChecklistItem(
                    id: "skipped_review",
                    icon: "exclamationmark.triangle.fill",
                    title: "Controlla gli elementi saltati",
                    subtitle: "Usa «Riprova solo i mancanti» per recuperare eventuali file iCloud."
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
        skippedCount: Int
    ) -> String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "it_IT")
        df.dateStyle = .medium
        df.timeStyle = .short
        let role = isReceiver ? "Ricevuto da" : "Inviato a"
        return """
        DirectSwitch — Ricevuta di Migrazione
        Data: \(df.string(from: Date()))
        \(role): \(peerName.isEmpty ? "Dispositivo collegato" : peerName)
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
