//
//  DirectSwitchAppMigrationEngine.swift
//  DirectSwitch-iOS
//
//  Created by Nicolas Donati.
//  Copyright © 2026 Nicolas Donati. Tutti i diritti riservati.
//

import Foundation
import Photos
import SwiftUI
import StoreKit
import UIKit
import Vision

/// Descrittore delle app più diffuse su iOS interrogabili istantaneamente tramite `LSApplicationQueriesSchemes`.
struct iOSKnownAppProbe: Sendable {
    let bundleId: String
    let appName: String
    let urlScheme: String
    let appStoreId: Int
}

/// Cache asincrona thread-safe dei metadati App Store (icone ufficiali e `trackId` numerico).
private actor AppStoreMetadataCache {
    static let shared = AppStoreMetadataCache()

    private var byBundleId: [String: (trackId: Int, iconUrl: String?, trackName: String)] = [:]
    private var byNormalizedName: [String: InstalledAppRecord] = [:]

    func getByBundle(_ bundleId: String) -> (trackId: Int, iconUrl: String?, trackName: String)? {
        byBundleId[bundleId.lowercased()]
    }

    func setByBundle(_ bundleId: String, trackId: Int, iconUrl: String?, trackName: String) {
        byBundleId[bundleId.lowercased()] = (trackId, iconUrl, trackName)
    }

    func getByName(_ name: String) -> InstalledAppRecord? {
        byNormalizedName[name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)]
    }

    func setByName(_ name: String, record: InstalledAppRecord) {
        byNormalizedName[name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)] = record
    }
}

/// Scanner delle app installate sull'iPhone mittente (combina rilevamento istantaneo `canOpenURL`,
/// lettura automatica da screenshot Home / Impostazioni tramite Apple `Vision` OCR locale e ricerca diretta App Store).
enum iOSInstalledAppsScanner {
    private static let customAppsStorageKey = "directswitch_custom_sender_apps_v1"

    /// Tutti gli schemi dichiarati in `Info.plist` (`<= 50` secondo il limite di sistema Apple iOS 15+).
    static let knownProbes: [iOSKnownAppProbe] = [
        iOSKnownAppProbe(bundleId: "net.whatsapp.WhatsApp", appName: "WhatsApp Messenger", urlScheme: "whatsapp-consumer", appStoreId: 310633997),
        iOSKnownAppProbe(bundleId: "net.whatsapp.WhatsAppSMB", appName: "WhatsApp Business", urlScheme: "whatsapp-smb", appStoreId: 1386412985),
        iOSKnownAppProbe(bundleId: "com.burbn.instagram", appName: "Instagram", urlScheme: "instagram", appStoreId: 389801252),
        iOSKnownAppProbe(bundleId: "ph.telegra.Telegraph", appName: "Telegram Messenger", urlScheme: "tg", appStoreId: 686449807),
        iOSKnownAppProbe(bundleId: "com.facebook.Facebook", appName: "Facebook", urlScheme: "fb", appStoreId: 284882215),
        iOSKnownAppProbe(bundleId: "com.facebook.Messenger", appName: "Messenger", urlScheme: "fb-messenger", appStoreId: 454638411),
        iOSKnownAppProbe(bundleId: "com.zhiliaoapp.musically", appName: "TikTok", urlScheme: "tiktok", appStoreId: 835599320),
        iOSKnownAppProbe(bundleId: "com.google.ios.youtube", appName: "YouTube", urlScheme: "youtube", appStoreId: 544007664),
        iOSKnownAppProbe(bundleId: "com.google.Gmail", appName: "Gmail", urlScheme: "googlegmail", appStoreId: 422689480),
        iOSKnownAppProbe(bundleId: "com.google.Maps", appName: "Google Maps", urlScheme: "comgooglemaps", appStoreId: 585027354),
        iOSKnownAppProbe(bundleId: "com.google.chrome.ios", appName: "Google Chrome", urlScheme: "googlechrome", appStoreId: 535886823),
        iOSKnownAppProbe(bundleId: "com.google.Drive", appName: "Google Drive", urlScheme: "googledrive", appStoreId: 507874739),
        iOSKnownAppProbe(bundleId: "com.google.photos", appName: "Google Foto", urlScheme: "googlephotos", appStoreId: 962194608),
        iOSKnownAppProbe(bundleId: "com.google.GoogleMobile", appName: "Google", urlScheme: "googleapp", appStoreId: 284815942),
        iOSKnownAppProbe(bundleId: "com.google.Authenticator", appName: "Google Authenticator", urlScheme: "otpauth", appStoreId: 388497605),
        iOSKnownAppProbe(bundleId: "com.spotify.client", appName: "Spotify", urlScheme: "spotify", appStoreId: 324684580),
        iOSKnownAppProbe(bundleId: "com.netflix.Netflix", appName: "Netflix", urlScheme: "nflx", appStoreId: 363590051),
        iOSKnownAppProbe(bundleId: "com.amazon.aiv.AIVApp", appName: "Amazon Prime Video", urlScheme: "aiv", appStoreId: 545519333),
        iOSKnownAppProbe(bundleId: "com.disney.disneyplus", appName: "Disney+", urlScheme: "disneyplus", appStoreId: 1446075923),
        iOSKnownAppProbe(bundleId: "com.dazn.theApp", appName: "DAZN", urlScheme: "dazn", appStoreId: 1119332524),
        iOSKnownAppProbe(bundleId: "com.amazon.AmazonIT", appName: "Amazon Shopping", urlScheme: "com.amazon.mobile.shopping", appStoreId: 297606951),
        iOSKnownAppProbe(bundleId: "com.yourcompany.PPClient", appName: "PayPal", urlScheme: "paypal", appStoreId: 283646709),
        iOSKnownAppProbe(bundleId: "com.revolut.revolut", appName: "Revolut", urlScheme: "revolut", appStoreId: 932493382),
        iOSKnownAppProbe(bundleId: "com.satispay.consumer", appName: "Satispay", urlScheme: "satispay", appStoreId: 934438340),
        iOSKnownAppProbe(bundleId: "com.microsoft.Office.Outlook", appName: "Microsoft Outlook", urlScheme: "ms-outlook", appStoreId: 951937596),
        iOSKnownAppProbe(bundleId: "com.microsoft.skype.teams", appName: "Microsoft Teams", urlScheme: "msteams", appStoreId: 1113153706),
        iOSKnownAppProbe(bundleId: "com.microsoft.azureauthenticator", appName: "Microsoft Authenticator", urlScheme: "msauth", appStoreId: 983156458),
        iOSKnownAppProbe(bundleId: "us.zoom.videomeetings", appName: "Zoom Workplace", urlScheme: "zoomus", appStoreId: 546505307),
        iOSKnownAppProbe(bundleId: "com.atebits.Tweetie2", appName: "X", urlScheme: "twitter", appStoreId: 333903271),
        iOSKnownAppProbe(bundleId: "com.burbn.barcelona", appName: "Threads", urlScheme: "barcelona", appStoreId: 6446901002),
        iOSKnownAppProbe(bundleId: "com.linkedin.LinkedIn", appName: "LinkedIn", urlScheme: "linkedin", appStoreId: 288429040),
        iOSKnownAppProbe(bundleId: "com.toyopagroup.picaboo", appName: "Snapchat", urlScheme: "snapchat", appStoreId: 447188370),
        iOSKnownAppProbe(bundleId: "pinterest", appName: "Pinterest", urlScheme: "pinterest", appStoreId: 429047995),
        iOSKnownAppProbe(bundleId: "com.reddit.Reddit", appName: "Reddit", urlScheme: "reddit", appStoreId: 1064216828),
        iOSKnownAppProbe(bundleId: "com.hammerandchisel.discord", appName: "Discord", urlScheme: "discord", appStoreId: 985746746),
        iOSKnownAppProbe(bundleId: "tv.twitch", appName: "Twitch", urlScheme: "twitch", appStoreId: 460177396),
        iOSKnownAppProbe(bundleId: "com.waze.iphone", appName: "Waze", urlScheme: "waze", appStoreId: 323229106),
        iOSKnownAppProbe(bundleId: "com.ubercab.UberClient", appName: "Uber", urlScheme: "uber", appStoreId: 368677368),
        iOSKnownAppProbe(bundleId: "it.subito.iphone", appName: "Subito", urlScheme: "subito", appStoreId: 385368449),
        iOSKnownAppProbe(bundleId: "fr.vinted", appName: "Vinted", urlScheme: "vinted", appStoreId: 999479354),
        iOSKnownAppProbe(bundleId: "com.booking.BookingApp", appName: "Booking.com", urlScheme: "booking", appStoreId: 367003839),
        iOSKnownAppProbe(bundleId: "com.airbnb.app", appName: "Airbnb", urlScheme: "airbnb", appStoreId: 401626263),
        iOSKnownAppProbe(bundleId: "com.openai.chat", appName: "ChatGPT", urlScheme: "chatgpt", appStoreId: 6448311069),
        iOSKnownAppProbe(bundleId: "com.shazam.Shazam", appName: "Shazam", urlScheme: "shazam", appStoreId: 284993459),
        iOSKnownAppProbe(bundleId: "com.canva.canvaeditor", appName: "Canva", urlScheme: "canva", appStoreId: 897446215),
        iOSKnownAppProbe(bundleId: "com.ebay.iphone", appName: "eBay", urlScheme: "ebay", appStoreId: 282614216),
        iOSKnownAppProbe(bundleId: "it.pagopa.app.io", appName: "IO", urlScheme: "ioit", appStoreId: 1505842859),
        iOSKnownAppProbe(bundleId: "posteitaliane.posteapp.appposteid", appName: "PosteID", urlScheme: "posteid", appStoreId: 1078512138)
    ]

