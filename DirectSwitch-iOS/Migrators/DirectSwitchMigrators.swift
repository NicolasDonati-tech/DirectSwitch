//
//  DirectSwitchMigrators.swift
//  DirectSwitch-iOS
//
//  Created by Nicolas Donati.
//  Copyright © 2026 Nicolas Donati. Tutti i diritti riservati.
//

import Foundation
import Contacts
import Photos
import EventKit
import StoreKit
import UIKit

/// Riepilogo locale dei dati e dello spazio disponibile sull'iPhone (parità con `LocalDeviceScanSummary` Android).
struct iOSLocalDeviceScanSummary: Sendable, Equatable {
    let contactsCount: Int
    let photosCount: Int
    let photosBytes: Int64
    let videosCount: Int
    let videosBytes: Int64
    let calendarEventsCount: Int
    let documentsCount: Int
    let whatsappArchivesCount: Int
    let freeStorageBytes: Int64
    let totalStorageBytes: Int64
    let hasFullPermissions: Bool
}

enum iOSStorageCapacityChecker {
    static func freeStorageBytes() -> Int64 {
        freeAndTotalStorageBytes().free
    }

    static func freeAndTotalStorageBytes() -> (free: Int64, total: Int64) {
        let url = URL(fileURLWithPath: NSHomeDirectory())
        let keys: Set<URLResourceKey> = [
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeAvailableCapacityKey,
            .volumeTotalCapacityKey
        ]
        guard let vals = try? url.resourceValues(forKeys: keys) else {
            return (0, 0)
        }
        let free: Int64
        if let imp = vals.volumeAvailableCapacityForImportantUsage, imp > 0 {
            free = imp
        } else if let std = vals.volumeAvailableCapacity {
            free = Int64(std)
        } else {
            free = 0
        }
        let total = Int64(vals.volumeTotalCapacity ?? 0)
        return (free, total)
    }
}

enum iOSDeviceDataAnalyzer {
    /// Legge subito spazio libero/totale e i conteggi delle sole categorie già autorizzate (nessun popup a freddo).
    static func scanAuthorizedSummary(stagedItems: [ManifestItem] = []) -> iOSLocalDeviceScanSummary {
        let (freeBytes, totalBytes) = iOSStorageCapacityChecker.freeAndTotalStorageBytes()
        let contactsAuth = CNContactStore.authorizationStatus(for: .contacts) == .authorized
        let photoStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        let photosAuth = (photoStatus == .authorized || photoStatus == .limited)
        let calAuth = iOSCalendarMigrator.isAuthorized()

        let contactsCount = contactsAuth ? iOSContactsSmartMerger.readAllContacts().count : 0
        let calendarCount = calAuth ? iOSCalendarMigrator.readEvents().count : 0

        var photosCount = 0
        var photosBytes: Int64 = 0
        var videosCount = 0
        var videosBytes: Int64 = 0

        if photosAuth {
            let fetched = PHAsset.fetchAssets(with: nil)
            fetched.enumerateObjects { asset, _, _ in
                if asset.mediaType == .image {
                    photosCount += 1
                    photosBytes += 2_800_000
                } else if asset.mediaType == .video {
                    videosCount += 1
                    videosBytes += Int64(max(1.0, asset.duration) * 2_200_000.0)
                }
            }
        }

        let docsCount = stagedItems.filter { $0.category == .DOCUMENTS }.count
        let waCount = stagedItems.filter { $0.category == .WHATSAPP_VAULT }.count

        return iOSLocalDeviceScanSummary(
            contactsCount: contactsCount,
            photosCount: photosCount,
            photosBytes: photosBytes,
            videosCount: videosCount,
            videosBytes: videosBytes,
            calendarEventsCount: calendarCount,
            documentsCount: docsCount,
            whatsappArchivesCount: waCount,
            freeStorageBytes: freeBytes,
            totalStorageBytes: totalBytes,
            hasFullPermissions: contactsAuth && photosAuth && calAuth
        )
    }

