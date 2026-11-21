//
//  DirectSwitchMigrators.swift
//  DirectSwitch-iOS
//
//  Created by Nicolas Donati.
//  Copyright © 2026 Nicolas Donati. Tutti i diritti riservati.
//

import Foundation
import AVFoundation
import Contacts
import CoreLocation
import Photos
import EventKit
import StoreKit
import UIKit

/// Riepilogo locale dei dati e dello spazio disponibile sull'iPhone (parità con `LocalDeviceScanSummary` Android).
struct iOSDocumentFolderSummary: Sendable, Equatable, Identifiable {
    var id: String { folderPath }
    let folderPath: String
    let fileCount: Int
    let totalBytes: Int64
}

struct iOSDocumentLocationSummary: Sendable, Equatable, Identifiable {
    var id: String { locationId }
    let locationId: String
    let locationName: String
    let folderCount: Int
    let fileCount: Int
    let totalBytes: Int64
    var isSelected: Bool = true
    var isRemovableBookmark: Bool = false

    init(
        locationId: String? = nil,
        locationName: String,
        folderCount: Int,
        fileCount: Int,
        totalBytes: Int64,
        isSelected: Bool = true,
        isRemovableBookmark: Bool = false
    ) {
        self.locationId = locationId ?? locationName
        self.locationName = locationName
        self.folderCount = folderCount
        self.fileCount = fileCount
        self.totalBytes = totalBytes
        self.isSelected = isSelected
        self.isRemovableBookmark = isRemovableBookmark
    }
}

enum iOSDocumentPresetKind: String, CaseIterable, Identifiable, Sendable {
    case iCloudDrive
    case onMyIPhone
    case chrome

    var id: String { rawValue }

    var title: String {
        switch self {
        case .iCloudDrive: return "iCloud Drive"
        case .onMyIPhone: return "Su iPhone"
        case .chrome: return "Chrome"
        }
    }

    var systemIcon: String {
        switch self {
        case .iCloudDrive: return "icloud.fill"
        case .onMyIPhone: return "iphone"
        case .chrome: return "globe"
        }
    }

    static func match(for summary: iOSDocumentLocationSummary) -> iOSDocumentPresetKind? {
        let lowerName = summary.locationName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let lowerId = summary.locationId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if lowerName == "icloud drive" {
            return .iCloudDrive
        }
        if lowerName == "chrome" || lowerName == "su iphone • chrome" || lowerId.hasSuffix("/chrome") {
            return .chrome
        }
        if lowerName == "su iphone" {
            return .onMyIPhone
        }
        return nil
    }
}

struct iOSDocumentsPrecheckReport: Sendable, Equatable {
    let totalFiles: Int
    let totalBytes: Int64
    let authorizedBookmarkFoldersCount: Int
    let localAppFolderFilesCount: Int
    let unreadableFilesCount: Int
    let folderSummaries: [iOSDocumentFolderSummary]
    var locationSummaries: [iOSDocumentLocationSummary] = []
}

struct iOSLocalDeviceScanSummary: Sendable, Equatable {
    let contactsCount: Int
    let photosCount: Int
    var livePhotosCount: Int = 0
    let photosBytes: Int64
    let videosCount: Int
    let videosBytes: Int64
    let calendarEventsCount: Int
    var remindersCount: Int = 0
    let documentsCount: Int
    var documentsBytes: Int64 = 0
    var documentFoldersCount: Int = 0
    var documentFolderSummaries: [iOSDocumentFolderSummary] = []
    var documentLocationSummaries: [iOSDocumentLocationSummary] = []
    let whatsappArchivesCount: Int
    let freeStorageBytes: Int64
    let totalStorageBytes: Int64
    let hasFullPermissions: Bool
    var contactsDenied: Bool = false
    var photosDenied: Bool = false
    var calendarsDenied: Bool = false
    var remindersDenied: Bool = false
    var photoAlbumsCount: Int = 0
    var iCloudPhotosCount: Int = 0
    var iCloudVideosCount: Int = 0
}

struct ContactsPreloadState: Equatable, Sendable {
    var loadedCount: Int = 0
    var totalCount: Int = 0
    var isLoading: Bool = false
    var isCompleted: Bool = false
}

struct PhotosPreloadState: Equatable, Sendable {
    var loadedCount: Int = 0
    var totalCount: Int = 0
    var livePhotosCount: Int = 0
    var albumsCount: Int = 0
    var iCloudCount: Int = 0
    var estimatedBytes: Int64 = 0
    var isLoading: Bool = false
    var isCompleted: Bool = false
}

struct VideosPreloadState: Equatable, Sendable {
    var loadedCount: Int = 0
    var totalCount: Int = 0
    var iCloudCount: Int = 0
    var estimatedBytes: Int64 = 0
    var isLoading: Bool = false
    var isCompleted: Bool = false
}

struct DateSyncPreloadState: Equatable, Sendable {
    var totalAllCount: Int = 0
    var totalUpToTodayCount: Int = 0
    var lastUpdatedAt: Date? = nil
    var isLoading: Bool = false
}

enum iOSPermissionsHelper {
    /// Elenco curato delle app essenziali più diffuse in Italia per il download 1-tap su nuovo iPhone senza iCloud.
    static let essentialiOSApps: [InstalledAppRecord] = [
        InstalledAppRecord(packageName: "net.whatsapp.WhatsApp", appName: "WhatsApp Messenger"),
        InstalledAppRecord(packageName: "com.google.Gmail", appName: "Gmail"),
        InstalledAppRecord(packageName: "com.google.Maps", appName: "Google Maps"),
        InstalledAppRecord(packageName: "com.google.chrome.ios", appName: "Google Chrome"),
        InstalledAppRecord(packageName: "com.google.ios.youtube", appName: "YouTube"),
        InstalledAppRecord(packageName: "com.burbn.instagram", appName: "Instagram"),
        InstalledAppRecord(packageName: "ph.telegra.Telegraph", appName: "Telegram Messenger"),
        InstalledAppRecord(packageName: "com.spotify.client", appName: "Spotify"),
        InstalledAppRecord(packageName: "com.microsoft.Office.Outlook", appName: "Microsoft Outlook"),
        InstalledAppRecord(packageName: "it.pagopa.app.io", appName: "IO"),
        InstalledAppRecord(packageName: "it.ipzs.cieid", appName: "CieID"),
        InstalledAppRecord(packageName: "posteitaliane.posteapp.appposteid", appName: "PosteID"),
        InstalledAppRecord(packageName: "it.aruba.pec.mobile", appName: "Aruba PEC")
    ]

    /// Richiede in anticipo i permessi di Contatti, Libreria Foto, Calendari, Promemoria e Notifiche background
    /// evitando che i popup di sistema compaiano a metà di una connessione HTTP attiva.
    static func requestAllTransferPermissions() async {
        _ = await iOSContactsSmartMerger.requestAccessIfNeeded()
        _ = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        _ = await iOSCalendarMigrator.requestAccessIfNeeded()
        _ = await iOSRemindersMigrator.requestAccessIfNeeded()
        await MainActor.run {
            iOSBackgroundTransferKeepAlive.shared.requestNotificationPermissionIfNeeded()
        }
    }

    static func receiverDeniedSummaryText() -> String? {
        var missing: [String] = []
        let cStatus = CNContactStore.authorizationStatus(for: .contacts)
        if cStatus == .denied || cStatus == .restricted {
            missing.append("Contatti")
        }
        let pStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if pStatus == .denied || pStatus == .restricted {
            missing.append("Foto")
        }
        let eStatus = EKEventStore.authorizationStatus(for: .event)
        if eStatus == .denied || eStatus == .restricted {
            missing.append("Calendari")
        }
        let rStatus = EKEventStore.authorizationStatus(for: .reminder)
        if rStatus == .denied || rStatus == .restricted {
            missing.append("Promemoria")
        }
        guard !missing.isEmpty else { return nil }
        return "Permessi disattivati su questo iPhone: \(missing.joined(separator: ", ")). Attivali in Impostazioni → DirectSwitch per salvare tutti i dati ricevuti."
    }

    /// Apre direttamente la schermata di DirectSwitch nelle Impostazioni iOS (dove si trovano lo switch «Rete locale», Foto e Contatti).
    @MainActor
    static func openDirectSwitchSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    /// Apre direttamente l'App Store per accedere allo storico gratuito «App → Non su questo iPhone» (0 GB su iCloud).
    @MainActor
    static func openAppStorePurchasedSection() {
        if let appStoreURL = URL(string: "itms-apps://itunes.apple.com/"),
           UIApplication.shared.canOpenURL(appStoreURL) {
            UIApplication.shared.open(appStoreURL)
            return
        }
        if let webURL = URL(string: "https://apps.apple.com/it/iphone/today") {
            UIApplication.shared.open(webURL)
        }
    }