    /// Suggerimenti rapidi italiani (SPID/CIE, Banche, Operatori, Trasporti) aggiungibili con 1 tocco sul mittente.
    static let italianQuickSuggestions: [InstalledAppRecord] = [
        InstalledAppRecord(packageName: "it.pagopa.app.io", appName: "IO", appStoreId: 1505842859, urlScheme: "ioit"),
        InstalledAppRecord(packageName: "it.ipzs.cieid", appName: "CieID", appStoreId: 1517873615),
        InstalledAppRecord(packageName: "posteitaliane.posteapp.appposteid", appName: "PosteID", appStoreId: 1078512138, urlScheme: "posteid"),
        InstalledAppRecord(packageName: "it.aruba.pec.mobile", appName: "Aruba PEC"),
        InstalledAppRecord(packageName: "com.intesasanpaolo.mobile", appName: "Intesa Sanpaolo Mobile"),
        InstalledAppRecord(packageName: "it.unicredit.mobile", appName: "UniCredit Mobile Banking"),
        InstalledAppRecord(packageName: "posteitaliane.posteapp.appbpol", appName: "BancoPosta"),
        InstalledAppRecord(packageName: "posteitaliane.posteapp.apppostepay", appName: "Postepay"),
        InstalledAppRecord(packageName: "com.fineco.it", appName: "Fineco"),
        InstalledAppRecord(packageName: "com.trenitalia.app", appName: "Trenitalia"),
        InstalledAppRecord(packageName: "it.ntvspa.italo", appName: "Italo Treno"),
        InstalledAppRecord(packageName: "com.easypark.iphone", appName: "EasyPark"),
        InstalledAppRecord(packageName: "it.mooneygo.app", appName: "MooneyGo"),
        InstalledAppRecord(packageName: "com.deliveroo.orderapp", appName: "Deliveroo"),
        InstalledAppRecord(packageName: "com.glovo.app", appName: "Glovo"),
        InstalledAppRecord(packageName: "com.canva.canvaeditor", appName: "Canva"),
        InstalledAppRecord(packageName: "com.lemon.lvoverseas", appName: "CapCut")
    ]

    private static let whitelistedSchemes: Set<String> = Set(knownProbes.map(\.urlScheme) + ["whatsapp", "com.cloudsave.ios"])

