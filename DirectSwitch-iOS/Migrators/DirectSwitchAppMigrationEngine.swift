//
//  DirectSwitchAppMigrationEngine.swift
//  DirectSwitch-iOS
//
//  Created by Nicolas Donati.
//  Copyright © 2026 Nicolas Donati. Tutti i diritti riservati.
//

import AVFoundation
import Foundation
import Photos
import SwiftUI
import StoreKit
import UIKit
import Vision

/// Risultato della cattura automatica di tutti gli screenshot (da istantanee pagine Home o video di scorrimento).
struct AutoScreenshotCaptureResult: Sendable {
    let discoveredApps: [InstalledAppRecord]
    let generatedScreenshotsCount: Int
    let analyzedVideoAssetLocalIdentifier: String?
    var analyzedScreenshotLocalIdentifiers: [String] = []

    var allTemporaryAssetIdentifiers: [String] {
        var ids = analyzedScreenshotLocalIdentifiers
        if let vid = analyzedVideoAssetLocalIdentifier, !vid.isEmpty, !ids.contains(vid) {
            ids.insert(vid, at: 0)
        }
        return ids
    }
}

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

/// Candidato app estratto tramite OCR spaziale (preserva il flag `wasTruncated` quando l'etichetta sulla Home finiva con `…`).
struct ParsedAppCandidate: Equatable, Sendable {
    let cleaned: String
    let wasTruncated: Bool
}

/// Riquadro di testo riconosciuto da `Vision` con coordinate normalizzate `(0..1)` per separare icone adiacenti e unire etichette su 2 righe.
struct RecognizedAppTextBox: Equatable, Sendable {
    let text: String
    let boundingBox: CGRect
    let confidence: Float
}

/// Scanner delle app installate sull'iPhone mittente (combina rilevamento istantaneo `canOpenURL`,
/// lettura spaziale accurata da Libreria App / Home tramite Apple `Vision` OCR locale e verifica rigorosa App Store).
enum iOSInstalledAppsScanner {
    private static let legacyCustomAppsStorageKey = "directswitch_custom_sender_apps_v1"
    private static let customAppsStorageKey = "directswitch_verified_sender_apps_v2"