    /// Cerca un'app direttamente sull'App Store di iPhone.
    @MainActor
    static func searchAppOnAppStore(appName: String) {
        let trimmed = appName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return }
        if let nativeURL = URL(string: "itms-apps://itunes.apple.com/search?term=\(encoded)"),
           UIApplication.shared.canOpenURL(nativeURL) {
            UIApplication.shared.open(nativeURL)
            return
        }
        if let webURL = URL(string: "https://apps.apple.com/it/search?term=\(encoded)") {
            UIApplication.shared.open(webURL)
        }
    }
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
    static func scanAuthorizedSummary(
        stagedItems: [ManifestItem] = [],
        knownRemindersCount: Int = 0,
        includePairedLiveVideoBytes: Bool = true,
        allowCloudOnly: Bool = false
    ) -> iOSLocalDeviceScanSummary {
        let (freeBytes, totalBytes) = iOSStorageCapacityChecker.freeAndTotalStorageBytes()
        let rawContactsStatus = CNContactStore.authorizationStatus(for: .contacts)
        let contactsAuth = iOSContactsSmartMerger.isAuthorized()
        let contactsDenied = (rawContactsStatus == .denied || rawContactsStatus == .restricted)

        let photoStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        let photosAuth = (photoStatus == .authorized || photoStatus == .limited)
        let photosDenied = (photoStatus == .denied || photoStatus == .restricted)

        let rawCalStatus = EKEventStore.authorizationStatus(for: .event)
        let calAuth = iOSCalendarMigrator.isAuthorized()
        let calendarsDenied = (rawCalStatus == .denied || rawCalStatus == .restricted)

        let rawRemStatus = EKEventStore.authorizationStatus(for: .reminder)
        let remAuth = iOSRemindersMigrator.isAuthorized()
        let remindersDenied = (rawRemStatus == .denied || rawRemStatus == .restricted)

        let contactsCount = contactsAuth ? iOSContactsSmartMerger.readAllContacts().count : 0
        let calendarCount = calAuth ? iOSCalendarMigrator.readEvents().count : 0

        var photosCount = 0
        var livePhotosCount = 0
        var photosBytes: Int64 = 0
        var iCloudPhotosCount = 0
        var videosCount = 0
        var videosBytes: Int64 = 0
        var iCloudVideosCount = 0
        let photoAlbumsCount = photosAuth
            ? PHAssetCollection.fetchAssetCollections(with: .album, subtype: .albumRegular, options: nil).count
            : 0

        if photosAuth {
            let fetched = PHAsset.fetchAssets(with: nil)
            fetched.enumerateObjects { asset, _, _ in
                if asset.mediaType == .image {
                    let measured = iOSPhotoKitMigrator.measureAssetBytes(
                        asset,
                        includePairedLiveVideoBytes: includePairedLiveVideoBytes,
                        allowCloudOnly: allowCloudOnly
                    )
                    if measured.isEligible {
                        photosCount += 1
                        if measured.hasEligibleLiveVideo {
                            livePhotosCount += 1
                        }
                        photosBytes += measured.bytes
                    }
                    if !measured.isLocallyAvailable {
                        iCloudPhotosCount += 1
                    }
                } else if asset.mediaType == .video {
                    let measured = iOSPhotoKitMigrator.measureAssetBytes(
                        asset,
                        includePairedLiveVideoBytes: false,
                        allowCloudOnly: allowCloudOnly
                    )
                    if measured.isEligible {
                        videosCount += 1
                        videosBytes += measured.bytes
                    }
                    if !measured.isLocallyAvailable {
                        iCloudVideosCount += 1
                    }
                }
            }
        }

        let docPrecheck = iOSDocumentsSandboxBridge.inspectPreTransferDocuments(
            stagedItems: stagedItems,
            includeWhatsAppVault: false
        )
        let waLocalCount = iOSDocumentsSandboxBridge.inspectPreTransferDocuments(
            stagedItems: stagedItems,
            includeWhatsAppVault: true
        )
            .folderSummaries
            .filter { $0.folderPath.hasPrefix("WhatsApp_Vault") }
            .reduce(0) { $0 + $1.fileCount }
        let waCount = max(stagedItems.filter { $0.category == .WHATSAPP_VAULT }.count, waLocalCount)

        return iOSLocalDeviceScanSummary(
            contactsCount: contactsCount,
            photosCount: photosCount,
            livePhotosCount: livePhotosCount,
            photosBytes: photosBytes,
            videosCount: videosCount,
            videosBytes: videosBytes,
            calendarEventsCount: calendarCount,
            remindersCount: knownRemindersCount,
            documentsCount: docPrecheck.totalFiles,
            documentsBytes: docPrecheck.totalBytes,
            documentFoldersCount: docPrecheck.folderSummaries.count,
            documentFolderSummaries: docPrecheck.folderSummaries,
            documentLocationSummaries: docPrecheck.locationSummaries,
            whatsappArchivesCount: waCount,
            freeStorageBytes: freeBytes,
            totalStorageBytes: totalBytes,
            hasFullPermissions: contactsAuth && photosAuth && calAuth && remAuth,
            contactsDenied: contactsDenied,
            photosDenied: photosDenied,
            calendarsDenied: calendarsDenied,
            remindersDenied: remindersDenied,
            photoAlbumsCount: photoAlbumsCount,
            iCloudPhotosCount: iCloudPhotosCount,
            iCloudVideosCount: iCloudVideosCount
        )
    }

    /// Richiede i permessi di lettura e restituisce il conteggio esatto dei contenuti sull'iPhone (inclusi Promemoria e Live Photos).
    static func requestPermissionsAndScanAll(stagedItems: [ManifestItem] = []) async -> iOSLocalDeviceScanSummary {
        _ = await iOSContactsSmartMerger.requestAccessIfNeeded()
        _ = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        _ = await iOSCalendarMigrator.requestAccessIfNeeded()
        _ = await iOSRemindersMigrator.requestAccessIfNeeded()
        let remCount = await iOSRemindersMigrator.readReminders().count
        return await Task.detached(priority: .userInitiated) {
            scanAuthorizedSummary(stagedItems: stagedItems, knownRemindersCount: remCount)
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
/// Supporta sia `.authorized` sia `CNAuthorizationStatus.limited` (`rawValue == 4`) introdotto in iOS 18+.
enum iOSContactsSmartMerger {
    static func isAuthorized() -> Bool {
        let status = CNContactStore.authorizationStatus(for: .contacts)
        return status == .authorized || status.rawValue == 4
    }

    static func requestAccessIfNeeded() async -> Bool {
        if isAuthorized() { return true }
        let store = CNContactStore()
        _ = try? await store.requestAccess(for: .contacts)
        return isAuthorized()
    }

    private static func encodeContactLabel(_ raw: String?) -> String {
        guard let raw, !raw.isEmpty else { return "other" }
        switch raw {
        case CNLabelPhoneNumberMobile: return "mobile"
        case CNLabelPhoneNumberiPhone: return "iphone"
        case CNLabelPhoneNumberMain: return "main"
        case CNLabelHome: return "home"
        case CNLabelWork: return "work"
        case CNLabelEmailiCloud: return "icloud"
        default: return CNLabeledValue<NSString>.localizedString(forLabel: raw)
        }
    }

    private static func decodePhoneLabel(_ tag: String) -> String {
        switch tag.lowercased() {
        case "mobile": return CNLabelPhoneNumberMobile
        case "iphone": return CNLabelPhoneNumberiPhone
        case "main": return CNLabelPhoneNumberMain
        case "home": return CNLabelHome
        case "work": return CNLabelWork
        case "other", "": return CNLabelOther
        default: return tag
        }
    }

    private static func decodeGenericLabel(_ tag: String) -> String {
        switch tag.lowercased() {
        case "home": return CNLabelHome
        case "work": return CNLabelWork
        case "icloud": return CNLabelEmailiCloud
        case "other", "": return CNLabelOther
        default: return tag
        }
    }

    static func readAllContacts() -> [ContactTransferRecord] {
        let store = CNContactStore()
        guard isAuthorized() else { return [] }
        let keys: [CNKeyDescriptor] = [
            CNContactIdentifierKey as CNKeyDescriptor,
            CNContactGivenNameKey as CNKeyDescriptor,
            CNContactFamilyNameKey as CNKeyDescriptor,
            CNContactNicknameKey as CNKeyDescriptor,
            CNContactOrganizationNameKey as CNKeyDescriptor,
            CNContactJobTitleKey as CNKeyDescriptor,
            CNContactBirthdayKey as CNKeyDescriptor,
            CNContactPhoneNumbersKey as CNKeyDescriptor,
            CNContactEmailAddressesKey as CNKeyDescriptor,
            CNContactUrlAddressesKey as CNKeyDescriptor,
            CNContactPostalAddressesKey as CNKeyDescriptor,
            CNContactThumbnailImageDataKey as CNKeyDescriptor
        ]
        let req = CNContactFetchRequest(keysToFetch: keys)
        var out: [ContactTransferRecord] = []
        try? store.enumerateContacts(with: req) { contact, _ in
            let given = contact.givenName.trimmingCharacters(in: .whitespaces)
            let family = contact.familyName.trimmingCharacters(in: .whitespaces)
            let name = [given, family]
                .filter { !$0.isEmpty }
                .joined(separator: " ")
                .trimmingCharacters(in: .whitespaces)
            let orgTrimmed = contact.organizationName.trimmingCharacters(in: .whitespaces)
            let nickTrimmed = contact.nickname.trimmingCharacters(in: .whitespaces)
            let jobTrimmed = contact.jobTitle.trimmingCharacters(in: .whitespaces)

            let labeledPhones: [LabeledValueRecord] = contact.phoneNumbers.compactMap { lv in
                let val = lv.value.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !val.isEmpty else { return nil }
                return LabeledValueRecord(label: encodeContactLabel(lv.label), value: val)
            }
            let phones = labeledPhones.map(\.value)

            let labeledEmails: [LabeledValueRecord] = contact.emailAddresses.compactMap { lv in
                let val = String(lv.value).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !val.isEmpty else { return nil }
                return LabeledValueRecord(label: encodeContactLabel(lv.label), value: val)
            }
            let emails = labeledEmails.map(\.value)

            let urls: [String] = contact.urlAddresses.map { String($0.value).trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }

            let addresses: [PostalAddressTransferRecord] = contact.postalAddresses.compactMap { lv in
                let pa = lv.value
                if pa.street.isEmpty && pa.city.isEmpty && pa.postalCode.isEmpty && pa.country.isEmpty {
                    return nil
                }
                return PostalAddressTransferRecord(
                    label: encodeContactLabel(lv.label),
                    street: pa.street,
                    city: pa.city,
                    state: pa.state,
                    postalCode: pa.postalCode,
                    country: pa.country
                )
            }

            var avatarBase64: String? = nil
            if let thumb = contact.thumbnailImageData, !thumb.isEmpty, thumb.count <= 65_536 {
                avatarBase64 = thumb.base64EncodedString()
            }

            let fallbackLabel = !orgTrimmed.isEmpty ? orgTrimmed : (!nickTrimmed.isEmpty ? nickTrimmed : (phones.first ?? emails.first ?? ""))
            let effectiveName = name.isEmpty ? fallbackLabel : name

            if !effectiveName.isEmpty {
                out.append(
                    ContactTransferRecord(
                        id: contact.identifier,
                        displayName: effectiveName,
                        phones: phones,
                        emails: emails,
                        organization: orgTrimmed.isEmpty ? nil : orgTrimmed,
                        givenName: given.isEmpty ? nil : given,
                        familyName: family.isEmpty ? nil : family,
                        nickname: nickTrimmed.isEmpty ? nil : nickTrimmed,
                        jobTitle: jobTrimmed.isEmpty ? nil : jobTrimmed,
                        birthdayYear: contact.birthday?.year,
                        birthdayMonth: contact.birthday?.month,
                        birthdayDay: contact.birthday?.day,
                        labeledPhones: labeledPhones.isEmpty ? nil : labeledPhones,
                        labeledEmails: labeledEmails.isEmpty ? nil : labeledEmails,
                        urls: urls.isEmpty ? nil : urls,
                        postalAddresses: addresses.isEmpty ? nil : addresses,
                        avatarJpegBase64: avatarBase64
                    )
                )
            }
        }
        return out
    }

    /// Precaricamento progressivo dei contatti fino al totale effettivo presente in rubrica per la tendina UI.
    static func preloadContactsCountWithProgress(
        onProgress: @Sendable @escaping (_ loaded: Int, _ total: Int) -> Void
    ) async -> Int {
        guard isAuthorized() else {
            onProgress(0, 0)
            return 0
        }
        return await Task.detached(priority: .userInitiated) {
            let store = CNContactStore()
            let countKeys: [CNKeyDescriptor] = [
                CNContactIdentifierKey as CNKeyDescriptor,
                CNContactGivenNameKey as CNKeyDescriptor,
                CNContactFamilyNameKey as CNKeyDescriptor,
                CNContactOrganizationNameKey as CNKeyDescriptor,
                CNContactNicknameKey as CNKeyDescriptor,
                CNContactPhoneNumbersKey as CNKeyDescriptor,
                CNContactEmailAddressesKey as CNKeyDescriptor
            ]
            var identifiers: [String] = []
            try? store.enumerateContacts(with: CNContactFetchRequest(keysToFetch: countKeys)) { contact, _ in
                let given = contact.givenName.trimmingCharacters(in: .whitespaces)
                let family = contact.familyName.trimmingCharacters(in: .whitespaces)
                let name = [given, family].filter { !$0.isEmpty }.joined(separator: " ").trimmingCharacters(in: .whitespaces)
                let org = contact.organizationName.trimmingCharacters(in: .whitespaces)
                let nick = contact.nickname.trimmingCharacters(in: .whitespaces)
                let firstPhone = contact.phoneNumbers.first?.value.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let firstEmail = (contact.emailAddresses.first?.value as String?)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if !name.isEmpty || !org.isEmpty || !nick.isEmpty || !firstPhone.isEmpty || !firstEmail.isEmpty {
                    identifiers.append(contact.identifier)
                }
            }
            let total = identifiers.count
            guard total > 0 else {
                onProgress(0, 0)
                return 0
            }
            let identifierSet = Set(identifiers)
            let fullKeys: [CNKeyDescriptor] = [
                CNContactIdentifierKey as CNKeyDescriptor,
                CNContactGivenNameKey as CNKeyDescriptor,
                CNContactFamilyNameKey as CNKeyDescriptor,
                CNContactNicknameKey as CNKeyDescriptor,
                CNContactOrganizationNameKey as CNKeyDescriptor,
                CNContactJobTitleKey as CNKeyDescriptor,
                CNContactBirthdayKey as CNKeyDescriptor,
                CNContactPhoneNumbersKey as CNKeyDescriptor,
                CNContactEmailAddressesKey as CNKeyDescriptor,
                CNContactUrlAddressesKey as CNKeyDescriptor,
                CNContactPostalAddressesKey as CNKeyDescriptor,
                CNContactThumbnailImageDataKey as CNKeyDescriptor
            ]
            let step = max(1, total / 24)
            var loaded = 0
            onProgress(0, total)
            let req = CNContactFetchRequest(keysToFetch: fullKeys)
            try? store.enumerateContacts(with: req) { contact, _ in
                if identifierSet.contains(contact.identifier) {
                    loaded += 1
                    if loaded % step == 0 || loaded == total {
                        onProgress(min(loaded, total), total)
                    }
                }
            }
            onProgress(total, total)
            return total
        }.value
    }

    static func mergeIncomingContacts(_ incoming: [ContactTransferRecord]) -> (inserted: Int, skipped: Int) {
        guard isAuthorized(), !incoming.isEmpty else { return (0, 0) }
        let store = CNContactStore()
        let existing = readAllContacts()
        var existingPhones = Set(existing.flatMap { $0.phones }.map { PhoneNormalizer.normalizeKey($0) }.filter { !$0.isEmpty })
        var existingEmails = Set(existing.flatMap { $0.emails }.map { $0.lowercased() })
        var existingNameOnly = Set(
            existing
                .filter { $0.phones.isEmpty && $0.emails.isEmpty }
                .map { $0.displayName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        )

        var skipped = 0
        var toInsert: [CNMutableContact] = []

        for record in incoming {
            let normPhones = record.phones.map { PhoneNormalizer.normalizeKey($0) }.filter { !$0.isEmpty }
            let normEmails = record.emails.map { $0.lowercased() }
            let normName = record.displayName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

            let isDuplicate: Bool
            if !normPhones.isEmpty || !normEmails.isEmpty {
                isDuplicate = normPhones.contains(where: { existingPhones.contains($0) }) ||
                    normEmails.contains(where: { existingEmails.contains($0) })
            } else {
                isDuplicate = normName.isEmpty || existingNameOnly.contains(normName)
            }

            if isDuplicate {
                skipped += 1
                continue
            }

            let mutable = CNMutableContact()
            if let g = record.givenName, !g.isEmpty {
                mutable.givenName = g
                if let f = record.familyName, !f.isEmpty {
                    mutable.familyName = f
                }
            } else {
                let parts = record.displayName.split(separator: " ", maxSplits: 1).map(String.init)
                mutable.givenName = parts.first ?? record.displayName
                if parts.count > 1 { mutable.familyName = parts[1] }
            }
            if let org = record.organization, !org.isEmpty {
                mutable.organizationName = org
            }
            if let nick = record.nickname, !nick.isEmpty {
                mutable.nickname = nick
            }
            if let job = record.jobTitle, !job.isEmpty {
                mutable.jobTitle = job
            }
            if let bMonth = record.birthdayMonth, let bDay = record.birthdayDay {
                var comps = DateComponents()
                if let bYear = record.birthdayYear, bYear > 1900 {
                    comps.year = bYear
                }
                comps.month = bMonth
                comps.day = bDay
                mutable.birthday = comps
            }

            if let richPhones = record.labeledPhones, !richPhones.isEmpty {
                mutable.phoneNumbers = richPhones.map {
                    CNLabeledValue(label: decodePhoneLabel($0.label), value: CNPhoneNumber(stringValue: $0.value))
                }
            } else {
                mutable.phoneNumbers = record.phones.map {
                    CNLabeledValue(label: CNLabelPhoneNumberMobile, value: CNPhoneNumber(stringValue: $0))
                }
            }

            if let richEmails = record.labeledEmails, !richEmails.isEmpty {
                mutable.emailAddresses = richEmails.map {
                    CNLabeledValue(label: decodeGenericLabel($0.label), value: $0.value as NSString)
                }
            } else {
                mutable.emailAddresses = record.emails.map {
                    CNLabeledValue(label: CNLabelOther, value: $0 as NSString)
                }
            }

            if let urls = record.urls, !urls.isEmpty {
                mutable.urlAddresses = urls.map {
                    CNLabeledValue(label: CNLabelURLAddressHomePage, value: $0 as NSString)
                }
            }

            if let addresses = record.postalAddresses, !addresses.isEmpty {
                mutable.postalAddresses = addresses.map { addr in
                    let mAddr = CNMutablePostalAddress()
                    mAddr.street = addr.street
                    mAddr.city = addr.city
                    mAddr.state = addr.state
                    mAddr.postalCode = addr.postalCode
                    mAddr.country = addr.country
                    return CNLabeledValue(label: decodeGenericLabel(addr.label ?? "home"), value: mAddr)
                }
            }

            if let b64 = record.avatarJpegBase64,
               let imgData = Data(base64Encoded: b64),
               !imgData.isEmpty {
                mutable.imageData = imgData
            }

            toInsert.append(mutable)
            normPhones.forEach { existingPhones.insert($0) }
            normEmails.forEach { existingEmails.insert($0) }
            if normPhones.isEmpty && normEmails.isEmpty && !normName.isEmpty {
                existingNameOnly.insert(normName)
            }
        }

        guard !toInsert.isEmpty else { return (0, skipped) }

        let batchSaveReq = CNSaveRequest()
        for mutable in toInsert {
            batchSaveReq.add(mutable, toContainerWithIdentifier: nil)
        }
        do {
            try store.execute(batchSaveReq)
            return (toInsert.count, skipped)
        } catch {
            // Fallback singolo per contatto: evita che 1 contatto malformato annulli l'intera rubrica
            var singleSaved = 0
            for mutable in toInsert {
                let singleReq = CNSaveRequest()
                singleReq.add(mutable, toContainerWithIdentifier: nil)
                if (try? store.execute(singleReq)) != nil {
                    singleSaved += 1
                }
            }
            return (singleSaved, skipped)
        }
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
    static func isAuthorized() -> Bool {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        return status == .authorized || status == .limited
    }

    static func requestAccessIfNeeded() async -> PHAuthorizationStatus {
        let current = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if current == .authorized || current == .limited || current == .denied || current == .restricted {
            return current
        }
        return await PHPhotoLibrary.requestAuthorization(for: .readWrite)
    }

    private static func resourceFileSize(_ resource: PHAssetResource) -> Int64? {
        if let v = resource.value(forKey: "fileSize") as? Int64 {
            return v
        }
        if let n = resource.value(forKey: "fileSize") as? NSNumber {
            return n.int64Value
        }
        return nil
    }

    private static func resourceIsLocallyAvailable(_ resource: PHAssetResource) -> Bool {
        if let b = resource.value(forKey: "locallyAvailable") as? Bool {
            return b
        }
        if let n = resource.value(forKey: "locallyAvailable") as? NSNumber {
            return n.boolValue
        }
        return true
    }

    /// Individua la migliore risorsa principale realmente leggibile e trasferibile di un `PHAsset`:
    /// - Preferisce sempre una risorsa disponibile in locale (`locallyAvailable == true`) con `fileSize > 0`,
    ///   evitando fallimenti su foto modificate la cui versione `.fullSizePhoto` è solo su iCloud mentre `.photo` è locale.
    /// - Quando `allowCloudOnly == false` (predefinito), esclude a priori gli asset non scaricati localmente
    ///   così la selezione mostra solo i file realmente idonei al trasferimento (zero sorprese di file illeggibili).
    static func bestTransferablePrimaryResource(
        for asset: PHAsset,
        allowCloudOnly: Bool = false
    ) -> (resource: PHAssetResource, isLocallyAvailable: Bool, fileSize: Int64)? {
        let resources = PHAssetResource.assetResources(for: asset)
        guard !resources.isEmpty else { return nil }

        let orderedCandidates: [PHAssetResource]
        if asset.mediaType == .video {
            let fullVid = resources.filter { $0.type == .fullSizeVideo }
            let origVid = resources.filter { $0.type == .video }
            let otherVid = resources.filter {
                $0.type != .fullSizeVideo && $0.type != .video && $0.type != .adjustmentData
            }
            orderedCandidates = fullVid + origVid + otherVid
        } else {
            let fullPhoto = resources.filter { $0.type == .fullSizePhoto }
            let origPhoto = resources.filter { $0.type == .photo }
            let altPhoto = resources.filter { $0.type == .alternatePhoto }
            let otherPhoto = resources.filter {
                $0.type != .fullSizePhoto && $0.type != .photo && $0.type != .alternatePhoto &&
                $0.type != .adjustmentData && $0.type != .pairedVideo && $0.type != .fullSizePairedVideo
            }
            orderedCandidates = fullPhoto + origPhoto + altPhoto + otherPhoto
        }

        // 1. Prima scelta: risorsa realmente disponibile in locale con dimensione valida (> 0)
        for res in orderedCandidates {
            let isLocal = resourceIsLocallyAvailable(res)
            guard isLocal else { continue }
            let rawSize = resourceFileSize(res)
            if let s = rawSize, s <= 0 { continue }
            return (res, true, max(1, rawSize ?? 1_048_576))
        }

        // 2. Solo se l'utente ha esplicitamente abilitato gli elementi su iCloud (ed evitando album condivisi non scaricati)
        guard allowCloudOnly, asset.sourceType != .typeCloudShared else {
            return nil
        }
        for res in orderedCandidates {
            let rawSize = resourceFileSize(res)
            if let s = rawSize, s <= 0 { continue }
            return (res, false, max(1, rawSize ?? 1_048_576))
        }
        return nil
    }

    /// Individua la clip `.MOV` accoppiata di una Live Photo solo se effettivamente trasferibile.
    static func bestTransferablePairedLiveResource(
        for asset: PHAsset,
        allowCloudOnly: Bool = false
    ) -> (resource: PHAssetResource, fileSize: Int64)? {
        guard asset.mediaType == .image, asset.mediaSubtypes.contains(.photoLive) else {
            return nil
        }
        let resources = PHAssetResource.assetResources(for: asset)
        let candidates = resources.filter { $0.type == .fullSizePairedVideo } + resources.filter { $0.type == .pairedVideo }
        for res in candidates {
            let isLocal = resourceIsLocallyAvailable(res)
            let rawSize = resourceFileSize(res) ?? 0
            if isLocal && rawSize > 0 {
                return (res, rawSize)
            }
        }
        guard allowCloudOnly else { return nil }
        for res in candidates {
            let rawSize = resourceFileSize(res) ?? 0
            if rawSize > 0 {
                return (res, rawSize)
            }
        }
        return nil
    }

    /// Misura i byte reali (`fileSize` di `PHAssetResource`) e l'idoneità effettiva al trasferimento.
    static func measureAssetBytes(
        _ asset: PHAsset,
        includePairedLiveVideoBytes: Bool = true,
        allowCloudOnly: Bool = false
    ) -> (bytes: Int64, isLocallyAvailable: Bool, isEligible: Bool, hasEligibleLiveVideo: Bool) {
        if let localOrEligible = bestTransferablePrimaryResource(for: asset, allowCloudOnly: allowCloudOnly) {
            let livePair: (resource: PHAssetResource, fileSize: Int64)? = (includePairedLiveVideoBytes && asset.mediaType == .image)
                ? bestTransferablePairedLiveResource(for: asset, allowCloudOnly: allowCloudOnly)
                : nil
            let liveSize = livePair?.fileSize ?? 0
            return (localOrEligible.fileSize + liveSize, localOrEligible.isLocallyAvailable, true, livePair != nil)
        }
        let hasCloudCandidate = bestTransferablePrimaryResource(for: asset, allowCloudOnly: true) != nil
        return (0, !hasCloudCandidate, false, false)
    }

    /// Precaricamento progressivo dei soli media realmente idonei al trasferimento (leggendo `PHAssetResource` reale).
    static func preloadMediaStatsWithProgress(
        for mediaType: PHAssetMediaType,
        includePairedLiveVideoBytes: Bool = true,
        allowCloudOnly: Bool = false,
        onProgress: @Sendable @escaping (_ loaded: Int, _ total: Int, _ liveCount: Int, _ albumsCount: Int, _ iCloudCount: Int, _ estimatedBytes: Int64) -> Void
    ) async -> (total: Int, liveCount: Int, albumsCount: Int, iCloudCount: Int, estimatedBytes: Int64) {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard status == .authorized || status == .limited else {
            onProgress(0, 0, 0, 0, 0, 0)
            return (0, 0, 0, 0, 0)
        }
        return await Task.detached(priority: .userInitiated) {
            let albumsCount = mediaType == .image
                ? PHAssetCollection.fetchAssetCollections(with: .album, subtype: .albumRegular, options: nil).count
                : 0
            let fetched = PHAsset.fetchAssets(with: mediaType, options: nil)
            let rawTotal = fetched.count
            guard rawTotal > 0 else {
                onProgress(0, 0, 0, albumsCount, 0, 0)
                return (0, 0, albumsCount, 0, 0)
            }
            onProgress(0, rawTotal, 0, albumsCount, 0, 0)
            let step = max(1, rawTotal / 24)
            var scanned = 0
            var eligibleCount = 0
            var liveCount = 0
            var iCloudCount = 0
            var bytes: Int64 = 0
            fetched.enumerateObjects { asset, _, _ in
                scanned += 1
                let measured = measureAssetBytes(
                    asset,
                    includePairedLiveVideoBytes: mediaType == .image && includePairedLiveVideoBytes,
                    allowCloudOnly: allowCloudOnly
                )
                if measured.isEligible {
                    eligibleCount += 1
                    if measured.hasEligibleLiveVideo {
                        liveCount += 1
                    }
                    bytes += measured.bytes
                }
                if !measured.isLocallyAvailable {
                    iCloudCount += 1
                }
                if scanned % step == 0 || scanned == rawTotal {
                    onProgress(eligibleCount, max(eligibleCount, rawTotal - (allowCloudOnly ? 0 : iCloudCount)), liveCount, albumsCount, iCloudCount, bytes)
                }
            }
            onProgress(eligibleCount, eligibleCount, liveCount, albumsCount, iCloudCount, bytes)
            return (eligibleCount, liveCount, albumsCount, iCloudCount, bytes)
        }.value
    }
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
                ?? resources.first(where: { $0.type != .adjustmentData })
        } else {
            return resources.first(where: { $0.type == .fullSizePhoto })
                ?? resources.first(where: { $0.type == .photo })
                ?? resources.first(where: { $0.type == .alternatePhoto })
                ?? resources.first(where: {
                    $0.type != .adjustmentData && $0.type != .pairedVideo && $0.type != .fullSizePairedVideo
                })
        }
    }

    /// Individua la clip `.MOV` accoppiata se l'asset è una Live Photo nativa di iPhone.
    static func pairedLiveVideoResource(for asset: PHAsset) -> PHAssetResource? {
        guard asset.mediaType == .image, asset.mediaSubtypes.contains(.photoLive) else {
            return nil
        }
        let resources = PHAssetResource.assetResources(for: asset)
        return resources.first(where: { $0.type == .fullSizePairedVideo })
            ?? resources.first(where: { $0.type == .pairedVideo })
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
        let res = await saveMediaFileToLibraryWithReason(item: item, fileURL: fileURL, pairedLiveVideoURL: nil)
        return res.saved
    }

    /// Salva una foto, una Live Photo (`.HEIC` + `.MOV` accoppiato) o un video nel Rullino iOS in due fasi isolate:
    /// 1) Salva prima il file nel Rullino principale con `PHAssetResourceCreationOptions` (preservando data, GPS e Preferiti ❤️).
    ///    Se è presente `pairedLiveVideoURL`, tenta prima la ricostruzione atomica Live Photo; se iOS rifiuta l'accoppiamento
    ///    (es. su foto ritagliate), ripiega automaticamente sul salvataggio della foto singola senza perdere alcuno scatto.
    /// 2) Solo dopo il salvataggio, collega opzionalmente l'asset all'Album utente (`subtype: .albumRegular`).
    static func saveMediaFileToLibraryWithReason(
        item: ManifestItem,
        fileURL: URL,
        pairedLiveVideoURL: URL? = nil
    ) async -> (saved: Bool, savedAsLivePhoto: Bool, errorCode: String?) {
        let rwStatus = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        var isFullReadWrite = (rwStatus == .authorized)
        var canSaveToLibrary = (rwStatus == .authorized || rwStatus == .limited)
        if !canSaveToLibrary {
            let addStatus = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            canSaveToLibrary = (addStatus == .authorized || addStatus == .limited)
            isFullReadWrite = false
        }
        guard canSaveToLibrary else {
            return (false, false, "photo_permission_denied")
        }
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return (false, false, "missing_temp_file")
        }

        let safeName = URL(fileURLWithPath: item.fileName).lastPathComponent
        let fallbackExt = item.category == .VIDEOS ? "mp4" : "jpg"
        let finalName = safeName.isEmpty ? "media_\(UUID().uuidString).\(fallbackExt)" : safeName

        let healed = MediaTimelineHealer.resolveBestCaptureEpochMillis(
            fileName: finalName,
            reportedEpochMillis: item.capturedEpochMillis
        )
        let effectiveEpochMs = healed.epochMillis > 0 ? healed.epochMillis : item.capturedEpochMillis

        var effectiveFileURL = fileURL
        var healedExifTempURL: URL? = nil
        if item.category == .PHOTOS && effectiveEpochMs > 0 && pairedLiveVideoURL == nil {
            if let injected = MediaTimelineHealer.injectExifDateIntoImageIfNeeded(
                sourceURL: fileURL,
                epochMillis: effectiveEpochMs,
                forceOverwrite: healed.wasHealedFromFilename
            ) {
                healedExifTempURL = injected
                effectiveFileURL = injected
            }
        }
        defer {
            if let healedExifTempURL {
                try? FileManager.default.removeItem(at: healedExifTempURL)
            }
        }

        let creationDate: Date? = effectiveEpochMs > 0
            ? Date(timeIntervalSince1970: TimeInterval(effectiveEpochMs) / 1000.0)
            : nil
        let locationObj: CLLocation? = {
            if let lat = item.latitude, let lon = item.longitude {
                return CLLocation(latitude: lat, longitude: lon)
            }
            return nil
        }()
        let markFavorite = (item.isFavorite == true)

        final class LocalIdBox: @unchecked Sendable {
            var value: String?
        }
        let idBox = LocalIdBox()
        var savedLive = false

        // Percorso 1: ricostruzione nativa Live Photo (.photo + .pairedVideo nella stessa PHAssetCreationRequest)
        // Supporta sia Live Photo iPhone->iPhone (.mov nativo) sia Android Motion Photo (.mp4 -> .mov con content identifier QuickTime).
        if item.category == .PHOTOS,
           let incomingLiveURL = pairedLiveVideoURL,
           FileManager.default.fileExists(atPath: incomingLiveURL.path) {
            let crossOsPair = await iOSCrossOsLiveMotionBridge.prepareCrossOsLivePhotoPairIfNeeded(
                stillURL: effectiveFileURL,
                liveVideoURL: incomingLiveURL
            )
            defer {
                if let dir = crossOsPair?.cleanupDir {
                    try? FileManager.default.removeItem(at: dir)
                }
            }
            let photoURLForLive = crossOsPair?.stillURL ?? effectiveFileURL
            let movURLForLive = crossOsPair?.movURL ?? incomingLiveURL
            let rawLiveName = URL(fileURLWithPath: item.livePhotoVideoFileName ?? "").lastPathComponent
            let finalLiveName = (crossOsPair != nil || rawLiveName.isEmpty)
                ? "live_\(UUID().uuidString).mov"
                : rawLiveName
            do {
                try await PHPhotoLibrary.shared().performChanges {
                    let req = PHAssetCreationRequest.forAsset()
                    let photoOpts = PHAssetResourceCreationOptions()
                    photoOpts.originalFilename = finalName
                    photoOpts.shouldMoveFile = false
                    req.addResource(with: .photo, fileURL: photoURLForLive, options: photoOpts)

                    let liveOpts = PHAssetResourceCreationOptions()
                    liveOpts.originalFilename = finalLiveName
                    liveOpts.shouldMoveFile = false
                    req.addResource(with: .pairedVideo, fileURL: movURLForLive, options: liveOpts)

                    if let creationDate { req.creationDate = creationDate }
                    if let locationObj { req.location = locationObj }
                    if markFavorite { req.isFavorite = true }
                    idBox.value = req.placeholderForCreatedAsset?.localIdentifier
                }
                savedLive = true
            } catch {
                savedLive = false
            }
        }

        // Percorso 2: salvataggio foto singola o video 4K (usato anche come fallback infallibile se il pairing Live Photo fallisce)
        if !savedLive {
            do {
                try await PHPhotoLibrary.shared().performChanges {
                    let req = PHAssetCreationRequest.forAsset()
                    let resOpts = PHAssetResourceCreationOptions()
                    resOpts.originalFilename = finalName
                    resOpts.shouldMoveFile = false
                    if item.category == .VIDEOS {
                        req.addResource(with: .video, fileURL: effectiveFileURL, options: resOpts)
                    } else {
                        req.addResource(with: .photo, fileURL: effectiveFileURL, options: resOpts)
                    }
                    if let creationDate { req.creationDate = creationDate }
                    if let locationObj { req.location = locationObj }
                    if markFavorite { req.isFavorite = true }
                    idBox.value = req.placeholderForCreatedAsset?.localIdentifier
                }
            } catch {
                // Secondo tentativo minimale tramite URL immagine/video standard
                do {
                    try await PHPhotoLibrary.shared().performChanges {
                        let fallbackReq = item.category == .VIDEOS
                            ? PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: effectiveFileURL)
                            : PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: effectiveFileURL)
                        if let creationDate { fallbackReq?.creationDate = creationDate }
                        if let locationObj { fallbackReq?.location = locationObj }
                        if markFavorite { fallbackReq?.isFavorite = true }
                        idBox.value = fallbackReq?.placeholderForCreatedAsset?.localIdentifier
                    }
                } catch {
                    return (false, false, "photokit_save_failed")
                }
            }
        }

        // Associazione opzionale all'album utente in una transazione separata (non fallisce mai il salvataggio principale)
        let albumTitle = item.relativeAlbumOrFolder.trimmingCharacters(in: .whitespacesAndNewlines)
        let skipAlbumNames: Set<String> = ["", "iPhone_Camera", "Camera", "Recenti", "Recent"]
        if isFullReadWrite,
           !skipAlbumNames.contains(albumTitle),
           let assetId = idBox.value,
           let targetAlbum = fetchOrCreateAlbum(named: albumTitle),
           targetAlbum.canPerform(.addContent) {
            let assets = PHAsset.fetchAssets(withLocalIdentifiers: [assetId], options: nil)
            if assets.count > 0 {
                try? await PHPhotoLibrary.shared().performChanges {
                    if let albumChangeReq = PHAssetCollectionChangeRequest(for: targetAlbum) {
                        albumChangeReq.addAssets(assets)
                    }
                }
            }
        }

        return (true, savedLive, nil)
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

    private static let albumCacheLock = NSLock()
    private static var albumLocalIdentifierCache: [String: String] = [:]

    private static func fetchOrCreateAlbum(named title: String) -> PHAssetCollection? {
        albumCacheLock.lock()
        let cachedId = albumLocalIdentifierCache[title]
        albumCacheLock.unlock()

        if let cachedId {
            if let cachedAlbum = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [cachedId], options: nil).firstObject,
               cachedAlbum.canPerform(.addContent) {
                return cachedAlbum
            }
        }

        let fetchOptions = PHFetchOptions()
        fetchOptions.predicate = NSPredicate(format: "title = %@", title)
        let collections = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .albumRegular, options: fetchOptions)
        if let existing = collections.firstObject, existing.canPerform(.addContent) {
            albumCacheLock.lock()
            albumLocalIdentifierCache[title] = existing.localIdentifier
            albumCacheLock.unlock()
            return existing
        }
        var placeholderId: String?
        try? PHPhotoLibrary.shared().performChangesAndWait {
            let createReq = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: title)
            placeholderId = createReq.placeholderForCreatedAssetCollection.localIdentifier
        }
        guard let id = placeholderId,
              let created = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [id], options: nil).firstObject else {
            return nil
        }
        albumCacheLock.lock()
        albumLocalIdentifierCache[title] = created.localIdentifier
        albumCacheLock.unlock()
        return created
    }

    struct ScannedLibraryAssetEntry: @unchecked Sendable {
        let item: ManifestItem
        let asset: PHAsset
        let liveVideoBytes: Int64
        let isLocallyAvailable: Bool
    }

    /// Scansiona Foto, Live Photos e Video del Rullino iOS fuori dal Main Thread preservando Album utente, Preferiti (❤️),
    /// coordinate GPS e dimensione reale della clip Live Photo (`livePhotoVideoSizeBytes`) per parità 1:1 tra mittente e ricevente.
    /// Quando `allowCloudOnly == false` (predefinito), include SOLO elementi verificati localmente idonei al trasferimento.
    static func scanLibraryAssetsDetailed(
        includePhotos: Bool,
        includeVideos: Bool,
        allowCloudOnly: Bool = false
    ) async -> (items: [ScannedLibraryAssetEntry], iCloudOptimizedCount: Int) {
        guard includePhotos || includeVideos else { return ([], 0) }
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        guard status == .authorized || status == .limited else { return ([], 0) }

        return await Task.detached(priority: .userInitiated) {
            let albumMap = buildAssetAlbumMap()
            let opts = PHFetchOptions()
            opts.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            let fetched = PHAsset.fetchAssets(with: opts)
            var localEntries: [ScannedLibraryAssetEntry] = []
            var cloudEntries: [ScannedLibraryAssetEntry] = []
            var cloudOptimized = 0

            fetched.enumerateObjects { asset, idx, _ in
                let isVideo = asset.mediaType == .video
                let isPhoto = asset.mediaType == .image
                if (isVideo && !includeVideos) || (isPhoto && !includePhotos) || (!isVideo && !isPhoto) {
                    return
                }
                guard let chosen = bestTransferablePrimaryResource(for: asset, allowCloudOnly: allowCloudOnly) else {
                    if bestTransferablePrimaryResource(for: asset, allowCloudOnly: true) != nil {
                        cloudOptimized += 1
                    }
                    return
                }
                let primary = chosen.resource
                let isLocal = chosen.isLocallyAvailable
                if !isLocal {
                    cloudOptimized += 1
                }
                let pairedLive = isPhoto ? bestTransferablePairedLiveResource(for: asset, allowCloudOnly: allowCloudOnly) : nil
                let liveSize = pairedLive?.fileSize ?? 0
                let size = chosen.fileSize
                let createdMs = Int64((asset.creationDate?.timeIntervalSince1970 ?? 0) * 1000.0)
                let fileName = primary.originalFilename.isEmpty ? "media_\(idx).\(isVideo ? "mov" : "jpg")" : primary.originalFilename
                let albumName = albumMap[asset.localIdentifier] ?? "iPhone_Camera"
                let cat: TransferCategory = isVideo ? .VIDEOS : .PHOTOS
                let stableId = stableManifestItemId(
                    localIdentifier: asset.localIdentifier,
                    category: cat,
                    fallbackIndex: idx
                )
                let item = ManifestItem(
                    id: stableId,
                    category: cat,
                    fileName: fileName,
                    relativeAlbumOrFolder: albumName,
                    sizeBytes: size,
                    capturedEpochMillis: createdMs,
                    dedupKey: "\(fileName.lowercased())_\(size)_\(createdMs)",
                    mimeType: mimeTypeForFileName(fileName, isVideo: isVideo),
                    isFavorite: asset.isFavorite ? true : nil,
                    latitude: asset.location?.coordinate.latitude,
                    longitude: asset.location?.coordinate.longitude,
                    isLivePhoto: pairedLive != nil ? true : nil,
                    livePhotoVideoFileName: pairedLive?.resource.originalFilename,
                    livePhotoVideoSizeBytes: liveSize > 0 ? liveSize : nil
                )
                let entry = ScannedLibraryAssetEntry(
                    item: item,
                    asset: asset,
                    liveVideoBytes: max(0, liveSize),
                    isLocallyAvailable: isLocal
                )
                if isLocal {
                    localEntries.append(entry)
                } else {
                    cloudEntries.append(entry)
                }
            }
            return (localEntries + cloudEntries, cloudOptimized)
        }.value
    }

    static func scanLibraryAssetsWithMetadata(
        includePhotos: Bool,
        includeVideos: Bool
    ) async -> (items: [(ManifestItem, PHAsset)], iCloudOptimizedCount: Int) {
        let detailed = await scanLibraryAssetsDetailed(includePhotos: includePhotos, includeVideos: includeVideos)
        return (detailed.items.map { ($0.item, $0.asset) }, detailed.iCloudOptimizedCount)
    }

    static func stableManifestItemId(
        localIdentifier: String,
        category: TransferCategory,
        fallbackIndex: Int
    ) -> String {
        let prefix = category.rawValue.lowercased()
        let sanitized = String(localIdentifier.unicodeScalars.map { scalar -> Character in
            if CharacterSet.alphanumerics.contains(scalar) || scalar == "-" || scalar == "_" {
                return Character(scalar)
            }
            return "_"
        }).trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        return sanitized.isEmpty ? "\(prefix)_\(fallbackIndex)" : "\(prefix)_\(sanitized)"
    }

    static func scanLibraryAssets(includePhotos: Bool, includeVideos: Bool) async -> [(ManifestItem, PHAsset)] {
        let res = await scanLibraryAssetsWithMetadata(includePhotos: includePhotos, includeVideos: includeVideos)
        return res.items
    }

    private final class AsyncExportResumeGuard: @unchecked Sendable {
        private let lock = NSLock()
        private var resumed = false
        private var imageRequestId: PHImageRequestID? = nil
        private var degradedData: Data? = nil
        private var degradedExtension: String = "jpg"
        private let startTime: TimeInterval = Date().timeIntervalSinceReferenceDate
        private var lastActivityTime: TimeInterval = Date().timeIntervalSinceReferenceDate

        func setImageRequestId(_ id: PHImageRequestID) {
            lock.lock()
            imageRequestId = id
            lock.unlock()
        }

        func saveDegradedData(_ data: Data, fileExtension: String) {
            guard !data.isEmpty else { return }
            lock.lock()
            if data.count >= (degradedData?.count ?? 0) {
                degradedData = data
                degradedExtension = fileExtension
            }
            lastActivityTime = Date().timeIntervalSinceReferenceDate
            lock.unlock()
        }

        func consumeDegradedData() -> (Data, String)? {
            lock.lock()
            defer { lock.unlock() }
            guard let data = degradedData, !data.isEmpty else { return nil }
            degradedData = nil
            return (data, degradedExtension)
        }

        func touchActivity() {
            lock.lock()
            lastActivityTime = Date().timeIntervalSinceReferenceDate
            lock.unlock()
        }

        func isCompleted() -> Bool {
            lock.lock()
            let done = resumed
            lock.unlock()
            return done
        }

        func hasTimedOut(idleTimeout: TimeInterval, maxTotalTimeout: TimeInterval) -> Bool {
            let now = Date().timeIntervalSinceReferenceDate
            lock.lock()
            let done = resumed
            let idle = now - lastActivityTime
            let total = now - startTime
            lock.unlock()
            if done { return false }
            return idle >= idleTimeout || total >= maxTotalTimeout
        }

        func tryClaim(cancelPending: Bool = false) -> Bool {
            lock.lock()
            let shouldResume = !resumed
            resumed = true
            let iId = imageRequestId
            lock.unlock()
            if shouldResume && cancelPending, let iId {
                PHImageManager.default().cancelImageRequest(iId)
            }
            return shouldResume
        }

        func startActivityWatchdog(
            idleTimeout: TimeInterval,
            maxTotalTimeout: TimeInterval,
            onTimeout: @Sendable @escaping () -> Void
        ) {
            @Sendable func poll() {
                if self.isCompleted() { return }
                if self.hasTimedOut(idleTimeout: idleTimeout, maxTotalTimeout: maxTotalTimeout) {
                    if self.tryClaim(cancelPending: true) {
                        onTimeout()
                    }
                    return
                }
                DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 2.0) {
                    poll()
                }
            }
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + min(2.0, max(0.4, idleTimeout))) {
                poll()
            }
        }
    }

    private static func inferImageExtension(fromData data: Data, uti: String?) -> String {
        let lowerUti = (uti ?? "").lowercased()
        if lowerUti.contains("heic") { return "heic" }
        if lowerUti.contains("heif") { return "heif" }
        if lowerUti.contains("png") { return "png" }
        if lowerUti.contains("jpeg") || lowerUti.contains("jpg") { return "jpg" }
        if data.count >= 3 && data[0] == 0xFF && data[1] == 0xD8 && data[2] == 0xFF {
            return "jpg"
        }
        if data.count >= 4 && data[0] == 0x89 && data[1] == 0x50 && data[2] == 0x4E && data[3] == 0x47 {
            return "png"
        }
        return "jpg"
    }

    private static func writeTempImageData(_ data: Data, ext: String, prefix: String) -> URL? {
        guard !data.isEmpty else { return nil }
        let destURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)_\(UUID().uuidString).\(ext)")
        do {
            try data.write(to: destURL, options: .atomic)
            return destURL
        } catch {
            try? FileManager.default.removeItem(at: destURL)
            return nil
        }
    }

    /// Esporta un `PHAsset` su file temporaneo con livelli progressivi di resilienza iCloud + cache locale:
    /// 1) `PHAssetResourceManager` con monitoraggio attivo dell'avanzamento iCloud (non interrompe download attivi),
    /// 2) Risorsa alternativa dell'asset,
    /// 3) `PHImageManager` (`requestImageDataAndOrientation` `.current` e fallback `.original`), trattenendo l'eventuale anteprima ricevuta se iCloud cade,
    /// 4) Estrazione asincrona dalla cache locale di Foto (`.fastFormat` + `.opportunistic`, MAI `isSynchronous = true` che forza `.highQualityFormat`),
    /// 5) Per i video: `.highQualityFormat` -> `.mediumQualityFormat` -> `.fastFormat`, gestendo anche `AVComposition` (Slow-Mo/modificati).
    static func exportAssetToTempFile(_ asset: PHAsset, allowNetwork: Bool = true) async -> URL? {
        if let chosen = bestTransferablePrimaryResource(for: asset, allowCloudOnly: allowNetwork) {
            let primary = chosen.resource
            let isLocal = chosen.isLocallyAvailable
            let maxTimeout: TimeInterval = isLocal
                ? 60.0
                : (asset.mediaType == .video ? 420.0 : 180.0)
            let idleTimeout: TimeInterval = isLocal ? 35.0 : 25.0
            if let exported = await exportResourceToTempFile(
                primary,
                prefix: "ds_exp",
                allowNetwork: !isLocal && allowNetwork,
                idleTimeoutSeconds: idleTimeout,
                maxTotalSeconds: maxTimeout
            ) {
                return exported
            }
            if allowNetwork {
                try? await Task.sleep(nanoseconds: 200_000_000)
                let resources = PHAssetResource.assetResources(for: asset)
                let fallbackRes: PHAssetResource? = {
                    if asset.mediaType == .video {
                        return resources.first(where: { $0.type == .video && $0 != primary }) ?? primary
                    } else {
                        return resources.first(where: { $0.type == .photo && $0 != primary })
                            ?? resources.first(where: { $0.type == .alternatePhoto && $0 != primary })
                            ?? primary
                    }
                }()
                if let fallbackRes,
                   let exported = await exportResourceToTempFile(
                       fallbackRes,
                       prefix: "ds_exp_fb",
                       allowNetwork: true,
                       idleTimeoutSeconds: 18.0,
                       maxTotalSeconds: 120.0
                   ) {
                    return exported
                }
            }
        }

        if asset.mediaType == .image {
            if let highCurrent = await exportImageViaImageManager(
                asset,
                allowNetwork: allowNetwork,
                deliveryMode: .highQualityFormat,
                version: .current,
                idleTimeoutSeconds: allowNetwork ? 22.0 : 10.0,
                maxTotalSeconds: allowNetwork ? 150.0 : 20.0
            ) {
                return highCurrent
            }
            if let highOrig = await exportImageViaImageManager(
                asset,
                allowNetwork: allowNetwork,
                deliveryMode: .highQualityFormat,
                version: .original,
                idleTimeoutSeconds: allowNetwork ? 18.0 : 10.0,
                maxTotalSeconds: allowNetwork ? 90.0 : 20.0
            ) {
                return highOrig
            }
            return await exportBestLocalCachedImage(asset)
        } else if asset.mediaType == .video {
            if let highVid = await exportVideoViaImageManager(
                asset,
                allowNetwork: allowNetwork,
                deliveryMode: .highQualityFormat,
                version: .current,
                idleTimeoutSeconds: allowNetwork ? 25.0 : 15.0,
                maxTotalSeconds: allowNetwork ? 360.0 : 60.0
            ) {
                return highVid
            }
            if let medVid = await exportVideoViaImageManager(
                asset,
                allowNetwork: allowNetwork,
                deliveryMode: .mediumQualityFormat,
                version: .current,
                idleTimeoutSeconds: allowNetwork ? 20.0 : 12.0,
                maxTotalSeconds: allowNetwork ? 180.0 : 40.0
            ) {
                return medVid
            }
            if allowNetwork, let fastNetVid = await exportVideoViaImageManager(
                asset,
                allowNetwork: true,
                deliveryMode: .fastFormat,
                version: .original,
                idleTimeoutSeconds: 15.0,
                maxTotalSeconds: 90.0
            ) {
                return fastNetVid
            }
            return await exportVideoViaImageManager(
                asset,
                allowNetwork: false,
                deliveryMode: .fastFormat,
                version: .current,
                idleTimeoutSeconds: 12.0,
                maxTotalSeconds: 20.0
            )
        }
        return nil
    }

    private static func exportImageViaImageManager(
        _ asset: PHAsset,
        allowNetwork: Bool = true,
        deliveryMode: PHImageRequestOptionsDeliveryMode = .highQualityFormat,
        version: PHImageRequestOptionsVersion = .current,
        idleTimeoutSeconds: TimeInterval = 22.0,
        maxTotalSeconds: TimeInterval = 150.0
    ) async -> URL? {
        await withCheckedContinuation { (continuation: CheckedContinuation<URL?, Never>) in
            let guardBox = AsyncExportResumeGuard()
            let opts = PHImageRequestOptions()
            opts.isNetworkAccessAllowed = allowNetwork
            opts.deliveryMode = deliveryMode
            opts.version = version
            opts.resizeMode = .none
            opts.isSynchronous = false
            opts.progressHandler = { _, _, _, _ in
                guardBox.touchActivity()
            }

            guardBox.startActivityWatchdog(idleTimeout: idleTimeoutSeconds, maxTotalTimeout: maxTotalSeconds) {
                if let (fallbackData, fallbackExt) = guardBox.consumeDegradedData(),
                   let url = Self.writeTempImageData(fallbackData, ext: fallbackExt, prefix: "ds_imgdeg") {
                    continuation.resume(returning: url)
                } else {
                    continuation.resume(returning: nil)
                }
            }

            let reqId = PHImageManager.default().requestImageDataAndOrientation(for: asset, options: opts) { data, dataUTI, _, info in
                let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                if let data, !data.isEmpty, isDegraded && deliveryMode == .highQualityFormat {
                    let degExt = Self.inferImageExtension(fromData: data, uti: dataUTI)
                    guardBox.saveDegradedData(data, fileExtension: degExt)
                    return
                }
                guard guardBox.tryClaim() else { return }
                if let data, !data.isEmpty {
                    let resolvedExt = Self.inferImageExtension(fromData: data, uti: dataUTI)
                    if let url = Self.writeTempImageData(data, ext: resolvedExt, prefix: "ds_imgmgr") {
                        continuation.resume(returning: url)
                        return
                    }
                }
                if let (fallbackData, fallbackExt) = guardBox.consumeDegradedData(),
                   let url = Self.writeTempImageData(fallbackData, ext: fallbackExt, prefix: "ds_imgdeg") {
                    continuation.resume(returning: url)
                } else {
                    continuation.resume(returning: nil)
                }
            }
            guardBox.setImageRequestId(reqId)
        }
    }

    /// Recupera la migliore copia già presente nella cache locale di Foto (asincrono con `.fastFormat` / `.opportunistic`,
    /// evitando `isSynchronous = true` che in PhotoKit forza `.highQualityFormat` e restituisce `nil` sui file solo su iCloud).
    private static func exportBestLocalCachedImage(_ asset: PHAsset) async -> URL? {
        for version in [PHImageRequestOptionsVersion.current, .unadjusted] {
            if let fastDataURL = await exportImageViaImageManager(
                asset,
                allowNetwork: false,
                deliveryMode: .fastFormat,
                version: version,
                idleTimeoutSeconds: 4.5,
                maxTotalSeconds: 6.0
            ) {
                return fastDataURL
            }
        }

        for delivery in [PHImageRequestOptionsDeliveryMode.fastFormat, .opportunistic] {
            if let renderedURL = await exportCachedUIImageAsync(asset, deliveryMode: delivery) {
                return renderedURL
            }
        }
        return nil
    }

    private static func exportCachedUIImageAsync(
        _ asset: PHAsset,
        deliveryMode: PHImageRequestOptionsDeliveryMode
    ) async -> URL? {
        await withCheckedContinuation { (continuation: CheckedContinuation<URL?, Never>) in
            let guardBox = AsyncExportResumeGuard()
            let opts = PHImageRequestOptions()
            opts.isNetworkAccessAllowed = false
            opts.isSynchronous = false
            opts.deliveryMode = deliveryMode
            opts.resizeMode = .fast
            opts.version = .current

            guardBox.startActivityWatchdog(idleTimeout: 3.5, maxTotalTimeout: 4.5) {
                if let (fallbackData, fallbackExt) = guardBox.consumeDegradedData(),
                   let url = Self.writeTempImageData(fallbackData, ext: fallbackExt, prefix: "ds_cached_ui") {
                    continuation.resume(returning: url)
                } else {
                    continuation.resume(returning: nil)
                }
            }

            let targetSize = CGSize(width: 2048, height: 2048)
            let reqId = PHImageManager.default().requestImage(
                for: asset,
                targetSize: targetSize,
                contentMode: .aspectFit,
                options: opts
            ) { img, info in
                let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                if let img,
                   img.size.width >= 64,
                   img.size.height >= 64,
                   let jpeg = img.jpegData(compressionQuality: 0.92),
                   !jpeg.isEmpty {
                    if isDegraded && deliveryMode == .opportunistic {
                        guardBox.saveDegradedData(jpeg, fileExtension: "jpg")
                        return
                    }
                    guard guardBox.tryClaim() else { return }
                    continuation.resume(returning: Self.writeTempImageData(jpeg, ext: "jpg", prefix: "ds_cached_ui"))
                    return
                }
                if !isDegraded {
                    guard guardBox.tryClaim() else { return }
                    if let (fallbackData, fallbackExt) = guardBox.consumeDegradedData(),
                       let url = Self.writeTempImageData(fallbackData, ext: fallbackExt, prefix: "ds_cached_ui") {
                        continuation.resume(returning: url)
                    } else {
                        continuation.resume(returning: nil)
                    }
                }
            }
            guardBox.setImageRequestId(reqId)
        }
    }

    private static func exportVideoViaImageManager(
        _ asset: PHAsset,
        allowNetwork: Bool = true,
        deliveryMode: PHVideoRequestOptionsDeliveryMode = .highQualityFormat,
        version: PHVideoRequestOptionsVersion = .current,
        idleTimeoutSeconds: TimeInterval = 25.0,
        maxTotalSeconds: TimeInterval = 360.0
    ) async -> URL? {
        await withCheckedContinuation { (continuation: CheckedContinuation<URL?, Never>) in
            let guardBox = AsyncExportResumeGuard()
            let opts = PHVideoRequestOptions()
            opts.isNetworkAccessAllowed = allowNetwork
            opts.deliveryMode = deliveryMode
            opts.version = version
            opts.progressHandler = { _, _, _, _ in
                guardBox.touchActivity()
            }

            guardBox.startActivityWatchdog(idleTimeout: idleTimeoutSeconds, maxTotalTimeout: maxTotalSeconds) {
                continuation.resume(returning: nil)
            }

            let reqId = PHImageManager.default().requestAVAsset(forVideo: asset, options: opts) { avAsset, _, _ in
                guard guardBox.tryClaim() else { return }
                if let urlAsset = avAsset as? AVURLAsset {
                    let ext = urlAsset.url.pathExtension.isEmpty ? "mov" : urlAsset.url.pathExtension
                    let destURL = FileManager.default.temporaryDirectory
                        .appendingPathComponent("ds_vidmgr_\(UUID().uuidString).\(ext)")
                    do {
                        try FileManager.default.copyItem(at: urlAsset.url, to: destURL)
                        continuation.resume(returning: destURL)
                    } catch {
                        try? FileManager.default.removeItem(at: destURL)
                        continuation.resume(returning: nil)
                    }
                    return
                }
                guard let avAsset,
                      let exportSession = AVAssetExportSession(asset: avAsset, presetName: AVAssetExportPresetHighestQuality)
                        ?? AVAssetExportSession(asset: avAsset, presetName: AVAssetExportPreset1280x720) else {
                    continuation.resume(returning: nil)
                    return
                }
                let destURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent("ds_vidcomp_\(UUID().uuidString).mp4")
                try? FileManager.default.removeItem(at: destURL)
                exportSession.outputURL = destURL
                exportSession.outputFileType = .mp4
                exportSession.shouldOptimizeForNetworkUse = false
                exportSession.exportAsynchronously {
                    if exportSession.status == .completed && FileManager.default.fileExists(atPath: destURL.path) {
                        continuation.resume(returning: destURL)
                    } else {
                        try? FileManager.default.removeItem(at: destURL)
                        continuation.resume(returning: nil)
                    }
                }
            }
            guardBox.setImageRequestId(reqId)
        }
    }

    /// Esporta la componente video `.MOV` accoppiata di una Live Photo su file temporaneo.
    static func exportLivePairedVideoToTempFile(_ asset: PHAsset, allowNetwork: Bool = true) async -> URL? {
        guard let paired = bestTransferablePairedLiveResource(for: asset, allowCloudOnly: allowNetwork)?.resource else { return nil }
        let isLocal = resourceIsLocallyAvailable(paired)
        return await exportResourceToTempFile(
            paired,
            prefix: "ds_live",
            allowNetwork: !isLocal && allowNetwork,
            idleTimeoutSeconds: isLocal ? 20.0 : 18.0,
            maxTotalSeconds: isLocal ? 45.0 : 90.0
        )
    }

    private static func exportResourceToTempFile(
        _ resource: PHAssetResource,
        prefix: String,
        allowNetwork: Bool = true,
        idleTimeoutSeconds: TimeInterval = 25.0,
        maxTotalSeconds: TimeInterval = 180.0
    ) async -> URL? {
        let safeName = URL(fileURLWithPath: resource.originalFilename).lastPathComponent
        let destURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)_\(UUID().uuidString)_\(safeName.isEmpty ? "asset.bin" : safeName)")
        try? FileManager.default.removeItem(at: destURL)

        return await withCheckedContinuation { (continuation: CheckedContinuation<URL?, Never>) in
            let guardBox = AsyncExportResumeGuard()
            let opts = PHAssetResourceRequestOptions()
            opts.isNetworkAccessAllowed = allowNetwork
            opts.progressHandler = { _ in
                guardBox.touchActivity()
            }

            guardBox.startActivityWatchdog(idleTimeout: idleTimeoutSeconds, maxTotalTimeout: maxTotalSeconds) {
                try? FileManager.default.removeItem(at: destURL)
                continuation.resume(returning: nil)
            }

            PHAssetResourceManager.default().writeData(
                for: resource,
                toFile: destURL,
                options: opts
            ) { error in
                guard guardBox.tryClaim() else {
                    try? FileManager.default.removeItem(at: destURL)
                    return
                }
                if error != nil || !FileManager.default.fileExists(atPath: destURL.path) {
                    try? FileManager.default.removeItem(at: destURL)
                    continuation.resume(returning: nil)
                } else {
                    let size = (try? FileManager.default.attributesOfItem(atPath: destURL.path)[.size] as? Int64) ?? 0
                    if size <= 0 {
                        try? FileManager.default.removeItem(at: destURL)
                        continuation.resume(returning: nil)
                    } else {
                        continuation.resume(returning: destURL)
                    }
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
        let targetDir = docsRoot
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
    static func isPasswordsCsvFile(_ fileName: String) -> Bool {
        URL(fileURLWithPath: fileName).pathExtension.lowercased() == "csv"
    }

    static func mimeForExtension(_ ext: String) -> String {
        switch ext.lowercased() {
        case "pdf": return "application/pdf"
        case "zip": return "application/zip"
        case "rar": return "application/vnd.rar"
        case "7z": return "application/x-7z-compressed"
        case "txt", "md", "log": return "text/plain"
        case "csv": return "text/csv"
        case "json": return "application/json"
        case "xml": return "application/xml"
        case "html", "htm": return "text/html"
        case "rtf": return "application/rtf"
        case "epub": return "application/epub+zip"
        case "doc": return "application/msword"
        case "docx": return "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
        case "xls": return "application/vnd.ms-excel"
        case "xlsx": return "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
        case "ppt": return "application/vnd.ms-powerpoint"
        case "pptx": return "application/vnd.openxmlformats-officedocument.presentationml.presentation"
        case "vcf": return "text/vcard"
        case "ics": return "text/calendar"
        case "m4a", "aac": return "audio/mp4"
        case "mp3": return "audio/mpeg"
        case "wav": return "audio/wav"
        case "flac": return "audio/flac"
        case "opus", "ogg": return "audio/ogg"
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

    private static let folderBookmarksDefaultsKey = "directswitch_ios_folder_bookmarks_v1"

    private static let genericContainerFolders: Set<String> = [
        "mobile documents",
        "com~apple~clouddocs",
        "inbox",
        "tmp",
        "temp",
        "directswitch_sharedvault",
        "directswitch_documenti",
        "file provider storage",
        "localstorage",
        "shared",
        "documents",
        "on my iphone",
        "su iphone"
    ]

    /// Ricostruisce in sicurezza la gerarchia di sottocartelle dentro `Su iPhone -> DirectSwitch`.
    static func sanitizedRelativeComponents(_ rawFolder: String) -> [String] {
        let normalized = rawFolder.replacingOccurrences(of: "\\", with: "/")
        return normalized
            .split(separator: "/")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0 != "." && $0 != ".." }
    }

    static func normalizedFolderString(_ rawFolder: String, fallback: String = "Documenti") -> String {
        let comps = sanitizedRelativeComponents(rawFolder)
        return comps.isEmpty ? fallback : comps.joined(separator: "/")
    }

    static func targetDirectory(for item: ManifestItem) -> URL? {
        guard let docsRoot = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return nil
        }
        var dir = docsRoot
        if item.category == .WHATSAPP_VAULT {
            dir = dir.appendingPathComponent("WhatsApp_Vault", isDirectory: true)
        } else {
            let comps = sanitizedRelativeComponents(item.relativeAlbumOrFolder)
            if comps.isEmpty {
                dir = dir.appendingPathComponent("Documenti", isDirectory: true)
            } else {
                for comp in comps {
                    dir = dir.appendingPathComponent(comp, isDirectory: true)
                }
            }
        }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func existingEqualSizeMatch(at exactURL: URL, incomingSize: Int64) -> Bool {
        guard incomingSize > 0, FileManager.default.fileExists(atPath: exactURL.path),
              let attrs = try? FileManager.default.attributesOfItem(atPath: exactURL.path) else {
            return false
        }
        let existingSize = (attrs[.size] as? Int64) ?? (attrs[.size] as? NSNumber)?.int64Value ?? -1
        return existingSize == incomingSize
    }

    /// Salva un file decifrato su disco nella cartella visibile in "File -> Su iPhone -> DirectSwitch",
    /// preservando esattamente le cartelle originali ed evitando duplicati identici.
    static func saveDocumentFile(item: ManifestItem, sourceFileURL: URL) -> Bool {
        guard let targetDir = targetDirectory(for: item) else { return false }
        let safeFileName = URL(fileURLWithPath: item.fileName).lastPathComponent
        let preferredName = safeFileName.isEmpty ? "documento_\(item.id)" : safeFileName
        let exactDestURL = targetDir.appendingPathComponent(preferredName)

        let sourceAttrs = try? FileManager.default.attributesOfItem(atPath: sourceFileURL.path)
        let sourceSize = (sourceAttrs?[.size] as? Int64) ?? (sourceAttrs?[.size] as? NSNumber)?.int64Value ?? item.sizeBytes
        if existingEqualSizeMatch(at: exactDestURL, incomingSize: sourceSize) {
            try? FileManager.default.removeItem(at: sourceFileURL)
            return true
        }

        let destURL = uniqueDestinationURL(in: targetDir, preferredFileName: preferredName)
        do {
            if FileManager.default.fileExists(atPath: destURL.path) {
                try FileManager.default.removeItem(at: destURL)
            }
            try FileManager.default.moveItem(at: sourceFileURL, to: destURL)
            return true
        } catch {
            do {
                try FileManager.default.copyItem(at: sourceFileURL, to: destURL)
                try? FileManager.default.removeItem(at: sourceFileURL)
                return true
            } catch {
                return false
            }
        }
    }

    static func saveDocument(item: ManifestItem, plainData: Data) -> Bool {
        guard let targetDir = targetDirectory(for: item) else { return false }
        let safeFileName = URL(fileURLWithPath: item.fileName).lastPathComponent
        let preferredName = safeFileName.isEmpty ? "documento_\(item.id)" : safeFileName
        let exactDestURL = targetDir.appendingPathComponent(preferredName)
        if existingEqualSizeMatch(at: exactDestURL, incomingSize: Int64(plainData.count)) {
            return true
        }
        let destURL = uniqueDestinationURL(in: targetDir, preferredFileName: preferredName)
        do {
            try plainData.write(to: destURL, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    private static func documentDedupTokens(folder: String, fileName: String, sizeBytes: Int64, modMs: Int64) -> [String] {
        let folderKey = normalizedFolderString(folder).lowercased()
        let nameKey = fileName.lowercased()
        let base = "\(folderKey)/\(nameKey)_\(sizeBytes)"
        return [base, "\(base)_\(modMs)"]
    }

    static func existingDocumentDedupKeys() -> Set<String> {
        guard let docsRoot = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return []
        }
        var keys: Set<String> = []
        let resolvedRoot = docsRoot.resolvingSymlinksInPath().path
        if let enumerator = FileManager.default.enumerator(
            at: docsRoot,
            includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) {
            for case let childURL as URL in enumerator {
                let relFolder = computeRelativeFolder(
                    childURL: childURL,
                    resolvedRootPath: resolvedRoot,
                    baseFolderName: ""
                )
                if relFolder == "Inbox" || relFolder.hasPrefix("Inbox/") {
                    continue
                }
                let vals = try? childURL.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey])
                if vals?.isDirectory == true { continue }
                let info = inspectReadableFile(at: childURL)
                guard info.readable, info.size > 0 else { continue }
                let modMs = Int64(info.modDate.timeIntervalSince1970 * 1000.0)
                for token in documentDedupTokens(
                    folder: relFolder,
                    fileName: childURL.lastPathComponent,
                    sizeBytes: info.size,
                    modMs: modMs
                ) {
                    keys.insert(token)
                }
            }
        }
        return keys
    }

    // MARK: - Destinazioni scrivibili esterne su iPhone ricevente (Su iPhone / iCloud Drive / Drive)

    struct ReceiverAuthorizedDestination {
        let url: URL
        let locationLabel: String
        let isContainerRoot: Bool
        let matchSegments: [String]
        let displayRoot: String
        let dedupFolderRoot: String
    }

    final class ReceiverDestinationSession {
        private var scopedURLs: [URL] = []
        private(set) var destinations: [ReceiverAuthorizedDestination] = []
        private(set) var fallbackRoot: ReceiverAuthorizedDestination?

        init(
            destinations: [ReceiverAuthorizedDestination] = [],
            fallbackRoot: ReceiverAuthorizedDestination? = nil,
            scopedURLs: [URL] = []
        ) {
            self.destinations = destinations
            self.fallbackRoot = fallbackRoot
            self.scopedURLs = scopedURLs
        }

        deinit {
            close()
        }

        func close() {
            for url in scopedURLs {
                url.stopAccessingSecurityScopedResource()
            }
            scopedURLs.removeAll()
            destinations.removeAll()
            fallbackRoot = nil
        }

        static func openFromPersistedBookmarks() -> ReceiverDestinationSession {
            let defaults = UserDefaults.standard
            var scoped: [URL] = []
            var resolvedDestinations: [ReceiverAuthorizedDestination] = []
            var seenStdPaths: Set<String> = []

            let rawList = (defaults.array(forKey: receiverDestinationBookmarksKey) as? [Data]) ?? []
            var validList: [Data] = []
            for data in rawList {
                var stale = false
                if let url = try? URL(
                    resolvingBookmarkData: data,
                    options: [],
                    relativeTo: nil,
                    bookmarkDataIsStale: &stale
                ) {
                    let stdPath = url.standardizedFileURL.path
                    guard seenStdPaths.insert(stdPath).inserted else { continue }
                    if url.startAccessingSecurityScopedResource() {
                        scoped.append(url)
                    }
                    if let dest = buildAuthorizedDestination(for: url) {
                        resolvedDestinations.append(dest)
                    }
                    if stale, let refreshed = createBookmarkDataCompat(for: url) {
                        validList.append(refreshed)
                    } else {
                        validList.append(data)
                    }
                }
            }
            if validList.count != rawList.count {
                defaults.set(validList, forKey: receiverDestinationBookmarksKey)
            }

            liveSessionLock.lock()
            let liveReceiverEntries = Array(liveSessionReceiverURLs.values)
            let liveFallbackEntry = liveSessionFallbackRootURL
            liveSessionLock.unlock()

            for entry in liveReceiverEntries {
                let stdPath = entry.url.standardizedFileURL.path
                guard seenStdPaths.insert(stdPath).inserted else { continue }
                if !entry.keepScopeOpen, entry.url.startAccessingSecurityScopedResource() {
                    scoped.append(entry.url)
                }
                if let dest = buildAuthorizedDestination(for: entry.url) {
                    resolvedDestinations.append(dest)
                }
            }

            var resolvedFallback: ReceiverAuthorizedDestination? = nil
            if let fallbackData = defaults.data(forKey: receiverFallbackBookmarkKey) {
                var stale = false
                if let fUrl = try? URL(
                    resolvingBookmarkData: fallbackData,
                    options: [],
                    relativeTo: nil,
                    bookmarkDataIsStale: &stale
                ) {
                    if fUrl.startAccessingSecurityScopedResource() {
                        scoped.append(fUrl)
                    }
                    resolvedFallback = buildAuthorizedDestination(for: fUrl)
                    if stale, let refreshed = createBookmarkDataCompat(for: fUrl) {
                        defaults.set(refreshed, forKey: receiverFallbackBookmarkKey)
                    }
                }
            } else if let fbEntry = liveFallbackEntry {
                if !fbEntry.keepScopeOpen, fbEntry.url.startAccessingSecurityScopedResource() {
                    scoped.append(fbEntry.url)
                }
                resolvedFallback = buildAuthorizedDestination(for: fbEntry.url)
            }

            return ReceiverDestinationSession(
                destinations: resolvedDestinations,
                fallbackRoot: resolvedFallback,
                scopedURLs: scoped
            )
        }
    }

    private static let receiverDestinationBookmarksKey = "directswitch_receiver_dest_bookmarks_v1"
    private static let receiverFallbackBookmarkKey = "directswitch_receiver_fallback_bookmark_v1"
    private static let liveSessionLock = NSLock()
    private static var liveSessionReceiverURLs: [String: (url: URL, keepScopeOpen: Bool)] = [:]
    private static var liveSessionFallbackRootURL: (url: URL, keepScopeOpen: Bool)? = nil
    private static var liveSessionPositionURLs: [String: (url: URL, keepScopeOpen: Bool)] = [:]

    private static func createBookmarkDataCompat(for url: URL) -> Data? {
        if let minimal = try? url.bookmarkData(
            options: .minimalBookmark,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) {
            return minimal
        }
        return try? url.bookmarkData(
            options: [],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }

    static func isTemporaryStagedFile(_ url: URL) -> Bool {
        let stagingPath = stagingVaultDirectory().resolvingSymlinksInPath().path
        let filePath = url.resolvingSymlinksInPath().path
        return filePath.hasPrefix(stagingPath + "/")
    }

    static func coordinatedRead<T>(at url: URL, _ accessor: (URL) throws -> T) throws -> T {
        var coordError: NSError?
        var bodyResult: Result<T, Error>?
        let coordinator = NSFileCoordinator(filePresenter: nil)
        coordinator.coordinate(readingItemAt: url, options: [.withoutChanges], error: &coordError) { readURL in
            bodyResult = Result { try accessor(readURL) }
        }
        if let res = bodyResult {
            return try res.get()
        }
        return try accessor(url)
    }

    private static let folderAliasGroups: [[String]] = [
        ["download", "downloads", "scaricati"],
        ["documents", "documenti"],
        ["pictures", "immagini", "photos", "foto"],
        ["movies", "filmati", "videos", "video"],
        ["music", "musica", "audio"],
        ["desktop", "scrivania"]
    ]

    private static let volumeRootPrefixesToStrip: Set<String> = [
        "memoria_interna", "scheda_sd", "su_iphone", "memoria_locale"
    ]

    static func canonicalFolderSegment(_ segment: String) -> String {
        let lower = segment.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        for group in folderAliasGroups where group.contains(lower) {
            return group[0]
        }
        return lower
    }

    static func buildAuthorizedDestination(for url: URL) -> ReceiverAuthorizedDestination? {
        if let vals = try? url.resourceValues(forKeys: [.isDirectoryKey]), vals.isDirectory == false {
            return nil
        }
        var isDir: ObjCBool = false
        let resolvedPath = url.resolvingSymlinksInPath().path
        if FileManager.default.fileExists(atPath: resolvedPath, isDirectory: &isDir), !isDir.boolValue {
            return nil
        }
        let classified = classifyPositionBaseFolder(for: url, isDirectory: true)
        let baseComps = sanitizedRelativeComponents(classified.baseFolder)
        let isContainer = classified.baseFolder.isEmpty
            || classified.baseFolder == "iCloud_Drive"
            || classified.baseFolder == "Su_iPhone"
            || classified.baseFolder == "Memoria_Locale"

        let matchComps: [String]
        let leafLabel: String
        let dedupRoot: String
        if isContainer {
            matchComps = []
            leafLabel = ""
            dedupRoot = classified.baseFolder
        } else {
            let trimmedForMatch: [String]
            if baseComps.first?.lowercased() == "icloud_drive" {
                trimmedForMatch = Array(baseComps.dropFirst())
            } else {
                trimmedForMatch = baseComps
            }
            matchComps = trimmedForMatch.isEmpty ? baseComps : trimmedForMatch
            leafLabel = matchComps.joined(separator: "/")
            dedupRoot = baseComps.joined(separator: "/")
        }

        let displayRoot = leafLabel.isEmpty
            ? classified.locationLabel
            : "\(classified.locationLabel) → \(leafLabel)"

        return ReceiverAuthorizedDestination(
            url: url,
            locationLabel: classified.locationLabel,
            isContainerRoot: isContainer,
            matchSegments: matchComps.map { $0.lowercased() },
            displayRoot: displayRoot,
            dedupFolderRoot: dedupRoot
        )
    }

    @discardableResult
    static func authorizeReceiverDestinationBookmarks(_ urls: [URL]) -> Int {
        let defaults = UserDefaults.standard
        var existingData = (defaults.array(forKey: receiverDestinationBookmarksKey) as? [Data]) ?? []
        var seenPaths = Set(existingData.compactMap { data -> String? in
            var stale = false
            return (try? URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &stale))?.standardizedFileURL.path
        })
        for url in urls where url.isFileURL {
            let scoped = url.startAccessingSecurityScopedResource()
            if let vals = try? url.resourceValues(forKeys: [.isDirectoryKey]), vals.isDirectory == false {
                if scoped { url.stopAccessingSecurityScopedResource() }
                continue
            }
            let stdPath = url.standardizedFileURL.path
            if let bookmark = createBookmarkDataCompat(for: url) {
                if seenPaths.insert(stdPath).inserted {
                    existingData.append(bookmark)
                }
                liveSessionLock.lock()
                liveSessionReceiverURLs[stdPath] = (url, false)
                liveSessionLock.unlock()
                if scoped { url.stopAccessingSecurityScopedResource() }
            } else {
                liveSessionLock.lock()
                liveSessionReceiverURLs[stdPath] = (url, scoped)
                liveSessionLock.unlock()
            }
        }
        defaults.set(existingData, forKey: receiverDestinationBookmarksKey)
        liveSessionLock.lock()
        let total = Set(seenPaths).union(liveSessionReceiverURLs.keys).count
        liveSessionLock.unlock()
        return total
    }

    @discardableResult
    static func setReceiverFallbackRootBookmark(_ urls: [URL]) -> Bool {
        guard let url = urls.first, url.isFileURL else { return false }
        let scoped = url.startAccessingSecurityScopedResource()
        if let vals = try? url.resourceValues(forKeys: [.isDirectoryKey]), vals.isDirectory == false {
            if scoped { url.stopAccessingSecurityScopedResource() }
            return false
        }
        if let bookmark = createBookmarkDataCompat(for: url) {
            UserDefaults.standard.set(bookmark, forKey: receiverFallbackBookmarkKey)
            liveSessionLock.lock()
            if let old = liveSessionFallbackRootURL, old.keepScopeOpen {
                old.url.stopAccessingSecurityScopedResource()
            }
            liveSessionFallbackRootURL = (url, false)
            liveSessionLock.unlock()
            if scoped { url.stopAccessingSecurityScopedResource() }
            return true
        } else {
            liveSessionLock.lock()
            if let old = liveSessionFallbackRootURL, old.keepScopeOpen {
                old.url.stopAccessingSecurityScopedResource()
            }
            liveSessionFallbackRootURL = (url, scoped)
            liveSessionLock.unlock()
            return true
        }
    }

    static func receiverDestinationsSummary() -> (destinations: [String], fallbackRoot: String?) {
        let session = ReceiverDestinationSession.openFromPersistedBookmarks()
        defer { session.close() }
        return (
            destinations: session.destinations.map(\.displayRoot),
            fallbackRoot: session.fallbackRoot?.displayRoot
        )
    }

    static func clearReceiverDestinations() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: receiverDestinationBookmarksKey)
        defaults.removeObject(forKey: receiverFallbackBookmarkKey)
        liveSessionLock.lock()
        for entry in liveSessionReceiverURLs.values where entry.keepScopeOpen {
            entry.url.stopAccessingSecurityScopedResource()
        }
        liveSessionReceiverURLs.removeAll()
        if let fb = liveSessionFallbackRootURL, fb.keepScopeOpen {
            fb.url.stopAccessingSecurityScopedResource()
        }
        liveSessionFallbackRootURL = nil
        liveSessionLock.unlock()
    }

    static func resolveWritableTargetDirectory(
        for item: ManifestItem,
        destinations: [ReceiverAuthorizedDestination],
        fallbackRoot: ReceiverAuthorizedDestination?
    ) -> (directoryURL: URL, displayFolder: String, isExternal: Bool)? {
        let rawComps = item.category == .WHATSAPP_VAULT
            ? ["WhatsApp_Vault"]
            : sanitizedRelativeComponents(item.relativeAlbumOrFolder)
        let incomingWantsICloud = rawComps.first?.lowercased() == "icloud_drive"

        var candidateCompsList: [[String]] = []
        if !rawComps.isEmpty {
            candidateCompsList.append(rawComps)
            if let firstLower = rawComps.first?.lowercased(),
               (volumeRootPrefixesToStrip.contains(firstLower)
                || firstLower == "icloud_drive"
                || firstLower.hasPrefix("archivio_usb_")
                || firstLower.hasPrefix("sd_")) {
                let stripped = Array(rawComps.dropFirst())
                if !stripped.isEmpty {
                    candidateCompsList.append(stripped)
                }
            }
        }

        // 1. Corrispondenza più lunga con una posizione/cartella reale autorizzata (es. Download -> Su iPhone/Download, iCloud_Drive/Lavoro -> iCloud Drive/Lavoro)
        var matchPool = destinations
        if let fb = fallbackRoot {
            matchPool.append(fb)
        }
        var bestMatch: (dest: ReceiverAuthorizedDestination, consumedCount: Int, remaining: [String], score: Int)? = nil
        for dest in matchPool {
            if dest.isContainerRoot {
                let destIsICloud = dest.locationLabel == "iCloud Drive"
                if (destIsICloud && incomingWantsICloud) || (!destIsICloud && !incomingWantsICloud) {
                    let subComps = (destIsICloud && incomingWantsICloud) ? Array(rawComps.dropFirst()) : rawComps
                    let cleanSub = subComps.isEmpty ? ["Documenti"] : subComps
                    let score = 500 + (destIsICloud == incomingWantsICloud ? 50 : 0)
                    if bestMatch == nil || score > bestMatch!.score {
                        bestMatch = (dest, rawComps.count, cleanSub, score)
                    }
                }
                continue
            }

            let pattern = dest.matchSegments
            guard !pattern.isEmpty else { continue }

            for candidate in candidateCompsList {
                // Cerca corrispondenza come prefisso (priorità massima) o come sottosequenza all'inizio del percorso effettivo
                if candidate.count >= pattern.count {
                    let matchedPrefix = zip(candidate.prefix(pattern.count), pattern).allSatisfy {
                        canonicalFolderSegment($0.0) == canonicalFolderSegment($0.1)
                    }
                    if matchedPrefix {
                        let remaining = Array(candidate.dropFirst(pattern.count))
                        let exactOriginBonus = ((dest.locationLabel == "iCloud Drive") == incomingWantsICloud) ? 40 : 0
                        let fullMatchBonus = (candidate.count == rawComps.count) ? 20 : 10
                        let score = 1000 + pattern.count * 100 + exactOriginBonus + fullMatchBonus
                        if bestMatch == nil || score > bestMatch!.score {
                            bestMatch = (dest, pattern.count, remaining, score)
                        }
                    }
                }
                // Inoltre verifica se una sotto-cartella del percorso corrisponde alla cartella autorizzata (es. root/Azienda/2026 -> Azienda autorizzata)
                if pattern.count == 1, candidate.count > 1,
                   let matchIdx = candidate.firstIndex(where: { canonicalFolderSegment($0) == canonicalFolderSegment(pattern[0]) }),
                   matchIdx > 0 {
                    let remaining = Array(candidate.dropFirst(matchIdx + 1))
                    let score = 700 + (((dest.locationLabel == "iCloud Drive") == incomingWantsICloud) ? 30 : 0)
                    if bestMatch == nil || score > bestMatch!.score {
                        bestMatch = (dest, matchIdx + 1, remaining, score)
                    }
                }
            }
        }

        if let best = bestMatch {
            var dir = best.dest.url
            for seg in best.remaining {
                dir = dir.appendingPathComponent(seg, isDirectory: true)
            }
            let display = best.remaining.isEmpty
                ? best.dest.displayRoot
                : "\(best.dest.displayRoot)/\(best.remaining.joined(separator: "/"))"
            return (dir, display, true)
        }

        // 2. Cartella base scelta dal cliente su Su iPhone / iCloud Drive per eventuali cartelle nuove non ancora esistenti
        if let fb = fallbackRoot, item.category != .WHATSAPP_VAULT {
            let cleanComps: [String]
            if fb.isContainerRoot && fb.locationLabel == "iCloud Drive" && incomingWantsICloud {
                cleanComps = Array(rawComps.dropFirst())
            } else {
                cleanComps = rawComps
            }
            let effectiveComps = cleanComps.isEmpty ? ["Documenti"] : cleanComps
            var dir = fb.url
            for seg in effectiveComps {
                dir = dir.appendingPathComponent(seg, isDirectory: true)
            }
            let display = "\(fb.displayRoot)/\(effectiveComps.joined(separator: "/"))"
            return (dir, display, true)
        }

        return nil
    }

    static func saveDocumentFileToDestination(
        item: ManifestItem,
        sourceFileURL: URL,
        session: ReceiverDestinationSession? = nil
    ) -> (saved: Bool, displayFolder: String) {
        let managedSession = session == nil ? ReceiverDestinationSession.openFromPersistedBookmarks() : nil
        defer { managedSession?.close() }
        let activeSession = session ?? managedSession

        if let active = activeSession,
           let resolved = resolveWritableTargetDirectory(
               for: item,
               destinations: active.destinations,
               fallbackRoot: active.fallbackRoot
           ) {
            if writeFile(sourceFileURL: sourceFileURL, into: resolved.directoryURL, item: item, useCoordinator: true) {
                return (true, resolved.displayFolder)
            }
        }

        guard let targetDir = targetDirectory(for: item) else {
            return (false, "File → Su iPhone → DirectSwitch")
        }
        let ok = writeFile(sourceFileURL: sourceFileURL, into: targetDir, item: item, useCoordinator: false)
        let folderLabel = item.category == .WHATSAPP_VAULT
            ? "WhatsApp_Vault"
            : normalizedFolderString(item.relativeAlbumOrFolder)
        return (ok, "File → Su iPhone → DirectSwitch/\(folderLabel)")
    }

    private static func writeFile(
        sourceFileURL: URL,
        into targetDir: URL,
        item: ManifestItem,
        useCoordinator: Bool
    ) -> Bool {
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: targetDir, withIntermediateDirectories: true)
            let rawName = URL(fileURLWithPath: item.fileName).lastPathComponent
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let safeName = (rawName.isEmpty || rawName == "." || rawName == "..")
                ? "documento_\(item.id.prefix(6))"
                : rawName
            var destURL = targetDir.appendingPathComponent(safeName)
            if fm.fileExists(atPath: destURL.path) {
                let existingSize = (try? fm.attributesOfItem(atPath: destURL.path)[.size] as? NSNumber)?.int64Value ?? -1
                if item.sizeBytes > 0 && existingSize == item.sizeBytes {
                    if item.capturedEpochMillis > 0 {
                        let date = Date(timeIntervalSince1970: Double(item.capturedEpochMillis) / 1000.0)
                        try? fm.setAttributes([.modificationDate: date], ofItemAtPath: destURL.path)
                    }
                    return true
                }
                let ext = destURL.pathExtension
                let stem = destURL.deletingPathExtension().lastPathComponent
                var idx = 1
                while fm.fileExists(atPath: destURL.path) {
                    let alt = ext.isEmpty ? "\(stem) (\(idx))" : "\(stem) (\(idx)).\(ext)"
                    destURL = targetDir.appendingPathComponent(alt)
                    idx += 1
                }
            }

            if useCoordinator {
                var coordError: NSError?
                var innerError: Error?
                let coordinator = NSFileCoordinator()
                coordinator.coordinate(writingItemAt: destURL, options: .forReplacing, error: &coordError) { writeURL in
                    do {
                        if fm.fileExists(atPath: writeURL.path) {
                            try fm.removeItem(at: writeURL)
                        }
                        try fm.copyItem(at: sourceFileURL, to: writeURL)
                    } catch {
                        innerError = error
                    }
                }
                if coordError != nil || innerError != nil {
                    if !fm.fileExists(atPath: destURL.path) {
                        try fm.copyItem(at: sourceFileURL, to: destURL)
                    } else if let e = innerError ?? coordError {
                        throw e
                    }
                }
            } else {
                try fm.copyItem(at: sourceFileURL, to: destURL)
            }

            if item.capturedEpochMillis > 0 {
                let date = Date(timeIntervalSince1970: Double(item.capturedEpochMillis) / 1000.0)
                try? fm.setAttributes([.modificationDate: date], ofItemAtPath: destURL.path)
            }
            return true
        } catch {
            return false
        }
    }

    static func existingDocumentDedupKeys(including session: ReceiverDestinationSession?) -> Set<String> {
        var keys = existingDocumentDedupKeys()
        guard let session else { return keys }
        var scanRoots: [(URL, String)] = session.destinations.map { ($0.url, $0.dedupFolderRoot) }
        if let fb = session.fallbackRoot {
            scanRoots.append((fb.url, fb.isContainerRoot ? fb.dedupFolderRoot : ""))
        }
        var seenDirs: Set<String> = []
        for (rootURL, baseRoot) in scanRoots {
            let resolvedRoot = rootURL.resolvingSymlinksInPath().path
            guard seenDirs.insert(resolvedRoot).inserted else { continue }
            if let enumerator = FileManager.default.enumerator(
                at: rootURL,
                includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .fileSizeKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles]
            ) {
                for case let childURL as URL in enumerator {
                    let vals = try? childURL.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey])
                    if vals?.isDirectory == true { continue }
                    let info = inspectReadableFile(at: childURL)
                    guard info.readable, info.size > 0 else { continue }
                    let relFolder = computeRelativeFolder(
                        childURL: childURL,
                        resolvedRootPath: resolvedRoot,
                        baseFolderName: baseRoot
                    )
                    let modMs = Int64(info.modDate.timeIntervalSince1970 * 1000.0)
                    let fileName = childURL.lastPathComponent
                    for token in documentDedupTokens(folder: relFolder, fileName: fileName, sizeBytes: info.size, modMs: modMs) {
                        keys.insert(token)
                    }
                    // Emetti anche tutte le varianti alias del primo segmento e senza prefisso iCloud_Drive/
                    let relComps = sanitizedRelativeComponents(relFolder)
                    if !relComps.isEmpty {
                        let firstLower = relComps[0].lowercased()
                        for group in folderAliasGroups where group.contains(firstLower) {
                            for alias in group where alias != firstLower {
                                let aliasFolder = ([alias] + Array(relComps.dropFirst())).joined(separator: "/")
                                for token in documentDedupTokens(folder: aliasFolder, fileName: fileName, sizeBytes: info.size, modMs: modMs) {
                                    keys.insert(token)
                                }
                            }
                        }
                        if firstLower == "icloud_drive", relComps.count > 1 {
                            let strippedFolder = Array(relComps.dropFirst()).joined(separator: "/")
                            for token in documentDedupTokens(folder: strippedFolder, fileName: fileName, sizeBytes: info.size, modMs: modMs) {
                                keys.insert(token)
                            }
                        }
                    }
                }
            }
        }
        return keys
    }

    static func matchesExistingDocumentDedup(item: ManifestItem, existingKeys: Set<String>) -> Bool {
        let folder = item.category == .WHATSAPP_VAULT
            ? "WhatsApp_Vault"
            : normalizedFolderString(item.relativeAlbumOrFolder)
        let nameKey = URL(fileURLWithPath: item.fileName).lastPathComponent.lowercased()
        let sizeKey = "\(folder.lowercased())/\(nameKey)_\(item.sizeBytes)"
        return existingKeys.contains(sizeKey) || existingKeys.contains("\(sizeKey)_\(item.capturedEpochMillis)")
    }

    // MARK: - Segnalibri persistenti per intere posizioni (cartelle + file radice) e controllo iCloud

    private enum PositionOrigin {
        case directSwitchDocs
        case onMyIPhone
        case iCloudDrive(appContainer: String?)
        case externalLocation(name: String)

        var displayLocationName: String {
            switch self {
            case .directSwitchDocs: return "DirectSwitch (Su iPhone)"
            case .onMyIPhone: return "Su iPhone"
            case .iCloudDrive(let app): return app.map { "iCloud Drive (\($0))" } ?? "iCloud Drive"
            case .externalLocation(let name): return name
            }
        }
    }

    private static func detectPositionOrigin(for url: URL) -> PositionOrigin {
        let resolvedPath = url.resolvingSymlinksInPath().path
        if let docsRoot = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            let docsPath = docsRoot.resolvingSymlinksInPath().path
            if resolvedPath == docsPath || resolvedPath.hasPrefix(docsPath + "/") {
                return .directSwitchDocs
            }
        }
        if let mobileRange = resolvedPath.range(of: "/Mobile Documents/") {
            let afterMobile = String(resolvedPath[mobileRange.upperBound...])
            let container = String(afterMobile.split(separator: "/", maxSplits: 1).first ?? "")
            if container == "com~apple~CloudDocs" || container == "com.apple.CloudDocs" || container.isEmpty {
                return .iCloudDrive(appContainer: nil)
            }
            let cleanApp = container
                .replacingOccurrences(of: "iCloud~", with: "")
                .replacingOccurrences(of: "~", with: ".")
                .split(separator: ".")
                .last
                .map(String.init)
            return .iCloudDrive(appContainer: (cleanApp?.isEmpty == false) ? cleanApp : container)
        }
        if resolvedPath.contains("/File Provider Storage/") ||
            resolvedPath.contains("/com.apple.FileProvider.LocalStorage/") {
            return .onMyIPhone
        }
        if let liveRange = resolvedPath.range(of: "/LiveFiles/") {
            let afterLive = String(resolvedPath[liveRange.upperBound...])
            let parts = afterLive.split(separator: "/").map(String.init)
            if let vol = parts.dropFirst().first ?? parts.first, !vol.isEmpty {
                return .externalLocation(name: vol)
            }
            return .externalLocation(name: "Archivio_Esterno")
        }
        if (try? url.resourceValues(forKeys: [.isUbiquitousItemKey]).isUbiquitousItem) == true {
            return .iCloudDrive(appContainer: nil)
        }
        return .onMyIPhone
    }

    static func classifyPositionBaseFolder(for url: URL, isDirectory: Bool) -> (baseFolder: String, locationLabel: String) {
        let origin = detectPositionOrigin(for: url)
        let label = origin.displayLocationName
        let rawLast = url.lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
        let rawLower = rawLast.lowercased()

        switch origin {
        case .directSwitchDocs:
            return ("", label)
        case .onMyIPhone:
            if isDirectory {
                if rawLower == "file provider storage" ||
                    rawLower == "localstorage" ||
                    rawLower == "on my iphone" ||
                    rawLower == "su iphone" {
                    return ("", label)
                }
                return (rawLast.isEmpty ? "Su_iPhone" : rawLast, label)
            }
            return ("Su_iPhone", label)
        case .iCloudDrive(let app):
            let rootName = app.map { "iCloud_Drive/\($0)" } ?? "iCloud_Drive"
            if isDirectory {
                if rawLower == "com~apple~clouddocs" ||
                    rawLower == "com.apple.clouddocs" ||
                    rawLower == "documents" ||
                    rawLower == "mobile documents" ||
                    rawLast.isEmpty {
                    return (rootName, label)
                }
                return ("\(rootName)/\(rawLast)", label)
            }
            return (rootName, label)
        case .externalLocation(let locName):
            let cleanLoc = sanitizedRelativeComponents(locName).first ?? "Archivio_Esterno"
            if isDirectory {
                if rawLower == cleanLoc.lowercased() || rawLast.isEmpty {
                    return (cleanLoc, label)
                }
                return ("\(cleanLoc)/\(rawLast)", label)
            }
            return (cleanLoc, label)
        }
    }

    private static let deselectedPositionIdsKey = "directswitch_deselected_doc_locations_v1"

    static func positionLocationId(for url: URL) -> String {
        "pos:\(url.standardizedFileURL.path)"
    }

    static func isPositionSelected(locationId: String) -> Bool {
        let deselected = Set(UserDefaults.standard.stringArray(forKey: deselectedPositionIdsKey) ?? [])
        return !deselected.contains(locationId)
    }

    static func setPositionSelected(locationId: String, isSelected: Bool) {
        var deselected = Set(UserDefaults.standard.stringArray(forKey: deselectedPositionIdsKey) ?? [])
        if isSelected {
            deselected.remove(locationId)
        } else {
            deselected.insert(locationId)
        }
        UserDefaults.standard.set(Array(deselected), forKey: deselectedPositionIdsKey)
    }

    static func displayPositionLabel(for url: URL, isDirectory: Bool) -> String {
        let (baseFolder, locLabel) = classifyPositionBaseFolder(for: url, isDirectory: isDirectory)
        if locLabel == "Su iPhone" {
            if baseFolder.isEmpty || baseFolder == "Su_iPhone" {
                return "Su iPhone"
            }
            if baseFolder.caseInsensitiveCompare("Chrome") == .orderedSame {
                return "Chrome"
            }
            return "Su iPhone • \(baseFolder)"
        }
        if locLabel.hasPrefix("iCloud Drive") {
            if baseFolder == "iCloud_Drive" {
                return locLabel
            }
            if baseFolder.hasPrefix("iCloud_Drive/") {
                let sub = String(baseFolder.dropFirst("iCloud_Drive/".count))
                return sub.isEmpty ? locLabel : "\(locLabel) • \(sub)"
            }
            return locLabel
        }
        if baseFolder.isEmpty || baseFolder.caseInsensitiveCompare(locLabel) == .orderedSame {
            return locLabel
        }
        return "\(locLabel) • \(baseFolder)"
    }

    static func authorizePositionBookmarks(_ urls: [URL]) -> (addedBookmarks: Int, stagedFallback: [(ManifestItem, URL)]) {
        let existingDatas = (UserDefaults.standard.array(forKey: folderBookmarksDefaultsKey) as? [Data]) ?? []
        var existingPaths: Set<String> = []
        var cleanExistingDatas: [Data] = []
        for data in existingDatas {
            var stale = false
            if let resolved = try? URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &stale) {
                let stdPath = resolved.standardizedFileURL.path
                if existingPaths.insert(stdPath).inserted {
                    cleanExistingDatas.append(data)
                }
            }
        }

        var addedCount = 0
        for url in urls where url.isFileURL {
            let stdPath = url.standardizedFileURL.path
            let locId = positionLocationId(for: url)
            setPositionSelected(locationId: locId, isSelected: true)

            let accessed = url.startAccessingSecurityScopedResource()
            if let bookmark = createBookmarkDataCompat(for: url) {
                if existingPaths.insert(stdPath).inserted {
                    cleanExistingDatas.append(bookmark)
                    addedCount += 1
                }
                liveSessionLock.lock()
                if let old = liveSessionPositionURLs[stdPath], old.keepScopeOpen {
                    old.url.stopAccessingSecurityScopedResource()
                }
                liveSessionPositionURLs[stdPath] = (url, false)
                liveSessionLock.unlock()
                if accessed {
                    url.stopAccessingSecurityScopedResource()
                }
            } else {
                liveSessionLock.lock()
                if let old = liveSessionPositionURLs[stdPath], old.keepScopeOpen {
                    old.url.stopAccessingSecurityScopedResource()
                }
                liveSessionPositionURLs[stdPath] = (url, accessed)
                liveSessionLock.unlock()
                addedCount += 1
            }
        }
        UserDefaults.standard.set(cleanExistingDatas, forKey: folderBookmarksDefaultsKey)
        return (addedCount, [])
    }

    @discardableResult
    static func authorizeFolderBookmarks(_ urls: [URL]) -> Int {
        authorizePositionBookmarks(urls).addedBookmarks
    }

    static func persistedFolderBookmarksCount() -> Int {
        resolveBookmarkedLocationEntries().count
    }

    static func removeAuthorizedPosition(locationId: String) {
        let targetStdPath = locationId.hasPrefix("pos:")
            ? String(locationId.dropFirst(4))
            : locationId
        let datas = (UserDefaults.standard.array(forKey: folderBookmarksDefaultsKey) as? [Data]) ?? []
        var kept: [Data] = []
        for data in datas {
            var isStale = false
            if let url = try? URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &isStale),
               url.standardizedFileURL.path == targetStdPath {
                continue
            }
            kept.append(data)
        }
        UserDefaults.standard.set(kept, forKey: folderBookmarksDefaultsKey)

        liveSessionLock.lock()
        if let removed = liveSessionPositionURLs.removeValue(forKey: targetStdPath), removed.keepScopeOpen {
            removed.url.stopAccessingSecurityScopedResource()
        }
        liveSessionLock.unlock()

        var deselected = Set(UserDefaults.standard.stringArray(forKey: deselectedPositionIdsKey) ?? [])
        deselected.remove(locationId)
        UserDefaults.standard.set(Array(deselected), forKey: deselectedPositionIdsKey)
    }

    static func clearFolderBookmarks() {
        UserDefaults.standard.removeObject(forKey: folderBookmarksDefaultsKey)
        UserDefaults.standard.removeObject(forKey: deselectedPositionIdsKey)
        liveSessionLock.lock()
        for entry in liveSessionPositionURLs.values where entry.keepScopeOpen {
            entry.url.stopAccessingSecurityScopedResource()
        }
        liveSessionPositionURLs.removeAll()
        liveSessionLock.unlock()
    }

    static func resolveBookmarkedFolderURLs() -> [URL] {
        resolveBookmarkedLocationURLs()
    }

    private static func resolveBookmarkedLocationEntries() -> [(locationId: String, url: URL, keepScopeAlreadyOpen: Bool)] {
        let datas = (UserDefaults.standard.array(forKey: folderBookmarksDefaultsKey) as? [Data]) ?? []
        var entries: [(locationId: String, url: URL, keepScopeAlreadyOpen: Bool)] = []
        var refreshedDatas: [Data] = []
        var seenPaths: Set<String> = []

        for data in datas {
            var isStale = false
            guard let url = try? URL(
                resolvingBookmarkData: data,
                options: [],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) else {
                continue
            }
            let stdPath = url.standardizedFileURL.path
            guard seenPaths.insert(stdPath).inserted else { continue }
            if isStale {
                let accessed = url.startAccessingSecurityScopedResource()
                if let renewed = createBookmarkDataCompat(for: url) {
                    refreshedDatas.append(renewed)
                } else {
                    refreshedDatas.append(data)
                }
                if accessed {
                    url.stopAccessingSecurityScopedResource()
                }
            } else {
                refreshedDatas.append(data)
            }
            entries.append((positionLocationId(for: url), url, false))
        }
        if !datas.isEmpty && refreshedDatas.count != datas.count {
            UserDefaults.standard.set(refreshedDatas, forKey: folderBookmarksDefaultsKey)
        }

        liveSessionLock.lock()
        let liveEntries = liveSessionPositionURLs
        liveSessionLock.unlock()
        for (stdPath, live) in liveEntries {
            guard seenPaths.insert(stdPath).inserted else { continue }
            entries.append((positionLocationId(for: live.url), live.url, live.keepScopeOpen))
        }
        return entries
    }

    static func resolveBookmarkedLocationURLs() -> [URL] {
        resolveBookmarkedLocationEntries().map(\.url)
    }

    static func prepareReadableFileForUpload(at url: URL) -> Bool {
        inspectReadableFile(at: url).readable
    }

    static func inspectReadableFile(at url: URL) -> (readable: Bool, size: Int64, modDate: Date) {
        let vals = try? url.resourceValues(forKeys: [
            .isUbiquitousItemKey,
            .ubiquitousItemDownloadingStatusKey,
            .fileSizeKey,
            .totalFileSizeKey,
            .contentModificationDateKey
        ])
        if vals?.isUbiquitousItem == true,
           vals?.ubiquitousItemDownloadingStatus != URLUbiquitousItemDownloadingStatus.current {
            try? FileManager.default.startDownloadingUbiquitousItem(at: url)
            return (false, 0, Date())
        }

        var resultSize: Int64 = 0
        var resultDate: Date = Date()
        var isReadable = false
        var coordError: NSError?
        let coordinator = NSFileCoordinator(filePresenter: nil)
        coordinator.coordinate(readingItemAt: url, options: [.withoutChanges], error: &coordError) { readURL in
            guard let attrs = try? FileManager.default.attributesOfItem(atPath: readURL.path) else {
                return
            }
            let size = (attrs[.size] as? Int64) ?? (attrs[.size] as? NSNumber)?.int64Value ?? 0
            if let handle = try? FileHandle(forReadingFrom: readURL) {
                handle.closeFile()
                resultSize = max(0, size)
                resultDate = (attrs[.modificationDate] as? Date) ?? Date()
                isReadable = true
            }
        }
        if isReadable {
            return (true, resultSize, resultDate)
        }
        if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path) {
            let size = (attrs[.size] as? Int64) ?? (attrs[.size] as? NSNumber)?.int64Value ?? 0
            if let handle = try? FileHandle(forReadingFrom: url) {
                handle.closeFile()
                return (true, max(0, size), (attrs[.modificationDate] as? Date) ?? Date())
            }
        }
        return (false, 0, Date())
    }

    private static func inferMeaningfulParentFolder(for url: URL, fileExtension ext: String) -> String {
        let candidate = url.deletingLastPathComponent().lastPathComponent
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = candidate.lowercased()
        if !candidate.isEmpty,
           candidate != ".",
           candidate != "..",
           !genericContainerFolders.contains(lower),
           UUID(uuidString: candidate) == nil {
            return candidate
        }
        return ext == "csv" ? "Password_Esportate" : "Documenti"
    }

    private static func computeRelativeFolder(
        childURL: URL,
        resolvedRootPath: String,
        baseFolderName: String
    ) -> String {
        let childDirPath = childURL.deletingLastPathComponent().resolvingSymlinksInPath().path
        var subRel = ""
        if childDirPath.hasPrefix(resolvedRootPath) {
            subRel = String(childDirPath.dropFirst(resolvedRootPath.count))
                .trimmingCharacters(in: CharacterSet(charactersIn: "/\\"))
        }
        if baseFolderName.isEmpty {
            return subRel.isEmpty ? "Documenti" : subRel
        }
        return subRel.isEmpty ? baseFolderName : "\(baseFolderName)/\(subRel)"
    }

    private static func buildManifestItem(
        fileName: String,
        relativeFolder: String,
        size: Int64,
        modDate: Date,
        counter: Int
    ) -> ManifestItem {
        let modMs = Int64(modDate.timeIntervalSince1970 * 1000.0)
        let lower = fileName.lowercased()
        let ext = URL(fileURLWithPath: fileName).pathExtension.lowercased()
        let isWhatsApp = lower.contains("whatsapp") || ext == "opus" || (ext == "zip" && lower.contains("chat")) ||
            relativeFolder.lowercased().hasPrefix("whatsapp_vault")
        let category: TransferCategory = isWhatsApp ? .WHATSAPP_VAULT : .DOCUMENTS
        let cleanRel = normalizedFolderString(relativeFolder)
        let folderToUse = isWhatsApp ? "WhatsApp_Vault" : cleanRel
        return ManifestItem(
            id: "doc_\(UUID().uuidString.prefix(8).lowercased())_\(counter)",
            category: category,
            fileName: fileName,
            relativeAlbumOrFolder: folderToUse,
            sizeBytes: size,
            capturedEpochMillis: modMs,
            dedupKey: "\(folderToUse.lowercased())/\(lower)_\(size)_\(modMs)",
            mimeType: mimeForExtension(ext)
        )
    }

    private static func appendDirectoryItems(
        rootURL: URL,
        baseFolderName: String,
        locationId: String,
        locationLabel: String,
        skipInbox: Bool,
        skipOwnAppDocs: Bool,
        includeWhatsAppVault: Bool,
        counter: inout Int,
        seenDedup: inout Set<String>,
        unreadableCount: inout Int,
        discoveredFolders: inout Set<String>,
        collector: (ManifestItem, URL, String, String) -> Void
    ) {
        let ownDocsResolved = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?.resolvingSymlinksInPath().path
        let resourceKeys: [URLResourceKey] = [
            .nameKey,
            .isDirectoryKey,
            .isRegularFileKey,
            .isPackageKey,
            .fileSizeKey,
            .totalFileSizeKey,
            .contentModificationDateKey,
            .isUbiquitousItemKey,
            .ubiquitousItemDownloadingStatusKey
        ]

        func enumerateRoot(_ effectiveRoot: URL) -> Bool {
            let resolvedRoot = effectiveRoot.resolvingSymlinksInPath().path
            guard let enumerator = FileManager.default.enumerator(
                at: effectiveRoot,
                includingPropertiesForKeys: resourceKeys,
                options: [.skipsHiddenFiles]
            ) else {
                return false
            }
            for case let childURL as URL in enumerator {
                let childResolved = childURL.resolvingSymlinksInPath().path
                if skipOwnAppDocs, let ownDocs = ownDocsResolved,
                   (childResolved == ownDocs || childResolved.hasPrefix(ownDocs + "/")) {
                    enumerator.skipDescendants()
                    continue
                }
                let vals = try? childURL.resourceValues(forKeys: Set(resourceKeys))
                let isDir = (vals?.isDirectory == true) && (vals?.isPackage != true)
                if isDir {
                    let subPath = childURL.resolvingSymlinksInPath().path
                    if subPath.hasPrefix(resolvedRoot) {
                        let subRel = String(subPath.dropFirst(resolvedRoot.count))
                            .trimmingCharacters(in: CharacterSet(charactersIn: "/\\"))
                        if !subRel.isEmpty {
                            let fullFolder = baseFolderName.isEmpty ? subRel : "\(baseFolderName)/\(subRel)"
                            if !(skipInbox && (fullFolder == "Inbox" || fullFolder.hasPrefix("Inbox/") ||
                                fullFolder == "SMS_Archivio" || fullFolder.hasPrefix("SMS_Archivio/"))) {
                                discoveredFolders.insert(normalizedFolderString(fullFolder).lowercased())
                            }
                        }
                    }
                    continue
                }
                let relFolder = computeRelativeFolder(
                    childURL: childURL,
                    resolvedRootPath: resolvedRoot,
                    baseFolderName: baseFolderName
                )
                if skipInbox && (relFolder == "Inbox" || relFolder.hasPrefix("Inbox/") ||
                    relFolder == "SMS_Archivio" || relFolder.hasPrefix("SMS_Archivio/")) {
                    continue
                }
                if vals?.isUbiquitousItem == true,
                   vals?.ubiquitousItemDownloadingStatus != URLUbiquitousItemDownloadingStatus.current {
                    try? FileManager.default.startDownloadingUbiquitousItem(at: childURL)
                    unreadableCount += 1
                    continue
                }

                let fileSize: Int64
                if let s = vals?.fileSize ?? vals?.totalFileSize {
                    fileSize = Int64(max(0, s))
                } else if let attrs = try? FileManager.default.attributesOfItem(atPath: childURL.path),
                          let num = (attrs[.size] as? Int64) ?? (attrs[.size] as? NSNumber)?.int64Value {
                    fileSize = max(0, num)
                } else {
                    unreadableCount += 1
                    continue
                }

                let modDate = vals?.contentModificationDate
                    ?? ((try? FileManager.default.attributesOfItem(atPath: childURL.path)[.modificationDate]) as? Date)
                    ?? Date()

                let safeName = (vals?.name ?? childURL.lastPathComponent)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let item = buildManifestItem(
                    fileName: safeName.isEmpty ? "documento_\(counter).bin" : safeName,
                    relativeFolder: relFolder,
                    size: fileSize,
                    modDate: modDate,
                    counter: counter
                )
                if item.category == .WHATSAPP_VAULT && !includeWhatsAppVault {
                    continue
                }
                discoveredFolders.insert(item.relativeAlbumOrFolder.lowercased())
                let normKey = "\(item.relativeAlbumOrFolder.lowercased())/\(item.fileName.lowercased())_\(item.sizeBytes)"
                guard seenDedup.insert(normKey).inserted else { continue }
                counter += 1
                collector(item, childURL, locationId, locationLabel)
            }
            return true
        }

        var didEnumerate = false
        var coordError: NSError?
        let coordinator = NSFileCoordinator(filePresenter: nil)
        coordinator.coordinate(readingItemAt: rootURL, options: [.withoutChanges], error: &coordError) { coordinatedRoot in
            didEnumerate = enumerateRoot(coordinatedRoot)
        }
        if !didEnumerate {
            _ = enumerateRoot(rootURL)
        }
    }

    private struct ScannedLocationMeta {
        let locationId: String
        let locationName: String
        let isRemovableBookmark: Bool
        var discoveredFolders: Set<String>
    }

    private static func scanAllLocations(
        stagedItems: [(ManifestItem, URL)],
        includeDocuments: Bool,
        includeWhatsAppVault: Bool,
        keepSecurityScopesOpen: Bool,
        onlySelectedPositions: Bool
    ) -> (
        entries: [(item: ManifestItem, url: URL, locationId: String, locationName: String)],
        locationMetas: [ScannedLocationMeta],
        unreadableCount: Int,
        authorizedPositionsCount: Int,
        localAppFilesCount: Int,
        activeScopes: [URL]
    ) {
        var counter = 0
        var seenKeys: Set<String> = []
        var unreadableCount = 0
        var localAppFiles = 0
        var results: [(item: ManifestItem, url: URL, locationId: String, locationName: String)] = []
        var metas: [ScannedLocationMeta] = []
        var activeScopes: [URL] = []

        func appendIfCategoryMatches(
            _ item: ManifestItem,
            _ url: URL,
            _ locId: String,
            _ locLabel: String,
            isLocalApp: Bool = false
        ) {
            let allow = (item.category == .WHATSAPP_VAULT && includeWhatsAppVault) ||
                        (item.category != .WHATSAPP_VAULT && includeDocuments)
            guard allow else { return }
            if isLocalApp { localAppFiles += 1 }
            results.append((item, url, locId, locLabel))
        }

        let localAppId = "builtin:directswitch"
        if !onlySelectedPositions || isPositionSelected(locationId: localAppId),
           let docsRoot = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            var localFolders: Set<String> = []
            appendDirectoryItems(
                rootURL: docsRoot,
                baseFolderName: "",
                locationId: localAppId,
                locationLabel: "DirectSwitch (Su iPhone)",
                skipInbox: true,
                skipOwnAppDocs: false,
                includeWhatsAppVault: includeWhatsAppVault,
                counter: &counter,
                seenDedup: &seenKeys,
                unreadableCount: &unreadableCount,
                discoveredFolders: &localFolders
            ) { item, url, locId, locLabel in
                appendIfCategoryMatches(item, url, locId, locLabel, isLocalApp: true)
            }
            if localAppFiles > 0 {
                metas.append(
                    ScannedLocationMeta(
                        locationId: localAppId,
                        locationName: "DirectSwitch (Su iPhone)",
                        isRemovableBookmark: false,
                        discoveredFolders: localFolders
                    )
                )
            }
        }

        let bookmarkedLocations = resolveBookmarkedLocationEntries()
        for locEntry in bookmarkedLocations {
            let locId = locEntry.locationId
            if onlySelectedPositions && !isPositionSelected(locationId: locId) {
                continue
            }
            let locURL = locEntry.url
            let accessed = locEntry.keepScopeAlreadyOpen ? false : locURL.startAccessingSecurityScopedResource()
            if accessed && keepSecurityScopesOpen {
                activeScopes.append(locURL)
            }
            defer {
                if accessed && !keepSecurityScopesOpen {
                    locURL.stopAccessingSecurityScopedResource()
                }
            }
            let isDir = ((try? locURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? true)
            let (baseFolder, _) = classifyPositionBaseFolder(for: locURL, isDirectory: isDir)
            let displayLabel = displayPositionLabel(for: locURL, isDirectory: isDir)
            var locFolders: Set<String> = []

            if isDir {
                appendDirectoryItems(
                    rootURL: locURL,
                    baseFolderName: baseFolder,
                    locationId: locId,
                    locationLabel: displayLabel,
                    skipInbox: false,
                    skipOwnAppDocs: true,
                    includeWhatsAppVault: includeWhatsAppVault,
                    counter: &counter,
                    seenDedup: &seenKeys,
                    unreadableCount: &unreadableCount,
                    discoveredFolders: &locFolders
                ) { item, url, entryLocId, entryLocLabel in
                    appendIfCategoryMatches(item, url, entryLocId, entryLocLabel)
                }
            } else {
                let info = inspectReadableFile(at: locURL)
                if info.readable {
                    let safeName = locURL.lastPathComponent
                    let item = buildManifestItem(
                        fileName: safeName.isEmpty ? "documento_\(counter).bin" : safeName,
                        relativeFolder: baseFolder,
                        size: info.size,
                        modDate: info.modDate,
                        counter: counter
                    )
                    locFolders.insert(item.relativeAlbumOrFolder.lowercased())
                    let normKey = "\(item.relativeAlbumOrFolder.lowercased())/\(item.fileName.lowercased())_\(item.sizeBytes)"
                    if seenKeys.insert(normKey).inserted {
                        counter += 1
                        appendIfCategoryMatches(item, locURL, locId, displayLabel)
                    }
                } else {
                    unreadableCount += 1
                }
            }

            metas.append(
                ScannedLocationMeta(
                    locationId: locId,
                    locationName: displayLabel,
                    isRemovableBookmark: true,
                    discoveredFolders: locFolders
                )
            )
        }

        let stagedLocId = "builtin:staged"
        if !stagedItems.isEmpty && (!onlySelectedPositions || isPositionSelected(locationId: stagedLocId)) {
            var stagedFolders: Set<String> = []
            for (item, url) in stagedItems {
                let normKey = "\(normalizedFolderString(item.relativeAlbumOrFolder).lowercased())/\(item.fileName.lowercased())_\(item.sizeBytes)"
                if seenKeys.insert(normKey).inserted {
                    stagedFolders.insert(normalizedFolderString(item.relativeAlbumOrFolder).lowercased())
                    appendIfCategoryMatches(item, url, stagedLocId, "File allegati")
                }
            }
            if !stagedFolders.isEmpty {
                metas.append(
                    ScannedLocationMeta(
                        locationId: stagedLocId,
                        locationName: "File allegati",
                        isRemovableBookmark: false,
                        discoveredFolders: stagedFolders
                    )
                )
            }
        }

        return (results, metas, unreadableCount, bookmarkedLocations.count, localAppFiles, activeScopes)
    }

    /// Scansione di pre-controllo sul dispositivo iOS per intere posizioni:
    /// mostra SEMPRE ogni posizione autorizzata con il suo stato di selezione, e calcola totali e cartelle sulle sole posizioni selezionate.
    static func inspectPreTransferDocuments(
        stagedItems: [ManifestItem] = [],
        includeWhatsAppVault: Bool = false
    ) -> iOSDocumentsPrecheckReport {
        let placeholderURL = URL(fileURLWithPath: "/")
        let stagedPairs = stagedItems.map { ($0, placeholderURL) }
        let scan = scanAllLocations(
            stagedItems: stagedPairs,
            includeDocuments: true,
            includeWhatsAppVault: includeWhatsAppVault,
            keepSecurityScopesOpen: false,
            onlySelectedPositions: false
        )

        var groupedFolders: [String: (count: Int, bytes: Int64)] = [:]
        var statsByLocId: [String: (folders: Set<String>, count: Int, bytes: Int64)] = [:]
        var selectedTotalFiles = 0
        var selectedTotalBytes: Int64 = 0

        for entry in scan.entries {
            let folder = normalizedFolderString(entry.item.relativeAlbumOrFolder)
            var locStat = statsByLocId[entry.locationId] ?? (Set<String>(), 0, 0)
            locStat.folders.insert(folder.lowercased())
            locStat.count += 1
            locStat.bytes += entry.item.sizeBytes
            statsByLocId[entry.locationId] = locStat

            if isPositionSelected(locationId: entry.locationId) {
                let prevF = groupedFolders[folder] ?? (0, 0)
                groupedFolders[folder] = (prevF.count + 1, prevF.bytes + entry.item.sizeBytes)
                selectedTotalFiles += 1
                selectedTotalBytes += entry.item.sizeBytes
            }
        }

        let summaries = groupedFolders.map { key, val in
            iOSDocumentFolderSummary(folderPath: key, fileCount: val.count, totalBytes: val.bytes)
        }.sorted { lhs, rhs in
            if lhs.fileCount != rhs.fileCount { return lhs.fileCount > rhs.fileCount }
            return lhs.folderPath.localizedCaseInsensitiveCompare(rhs.folderPath) == .orderedAscending
        }

        var seenLocIds: Set<String> = []
        var locSummaries: [iOSDocumentLocationSummary] = []
        for meta in scan.locationMetas {
            guard seenLocIds.insert(meta.locationId).inserted else { continue }
            let stat = statsByLocId[meta.locationId] ?? (Set<String>(), 0, 0)
            let mergedFolders = meta.discoveredFolders.union(stat.folders)
            locSummaries.append(
                iOSDocumentLocationSummary(
                    locationId: meta.locationId,
                    locationName: meta.locationName,
                    folderCount: mergedFolders.count,
                    fileCount: stat.count,
                    totalBytes: stat.bytes,
                    isSelected: isPositionSelected(locationId: meta.locationId),
                    isRemovableBookmark: meta.isRemovableBookmark
                )
            )
        }

        return iOSDocumentsPrecheckReport(
            totalFiles: selectedTotalFiles,
            totalBytes: selectedTotalBytes,
            authorizedBookmarkFoldersCount: scan.authorizedPositionsCount,
            localAppFolderFilesCount: scan.localAppFilesCount,
            unreadableFilesCount: scan.unreadableCount,
            folderSummaries: summaries,
            locationSummaries: locSummaries
        )
    }

    /// Raccoglie tutti i documenti verificati dalle posizioni selezionate mantenendo attivi gli accessi security-scoped fino al termine dell'invio.
    static func collectAllVerifiedDocumentsForTransfer(
        explicitPicked: [(ManifestItem, URL)],
        includeDocuments: Bool,
        includeWhatsAppVault: Bool
    ) -> (items: [(ManifestItem, URL)], activeSecurityScopes: [URL]) {
        let scan = scanAllLocations(
            stagedItems: explicitPicked,
            includeDocuments: includeDocuments,
            includeWhatsAppVault: includeWhatsAppVault,
            keepSecurityScopesOpen: true,
            onlySelectedPositions: true
        )
        return (scan.entries.map { ($0.item, $0.url) }, scan.activeScopes)
    }

    /// Copia nel Vault singoli file, archivi `.zip` di WhatsApp, file Password `.csv` oppure INTERE CARTELLE
    /// selezionate da «Su iPhone» nell'app File, preservando ricorsivamente tutta la gerarchia di sottocartelle.
    static func importPickedDocumentURLs(_ urls: [URL]) -> [(ManifestItem, URL)] {
        let stagingDir = stagingVaultDirectory()
        var results: [(ManifestItem, URL)] = []
        var counter = 0

        func stageSingleFile(sourceURL: URL, relativeFolder: String, removeInboxIfApplicable: Bool) {
            let rawName = sourceURL.lastPathComponent
            let safeName = rawName.isEmpty ? "documento_\(counter).bin" : rawName
            let stagedURL = uniqueDestinationURL(
                in: stagingDir,
                preferredFileName: "\(UUID().uuidString.prefix(6))_\(safeName)"
            )
            let info = inspectReadableFile(at: sourceURL)
            guard info.readable, info.size > 0 else { return }
            do {
                try FileManager.default.copyItem(at: sourceURL, to: stagedURL)
                if removeInboxIfApplicable && sourceURL.path.contains("/Documents/Inbox/") {
                    try? FileManager.default.removeItem(at: sourceURL)
                }
                let item = buildManifestItem(
                    fileName: safeName,
                    relativeFolder: relativeFolder,
                    size: info.size,
                    modDate: info.modDate,
                    counter: counter
                )
                counter += 1
                results.append((item, stagedURL))
            } catch {
                try? FileManager.default.removeItem(at: stagedURL)
            }
        }

        for url in urls {
            guard url.isFileURL else { continue }
            let accessed = url.startAccessingSecurityScopedResource()
            defer {
                if accessed { url.stopAccessingSecurityScopedResource() }
            }

            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            if isDir {
                let (cleanRoot, _) = classifyPositionBaseFolder(for: url, isDirectory: true)
                let resolvedRootPath = url.resolvingSymlinksInPath().path
                if let enumerator = FileManager.default.enumerator(
                    at: url,
                    includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey],
                    options: [.skipsHiddenFiles]
                ) {
                    for case let childURL as URL in enumerator {
                        let vals = try? childURL.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey])
                        if vals?.isDirectory == true { continue }
                        let fullRel = computeRelativeFolder(
                            childURL: childURL,
                            resolvedRootPath: resolvedRootPath,
                            baseFolderName: cleanRoot
                        )
                        stageSingleFile(sourceURL: childURL, relativeFolder: fullRel, removeInboxIfApplicable: false)
                    }
                }
            } else {
                let ext = url.pathExtension.lowercased()
                let inferredFolder = inferMeaningfulParentFolder(for: url, fileExtension: ext)
                stageSingleFile(sourceURL: url, relativeFolder: inferredFolder, removeInboxIfApplicable: true)
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

    static func clearAllPickedDocumentsAndBookmarks() {
        clearStagedVault()
        clearFolderBookmarks()
    }
}