    @MainActor
    static func canOpenScheme(_ rawScheme: String) -> Bool {
        let clean = rawScheme
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "://", with: "")
        guard !clean.isEmpty, whitelistedSchemes.contains(clean),
              let url = URL(string: "\(clean)://") else {
            return false
        }
        return UIApplication.shared.canOpenURL(url)
    }

    @MainActor
    static func isPersonalWhatsAppInstalled() -> Bool {
        if canOpenScheme("whatsapp-consumer") {
            return true
        }
        // Se WhatsApp Business NON è installato, lo schema generico `whatsapp://` appartiene a WhatsApp Personale
        if !canOpenScheme("whatsapp-smb") && canOpenScheme("whatsapp") {
            return true
        }
        return false
    }

    @MainActor
    static func isWhatsAppBusinessInstalled() -> Bool {
        canOpenScheme("whatsapp-smb")
    }

    @MainActor
    static func isAppAlreadyInstalledOnThisPhone(_ app: InstalledAppRecord) -> Bool {
        if app.packageName == "net.whatsapp.WhatsApp" || app.appStoreId == 310633997 {
            return isPersonalWhatsAppInstalled()
        }
        if app.packageName == "net.whatsapp.WhatsAppSMB" || app.appStoreId == 1386412985 {
            return isWhatsAppBusinessInstalled()
        }
        if let scheme = app.urlScheme, !scheme.isEmpty, canOpenScheme(scheme) {
            return true
        }
        if let probe = knownProbes.first(where: {
            $0.bundleId.caseInsensitiveCompare(app.packageName) == .orderedSame
                || ($0.appStoreId == app.appStoreId && app.appStoreId != nil)
                || $0.appName.caseInsensitiveCompare(app.appName) == .orderedSame
        }) {
            if probe.bundleId == "net.whatsapp.WhatsApp" {
                return isPersonalWhatsAppInstalled()
            }
            return canOpenScheme(probe.urlScheme)
        }
        return false
    }

    /// Rileva istantaneamente tutte le app installate su questo iPhone interrogando gli schemi registrati
    /// e unendole alle eventuali app aggiuntive salvate dall'utente (via ricerca o screenshot Home/Impostazioni).
    @MainActor
    static func scanLocallyInstalledApps() -> [InstalledAppRecord] {
        var detected: [InstalledAppRecord] = []
        var seenBundles = Set<String>()
        var seenStoreIds = Set<Int>()

        for probe in knownProbes {
            let isInstalled: Bool
            if probe.bundleId == "net.whatsapp.WhatsApp" {
                isInstalled = isPersonalWhatsAppInstalled()
            } else {
                isInstalled = canOpenScheme(probe.urlScheme)
            }
            if isInstalled {
                seenBundles.insert(probe.bundleId.lowercased())
                seenStoreIds.insert(probe.appStoreId)
                detected.append(
                    InstalledAppRecord(
                        packageName: probe.bundleId,
                        appName: probe.appName,
                        appStoreId: probe.appStoreId,
                        iconUrl: nil,
                        urlScheme: probe.urlScheme
                    )
                )
            }
        }

        for extra in loadSavedCustomApps() {
            let bundleKey = extra.packageName.lowercased()
            if seenBundles.contains(bundleKey) { continue }
            if let sid = extra.appStoreId, seenStoreIds.contains(sid) { continue }
            seenBundles.insert(bundleKey)
            if let sid = extra.appStoreId { seenStoreIds.insert(sid) }
            detected.append(extra)
        }

        return detected
    }

    static func loadSavedCustomApps() -> [InstalledAppRecord] {
        guard let data = UserDefaults.standard.data(forKey: customAppsStorageKey),
              let decoded = try? JSONDecoder().decode([InstalledAppRecord].self, from: data) else {
            return []
        }
        return decoded
    }

    static func saveCustomApps(_ apps: [InstalledAppRecord]) {
        if let data = try? JSONEncoder().encode(apps) {
            UserDefaults.standard.set(data, forKey: customAppsStorageKey)
        }
    }

    static func appendCustomApps(_ newApps: [InstalledAppRecord]) {
        var existing = loadSavedCustomApps()
        for app in newApps {
            let alreadyThere = existing.contains {
                $0.packageName.caseInsensitiveCompare(app.packageName) == .orderedSame
                    || ($0.appStoreId != nil && $0.appStoreId == app.appStoreId)
            }
            if !alreadyThere {
                existing.append(app)
            }
        }
        saveCustomApps(existing)
    }

    /// Filtra le stringhe estratte tramite OCR da screenshot della schermata Home o di «Impostazioni → App»,
    /// scartando orari, percentuali batteria, operatori e app preinstallate di sistema Apple.
    static func filterPlausibleAppNames(_ rawStrings: [String]) -> [String] {
        let ignoredTerms: Set<String> = [
            "impostazioni", "settings", "app", "applicazioni", "cerca", "search", "indietro",
            "fotocamera", "foto", "telefono", "messaggi", "safari", "orologio", "calendario",
            "promemoria", "note", "mappe", "meteo", "borsa", "salute", "wallet", "casa",
            "dov'è", "trova", "app store", "itunes store", "file", "calcolatrice", "bussola",
            "metro", "memo vocali", "contatti", "suggerimenti", "comandi rapidi", "lente",
            "traduzi", "traduttore", "libri", "podcast", "tv", "musica", "fitness", "diario",
            "password", "freeform", "watch", "facetime", "mail", "directswitch", "libreria app",
            "5g", "4g", "lte", "wifi", "wi-fi", "iliad", "vodafone", "tim", "windtre", "fastweb", "ho."
        ]

        var out: [String] = []
        var seen = Set<String>()

        for raw in rawStrings {
            let cleaned = raw
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "•›<>-–—_·:"))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard cleaned.count >= 2, cleaned.count <= 28 else { continue }

            let lower = cleaned.lowercased()
            if ignoredTerms.contains(lower) { continue }
            if lower.hasSuffix("%") || lower.contains("kb/s") || lower.contains("mb/s") { continue }

            // Scarta orari (es. 21:10) o soli numeri/simboli
            let lettersCount = cleaned.unicodeScalars.filter { CharacterSet.letters.contains($0) }.count
            if lettersCount < 2 { continue }

            if !seen.contains(lower) {
                seen.insert(lower)
                out.append(cleaned)
            }
        }
        return Array(out.prefix(45))
    }

    /// Legge tramite Apple `Vision` (`VNRecognizeTextRequest` 100% locale su dispositivo) i nomi di tutte le app
    /// presenti negli screenshot della schermata Home o di «Impostazioni → App» e ne risolve icona e ID su App Store.
    static func recognizeAppsFromScreenshots(_ images: [UIImage]) async -> [InstalledAppRecord] {
        guard !images.isEmpty else { return [] }
        let cgImages = images.compactMap(\.cgImage)
        guard !cgImages.isEmpty else { return [] }

        let extractedLines: [String] = await Task.detached(priority: .userInitiated) {
            var lines: [String] = []
            for cgImg in cgImages {
                let req = VNRecognizeTextRequest()
                req.recognitionLevel = .accurate
                req.usesLanguageCorrection = false
                req.recognitionLanguages = ["it-IT", "en-US"]
                let handler = VNImageRequestHandler(cgImage: cgImg, options: [:])
                try? handler.perform([req])
                if let observations = req.results {
                    for obs in observations {
                        if let top = obs.topCandidates(1).first, top.confidence >= 0.45 {
                            lines.append(top.string)
                        }
                    }
                }
            }
            return lines
        }.value

        let candidates = filterPlausibleAppNames(extractedLines)
        guard !candidates.isEmpty else { return [] }

        var resolved: [InstalledAppRecord] = []
        var seenKeys = Set<String>()

        // Risolve a blocchi concorrenti da 6 per velocità (~1.5s) senza saturare la rete
        let chunkSize = 6
        var idx = 0
        while idx < candidates.count {
            let slice = Array(candidates[idx..<min(idx + chunkSize, candidates.count)])
            idx += chunkSize

            let batchMatches = await withTaskGroup(of: (String, InstalledAppRecord?).self) { group -> [(String, InstalledAppRecord?)] in
                for candidate in slice {
                    group.addTask {
                        let match = await iOSAppStoreCatalogResolver.searchBestMatch(appName: candidate, strictTitleSimilarity: true)
                        return (candidate, match)
                    }
                }
                var collected: [(String, InstalledAppRecord?)] = []
                for await pair in group {
                    collected.append(pair)
                }
                return collected
            }

            for (_, maybeApp) in batchMatches {
                guard let app = maybeApp else { continue }
                let dedup = "\(app.packageName.lowercased())_\(app.appStoreId ?? 0)"
                if !seenKeys.contains(dedup) && app.packageName.lowercased() != "com.directswitch.ios" {
                    seenKeys.insert(dedup)
                    resolved.append(app)
                }
            }
        }

        return resolved
    }

    /// Legge con 1 solo tocco gli ultimi screenshot recenti dall'album «Istantanee» (ultime 48 ore)
    /// per importare decine di app dalla Home o da «Impostazioni → App» senza selezionarle manualmente una per una.
    static func fetchRecentScreenshotsFromLibrary(maxCount: Int = 12) async -> [UIImage] {
        var status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if status == .notDetermined {
            status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        }
        guard status == .authorized || status == .limited else {
            return []
        }

        let cutoffDate = Date().addingTimeInterval(-48 * 3600)
        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        fetchOptions.predicate = NSPredicate(format: "creationDate >= %@", cutoffDate as NSDate)
        fetchOptions.fetchLimit = maxCount

        let screenshotAlbums = PHAssetCollection.fetchAssetCollections(
            with: .smartAlbum,
            subtype: .smartAlbumScreenshots,
            options: nil
        )
        let assetsResult: PHFetchResult<PHAsset>
        if let album = screenshotAlbums.firstObject {
            assetsResult = PHAsset.fetchAssets(in: album, options: fetchOptions)
        } else {
            return []
        }
        guard assetsResult.count > 0 else { return [] }

        var assets: [PHAsset] = []
        assetsResult.enumerateObjects { asset, _, _ in
            assets.append(asset)
        }

        let imageManager = PHImageManager.default()
        let reqOptions = PHImageRequestOptions()
        reqOptions.isNetworkAccessAllowed = true
        reqOptions.deliveryMode = .highQualityFormat
        reqOptions.isSynchronous = false

        var images: [UIImage] = []
        for asset in assets {
            let loaded: UIImage? = await withCheckedContinuation { continuation in
                var settled = false
                let lock = NSLock()
                imageManager.requestImageDataAndOrientation(for: asset, options: reqOptions) { data, _, _, _ in
                    lock.lock()
                    defer { lock.unlock() }
                    guard !settled else { return }
                    settled = true
                    if let data, let img = UIImage(data: data) {
                        continuation.resume(returning: img)
                    } else {
                        continuation.resume(returning: nil)
                    }
                }
            }
            if let loaded {
                images.append(loaded)
            }
        }
        return images
    }
}

