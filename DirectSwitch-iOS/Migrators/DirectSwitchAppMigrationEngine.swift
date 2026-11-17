//
//  DirectSwitchAppMigrationEngine.swift
//  DirectSwitch-iOS
//
//  Created by Nicolas Donati.
//  Copyright © 2026 Nicolas Donati. Tutti i diritti riservati.
//

import AVFoundation
import Foundation
import ImageIO
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

/// Risultato verificato da App Store con nome sviluppatore per disambiguare omonimie in fase di ricerca manuale.
struct AppStoreSearchHit: Identifiable, Sendable {
    let record: InstalledAppRecord
    let developerName: String?

    var id: String { record.id }
}

/// Risultato dell'importazione deterministica da Resoconto sulla privacy delle app Apple (`.ndjson`).
struct AppPrivacyReportImportResult: Sendable {
    let apps: [InstalledAppRecord]
    let rawBundleIdsCount: Int
}

/// Categoria curata per la selezione rapida a 1 tocco (zero attese e zero scansione fotocamera).
struct AppQuickCategory: Identifiable, Sendable {
    let id: String
    let title: String
    let iconName: String
    var isGoogleAndroidPreinstalledCategory: Bool = false
    let apps: [InstalledAppRecord]
}

/// Scanner deterministico delle app installate sull'iPhone mittente:
/// 1) 48 schemi verificati (`knownProbes` + WhatsApp + CloudSave = limite massimo 50 consentito da iOS)
/// 2) Rilevamento automatico gratuito da Album Foto e metadati media (`iOSPhotoMetadataAppDetector`)
/// 3) Catalogo curato per categorie italiane a 1 tocco e ricerca ufficiale App Store
enum iOSInstalledAppsScanner {
    private static let legacyCustomAppsStorageKey = "directswitch_custom_sender_apps_v1"
    private static let legacyCustomAppsStorageKeyV2 = "directswitch_verified_sender_apps_v2"
    private static let customAppsStorageKey = "directswitch_verified_sender_apps_v3"

    static let androidPreinstalledGoogleBundleIds: Set<String> = [
        "com.google.ios.youtube",
        "com.google.gmail",
        "com.google.maps",
        "com.google.chrome.ios",
        "com.google.drive",
        "com.google.photos",
        "com.google.googlemobile",
        "com.google.calendar"
    ]