private enum iOSEventStoreHelpers {
    static let maxChunkSeconds: TimeInterval = 365.0 * 86400.0 * 3.0

    static func canRead(entityType: EKEntityType) -> Bool {
        let status = EKEventStore.authorizationStatus(for: entityType)
        if #available(iOS 17.0, *) {
            return status == .fullAccess
        } else {
            return status == .authorized
        }
    }

    static func canWrite(entityType: EKEntityType) -> Bool {
        let status = EKEventStore.authorizationStatus(for: entityType)
        if #available(iOS 17.0, *) {
            return status == .fullAccess || status == .writeOnly
        } else {
            return status == .authorized
        }
    }

    static func requestAccess(entityType: EKEntityType) async -> Bool {
        if canRead(entityType: entityType) { return true }
        let current = EKEventStore.authorizationStatus(for: entityType)
        if current == .denied || current == .restricted { return false }
        if #available(iOS 17.0, *), current == .writeOnly { return true }

        return await requestSystemAccessOnMain(entityType: entityType)
    }

    @MainActor
    private static func requestSystemAccessOnMain(entityType: EKEntityType) async -> Bool {
        let store = EKEventStore()
        defer { _ = store }
        if #available(iOS 17.0, *) {
            switch entityType {
            case .event:
                _ = try? await store.requestFullAccessToEvents()
            case .reminder:
                _ = try? await store.requestFullAccessToReminders()
            @unknown default:
                break
            }
        } else {
            _ = try? await store.requestAccess(to: entityType)
        }
        return canWrite(entityType: entityType)
    }

    static func resolveWritableCalendar(
        in store: EKEventStore,
        entityType: EKEntityType,
        fallbackTitle: String
    ) -> EKCalendar? {
        let defaultCal: EKCalendar? = entityType == .event
            ? store.defaultCalendarForNewEvents
            : store.defaultCalendarForNewReminders()
        if let defaultCal, defaultCal.allowsContentModifications {
            return defaultCal
        }
        let writable = store.calendars(for: entityType).filter { cal in
            cal.allowsContentModifications && cal.type != .birthday && cal.type != .subscription
        }
        if let preferred = writable.first(where: {
            $0.source?.sourceType == .calDAV || $0.source?.sourceType == .mobileMe
        }) ?? writable.first(where: { $0.source?.sourceType == .local }) ?? writable.first {
            return preferred
        }

        let candidateSources = store.sources.filter {
            $0.sourceType == .local || $0.sourceType == .calDAV || $0.sourceType == .mobileMe
        }
        for source in candidateSources {
            let newCal = EKCalendar(for: entityType, eventStore: store)
            newCal.title = fallbackTitle
            newCal.source = source
            if (try? store.saveCalendar(newCal, commit: true)) != nil, newCal.allowsContentModifications {
                return newCal
            }
        }
        return store.calendars(for: entityType).first(where: { $0.allowsContentModifications })
    }

    static func writableCalendarsByLowerTitle(in store: EKEventStore, entityType: EKEntityType) -> [String: EKCalendar] {
        var map: [String: EKCalendar] = [:]
        for cal in store.calendars(for: entityType) where cal.allowsContentModifications && cal.type != .birthday && cal.type != .subscription {
            let key = cal.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if !key.isEmpty && map[key] == nil {
                map[key] = cal
            }
        }
        return map
    }

    static func ensureTargetCalendar(
        named rawName: String?,
        entityType: EKEntityType,
        in store: EKEventStore,
        fallback: EKCalendar,
        cache: inout [String: EKCalendar]
    ) -> EKCalendar {
        let trimmed = (rawName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return fallback }
        let lower = trimmed.lowercased()
        if let existing = cache[lower] {
            return existing
        }
        let preferredSources: [EKSource] = {
            var srcs: [EKSource] = []
            if let fbSource = fallback.source { srcs.append(fbSource) }
            for s in store.sources where !srcs.contains(where: { $0.sourceIdentifier == s.sourceIdentifier }) &&
                (s.sourceType == .calDAV || s.sourceType == .mobileMe || s.sourceType == .local) {
                srcs.append(s)
            }
            return srcs
        }()
        for source in preferredSources {
            let newCal = EKCalendar(for: entityType, eventStore: store)
            newCal.title = trimmed
            newCal.source = source
            if (try? store.saveCalendar(newCal, commit: true)) != nil {
                cache[lower] = newCal
                return newCal
            }
        }
        return fallback
    }

    /// Apple EventKit `predicateForEvents` tronca silenziosamente le query superiori a 4 anni ai soli primi 4 anni.
    static func fetchEventsChunked(in store: EKEventStore, from start: Date, to end: Date) -> [EKEvent] {
        guard start < end else { return [] }
        var collected: [EKEvent] = []
        var cursor = start
        while cursor < end {
            let chunkEnd = min(end, cursor.addingTimeInterval(maxChunkSeconds))
            let pred = store.predicateForEvents(withStart: cursor, end: chunkEnd, calendars: nil)
            collected.append(contentsOf: store.events(matching: pred))
            cursor = chunkEnd
        }
        return collected
    }
}