/// Risolve icone ufficiali `artworkUrl100` e `trackId` numerici tramite le API pubbliche Apple iTunes Lookup / Search (`country=it`).
enum iOSAppStoreCatalogResolver {
    private struct ITunesLookupResponse: Decodable {
        let results: [ITunesSoftwareEntry]
    }

    private struct ITunesSoftwareEntry: Decodable {
        let trackId: Int?
        let trackName: String?
        let bundleId: String?
        let artworkUrl100: String?
    }

    static func sanitizeIconUrl(_ raw: String?) -> String? {
        guard var str = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !str.isEmpty else {
            return nil
        }
        if str.hasPrefix("http://") {
            str = "https://" + str.dropFirst("http://".count)
        }
        return str
    }

    /// Arricchisce un elenco di `InstalledAppRecord` (sia nativi iOS sia ricevuti da Android) con `appStoreId` e `iconUrl`.
    static func enrichAppsWithStoreMetadata(_ apps: [InstalledAppRecord]) async -> [InstalledAppRecord] {
        guard !apps.isEmpty else { return [] }
        var working = apps

        // 1. Applica eventuali probe noti locali per avere subito `appStoreId` e `urlScheme`
        for i in working.indices {
            if let probe = iOSInstalledAppsScanner.knownProbes.first(where: {
                $0.bundleId.caseInsensitiveCompare(working[i].packageName) == .orderedSame
                    || $0.appName.caseInsensitiveCompare(working[i].appName) == .orderedSame
            }) {
                if working[i].appStoreId == nil {
                    working[i].appStoreId = probe.appStoreId
                }
                if working[i].urlScheme == nil {
                    working[i].urlScheme = probe.urlScheme
                }
            }
            if let cached = await AppStoreMetadataCache.shared.getByBundle(working[i].packageName) {
                if working[i].appStoreId == nil { working[i].appStoreId = cached.trackId }
                if working[i].iconUrl == nil { working[i].iconUrl = cached.iconUrl }
            }
        }

        // 2. Lookup batch per `bundleId` (fino a 20 per chiamata HTTP, velocissimo)
        let missingIconBundles = Array(Set(
            working
                .filter { $0.iconUrl == nil && $0.packageName.contains(".") }
                .map(\.packageName)
        ))

        let batchSize = 20
        var offset = 0
        while offset < missingIconBundles.count {
            let chunk = Array(missingIconBundles[offset..<min(offset + batchSize, missingIconBundles.count)])
            offset += batchSize
            let joined = chunk.joined(separator: ",")
            if let encoded = joined.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
               let url = URL(string: "https://itunes.apple.com/lookup?bundleId=\(encoded)&country=it") {
                var req = URLRequest(url: url, timeoutInterval: 6.0)
                req.httpMethod = "GET"
                if let (data, resp) = try? await URLSession.shared.data(for: req),
                   (resp as? HTTPURLResponse)?.statusCode == 200,
                   let parsed = try? JSONDecoder().decode(ITunesLookupResponse.self, from: data) {
                    for entry in parsed.results {
                        guard let bId = entry.bundleId, let tId = entry.trackId else { continue }
                        let cleanIcon = sanitizeIconUrl(entry.artworkUrl100)
                        let name = entry.trackName ?? bId
                        await AppStoreMetadataCache.shared.setByBundle(bId, trackId: tId, iconUrl: cleanIcon, trackName: name)
                        for idx in working.indices where working[idx].packageName.caseInsensitiveCompare(bId) == .orderedSame {
                            working[idx].appStoreId = tId
                            if let cleanIcon { working[idx].iconUrl = cleanIcon }
                        }
                    }
                }
            }
        }

        // 3. Lookup batch per `id` numerico per le app che hanno già `appStoreId` ma ancora nessuna `iconUrl`
        let missingIconIds = Array(Set(
            working.compactMap { $0.iconUrl == nil ? $0.appStoreId : nil }
        ))
        offset = 0
        while offset < missingIconIds.count {
            let chunk = Array(missingIconIds[offset..<min(offset + batchSize, missingIconIds.count)])
            offset += batchSize
            let joined = chunk.map(String.init).joined(separator: ",")
            if let url = URL(string: "https://itunes.apple.com/lookup?id=\(joined)&country=it") {
                var req = URLRequest(url: url, timeoutInterval: 6.0)
                req.httpMethod = "GET"
                if let (data, resp) = try? await URLSession.shared.data(for: req),
                   (resp as? HTTPURLResponse)?.statusCode == 200,
                   let parsed = try? JSONDecoder().decode(ITunesLookupResponse.self, from: data) {
                    for entry in parsed.results {
                        guard let tId = entry.trackId else { continue }
                        let cleanIcon = sanitizeIconUrl(entry.artworkUrl100)
                        for idx in working.indices where working[idx].appStoreId == tId {
                            if let cleanIcon { working[idx].iconUrl = cleanIcon }
                        }
                    }
                }
            }
        }

        // 4. Per eventuali app senza `appStoreId` (es. provenienti da Android), risolve per nome su App Store Italia
        for idx in working.indices where working[idx].appStoreId == nil {
            if let resolved = await searchBestMatch(appName: working[idx].appName, strictTitleSimilarity: false) {
                working[idx].appStoreId = resolved.appStoreId
                if working[idx].iconUrl == nil {
                    working[idx].iconUrl = resolved.iconUrl
                }
                if working[idx].urlScheme == nil {
                    working[idx].urlScheme = resolved.urlScheme
                }
            }
        }

        return working
    }

