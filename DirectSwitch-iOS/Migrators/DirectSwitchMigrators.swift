//
//  DirectSwitchMigrators.swift
//  DirectSwitch-iOS
//
//  Created by Nicolas Donati.
//  Copyright © 2026 Nicolas Donati. Tutti i diritti riservati.
//

import Foundation
import Contacts
import CoreLocation
import Photos
import EventKit
import StoreKit
import UIKit

/// Riepilogo locale dei dati e dello spazio disponibile sull'iPhone (parità con `LocalDeviceScanSummary` Android).
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
    let whatsappArchivesCount: Int
    let freeStorageBytes: Int64
    let totalStorageBytes: Int64
    let hasFullPermissions: Bool
    var contactsDenied: Bool = false
    var photosDenied: Bool = false
    var calendarsDenied: Bool = false
    var remindersDenied: Bool = false
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
        knownRemindersCount: Int = 0
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
        var videosCount = 0
        var videosBytes: Int64 = 0

        if photosAuth {
            let fetched = PHAsset.fetchAssets(with: nil)
            fetched.enumerateObjects { asset, _, _ in
                if asset.mediaType == .image {
                    photosCount += 1
                    if asset.mediaSubtypes.contains(.photoLive) {
                        livePhotosCount += 1
                        photosBytes += 4_800_000
                    } else {
                        photosBytes += 2_800_000
                    }
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
            livePhotosCount: livePhotosCount,
            photosBytes: photosBytes,
            videosCount: videosCount,
            videosBytes: videosBytes,
            calendarEventsCount: calendarCount,
            remindersCount: knownRemindersCount,
            documentsCount: docsCount,
            whatsappArchivesCount: waCount,
            freeStorageBytes: freeBytes,
            totalStorageBytes: totalBytes,
            hasFullPermissions: contactsAuth && photosAuth && calAuth && remAuth,
            contactsDenied: contactsDenied,
            photosDenied: photosDenied,
            calendarsDenied: calendarsDenied,
            remindersDenied: remindersDenied
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

        let creationDate: Date? = item.capturedEpochMillis > 0
            ? Date(timeIntervalSince1970: TimeInterval(item.capturedEpochMillis) / 1000.0)
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
        if item.category == .PHOTOS,
           let liveURL = pairedLiveVideoURL,
           FileManager.default.fileExists(atPath: liveURL.path) {
            let rawLiveName = URL(fileURLWithPath: item.livePhotoVideoFileName ?? "").lastPathComponent
            let finalLiveName = rawLiveName.isEmpty ? "live_\(UUID().uuidString).mov" : rawLiveName
            do {
                try await PHPhotoLibrary.shared().performChanges {
                    let req = PHAssetCreationRequest.forAsset()
                    let photoOpts = PHAssetResourceCreationOptions()
                    photoOpts.originalFilename = finalName
                    photoOpts.shouldMoveFile = false
                    req.addResource(with: .photo, fileURL: fileURL, options: photoOpts)

                    let liveOpts = PHAssetResourceCreationOptions()
                    liveOpts.originalFilename = finalLiveName
                    liveOpts.shouldMoveFile = false
                    req.addResource(with: .pairedVideo, fileURL: liveURL, options: liveOpts)

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
                        req.addResource(with: .video, fileURL: fileURL, options: resOpts)
                    } else {
                        req.addResource(with: .photo, fileURL: fileURL, options: resOpts)
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
                            ? PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: fileURL)
                            : PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: fileURL)
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

    /// Scansiona Foto, Live Photos e Video del Rullino iOS preservando Album utente, Preferiti (❤️), coordinate GPS
    /// e usando un ID deterministico basato su `localIdentifier` così il Resume funziona anche dopo nuovi scatti/screenshot.
    static func scanLibraryAssetsWithMetadata(
        includePhotos: Bool,
        includeVideos: Bool
    ) async -> (items: [(ManifestItem, PHAsset)], iCloudOptimizedCount: Int) {
        guard includePhotos || includeVideos else { return ([], 0) }
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        guard status == .authorized || status == .limited else { return ([], 0) }

        let albumMap = buildAssetAlbumMap()
        let opts = PHFetchOptions()
        opts.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        let fetched = PHAsset.fetchAssets(with: opts)
        var out: [(ManifestItem, PHAsset)] = []
        var cloudOptimized = 0

        fetched.enumerateObjects { asset, idx, _ in
            let isVideo = asset.mediaType == .video
            let isPhoto = asset.mediaType == .image
            if (isVideo && !includeVideos) || (isPhoto && !includePhotos) || (!isVideo && !isPhoto) {
                return
            }
            guard let primary = primaryMediaResource(for: asset) else { return }
            if let locallyAvailable = primary.value(forKey: "locallyAvailable") as? Bool, !locallyAvailable {
                cloudOptimized += 1
            }
            let pairedLive = isPhoto ? pairedLiveVideoResource(for: asset) : nil
            let size = (primary.value(forKey: "fileSize") as? Int64) ?? 1_048_576
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
                livePhotoVideoFileName: pairedLive?.originalFilename
            )
            out.append((item, asset))
        }
        return (out, cloudOptimized)
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

    /// Esporta un `PHAsset` direttamente su file temporaneo su disco con triplo livello di resilienza
    /// contro rallentamenti di `assetsd` su librerie da 5.000+ elementi o risorse modificate.
    static func exportAssetToTempFile(_ asset: PHAsset) async -> URL? {
        if let primary = primaryMediaResource(for: asset) {
            if let exported = await exportResourceToTempFile(primary, prefix: "ds_exp") {
                return exported
            }
            // Livello 2: breve attesa se il demone PhotoKit (`assetsd`) è saturo e tentativo sulla risorsa base originale
            try? await Task.sleep(nanoseconds: 250_000_000)
            let resources = PHAssetResource.assetResources(for: asset)
            let fallbackRes: PHAssetResource? = {
                if asset.mediaType == .video {
                    return resources.first(where: { $0.type == .video && $0 != primary }) ?? primary
                } else {
                    return resources.first(where: { $0.type == .photo && $0 != primary }) ?? primary
                }
            }()
            if let fallbackRes, let exported = await exportResourceToTempFile(fallbackRes, prefix: "ds_exp_fb") {
                return exported
            }
        }

        // Livello 3 (per foto): fallback tramite PHImageManager ad alta qualità
        if asset.mediaType == .image {
            return await exportImageViaImageManager(asset)
        }
        return nil
    }

    private static func exportImageViaImageManager(_ asset: PHAsset) async -> URL? {
        await withCheckedContinuation { continuation in
            let opts = PHImageRequestOptions()
            opts.isNetworkAccessAllowed = true
            opts.deliveryMode = .highQualityFormat
            opts.version = .current
            opts.isSynchronous = false

            final class ResumeGuard: @unchecked Sendable {
                private let lock = NSLock()
                private var resumed = false
                func tryClaim() -> Bool {
                    lock.lock()
                    defer { lock.unlock() }
                    if resumed { return false }
                    resumed = true
                    return true
                }
            }
            let guardBox = ResumeGuard()

            PHImageManager.default().requestImageDataAndOrientation(for: asset, options: opts) { data, _, _, info in
                let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                if isDegraded { return }
                guard guardBox.tryClaim() else { return }
                guard let data, !data.isEmpty else {
                    continuation.resume(returning: nil)
                    return
                }
                let destURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent("ds_imgmgr_\(UUID().uuidString).jpg")
                do {
                    try data.write(to: destURL, options: .atomic)
                    continuation.resume(returning: destURL)
                } catch {
                    try? FileManager.default.removeItem(at: destURL)
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    /// Esporta la componente video `.MOV` accoppiata di una Live Photo su file temporaneo.
    static func exportLivePairedVideoToTempFile(_ asset: PHAsset) async -> URL? {
        guard let paired = pairedLiveVideoResource(for: asset) else { return nil }
        return await exportResourceToTempFile(paired, prefix: "ds_live")
    }

    private static func exportResourceToTempFile(_ resource: PHAssetResource, prefix: String) async -> URL? {
        let safeName = URL(fileURLWithPath: resource.originalFilename).lastPathComponent
        let destURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)_\(UUID().uuidString)_\(safeName.isEmpty ? "asset.bin" : safeName)")
        try? FileManager.default.removeItem(at: destURL)

        return await withCheckedContinuation { continuation in
            let opts = PHAssetResourceRequestOptions()
            opts.isNetworkAccessAllowed = true
            PHAssetResourceManager.default().writeData(
                for: resource,
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
    static func isPasswordsCsvFile(_ fileName: String) -> Bool {
        URL(fileURLWithPath: fileName).pathExtension.lowercased() == "csv"
    }

    static func mimeForExtension(_ ext: String) -> String {
        switch ext.lowercased() {
        case "pdf": return "application/pdf"
        case "zip": return "application/zip"
        case "txt": return "text/plain"
        case "csv": return "text/csv"
        case "vcf": return "text/vcard"
        case "ics": return "text/calendar"
        case "m4a": return "audio/mp4"
        case "mp3": return "audio/mpeg"
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

    /// Ricostruisce in sicurezza la gerarchia di sottocartelle dentro `Su iPhone -> DirectSwitch -> DirectSwitch_Documenti`.
    static func sanitizedRelativeComponents(_ rawFolder: String) -> [String] {
        let normalized = rawFolder.replacingOccurrences(of: "\\", with: "/")
        return normalized
            .split(separator: "/")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0 != "." && $0 != ".." }
    }

    static func targetDirectory(for item: ManifestItem) -> URL? {
        guard let docsRoot = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return nil
        }
        var dir = docsRoot.appendingPathComponent("DirectSwitch_Documenti", isDirectory: true)
        if item.category == .WHATSAPP_VAULT {
            dir = dir.appendingPathComponent("WhatsApp_Vault", isDirectory: true)
        } else {
            for comp in sanitizedRelativeComponents(item.relativeAlbumOrFolder) {
                dir = dir.appendingPathComponent(comp, isDirectory: true)
            }
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
            do {
                try FileManager.default.copyItem(at: sourceURL, to: stagedURL)
                if removeInboxIfApplicable && sourceURL.path.contains("/Documents/Inbox/") {
                    try? FileManager.default.removeItem(at: sourceURL)
                }
                let attrs = try FileManager.default.attributesOfItem(atPath: stagedURL.path)
                let size = (attrs[.size] as? Int64) ?? (attrs[.size] as? NSNumber)?.int64Value ?? 0
                guard size > 0 else {
                    try? FileManager.default.removeItem(at: stagedURL)
                    return
                }
                let modDate = (attrs[.modificationDate] as? Date) ?? Date()
                let modMs = Int64(modDate.timeIntervalSince1970 * 1000.0)
                let lower = safeName.lowercased()
                let ext = sourceURL.pathExtension.lowercased()
                let isWhatsApp = lower.contains("whatsapp") || ext == "opus" || (ext == "zip" && lower.contains("chat"))
                let category: TransferCategory = isWhatsApp ? .WHATSAPP_VAULT : .DOCUMENTS
                let folderToUse = isWhatsApp ? "WhatsApp_Vault" : (relativeFolder.isEmpty ? "Documenti" : relativeFolder)
                let item = ManifestItem(
                    id: "doc_\(UUID().uuidString.prefix(8).lowercased())_\(counter)",
                    category: category,
                    fileName: safeName,
                    relativeAlbumOrFolder: folderToUse,
                    sizeBytes: size,
                    capturedEpochMillis: modMs,
                    dedupKey: "\(folderToUse.lowercased())/\(lower)_\(size)_\(modMs)",
                    mimeType: mimeForExtension(ext)
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
                let rootFolderName = url.lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
                let cleanRoot = rootFolderName.isEmpty ? "Cartella_iPhone" : rootFolderName
                let resolvedRootPath = url.resolvingSymlinksInPath().path
                if let enumerator = FileManager.default.enumerator(
                    at: url,
                    includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey],
                    options: [.skipsHiddenFiles]
                ) {
                    for case let childURL as URL in enumerator {
                        let vals = try? childURL.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey])
                        if vals?.isDirectory == true { continue }
                        let childDirPath = childURL.deletingLastPathComponent().resolvingSymlinksInPath().path
                        var subRel = ""
                        if childDirPath.hasPrefix(resolvedRootPath) {
                            subRel = String(childDirPath.dropFirst(resolvedRootPath.count))
                                .trimmingCharacters(in: CharacterSet(charactersIn: "/\\"))
                        }
                        let fullRel = subRel.isEmpty ? cleanRoot : "\(cleanRoot)/\(subRel)"
                        stageSingleFile(sourceURL: childURL, relativeFolder: fullRel, removeInboxIfApplicable: false)
                    }
                }
            } else {
                let ext = url.pathExtension.lowercased()
                let defaultFolder = ext == "csv" ? "Password_Esportate" : "Documenti"
                stageSingleFile(sourceURL: url, relativeFolder: defaultFolder, removeInboxIfApplicable: true)
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

    static func readEvents() -> [CalendarEventRecord] {
        guard isAuthorized() else { return [] }
        let store = EKEventStore()
        // Finestra ampia (-10 anni .. +10 anni) per non perdere appuntamenti storici o ricorrenze annuali
        let start = Date().addingTimeInterval(-365 * 86400 * 10)
        let end = Date().addingTimeInterval(365 * 86400 * 10)
        let pred = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        return store.events(matching: pred).map { ev in
            let rule = ev.recurrenceRules?.first
            let alarmOffset = ev.alarms?.first?.relativeOffset
            return CalendarEventRecord(
                id: ev.eventIdentifier ?? UUID().uuidString,
                title: ev.title ?? "Evento",
                description: ev.notes,
                location: ev.location,
                startEpochMillis: Int64(ev.startDate.timeIntervalSince1970 * 1000.0),
                endEpochMillis: Int64(ev.endDate.timeIntervalSince1970 * 1000.0),
                allDay: ev.isAllDay,
                calendarTitle: ev.calendar?.title,
                recurrenceFrequency: rule.map { encodeFrequency($0.frequency) },
                recurrenceInterval: rule.map { max(1, $0.interval) },
                alarmOffsetSeconds: alarmOffset
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
            if let freq = decodeFrequency(rec.recurrenceFrequency) {
                let rule = EKRecurrenceRule(
                    recurrenceWith: freq,
                    interval: max(1, rec.recurrenceInterval ?? 1),
                    end: nil
                )
                ev.addRecurrenceRule(rule)
            }
            if let offset = rec.alarmOffsetSeconds {
                ev.addAlarm(EKAlarm(relativeOffset: offset))
            }
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

/// Migratore nativo dei Promemoria Apple (`EKReminder`) senza iCloud, con conservazione delle liste, scadenze, note e priorità.
enum iOSRemindersMigrator {
    static func isAuthorized() -> Bool {
        let status = EKEventStore.authorizationStatus(for: .reminder)
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
            return (try? await store.requestFullAccessToReminders()) ?? false
        } else {
            return (try? await store.requestAccess(to: .reminder)) ?? false
        }
    }

    static func readReminders() async -> [ReminderTransferRecord] {
        guard isAuthorized() else { return [] }
        let store = EKEventStore()
        let pred = store.predicateForReminders(in: nil)
        let fetched: [EKReminder] = await withCheckedContinuation { cont in
            store.fetchReminders(matching: pred) { list in
                cont.resume(returning: list ?? [])
            }
        }
        return fetched.compactMap { rem in
            let cleanTitle = (rem.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleanTitle.isEmpty else { return nil }
            let dueMs: Int64? = {
                guard let comps = rem.dueDateComponents,
                      let date = Calendar.current.date(from: comps) else { return nil }
                return Int64(date.timeIntervalSince1970 * 1000.0)
            }()
            return ReminderTransferRecord(
                id: rem.calendarItemIdentifier,
                title: cleanTitle,
                notes: rem.notes,
                listName: rem.calendar?.title,
                isCompleted: rem.isCompleted,
                priority: rem.priority,
                dueEpochMillis: dueMs
            )
        }
    }

    static func importReminders(_ incoming: [ReminderTransferRecord]) async -> Int {
        guard !incoming.isEmpty, isAuthorized() else { return 0 }
        let store = EKEventStore()
        guard let fallbackCalendar = store.defaultCalendarForNewReminders() else { return 0 }

        let existingPred = store.predicateForReminders(in: nil)
        let existingList: [EKReminder] = await withCheckedContinuation { cont in
            store.fetchReminders(matching: existingPred) { list in
                cont.resume(returning: list ?? [])
            }
        }

        var existingSignatures = Set<String>()
        for rem in existingList {
            let normList = (rem.calendar?.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let normTitle = (rem.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if !normTitle.isEmpty {
                existingSignatures.insert("\(normList)|\(normTitle)")
            }
        }

        var calendarsByLowerName: [String: EKCalendar] = [:]
        for cal in store.calendars(for: .reminder) where cal.allowsContentModifications {
            calendarsByLowerName[cal.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()] = cal
        }

        func targetList(named rawName: String?) -> EKCalendar {
            let trimmed = (rawName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return fallbackCalendar }
            let lower = trimmed.lowercased()
            if let existingCal = calendarsByLowerName[lower] {
                return existingCal
            }
            let newCal = EKCalendar(for: .reminder, eventStore: store)
            newCal.title = trimmed
            newCal.source = fallbackCalendar.source
            if (try? store.saveCalendar(newCal, commit: true)) != nil {
                calendarsByLowerName[lower] = newCal
                return newCal
            }
            return fallbackCalendar
        }

        var imported = 0
        for rec in incoming {
            let cleanTitle = rec.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleanTitle.isEmpty else { continue }
            let targetCal = targetList(named: rec.listName)
            let sig = "\(targetCal.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())|\(cleanTitle.lowercased())"
            if existingSignatures.contains(sig) {
                continue
            }

            let rem = EKReminder(eventStore: store)
            rem.calendar = targetCal
            rem.title = cleanTitle
            rem.notes = rec.notes
            rem.isCompleted = rec.isCompleted
            rem.priority = rec.priority
            if let dueMs = rec.dueEpochMillis {
                let dueDate = Date(timeIntervalSince1970: TimeInterval(dueMs) / 1000.0)
                rem.dueDateComponents = Calendar.current.dateComponents(
                    [.year, .month, .day, .hour, .minute],
                    from: dueDate
                )
            }
            if (try? store.save(rem, commit: false)) != nil {
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