    /// Tutti gli schemi univoci dichiarati in `Info.plist` (`<= 50` secondo il limite Apple; esclusi schemi generici come `otpauth`/`msauth`/`booking` per zero falsi positivi).
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
        iOSKnownAppProbe(bundleId: "com.google.Authenticator", appName: "Google Authenticator", urlScheme: "googleauthenticator", appStoreId: 388497605),
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
        iOSKnownAppProbe(bundleId: "com.airbnb.app", appName: "Airbnb", urlScheme: "airbnb", appStoreId: 401626263),
        iOSKnownAppProbe(bundleId: "com.openai.chat", appName: "ChatGPT", urlScheme: "chatgpt", appStoreId: 6448311069),
        iOSKnownAppProbe(bundleId: "com.shazam.Shazam", appName: "Shazam", urlScheme: "shazam", appStoreId: 284993459),
        iOSKnownAppProbe(bundleId: "com.canva.canvaeditor", appName: "Canva", urlScheme: "canva", appStoreId: 897446215),
        iOSKnownAppProbe(bundleId: "com.ebay.iphone", appName: "eBay", urlScheme: "ebay", appStoreId: 282614216),
        iOSKnownAppProbe(bundleId: "it.pagopa.app.io", appName: "IO", urlScheme: "ioit", appStoreId: 1505842859),
        iOSKnownAppProbe(bundleId: "posteitaliane.posteapp.appposteid", appName: "PosteID", urlScheme: "posteid", appStoreId: 1078512138)
    ]

    /// Suggerimenti rapidi italiani ed europei (SPID/CIE, Banche, Pagamenti, Trasporti, Domotica e Utility) aggiungibili con 1 tocco.
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
        InstalledAppRecord(packageName: "it.bancomat.pay", appName: "BANCOMAT"),
        InstalledAppRecord(packageName: "it.icbpi.mobile", appName: "Nexi Pay"),
        InstalledAppRecord(packageName: "net.klarna.app", appName: "Klarna"),
        InstalledAppRecord(packageName: "it.hype.app", appName: "HYPE"),
        InstalledAppRecord(packageName: "com.trenitalia.app", appName: "Trenitalia"),
        InstalledAppRecord(packageName: "it.ntvspa.italo", appName: "Italo Treno"),
        InstalledAppRecord(packageName: "com.ryanair.cheapflights", appName: "Ryanair"),
        InstalledAppRecord(packageName: "com.easypark.iphone", appName: "EasyPark"),
        InstalledAppRecord(packageName: "it.mooneygo.app", appName: "MooneyGo"),
        InstalledAppRecord(packageName: "it.telepass.tpy", appName: "Telepass"),
        InstalledAppRecord(packageName: "com.deliveroo.orderapp", appName: "Deliveroo"),
        InstalledAppRecord(packageName: "com.glovo.app", appName: "Glovo"),
        InstalledAppRecord(packageName: "com.einnovation.temu", appName: "Temu"),
        InstalledAppRecord(packageName: "com.brave.ios.browser", appName: "Brave"),
        InstalledAppRecord(packageName: "com.microsoft.msedge", appName: "Microsoft Edge"),
        InstalledAppRecord(packageName: "ch.protonmail.vpn", appName: "Proton VPN"),
        InstalledAppRecord(packageName: "com.google.calendar", appName: "Google Calendar"),
        InstalledAppRecord(packageName: "com.ookla.speedtest", appName: "Speedtest"),
        InstalledAppRecord(packageName: "com.teamviewer.rc", appName: "TeamViewer"),
        InstalledAppRecord(packageName: "it.a2a.mya2a", appName: "MyA2A"),
        InstalledAppRecord(packageName: "cloud.shelly.smartcontrol", appName: "Shelly Smart Control"),
        InstalledAppRecord(packageName: "com.ezviz.ezviz", appName: "EZVIZ"),
        InstalledAppRecord(packageName: "com.dreame.smartlife", appName: "Dreamehome"),
        InstalledAppRecord(packageName: "com.preply.tutor", appName: "Preply"),
        InstalledAppRecord(packageName: "com.canva.canvaeditor", appName: "Canva"),
        InstalledAppRecord(packageName: "com.lemon.lvoverseas", appName: "CapCut")
    ]

    /// Mappa le etichette corte o troncate mostrate sotto le icone della schermata Home iOS al titolo completo su App Store Italia.
    private static let homeScreenShortAliases: [String: String] = [
        "whatsapp": "WhatsApp Messenger",
        "wa business": "WhatsApp Business",
        "whatsapp busi": "WhatsApp Business",
        "telegram": "Telegram Messenger",
        "maps": "Google Maps",
        "google maps": "Google Maps",
        "chrome": "Google Chrome",
        "google chrom": "Google Chrome",
        "drive": "Google Drive",
        "prime video": "Amazon Prime Video",
        "amazon": "Amazon Shopping",
        "outlook": "Microsoft Outlook",
        "teams": "Microsoft Teams",
        "authenticator": "Google Authenticator",
        "google authe": "Google Authenticator",
        "ms authenticator": "Microsoft Authenticator",
        "zoom": "Zoom Workplace",
        "booking": "Booking.com",
        "booking.com": "Booking.com",
        "edge": "Microsoft Edge",
        "nexipay": "Nexi Pay",
        "nexi pay": "Nexi Pay",
        "bancomat": "BANCOMAT",
        "bancomat pay": "BANCOMAT",
        "intesa": "Intesa Sanpaolo Mobile",
        "intesa sanpaolo": "Intesa Sanpaolo Mobile",
        "intesa sanpa": "Intesa Sanpaolo Mobile",
        "unicredit": "UniCredit Mobile Banking",
        "unicredit mo": "UniCredit Mobile Banking",
        "bancoposta": "BancoPosta",
        "postepay": "Postepay",
        "posteid": "PosteID",
        "cieid": "CieID",
        "aruba pec": "Aruba PEC",
        "aruba id": "Aruba ID",
        "bper": "BPER Banca",
        "bper banca": "BPER Banca",
        "mediolanum": "Banca Mediolanum",
        "banca mediol": "Banca Mediolanum",
        "banca sella": "Banca Sella",
        "sella": "Banca Sella",
        "credit agricole": "Crédit Agricole Italia",
        "crédit agric": "Crédit Agricole Italia",
        "credit agric": "Crédit Agricole Italia",
        "isybank": "Isybank",
        "illimity": "illimity Bank",
        "widiba": "Banca Widiba",
        "findomestic": "Findomestic",
        "scalapay": "Scalapay",
        "too good to": "Too Good To Go",
        "too good to go": "Too Good To Go",
        "just eat": "Just Eat",
        "mediaset inf": "Mediaset Infinity",
        "mediaset infinity": "Mediaset Infinity",
        "raiplay": "RaiPlay",
        "sky go": "Sky Go",
        "mytim": "MyTIM",
        "my vodafone": "My Vodafone",
        "myfastweb": "MyFastweb",
        "yt music": "YouTube Music",
        "youtube musi": "YouTube Music",
        "yt studio": "YouTube Studio",
        "proton vpn": "Proton VPN",
        "protonvpn": "Proton VPN",
        "proton mail": "Proton Mail",
        "nordvpn": "NordVPN",
        "surfshark": "Surfshark VPN",
        "speedtest": "Speedtest by Ookla",
        "shelly": "Shelly Smart Control",
        "shelly smart": "Shelly Smart Control",
        "smart life": "Smart Life - Smart Living",
        "tapo": "TP-Link Tapo",
        "xiaomi home": "Xiaomi Home",
        "dreamehome": "Dreamehome",
        "mya2a": "MyA2A",
        "enel energia": "Enel Energia",
        "plenitude": "Eni Plenitude",
        "italo": "Italo Treno",
        "trenord": "Trenord",
        "unipolmove": "UnipolMove",
        "classeviva": "ClasseViva Studenti",
        "argo didup": "DidUP Famiglia",
        "didup": "DidUP Famiglia",
        "garmin": "Garmin Connect",
        "garmin conne": "Garmin Connect",
        "zepp": "Zepp",
        "mi fitness": "Mi Fitness",
        "miodottore": "MioDottore",
        "doctolib": "Doctolib",
        "immobiliare": "Immobiliare.it",
        "autoscout24": "AutoScout24",
        "giallozaffer": "GialloZafferano",
        "fantacalcio": "Leghe Fantacalcio",
        "gemini": "Google Gemini",
        "copilot": "Microsoft Copilot",
        "claude": "Claude by Anthropic",
        "perplexity": "Perplexity",
        "meta ai": "Meta AI",
        "word": "Microsoft Word",
        "excel": "Microsoft Excel",
        "powerpoint": "Microsoft PowerPoint",
        "onedrive": "Microsoft OneDrive",
        "onenote": "Microsoft OneNote",
        "google keep": "Google Keep",
        "google meet": "Google Meet",
        "google earth": "Google Earth",
        "google trans": "Google Traduttore",
        "traduci goog": "Google Traduttore",
        "traduttore": "Google Traduttore",
        "thefork": "TheFork",
        "uber eats": "Uber Eats",
        "lidl plus": "Lidl Plus",
        "wizz air": "Wizz Air",
        "ita airways": "ITA Airways",
        "trade republ": "Trade Republic",
        "scalable cap": "Scalable Capital",
        "monte dei pa": "Banca MPS",
        "banca mps": "Banca MPS",
        "bnl": "BNL",
        "bbva": "BBVA Italia",
        "webank": "Webank",
        "credem": "Credem Banca",
        "mediobanca": "Mediobanca Premier",
        "youapp": "YouApp",
        "banco bpm": "YouApp",
        "poste itali": "Poste Italiane",
        "banca genera": "Banca Generali",
        "ing italia": "ING Italia",
        "sumup": "SumUp",
        "now tv": "NOW"
    ]

    /// Ripulisce un'etichetta letta dalla schermata Home / Libreria App (rimuovendo l'ellissi `…` o `...` e simboli di stato come ☁️/•).
    static func cleanHomeScreenAppLabel(_ raw: String) -> (cleaned: String, wasTruncated: Bool) {
        var working = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "•›<>-–—_·:|«»\"?~*=,;()"))
            .trimmingCharacters(in: .whitespacesAndNewlines)

        var truncated = false
        if working.hasSuffix("…") {
            truncated = true
            working = String(working.dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
        } else if working.hasSuffix("..") || working.hasSuffix(". .") {
            truncated = true
            while working.hasSuffix(".") || working.hasSuffix(" ") {
                working.removeLast()
            }
            working = working.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // Compatta spazi multipli interni
        let collapsed = working
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return (collapsed, truncated)
    }

    /// Restituisce la query canonica ottimale per cercare l'app su App Store Italia partendo dall'etichetta della Home / Libreria App.
    static func canonicalAppQuery(for rawLabel: String) -> String {
        let (cleaned, _) = cleanHomeScreenAppLabel(rawLabel)
        let lower = cleaned.lowercased()
        if let mapped = homeScreenShortAliases[lower] {
            return mapped
        }
        let folded = lower.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "it_IT"))
        if let mappedFolded = homeScreenShortAliases[folded] {
            return mappedFolded
        }
        return cleaned
    }

    /// Indica se l'etichetta corrisponde con certezza a un'app verificata con nome distintivo (`>= 4` caratteri, mai codici ambigui di 2 lettere).
    static func isInstantlyTrustedAppLabel(_ rawLabel: String) -> Bool {
        let (cleaned, _) = cleanHomeScreenAppLabel(rawLabel)
        let lower = cleaned.lowercased()
        guard lower.count >= 4 else { return false }
        if homeScreenShortAliases[lower] != nil {
            return true
        }
        if knownProbes.contains(where: { $0.appName.lowercased() == lower }) {
            return true
        }
        if italianQuickSuggestions.contains(where: { $0.appName.lowercased() == lower }) {
            return true
        }
        return false
    }

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
        // Rimuove eventuali app errate salvate da versioni precedenti nella vecchia chiave v1
        if UserDefaults.standard.object(forKey: legacyCustomAppsStorageKey) != nil {
            UserDefaults.standard.removeObject(forKey: legacyCustomAppsStorageKey)
        }
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

    static func clearSavedCustomApps() {
        UserDefaults.standard.removeObject(forKey: legacyCustomAppsStorageKey)
        UserDefaults.standard.removeObject(forKey: customAppsStorageKey)
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

    /// Sul telefono Mittente verifica localmente i bundle ambigui (es. "Google" letto da una cartella o da "Google Maps",
    /// "Messenger" letto da "WhatsApp Messenger", "X" letto da un tasto chiudi, "IO" letto da testo italiano):
    /// poiché il loro schema URL è dichiarato in `Info.plist`, se `canOpenURL` è falso su questo iPhone l'app NON è installata.
    @MainActor
    static func filterFalsePositiveProbesOnSender(_ apps: [InstalledAppRecord]) -> [InstalledAppRecord] {
        let strictLocalSchemeBundles: [String: String] = [
            "com.google.googlemobile": "googleapp",
            "com.facebook.messenger": "fb-messenger",
            "net.whatsapp.whatsappsmb": "whatsapp-smb",
            "com.atebits.tweetie2": "twitter",
            "it.pagopa.app.io": "ioit"
        ]
        return apps.filter { app in
            let lowerBundle = app.packageName.lowercased()
            if let requiredScheme = strictLocalSchemeBundles[lowerBundle] {
                return canOpenScheme(requiredScheme)
            }
            return true
        }
    }

    /// Termini di sistema iOS, barra di stato, calendario dinamico, widget, cartelle generiche e badge che NON sono app scaricate.
    static let ignoredNonAppTerms: Set<String> = [
        // App di sistema Apple preinstallate
        "impostazioni", "settings", "app", "applicazioni", "cerca", "q cerca", "search", "indietro",
        "fotocamera", "foto", "telefono", "messaggi", "safari", "orologio", "calendario",
        "promemoria", "note", "mappe", "meteo", "borsa", "salute", "wallet", "casa",
        "dov'è", "dov e", "trova", "app store", "itunes store", "file", "calcolatrice", "bussola",
        "metro", "memo vocali", "contatti", "suggerimenti", "comandi rapidi", "lente",
        "traduci", "traduzi", "libri", "podcast", "tv", "musica", "fitness", "diario",
        "password", "freeform", "watch", "apple watch", "airpods", "iphone", "ipad",
        "facetime", "mail", "playground", "image playground", "inviti", "directswitch",
        // Categorie Libreria App & nomi comuni di Cartelle sulla schermata Home
        "libreria app", "libreria delle app", "cerca app", "cerca nelle app", "nessun risultato",
        "app di default", "app predefinite", "app nascoste", "generali", "accessibilità",
        "notifiche", "suoni e feedback", "full immersion", "personale", "riposo", "sonno", "alla guida",
        "tempo di utilizzo", "batteria", "raccolta smart", "smart stack",
        "privacy e sicurezza", "spazio su iphone", "documenti e dati", "scarica app",
        "elimina app", "registrazione schermo", "interrompi", "annulla", "fine", "chiudi", "apri",
        "social", "utilità", "utility", "produttività e finanza", "produttività", "finanza", "creatività",
        "informazione e lettura", "informazione", "intrattenimento", "salute e forma fisica",
        "shopping e cibo", "shopping", "cibo", "spesa", "viaggi", "trasporti", "mobilità",
        "istruzione", "navigazione", "consultazione", "foto e video", "musica e audio",
        "giochi", "altro", "varie", "extra", "aggiunte di recente", "suggerimenti di siri",
        "modifica", "rimuovi app", "condividi app", "condividi", "rimuovi", "elimina",
        "banche", "banca", "pagamenti", "carte", "lavoro", "ufficio", "scuola", "studio",
        "sport", "notizie", "news", "streaming", "strumenti", "tools", "domotica", "famiglia",
        // Barra di stato / Operatori SIM (le app reali si chiamano MyTIM, My Vodafone, MyFastweb)
        "5g", "4g", "3g", "lte", "wifi", "wi-fi", "sos", "solo sos", "nessun servizio",
        "iliad", "iliad it", "vodafone", "vodafone it", "tim", "tim it", "tim 5g",
        "windtre 5g", "fastweb", "fastweb it", "ho.", "ho", "very", "kena",
        // Giorni icona Calendario (es. "GIO 12"), mesi e widget Meteo / Foto
        "lun", "mar", "mer", "gio", "ven", "sab", "dom",
        "mon", "tue", "wed", "thu", "fri", "sat", "sun",
        "lunedì", "martedì", "mercoledì", "giovedì", "venerdì", "sabato", "domenica",
        "gennaio", "febbraio", "marzo", "aprile", "maggio", "giugno",
        "luglio", "agosto", "settembre", "ottobre", "novembre", "dicembre",
        "gen", "feb", "apr", "mag", "giu", "lug", "ago", "set", "ott", "nov", "dic",
        "jan", "aug", "sep", "oct", "dec",
        "oggi", "ieri", "domani", "ora", "adesso", "nessun evento", "nessuna sveglia",
        "sereno", "soleggiato", "nuvoloso", "pioggia", "temporale", "neve", "vento", "umidità",
        "per te", "ricordi", "in evidenza", "media giornaliera",
        // Badge grafici dentro le icone & brevi parole di sistema/interfaccia (evitano false corrispondenze sullo Store)
        "pro", "max", "vip", "hd", "4k", "ai", "new", "free", "plus", "live", "play",
        "info", "menu", "start", "stop", "scan", "chat", "call", "pass", "card", "shop",
        "club", "test", "beta", "lite", "mini", "ultra", "auto", "smart", "cloud", "home",
        "web", "net", "vpn", "pdf", "qr", "sim", "esim", "pin", "spid", "cie", "pec",
        "ok", "no", "si", "sì", "am", "pm", "re", "di", "da", "in", "con", "su", "per",
        "tra", "fra", "del", "al", "un", "una", "uno", "gli", "the", "and", "for", "off",
        "tap", "add", "all", "are", "but", "can", "day", "end", "faq", "few", "get", "has",
        "how", "key", "low", "min", "not", "now", "old", "one", "our", "out", "own", "pay",
        "put", "run", "see", "set", "six", "two", "use", "way", "who", "why", "yes", "yet", "you"
    ]

    private static let ignoredSubstrings: [String] = [
        "ultimo utilizzo", "mai utilizzat", "kb/s", "mb/s", "registrazione dello schermo",
        "spazio disponibile", "in uso", "elementi nascosti", "nessun evento", "cerca app",
        "iliad it", "vodafone it", "nessun servizio", "parzialmente nuvoloso", "condizioni meteo"
    ]

    /// Marchi univoci a 3 caratteri effettivamente diffusi in Italia come nomi completi sotto icona.
    private static let allowedThreeCharAppTokens: Set<String> = [
        "vlc", "dhl", "ups", "gls", "brt", "h&m", "n26", "avg", "kfc", "atm", "gtt", "bmw", "ovs", "bnl", "ing"
    ]

    /// Analizza e filtra le stringhe OCR mantenendo l'informazione `wasTruncated` (`…` / `...`) per il matching rigoroso.
    static func parsePlausibleAppCandidates(_ rawStrings: [String]) -> [ParsedAppCandidate] {
        let weekdayOrMonthPrefixes: Set<String> = [
            "lun", "mar", "mer", "gio", "ven", "sab", "dom",
            "mon", "tue", "wed", "thu", "fri", "sat", "sun",
            "gen", "feb", "apr", "mag", "giu", "lug", "ago", "set", "ott", "nov", "dic",
            "jan", "aug", "sep", "oct", "dec"
        ]

        var out: [ParsedAppCandidate] = []
        var seen = Set<String>()

        for raw in rawStrings {
            let (cleaned, wasTruncated) = cleanHomeScreenAppLabel(raw)
            guard cleaned.count >= 2, cleaned.count <= 40 else { continue }

            let words = cleaned.split(separator: " ").map(String.init)
            // Un nome di icona o voce in Libreria App non è una frase lunga di un widget
            guard words.count <= 5 else { continue }

            // Scarta frammenti della barra laterale alfabetica A–Z (es. "A B C", "X Y")
            if words.count >= 2 && words.allSatisfy({ $0.count <= 1 }) { continue }

            let lower = cleaned.lowercased()
            if ignoredNonAppTerms.contains(lower) { continue }
            if lower.hasSuffix("%") || lower.hasSuffix("°") || lower.hasSuffix("°c") || lower.contains("€") || lower.contains("$") {
                continue
            }
            if ignoredSubstrings.contains(where: { lower.contains($0) }) { continue }

            // Scarta etichette brevi a 2 o 3 caratteri non corrispondenti a un'app/alias noto (evita rumore grafico delle icone e pulsanti UI)
            let isKnownShortAlias = homeScreenShortAliases[lower] != nil
                || knownProbes.contains(where: { $0.appName.lowercased() == lower })
            if cleaned.count == 2 && cleaned != "IO" && !isKnownShortAlias {
                continue
            }
            if cleaned.count == 3 && !isKnownShortAlias && !allowedThreeCharAppTokens.contains(lower) {
                continue
            }

            // Scarta date dell'icona Calendario / Lock / Widget (es. "GIO 12", "12 NOV", "GIO 12 NOV")
            if words.count == 2 || words.count == 3 {
                let lw = words.map { $0.lowercased().trimmingCharacters(in: .punctuationCharacters) }
                let hasDateToken = lw.contains { weekdayOrMonthPrefixes.contains($0) }
                let hasDayNumber = lw.contains { !$0.isEmpty && $0.allSatisfy(\.isNumber) && $0.count <= 2 }
                if hasDateToken && hasDayNumber {
                    continue
                }
                if words.count == 2, ["5g", "4g", "lte", "it"].contains(lw[1]),
                   ["iliad", "vodafone", "tim", "windtre", "fastweb", "very", "kena", "ho", "ho."].contains(lw[0]) {
                    continue
                }
            }

            // Scarta dimensioni spazio (es. "348,2 MB", "1.4 GB", "820 KB")
            if lower.hasSuffix(" mb") || lower.hasSuffix(" gb") || lower.hasSuffix(" kb") || lower.hasSuffix(" tb") {
                let prefixPart = lower.dropLast(3).trimmingCharacters(in: .whitespaces)
                if prefixPart.allSatisfy({ $0.isNumber || $0 == "," || $0 == "." }) {
                    continue
                }
            }

            // Scarta orari (es. 20:09), date (12/11) o stringhe prive di lettere (ammette marchi alfanumerici noti come "N26")
            if cleaned.contains(":") && cleaned.filter(\.isNumber).count >= 2 { continue }
            let lettersCount = cleaned.unicodeScalars.filter { CharacterSet.letters.contains($0) }.count
            if lettersCount == 0 { continue }
            if lettersCount < 2 && !isKnownShortAlias && !allowedThreeCharAppTokens.contains(lower) {
                continue
            }

            // Evita falsi positivi da "io" minuscolo in frasi italiane (l'app ufficiale PagoPA è scritta "IO" maiuscolo)
            if lower == "io" && cleaned != "IO" { continue }

            if !seen.contains(lower) {
                seen.insert(lower)
                out.append(ParsedAppCandidate(cleaned: cleaned, wasTruncated: wasTruncated))
            }
        }
        return Array(out.prefix(250))
    }

    /// Filtra le stringhe estratte tramite OCR restituendo i nomi candidati puliti (fino a 250 app utente).
    static func filterPlausibleAppNames(_ rawStrings: [String]) -> [String] {
        parsePlausibleAppCandidates(rawStrings).map(\.cleaned)
    }

    // MARK: - Geometria Spaziale Vision (Separa icone affiancate sulla stessa riga + Unisce etichette su 2 righe + Taglia barra di stato)

    /// Suddivide una singola riga `VNRecognizedTextObservation` quando `Vision` fonde per errore due icone adiacenti
    /// della griglia Home (es. `"Spotify   Netflix"` -> `["Spotify", "Netflix"]`) misurando il gap orizzontale tra parole.
    private static func splitHorizontallyMergedObservation(
        _ obs: VNRecognizedTextObservation,
        minConfidence: Float
    ) -> [RecognizedAppTextBox] {
        guard let top = obs.topCandidates(1).first, top.confidence >= minConfidence else {
            return []
        }
        let fullText = top.string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !fullText.isEmpty else { return [] }

        // Individua i range delle singole parole nella stringa riconosciuta
        var wordTokens: [(word: String, rect: CGRect)] = []
        var searchStart = fullText.startIndex
        while searchStart < fullText.endIndex {
            while searchStart < fullText.endIndex && fullText[searchStart].isWhitespace {
                searchStart = fullText.index(after: searchStart)
            }
            guard searchStart < fullText.endIndex else { break }
            var wordEnd = searchStart
            while wordEnd < fullText.endIndex && !fullText[wordEnd].isWhitespace {
                wordEnd = fullText.index(after: wordEnd)
            }
            let range = searchStart..<wordEnd
            let tokenStr = String(fullText[range])
            if let wordObs = try? top.boundingBox(for: range) {
                wordTokens.append((tokenStr, wordObs.boundingBox))
            } else {
                return [RecognizedAppTextBox(text: fullText, boundingBox: obs.boundingBox, confidence: top.confidence)]
            }
            searchStart = wordEnd
        }

        guard wordTokens.count >= 2 else {
            return [RecognizedAppTextBox(text: fullText, boundingBox: obs.boundingBox, confidence: top.confidence)]
        }

        wordTokens.sort { $0.rect.minX < $1.rect.minX }

        var segments: [RecognizedAppTextBox] = []
        var currentWords: [String] = [wordTokens[0].word]
        var currentUnionRect: CGRect = wordTokens[0].rect

        for idx in 1..<wordTokens.count {
            let next = wordTokens[idx]
            let prevMaxX = currentUnionRect.maxX
            let gap = next.rect.minX - prevMaxX
            let avgHeight = max(0.008, (currentUnionRect.height + next.rect.height) * 0.5)
            // Dentro il nome di una singola app lo spazio tra parole è ~0.35-0.8x altezza carattere (~0.006-0.015);
            // tra due icone affiancate della Home il vuoto supera max(0.022, 1.85x altezza carattere) anche con fotocamera distante.
            if gap > max(0.022, avgHeight * 1.85) {
                segments.append(
                    RecognizedAppTextBox(
                        text: currentWords.joined(separator: " "),
                        boundingBox: currentUnionRect,
                        confidence: top.confidence
                    )
                )
                currentWords = [next.word]
                currentUnionRect = next.rect
            } else {
                currentWords.append(next.word)
                currentUnionRect = currentUnionRect.union(next.rect)
            }
        }

        segments.append(
            RecognizedAppTextBox(
                text: currentWords.joined(separator: " "),
                boundingBox: currentUnionRect,
                confidence: top.confidence
            )
        )
        return segments
    }

    /// Elabora i riquadri spaziali `RecognizedAppTextBox`:
    /// 1) Scarta la barra di stato superiore (`y > 0.942` negli screenshot: ora, operatore SIM, batteria) e scritte giganti dei widget.
    /// 2) Unisce automaticamente le etichette centrate su 2 righe sotto la stessa icona (es. `"Intesa"` + `"Sanpaolo"` -> `"Intesa Sanpaolo"`),
    ///    senza mai fondere righe distinte dell'elenco verticale A–Z in «Libreria app».
    static func mergeAndSplitSpatialTextBoxes(
        _ rawBoxes: [RecognizedAppTextBox],
        stripTopStatusBar: Bool
    ) -> [String] {
        let maxAllowedHeight: CGFloat = stripTopStatusBar ? 0.036 : 0.055
        let filteredBoxes = rawBoxes.filter { item in
            let b = item.boundingBox
            if stripTopStatusBar && b.minY > 0.942 {
                return false
            }
            if b.height < 0.005 || b.height > maxAllowedHeight {
                return false
            }
            return !item.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        guard !filteredBoxes.isEmpty else { return [] }

        // Ordina dall'alto verso il basso (maxY decrescente in Vision) e da sinistra a destra
        let sorted = filteredBoxes.sorted { a, b in
            if abs(a.boundingBox.maxY - b.boundingBox.maxY) > 0.012 {
                return a.boundingBox.maxY > b.boundingBox.maxY
            }
            return a.boundingBox.minX < b.boundingBox.minX
        }

        var consumed = Set<Int>()
        var outputLines: [String] = []

        for i in sorted.indices {
            if consumed.contains(i) { continue }
            let upper = sorted[i]
            let uBox = upper.boundingBox

            // Verifica se subito sotto questa etichetta stretta (colonna icona Home < 0.29) c'è la 2ª riga centrate dello stesso nome app
            var joinedText = upper.text
            if uBox.width < 0.29 {
                var bestLowerIdx: Int? = nil
                var bestVGap: CGFloat = .greatestFiniteMagnitude

                for j in (i + 1)..<sorted.count {
                    if consumed.contains(j) { continue }
                    let lower = sorted[j]
                    let lBox = lower.boundingBox
                    guard lBox.width < 0.29 else { continue }

                    let maxLineHeight = max(uBox.height, lBox.height)
                    let vGap = uBox.minY - lBox.maxY
                    if vGap > maxLineHeight * 0.72 {
                        if uBox.minY - lBox.maxY > 0.035 { break }
                        continue
                    }
                    guard vGap >= -0.005 else { continue }

                    // Stessa colonna verticale centrata sotto l'icona e altezza font compatibile
                    let xDelta = abs(uBox.midX - lBox.midX)
                    let isLeftAlignedAZRows = abs(uBox.minX - lBox.minX) < 0.010 && abs(uBox.width - lBox.width) > 0.05 && vGap > maxLineHeight * 0.42
                    let heightRatio = maxLineHeight / max(0.001, min(uBox.height, lBox.height))
                    if !isLeftAlignedAZRows && xDelta < 0.045 && heightRatio <= 1.70 && vGap < bestVGap {
                        bestVGap = vGap
                        bestLowerIdx = j
                    }
                }

                if let matchIdx = bestLowerIdx {
                    consumed.insert(matchIdx)
                    joinedText = "\(upper.text) \(sorted[matchIdx].text)"
                }
            }

            outputLines.append(joinedText)
        }

        return outputLines
    }

    /// Esegue l'OCR spaziale Apple `Vision` su un singolo screenshot (`CGImage`).
    private static func recognizeTextLines(in cgImg: CGImage, stripTopStatusBar: Bool = true) -> [String] {
        let req = VNRecognizeTextRequest()
        req.recognitionLevel = .accurate
        req.usesLanguageCorrection = false
        req.recognitionLanguages = ["it-IT", "en-US"]
        let handler = VNImageRequestHandler(cgImage: cgImg, options: [:])
        try? handler.perform([req])

        guard let observations = req.results, !observations.isEmpty else { return [] }
        var boxes: [RecognizedAppTextBox] = []
        for obs in observations {
            boxes.append(contentsOf: splitHorizontallyMergedObservation(obs, minConfidence: 0.56))
        }
        return mergeAndSplitSpatialTextBoxes(boxes, stripTopStatusBar: stripTopStatusBar)
    }

    /// Esegue l'OCR spaziale Apple `Vision` su un fotogramma live della fotocamera (`CVPixelBuffer`).
    static func recognizeSpatialCameraFrameLines(
        in pixelBuffer: CVPixelBuffer,
        orientation: CGImagePropertyOrientation = .right,
        minConfidence: Float = 0.60
    ) -> [String] {
        let req = VNRecognizeTextRequest()
        req.recognitionLevel = .accurate
        req.usesLanguageCorrection = false
        req.recognitionLanguages = ["it-IT", "en-US"]
        req.regionOfInterest = CGRect(x: 0.04, y: 0.05, width: 0.92, height: 0.90)

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: orientation, options: [:])
        try? handler.perform([req])

        guard let observations = req.results, !observations.isEmpty else { return [] }
        var boxes: [RecognizedAppTextBox] = []
        for obs in observations {
            boxes.append(contentsOf: splitHorizontallyMergedObservation(obs, minConfidence: minConfidence))
        }
        // Nella fotocamera live il bordo superiore dell'inquadratura non coincide con y=1.0 dello schermo, quindi non tagliamo per Y fisso
        return mergeAndSplitSpatialTextBoxes(boxes, stripTopStatusBar: false)
    }

    /// Risolve i candidati estratti (da Libreria App, schermata Home o fotocamera live) in record ufficiali App Store:
    /// - Fast-path istantaneo a 0 chiamate `/search` per le 46 app verificate in `knownProbes`
    /// - Concorrenza controllata (`chunkSize = 3` + pacing anti-rate-limit) per non perdere nessuna app su cataloghi da 100+ app
    /// - Verifica rigorosa del titolo principale (`strictTitleSimilarity: true`) per zero app inventate
    static func resolveCandidateAppLines(_ extractedLines: [String]) async -> [InstalledAppRecord] {
        let candidates = parsePlausibleAppCandidates(extractedLines)
        guard !candidates.isEmpty else { return [] }

        var resolved: [InstalledAppRecord] = []
        var seenKeys = Set<String>()
        var networkCandidates: [(query: String, wasTruncated: Bool)] = []

        // 1. Risoluzione offline immediata (0ms, zero rate-limit) per tutte le app già presenti in `knownProbes`
        for cand in candidates {
            let query = canonicalAppQuery(for: cand.cleaned)
            if let probe = knownProbes.first(where: { $0.appName.caseInsensitiveCompare(query) == .orderedSame }) {
                let dedup = "\(probe.bundleId.lowercased())_\(probe.appStoreId)"
                if !seenKeys.contains(dedup) {
                    seenKeys.insert(dedup)
                    resolved.append(
                        InstalledAppRecord(
                            packageName: probe.bundleId,
                            appName: probe.appName,
                            appStoreId: probe.appStoreId,
                            iconUrl: nil,
                            urlScheme: probe.urlScheme
                        )
                    )
                }
            } else {
                networkCandidates.append((query: query, wasTruncated: cand.wasTruncated))
            }
        }

        // 2. Ricerca App Store controllata (`chunkSize = 3` + pausa leggera) per evitare qualsiasi blocco HTTP 429/403 di iTunes
        let chunkSize = 3
        var idx = 0
        while idx < networkCandidates.count {
            let slice = Array(networkCandidates[idx..<min(idx + chunkSize, networkCandidates.count)])
            idx += chunkSize

            let batchMatches = await withTaskGroup(of: InstalledAppRecord?.self) { group -> [InstalledAppRecord] in
                for item in slice {
                    group.addTask {
                        await iOSAppStoreCatalogResolver.searchBestMatch(
                            appName: item.query,
                            wasTruncated: item.wasTruncated,
                            strictTitleSimilarity: true
                        )
                    }
                }
                var collected: [InstalledAppRecord] = []
                for await maybeApp in group {
                    if let app = maybeApp {
                        collected.append(app)
                    }
                }
                return collected
            }

            for app in batchMatches {
                let dedup = "\(app.packageName.lowercased())_\(app.appStoreId ?? 0)"
                if !seenKeys.contains(dedup) && app.packageName.lowercased() != "com.directswitch.ios" {
                    seenKeys.insert(dedup)
                    resolved.append(app)
                }
            }

            if idx < networkCandidates.count {
                try? await Task.sleep(nanoseconds: 95_000_000)
            }
        }

        // 3. Carica in un'unica chiamata batch `/lookup?id=...` le icone mancanti delle app risolte offline
        if resolved.contains(where: { $0.iconUrl == nil }) {
            resolved = await iOSAppStoreCatalogResolver.enrichAppsWithStoreMetadata(resolved)
        }

        return resolved
    }

    /// Legge tramite Apple `Vision` spaziale i nomi di tutte le app presenti negli screenshot scelti dall'utente.
    static func recognizeAppsFromScreenshots(_ images: [UIImage]) async -> [InstalledAppRecord] {
        guard !images.isEmpty else { return [] }
        let cgImages = images.compactMap(\.cgImage)
        guard !cgImages.isEmpty else { return [] }

        let extractedLines: [String] = await Task.detached(priority: .userInitiated) {
            var lines: [String] = []
            for cgImg in cgImages {
                autoreleasepool {
                    lines.append(contentsOf: recognizeTextLines(in: cgImg, stripTopStatusBar: true))
                }
            }
            return lines
        }.value

        return await resolveCandidateAppLines(extractedLines)
    }

    /// Estrae automaticamente i fotogrammi nitidi da un video di scorrimento schermo (`AVAsset`) in `autoreleasepool`.
    static func extractLinesFromScrollVideoAsset(_ avAsset: AVAsset, maxScreenshots: Int = 35) async -> (lines: [String], generatedCount: Int) {
        final class UncheckedAssetBox: @unchecked Sendable {
            let asset: AVAsset
            init(_ asset: AVAsset) { self.asset = asset }
        }
        let box = UncheckedAssetBox(avAsset)
        let durationTime = (try? await avAsset.load(.duration)) ?? .zero
        let totalSeconds = max(0.0, CMTimeGetSeconds(durationTime))
        guard totalSeconds > 0.15 else { return ([], 0) }

        let effectiveDuration = min(totalSeconds, 65.0)
        let stepSeconds = max(0.55, effectiveDuration / Double(max(1, maxScreenshots)))
        var sampleTimes: [CMTime] = []
        var cursor = 0.20
        while cursor < effectiveDuration && sampleTimes.count < maxScreenshots {
            sampleTimes.append(CMTime(seconds: cursor, preferredTimescale: 600))
            cursor += stepSeconds
        }
        if sampleTimes.isEmpty {
            sampleTimes.append(CMTime(seconds: min(0.1, effectiveDuration * 0.5), preferredTimescale: 600))
        }

        return await Task.detached(priority: .userInitiated) {
            let generator = AVAssetImageGenerator(asset: box.asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 1290, height: 2796)
            generator.requestedTimeToleranceBefore = CMTime(seconds: 0.12, preferredTimescale: 600)
            generator.requestedTimeToleranceAfter = CMTime(seconds: 0.12, preferredTimescale: 600)

            var allLines: [String] = []
            var count = 0
            for t in sampleTimes {
                autoreleasepool {
                    if let cgImg = try? generator.copyCGImage(at: t, actualTime: nil) {
                        count += 1
                        allLines.append(contentsOf: recognizeTextLines(in: cgImg, stripTopStatusBar: true))
                    }
                }
            }
            return (allLines, count)
        }.value
    }

    /// Analizza un file video locale scelto esplicitamente dall'utente via `PhotosPicker`.
    static func recognizeAppsFromScrollVideoURL(_ url: URL) async -> (apps: [InstalledAppRecord], generatedScreenshots: Int) {
        let asset = AVURLAsset(url: url)
        let (lines, framesCount) = await extractLinesFromScrollVideoAsset(asset, maxScreenshots: 35)
        guard !lines.isEmpty else { return ([], framesCount) }
        let apps = await resolveCandidateAppLines(lines)
        return (apps, framesCount)
    }

    /// PASSO 1 AUTOMATICO: legge esclusivamente gli screenshot (o registrazioni schermo verticali) scattati per la sessione corrente,
    /// evitando di analizzare vecchi video personali o vecchi screenshot di chat WhatsApp/web che inventerebbero app inesistenti.
    static func extractAutomaticScreenshotsAndRecognizeApps(since armedDate: Date?) async -> AutoScreenshotCaptureResult {
        var status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if status == .notDetermined {
            status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        }
        guard status == .authorized || status == .limited else {
            return AutoScreenshotCaptureResult(discoveredApps: [], generatedScreenshotsCount: 0, analyzedVideoAssetLocalIdentifier: nil)
        }

        // Finestra stretta: se armato dal Passo 1 usa l'istante di avvio (-10s), altrimenti solo gli ultimi 25 minuti (mai 48 ore!)
        let cutoffDate: Date
        if let armed = armedDate {
            cutoffDate = armed.addingTimeInterval(-10)
        } else {
            cutoffDate = Date().addingTimeInterval(-25 * 60)
        }

        var collectedLines: [String] = []
        var totalGeneratedFrames = 0
        var newestAnalyzedVideoId: String? = nil

        // 1. Analizza video SOLO se l'utente aveva armato la cattura (`armedDate != nil`) E il video ha proporzioni verticali da schermo iPhone
        if armedDate != nil {
            let screenBounds = await MainActor.run { UIScreen.main.bounds }
            let expectedAspect = min(screenBounds.width, screenBounds.height) / max(1.0, max(screenBounds.width, screenBounds.height))

            let videoFetch = PHFetchOptions()
            videoFetch.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            videoFetch.predicate = NSPredicate(format: "creationDate >= %@ AND duration <= 180", cutoffDate as NSDate)
            videoFetch.fetchLimit = 2

            let videoAssets = PHAsset.fetchAssets(with: .video, options: videoFetch)
            if videoAssets.count > 0 {
                var screenVideos: [PHAsset] = []
                videoAssets.enumerateObjects { asset, _, _ in
                    guard asset.pixelHeight > asset.pixelWidth, asset.pixelWidth > 0 else { return }
                    let vidAspect = CGFloat(asset.pixelWidth) / CGFloat(asset.pixelHeight)
                    // Accetta solo registrazioni con aspect ratio dello schermo dell'iPhone (~0.46), mai video 9:16=0.5625 girati dalla fotocamera!
                    if abs(vidAspect - expectedAspect) <= 0.035 {
                        screenVideos.append(asset)
                    }
                }

                let imageManager = PHImageManager.default()
                let vidOptions = PHVideoRequestOptions()
                vidOptions.isNetworkAccessAllowed = true
                vidOptions.deliveryMode = .highQualityFormat

                for videoPhAsset in screenVideos {
                    let loadedAVAsset: AVAsset? = await withCheckedContinuation { continuation in
                        var settled = false
                        let lock = NSLock()
                        imageManager.requestAVAsset(forVideo: videoPhAsset, options: vidOptions) { avAsset, _, _ in
                            lock.lock()
                            defer { lock.unlock() }
                            guard !settled else { return }
                            settled = true
                            continuation.resume(returning: avAsset)
                        }
                    }
                    if let avAsset = loadedAVAsset {
                        let (videoLines, framesCount) = await extractLinesFromScrollVideoAsset(avAsset, maxScreenshots: 35)
                        if framesCount > 0 {
                            totalGeneratedFrames += framesCount
                            collectedLines.append(contentsOf: videoLines)
                            if newestAnalyzedVideoId == nil {
                                newestAnalyzedVideoId = videoPhAsset.localIdentifier
                            }
                        }
                    }
                }
            }
        }

        // 2. Legge gli screenshot recenti dall'album «Istantanee» (fino a 20 pagine)
        let recentScreenshotPairs = await fetchRecentScreenshotsWithIdentifiersFromLibrary(maxCount: 20, since: cutoffDate)
        let screenshotIdsForCleanup = armedDate != nil ? recentScreenshotPairs.map(\.localIdentifier) : []
        if !recentScreenshotPairs.isEmpty {
            let cgImgs = recentScreenshotPairs.compactMap(\.image.cgImage)
            let shotLines: [String] = await Task.detached(priority: .userInitiated) {
                var out: [String] = []
                for cg in cgImgs {
                    autoreleasepool {
                        out.append(contentsOf: recognizeTextLines(in: cg, stripTopStatusBar: true))
                    }
                }
                return out
            }.value
            totalGeneratedFrames += cgImgs.count
            collectedLines.append(contentsOf: shotLines)
        }

        guard !collectedLines.isEmpty else {
            return AutoScreenshotCaptureResult(
                discoveredApps: [],
                generatedScreenshotsCount: totalGeneratedFrames,
                analyzedVideoAssetLocalIdentifier: newestAnalyzedVideoId,
                analyzedScreenshotLocalIdentifiers: screenshotIdsForCleanup
            )
        }

        let rawResolved = await resolveCandidateAppLines(collectedLines)
        let verifiedApps = await MainActor.run {
            filterFalsePositiveProbesOnSender(rawResolved)
        }
        return AutoScreenshotCaptureResult(
            discoveredApps: verifiedApps,
            generatedScreenshotsCount: totalGeneratedFrames,
            analyzedVideoAssetLocalIdentifier: newestAnalyzedVideoId,
            analyzedScreenshotLocalIdentifiers: screenshotIdsForCleanup
        )
    }

    /// Consente di eliminare con 1 tocco dal Rullino gli screenshot temporanei delle pagine Home o la breve registrazione usati per rilevare le app.
    static func deleteTemporaryCapturedAssets(localIdentifiers: [String]) async -> Bool {
        let validIds = localIdentifiers.filter { !$0.isEmpty }
        guard !validIds.isEmpty else { return false }
        let fetched = PHAsset.fetchAssets(withLocalIdentifiers: validIds, options: nil)
        guard fetched.count > 0 else { return false }
        return await withCheckedContinuation { continuation in
            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.deleteAssets(fetched)
            }) { success, _ in
                continuation.resume(returning: success)
            }
        }
    }

    static func deleteTemporaryRecordingAsset(localIdentifier: String) async -> Bool {
        await deleteTemporaryCapturedAssets(localIdentifiers: [localIdentifier])
    }

    /// Legge gli screenshot dall'album «Istantanee» a partire da una data (default ultime 48 ore).
    static func fetchRecentScreenshotsFromLibrary(maxCount: Int = 12, since customCutoff: Date? = nil) async -> [UIImage] {
        let pairs = await fetchRecentScreenshotsWithIdentifiersFromLibrary(maxCount: maxCount, since: customCutoff)
        return pairs.map(\.image)
    }

    static func fetchRecentScreenshotsWithIdentifiersFromLibrary(
        maxCount: Int = 12,
        since customCutoff: Date? = nil
    ) async -> [(localIdentifier: String, image: UIImage)] {
        var status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if status == .notDetermined {
            status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        }
        guard status == .authorized || status == .limited else {
            return []
        }

        let cutoffDate = customCutoff ?? Date().addingTimeInterval(-48 * 3600)
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

        var results: [(localIdentifier: String, image: UIImage)] = []
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
                results.append((asset.localIdentifier, loaded))
            }
        }
        return results
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
            if let resolved = await searchBestMatch(appName: working[idx].appName, wasTruncated: false, strictTitleSimilarity: false) {
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

    /// Normalizza un titolo rimuovendo accenti e punteggiatura superflua (mantenendo `+` e `&` per nomi come `Disney+` e `H&M`).
    static func normalizeForTitleMatch(_ raw: String) -> String {
        let folded = raw.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "it_IT")).lowercased()
        var out = ""
        out.reserveCapacity(folded.count)
        for scalar in folded.unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) || scalar == "+" || scalar == "&" {
                out.unicodeScalars.append(scalar)
            } else {
                out.append(" ")
            }
        }
        return out
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    /// Estrae il titolo principale dell'app su App Store tagliando gli slogan di marketing dopo ` - `, `: `, `, `, ` by `, ` | `, ` (`, ecc.
    static func extractPrimaryStoreTitle(_ storeTrackName: String) -> String {
        let separators = [" - ", " – ", " — ", ": ", ", ", " | ", " · ", " • ", " (", " by "]
        var bestCut = storeTrackName.endIndex
        for sep in separators {
            if let range = storeTrackName.range(of: sep), range.lowerBound < bestCut, range.lowerBound > storeTrackName.startIndex {
                bestCut = range.lowerBound
            }
        }
        return String(storeTrackName[..<bestCut]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Parole singole generiche che non devono mai abbinare per prefisso o titolo parziale un'app dello Store.
    private static let genericAmbiguousSingleWords: Set<String> = [
        "lavoro", "banche", "banca", "finanza", "scuola", "studio", "sport", "viaggi", "casa",
        "salute", "foto", "video", "musica", "giochi", "notizie", "news", "meteo", "mappe",
        "spesa", "cibo", "auto", "moto", "treni", "voli", "hotel", "varie", "altro", "extra",
        "pro", "max", "vip", "hd", "4k", "ai", "new", "free", "plus", "live", "play", "scan",
        "chat", "call", "smart", "cloud", "home", "club", "pass", "card", "shop", "info", "menu",
        "test", "ora", "oggi", "ieri", "domani", "condividi", "modifica", "cerca", "apri", "chiudi"
    ]

    private static let allowedTrailingStoreQualifiers: Set<String> = [
        "app", "mobile", "italia", "italy", "it", "banca", "bank", "banking", "pay", "messenger",
        "shopping", "shop", "club", "music", "video", "tv", "plus", "go", "online", "smart", "control",
        "home", "connect", "workplace", "studenti", "famiglia", "famiglie", "clienti", "card", "otp",
        "live", "ai", "studio", "editor", "notify", "energia", "assicurazioni", "flights", "airlines",
        "treno", "vpn", "browser", "mail"
    ]

    /// Verifica rigorosa anti-allucinazione tra il nome letto sullo schermo del telefono e il titolo ufficiale su App Store:
    /// impedisce che parole casuali, nomi di cartelle o sottotitoli generino app inesistenti.
    static func isVerifiedAppStoreTitleMatch(
        candidateQuery: String,
        wasTruncated: Bool,
        storeAppName: String
    ) -> Bool {
        let cand = normalizeForTitleMatch(candidateQuery)
        let prim = normalizeForTitleMatch(extractPrimaryStoreTitle(storeAppName))
        let full = normalizeForTitleMatch(storeAppName)
        guard !cand.isEmpty, !prim.isEmpty else { return false }

        let candWords = cand.split(separator: " ").map(String.init)
        let primWords = prim.split(separator: " ").map(String.init)
        guard !candWords.isEmpty, !primWords.isEmpty else { return false }

        if candWords.count == 1 && genericAmbiguousSingleWords.contains(cand) {
            return false
        }

        // 1. Corrispondenza esatta col titolo principale dello Store (es. "Subito" == "Subito" in "Subito - Annunci e shopping")
        if cand == prim || cand == full {
            return true
        }

        // 2. Etichetta troncata da iOS sulla schermata Home con `…` (es. "Banca Mediol…" -> prefisso di "Banca Mediolanum")
        if wasTruncated && cand.count >= 5 && (prim.hasPrefix(cand) || full.hasPrefix(cand)) {
            return true
        }

        // 3. Corrispondenza per parole intere dall'inizio del titolo principale (es. "Fineco" -> "Fineco Bank", "ClasseViva" -> "ClasseViva Studenti")
        if primWords.count > candWords.count && Array(primWords.prefix(candWords.count)) == candWords {
            if candWords.count >= 2 {
                return true
            }
            let trailing = primWords.dropFirst(candWords.count)
            if cand.count >= 7 && primWords.count <= 3 {
                return true
            }
            if cand.count >= 4 && primWords.count <= 3 && trailing.allSatisfy({ allowedTrailingStoreQualifiers.contains($0) }) {
                return true
            }
        }

        return false
    }

    static func searchBestMatch(
        appName: String,
        wasTruncated: Bool = false,
        strictTitleSimilarity: Bool
    ) async -> InstalledAppRecord? {
        let trimmed = appName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let cacheKey = wasTruncated ? "\(trimmed)|trunc" : trimmed
        if let cached = await AppStoreMetadataCache.shared.getByName(cacheKey) {
            return cached
        }

        let results = await searchAppStore(query: trimmed, limit: 8)

        if !strictTitleSimilarity {
            if let first = results.first {
                await AppStoreMetadataCache.shared.setByName(cacheKey, record: first)
                return first
            }
            return nil
        }

        // Priorità 1: match esatto sul titolo principale
        let normQuery = normalizeForTitleMatch(trimmed)
        if let exactHit = results.first(where: {
            normalizeForTitleMatch(extractPrimaryStoreTitle($0.appName)) == normQuery
                && isVerifiedAppStoreTitleMatch(candidateQuery: trimmed, wasTruncated: wasTruncated, storeAppName: $0.appName)
        }) {
            await AppStoreMetadataCache.shared.setByName(cacheKey, record: exactHit)
            return exactHit
        }

        // Priorità 2: primo risultato verificato rigorosamente
        if let verifiedHit = results.first(where: {
            isVerifiedAppStoreTitleMatch(candidateQuery: trimmed, wasTruncated: wasTruncated, storeAppName: $0.appName)
        }) {
            await AppStoreMetadataCache.shared.setByName(cacheKey, record: verifiedHit)
            return verifiedHit
        }

        // Priorità 3: se l'etichetta Home finiva con `…` e l'ultima parola era tagliata a metà (es. "Banca Mediol…"),
        // cerca con le parole intere precedenti mantenendo l'obbligo che il titolo inizi con l'intero prefisso letto!
        if wasTruncated {
            let parts = trimmed.split(separator: " ").map(String.init)
            if parts.count >= 2 {
                let wholeWordsPrefix = parts.dropLast().joined(separator: " ")
                if wholeWordsPrefix.count >= 4 {
                    let fallbackResults = await searchAppStore(query: wholeWordsPrefix, limit: 15)
                    if let truncHit = fallbackResults.first(where: {
                        isVerifiedAppStoreTitleMatch(candidateQuery: trimmed, wasTruncated: true, storeAppName: $0.appName)
                    }) {
                        await AppStoreMetadataCache.shared.setByName(cacheKey, record: truncHit)
                        return truncHit
                    }
                }
            }
        }

        return nil
    }

    static func searchAppStore(query: String, limit: Int = 12) async -> [InstalledAppRecord] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://itunes.apple.com/search?term=\(encoded)&country=it&entity=software&limit=\(limit)") else {
            return []
        }

        var responseData: Data? = nil
        for attempt in 0..<2 {
            var req = URLRequest(url: url, timeoutInterval: 6.5)
            req.httpMethod = "GET"
            if let (data, resp) = try? await URLSession.shared.data(for: req),
               let code = (resp as? HTTPURLResponse)?.statusCode {
                if code == 200 {
                    responseData = data
                    break
                }
                // Se iTunes applica un rate-limit temporaneo (429/403/503), attende 650ms e riprova per non saltare alcuna app
                if (code == 429 || code == 403 || code >= 500) && attempt == 0 {
                    try? await Task.sleep(nanoseconds: 650_000_000)
                    continue
                }
                break
            } else if attempt == 0 {
                try? await Task.sleep(nanoseconds: 450_000_000)
            }
        }

        guard let data = responseData,
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

    func appendAdditionalApps(_ extraApps: [InstalledAppRecord]) {
        guard !extraApps.isEmpty else { return }
        if apps.isEmpty {
            configure(with: extraApps)
            return
        }
        let merged = DirectSwitchTransportViewModel.mergeUniqueApps(apps, extraApps)
        guard merged.count > apps.count else { return }
        apps = merged
        refreshInstalledStatuses()
        for item in merged where !alreadyInstalledIds.contains(item.id) && !completedIds.contains(item.id) {
            selectedIds.insert(item.id)
        }
        guard !dryRunPresentationForTesting else { return }
        isEnrichingMetadata = true
        Task {
            let enriched = await iOSAppStoreCatalogResolver.enrichAppsWithStoreMetadata(merged)
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

// MARK: - Stabilizzatore Multi-Fotogramma e Scanner Fotocamera Live 4K Macro (Zero Registrazione Schermo, Zero App Inventate)

/// Stabilizza le etichette lette in tempo reale dalla fotocamera puntando lo schermo del vecchio telefono:
/// richiede SEMPRE almeno 2 fotogrammi nitidi coerenti (~0.28s) prima di confermare qualsiasi app,
/// eliminando al 100% gli errori da sfocatura durante lo scorrimento delle pagine.
struct LiveCameraCandidateStabilizer: Sendable {
    private var sightingsByKey: [String: Int] = [:]
    private var emittedKeys: Set<String> = []
    var requiredFramesCount: Int = 2

    mutating func reset() {
        sightingsByKey.removeAll()
        emittedKeys.removeAll()
    }

    mutating func allowRetry(forRawCandidates rawCandidates: [String]) {
        for raw in rawCandidates {
            let key = iOSInstalledAppsScanner.canonicalAppQuery(for: raw).lowercased()
            emittedKeys.remove(key)
            sightingsByKey[key] = 1
        }
    }

    mutating func ingestFrameLines(_ rawFrameLines: [String]) -> [String] {
        let parsedInFrame = iOSInstalledAppsScanner.parsePlausibleAppCandidates(rawFrameLines)
        guard !parsedInFrame.isEmpty else { return [] }

        var newlyStabilized: [String] = []
        let threshold = max(1, requiredFramesCount)

        for cand in parsedInFrame {
            let key = iOSInstalledAppsScanner.canonicalAppQuery(for: cand.cleaned).lowercased()
            guard !emittedKeys.contains(key) else { continue }

            let nextCount = (sightingsByKey[key] ?? 0) + 1
            sightingsByKey[key] = nextCount

            if nextCount >= threshold {
                emittedKeys.insert(key)
                newlyStabilized.append(cand.wasTruncated ? "\(cand.cleaned)…" : cand.cleaned)
            }
        }
        return newlyStabilized
    }
}

private final class CameraFrameVisionWorker: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    let sampleQueue = DispatchQueue(label: "com.directswitch.livecamera.vision", qos: .userInitiated)
    private var lastAnalyzedTimestamp: CFAbsoluteTime = 0
    private var stabilizer = LiveCameraCandidateStabilizer()
    private let onNewStabilizedCandidates: @Sendable ([String]) -> Void

    init(onNewStabilizedCandidates: @escaping @Sendable ([String]) -> Void) {
        self.onNewStabilizedCandidates = onNewStabilizedCandidates
        super.init()
    }

    func resetState() {
        sampleQueue.async { [weak self] in
            self?.lastAnalyzedTimestamp = 0
            self?.stabilizer.reset()
        }
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        let now = CFAbsoluteTimeGetCurrent()
        guard now - lastAnalyzedTimestamp >= 0.27 else { return }
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        lastAnalyzedTimestamp = now

        var recognizedLines: [String] = []
        autoreleasepool {
            recognizedLines = iOSInstalledAppsScanner.recognizeSpatialCameraFrameLines(
                in: pixelBuffer,
                orientation: .right,
                minConfidence: 0.56
            )
        }

        guard !recognizedLines.isEmpty else { return }
        let readyBatch = stabilizer.ingestFrameLines(recognizedLines)
        if !readyBatch.isEmpty {
            onNewStabilizedCandidates(readyBatch)
        }
    }
}

/// Gestisce la sessione `AVCaptureSession` 4K con autofocus Macro automatico (`builtInTripleCamera` / `builtInDualWideCamera`)
/// per leggere nitidamente il 100% delle app sfogliate in «Libreria app (A–Z)» o sulla schermata Home del vecchio telefono.
@MainActor
final class LiveCameraAppScannerViewModel: NSObject, ObservableObject {
    @Published var discoveredApps: [InstalledAppRecord] = []
    @Published var newlyScannedCount: Int = 0
    @Published var latestDetectedAppName: String? = nil
    @Published var isCameraRunning: Bool = false
    @Published var isCameraPermissionDenied: Bool = false
    @Published var pendingLookupsCount: Int = 0

    var onLiveAppsChanged: (([InstalledAppRecord]) -> Void)? = nil

    let captureSession = AVCaptureSession()
    private var initialSeedApps: [InstalledAppRecord] = []
    private var isConfigured = false
    private var worker: CameraFrameVisionWorker? = nil
    private let haptic = UIImpactFeedbackGenerator(style: .light)

    func bootstrap(seedApps: [InstalledAppRecord]) {
        var unique: [InstalledAppRecord] = []
        for item in seedApps {
            let exists = unique.contains {
                $0.packageName.caseInsensitiveCompare(item.packageName) == .orderedSame
                    || ($0.appStoreId != nil && $0.appStoreId == item.appStoreId)
            }
            if !exists {
                unique.append(item)
            }
        }
        initialSeedApps = unique
        discoveredApps = unique
        newlyScannedCount = 0
        latestDetectedAppName = nil
        haptic.prepare()

        Task {
            let enriched = await iOSAppStoreCatalogResolver.enrichAppsWithStoreMetadata(unique)
            if !enriched.isEmpty {
                for rich in enriched {
                    if let idx = self.discoveredApps.firstIndex(where: {
                        $0.packageName.caseInsensitiveCompare(rich.packageName) == .orderedSame
                            || ($0.appStoreId != nil && $0.appStoreId == rich.appStoreId)
                    }) {
                        self.discoveredApps[idx] = rich
                    }
                }
            }
        }
    }

    func resetToSeedApps() {
        worker?.resetState()
        discoveredApps = initialSeedApps
        newlyScannedCount = 0
        latestDetectedAppName = nil
        onLiveAppsChanged?(discoveredApps)
    }

    func startScanning() {
        Task {
            let status = AVCaptureDevice.authorizationStatus(for: .video)
            let granted: Bool
            switch status {
            case .authorized:
                granted = true
            case .notDetermined:
                granted = await AVCaptureDevice.requestAccess(for: .video)
            default:
                granted = false
            }

            guard granted else {
                self.isCameraPermissionDenied = true
                return
            }
            self.isCameraPermissionDenied = false
            self.configureSessionIfNeededAndStart()
        }
    }

    func stopScanning() {
        let sessionRef = captureSession
        isCameraRunning = false
        DispatchQueue.global(qos: .utility).async {
            if sessionRef.isRunning {
                sessionRef.stopRunning()
            }
        }
    }

    func removeApp(_ app: InstalledAppRecord) {
        discoveredApps.removeAll { $0.id == app.id }
        onLiveAppsChanged?(discoveredApps)
    }

    private static func bestMacroCapableBackCamera() -> AVCaptureDevice? {
        let preferredTypes: [AVCaptureDevice.DeviceType] = [
            .builtInTripleCamera,
            .builtInDualWideCamera,
            .builtInDualCamera,
            .builtInWideAngleCamera
        ]
        for type in preferredTypes {
            if let dev = AVCaptureDevice.default(type, for: .video, position: .back) {
                return dev
            }
        }
        return AVCaptureDevice.default(for: .video)
    }

    private func configureSessionIfNeededAndStart() {
        if !isConfigured {
            let visionWorker = CameraFrameVisionWorker { [weak self] candidates in
                Task { @MainActor [weak self] in
                    self?.resolveIncomingCandidates(candidates)
                }
            }
            self.worker = visionWorker

            captureSession.beginConfiguration()

            // Aggiunge prima l'input fotocamera virtuale (così può abilitare sia il Macro ravvicinato automatico sia il 4K nitido)
            if let device = Self.bestMacroCapableBackCamera() {
                if (try? device.lockForConfiguration()) != nil {
                    if device.isFocusModeSupported(.continuousAutoFocus) {
                        device.focusMode = .continuousAutoFocus
                    }
                    if device.isAutoFocusRangeRestrictionSupported {
                        device.autoFocusRangeRestriction = .near
                    }
                    if device.isExposureModeSupported(.continuousAutoExposure) {
                        device.exposureMode = .continuousAutoExposure
                    }
                    if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
                        device.whiteBalanceMode = .continuousAutoWhiteBalance
                    }
                    device.unlockForConfiguration()
                }
                if let input = try? AVCaptureDeviceInput(device: device),
                   captureSession.canAddInput(input) {
                    captureSession.addInput(input)
                }
            }

            if captureSession.canSetSessionPreset(.hd4K3840x2160) {
                captureSession.sessionPreset = .hd4K3840x2160
            } else if captureSession.canSetSessionPreset(.hd1920x1080) {
                captureSession.sessionPreset = .hd1920x1080
            } else {
                captureSession.sessionPreset = .high
            }

            let videoOutput = AVCaptureVideoDataOutput()
            videoOutput.alwaysDiscardsLateVideoFrames = true
            videoOutput.setSampleBufferDelegate(visionWorker, queue: visionWorker.sampleQueue)
            if captureSession.canAddOutput(videoOutput) {
                captureSession.addOutput(videoOutput)
            }
            captureSession.commitConfiguration()
            isConfigured = true
        } else {
            worker?.resetState()
        }

        let sessionRef = captureSession
        isCameraRunning = true
        DispatchQueue.global(qos: .userInitiated).async {
            if !sessionRef.isRunning {
                sessionRef.startRunning()
            }
        }
    }

    private func resolveIncomingCandidates(_ candidates: [String]) {
        guard !candidates.isEmpty else { return }
        pendingLookupsCount += candidates.count

        Task {
            let resolved = await iOSInstalledAppsScanner.resolveCandidateAppLines(candidates)
            self.pendingLookupsCount = max(0, self.pendingLookupsCount - candidates.count)
            guard !resolved.isEmpty else { return }

            var addedAny = false
            for app in resolved {
                let exists = self.discoveredApps.contains {
                    $0.packageName.caseInsensitiveCompare(app.packageName) == .orderedSame
                        || ($0.appStoreId != nil && $0.appStoreId == app.appStoreId)
                }
                if !exists {
                    self.discoveredApps.append(app)
                    self.newlyScannedCount += 1
                    self.latestDetectedAppName = app.appName
                    addedAny = true
                }
            }

            if addedAny {
                self.haptic.impactOccurred()
                self.onLiveAppsChanged?(self.discoveredApps)
            }
        }
    }
}