    static func searchBestMatch(appName: String, strictTitleSimilarity: Bool) async -> InstalledAppRecord? {
        let trimmed = appName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let cached = await AppStoreMetadataCache.shared.getByName(trimmed) {
            return cached
        }
        let results = await searchAppStore(query: trimmed, limit: 3)
        guard let first = results.first else { return nil }

        if strictTitleSimilarity {
            let qLower = trimmed.lowercased()
            let tLower = first.appName.lowercased()
            let qFirstWord = qLower.split(separator: " ").first.map(String.init) ?? qLower
            let matches = tLower.contains(qLower)
                || qLower.contains(tLower)
                || (qFirstWord.count >= 3 && tLower.contains(qFirstWord))
            if !matches {
                return nil
            }
        }

        await AppStoreMetadataCache.shared.setByName(trimmed, record: first)
        return first
    }

    static func searchAppStore(query: String, limit: Int = 12) async -> [InstalledAppRecord] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://itunes.apple.com/search?term=\(encoded)&country=it&entity=software&limit=\(limit)") else {
            return []
        }
        var req = URLRequest(url: url, timeoutInterval: 6.0)
        req.httpMethod = "GET"
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let parsed = try? JSONDecoder().decode(ITunesLookupResponse.self, from: data) else {
            return []
        }

        var out: [InstalledAppRecord] = []
        for entry in parsed.results {
            guard let bundleId = entry.bundleId,
                  let trackName = entry.trackName,
                  let trackId = entry.trackId else { continue }
            let matchedProbe = iOSInstalledAppsScanner.knownProbes.first {
                $0.bundleId.caseInsensitiveCompare(bundleId) == .orderedSame || $0.appStoreId == trackId
            }
            out.append(
                InstalledAppRecord(
                    packageName: bundleId,
                    appName: trackName,
                    appStoreId: trackId,
                    iconUrl: sanitizeIconUrl(entry.artworkUrl100),
                    urlScheme: matchedProbe?.urlScheme
                )
            )
        }
        return out
    }

    /// Apre direttamente la scheda esatta dell'app su App Store (mai una ricerca generica quando `appStoreId` è noto).
    @MainActor
    static func openDirectAppStorePage(for app: InstalledAppRecord) {
        if let trackId = app.appStoreId, trackId > 0 {
            if let nativeURL = URL(string: "itms-apps://itunes.apple.com/app/id\(trackId)"),
               UIApplication.shared.canOpenURL(nativeURL) {
                UIApplication.shared.open(nativeURL)
                return
            }
            if let webURL = URL(string: "https://apps.apple.com/it/app/id\(trackId)") {
                UIApplication.shared.open(webURL)
                return
            }
        }
        iOSPermissionsHelper.searchAppOnAppStore(appName: app.appName)
    }
}

/// Motore di installazione rapida 1-tocco sul nuovo iPhone:
/// 1) Livello 1 (Predefinito): Mini-banner di sistema fisso in basso (`SKOverlay`, posizione `.bottom`) senza mai uscire da DirectSwitch
///    né aprire/chiudere 100 pagine intere dell'App Store — il tasto «Ottieni» resta fisso sotto il pollice e sincronizza ogni app col nuovo iCloud.
/// 2) Livello 2 (Fallback automatico): `SKStoreProductViewController` se una specifica app o build sideloaded non supporta `SKOverlay`.
/// 3) Livello 3 (Fallback universale `Free-Install.ipa`): Link diretto `itms-apps://itunes.apple.com/app/id<trackId>` con concatenazione automatica al rientro.
@MainActor
final class iOSSequentialAppInstaller: NSObject, ObservableObject, SKOverlayDelegate, SKStoreProductViewControllerDelegate, UIAdaptivePresentationControllerDelegate {
    enum DeliveryMode: Equatable {
        case fastBottomOverlay
        case inlineStoreSheet
        case externalAppStore
    }