    /// Richiede i permessi di lettura e restituisce il conteggio esatto dei contenuti sull'iPhone.
    static func requestPermissionsAndScanAll(stagedItems: [ManifestItem] = []) async -> iOSLocalDeviceScanSummary {
        _ = await iOSContactsSmartMerger.requestAccessIfNeeded()
        _ = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        _ = await iOSCalendarMigrator.requestAccessIfNeeded()
        return await Task.detached(priority: .userInitiated) {
            scanAuthorizedSummary(stagedItems: stagedItems)
        }.value
    }
}

enum iOSLicenseStore {
    static let productIdCrossOsPass = "com.directswitch.ios.cross_os_pass"
    private static let key = "directswitch_cross_os_pro_unlocked"

    static var isLocalProUnlocked: Bool {
        get {
            if UserDefaults.standard.object(forKey: key) == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: key)
        }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }

    /// Solo per cross-sell informativo: non sblocca il Pass Pro senza verifica crittografica.
    static var isCloudSaveInstalled: Bool {
        guard let url = URL(string: "com.cloudsave.ios://") else { return false }
        return UIApplication.shared.canOpenURL(url)
    }

    static var hasVerifiedCloudSaveProEntitlement: Bool {
        false
    }

    /// Acquisto nativo StoreKit 2 con sblocco immediato pre-pubblicazione quando lo SKU non è ancora attivo su App Store Connect.
    @MainActor
    static func purchaseCrossOsPass(allowPreLaunchFallback: Bool = true) async -> (Bool, String) {
        let canFallback = allowPreLaunchFallback

        do {
            let products = try await Product.products(for: [productIdCrossOsPass])
            if let product = products.first {
                let result = try await product.purchase()
                switch result {
                case .success(let verification):
                    if case .verified(let transaction) = verification {
                        await transaction.finish()
                        isLocalProUnlocked = true
                        return (true, "Premium Direct verificato e attivato!")
                    }
                    return (false, "Verifica crittografica ricevuta App Store non riuscita.")
                case .userCancelled:
                    return (false, "Acquisto annullato dall'utente.")
                case .pending:
                    return (false, "Acquisto in attesa di approvazione.")
                @unknown default:
                    return (false, "Stato acquisto sconosciuto.")
                }
            } else if canFallback {
                isLocalProUnlocked = true
                return (true, "Premium Direct attivato (Modalità Pre-Lancio / Test)!")
            } else {
                return (false, "Prodotto non ancora disponibile su App Store.")
            }
        } catch {
            if canFallback {
                isLocalProUnlocked = true
                return (true, "Premium Direct attivato (Modalità Pre-Lancio / Test)!")
            }
            return (false, "Errore StoreKit: \(error.localizedDescription)")
        }
    }

    @MainActor
    static func restoreStoreKitEntitlements() async -> Bool {
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result,
               transaction.productID == productIdCrossOsPass,
               transaction.revocationDate == nil {
                isLocalProUnlocked = true
                return true
            }
        }
        return isLocalProUnlocked
    }
}

/// Smart Merger Rubrica iOS (`CNContactStore`): unisce i contatti in entrata evitando qualsiasi duplicato.
enum iOSContactsSmartMerger {
    static func requestAccessIfNeeded() async -> Bool {
        let store = CNContactStore()
        return (try? await store.requestAccess(for: .contacts)) ?? false
    }

    static func readAllContacts() -> [ContactTransferRecord] {
        let store = CNContactStore()
        guard CNContactStore.authorizationStatus(for: .contacts) == .authorized else { return [] }
        let keys: [CNKeyDescriptor] = [
            CNContactIdentifierKey as CNKeyDescriptor,
            CNContactGivenNameKey as CNKeyDescriptor,
            CNContactFamilyNameKey as CNKeyDescriptor,
            CNContactOrganizationNameKey as CNKeyDescriptor,
            CNContactPhoneNumbersKey as CNKeyDescriptor,
            CNContactEmailAddressesKey as CNKeyDescriptor
        ]
        let req = CNContactFetchRequest(keysToFetch: keys)
        var out: [ContactTransferRecord] = []
        try? store.enumerateContacts(with: req) { contact, _ in
            let name = [contact.givenName, contact.familyName]
                .filter { !$0.isEmpty }
                .joined(separator: " ")
                .trimmingCharacters(in: .whitespaces)
            let orgTrimmed = contact.organizationName.trimmingCharacters(in: .whitespaces)
            let phones = contact.phoneNumbers.map { $0.value.stringValue }.filter { !$0.isEmpty }
            let emails = contact.emailAddresses.map { String($0.value) }.filter { !$0.isEmpty }
            let fallbackLabel = !orgTrimmed.isEmpty ? orgTrimmed : (phones.first ?? emails.first ?? "")
            let effectiveName = name.isEmpty ? fallbackLabel : name

            if !effectiveName.isEmpty && (!phones.isEmpty || !emails.isEmpty) {
                out.append(
                    ContactTransferRecord(
                        id: contact.identifier,
                        displayName: effectiveName,
                        phones: phones,
                        emails: emails,
                        organization: orgTrimmed.isEmpty ? nil : orgTrimmed
                    )
                )
            }
        }
        return out
    }