    static func isGoogleAppPreinstalledOnAndroid(_ app: InstalledAppRecord) -> Bool {
        androidPreinstalledGoogleBundleIds.contains(app.packageName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
    }

    /// Tutti gli schemi univoci dichiarati in `Info.plist` (`<= 50` incluso `whatsapp` e `com.cloudsave.ios`).
    /// Gli slot precedentemente usati dalle app Google già preinstallate su Android (YouTube, Gmail, Maps, Chrome, Drive, Foto, Google)
    /// sono ora dedicati a CieID, Booking.com, Temu, SHEIN, Trenitalia, Telepass e Strava.
    static let knownProbes: [iOSKnownAppProbe] = [
        iOSKnownAppProbe(bundleId: "net.whatsapp.WhatsApp", appName: "WhatsApp Messenger", urlScheme: "whatsapp-consumer", appStoreId: 310633997),
        iOSKnownAppProbe(bundleId: "net.whatsapp.WhatsAppSMB", appName: "WhatsApp Business", urlScheme: "whatsapp-smb", appStoreId: 1386412985),
        iOSKnownAppProbe(bundleId: "com.burbn.instagram", appName: "Instagram", urlScheme: "instagram", appStoreId: 389801252),
        iOSKnownAppProbe(bundleId: "ph.telegra.Telegraph", appName: "Telegram Messenger", urlScheme: "tg", appStoreId: 686449807),
        iOSKnownAppProbe(bundleId: "com.facebook.Facebook", appName: "Facebook", urlScheme: "fb", appStoreId: 284882215),
        iOSKnownAppProbe(bundleId: "com.facebook.Messenger", appName: "Messenger", urlScheme: "fb-messenger", appStoreId: 454638411),
        iOSKnownAppProbe(bundleId: "com.zhiliaoapp.musically", appName: "TikTok", urlScheme: "tiktok", appStoreId: 835599320),
        iOSKnownAppProbe(bundleId: "it.ipzs.cieID", appName: "CieID", urlScheme: "cieid", appStoreId: 1504644677),
        iOSKnownAppProbe(bundleId: "com.booking.BookingApp", appName: "Booking.com", urlScheme: "booking", appStoreId: 367003839),
        iOSKnownAppProbe(bundleId: "com.einnovation.temu", appName: "Temu", urlScheme: "temu", appStoreId: 1641486558),
        iOSKnownAppProbe(bundleId: "zzkko.com.ZZKKO", appName: "SHEIN", urlScheme: "shein", appStoreId: 878577184),
        iOSKnownAppProbe(bundleId: "com.promptu.ProntoTreno", appName: "Trenitalia", urlScheme: "trenitalia", appStoreId: 331050847),
        iOSKnownAppProbe(bundleId: "it.telepass", appName: "Telepass", urlScheme: "telepass", appStoreId: 454224356),
        iOSKnownAppProbe(bundleId: "com.strava.stravaride", appName: "Strava", urlScheme: "strava", appStoreId: 426826309),
        iOSKnownAppProbe(bundleId: "com.google.Authenticator", appName: "Google Authenticator", urlScheme: "googleauthenticator", appStoreId: 388497605),
        iOSKnownAppProbe(bundleId: "com.spotify.client", appName: "Spotify", urlScheme: "spotify", appStoreId: 324684580),
        iOSKnownAppProbe(bundleId: "com.netflix.Netflix", appName: "Netflix", urlScheme: "nflx", appStoreId: 363590051),
        iOSKnownAppProbe(bundleId: "com.amazon.aiv.AIVApp", appName: "Amazon Prime Video", urlScheme: "aiv", appStoreId: 545519333),
        iOSKnownAppProbe(bundleId: "com.disney.disneyplus", appName: "Disney+", urlScheme: "disneyplus", appStoreId: 1446075923),
        iOSKnownAppProbe(bundleId: "com.dazn.theApp", appName: "DAZN", urlScheme: "dazn", appStoreId: 1129523589),
        iOSKnownAppProbe(bundleId: "com.amazon.AmazonIT", appName: "Amazon Shopping", urlScheme: "com.amazon.mobile.shopping", appStoreId: 297606951),
        iOSKnownAppProbe(bundleId: "com.yourcompany.PPClient", appName: "PayPal", urlScheme: "paypal", appStoreId: 283646709),
        iOSKnownAppProbe(bundleId: "com.revolut.revolut", appName: "Revolut", urlScheme: "revolut", appStoreId: 932493382),
        iOSKnownAppProbe(bundleId: "com.satispay.customer.p2p", appName: "Satispay", urlScheme: "satispay", appStoreId: 790287076),
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
        iOSKnownAppProbe(bundleId: "com.subito.subito", appName: "Subito", urlScheme: "subito", appStoreId: 450775137),
        iOSKnownAppProbe(bundleId: "lt.manodrabuziai.fr", appName: "Vinted", urlScheme: "vinted", appStoreId: 632064380),
        iOSKnownAppProbe(bundleId: "com.airbnb.app", appName: "Airbnb", urlScheme: "airbnb", appStoreId: 401626263),
        iOSKnownAppProbe(bundleId: "com.openai.chat", appName: "ChatGPT", urlScheme: "chatgpt", appStoreId: 6448311069),
        iOSKnownAppProbe(bundleId: "com.shazam.Shazam", appName: "Shazam", urlScheme: "shazam", appStoreId: 284993459),
        iOSKnownAppProbe(bundleId: "com.canva.canvaeditor", appName: "Canva", urlScheme: "canva", appStoreId: 897446215),
        iOSKnownAppProbe(bundleId: "com.ebay.iphone", appName: "eBay", urlScheme: "ebay", appStoreId: 282614216),
        iOSKnownAppProbe(bundleId: "it.pagopa.app.io", appName: "IO", urlScheme: "ioit", appStoreId: 1501681835),
        iOSKnownAppProbe(bundleId: "it.poste.postebuy2", appName: "PosteID", urlScheme: "posteid", appStoreId: 649492675),
        iOSKnownAppProbe(bundleId: "com.getdropbox.Dropbox", appName: "Dropbox", urlScheme: "dbapi-2", appStoreId: 327630330),
        iOSKnownAppProbe(bundleId: "com.tinyspeck.chatlyio", appName: "Slack", urlScheme: "slack", appStoreId: 618783545)
    ]

    /// Categorie curate italiane ed europee con Bundle ID e App Store ID verificati su App Store Italia,
    /// selezionabili con 1 tocco in `SenderAppsSelectionSheet` (zero attese e zero fotocamera).
    static let curatedCategories: [AppQuickCategory] = [
        AppQuickCategory(
            id: "banks_payments",
            title: "Banche & Pagamenti",
            iconName: "building.columns.fill",
            apps: [
                InstalledAppRecord(packageName: "com.intesasanpaolo.ibiphone", appName: "Intesa Sanpaolo Mobile", appStoreId: 597360475, detectionSource: "Categoria Banche"),
                InstalledAppRecord(packageName: "com.internet.unicredit.iphoneapp", appName: "UniCredit Mobile Banking", appStoreId: 396670008, detectionSource: "Categoria Banche"),
                InstalledAppRecord(packageName: "it.poste.spim", appName: "Poste Italiane", appStoreId: 781421802, detectionSource: "Categoria Banche"),
                InstalledAppRecord(packageName: "com.intesasanpaolo.isybank.mobile", appName: "Isybank", appStoreId: 1666218772, detectionSource: "Categoria Banche"),
                InstalledAppRecord(packageName: "com.fineco.fineco", appName: "Fineco", appStoreId: 405225581, detectionSource: "Categoria Banche"),
                InstalledAppRecord(packageName: "com.bbva.italy", appName: "BBVA Italia", appStoreId: 1536949050, detectionSource: "Categoria Banche"),
                InstalledAppRecord(packageName: "it.bper.mobilebanking", appName: "BPER Banca", appStoreId: 554965344, detectionSource: "Categoria Banche"),
                InstalledAppRecord(packageName: "it.bancamediolanum.imedfullclient", appName: "Banca Mediolanum", appStoreId: 412610547, detectionSource: "Categoria Banche"),
                InstalledAppRecord(packageName: "it.caitalia.apphub", appName: "Crédit Agricole Italia", appStoreId: 1502700297, detectionSource: "Categoria Banche"),
                InstalledAppRecord(packageName: "com.hype.it", appName: "HYPE", appStoreId: 943405905, detectionSource: "Categoria Banche"),
                InstalledAppRecord(packageName: "it.cartasi.mobile.iPhone", appName: "Nexi Pay", appStoreId: 518695175, detectionSource: "Categoria Banche"),
                InstalledAppRecord(packageName: "it.bancomat.pay.user", appName: "BANCOMAT", appStoreId: 1467760256, detectionSource: "Categoria Banche"),
                InstalledAppRecord(packageName: "com.revolut.revolut", appName: "Revolut", appStoreId: 932493382, urlScheme: "revolut", detectionSource: "Categoria Banche"),
                InstalledAppRecord(packageName: "com.satispay.customer.p2p", appName: "Satispay", appStoreId: 790287076, urlScheme: "satispay", detectionSource: "Categoria Banche"),
                InstalledAppRecord(packageName: "com.yourcompany.PPClient", appName: "PayPal", appStoreId: 283646709, urlScheme: "paypal", detectionSource: "Categoria Banche")
            ]
        ),
        AppQuickCategory(
            id: "spid_office",
            title: "SPID, CIE & Ufficio",
            iconName: "person.text.rectangle.fill",
            apps: [
                InstalledAppRecord(packageName: "it.pagopa.app.io", appName: "IO", appStoreId: 1501681835, urlScheme: "ioit", detectionSource: "Categoria SPID/PA"),
                InstalledAppRecord(packageName: "it.ipzs.cieID", appName: "CieID", appStoreId: 1504644677, urlScheme: "cieid", detectionSource: "Categoria SPID/PA"),
                InstalledAppRecord(packageName: "it.poste.postebuy2", appName: "PosteID", appStoreId: 649492675, urlScheme: "posteid", detectionSource: "Categoria SPID/PA"),
                InstalledAppRecord(packageName: "it.aruba.mobilepec", appName: "Aruba PEC", appStoreId: 973510245, detectionSource: "Categoria SPID/PA"),
                InstalledAppRecord(packageName: "com.adobe.scan.ios", appName: "Adobe Scan", appStoreId: 1199564834, detectionSource: "Categoria SPID/PA"),
                InstalledAppRecord(packageName: "com.intsig.CamScanner", appName: "CamScanner", appStoreId: 388624839, detectionSource: "Categoria SPID/PA"),
                InstalledAppRecord(packageName: "com.microsoft.Office.Word", appName: "Microsoft Word", appStoreId: 586447913, detectionSource: "Categoria Ufficio"),
                InstalledAppRecord(packageName: "com.microsoft.Office.Excel", appName: "Microsoft Excel", appStoreId: 586683407, detectionSource: "Categoria Ufficio"),
                InstalledAppRecord(packageName: "com.microsoft.skydrive", appName: "Microsoft OneDrive", appStoreId: 477537958, detectionSource: "Categoria Ufficio")
            ]
        ),
        AppQuickCategory(
            id: "transport_travel",
            title: "Trasporti & Viaggi",
            iconName: "tram.fill",
            apps: [
                InstalledAppRecord(packageName: "com.promptu.ProntoTreno", appName: "Trenitalia", appStoreId: 331050847, urlScheme: "trenitalia", detectionSource: "Categoria Trasporti"),
                InstalledAppRecord(packageName: "com.accenture.ntvapp", appName: "Italo Treno", appStoreId: 804056898, detectionSource: "Categoria Trasporti"),
                InstalledAppRecord(packageName: "it.telepass", appName: "Telepass", appStoreId: 454224356, urlScheme: "telepass", detectionSource: "Categoria Trasporti"),
                InstalledAppRecord(packageName: "net.pluservice.myCicero", appName: "MooneyGo", appStoreId: 595700208, detectionSource: "Categoria Trasporti"),
                InstalledAppRecord(packageName: "net.easypark.app", appName: "EasyPark", appStoreId: 449594317, detectionSource: "Categoria Trasporti"),
                InstalledAppRecord(packageName: "com.ryanair.cheapflights", appName: "Ryanair", appStoreId: 504270602, detectionSource: "Categoria Viaggi"),
                InstalledAppRecord(packageName: "com.booking.BookingApp", appName: "Booking.com", appStoreId: 367003839, urlScheme: "booking", detectionSource: "Categoria Viaggi"),
                InstalledAppRecord(packageName: "com.airbnb.app", appName: "Airbnb", appStoreId: 401626263, urlScheme: "airbnb", detectionSource: "Categoria Viaggi"),
                InstalledAppRecord(packageName: "com.ubercab.UberClient", appName: "Uber", appStoreId: 368677368, urlScheme: "uber", detectionSource: "Categoria Trasporti"),
                InstalledAppRecord(packageName: "com.waze.iphone", appName: "Waze", appStoreId: 323229106, urlScheme: "waze", detectionSource: "Categoria Trasporti")
            ]
        ),
        AppQuickCategory(
            id: "shopping_food",
            title: "Shopping & Cibo",
            iconName: "bag.fill",
            apps: [
                InstalledAppRecord(packageName: "com.amazon.AmazonIT", appName: "Amazon Shopping", appStoreId: 297606951, urlScheme: "com.amazon.mobile.shopping", detectionSource: "Categoria Shopping"),
                InstalledAppRecord(packageName: "com.glovo.glovo", appName: "Glovo", appStoreId: 951812684, detectionSource: "Categoria Cibo"),
                InstalledAppRecord(packageName: "com.deliveroo.orderapp", appName: "Deliveroo", appStoreId: 1001501844, detectionSource: "Categoria Cibo"),
                InstalledAppRecord(packageName: "com.justeat.JUSTEAT", appName: "Just Eat", appStoreId: 566347057, detectionSource: "Categoria Cibo"),
                InstalledAppRecord(packageName: "com.einnovation.temu", appName: "Temu", appStoreId: 1641486558, urlScheme: "temu", detectionSource: "Categoria Shopping"),
                InstalledAppRecord(packageName: "zzkko.com.ZZKKO", appName: "SHEIN", appStoreId: 878577184, urlScheme: "shein", detectionSource: "Categoria Shopping"),
                InstalledAppRecord(packageName: "com.subito.subito", appName: "Subito", appStoreId: 450775137, urlScheme: "subito", detectionSource: "Categoria Shopping"),
                InstalledAppRecord(packageName: "lt.manodrabuziai.fr", appName: "Vinted", appStoreId: 632064380, urlScheme: "vinted", detectionSource: "Categoria Shopping"),
                InstalledAppRecord(packageName: "com.ebay.iphone", appName: "eBay", appStoreId: 282614216, urlScheme: "ebay", detectionSource: "Categoria Shopping")
            ]
        ),
        AppQuickCategory(
            id: "photo_video_sport",
            title: "Foto, Video & Sport",
            iconName: "camera.aperture",
            apps: [
                InstalledAppRecord(packageName: "com.lemon.lvoverseas", appName: "CapCut", appStoreId: 1500855883, detectionSource: "Categoria Foto & Video"),
                InstalledAppRecord(packageName: "com.camerasideas.InstaShot", appName: "InShot", appStoreId: 997362197, detectionSource: "Categoria Foto & Video"),
                InstalledAppRecord(packageName: "com.adobe.lrmobilephone", appName: "Lightroom", appStoreId: 878783582, detectionSource: "Categoria Foto & Video"),
                InstalledAppRecord(packageName: "com.niksoftware.snapseedforipad", appName: "Snapseed", appStoreId: 439438619, detectionSource: "Categoria Foto & Video"),
                InstalledAppRecord(packageName: "com.picsart.studio", appName: "Picsart", appStoreId: 587366035, detectionSource: "Categoria Foto & Video"),
                InstalledAppRecord(packageName: "co.visualsupply.cam", appName: "VSCO", appStoreId: 588013838, detectionSource: "Categoria Foto & Video"),
                InstalledAppRecord(packageName: "com.bigwinepot.nwdn.international", appName: "Remini", appStoreId: 1470373330, detectionSource: "Categoria Foto & Video"),
                InstalledAppRecord(packageName: "com.lightricks.Facetune2", appName: "Facetune", appStoreId: 1149994032, detectionSource: "Categoria Foto & Video"),
                InstalledAppRecord(packageName: "com.dr1ven.eraser", appName: "Photoroom", appStoreId: 1455009060, detectionSource: "Categoria Foto & Video"),
                InstalledAppRecord(packageName: "com.frontrow.vlog", appName: "VN Video Editor", appStoreId: 1343581380, detectionSource: "Categoria Foto & Video"),
                InstalledAppRecord(packageName: "com.strava.stravaride", appName: "Strava", appStoreId: 426826309, urlScheme: "strava", detectionSource: "Categoria Sport"),
                InstalledAppRecord(packageName: "com.garmin.connect.mobile", appName: "Garmin Connect", appStoreId: 583446403, detectionSource: "Categoria Sport"),
                InstalledAppRecord(packageName: "com.gopro.GoPro", appName: "GoPro Quik", appStoreId: 561350520, detectionSource: "Categoria Foto & Video"),
                InstalledAppRecord(packageName: "com.dji.golite", appName: "DJI Fly", appStoreId: 1479649251, detectionSource: "Categoria Foto & Video")
            ]
        ),
        AppQuickCategory(
            id: "operators_home",
            title: "Operatori, Utenze & Casa",
            iconName: "house.fill",
            apps: [
                InstalledAppRecord(packageName: "it.telecomitalia.119SelfService", appName: "MyTIM", appStoreId: 378783815, detectionSource: "Categoria Operatori"),
                InstalledAppRecord(packageName: "com.vodafone.my190", appName: "My Vodafone", appStoreId: 365804068, detectionSource: "Categoria Operatori"),
                InstalledAppRecord(packageName: "it.wind.mywind", appName: "WINDTRE", appStoreId: 492519547, detectionSource: "Categoria Operatori"),
                InstalledAppRecord(packageName: "com.enel.energia", appName: "Enel Energia", appStoreId: 767368903, detectionSource: "Categoria Utenze"),
                InstalledAppRecord(packageName: "com.eni.EniAutoletturaGas", appName: "Eni Plenitude", appStoreId: 454695340, detectionSource: "Categoria Utenze"),
                InstalledAppRecord(packageName: "com.tplink.tapo", appName: "TP-Link Tapo", appStoreId: 1472718009, detectionSource: "Categoria Casa"),
                InstalledAppRecord(packageName: "com.hikvision.ezviz", appName: "EZVIZ", appStoreId: 886947564, detectionSource: "Categoria Casa"),
                InstalledAppRecord(packageName: "cloud.shelly.app", appName: "Shelly Smart Control", appStoreId: 1660045967, detectionSource: "Categoria Casa")
            ]
        ),
        AppQuickCategory(
            id: "streaming_ai_tools",
            title: "Streaming, TV, AI & Sicurezza",
            iconName: "tv.fill",
            apps: [
                InstalledAppRecord(packageName: "it.rainet.ipad.raitv", appName: "RaiPlay", appStoreId: 501323740, detectionSource: "Categoria Streaming"),
                InstalledAppRecord(packageName: "it.mediaset.video.iphone", appName: "Mediaset Infinity", appStoreId: 412625083, detectionSource: "Categoria Streaming"),
                InstalledAppRecord(packageName: "it.sky.skygoitalia", appName: "Sky Go", appStoreId: 454435005, detectionSource: "Categoria Streaming"),
                InstalledAppRecord(packageName: "com.nowtv.it", appName: "NOW", appStoreId: 1377753603, detectionSource: "Categoria Streaming"),
                InstalledAppRecord(packageName: "com.google.gemini", appName: "Google Gemini", appStoreId: 6477489729, detectionSource: "Categoria AI"),
                InstalledAppRecord(packageName: "com.anthropic.claude", appName: "Claude", appStoreId: 6473753684, detectionSource: "Categoria AI"),
                InstalledAppRecord(packageName: "ai.perplexity.app", appName: "Perplexity", appStoreId: 1668000334, detectionSource: "Categoria AI"),
                InstalledAppRecord(packageName: "com.nordvpn.NordVPN", appName: "NordVPN", appStoreId: 905953485, detectionSource: "Categoria Sicurezza"),
                InstalledAppRecord(packageName: "ch.protonmail.protonmail", appName: "Proton Mail", appStoreId: 979659905, detectionSource: "Categoria Sicurezza"),
                InstalledAppRecord(packageName: "com.duolingo.DuolingoMobile", appName: "Duolingo", appStoreId: 570060128, detectionSource: "Categoria Studio"),
                InstalledAppRecord(packageName: "org.whispersystems.signal", appName: "Signal", appStoreId: 874139669, detectionSource: "Categoria Messaggi"),
                InstalledAppRecord(packageName: "com.viber", appName: "Viber", appStoreId: 382617920, detectionSource: "Categoria Messaggi")
            ]
        ),
        AppQuickCategory(
            id: "google_essentials",
            title: "Google (solo per iPhone)",
            iconName: "g.circle.fill",
            isGoogleAndroidPreinstalledCategory: true,
            apps: [
                InstalledAppRecord(packageName: "com.google.ios.youtube", appName: "YouTube", appStoreId: 544007664, detectionSource: "Categoria Google"),
                InstalledAppRecord(packageName: "com.google.Gmail", appName: "Gmail", appStoreId: 422689480, detectionSource: "Categoria Google"),
                InstalledAppRecord(packageName: "com.google.Maps", appName: "Google Maps", appStoreId: 585027354, detectionSource: "Categoria Google"),
                InstalledAppRecord(packageName: "com.google.chrome.ios", appName: "Google Chrome", appStoreId: 535886823, detectionSource: "Categoria Google"),
                InstalledAppRecord(packageName: "com.google.Drive", appName: "Google Drive", appStoreId: 507874739, detectionSource: "Categoria Google"),
                InstalledAppRecord(packageName: "com.google.photos", appName: "Google Foto", appStoreId: 962194608, detectionSource: "Categoria Google"),
                InstalledAppRecord(packageName: "com.google.GoogleMobile", appName: "Google", appStoreId: 284815942, detectionSource: "Categoria Google"),
                InstalledAppRecord(packageName: "com.google.calendar", appName: "Google Calendar", appStoreId: 909319292, detectionSource: "Categoria Google")
            ]
        )
    ]

    /// Suggerimenti rapidi italiani derivati senza duplicazioni dalle categorie curate.
    static var italianQuickSuggestions: [InstalledAppRecord] {
        curatedCategories
            .filter { !$0.isGoogleAndroidPreinstalledCategory }
            .flatMap(\.apps)
    }

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
        "aruba otp": "Aruba OTP",
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
        "now": "NOW",
        "mytim": "MyTIM",
        "my vodafone": "My Vodafone",
        "myfastweb": "MyFastweb",
        "windtre": "WINDTRE",
        "very": "Very Mobile",
        "kena": "Kena Mobile",
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
        "flixbus": "FlixBus",
        "blablacar": "BlaBlaCar",
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
        "deepseek": "DeepSeek",
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
        "poste italia": "Poste Italiane",
        "banca genera": "Banca Generali",
        "ing italia": "ING Italia",
        "sumup": "SumUp",
        "now tv": "NOW"
    ]