    @Published var apps: [InstalledAppRecord] = []
    @Published var selectedIds: Set<String> = []
    @Published var completedIds: Set<String> = []
    @Published var alreadyInstalledIds: Set<String> = []
    @Published var isEnrichingMetadata: Bool = false

    @Published var isRunningSequence: Bool = false
    @Published var isSingleOverlaySession: Bool = false
    @Published var isLoadingInlineCard: Bool = false
    @Published var isOverlayVisible: Bool = false
    @Published var overlaySafeBottomPadding: CGFloat = 78
    @Published var activeDeliveryMode: DeliveryMode = .fastBottomOverlay

    @Published var currentQueuePosition: Int = 0
    @Published var totalQueueCount: Int = 0
    @Published var currentActiveApp: InstalledAppRecord? = nil
    @Published var waitingForExternalReturn: Bool = false
    @Published private(set) var historyStack: [InstalledAppRecord] = []

    /// Usato nei test unitari su simulatore per verificare la macchina a stati della coda senza invocare `storekitd`.
    var dryRunPresentationForTesting: Bool = false

    private var queue: [InstalledAppRecord] = []
    private var overlayUnsupportedOnDevice: Bool = false
    private var hasEverPresentedOverlaySuccessfully: Bool = false
    private var preferExternalAppStore: Bool = false
    private var inlineSheetHandledForCurrentStep: Bool = false
    private var isSwitchingOverlayProgrammatically: Bool = false
    private var currentPresentationAttemptId: UUID = UUID()
    private var autoAdvanceTask: Task<Void, Never>? = nil
    private var liveInstallMonitorTask: Task<Void, Never>? = nil
    private var activeOverlayInstance: SKOverlay? = nil

    var pendingInstallableCount: Int {
        apps.filter { selectedIds.contains($0.id) && !alreadyInstalledIds.contains($0.id) && !completedIds.contains($0.id) }.count
    }

    var canGoBackInQueue: Bool {
        isRunningSequence && !historyStack.isEmpty
    }

    var showsFloatingBottomBar: Bool {
        (isRunningSequence || isSingleOverlaySession)
            && activeDeliveryMode == .fastBottomOverlay
            && currentActiveApp != nil
    }

    func reset() {
        stopSequence()
        apps = []
        selectedIds = []
        completedIds = []
        alreadyInstalledIds = []
        historyStack = []
        isEnrichingMetadata = false
    }

    func configure(with incomingApps: [InstalledAppRecord]) {
        guard !incomingApps.isEmpty else {
            reset()
            return
        }
        if apps.map(\.id) == incomingApps.map(\.id) && !apps.isEmpty {
            refreshInstalledStatuses()
            completedIds.removeAll()
            selectedIds = Set(
                apps
                    .filter { !alreadyInstalledIds.contains($0.id) }
                    .map(\.id)
            )
            return
        }

        completedIds.removeAll()
        historyStack.removeAll()
        apps = incomingApps
        refreshInstalledStatuses()
        selectedIds = Set(
            incomingApps
                .filter { !alreadyInstalledIds.contains($0.id) }
                .map(\.id)
        )

        guard !dryRunPresentationForTesting else { return }
        isEnrichingMetadata = true
        Task {
            let enriched = await iOSAppStoreCatalogResolver.enrichAppsWithStoreMetadata(incomingApps)
            let byId = Dictionary(uniqueKeysWithValues: enriched.map { ($0.id, $0) })
            self.apps = enriched
            self.queue = self.queue.map { byId[$0.id] ?? $0 }
            self.historyStack = self.historyStack.map { byId[$0.id] ?? $0 }
            if let active = self.currentActiveApp, let updatedActive = byId[active.id] {
                self.currentActiveApp = updatedActive
            }
            self.refreshInstalledStatuses()
            self.isEnrichingMetadata = false
        }
    }

    func refreshInstalledStatuses() {
        var installed = Set<String>()
        for app in apps {
            if iOSInstalledAppsScanner.isAppAlreadyInstalledOnThisPhone(app) {
                installed.insert(app.id)
            }
        }
        alreadyInstalledIds = installed
    }

    func toggleSelection(for app: InstalledAppRecord) {
        guard !alreadyInstalledIds.contains(app.id) else { return }
        if selectedIds.contains(app.id) {
            selectedIds.remove(app.id)
        } else {
            selectedIds.insert(app.id)
        }
    }

    func selectAllPending() {
        for app in apps where !alreadyInstalledIds.contains(app.id) {
            selectedIds.insert(app.id)
        }
    }

    /// Installa una singola app mostrando subito il mini-banner `SKOverlay` fisso in basso (o fallback automatico).
    func installSingleApp(_ app: InstalledAppRecord) {
        stopSequence()
        currentActiveApp = app
        isSingleOverlaySession = true
        currentQueuePosition = 1
        totalQueueCount = 1
        startLiveInstallMonitor()
        presentAppFastBannerOrFallback(app: app, partOfSequence: false)
    }

    /// Avvia la sequenza rapida con mini-banner fisso in basso per tutte le app selezionate.
    func startAutomaticSequence() {
        stopSequence()
        refreshInstalledStatuses()
        let pending = apps.filter {
            selectedIds.contains($0.id) && !alreadyInstalledIds.contains($0.id) && !completedIds.contains($0.id)
        }
        guard !pending.isEmpty else { return }

        queue = pending
        historyStack = []
        totalQueueCount = pending.count
        currentQueuePosition = 0
        isRunningSequence = true
        isSingleOverlaySession = false
        waitingForExternalReturn = false
        startLiveInstallMonitor()
        advanceToNextInQueue()
    }

    /// Conferma di aver premuto «Ottieni» sul mini-banner in basso e carica istantaneamente l'app successiva nello stesso punto.
    func confirmCurrentAndAdvance() {
        autoAdvanceTask?.cancel()
        waitingForExternalReturn = false
        isLoadingInlineCard = false

        if let active = currentActiveApp {
            completedIds.insert(active.id)
            if isRunningSequence {
                historyStack.append(active)
            }
        }

        if isSingleOverlaySession {
            stopSequence()
            return
        }

        guard isRunningSequence else { return }
        advanceToNextInQueue()
    }