    static func mergeIncomingContacts(_ incoming: [ContactTransferRecord]) -> (inserted: Int, skipped: Int) {
        guard CNContactStore.authorizationStatus(for: .contacts) == .authorized,
              !incoming.isEmpty else { return (0, 0) }
        let store = CNContactStore()
        let existing = readAllContacts()
        var existingPhones = Set(existing.flatMap { $0.phones }.map { PhoneNormalizer.normalizeKey($0) }.filter { !$0.isEmpty })
        var existingEmails = Set(existing.flatMap { $0.emails }.map { $0.lowercased() })

        var inserted = 0
        var skipped = 0
        let saveReq = CNSaveRequest()

        for record in incoming {
            let normPhones = record.phones.map { PhoneNormalizer.normalizeKey($0) }.filter { !$0.isEmpty }
            let normEmails = record.emails.map { $0.lowercased() }
            if normPhones.contains(where: { existingPhones.contains($0) }) ||
                normEmails.contains(where: { existingEmails.contains($0) }) {
                skipped += 1
                continue
            }

            let mutable = CNMutableContact()
            let parts = record.displayName.split(separator: " ", maxSplits: 1).map(String.init)
            mutable.givenName = parts.first ?? record.displayName
            if parts.count > 1 { mutable.familyName = parts[1] }
            if let org = record.organization, !org.isEmpty {
                mutable.organizationName = org
            }
            mutable.phoneNumbers = record.phones.map {
                CNLabeledValue(label: CNLabelPhoneNumberMobile, value: CNPhoneNumber(stringValue: $0))
            }
            mutable.emailAddresses = record.emails.map {
                CNLabeledValue(label: CNLabelOther, value: $0 as NSString)
            }
            saveReq.add(mutable, toContainerWithIdentifier: nil)
            inserted += 1
            normPhones.forEach { existingPhones.insert($0) }
            normEmails.forEach { existingEmails.insert($0) }
        }

        if inserted > 0 {
            do {
                try store.execute(saveReq)
            } catch {
                return (0, skipped)
            }
        }
        return (inserted, skipped)
    }

    /// Genera un pacchetto `.vcf` RFC 2426 per il Portale Web di Bootstrap rapido.
    static func exportVCardBundle() -> String {
        let contacts = readAllContacts()
        var out = ""
        out.reserveCapacity(contacts.count * 128)
        for c in contacts {
            let safeName = c.displayName
                .replacingOccurrences(of: "\r", with: " ")
                .replacingOccurrences(of: "\n", with: " ")
            out += "BEGIN:VCARD\r\nVERSION:3.0\r\n"
            out += "FN:\(safeName)\r\n"
            out += "N:\(safeName);;;;\r\n"
            for phone in c.phones {
                out += "TEL;TYPE=CELL:\(phone.trimmingCharacters(in: .whitespacesAndNewlines))\r\n"
            }
            for email in c.emails {
                out += "EMAIL;TYPE=INTERNET:\(email.trimmingCharacters(in: .whitespacesAndNewlines))\r\n"
            }
            out += "END:VCARD\r\n"
        }
        return out
    }
}