enum iOSCalendarMigrator {
    static func isAuthorized() -> Bool {
        iOSEventStoreHelpers.canRead(entityType: .event)
    }

    static func canWrite() -> Bool {
        iOSEventStoreHelpers.canWrite(entityType: .event)
    }

    static func requestAccessIfNeeded() async -> Bool {
        await iOSEventStoreHelpers.requestAccess(entityType: .event)
    }

    private static func encodeFrequency(_ freq: EKRecurrenceFrequency) -> String {
        switch freq {
        case .daily: return "daily"
        case .weekly: return "weekly"
        case .monthly: return "monthly"
        case .yearly: return "yearly"
        @unknown default: return "yearly"
        }
    }

    private static func decodeFrequency(_ raw: String?) -> EKRecurrenceFrequency? {
        switch raw?.lowercased() {
        case "daily": return .daily
        case "weekly": return .weekly
        case "monthly": return .monthly
        case "yearly": return .yearly
        default: return nil
        }
    }

    static func readEvents(upToDate: Date? = nil) -> [CalendarEventRecord] {
        guard isAuthorized() else { return [] }
        let store = EKEventStore()
        let start = Date().addingTimeInterval(-365 * 86400 * 10)
        let defaultEnd = Date().addingTimeInterval(365 * 86400 * 10)
        let end: Date = {
            guard let cutoff = upToDate else { return defaultEnd }
            let endOfCutoffDay = Calendar.current.date(bySettingHour: 23, minute: 59, second: 59, of: cutoff) ?? cutoff
            return max(start, min(defaultEnd, endOfCutoffDay))
        }()

        let rawEvents = iOSEventStoreHelpers.fetchEventsChunked(in: store, from: start, to: end)
        var seenSeriesOrOccurrence = Set<String>()
        var records: [CalendarEventRecord] = []

        for ev in rawEvents {
            let startMs = Int64(ev.startDate.timeIntervalSince1970 * 1000.0)
            let endMsRaw = Int64(ev.endDate.timeIntervalSince1970 * 1000.0)
            let safeEndMs = endMsRaw >= startMs ? endMsRaw : (startMs + 3_600_000)
            let evId = ev.eventIdentifier ?? UUID().uuidString
            let dedupKey: String = (ev.hasRecurrenceRules && !ev.isDetached)
                ? "rec|\(evId)"
                : "occ|\(evId)|\(startMs)"
            guard seenSeriesOrOccurrence.insert(dedupKey).inserted else { continue }

            let rule = ev.recurrenceRules?.first
            let freqStr = rule.map { encodeFrequency($0.frequency) }
            let interval = rule.map { max(1, $0.interval) }
            let rruleStr = CalendarRecurrenceMapper.toRRule(frequency: freqStr, interval: interval)
            let alarmOffset = ev.alarms?.first?.relativeOffset

            records.append(
                CalendarEventRecord(
                    id: evId,
                    title: ev.title ?? "Evento",
                    description: ev.notes,
                    location: ev.location,
                    startEpochMillis: startMs,
                    endEpochMillis: safeEndMs,
                    allDay: ev.isAllDay,
                    rrule: rruleStr,
                    calendarTitle: ev.calendar?.title,
                    recurrenceFrequency: freqStr,
                    recurrenceInterval: interval,
                    alarmOffsetSeconds: alarmOffset
                )
            )
        }
        return records
    }