    /// Torna immediatamente all'app precedente nel mini-banner se si è toccato «Prossima» per errore.
    func goBackToPreviousApp() {
        guard isRunningSequence, let previous = historyStack.popLast() else { return }
        autoAdvanceTask?.cancel()
        waitingForExternalReturn = false
        isLoadingInlineCard = false

        if let active = currentActiveApp {
            queue.insert(active, at: 0)
            currentQueuePosition = max(1, currentQueuePosition - 1)
        } else {
            currentQueuePosition = max(1, currentQueuePosition)
        }

        completedIds.remove(previous.id)
        currentActiveApp = previous
        presentAppFastBannerOrFallback(app: previous, partOfSequence: true)
    }

    /// Riapre il mini-banner `SKOverlay` dell'app corrente se l'utente lo ha chiuso scorrendo verso il basso.
    func reopenCurrentOverlay() {
        guard let active = currentActiveApp else { return }
        presentAppFastBannerOrFallback(app: active, partOfSequence: isRunningSequence)
    }

    func skipCurrentAndContinue() {
        autoAdvanceTask?.cancel()
        waitingForExternalReturn = false
        isLoadingInlineCard = false
        if let active = currentActiveApp, isRunningSequence {
            historyStack.append(active)
        }
        if isSingleOverlaySession {
            stopSequence()
            return
        }
        guard isRunningSequence else { return }
        advanceToNextInQueue()
    }

    func stopSequence() {
        currentPresentationAttemptId = UUID()
        autoAdvanceTask?.cancel()
        autoAdvanceTask = nil
        liveInstallMonitorTask?.cancel()
        liveInstallMonitorTask = nil
        dismissOverlayIfPresent()
        queue.removeAll()
        historyStack.removeAll()
        isRunningSequence = false
        isSingleOverlaySession = false
        isLoadingInlineCard = false
        isOverlayVisible = false
        waitingForExternalReturn = false
        currentActiveApp = nil
    }