/// Importatore ed esportatore nativo Rullino iOS (`PhotoKit`) con streaming su disco anti-OOM per video 4K,
/// deduplicazione automatica, preservazione reale degli Album utente e MIME type accurati (HEIC/MOV/MP4/PNG).
enum iOSPhotoKitMigrator {
    static func mimeTypeForFileName(_ fileName: String, isVideo: Bool) -> String {
        let ext = URL(fileURLWithPath: fileName).pathExtension.lowercased()
        switch ext {
        case "heic": return "image/heic"
        case "heif": return "image/heif"
        case "jpg", "jpeg": return "image/jpeg"
        case "png": return "image/png"
        case "webp": return "image/webp"
        case "gif": return "image/gif"
        case "dng": return "image/x-adobe-dng"
        case "mp4", "m4v": return "video/mp4"
        case "mov": return "video/quicktime"
        case "3gp": return "video/3gpp"
        default: return isVideo ? "video/quicktime" : "image/jpeg"
        }
    }

    /// Seleziona sempre la risorsa principale a piena risoluzione evitando plist `.adjustmentData` su foto modificate.
    static func primaryMediaResource(for asset: PHAsset) -> PHAssetResource? {
        let resources = PHAssetResource.assetResources(for: asset)
        if asset.mediaType == .video {
            return resources.first(where: { $0.type == .fullSizeVideo })
                ?? resources.first(where: { $0.type == .video })
                ?? resources.first
        } else {
            return resources.first(where: { $0.type == .fullSizePhoto })
                ?? resources.first(where: { $0.type == .photo })
                ?? resources.first
        }
    }

    private static func buildAssetAlbumMap() -> [String: String] {
        var map: [String: String] = [:]
        let collections = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .albumRegular, options: nil)
        collections.enumerateObjects { collection, _, _ in
            let title = (collection.localizedTitle ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { return }
            let assets = PHAsset.fetchAssets(in: collection, options: nil)
            assets.enumerateObjects { asset, _, _ in
                if map[asset.localIdentifier] == nil {
                    map[asset.localIdentifier] = title
                }
            }
        }
        return map
    }

    static func saveMediaFileToLibrary(item: ManifestItem, fileURL: URL) async -> Bool {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        guard status == .authorized || status == .limited else { return false }

        let safeName = URL(fileURLWithPath: item.fileName).lastPathComponent
        let fallbackExt = item.category == .VIDEOS ? "mp4" : "jpg"
        let finalName = safeName.isEmpty ? "media_\(UUID().uuidString).\(fallbackExt)" : safeName
        let importURL: URL
        var cleanupImportURL = false

        if fileURL.lastPathComponent == finalName {
            importURL = fileURL
        } else {
            let renamedURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("\(UUID().uuidString)_\(finalName)")
            try? FileManager.default.removeItem(at: renamedURL)
            if (try? FileManager.default.linkItem(at: fileURL, to: renamedURL)) != nil ||
                (try? FileManager.default.copyItem(at: fileURL, to: renamedURL)) != nil {
                importURL = renamedURL
                cleanupImportURL = true
            } else {
                importURL = fileURL
            }
        }
        defer {
            if cleanupImportURL {
                try? FileManager.default.removeItem(at: importURL)
            }
        }

        do {
            let albumTitle = item.relativeAlbumOrFolder.trimmingCharacters(in: .whitespacesAndNewlines)
            let targetAlbum = (albumTitle.isEmpty || albumTitle == "iPhone_Camera")
                ? nil
                : fetchOrCreateAlbum(named: albumTitle)

            try await PHPhotoLibrary.shared().performChanges {
                let req = PHAssetCreationRequest.forAsset()
                if item.category == .VIDEOS {
                    req.addResource(with: .video, fileURL: importURL, options: nil)
                } else {
                    req.addResource(with: .photo, fileURL: importURL, options: nil)
                }
                if item.capturedEpochMillis > 0 {
                    req.creationDate = Date(timeIntervalSince1970: TimeInterval(item.capturedEpochMillis) / 1000.0)
                }
                if let album = targetAlbum,
                   let placeholder = req.placeholderForCreatedAsset,
                   let albumChangeReq = PHAssetCollectionChangeRequest(for: album) {
                    albumChangeReq.addAssets([placeholder] as NSArray)
                }
            }
            return true
        } catch {
            return false
        }
    }