    private static func populateEKEvent(
        _ ev: EKEvent,
        from rec: CalendarEventRecord,
        calendar: EKCalendar,
        includeRecurrenceAndAlarm: Bool
    ) {
        let startDate = Date(timeIntervalSince1970: TimeInterval(rec.startEpochMillis) / 1000.0)
        let safeEndMs = rec.endEpochMillis >= rec.startEpochMillis
            ? rec.endEpochMillis
            : (rec.startEpochMillis + (rec.allDay ? 86_400_000 : 3_600_000))
        let endDate = Date(timeIntervalSince1970: TimeInterval(safeEndMs) / 1000.0)

        ev.calendar = calendar
        ev.title = rec.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Evento" : rec.title
        ev.notes = rec.description
        ev.location = rec.location
        ev.startDate = startDate
        ev.endDate = max(startDate, endDate)
        ev.isAllDay = rec.allDay

        guard includeRecurrenceAndAlarm else { return }
        let parsedRRule = CalendarRecurrenceMapper.parseRRule(rec.rrule)
        let freqStr = rec.recurrenceFrequency ?? parsedRRule?.frequency
        let interval = max(1, rec.recurrenceInterval ?? parsedRRule?.interval ?? 1)
        if let freq = decodeFrequency(freqStr) {
            ev.addRecurrenceRule(EKRecurrenceRule(recurrenceWith: freq, interval: interval, end: nil))
        }
        if let offset = rec.alarmOffsetSeconds, offset.isFinite {
            ev.addAlarm(EKAlarm(relativeOffset: offset))
        }
    }