    /// Chiamato quando DirectSwitch torna attiva in primo piano (`scenePhase == .active`):
    /// se il download era stato aperto nell'App Store esterno, passa automaticamente all'app successiva della coda!
    func handleSceneBecameActive() {
        refreshInstalledStatuses()
        guard isRunningSequence && waitingForExternalReturn else { return }
        waitingForExternalReturn = false

        if let active = currentActiveApp {
            completedIds.insert(active.id)
            historyStack.append(active)
        }

        if queue.isEmpty {
            stopSequence()
            return
        }

        autoAdvanceTask?.cancel()
        autoAdvanceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 650_000_000)
            guard let self, !Task.isCancelled, self.isRunningSequence else { return }
            self.advanceToNextInQueue()
        }
    }

    private func startLiveInstallMonitor() {
        liveInstallMonitorTask?.cancel()
        guard !dryRunPresentationForTesting else { return }
        liveInstallMonitorTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard let self, !Task.isCancelled else { return }
                guard self.isRunningSequence || self.isSingleOverlaySession else { return }
                self.refreshInstalledStatuses()
                if let active = self.currentActiveApp, self.alreadyInstalledIds.contains(active.id) {
                    self.confirmCurrentAndAdvance()
                }
            }
        }
    }

    private func advanceToNextInQueue() {
        refreshInstalledStatuses()
        while !queue.isEmpty {
            let candidate = queue.removeFirst()
            currentQueuePosition += 1
            if alreadyInstalledIds.contains(candidate.id) || completedIds.contains(candidate.id) {
                continue
            }
            currentActiveApp = candidate
            presentAppFastBannerOrFallback(app: candidate, partOfSequence: true)
            return
        }
        stopSequence()
    }

    private func dismissOverlayIfPresent() {
        guard !dryRunPresentationForTesting else {
            isOverlayVisible = false
            return
        }
        isSwitchingOverlayProgrammatically = true
        activeOverlayInstance = nil
        if let scene = Self.activeWindowScene() {
            SKOverlay.dismiss(in: scene)
        }
        isOverlayVisible = false
    }

    private func presentAppFastBannerOrFallback(app: InstalledAppRecord, partOfSequence: Bool) {
        let attemptId = UUID()
        currentPresentationAttemptId = attemptId

        if dryRunPresentationForTesting {
            activeDeliveryMode = .fastBottomOverlay
            isOverlayVisible = true
            isLoadingInlineCard = false
            return
        }

        // Livello 1: Mini-banner di sistema fisso in basso (`SKOverlay`) senza cambiare schermata
        if !overlayUnsupportedOnDevice,
           let trackId = app.appStoreId, trackId > 0,
           let scene = Self.activeWindowScene() {
            activeDeliveryMode = .fastBottomOverlay
            isLoadingInlineCard = true

            let hadVisibleOverlay = isOverlayVisible || activeOverlayInstance != nil
            if hadVisibleOverlay {
                isSwitchingOverlayProgrammatically = true
                SKOverlay.dismiss(in: scene)
                isOverlayVisible = false
            }

            Task { @MainActor [weak self] in
                if hadVisibleOverlay {
                    try? await Task.sleep(nanoseconds: 160_000_000)
                }
                guard let self, self.currentPresentationAttemptId == attemptId else { return }
                guard let liveScene = Self.activeWindowScene() else {
                    self.presentInlineSheetOrExternalFallback(app: app, partOfSequence: partOfSequence, attemptId: attemptId)
                    return
                }

                self.isSwitchingOverlayProgrammatically = false
                let config = SKOverlay.AppConfiguration(appIdentifier: String(trackId), position: .bottom)
                config.userDismissible = true
                let overlay = SKOverlay(configuration: config)
                overlay.delegate = self
                self.activeOverlayInstance = overlay
                overlay.present(in: liveScene)

                // Timeout di sicurezza (2.3s): se su build sideloaded Free-Install `storekitd` ignora SKOverlay senza chiamare il delegate, scala subito al fallback
                try? await Task.sleep(nanoseconds: 2_300_000_000)
                guard self.currentPresentationAttemptId == attemptId, !self.isOverlayVisible else { return }
                self.isLoadingInlineCard = false
                if !self.hasEverPresentedOverlaySuccessfully {
                    self.overlayUnsupportedOnDevice = true
                }
                self.dismissOverlayIfPresent()
                self.presentInlineSheetOrExternalFallback(app: app, partOfSequence: partOfSequence, attemptId: attemptId)
            }
            return
        }

        presentInlineSheetOrExternalFallback(app: app, partOfSequence: partOfSequence, attemptId: attemptId)
    }

    private func presentInlineSheetOrExternalFallback(app: InstalledAppRecord, partOfSequence: Bool, attemptId: UUID) {
        guard currentPresentationAttemptId == attemptId else { return }

        guard !preferExternalAppStore,
              let trackId = app.appStoreId, trackId > 0,
              Self.topMostViewController() != nil else {
            activeDeliveryMode = .externalAppStore
            openExternalAndTrack(app: app, partOfSequence: partOfSequence)
            return
        }

        activeDeliveryMode = .inlineStoreSheet
        isLoadingInlineCard = true
        inlineSheetHandledForCurrentStep = false

        let storeVC = SKStoreProductViewController()
        storeVC.delegate = self
        storeVC.presentationController?.delegate = self

        final class LoadTimeoutGate: @unchecked Sendable {
            private let lock = NSLock()
            private var settled = false
            func trySettle() -> Bool {
                lock.lock()
                defer { lock.unlock() }
                if settled { return false }
                settled = true
                return true
            }
        }
        let gate = LoadTimeoutGate()

        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            guard gate.trySettle(), let self, self.currentPresentationAttemptId == attemptId else { return }
            self.isLoadingInlineCard = false
            self.preferExternalAppStore = true
            self.activeDeliveryMode = .externalAppStore
            self.openExternalAndTrack(app: app, partOfSequence: partOfSequence)
        }

        let params: [String: Any] = [
            SKStoreProductParameterITunesItemIdentifier: NSNumber(value: trackId)
        ]
        storeVC.loadProduct(withParameters: params) { [weak self] loaded, _ in
            Task { @MainActor [weak self] in
                guard gate.trySettle(), let self, self.currentPresentationAttemptId == attemptId else { return }
                self.isLoadingInlineCard = false
                if loaded, let livePresenter = Self.topMostViewController(), livePresenter.presentedViewController == nil {
                    livePresenter.present(storeVC, animated: true)
                    if !partOfSequence {
                        self.completedIds.insert(app.id)
                    }
                } else {
                    self.preferExternalAppStore = true
                    self.activeDeliveryMode = .externalAppStore
                    self.openExternalAndTrack(app: app, partOfSequence: partOfSequence)
                }
            }
        }
    }

    private func openExternalAndTrack(app: InstalledAppRecord, partOfSequence: Bool) {
        if partOfSequence {
            waitingForExternalReturn = true
        } else {
            completedIds.insert(app.id)
            isSingleOverlaySession = false
        }
        iOSAppStoreCatalogResolver.openDirectAppStorePage(for: app)
    }

    private func updateSafeBottomPadding(from endFrame: CGRect) {
        guard endFrame.height > 20 else { return }
        let scene = Self.activeWindowScene()
        let keyWindow = scene?.windows.first(where: \.isKeyWindow) ?? scene?.windows.first
        let windowHeight = keyWindow?.bounds.height ?? UIScreen.main.bounds.height
        let safeBottom = keyWindow?.safeAreaInsets.bottom ?? 0

        let computed: CGFloat
        if endFrame.minY > 100 && endFrame.minY < windowHeight {
            computed = max(68, (windowHeight - endFrame.minY) - safeBottom)
        } else {
            computed = max(68, endFrame.height)
        }
        overlaySafeBottomPadding = min(140, computed)
    }

    private func handleInlineStoreDismissed() {
        guard !inlineSheetHandledForCurrentStep else { return }
        inlineSheetHandledForCurrentStep = true

        if let active = currentActiveApp {
            completedIds.insert(active.id)
            if isRunningSequence {
                historyStack.append(active)
            }
        }
        refreshInstalledStatuses()

        if isSingleOverlaySession {
            stopSequence()
            return
        }

        guard isRunningSequence else { return }
        autoAdvanceTask?.cancel()
        autoAdvanceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard let self, !Task.isCancelled, self.isRunningSequence else { return }
            self.advanceToNextInQueue()
        }
    }

    // MARK: - SKOverlayDelegate

    nonisolated func storeOverlayWillStartPresentation(_ overlay: SKOverlay, transitionContext: SKOverlay.TransitionContext) {
        let endFrame = transitionContext.endFrame
        Task { @MainActor [weak self] in
            guard let self, overlay === self.activeOverlayInstance else { return }
            self.updateSafeBottomPadding(from: endFrame)
            self.isOverlayVisible = true
            self.isLoadingInlineCard = false
            self.hasEverPresentedOverlaySuccessfully = true
        }
    }

    nonisolated func storeOverlayDidFinishPresentation(_ overlay: SKOverlay, transitionContext: SKOverlay.TransitionContext) {
        let endFrame = transitionContext.endFrame
        Task { @MainActor [weak self] in
            guard let self, overlay === self.activeOverlayInstance else { return }
            self.updateSafeBottomPadding(from: endFrame)
            self.isOverlayVisible = true
            self.isLoadingInlineCard = false
            self.hasEverPresentedOverlaySuccessfully = true
        }
    }

    nonisolated func storeOverlayDidFinishDismissal(_ overlay: SKOverlay, transitionContext: SKOverlay.TransitionContext) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            if !self.isSwitchingOverlayProgrammatically && overlay === self.activeOverlayInstance {
                self.isOverlayVisible = false
            }
        }
    }

    nonisolated func storeOverlayDidFailToLoad(_ overlay: SKOverlay, error: Error) {
        Task { @MainActor [weak self] in
            guard let self, overlay === self.activeOverlayInstance else { return }
            self.isLoadingInlineCard = false
            self.isOverlayVisible = false
            self.activeOverlayInstance = nil
            if !self.hasEverPresentedOverlaySuccessfully {
                self.overlayUnsupportedOnDevice = true
            }
            if let active = self.currentActiveApp {
                self.presentInlineSheetOrExternalFallback(
                    app: active,
                    partOfSequence: self.isRunningSequence,
                    attemptId: self.currentPresentationAttemptId
                )
            }
        }
    }

    // MARK: - SKStoreProductViewControllerDelegate

    nonisolated func productViewControllerDidFinish(_ viewController: SKStoreProductViewController) {
        Task { @MainActor [weak self] in
            viewController.dismiss(animated: true) {
                Task { @MainActor [weak self] in
                    self?.handleInlineStoreDismissed()
                }
            }
        }
    }

    nonisolated func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        Task { @MainActor [weak self] in
            self?.handleInlineStoreDismissed()
        }
    }

    private static func activeWindowScene() -> UIWindowScene? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
    }

    private static func topMostViewController() -> UIViewController? {
        guard let activeScene = activeWindowScene(),
              let root = activeScene.windows.first(where: \.isKeyWindow)?.rootViewController
                ?? activeScene.windows.first?.rootViewController else {
            return nil
        }
        var current = root
        while let presented = current.presentedViewController {
            current = presented
        }
        return current
    }
}