    static func saveMediaToLibrary(item: ManifestItem, plainData: Data) async -> Bool {
        let safeName = URL(fileURLWithPath: item.fileName).lastPathComponent
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString)_\(safeName.isEmpty ? "media.bin" : safeName)")
        do {
            try plainData.write(to: tempURL, options: .atomic)
            defer { try? FileManager.default.removeItem(at: tempURL) }
            return await saveMediaFileToLibrary(item: item, fileURL: tempURL)
        } catch {
            return false
        }
    }

    /// Costruisce l'insieme delle chiavi di deduplicazione già presenti nel Rullino iOS.
    static func existingDedupKeys() async -> Set<String> {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        guard status == .authorized || status == .limited else { return [] }
        let fetched = PHAsset.fetchAssets(with: nil)
        var keys = Set<String>()
        fetched.enumerateObjects { asset, _, _ in
            guard let primary = primaryMediaResource(for: asset) else { return }
            let size = (primary.value(forKey: "fileSize") as? Int64) ?? 0
            let createdMs = Int64((asset.creationDate?.timeIntervalSince1970 ?? 0) * 1000.0)
            let name = primary.originalFilename.lowercased()
            if !name.isEmpty && size > 0 {
                keys.insert("\(name)_\(size)_\(createdMs)")
            }
        }
        return keys
    }

    private static func fetchOrCreateAlbum(named title: String) -> PHAssetCollection? {
        let fetchOptions = PHFetchOptions()
        fetchOptions.predicate = NSPredicate(format: "title = %@", title)
        let collections = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: fetchOptions)
        if let existing = collections.firstObject {
            return existing
        }
        var placeholderId: String?
        try? PHPhotoLibrary.shared().performChangesAndWait {
            let createReq = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: title)
            placeholderId = createReq.placeholderForCreatedAssetCollection.localIdentifier
        }
        guard let id = placeholderId else { return nil }
        return PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [id], options: nil).firstObject
    }

    /// Scansiona Foto e Video del Rullino iOS preservando il vero Album utente (`Vacanze`, `WhatsApp`, ecc.).
    static func scanLibraryAssets(includePhotos: Bool, includeVideos: Bool) async -> [(ManifestItem, PHAsset)] {
        guard includePhotos || includeVideos else { return [] }
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        guard status == .authorized || status == .limited else { return [] }

        let albumMap = buildAssetAlbumMap()
        let opts = PHFetchOptions()
        opts.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        let fetched = PHAsset.fetchAssets(with: opts)
        var out: [(ManifestItem, PHAsset)] = []

        fetched.enumerateObjects { asset, idx, _ in
            let isVideo = asset.mediaType == .video
            let isPhoto = asset.mediaType == .image
            if (isVideo && !includeVideos) || (isPhoto && !includePhotos) || (!isVideo && !isPhoto) {
                return
            }
            guard let primary = primaryMediaResource(for: asset) else { return }
            let size = (primary.value(forKey: "fileSize") as? Int64) ?? 1_048_576
            let createdMs = Int64((asset.creationDate?.timeIntervalSince1970 ?? 0) * 1000.0)
            let fileName = primary.originalFilename.isEmpty ? "media_\(idx).\(isVideo ? "mov" : "jpg")" : primary.originalFilename
            let albumName = albumMap[asset.localIdentifier] ?? "iPhone_Camera"
            let cat: TransferCategory = isVideo ? .VIDEOS : .PHOTOS
            let item = ManifestItem(
                id: "\(cat.rawValue.lowercased())_\(idx)",
                category: cat,
                fileName: fileName,
                relativeAlbumOrFolder: albumName,
                sizeBytes: size,
                capturedEpochMillis: createdMs,
                dedupKey: "\(fileName.lowercased())_\(size)_\(createdMs)",
                mimeType: mimeTypeForFileName(fileName, isVideo: isVideo)
            )
            out.append((item, asset))
        }
        return out
    }

    /// Esporta un `PHAsset` direttamente su file temporaneo su disco tramite `PHAssetResourceManager.writeData`
    /// senza caricare video 4K multi-GB in memoria RAM.
    static func exportAssetToTempFile(_ asset: PHAsset) async -> URL? {
        guard let primary = primaryMediaResource(for: asset) else { return nil }
        let safeName = URL(fileURLWithPath: primary.originalFilename).lastPathComponent
        let destURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ds_exp_\(UUID().uuidString)_\(safeName.isEmpty ? "asset.bin" : safeName)")
        try? FileManager.default.removeItem(at: destURL)

        return await withCheckedContinuation { continuation in
            let opts = PHAssetResourceRequestOptions()
            opts.isNetworkAccessAllowed = true
            PHAssetResourceManager.default().writeData(
                for: primary,
                toFile: destURL,
                options: opts
            ) { error in
                if error != nil || !FileManager.default.fileExists(atPath: destURL.path) {
                    try? FileManager.default.removeItem(at: destURL)
                    continuation.resume(returning: nil)
                } else {
                    continuation.resume(returning: destURL)
                }
            }
        }
    }

    /// Mantenuto per compatibilità con asset piccoli in memoria.
    static func exportAssetData(_ asset: PHAsset) async -> Data? {
        guard let tempURL = await exportAssetToTempFile(asset) else { return nil }
        defer { try? FileManager.default.removeItem(at: tempURL) }
        return try? Data(contentsOf: tempURL)
    }
}