    static func importEventsWithStats(_ incoming: [CalendarEventRecord]) -> (imported: Int, alreadyPresent: Int) {
        guard !incoming.isEmpty, canWrite() else { return (0, 0) }
        let store = EKEventStore()
        guard let fallbackCalendar = iOSEventStoreHelpers.resolveWritableCalendar(
            in: store,
            entityType: .event,
            fallbackTitle: "Calendario"
        ) else {
            return (0, 0)
        }

        var existingSignatures = Set<String>()
        if isAuthorized() {
            let minMs = incoming.map(\.startEpochMillis).min() ?? 0
            let maxMs = incoming.map(\.endEpochMillis).max() ?? minMs
            let existingStart = Date(timeIntervalSince1970: TimeInterval(minMs) / 1000.0 - 86_400)
            let existingEnd = Date(timeIntervalSince1970: TimeInterval(max(maxMs, minMs)) / 1000.0 + 86_400)
            for ev in iOSEventStoreHelpers.fetchEventsChunked(in: store, from: existingStart, to: existingEnd) {
                let normTitle = (ev.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                let startMinute = Int64(ev.startDate.timeIntervalSince1970 * 1000.0) / 60_000
                existingSignatures.insert("\(normTitle)_\(startMinute)")
            }
        }

        var calendarCache = iOSEventStoreHelpers.writableCalendarsByLowerTitle(in: store, entityType: .event)
        var pendingRecords: [(record: CalendarEventRecord, calendar: EKCalendar, sig: String)] = []
        var alreadyPresent = 0

        for rec in incoming {
            let normTitle = rec.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let sig = "\(normTitle)_\(rec.startEpochMillis / 60_000)"
            if existingSignatures.contains(sig) {
                alreadyPresent += 1
                continue
            }
            let targetCal = iOSEventStoreHelpers.ensureTargetCalendar(
                named: rec.calendarTitle,
                entityType: .event,
                in: store,
                fallback: fallbackCalendar,
                cache: &calendarCache
            )
            existingSignatures.insert(sig)
            pendingRecords.append((rec, targetCal, sig))
        }

        guard !pendingRecords.isEmpty else {
            return (0, alreadyPresent)
        }

        var queuedCount = 0
        for item in pendingRecords {
            let ev = EKEvent(eventStore: store)
            populateEKEvent(ev, from: item.record, calendar: item.calendar, includeRecurrenceAndAlarm: true)
            if (try? store.save(ev, span: .thisEvent, commit: false)) != nil {
                queuedCount += 1
            }
        }
        if queuedCount > 0, (try? store.commit()) != nil {
            return (queuedCount, alreadyPresent)
        }

        // Fallback atomico per singolo evento: impedisce che 1 elemento anomalo annulli tutti gli altri al commit().
        store.reset()
        let freshStore = EKEventStore()
        let freshFallback = iOSEventStoreHelpers.resolveWritableCalendar(
            in: freshStore,
            entityType: .event,
            fallbackTitle: "Calendario"
        ) ?? fallbackCalendar
        var freshCache = iOSEventStoreHelpers.writableCalendarsByLowerTitle(in: freshStore, entityType: .event)
        var savedIndividually = 0

        for item in pendingRecords {
            let targetCal = freshCache[item.calendar.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()]
                ?? freshFallback
            let evFull = EKEvent(eventStore: freshStore)
            populateEKEvent(evFull, from: item.record, calendar: targetCal, includeRecurrenceAndAlarm: true)
            if (try? freshStore.save(evFull, span: .thisEvent, commit: true)) != nil {
                savedIndividually += 1
                continue
            }
            freshStore.reset()
            let evBasic = EKEvent(eventStore: freshStore)
            populateEKEvent(evBasic, from: item.record, calendar: freshFallback, includeRecurrenceAndAlarm: false)
            if (try? freshStore.save(evBasic, span: .thisEvent, commit: true)) != nil {
                savedIndividually += 1
            } else {
                freshStore.reset()
            }
        }
        return (savedIndividually, alreadyPresent)
    }

    static func importEvents(_ incoming: [CalendarEventRecord]) -> Int {
        importEventsWithStats(incoming).imported
    }
}

/// Migratore nativo dei Promemoria Apple (`EKReminder`) senza iCloud, con conservazione delle liste, scadenze, note e priorità.
enum iOSRemindersMigrator {
    static func isAuthorized() -> Bool {
        iOSEventStoreHelpers.canRead(entityType: .reminder)
    }