    /// Ripulisce un'etichetta letta dalla schermata Home / Libreria App (rimuovendo l'ellissi `…` o `...` e simboli/badge iniziali come `• `).
    static func cleanHomeScreenAppLabel(_ raw: String) -> (cleaned: String, wasTruncated: Bool) {
        var working = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "•›<>-–—_·:|«»\"?~*=,;()"))
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Rimuove eventuali simboli di notifica / download / TestFlight all'inizio dell'etichetta (es. "○ TestApp", "☁️ App", "● App")
        while let first = working.unicodeScalars.first,
              ["☁", "⬇", "↓", "●", "○", "◉", "🔸", "🔹", "•"].contains(String(first)) {
            working = String(working.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
        }

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

    /// Restituisce esclusivamente le app rilevate con certezza matematica sul dispositivo tramite i 50 schemi registrati.
    @MainActor
    static func scanLocallyInstalledProbesOnly() -> [InstalledAppRecord] {
        var detected: [InstalledAppRecord] = []
        for probe in knownProbes {
            let isInstalled: Bool
            if probe.bundleId == "net.whatsapp.WhatsApp" {
                isInstalled = isPersonalWhatsAppInstalled()
            } else {
                isInstalled = canOpenScheme(probe.urlScheme)
            }
            if isInstalled {
                detected.append(
                    InstalledAppRecord(
                        packageName: probe.bundleId,
                        appName: probe.appName,
                        appStoreId: probe.appStoreId,
                        iconUrl: nil,
                        urlScheme: probe.urlScheme,
                        detectionSource: "Verificata su iPhone"
                    )
                )
            }
        }
        return detected
    }

    /// Scansione istantanea completa senza attese né fotocamera:
    /// 1) 48 schemi verificati (`canOpenURL`)
    /// 2) App già salvate da categorie / ricerca manuale
    /// 3) Indizi deterministici da Album Foto e prefissi file in libreria Foto (se il permesso Foto è già concesso)
    static func detectAllAppsInstantAsync() async -> (apps: [InstalledAppRecord], verifiedProbesCount: Int, photoDiscoveredCount: Int) {
        let probesOnly = await MainActor.run { scanLocallyInstalledProbesOnly() }
        let savedCustom = await MainActor.run { filterFalsePositiveProbesOnSender(loadSavedCustomApps()) }
        let photoCluesRaw = await Task.detached(priority: .userInitiated) {
            iOSPhotoMetadataAppDetector.scanAuthorizedPhotoLibraryClues()
        }.value
        let photoClues = await MainActor.run { filterFalsePositiveProbesOnSender(photoCluesRaw) }

        var merged = probesOnly
        var seenBundles = Set(merged.map { $0.packageName.lowercased() })
        var seenStoreIds = Set(merged.compactMap(\.appStoreId))
        var photoCount = 0

        for clue in photoClues {
            let bundleKey = clue.packageName.lowercased()
            if seenBundles.contains(bundleKey) { continue }
            if let sid = clue.appStoreId, seenStoreIds.contains(sid) { continue }
            seenBundles.insert(bundleKey)
            if let sid = clue.appStoreId { seenStoreIds.insert(sid) }
            merged.append(clue)
            photoCount += 1
        }

        for extra in savedCustom {
            let bundleKey = extra.packageName.lowercased()
            if seenBundles.contains(bundleKey) { continue }
            if let sid = extra.appStoreId, seenStoreIds.contains(sid) { continue }
            seenBundles.insert(bundleKey)
            if let sid = extra.appStoreId { seenStoreIds.insert(sid) }
            merged.append(extra)
        }

        return (merged, probesOnly.count, photoCount)
    }

    /// Rileva istantaneamente tutte le app verificabili tramite gli schemi `Info.plist`
    /// unendole alle eventuali app aggiunte da Foto, categorie rapide o ricerca App Store.
    @MainActor
    static func scanLocallyInstalledApps() -> [InstalledAppRecord] {
        var detected = scanLocallyInstalledProbesOnly()
        var seenBundles = Set(detected.map { $0.packageName.lowercased() })
        var seenStoreIds = Set(detected.compactMap(\.appStoreId))

        for extra in filterFalsePositiveProbesOnSender(loadSavedCustomApps()) {
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
        // Purga automaticamente le vecchie chiavi v1/v2 che potevano contenere app errate da OCR o vecchi matcher
        if UserDefaults.standard.object(forKey: legacyCustomAppsStorageKey) != nil {
            UserDefaults.standard.removeObject(forKey: legacyCustomAppsStorageKey)
        }
        if UserDefaults.standard.object(forKey: legacyCustomAppsStorageKeyV2) != nil {
            UserDefaults.standard.removeObject(forKey: legacyCustomAppsStorageKeyV2)
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
        UserDefaults.standard.removeObject(forKey: legacyCustomAppsStorageKeyV2)
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

    /// Verifica localmente ogni app coperta dai 50 schemi `Info.plist` (`knownProbes`), sia per `bundleId` sia per `appStoreId`
    /// o nome canonico: se `canOpenURL` sul dispositivo restituisce `false`, quell'app viene scartata senza falsi positivi.
    @MainActor
    static func filterFalsePositiveProbesOnSender(_ apps: [InstalledAppRecord]) -> [InstalledAppRecord] {
        return apps.filter { app in
            if let matchedProbe = knownProbes.first(where: {
                $0.bundleId.caseInsensitiveCompare(app.packageName) == .orderedSame
                    || (app.appStoreId != nil && $0.appStoreId == app.appStoreId)
                    || $0.appName.caseInsensitiveCompare(app.appName) == .orderedSame
            }) {
                if matchedProbe.bundleId == "net.whatsapp.WhatsApp" {
                    return isPersonalWhatsAppInstalled()
                }
                if matchedProbe.bundleId == "net.whatsapp.WhatsAppSMB" {
                    return isWhatsAppBusinessInstalled()
                }
                return canOpenScheme(matchedProbe.urlScheme)
            }
            return true
        }
    }

    private static let allowedUserFacingAppleBundleIds: Set<String> = [
        "com.apple.pages",
        "com.apple.keynote",
        "com.apple.numbers",
        "com.apple.imovie",
        "com.apple.garageband",
        "com.apple.clips",
        "com.apple.testflight",
        "com.apple.freeform",
        "com.apple.itunesu",
        "com.apple.swift-playgrounds"
    ]

    private static let extensionBundleSuffixes: [String] = [
        ".widget", ".widgets", ".widgetextension", ".notificationservice", ".notificationcontent",
        ".shareextension", ".share", ".intents", ".intentsextension", ".siriextension",
        ".keyboard", ".spotlight", ".quicklook", ".fileprovider", ".watchkitapp", ".watchkitextension",
        ".nse", ".appex", ".pluginkit"
    ]

    /// Riconosce file esportati da Impostazioni iPhone → Privacy e sicurezza → Resoconto sulla privacy delle app (`.ndjson`).
    static func isAppPrivacyReportFile(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        let name = url.lastPathComponent.lowercased()
        return ext == "ndjson" || name.contains("app_privacy_report") || name.contains("privacy_report")
    }

    /// Estrae gli esatti `bundleID` delle app dal testo NDJSON ufficiale del Resoconto sulla privacy delle app Apple,
    /// escludendo demoni di sistema Apple, estensioni widget/notifiche e DirectSwitch stesso (zero indovinelli OCR).
    static func extractBundleIdsFromAppPrivacyReportNDJSON(_ rawText: String) -> [String] {
        var collected = Set<String>()
        let lines = rawText.split(whereSeparator: { $0 == "\n" || $0 == "\r" })
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.hasPrefix("{"),
                  let data = trimmed.data(using: .utf8),
                  let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
                continue
            }

            var candidateId: String? = nil
            if let accessor = obj["accessor"] as? [String: Any],
               let identifier = accessor["identifier"] as? String {
                let idType = (accessor["identifierType"] as? String)?.lowercased()
                if idType == nil || idType == "bundleid" {
                    candidateId = identifier
                }
            }
            if candidateId == nil, let topLevelBundle = obj["bundleID"] as? String {
                candidateId = topLevelBundle
            }
            guard let cleanId = normalizePrivacyReportBundleId(candidateId) else { continue }
            collected.insert(cleanId)
        }
        return collected.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private static func normalizePrivacyReportBundleId(_ raw: String?) -> String? {
        guard var trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty,
              trimmed.contains("."),
              !trimmed.contains(" "),
              !trimmed.contains("/") else {
            return nil
        }
        var lower = trimmed.lowercased()
        for extSuffix in extensionBundleSuffixes where lower.hasSuffix(extSuffix) {
            trimmed = String(trimmed.dropLast(extSuffix.count))
            lower = trimmed.lowercased()
            break
        }
        guard trimmed.contains(".") else { return nil }
        if lower.hasPrefix("com.directswitch.") { return nil }
        if lower.hasPrefix("com.apple.") && !allowedUserFacingAppleBundleIds.contains(lower) {
            return nil
        }
        return trimmed
    }

    /// Importa in modo deterministico l'elenco reale delle app da un file `App_Privacy_Report_*.ndjson` condiviso dall'utente:
    /// interroga `itunes.apple.com/lookup?bundleId=...` in blocchi da 20 e scarta eventuali app già disinstallate verificando `canOpenURL`.
    static func importAppsFromAppPrivacyReport(url: URL) async -> AppPrivacyReportImportResult {
        let didStartScope = url.startAccessingSecurityScopedResource()
        defer {
            if didStartScope { url.stopAccessingSecurityScopedResource() }
        }
        let rawText: String? = try? iOSDocumentsSandboxBridge.coordinatedRead(at: url) { readURL in
            guard let attrs = try? FileManager.default.attributesOfItem(atPath: readURL.path),
                  let fileSize = (attrs[.size] as? Int64) ?? (attrs[.size] as? NSNumber)?.int64Value,
                  fileSize <= 64 * 1024 * 1024 else {
                return nil
            }
            return try? String(contentsOf: readURL, encoding: .utf8)
        }
        guard let rawText, !rawText.isEmpty else {
            return AppPrivacyReportImportResult(apps: [], rawBundleIdsCount: 0)
        }
        let bundleIds = extractBundleIdsFromAppPrivacyReportNDJSON(rawText)
        guard !bundleIds.isEmpty else {
            return AppPrivacyReportImportResult(apps: [], rawBundleIdsCount: 0)
        }
        let resolved = await iOSAppStoreCatalogResolver.resolveExactAppsByBundleIds(bundleIds)
        let verified = await filterFalsePositiveProbesOnSender(resolved)
        return AppPrivacyReportImportResult(apps: verified, rawBundleIdsCount: bundleIds.count)
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
        "vlc", "dhl", "ups", "gls", "brt", "h&m", "n26", "avg", "kfc", "atm", "gtt", "bmw", "ovs", "bnl", "ing", "rai", "qvc", "axa"
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
            // Evita falsi positivi su parole minuscole come "now" / "io", ma conserva le app scritte "NOW" / "IO" in maiuscolo
            if lower == "now" && cleaned != "NOW" { continue }
            if ignoredNonAppTerms.contains(lower) && !(cleaned == "NOW" || cleaned == "IO") { continue }
            if lower.hasSuffix("%") || lower.hasSuffix("°") || lower.hasSuffix("°c") || lower.contains("€") || lower.contains("$") {
                continue
            }
            if ignoredSubstrings.contains(where: { lower.contains($0) }) { continue }

            // Scarta etichette brevi a 2 o 3 caratteri non corrispondenti a un'app/alias noto (evita rumore grafico delle icone e pulsanti UI)
            let isKnownShortAlias = (homeScreenShortAliases[lower] != nil && !(lower == "now" && cleaned != "NOW"))
                || knownProbes.contains(where: { $0.appName.lowercased() == lower })
            if cleaned.count == 2 && cleaned != "IO" && !isKnownShortAlias {
                continue
            }
            if cleaned.count == 3 && !isKnownShortAlias && !allowedThreeCharAppTokens.contains(lower) && cleaned != "NOW" {
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
        // Consente nomi app più alti su iPhone SE / Display Zoom / Testo Grande in Libreria App A–Z (restando sotto ai widget giganti)
        let maxAllowedHeight: CGFloat = stripTopStatusBar ? 0.052 : 0.062
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
            boxes.append(contentsOf: splitHorizontallyMergedObservation(obs, minConfidence: 0.38))
        }
        return mergeAndSplitSpatialTextBoxes(boxes, stripTopStatusBar: stripTopStatusBar)
    }

    /// Esegue l'OCR spaziale Apple `Vision` su un fotogramma live della fotocamera (`CVPixelBuffer`).
    static func recognizeSpatialCameraFrameLines(
        in pixelBuffer: CVPixelBuffer,
        orientation: CGImagePropertyOrientation = .right,
        minConfidence: Float = 0.45
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
        var seenQueryLower = Set<String>()

        // 1. Risoluzione offline immediata (0ms, zero rate-limit /search) per probe e catalogo rapido italiano (`bundleId` batch /lookup)
        for cand in candidates {
            let query = canonicalAppQuery(for: cand.cleaned)
            let qLower = query.lowercased()
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
            } else if let knownBundle = italianQuickSuggestions.first(where: { $0.appName.caseInsensitiveCompare(query) == .orderedSame }) {
                let dedup = "\(knownBundle.packageName.lowercased())_\(knownBundle.appStoreId ?? 0)"
                if !seenKeys.contains(dedup) {
                    seenKeys.insert(dedup)
                    resolved.append(knownBundle)
                }
            } else if !seenQueryLower.contains(qLower) {
                seenQueryLower.insert(qLower)
                networkCandidates.append((query: query, wasTruncated: cand.wasTruncated))
            }
        }

        // 2. Ricerca App Store controllata (`chunkSize = 2` + pausa 135ms) con backoff HTTP 429/403 così iTunes non taglia la coda su 100+ app
        let chunkSize = 2
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
                try? await Task.sleep(nanoseconds: 135_000_000)
            }
        }

        // 3. Carica in batch `/lookup?bundleId=...` e `/lookup?id=...` sia `appStoreId` mancanti che icone ufficiali
        if resolved.contains(where: { $0.iconUrl == nil || $0.appStoreId == nil }) {
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

        // 2. Legge gli screenshot recenti dall'album «Istantanee» (fino a 35 pagine per elenchi A–Z con 150+ app)
        let recentScreenshotPairs = await fetchRecentScreenshotsWithIdentifiersFromLibrary(maxCount: 35, since: cutoffDate)
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
        let artistName: String?
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

    static let androidPackageToiOSBundleId: [String: String] = [
        "com.whatsapp": "net.whatsapp.WhatsApp",
        "com.whatsapp.w4b": "net.whatsapp.WhatsAppSMB",
        "com.instagram.android": "com.burbn.instagram",
        "org.telegram.messenger": "ph.telegra.Telegraph",
        "org.telegram.plus": "ph.telegra.Telegraph",
        "com.facebook.katana": "com.facebook.Facebook",
        "com.facebook.orca": "com.facebook.Messenger",
        "com.zhiliaoapp.musically": "com.zhiliaoapp.musically",
        "com.google.android.youtube": "com.google.ios.youtube",
        "com.google.android.gm": "com.google.Gmail",
        "com.google.android.apps.maps": "com.google.Maps",
        "com.android.chrome": "com.google.chrome.ios",
        "com.google.android.apps.docs": "com.google.Drive",
        "com.google.android.apps.photos": "com.google.photos",
        "com.google.android.googlequicksearchbox": "com.google.GoogleMobile",
        "com.google.android.apps.authenticator2": "com.google.Authenticator",
        "com.spotify.music": "com.spotify.client",
        "com.netflix.mediaclient": "com.netflix.Netflix",
        "com.amazon.avod.thirdpartyclient": "com.amazon.aiv.AIVApp",
        "com.disney.disneyplus": "com.disney.disneyplus",
        "com.dazn": "com.dazn.theApp",
        "com.amazon.mshop.android.shopping": "com.amazon.AmazonIT",
        "com.paypal.android.p2pmobile": "com.yourcompany.PPClient",
        "com.revolut.revolut": "com.revolut.revolut",
        "com.satispay.customer": "com.satispay.customer.p2p",
        "com.microsoft.office.outlook": "com.microsoft.Office.Outlook",
        "com.microsoft.teams": "com.microsoft.skype.teams",
        "us.zoom.videomeetings": "us.zoom.videomeetings",
        "com.twitter.android": "com.atebits.Tweetie2",
        "com.instagram.barcelona": "com.burbn.barcelona",
        "com.linkedin.android": "com.linkedin.LinkedIn",
        "com.snapchat.android": "com.toyopagroup.picaboo",
        "com.pinterest": "pinterest",
        "com.reddit.frontpage": "com.reddit.Reddit",
        "com.discord": "com.hammerandchisel.discord",
        "tv.twitch.android.app": "tv.twitch",
        "com.waze": "com.waze.iphone",
        "com.ubercab": "com.ubercab.UberClient",
        "it.subito": "com.subito.subito",
        "fr.vinted": "lt.manodrabuziai.fr",
        "com.airbnb.android": "com.airbnb.app",
        "com.openai.chatgpt": "com.openai.chat",
        "com.shazam.android": "com.shazam.Shazam",
        "com.canva.editor": "com.canva.canvaeditor",
        "com.ebay.mobile": "com.ebay.iphone",
        "it.pagopa.app.io": "it.pagopa.app.io",
        "it.ipzs.cieid": "it.ipzs.cieID",
        "posteitaliane.posteapp.appposteid": "it.poste.postebuy2",
        "com.einnovation.temu": "com.einnovation.temu",
        "com.zzkko": "zzkko.com.ZZKKO",
        "com.booking": "com.booking.BookingApp",
        "com.lynxspa.prontotreno": "com.promptu.ProntoTreno",
        "it.telepass.prod.telepasspyng": "it.telepass",
        "com.strava": "com.strava.stravaride",
        "com.brave.browser": "com.brave.ios.browser",
        "com.microsoft.emmx": "com.microsoft.msedge",
        "ch.protonvpn.android": "ch.protonmail.vpn",
        "com.google.android.calendar": "com.google.calendar",
        "org.zwanoo.android.speedtest": "com.ookla.speedtest",
        "com.teamviewer.teamviewer.market.mobile": "com.teamviewer.rc",
        "com.lemon.lvoverseas": "com.lemon.lvoverseas",
        "com.camerasideas.instashot": "com.camerasideas.InstaShot",
        "com.niksoftware.snapseed": "com.niksoftware.snapseedforipad",
        "com.adobe.lrmobile": "com.adobe.lrmobilephone",
        "com.picsart.studio": "com.picsart.studio",
        "com.vsco.cam": "co.visualsupply.cam",
        "com.bigwinepot.nwdn.international": "com.bigwinepot.nwdn.international",
        "com.dropbox.android": "com.getdropbox.Dropbox",
        "com.Slack": "com.tinyspeck.chatlyio",
        "com.latuabancaperandroid": "com.intesasanpaolo.ibiphone",
        "com.unicredit": "com.internet.unicredit.iphoneapp",
        "com.posteitaliane.spim": "it.poste.spim",
        "com.fineco.it": "com.fineco.fineco"
    ]

    /// Risolve un elenco di `bundleId` esatti su App Store Italia (`/lookup?bundleId=...`) senza mai indovinare o alterare nomi.
    static func resolveExactAppsByBundleIds(_ bundleIds: [String]) async -> [InstalledAppRecord] {
        let uniqueBundles = Array(Set(bundleIds.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }))
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        guard !uniqueBundles.isEmpty else { return [] }

        var resolved: [InstalledAppRecord] = []
        var seenBundleKeys = Set<String>()
        let batchSize = 20
        var offset = 0

        while offset < uniqueBundles.count {
            let chunk = Array(uniqueBundles[offset..<min(offset + batchSize, uniqueBundles.count)])
            offset += batchSize
            let joined = chunk.joined(separator: ",")
            guard let encoded = joined.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                  let url = URL(string: "https://itunes.apple.com/lookup?bundleId=\(encoded)&country=it") else {
                continue
            }
            var req = URLRequest(url: url, timeoutInterval: 8.0)
            req.httpMethod = "GET"
            if let (data, resp) = try? await URLSession.shared.data(for: req),
               (resp as? HTTPURLResponse)?.statusCode == 200,
               let parsed = try? JSONDecoder().decode(ITunesLookupResponse.self, from: data) {
                for entry in parsed.results {
                    guard let bId = entry.bundleId, let tId = entry.trackId, let tName = entry.trackName else { continue }
                    let key = bId.lowercased()
                    guard !seenBundleKeys.contains(key) else { continue }
                    seenBundleKeys.insert(key)
                    let icon = sanitizeIconUrl(entry.artworkUrl100)
                    await AppStoreMetadataCache.shared.setByBundle(bId, trackId: tId, iconUrl: icon, trackName: tName)
                    let matchedProbe = iOSInstalledAppsScanner.knownProbes.first {
                        $0.bundleId.caseInsensitiveCompare(bId) == .orderedSame || $0.appStoreId == tId
                    }
                    resolved.append(
                        InstalledAppRecord(
                            packageName: bId,
                            appName: tName,
                            appStoreId: tId,
                            iconUrl: icon,
                            urlScheme: matchedProbe?.urlScheme
                        )
                    )
                }
            }
        }
        return resolved.sorted { $0.appName.localizedCaseInsensitiveCompare($1.appName) == .orderedAscending }
    }

    /// Arricchisce un elenco di `InstalledAppRecord` (sia nativi iOS sia ricevuti da Android) con `appStoreId` e `iconUrl`.
    static func enrichAppsWithStoreMetadata(_ apps: [InstalledAppRecord]) async -> [InstalledAppRecord] {
        guard !apps.isEmpty else { return [] }
        var working = apps

        // 1. Applica mappa Android -> iOS e eventuali probe noti locali per avere subito `appStoreId` e `urlScheme`
        for i in working.indices {
            let pkgLower = working[i].packageName.lowercased()
            let mappedBundle = androidPackageToiOSBundleId[pkgLower]
            let canonicalName = iOSInstalledAppsScanner.canonicalAppQuery(for: working[i].appName)
            if let probe = iOSInstalledAppsScanner.knownProbes.first(where: {
                (mappedBundle != nil && $0.bundleId.caseInsensitiveCompare(mappedBundle!) == .orderedSame)
                    || $0.bundleId.caseInsensitiveCompare(working[i].packageName) == .orderedSame
                    || $0.appName.caseInsensitiveCompare(working[i].appName) == .orderedSame
                    || $0.appName.caseInsensitiveCompare(canonicalName) == .orderedSame
            }) {
                if working[i].appStoreId == nil {
                    working[i].appStoreId = probe.appStoreId
                }
                if working[i].urlScheme == nil {
                    working[i].urlScheme = probe.urlScheme
                }
            }
            if let cached = await AppStoreMetadataCache.shared.getByBundle(mappedBundle ?? working[i].packageName) {
                if working[i].appStoreId == nil { working[i].appStoreId = cached.trackId }
                if working[i].iconUrl == nil { working[i].iconUrl = cached.iconUrl }
            }
        }

        // 2. Lookup batch per `bundleId` (fino a 20 per chiamata HTTP, velocissimo)
        let missingIconBundles = Array(Set(
            working
                .filter { $0.iconUrl == nil && $0.packageName.contains(".") }
                .compactMap { item -> String? in
                    let pkgLower = item.packageName.lowercased()
                    return androidPackageToiOSBundleId[pkgLower] ?? item.packageName
                }
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
                        for idx in working.indices {
                            let targetBundle = androidPackageToiOSBundleId[working[idx].packageName.lowercased()] ?? working[idx].packageName
                            if targetBundle.caseInsensitiveCompare(bId) == .orderedSame {
                                working[idx].appStoreId = tId
                                if let cleanIcon { working[idx].iconUrl = cleanIcon }
                            }
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

        // 4. Per eventuali app senza `appStoreId` (es. provenienti da Android), risolve con alias + verifica rigorosa su App Store Italia
        for idx in working.indices where working[idx].appStoreId == nil {
            let query = iOSInstalledAppsScanner.canonicalAppQuery(for: working[idx].appName)
            if let resolved = await searchBestMatch(appName: query, wasTruncated: false, strictTitleSimilarity: true) {
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
        "app", "mobile", "italia", "italy", "it", "com", "official", "ufficiale", "banca", "bank", "banking", "pay", "messenger",
        "shopping", "shop", "club", "music", "video", "tv", "plus", "go", "online", "smart", "control", "free", "wallet",
        "home", "connect", "workplace", "studenti", "famiglia", "famiglie", "clienti", "card", "otp", "id", "pass", "hub",
        "live", "ai", "studio", "editor", "notify", "energia", "assicurazioni", "flights", "airlines", "scanner", "reader",
        "treno", "vpn", "browser", "mail", "remote", "tracker"
    ]

    /// Verifica rigorosa anti-allucinazione tra il nome letto sullo schermo del telefono e il titolo ufficiale su App Store:
    /// impedisce che parole casuali, nomi di cartelle o sottotitoli generino app inesistenti, gestendo anche troncamenti senza `…`.
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

        // 2b. Troncamento Home/Libreria dove Vision OCR ha omesso i tre puntini `…` finali
        // (es. "Banca Mediol" -> "Banca Mediolanum", "GialloZaffer" -> "GialloZafferano"), mai per parole singole generiche
        if !wasTruncated && prim.hasPrefix(cand) {
            if candWords.count >= 2 && cand.count >= 10 && primWords.first == candWords.first {
                return true
            }
            if candWords.count == 1 && cand.count >= 9 && primWords.count == 1 && abs(prim.count - cand.count) <= 6 {
                return true
            }
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

    static func searchAppStoreDetailed(query: String, limit: Int = 12) async -> [AppStoreSearchHit] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://itunes.apple.com/search?term=\(encoded)&country=it&entity=software&limit=\(limit)") else {
            return []
        }

        var responseData: Data? = nil
        let backoffDelaysNs: [UInt64] = [800_000_000, 1_900_000_000]
        for attempt in 0..<3 {
            var req = URLRequest(url: url, timeoutInterval: 7.5)
            req.httpMethod = "GET"
            if let (data, resp) = try? await URLSession.shared.data(for: req),
               let code = (resp as? HTTPURLResponse)?.statusCode {
                if code == 200 {
                    responseData = data
                    break
                }
                if (code == 429 || code == 403 || code >= 500) && attempt < backoffDelaysNs.count {
                    try? await Task.sleep(nanoseconds: backoffDelaysNs[attempt])
                    continue
                }
                break
            } else if attempt < backoffDelaysNs.count {
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
        }

        guard let data = responseData,
              let parsed = try? JSONDecoder().decode(ITunesLookupResponse.self, from: data) else {
            return []
        }

        var out: [AppStoreSearchHit] = []
        for entry in parsed.results {
            guard let bundleId = entry.bundleId,
                  let trackName = entry.trackName,
                  let trackId = entry.trackId else { continue }
            let matchedProbe = iOSInstalledAppsScanner.knownProbes.first {
                $0.bundleId.caseInsensitiveCompare(bundleId) == .orderedSame || $0.appStoreId == trackId
            }
            let rec = InstalledAppRecord(
                packageName: bundleId,
                appName: trackName,
                appStoreId: trackId,
                iconUrl: sanitizeIconUrl(entry.artworkUrl100),
                urlScheme: matchedProbe?.urlScheme
            )
            out.append(AppStoreSearchHit(record: rec, developerName: entry.artistName))
        }
        return out
    }

    static func searchAppStore(query: String, limit: Int = 12) async -> [InstalledAppRecord] {
        await searchAppStoreDetailed(query: query, limit: limit).map(\.record)
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

/// Motore di installazione in-app sul nuovo iPhone (senza MAI uscire verso l'app esterna App Store in coda):
/// 1) Livello 1 (Predefinito): Mini-banner di sistema fisso in basso (`SKOverlay`, posizione `.bottom`) per restare in DirectSwitch.
/// 2) Livello 2 (Fallback in-app): `SKStoreProductViewController` se `SKOverlay` non è supportato sullo specifico dispositivo/build,
///    con controllo manuale «Interrompi / Prossima» alla chiusura della scheda (zero loop incontrollabili e zero apertura esterna dell'App Store).
@MainActor
final class iOSSequentialAppInstaller: NSObject, ObservableObject, SKOverlayDelegate, SKStoreProductViewControllerDelegate, UIAdaptivePresentationControllerDelegate {
    enum DeliveryMode: Equatable {
        case fastBottomOverlay
        case inlineStoreSheet
        case inlinePausedPrompt
    }

    @Published var apps: [InstalledAppRecord] = []
    @Published var selectedIds: Set<String> = []
    @Published var completedIds: Set<String> = []
    @Published var activeDownloadingIds: Set<String> = []
    @Published var alreadyInstalledIds: Set<String> = []
    @Published var unavailableInStoreIds: Set<String> = []
    @Published var isEnrichingMetadata: Bool = false

    @Published var isRunningSequence: Bool = false
    @Published var isSingleOverlaySession: Bool = false
    @Published var isLoadingInlineCard: Bool = false
    @Published var isOverlayVisible: Bool = false
    @Published var isWaitingInlineNextConfirmation: Bool = false
    @Published var overlaySafeBottomPadding: CGFloat = 78
    @Published var activeDeliveryMode: DeliveryMode = .fastBottomOverlay

    @Published var currentQueuePosition: Int = 0
    @Published var totalQueueCount: Int = 0
    @Published var currentActiveApp: InstalledAppRecord? = nil
    @Published var installerStatusNote: String? = nil
    @Published private(set) var historyStack: [InstalledAppRecord] = []

    /// Usato nei test unitari su simulatore per verificare la macchina a stati della coda senza invocare `storekitd`.
    var dryRunPresentationForTesting: Bool = false

    private var queue: [InstalledAppRecord] = []
    private var overlayUnsupportedOnDevice: Bool = false
    private var hasEverPresentedOverlaySuccessfully: Bool = false
    private var consecutiveOverlayFailures: Int = 0
    private var inlineSheetHandledForCurrentStep: Bool = false
    private var isSwitchingOverlayProgrammatically: Bool = false
    private var isDismissingByUserStop: Bool = false
    private var queueGeneration: Int = 0
    private var currentPresentationAttemptId: UUID = UUID()
    private var autoAdvanceTask: Task<Void, Never>? = nil
    private var liveInstallMonitorTask: Task<Void, Never>? = nil
    private var activeOverlayInstance: SKOverlay? = nil
    private weak var presentedStoreVC: SKStoreProductViewController? = nil

    /// App presenti nel catalogo App Store con `appStoreId` valido, installabili in-app senza uscire da DirectSwitch.
    var queueableApps: [InstalledAppRecord] {
        apps.filter { ($0.appStoreId ?? 0) > 0 }
    }

    /// App non trovate nel catalogo App Store italiano (`appStoreId == nil`): non vengono MAI aperte automaticamente nell'App Store esterno.
    var missingCatalogApps: [InstalledAppRecord] {
        apps.filter { ($0.appStoreId ?? 0) <= 0 }
    }

    /// App in scaricamento o già installate/avviate mostrate nella barra di avanzamento inferiore.
    var dockTrackedApps: [InstalledAppRecord] {
        apps.filter { app in
            currentActiveApp?.id == app.id
                || activeDownloadingIds.contains(app.id)
                || alreadyInstalledIds.contains(app.id)
                || completedIds.contains(app.id)
        }
    }

    var pendingInstallableCount: Int {
        queueableApps.filter {
            selectedIds.contains($0.id) && !alreadyInstalledIds.contains($0.id) && !completedIds.contains($0.id)
        }.count
    }

    var canGoBackInQueue: Bool {
        isRunningSequence && !historyStack.isEmpty
    }

    var showsFloatingBottomBar: Bool {
        guard currentActiveApp != nil else { return false }
        if isRunningSequence || isSingleOverlaySession {
            return activeDeliveryMode == .fastBottomOverlay || isWaitingInlineNextConfirmation
        }
        return false
    }

    func reset() {
        stopSequence()
        apps = []
        selectedIds = []
        completedIds = []
        activeDownloadingIds = []
        alreadyInstalledIds = []
        unavailableInStoreIds = []
        historyStack = []
        installerStatusNote = nil
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
            activeDownloadingIds.removeAll()
            selectedIds = Set(
                apps
                    .filter { ($0.appStoreId ?? 0) > 0 && !alreadyInstalledIds.contains($0.id) }
                    .map(\.id)
            )
            return
        }

        completedIds.removeAll()
        activeDownloadingIds.removeAll()
        unavailableInStoreIds.removeAll()
        historyStack.removeAll()
        installerStatusNote = nil
        apps = incomingApps
        refreshInstalledStatuses()
        selectedIds = Set(
            incomingApps
                .filter { ($0.appStoreId ?? 0) > 0 && !alreadyInstalledIds.contains($0.id) }
                .map(\.id)
        )

        guard !dryRunPresentationForTesting else { return }
        isEnrichingMetadata = true
        let expectedIds = incomingApps.map(\.id)
        Task {
            let enriched = await iOSAppStoreCatalogResolver.enrichAppsWithStoreMetadata(incomingApps)
            guard self.apps.map(\.id) == expectedIds else { return }
            let byId = Dictionary(uniqueKeysWithValues: enriched.map { ($0.id, $0) })
            self.apps = enriched
            self.queue = self.queue.map { byId[$0.id] ?? $0 }
            self.historyStack = self.historyStack.map { byId[$0.id] ?? $0 }
            if let active = self.currentActiveApp, let updatedActive = byId[active.id] {
                self.currentActiveApp = updatedActive
            }
            self.refreshInstalledStatuses()
            for app in enriched where (app.appStoreId ?? 0) > 0 && !self.alreadyInstalledIds.contains(app.id) && !self.completedIds.contains(app.id) {
                self.selectedIds.insert(app.id)
            }
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
        for item in merged where (item.appStoreId ?? 0) > 0 && !alreadyInstalledIds.contains(item.id) && !completedIds.contains(item.id) {
            selectedIds.insert(item.id)
        }
        guard !dryRunPresentationForTesting else { return }
        isEnrichingMetadata = true
        Task {
            let enriched = await iOSAppStoreCatalogResolver.enrichAppsWithStoreMetadata(merged)
            self.apps = enriched
            self.refreshInstalledStatuses()
            for app in enriched where (app.appStoreId ?? 0) > 0 && !self.alreadyInstalledIds.contains(app.id) && !self.completedIds.contains(app.id) {
                self.selectedIds.insert(app.id)
            }
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
        if !installed.isEmpty {
            activeDownloadingIds.subtract(installed)
        }
    }

    func toggleSelection(for app: InstalledAppRecord) {
        guard !alreadyInstalledIds.contains(app.id), (app.appStoreId ?? 0) > 0 else { return }
        if selectedIds.contains(app.id) {
            selectedIds.remove(app.id)
        } else {
            selectedIds.insert(app.id)
        }
    }

    func selectAllPending() {
        for app in queueableApps where !alreadyInstalledIds.contains(app.id) {
            selectedIds.insert(app.id)
        }
    }

    /// Installa una singola app verificata nel catalogo mostrando subito il mini-banner `SKOverlay` fisso in basso (o scheda in-app).
    func installSingleApp(_ app: InstalledAppRecord) {
        stopSequence()
        guard (app.appStoreId ?? 0) > 0 else {
            unavailableInStoreIds.insert(app.id)
            installerStatusNote = "«\(app.appName)» non ha una scheda App Store verificata: usa eventualmente la ricerca manuale in fondo."
            return
        }
        installerStatusNote = nil
        currentActiveApp = app
        isSingleOverlaySession = true
        isWaitingInlineNextConfirmation = false
        currentQueuePosition = 1
        totalQueueCount = 1
        startLiveInstallMonitor()
        presentAppFastBannerOrFallback(app: app, partOfSequence: false)
    }

    /// Avvia la sequenza in-app per le sole app con `appStoreId` verificato (mai apertura esterna dell'App Store).
    func startAutomaticSequence() {
        stopSequence()
        refreshInstalledStatuses()
        let pending = queueableApps.filter {
            selectedIds.contains($0.id) && !alreadyInstalledIds.contains($0.id) && !completedIds.contains($0.id)
        }
        guard !pending.isEmpty else {
            if !missingCatalogApps.isEmpty {
                installerStatusNote = "Le app restanti non risultano nel catalogo App Store italiano e sono elencate in fondo."
            }
            return
        }

        installerStatusNote = nil
        queue = pending
        historyStack = []
        totalQueueCount = pending.count
        currentQueuePosition = 0
        isRunningSequence = true
        isSingleOverlaySession = false
        isWaitingInlineNextConfirmation = false
        startLiveInstallMonitor()
        advanceToNextInQueue()
    }

    /// Registra l'app corrente come avviata/in scaricamento in basso e passa subito alla successiva della coda.
    func confirmCurrentAndAdvance() {
        autoAdvanceTask?.cancel()
        isLoadingInlineCard = false
        isWaitingInlineNextConfirmation = false

        if let active = currentActiveApp {
            completedIds.insert(active.id)
            if !alreadyInstalledIds.contains(active.id) && !unavailableInStoreIds.contains(active.id) {
                activeDownloadingIds.insert(active.id)
            }
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

    /// Apre l'app successiva dopo una pausa nella modalità scheda in-app (solo su tocco esplicito dell'utente).
    func resumePausedInlineNextApp() {
        guard isRunningSequence, let active = currentActiveApp else { return }
        isWaitingInlineNextConfirmation = false
        installerStatusNote = nil
        presentAppFastBannerOrFallback(app: active, partOfSequence: true)
    }

    /// Torna immediatamente all'app precedente nel mini-banner se si è toccato «Prossima» per errore.
    func goBackToPreviousApp() {
        guard isRunningSequence, let previous = historyStack.popLast() else { return }
        autoAdvanceTask?.cancel()
        isLoadingInlineCard = false
        isWaitingInlineNextConfirmation = false
        installerStatusNote = nil

        if let active = currentActiveApp {
            queue.insert(active, at: 0)
            currentQueuePosition = max(1, currentQueuePosition - 1)
        } else {
            currentQueuePosition = max(1, currentQueuePosition)
        }

        completedIds.remove(previous.id)
        activeDownloadingIds.remove(previous.id)
        currentActiveApp = previous
        presentAppFastBannerOrFallback(app: previous, partOfSequence: true)
    }

    /// Riapre il mini-banner `SKOverlay` dell'app corrente se l'utente lo ha chiuso scorrendo verso il basso.
    func reopenCurrentOverlay() {
        guard let active = currentActiveApp else { return }
        isWaitingInlineNextConfirmation = false
        presentAppFastBannerOrFallback(app: active, partOfSequence: isRunningSequence)
    }

    func skipCurrentAndContinue() {
        autoAdvanceTask?.cancel()
        isLoadingInlineCard = false
        isWaitingInlineNextConfirmation = false
        installerStatusNote = nil
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

    /// Arresta IMMEDIATAMENTE l'intera sequenza: invalida ogni callback pendente, chiude eventuali overlay/schede
    /// e garantisce che nessun'altra app venga mai aperta chiudendo o tornando nell'app.
    func stopSequence() {
        isDismissingByUserStop = true
        queueGeneration += 1
        currentPresentationAttemptId = UUID()
        autoAdvanceTask?.cancel()
        autoAdvanceTask = nil
        if queue.isEmpty && !isRunningSequence && activeDownloadingIds.isEmpty {
            liveInstallMonitorTask?.cancel()
            liveInstallMonitorTask = nil
        }
        dismissOverlayIfPresent()
        if !dryRunPresentationForTesting, let vc = presentedStoreVC {
            presentedStoreVC = nil
            vc.dismiss(animated: true)
        } else {
            presentedStoreVC = nil
        }
        queue.removeAll()
        historyStack.removeAll()
        isRunningSequence = false
        isSingleOverlaySession = false
        isLoadingInlineCard = false
        isOverlayVisible = false
        isWaitingInlineNextConfirmation = false
        currentActiveApp = nil
        isDismissingByUserStop = false
    }

    /// Chiamato quando DirectSwitch torna attiva in primo piano (`scenePhase == .active`):
    /// aggiorna solo gli stati `Installata ✓`, senza MAI aprire automaticamente altre app né lanciare App Store!
    func handleSceneBecameActive() {
        refreshInstalledStatuses()
    }

    private func startLiveInstallMonitor() {
        liveInstallMonitorTask?.cancel()
        guard !dryRunPresentationForTesting else { return }
        let capturedGeneration = queueGeneration
        liveInstallMonitorTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard let self, !Task.isCancelled else { return }
                self.refreshInstalledStatuses()
                if self.queueGeneration == capturedGeneration,
                   (self.isRunningSequence || self.isSingleOverlaySession),
                   let active = self.currentActiveApp,
                   self.alreadyInstalledIds.contains(active.id) {
                    self.confirmCurrentAndAdvance()
                    continue
                }
                if !self.isRunningSequence && !self.isSingleOverlaySession && self.activeDownloadingIds.isEmpty {
                    return
                }
            }
        }
    }

    private func advanceToNextInQueue() {
        guard isRunningSequence else { return }
        refreshInstalledStatuses()
        while !queue.isEmpty {
            let candidate = queue.removeFirst()
            currentQueuePosition += 1
            if alreadyInstalledIds.contains(candidate.id) || completedIds.contains(candidate.id) {
                continue
            }
            guard (candidate.appStoreId ?? 0) > 0 else {
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
        let attemptGen = queueGeneration
        currentPresentationAttemptId = attemptId

        if dryRunPresentationForTesting {
            activeDeliveryMode = .fastBottomOverlay
            isOverlayVisible = true
            isLoadingInlineCard = false
            isWaitingInlineNextConfirmation = false
            return
        }

        // Livello 1: Mini-banner di sistema fisso in basso (`SKOverlay`) senza cambiare schermata
        if !overlayUnsupportedOnDevice,
           let trackId = app.appStoreId, trackId > 0,
           let scene = Self.activeWindowScene() {
            activeDeliveryMode = .fastBottomOverlay
            isLoadingInlineCard = true
            isWaitingInlineNextConfirmation = false

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
                guard let self,
                      self.queueGeneration == attemptGen,
                      self.currentPresentationAttemptId == attemptId,
                      (self.isRunningSequence || self.isSingleOverlaySession) else { return }
                guard let liveScene = Self.activeWindowScene() else {
                    self.presentInlineStoreSheetOnly(app: app, partOfSequence: partOfSequence, attemptId: attemptId, attemptGen: attemptGen)
                    return
                }

                self.isSwitchingOverlayProgrammatically = false
                let config = SKOverlay.AppConfiguration(appIdentifier: String(trackId), position: .bottom)
                config.userDismissible = true
                let overlay = SKOverlay(configuration: config)
                overlay.delegate = self
                self.activeOverlayInstance = overlay
                overlay.present(in: liveScene)

                // Timeout di sicurezza (2.6s): se su questa build `storekitd` non mostra SKOverlay, scala alla scheda in-app StoreKit (mai all'App Store esterno)
                try? await Task.sleep(nanoseconds: 2_600_000_000)
                guard self.queueGeneration == attemptGen,
                      self.currentPresentationAttemptId == attemptId,
                      (self.isRunningSequence || self.isSingleOverlaySession),
                      !self.isOverlayVisible else { return }
                self.isLoadingInlineCard = false
                self.consecutiveOverlayFailures += 1
                if !self.hasEverPresentedOverlaySuccessfully && self.consecutiveOverlayFailures >= 2 {
                    self.overlayUnsupportedOnDevice = true
                }
                self.dismissOverlayIfPresent()
                self.presentInlineStoreSheetOnly(app: app, partOfSequence: partOfSequence, attemptId: attemptId, attemptGen: attemptGen)
            }
            return
        }

        presentInlineStoreSheetOnly(app: app, partOfSequence: partOfSequence, attemptId: attemptId, attemptGen: attemptGen)
    }

    private func presentInlineStoreSheetOnly(
        app: InstalledAppRecord,
        partOfSequence: Bool,
        attemptId: UUID,
        attemptGen: Int
    ) {
        guard queueGeneration == attemptGen,
              currentPresentationAttemptId == attemptId,
              (isRunningSequence || isSingleOverlaySession) else { return }

        guard let trackId = app.appStoreId, trackId > 0,
              let presenter = Self.topMostViewController(),
              presenter.presentedViewController == nil else {
            markAppUnavailableInOverlay(app: app, partOfSequence: partOfSequence)
            return
        }

        activeDeliveryMode = .inlineStoreSheet
        isLoadingInlineCard = true
        isWaitingInlineNextConfirmation = false
        inlineSheetHandledForCurrentStep = false

        let storeVC = SKStoreProductViewController()
        storeVC.delegate = self
        storeVC.presentationController?.delegate = self
        self.presentedStoreVC = storeVC

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
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            guard gate.trySettle(),
                  let self,
                  self.queueGeneration == attemptGen,
                  self.currentPresentationAttemptId == attemptId,
                  (self.isRunningSequence || self.isSingleOverlaySession) else { return }
            self.isLoadingInlineCard = false
            self.presentedStoreVC = nil
            self.markAppUnavailableInOverlay(app: app, partOfSequence: partOfSequence)
        }

        let params: [String: Any] = [
            SKStoreProductParameterITunesItemIdentifier: NSNumber(value: trackId)
        ]
        storeVC.loadProduct(withParameters: params) { [weak self] loaded, _ in
            Task { @MainActor [weak self] in
                guard gate.trySettle(),
                      let self,
                      self.queueGeneration == attemptGen,
                      self.currentPresentationAttemptId == attemptId,
                      (self.isRunningSequence || self.isSingleOverlaySession) else { return }
                self.isLoadingInlineCard = false
                if loaded,
                   let livePresenter = Self.topMostViewController(),
                   livePresenter.presentedViewController == nil {
                    livePresenter.present(storeVC, animated: true)
                } else {
                    self.presentedStoreVC = nil
                    self.markAppUnavailableInOverlay(app: app, partOfSequence: partOfSequence)
                }
            }
        }
    }

    /// Gestisce un'app non caricabile dal banner StoreKit senza MAI buttare fuori l'utente verso l'app esterna App Store.
    private func markAppUnavailableInOverlay(app: InstalledAppRecord, partOfSequence: Bool) {
        unavailableInStoreIds.insert(app.id)
        installerStatusNote = "«\(app.appName)» non si apre nel banner rapido Apple (puoi cercarla manualmente in basso a fine elenco senza bloccare la coda)."
        if !partOfSequence {
            stopSequence()
            return
        }
        guard isRunningSequence else { return }
        if queue.isEmpty {
            stopSequence()
            return
        }
        activeDeliveryMode = .inlinePausedPrompt
        isWaitingInlineNextConfirmation = true
        currentActiveApp = queue.removeFirst()
        currentQueuePosition += 1
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

    private func handleInlineStoreDismissed(expectedGeneration: Int) {
        presentedStoreVC = nil
        guard !isDismissingByUserStop,
              queueGeneration == expectedGeneration,
              !inlineSheetHandledForCurrentStep else { return }
        inlineSheetHandledForCurrentStep = true

        if let active = currentActiveApp {
            completedIds.insert(active.id)
            if !alreadyInstalledIds.contains(active.id) {
                activeDownloadingIds.insert(active.id)
            }
            if isRunningSequence {
                historyStack.append(active)
            }
        }
        refreshInstalledStatuses()

        if isSingleOverlaySession || !isRunningSequence {
            stopSequence()
            return
        }

        // Quando si chiude la scheda in-app («Fine»): NON lancia subito un'altra scheda a sorpresa in faccia all'utente!
        // Resta nella barra fissa in basso con i tasti espliciti «Interrompi» e «Prossima app →».
        guard !queue.isEmpty else {
            stopSequence()
            return
        }
        while !queue.isEmpty {
            let nextApp = queue.removeFirst()
            currentQueuePosition += 1
            if alreadyInstalledIds.contains(nextApp.id) || completedIds.contains(nextApp.id) || (nextApp.appStoreId ?? 0) <= 0 {
                continue
            }
            currentActiveApp = nextApp
            activeDeliveryMode = .inlinePausedPrompt
            isWaitingInlineNextConfirmation = true
            return
        }
        stopSequence()
    }

    // MARK: - SKOverlayDelegate

    nonisolated func storeOverlayWillStartPresentation(_ overlay: SKOverlay, transitionContext: SKOverlay.TransitionContext) {
        let endFrame = transitionContext.endFrame
        Task { @MainActor [weak self] in
            guard let self,
                  overlay === self.activeOverlayInstance,
                  (self.isRunningSequence || self.isSingleOverlaySession) else { return }
            self.updateSafeBottomPadding(from: endFrame)
            self.isOverlayVisible = true
            self.isLoadingInlineCard = false
            self.hasEverPresentedOverlaySuccessfully = true
            self.consecutiveOverlayFailures = 0
        }
    }

    nonisolated func storeOverlayDidFinishPresentation(_ overlay: SKOverlay, transitionContext: SKOverlay.TransitionContext) {
        let endFrame = transitionContext.endFrame
        Task { @MainActor [weak self] in
            guard let self,
                  overlay === self.activeOverlayInstance,
                  (self.isRunningSequence || self.isSingleOverlaySession) else { return }
            self.updateSafeBottomPadding(from: endFrame)
            self.isOverlayVisible = true
            self.isLoadingInlineCard = false
            self.hasEverPresentedOverlaySuccessfully = true
            self.consecutiveOverlayFailures = 0
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
            guard let self,
                  overlay === self.activeOverlayInstance,
                  (self.isRunningSequence || self.isSingleOverlaySession) else { return }
            self.isLoadingInlineCard = false
            self.isOverlayVisible = false
            self.activeOverlayInstance = nil
            self.consecutiveOverlayFailures += 1
            if !self.hasEverPresentedOverlaySuccessfully && self.consecutiveOverlayFailures >= 2 {
                self.overlayUnsupportedOnDevice = true
            }
            if let active = self.currentActiveApp {
                self.presentInlineStoreSheetOnly(
                    app: active,
                    partOfSequence: self.isRunningSequence,
                    attemptId: self.currentPresentationAttemptId,
                    attemptGen: self.queueGeneration
                )
            }
        }
    }

    // MARK: - SKStoreProductViewControllerDelegate

    nonisolated func productViewControllerDidFinish(_ viewController: SKStoreProductViewController) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            let gen = self.queueGeneration
            viewController.dismiss(animated: true) {
                Task { @MainActor [weak self] in
                    self?.handleInlineStoreDismissed(expectedGeneration: gen)
                }
            }
        }
    }

    nonisolated func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.handleInlineStoreDismissed(expectedGeneration: self.queueGeneration)
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
        guard now - lastAnalyzedTimestamp >= 0.22 else { return }
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        lastAnalyzedTimestamp = now

        var recognizedLines: [String] = []
        autoreleasepool {
            recognizedLines = iOSInstalledAppsScanner.recognizeSpatialCameraFrameLines(
                in: pixelBuffer,
                orientation: .right,
                minConfidence: 0.45
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

// MARK: - Rilevamento Extra-50 da Album Foto, Nomi File e Metadati EXIF / QuickTime (Zero Nuovi Permessi)

/// Regola deterministica per individuare un'app reale installata/usata su iPhone a partire da indizi locali
/// nella libreria Foto (titolo album creato dall'app, prefisso file univoco o tag Software EXIF/TIFF/QuickTime).
struct PhotoClueAppRule: Sendable {
    let bundleId: String
    let appName: String
    let appStoreId: Int?
    let urlScheme: String?
    let exactAlbumTitles: [String]
    let filenamePrefixes: [String]
    let softwareTagTokens: [String]
}

/// Rilevatore istantaneo extra-50 basato sui permessi Foto già concessi:
/// 1) Album creati automaticamente dalle app in Foto (`PHAssetCollection`) con data ultimo utilizzo
/// 2) Prefissi univoci di file media salvati da editor / action-cam / messaggistica
/// 3) Tag Software EXIF/TIFF/PNG e QuickTime letti a costo zero durante il trasferimento di foto e video
enum iOSPhotoMetadataAppDetector {
    static let rules: [PhotoClueAppRule] = [
        PhotoClueAppRule(
            bundleId: "net.whatsapp.WhatsApp", appName: "WhatsApp Messenger", appStoreId: 310633997, urlScheme: "whatsapp-consumer",
            exactAlbumTitles: ["whatsapp"], filenamePrefixes: [], softwareTagTokens: ["whatsapp"]
        ),
        PhotoClueAppRule(
            bundleId: "net.whatsapp.WhatsAppSMB", appName: "WhatsApp Business", appStoreId: 1386412985, urlScheme: "whatsapp-smb",
            exactAlbumTitles: ["whatsapp business"], filenamePrefixes: [], softwareTagTokens: []
        ),
        PhotoClueAppRule(
            bundleId: "com.burbn.instagram", appName: "Instagram", appStoreId: 389801252, urlScheme: "instagram",
            exactAlbumTitles: ["instagram"], filenamePrefixes: [], softwareTagTokens: ["instagram"]
        ),
        PhotoClueAppRule(
            bundleId: "ph.telegra.Telegraph", appName: "Telegram Messenger", appStoreId: 686449807, urlScheme: "tg",
            exactAlbumTitles: ["telegram"], filenamePrefixes: [], softwareTagTokens: []
        ),
        PhotoClueAppRule(
            bundleId: "com.toyopagroup.picaboo", appName: "Snapchat", appStoreId: 447188370, urlScheme: "snapchat",
            exactAlbumTitles: ["snapchat"], filenamePrefixes: ["snapchat-"], softwareTagTokens: ["snapchat"]
        ),
        PhotoClueAppRule(
            bundleId: "com.zhiliaoapp.musically", appName: "TikTok", appStoreId: 835599320, urlScheme: "tiktok",
            exactAlbumTitles: ["tiktok"], filenamePrefixes: ["tiktok_"], softwareTagTokens: ["tiktok"]
        ),
        PhotoClueAppRule(
            bundleId: "com.lemon.lvoverseas", appName: "CapCut", appStoreId: 1500855883, urlScheme: nil,
            exactAlbumTitles: ["capcut", "capcut projects"], filenamePrefixes: ["capcut", "lv_0_"], softwareTagTokens: ["capcut"]
        ),
        PhotoClueAppRule(
            bundleId: "com.camerasideas.InstaShot", appName: "InShot", appStoreId: 997362197, urlScheme: nil,
            exactAlbumTitles: ["inshot"], filenamePrefixes: ["inshot_"], softwareTagTokens: ["inshot"]
        ),
        PhotoClueAppRule(
            bundleId: "com.niksoftware.snapseedforipad", appName: "Snapseed", appStoreId: 439438619, urlScheme: nil,
            exactAlbumTitles: ["snapseed"], filenamePrefixes: ["snapseed"], softwareTagTokens: ["snapseed"]
        ),
        PhotoClueAppRule(
            bundleId: "com.adobe.lrmobilephone", appName: "Lightroom", appStoreId: 878783582, urlScheme: nil,
            exactAlbumTitles: ["lightroom", "adobe lightroom"], filenamePrefixes: ["lightroom", "lr_"], softwareTagTokens: ["lightroom", "adobe lightroom"]
        ),
        PhotoClueAppRule(
            bundleId: "com.picsart.studio", appName: "Picsart", appStoreId: 587366035, urlScheme: nil,
            exactAlbumTitles: ["picsart"], filenamePrefixes: ["picsart_"], softwareTagTokens: ["picsart"]
        ),
        PhotoClueAppRule(
            bundleId: "co.visualsupply.cam", appName: "VSCO", appStoreId: 588013838, urlScheme: nil,
            exactAlbumTitles: ["vsco", "vsco cam"], filenamePrefixes: ["vsco"], softwareTagTokens: ["vsco"]
        ),
        PhotoClueAppRule(
            bundleId: "com.bigwinepot.nwdn.international", appName: "Remini", appStoreId: 1470373330, urlScheme: nil,
            exactAlbumTitles: ["remini"], filenamePrefixes: ["remini"], softwareTagTokens: ["remini"]
        ),
        PhotoClueAppRule(
            bundleId: "com.lightricks.Facetune2", appName: "Facetune", appStoreId: 1149994032, urlScheme: nil,
            exactAlbumTitles: ["facetune", "facetune2"], filenamePrefixes: ["facetune"], softwareTagTokens: ["facetune"]
        ),
        PhotoClueAppRule(
            bundleId: "com.dr1ven.eraser", appName: "Photoroom", appStoreId: 1455009060, urlScheme: nil,
            exactAlbumTitles: ["photoroom"], filenamePrefixes: ["photoroom"], softwareTagTokens: ["photoroom"]
        ),
        PhotoClueAppRule(
            bundleId: "com.frontrow.vlog", appName: "VN Video Editor", appStoreId: 1343581380, urlScheme: nil,
            exactAlbumTitles: ["vn", "vn video editor"], filenamePrefixes: ["vn202", "vn201"], softwareTagTokens: ["vlognow", "vn video"]
        ),
        PhotoClueAppRule(
            bundleId: "com.canva.canvaeditor", appName: "Canva", appStoreId: 897446215, urlScheme: "canva",
            exactAlbumTitles: ["canva"], filenamePrefixes: [], softwareTagTokens: ["canva"]
        ),
        PhotoClueAppRule(
            bundleId: "com.viber", appName: "Viber", appStoreId: 382617920, urlScheme: nil,
            exactAlbumTitles: ["viber"], filenamePrefixes: ["viber_image_", "viber_video_"], softwareTagTokens: []
        ),
        PhotoClueAppRule(
            bundleId: "org.whispersystems.signal", appName: "Signal", appStoreId: 874139669, urlScheme: nil,
            exactAlbumTitles: ["signal"], filenamePrefixes: ["signal-20"], softwareTagTokens: []
        ),
        PhotoClueAppRule(
            bundleId: "com.dji.golite", appName: "DJI Fly", appStoreId: 1479649251, urlScheme: nil,
            exactAlbumTitles: ["dji fly", "dji mimo", "dji album", "dji"], filenamePrefixes: ["dji_fly_", "dji_mimo_"], softwareTagTokens: ["dji fly", "dji mimo", "dji "]
        ),
        PhotoClueAppRule(
            bundleId: "com.gopro.GoPro", appName: "GoPro Quik", appStoreId: 561350520, urlScheme: nil,
            exactAlbumTitles: ["gopro", "gopro quik", "quik"], filenamePrefixes: ["gopr", "gh01", "gx01"], softwareTagTokens: ["gopro"]
        ),
        PhotoClueAppRule(
            bundleId: "com.strava.stravaride", appName: "Strava", appStoreId: 426826309, urlScheme: "strava",
            exactAlbumTitles: ["strava"], filenamePrefixes: ["strava"], softwareTagTokens: ["strava"]
        ),
        PhotoClueAppRule(
            bundleId: "com.tplink.tapo", appName: "TP-Link Tapo", appStoreId: 1472718009, urlScheme: nil,
            exactAlbumTitles: ["tapo", "tp-link tapo"], filenamePrefixes: ["tapo_"], softwareTagTokens: []
        ),
        PhotoClueAppRule(
            bundleId: "com.hikvision.ezviz", appName: "EZVIZ", appStoreId: 886947564, urlScheme: nil,
            exactAlbumTitles: ["ezviz"], filenamePrefixes: ["ezviz_"], softwareTagTokens: []
        ),
        PhotoClueAppRule(
            bundleId: "com.adobe.scan.ios", appName: "Adobe Scan", appStoreId: 1199564834, urlScheme: nil,
            exactAlbumTitles: ["adobe scan"], filenamePrefixes: ["adobe scan"], softwareTagTokens: ["adobe scan"]
        ),
        PhotoClueAppRule(
            bundleId: "com.intsig.CamScanner", appName: "CamScanner", appStoreId: 388624839, urlScheme: nil,
            exactAlbumTitles: ["camscanner"], filenamePrefixes: ["camscanner"], softwareTagTokens: ["camscanner"]
        ),
        PhotoClueAppRule(
            bundleId: "com.reddit.Reddit", appName: "Reddit", appStoreId: 1064216828, urlScheme: "reddit",
            exactAlbumTitles: ["reddit"], filenamePrefixes: [], softwareTagTokens: []
        ),
        PhotoClueAppRule(
            bundleId: "pinterest", appName: "Pinterest", appStoreId: 429047995, urlScheme: "pinterest",
            exactAlbumTitles: ["pinterest"], filenamePrefixes: [], softwareTagTokens: []
        )
    ]

    static func formatSourceLabel(base: String, date: Date?, now: Date = Date()) -> String {
        guard let date else { return base }
        let days = max(0, Int(now.timeIntervalSince(date) / 86_400.0))
        if days == 0 {
            return "\(base) • oggi"
        } else if days <= 90 {
            return "\(base) • \(days)g fa"
        } else {
            return "\(base) • oltre 90g fa"
        }
    }

    private static func record(from rule: PhotoClueAppRule, source: String) -> InstalledAppRecord {
        InstalledAppRecord(
            packageName: rule.bundleId,
            appName: rule.appName,
            appStoreId: rule.appStoreId,
            iconUrl: nil,
            urlScheme: rule.urlScheme,
            detectionSource: source
        )
    }

    static func matchApp(forAlbumTitle title: String, latestDate: Date? = nil, now: Date = Date()) -> InstalledAppRecord? {
        let normalized = title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return nil }
        for rule in rules where rule.exactAlbumTitles.contains(normalized) {
            return record(from: rule, source: formatSourceLabel(base: "da Album Foto", date: latestDate, now: now))
        }
        return nil
    }

    static func matchApp(forMediaFilename fileName: String, assetDate: Date? = nil, now: Date = Date()) -> InstalledAppRecord? {
        let baseName = URL(fileURLWithPath: fileName).lastPathComponent.lowercased()
        guard !baseName.isEmpty else { return nil }
        // Ignora subito nomi generici della fotocamera o registrazioni di sistema
        if baseName.hasPrefix("img_") || baseName.hasPrefix("vid_") || baseName.hasPrefix("rpreplay_") || baseName.hasPrefix("screenshot") {
            return nil
        }
        for rule in rules where rule.filenamePrefixes.contains(where: { baseName.hasPrefix($0) }) {
            return record(from: rule, source: formatSourceLabel(base: "da Foto", date: assetDate, now: now))
        }
        return nil
    }

    static func matchApp(forSoftwareTag software: String, fileDate: Date? = nil, now: Date = Date()) -> InstalledAppRecord? {
        let lower = software.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !lower.isEmpty else { return nil }
        for rule in rules where rule.softwareTagTokens.contains(where: { lower.contains($0) }) {
            return record(from: rule, source: formatSourceLabel(base: "da Metadati Foto", date: fileDate, now: now))
        }
        return nil
    }

    /// Scansiona istantaneamente (senza chiedere nuovi permessi e senza decodificare file pesanti)
    /// gli Album utente e gli ultimi ~600 file del Rullino se il permesso Foto è già attivo.
    static func scanAuthorizedPhotoLibraryClues(maxFilenameScanCount: Int = 600, now: Date = Date()) -> [InstalledAppRecord] {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard status == .authorized || status == .limited else { return [] }

        var found: [InstalledAppRecord] = []
        var seenBundles = Set<String>()

        func appendIfNew(_ candidate: InstalledAppRecord?) {
            guard let candidate else { return }
            let key = candidate.packageName.lowercased()
            guard !seenBundles.contains(key) else { return }
            seenBundles.insert(key)
            found.append(candidate)
        }

        // 1. Album creati automaticamente dalle app in Foto (~10 ms)
        let collections = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .albumRegular, options: nil)
        let latestOpts = PHFetchOptions()
        latestOpts.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        latestOpts.fetchLimit = 1

        collections.enumerateObjects { collection, _, _ in
            guard let title = collection.localizedTitle?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !title.isEmpty else { return }
            // Verifica che la regola esista prima ancora di interrogare gli asset nell'album
            guard let previewRule = matchApp(forAlbumTitle: title) else { return }
            let newestInAlbum = PHAsset.fetchAssets(in: collection, options: latestOpts)
            guard let firstAsset = newestInAlbum.firstObject else { return }
            let datedRecord = matchApp(forAlbumTitle: title, latestDate: firstAsset.creationDate, now: now) ?? previewRule
            appendIfNew(datedRecord)
        }

        // 2. Prefissi file univoci sugli asset più recenti (soli metadati SQLite Photos, nessuna lettura disco)
        if maxFilenameScanCount > 0 {
            let fetchOpts = PHFetchOptions()
            fetchOpts.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            fetchOpts.fetchLimit = maxFilenameScanCount
            let assets = PHAsset.fetchAssets(with: fetchOpts)
            assets.enumerateObjects { asset, _, _ in
                guard let primary = PHAssetResource.assetResources(for: asset).first else { return }
                let fname = primary.originalFilename
                if let matched = matchApp(forMediaFilename: fname, assetDate: asset.creationDate, now: now) {
                    appendIfNew(matched)
                }
            }
        }

        return found
    }

    static func extractSoftwareTagFromImageFile(at fileURL: URL) -> String? {
        guard let source = CGImageSourceCreateWithURL(fileURL as CFURL, nil) else {
            return nil
        }
        if let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] {
            if let tiff = props[kCGImagePropertyTIFFDictionary as String] as? [String: Any],
               let sw = (tiff[kCGImagePropertyTIFFSoftware as String] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !sw.isEmpty {
                return sw
            }
            if let png = props[kCGImagePropertyPNGDictionary as String] as? [String: Any],
               let sw = (png["Software"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !sw.isEmpty {
                return sw
            }
        }
        if let metadata = CGImageSourceCopyMetadataAtIndex(source, 0, nil) {
            var foundSoftware: String? = nil
            let enumOpts = [kCGImageMetadataEnumerateRecursively: true] as CFDictionary
            CGImageMetadataEnumerateTagsUsingBlock(metadata, nil, enumOpts) { _, tag in
                let tagName = (CGImageMetadataTagCopyName(tag) as String?) ?? ""
                if tagName == "Software" || tagName == "CreatorTool",
                   let rawVal = CGImageMetadataTagCopyValue(tag) as? String {
                    let clean = rawVal.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !clean.isEmpty {
                        foundSoftware = clean
                        return false
                    }
                }
                return true
            }
            if let foundSoftware {
                return foundSoftware
            }
        }
        return nil
    }

    static func extractSoftwareTagFromVideoFile(at fileURL: URL) async -> String? {
        let asset = AVURLAsset(url: fileURL)
        guard let common = try? await asset.load(.commonMetadata) else { return nil }
        for item in common {
            guard item.commonKey == .commonKeySoftware || item.commonKey == .commonKeyCreator else { continue }
            if let str = (try? await item.load(.stringValue))?.trimmingCharacters(in: .whitespacesAndNewlines),
               !str.isEmpty {
                return str
            }
        }
        return nil
    }

    /// Analizza a costo zero l'header del file appena esportato durante il trasferimento di foto e video
    /// per ricavare il tag `Software` EXIF/TIFF/QuickTime o il prefisso nome file senza rallentare l'invio.
    static func detectAppFromExportedMediaFile(
        at fileURL: URL,
        originalFilename: String,
        isVideo: Bool,
        creationDate: Date?,
        now: Date = Date()
    ) async -> InstalledAppRecord? {
        let softwareTag: String? = isVideo
            ? await extractSoftwareTagFromVideoFile(at: fileURL)
            : extractSoftwareTagFromImageFile(at: fileURL)
        if let softwareTag, let matched = matchApp(forSoftwareTag: softwareTag, fileDate: creationDate, now: now) {
            return matched
        }
        return matchApp(forMediaFilename: originalFilename, assetDate: creationDate, now: now)
    }
}