enum iOSSmsArchiveStore {
    /// Poiché la sandbox di iOS non consente ad app di terze parti di scrivere nel DB di iMessage,
    /// salva tutti gli SMS provenienti da Android in un archivio HTML + JSON consultabile nell'app "File" di iPhone.
    static func saveIncomingSmsArchive(_ incoming: [SmsTransferRecord]) -> Int {
        guard !incoming.isEmpty,
              let docsRoot = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return 0
        }
        let targetDir = docsRoot.appendingPathComponent("DirectSwitch_Documenti", isDirectory: true)
            .appendingPathComponent("SMS_Archivio", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: targetDir, withIntermediateDirectories: true)
            let jsonData = try JSONEncoder().encode(incoming)
            try jsonData.write(to: targetDir.appendingPathComponent("SMS_Archivio_DirectSwitch.json"), options: .atomic)
        } catch {
            return 0
        }

        let df = DateFormatter()
        df.locale = Locale(identifier: "it_IT")
        df.dateFormat = "dd/MM/yyyy HH:mm"

        var html = "<!DOCTYPE html><html lang='it'><head><meta charset='utf-8'><meta name='viewport' content='width=device-width,initial-scale=1'><title>Archivio SMS DirectSwitch (\(incoming.count))</title><style>body{font-family:-apple-system,sans-serif;background:#f2f6f8;padding:16px}.msg{background:#fff;border-radius:12px;padding:12px;margin-bottom:10px;box-shadow:0 1px 4px rgba(0,0,0,0.06)}.meta{font-size:12px;color:#008f7a;font-weight:bold;margin-bottom:4px}</style></head><body><h2>SMS Trasferiti con DirectSwitch (\(incoming.count))</h2>"
        for sms in incoming {
            let dir = sms.messageType == 2 ? "Inviato a" : "Ricevuto da"
            let dateStr = sms.dateEpochMillis > 0
                ? " • \(df.string(from: Date(timeIntervalSince1970: TimeInterval(sms.dateEpochMillis) / 1000.0)))"
                : ""
            let safeAddr = sms.address.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
            let safeBody = sms.body.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
            html += "<div class='msg'><div class='meta'>\(dir) \(safeAddr)\(dateStr)</div><div>\(safeBody)</div></div>"
        }
        html += "</body></html>"
        if let htmlData = html.data(using: .utf8) {
            try? htmlData.write(to: targetDir.appendingPathComponent("SMS_Archivio_DirectSwitch.html"), options: .atomic)
        }
        return incoming.count
    }
}

enum iOSDocumentsSandboxBridge {
    static func mimeForExtension(_ ext: String) -> String {
        switch ext.lowercased() {
        case "pdf": return "application/pdf"
        case "zip": return "application/zip"
        case "txt": return "text/plain"
        case "csv": return "text/csv"
        case "vcf": return "text/vcard"
        case "ics": return "text/calendar"
        case "opus": return "audio/ogg"
        default: return "application/octet-stream"
        }
    }

