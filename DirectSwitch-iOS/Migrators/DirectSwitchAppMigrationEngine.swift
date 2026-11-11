//
//  DirectSwitchAppMigrationEngine.swift
//  DirectSwitch-iOS
//
//  Created by Nicolas Donati.
//  Copyright © 2026 Nicolas Donati. Tutti i diritti riservati.
//

import Foundation
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
        iOSKnownAppProbe(bundleId: "com.zhiliaoapp.musically", appName: "TikTok", urlScheme: "snssdk1233", appStoreId: 835599320),
        iOSKnownAppProbe(bundleId: "com.google.ios.youtube", appName: "YouTube", urlScheme: "youtube", appStoreId: 544007664),
        iOSKnownAppProbe(bundleId: "com.google.Gmail", appName: "Gmail", urlScheme: "googlegmail", appStoreId: 422689480),
        iOSKnownAppProbe(bundleId: "com.google.Maps", appName: "Google Maps", urlScheme: "comgooglemaps", appStoreId: 585027354),
        iOSKnownAppProbe(bundleId: "com.google.chrome.ios", appName: "Google Chrome", urlScheme: "googlechrome", appStoreId: 535886823),
        iOSKnownAppProbe(bundleId: "com.google.Drive", appName: "Google Drive", urlScheme: "googledrive", appStoreId: 507874739),
        iOSKnownAppProbe(bundleId: "com.google.photos", appName: "Google Foto", urlScheme: "googlephotos", appStoreId: 962194608),
        iOSKnownAppProbe(bundleId: "com.google.GoogleMobile", appName: "Google", urlScheme: "google", appStoreId: 284815942),
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
        iOSKnownAppProbe(bundleId: "com.ryanair.cheapflights", appName: "Ryanair", urlScheme: "ryanair", appStoreId: 572698805),
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

/// Motore di installazione sequenziale automatica sul nuovo iPhone:
/// apre una dopo l'altra le schede ufficiali App Store (`SKStoreProductViewController` nativo in-app con fallback automatico
/// al link diretto `id<trackId>` + concatenazione automatica al rientro in foreground per build sideloaded).
@MainActor
final class iOSSequentialAppInstaller: NSObject, ObservableObject, SKStoreProductViewControllerDelegate, UIAdaptivePresentationControllerDelegate {
    @Published var apps: [InstalledAppRecord] = []
    @Published var selectedIds: Set<String> = []
    @Published var completedIds: Set<String> = []
    @Published var alreadyInstalledIds: Set<String> = []
    @Published var isEnrichingMetadata: Bool = false

    @Published var isRunningSequence: Bool = false
    @Published var isLoadingInlineCard: Bool = false
    @Published var currentQueuePosition: Int = 0
    @Published var totalQueueCount: Int = 0
    @Published var currentActiveApp: InstalledAppRecord? = nil
    @Published var waitingForExternalReturn: Bool = false

    private var queue: [InstalledAppRecord] = []
    private var preferExternalAppStore: Bool = false
    private var inlineSheetHandledForCurrentStep: Bool = false
    private var autoAdvanceTask: Task<Void, Never>? = nil

    var pendingInstallableCount: Int {
        apps.filter { selectedIds.contains($0.id) && !alreadyInstalledIds.contains($0.id) && !completedIds.contains($0.id) }.count
    }