    static func canWrite() -> Bool {
        iOSEventStoreHelpers.canWrite(entityType: .reminder)
    }

    static func requestAccessIfNeeded() async -> Bool {
        await iOSEventStoreHelpers.requestAccess(entityType: .reminder)
    }

    static func readReminders(upToDate: Date? = nil) async -> [ReminderTransferRecord] {
        guard isAuthorized() else { return [] }
        let store = EKEventStore()
        let pred = store.predicateForReminders(in: nil)
        let fetched: [EKReminder] = await withCheckedContinuation { cont in
            store.fetchReminders(matching: pred) { list in
                cont.resume(returning: list ?? [])
            }
        }
        _ = store
        let cutoffMs: Int64? = upToDate.map { date in
            let endOfDay = Calendar.current.date(bySettingHour: 23, minute: 59, second: 59, of: date) ?? date
            return Int64(endOfDay.timeIntervalSince1970 * 1000.0)
        }
        return fetched.compactMap { rem in
            let cleanTitle = (rem.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleanTitle.isEmpty else { return nil }
            let dueMs: Int64? = {
                guard let comps = rem.dueDateComponents,
                      let date = Calendar.current.date(from: comps) else { return nil }
                return Int64(date.timeIntervalSince1970 * 1000.0)
            }()
            if let cutoffMs, let dueMs, dueMs > cutoffMs {
                return nil
            }
            return ReminderTransferRecord(
                id: rem.calendarItemIdentifier,
                title: cleanTitle,
                notes: rem.notes,
                listName: rem.calendar?.title,
                isCompleted: rem.isCompleted,
                priority: max(0, min(9, rem.priority)),
                dueEpochMillis: dueMs
            )
        }
    }

    private static func reminderSignature(listName: String, title: String, dueMs: Int64?) -> String {
        let dueBucket = dueMs.map { $0 / 60_000 } ?? -1
        return "\(listName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())|\(title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())|\(dueBucket)"
    }

    private static func populateEKReminder(
        _ rem: EKReminder,
        from rec: ReminderTransferRecord,
        calendar: EKCalendar
    ) {
        let cleanTitle = rec.title.trimmingCharacters(in: .whitespacesAndNewlines)
        rem.calendar = calendar
        rem.title = cleanTitle.isEmpty ? "Promemoria" : cleanTitle
        rem.notes = rec.notes
        rem.isCompleted = rec.isCompleted
        rem.completionDate = rec.isCompleted ? Date() : nil
        rem.priority = max(0, min(9, rec.priority))
        if let dueMs = rec.dueEpochMillis {
            let dueDate = Date(timeIntervalSince1970: TimeInterval(dueMs) / 1000.0)
            var comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: dueDate)
            comps.calendar = Calendar.current
            comps.timeZone = Calendar.current.timeZone
            rem.dueDateComponents = comps
        } else {
            rem.dueDateComponents = nil
        }
    }