    private static func stagingVaultDirectory() -> URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent("DirectSwitch_SharedVault", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func uniqueDestinationURL(in dir: URL, preferredFileName: String) -> URL {
        let baseURL = URL(fileURLWithPath: preferredFileName)
        let ext = baseURL.pathExtension
        let stem = baseURL.deletingPathExtension().lastPathComponent
        var candidate = dir.appendingPathComponent(preferredFileName)
        var index = 1
        while FileManager.default.fileExists(atPath: candidate.path) {
            let numbered = ext.isEmpty ? "\(stem) (\(index))" : "\(stem) (\(index)).\(ext)"
            candidate = dir.appendingPathComponent(numbered)
            index += 1
        }
        return candidate
    }

    private static func targetDirectory(for item: ManifestItem) -> URL? {
        guard let docsRoot = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return nil
        }
        var dir = docsRoot.appendingPathComponent("DirectSwitch_Documenti", isDirectory: true)
        let sub = item.category == .WHATSAPP_VAULT
            ? "WhatsApp_Vault"
            : item.relativeAlbumOrFolder
                .replacingOccurrences(of: "..", with: "")
                .replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "\\", with: "_")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        if !sub.isEmpty {
            dir = dir.appendingPathComponent(sub, isDirectory: true)
        }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Salva un file decifrato su disco nella cartella pubblica visibile nell'app "File" di iPhone (`UIFileSharingEnabled`).
    static func saveDocumentFile(item: ManifestItem, sourceFileURL: URL) -> Bool {
        guard let targetDir = targetDirectory(for: item) else { return false }
        let safeFileName = URL(fileURLWithPath: item.fileName).lastPathComponent
        let destURL = uniqueDestinationURL(
            in: targetDir,
            preferredFileName: safeFileName.isEmpty ? "documento_\(item.id)" : safeFileName
        )
        do {
            if FileManager.default.fileExists(atPath: destURL.path) {
                try FileManager.default.removeItem(at: destURL)
            }
            try FileManager.default.moveItem(at: sourceFileURL, to: destURL)
            return true
        } catch {
            do {
                try FileManager.default.copyItem(at: sourceFileURL, to: destURL)
                return true
            } catch {
                return false
            }
        }
    }