    func configure(with incomingApps: [InstalledAppRecord]) {
        guard !incomingApps.isEmpty else { return }
        if apps.map(\.id) == incomingApps.map(\.id) && !apps.isEmpty {
            refreshInstalledStatuses()
            return
        }

        apps = incomingApps
        refreshInstalledStatuses()
        selectedIds = Set(
            incomingApps
                .filter { !alreadyInstalledIds.contains($0.id) }
                .map(\.id)
        )

        isEnrichingMetadata = true
        Task {
            let enriched = await iOSAppStoreCatalogResolver.enrichAppsWithStoreMetadata(incomingApps)
            self.apps = enriched
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

    /// Installa una singola app (usando la card App Store interna oppure la scheda diretta App Store).
    func installSingleApp(_ app: InstalledAppRecord) {
        stopSequence()
        presentAppCardOrExternalStore(app: app, partOfSequence: false)
    }

    /// Avvia la coda automatica di tutte le app selezionate una dopo l'altra senza doverle cercare manualmente.
    func startAutomaticSequence() {
        autoAdvanceTask?.cancel()
        refreshInstalledStatuses()
        let pending = apps.filter {
            selectedIds.contains($0.id) && !alreadyInstalledIds.contains($0.id) && !completedIds.contains($0.id)
        }
        guard !pending.isEmpty else { return }

        queue = pending
        totalQueueCount = pending.count
        currentQueuePosition = 0
        isRunningSequence = true
        waitingForExternalReturn = false
        advanceToNextInQueue()
    }

    func skipCurrentAndContinue() {
        autoAdvanceTask?.cancel()
        waitingForExternalReturn = false
        isLoadingInlineCard = false
        guard isRunningSequence else { return }
        advanceToNextInQueue()
    }

    func stopSequence() {
        autoAdvanceTask?.cancel()
        autoAdvanceTask = nil
        queue.removeAll()
        isRunningSequence = false
        isLoadingInlineCard = false
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
        }

        if queue.isEmpty {
            stopSequence()
            return
        }

        autoAdvanceTask?.cancel()
        autoAdvanceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 750_000_000)
            guard let self, !Task.isCancelled, self.isRunningSequence else { return }
            self.advanceToNextInQueue()
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
            presentAppCardOrExternalStore(app: candidate, partOfSequence: true)
            return
        }
        stopSequence()
    }

    private func presentAppCardOrExternalStore(app: InstalledAppRecord, partOfSequence: Bool) {
        // Se non abbiamo un `trackId` numerico o la build sideloaded richiede apertura diretta App Store
        guard !preferExternalAppStore,
              let trackId = app.appStoreId, trackId > 0,
              let presenter = Self.topMostViewController() else {
            openExternalAndTrack(app: app, partOfSequence: partOfSequence)
            return
        }

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

        // Timeout rapido di 2.8s: se su Free-Install.ipa il demone StoreKit non risponde, passa subito alla scheda diretta App Store
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 2_800_000_000)
            guard gate.trySettle(), let self else { return }
            self.isLoadingInlineCard = false
            self.preferExternalAppStore = true
            self.openExternalAndTrack(app: app, partOfSequence: partOfSequence)
        }

        let params: [String: Any] = [
            SKStoreProductParameterITunesItemIdentifier: NSNumber(value: trackId)
        ]
        storeVC.loadProduct(withParameters: params) { [weak self] loaded, _ in
            Task { @MainActor [weak self] in
                guard gate.trySettle(), let self else { return }
                self.isLoadingInlineCard = false
                if loaded, let livePresenter = Self.topMostViewController(), livePresenter.presentedViewController == nil {
                    livePresenter.present(storeVC, animated: true)
                    if !partOfSequence {
                        self.completedIds.insert(app.id)
                    }
                } else {
                    self.preferExternalAppStore = true
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
        }
        iOSAppStoreCatalogResolver.openDirectAppStorePage(for: app)
    }

    private func handleInlineStoreDismissed() {
        guard !inlineSheetHandledForCurrentStep else { return }
        inlineSheetHandledForCurrentStep = true

        if let active = currentActiveApp {
            completedIds.insert(active.id)
        }
        refreshInstalledStatuses()

        guard isRunningSequence else { return }
        autoAdvanceTask?.cancel()
        autoAdvanceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 380_000_000)
            guard let self, !Task.isCancelled, self.isRunningSequence else { return }
            self.advanceToNextInQueue()
        }
    }

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

    private static func topMostViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let activeScene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        guard let root = activeScene?.windows.first(where: \.isKeyWindow)?.rootViewController
                ?? activeScene?.windows.first?.rootViewController else {
            return nil
        }
        var current = root
        while let presented = current.presentedViewController {
            current = presented
        }
        return current
    }
}