    static func importRemindersWithStats(_ incoming: [ReminderTransferRecord]) async -> (imported: Int, alreadyPresent: Int) {
        guard !incoming.isEmpty, canWrite() else { return (0, 0) }
        let store = EKEventStore()
        guard let fallbackCalendar = iOSEventStoreHelpers.resolveWritableCalendar(
            in: store,
            entityType: .reminder,
            fallbackTitle: "Promemoria"
        ) else {
            return (0, 0)
        }

        var existingSignatures = Set<String>()
        if isAuthorized() {
            let existingPred = store.predicateForReminders(in: nil)
            let existingList: [EKReminder] = await withCheckedContinuation { cont in
                store.fetchReminders(matching: existingPred) { list in
                    cont.resume(returning: list ?? [])
                }
            }
            for rem in existingList {
                let normList = rem.calendar?.title ?? ""
                let normTitle = (rem.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                guard !normTitle.isEmpty else { continue }
                let dueMs: Int64? = rem.dueDateComponents.flatMap { Calendar.current.date(from: $0) }
                    .map { Int64($0.timeIntervalSince1970 * 1000.0) }
                existingSignatures.insert(reminderSignature(listName: normList, title: normTitle, dueMs: dueMs))
            }
        }

        // Pre-creiamo le liste prima di accodare i promemoria con commit: false (evita conflitti nello stesso EKEventStore).
        var calendarCache = iOSEventStoreHelpers.writableCalendarsByLowerTitle(in: store, entityType: .reminder)
        var pending: [(record: ReminderTransferRecord, calendar: EKCalendar)] = []
        var alreadyPresent = 0

        for rec in incoming {
            let cleanTitle = rec.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleanTitle.isEmpty else { continue }
            let targetCal = iOSEventStoreHelpers.ensureTargetCalendar(
                named: rec.listName,
                entityType: .reminder,
                in: store,
                fallback: fallbackCalendar,
                cache: &calendarCache
            )
            let sig = reminderSignature(listName: targetCal.title, title: cleanTitle, dueMs: rec.dueEpochMillis)
            if existingSignatures.contains(sig) {
                alreadyPresent += 1
                continue
            }
            existingSignatures.insert(sig)
            pending.append((rec, targetCal))
        }

        guard !pending.isEmpty else {
            return (0, alreadyPresent)
        }

        var queuedCount = 0
        for item in pending {
            let rem = EKReminder(eventStore: store)
            populateEKReminder(rem, from: item.record, calendar: item.calendar)
            if (try? store.save(rem, commit: false)) != nil {
                queuedCount += 1
            }
        }
        if queuedCount > 0, (try? store.commit()) != nil {
            return (queuedCount, alreadyPresent)
        }

        // Fallback atomico per singolo promemoria su nuovo EKEventStore
        store.reset()
        let freshStore = EKEventStore()
        let freshFallback = iOSEventStoreHelpers.resolveWritableCalendar(
            in: freshStore,
            entityType: .reminder,
            fallbackTitle: "Promemoria"
        ) ?? fallbackCalendar
        var freshCache = iOSEventStoreHelpers.writableCalendarsByLowerTitle(in: freshStore, entityType: .reminder)
        var savedIndividually = 0

        for item in pending {
            let targetCal = freshCache[item.calendar.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()]
                ?? freshFallback
            let rem = EKReminder(eventStore: freshStore)
            populateEKReminder(rem, from: item.record, calendar: targetCal)
            if (try? freshStore.save(rem, commit: true)) != nil {
                savedIndividually += 1
                continue
            }
            freshStore.reset()
            let remFallback = EKReminder(eventStore: freshStore)
            populateEKReminder(remFallback, from: item.record, calendar: freshFallback)
            if (try? freshStore.save(remFallback, commit: true)) != nil {
                savedIndividually += 1
            } else {
                freshStore.reset()
            }
        }
        return (savedIndividually, alreadyPresent)
    }

    static func importReminders(_ incoming: [ReminderTransferRecord]) async -> Int {
        await importRemindersWithStats(incoming).imported
    }
}