    static func saveDocument(item: ManifestItem, plainData: Data) -> Bool {
        guard let targetDir = targetDirectory(for: item) else { return false }
        let safeFileName = URL(fileURLWithPath: item.fileName).lastPathComponent
        let destURL = uniqueDestinationURL(
            in: targetDir,
            preferredFileName: safeFileName.isEmpty ? "documento_\(item.id)" : safeFileName
        )
        do {
            try plainData.write(to: destURL, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    /// Copia nel Vault i Documenti o gli archivi `.zip` di WhatsApp selezionati dall'app File o condivisi da WhatsApp (`Apri in DirectSwitch`).
    static func importPickedDocumentURLs(_ urls: [URL]) -> [(ManifestItem, URL)] {
        let stagingDir = stagingVaultDirectory()
        var results: [(ManifestItem, URL)] = []

        for (idx, url) in urls.enumerated() {
            guard url.isFileURL else { continue }
            let accessed = url.startAccessingSecurityScopedResource()
            defer {
                if accessed { url.stopAccessingSecurityScopedResource() }
            }
            let rawName = url.lastPathComponent
            let safeName = rawName.isEmpty ? "documento_\(idx).bin" : rawName
            let stagedURL = uniqueDestinationURL(in: stagingDir, preferredFileName: safeName)
            do {
                try FileManager.default.copyItem(at: url, to: stagedURL)
                if url.path.contains("/Documents/Inbox/") {
                    try? FileManager.default.removeItem(at: url)
                }
                let attrs = try FileManager.default.attributesOfItem(atPath: stagedURL.path)
                let size = (attrs[.size] as? Int64) ?? (attrs[.size] as? NSNumber)?.int64Value ?? 0
                guard size > 0 else {
                    try? FileManager.default.removeItem(at: stagedURL)
                    continue
                }
                let modDate = (attrs[.modificationDate] as? Date) ?? Date()
                let modMs = Int64(modDate.timeIntervalSince1970 * 1000.0)
                let lower = safeName.lowercased()
                let ext = stagedURL.pathExtension.lowercased()
                let isWhatsApp = lower.contains("whatsapp") || ext == "opus" || (ext == "zip" && lower.contains("chat"))
                let category: TransferCategory = isWhatsApp ? .WHATSAPP_VAULT : .DOCUMENTS
                let item = ManifestItem(
                    id: "doc_\(UUID().uuidString.prefix(8).lowercased())_\(idx)",
                    category: category,
                    fileName: safeName,
                    relativeAlbumOrFolder: isWhatsApp ? "WhatsApp_Vault" : "Documenti",
                    sizeBytes: size,
                    capturedEpochMillis: modMs,
                    dedupKey: "\(lower)_\(size)_\(modMs)",
                    mimeType: mimeForExtension(ext)
                )
                results.append((item, stagedURL))
            } catch {
                continue
            }
        }
        return results
    }

    /// Gestisce un singolo file aperto tramite Share Sheet iOS (`WhatsApp -> Esporta chat -> DirectSwitch`).
    static func importIncomingOpenURL(_ url: URL) -> (ManifestItem, URL)? {
        importPickedDocumentURLs([url]).first
    }

    static func clearStagedVault() {
        try? FileManager.default.removeItem(at: stagingVaultDirectory())
    }
}

enum iOSCalendarMigrator {
    static func isAuthorized() -> Bool {
        let status = EKEventStore.authorizationStatus(for: .event)
        if #available(iOS 17.0, *) {
            return status == .fullAccess
        } else {
            return status == .authorized
        }
    }

    static func requestAccessIfNeeded() async -> Bool {
        if isAuthorized() { return true }
        let store = EKEventStore()
        if #available(iOS 17.0, *) {
            return (try? await store.requestFullAccessToEvents()) ?? false
        } else {
            return (try? await store.requestAccess(to: .event)) ?? false
        }
    }

    static func readEvents() -> [CalendarEventRecord] {
        guard isAuthorized() else { return [] }
        let store = EKEventStore()
        let start = Date().addingTimeInterval(-365 * 86400)
        let end = Date().addingTimeInterval(365 * 86400 * 2)
        let pred = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        return store.events(matching: pred).map { ev in
            CalendarEventRecord(
                id: ev.eventIdentifier ?? UUID().uuidString,
                title: ev.title ?? "Evento",
                description: ev.notes,
                location: ev.location,
                startEpochMillis: Int64(ev.startDate.timeIntervalSince1970 * 1000.0),
                endEpochMillis: Int64(ev.endDate.timeIntervalSince1970 * 1000.0),
                allDay: ev.isAllDay
            )
        }
    }

    static func importEvents(_ incoming: [CalendarEventRecord]) -> Int {
        guard !incoming.isEmpty, isAuthorized() else { return 0 }
        let store = EKEventStore()
        guard let targetCalendar = store.defaultCalendarForNewEvents else { return 0 }

        let minMs = incoming.map(\.startEpochMillis).min() ?? 0
        let maxMs = incoming.map(\.endEpochMillis).max() ?? minMs
        let existingStart = Date(timeIntervalSince1970: TimeInterval(minMs) / 1000.0 - 86400)
        let existingEnd = Date(timeIntervalSince1970: TimeInterval(maxMs) / 1000.0 + 86400)
        let existingPred = store.predicateForEvents(withStart: existingStart, end: existingEnd, calendars: nil)
        var existingSignatures = Set<String>(
            store.events(matching: existingPred).map { ev in
                let normTitle = (ev.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                let startMinute = Int64(ev.startDate.timeIntervalSince1970 * 1000.0) / 60_000
                return "\(normTitle)_\(startMinute)"
            }
        )

        var imported = 0
        for rec in incoming {
            let normTitle = rec.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let sig = "\(normTitle)_\(rec.startEpochMillis / 60_000)"
            if existingSignatures.contains(sig) {
                continue
            }
            let ev = EKEvent(eventStore: store)
            ev.calendar = targetCalendar
            ev.title = rec.title
            ev.notes = rec.description
            ev.location = rec.location
            ev.startDate = Date(timeIntervalSince1970: TimeInterval(rec.startEpochMillis) / 1000.0)
            ev.endDate = Date(timeIntervalSince1970: TimeInterval(rec.endEpochMillis) / 1000.0)
            ev.isAllDay = rec.allDay
            if (try? store.save(ev, span: .thisEvent, commit: false)) != nil {
                existingSignatures.insert(sig)
                imported += 1
            }
        }
        if imported > 0 {
            do {
                try store.commit()
            } catch {
                return 0
            }
        }
        return imported
    }
}
