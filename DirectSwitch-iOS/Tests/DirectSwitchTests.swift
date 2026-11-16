import XCTest
import CryptoKit
@testable import DirectSwitch

final class DirectSwitchTests: XCTestCase {

    func testLocalNetworkGuardAcceptsPrivateRanges() {
        for ip in ["10.0.0.5", "172.16.0.1", "172.31.255.254", "192.168.43.1", "169.254.10.2"] {
            XCTAssertTrue(DirectSwitchLocalNetwork.isLocalIPv4(ip), ip)
        }
    }

    func testLocalNetworkGuardRejectsPublicAndMalformed() {
        for ip in ["8.8.8.8", "172.15.0.1", "172.32.0.1", "192.169.1.1", "1.2.3", "192.168.1.256", "abc", "", "192.168.1.1.5"] {
            XCTAssertFalse(DirectSwitchLocalNetwork.isLocalIPv4(ip), ip)
        }
    }

    func testEnvelopeRoundTripAndTamperDetection() throws {
        let keyHex = String(repeating: "ab", count: 32)
        let key = try DirectSwitchCrypto.deriveSessionSymmetricKey(sessionKeyHex: keyHex)
        let sealed = try DirectSwitchCrypto.sealJsonEnvelope("{\"hello\":\"world\"}", key: key)
        XCTAssertEqual(try DirectSwitchCrypto.openJsonEnvelope(sealed, key: key), "{\"hello\":\"world\"}")

        var tampered = sealed
        tampered[tampered.count - 1] ^= 0x01
        XCTAssertThrowsError(try DirectSwitchCrypto.openJsonEnvelope(tampered, key: key))
    }

    func testEmptyStreamCSGCM1AuthenticatesAndRejectsBareHeader() throws {
        let key = try DirectSwitchCrypto.deriveSessionSymmetricKey(sessionKeyHex: String(repeating: "11", count: 32))
        let wrongKey = try DirectSwitchCrypto.deriveSessionSymmetricKey(sessionKeyHex: String(repeating: "22", count: 32))

        let encryptedEmpty = try DirectSwitchCrypto.encryptDataCSGCM1(Data(), key: key)
        XCTAssertGreaterThan(encryptedEmpty.count, 6)
        XCTAssertEqual(try DirectSwitchCrypto.decryptDataCSGCM1(encryptedEmpty, key: key), Data())
        XCTAssertThrowsError(try DirectSwitchCrypto.decryptDataCSGCM1(encryptedEmpty, key: wrongKey))
        XCTAssertThrowsError(try DirectSwitchCrypto.decryptDataCSGCM1(Data("CSGCM1".utf8), key: key))
    }

    func testFileStreamingCSGCM1RoundTripAndEmptyFile() throws {
        let key = try DirectSwitchCrypto.deriveSessionSymmetricKey(sessionKeyHex: String(repeating: "cd", count: 32))
        let tempDir = FileManager.default.temporaryDirectory
        let inURL = tempDir.appendingPathComponent("ds_test_in_\(UUID().uuidString).bin")
        let encURL = tempDir.appendingPathComponent("ds_test_enc_\(UUID().uuidString).csgcm1")
        let outURL = tempDir.appendingPathComponent("ds_test_out_\(UUID().uuidString).bin")
        defer {
            try? FileManager.default.removeItem(at: inURL)
            try? FileManager.default.removeItem(at: encURL)
            try? FileManager.default.removeItem(at: outURL)
        }

        // Test multi-blocco (> 4 MiB)
        let payload = Data((0..<(4 * 1024 * 1024 + 12345)).map { UInt8($0 & 0xff) })
        try payload.write(to: inURL)
        let (encPlainBytes, encSha) = try DirectSwitchCrypto.encryptFileCSGCM1(inputURL: inURL, outputURL: encURL, key: key)
        let (decPlainBytes, decSha) = try DirectSwitchCrypto.decryptFileCSGCM1(inputURL: encURL, outputURL: outURL, key: key)

        XCTAssertEqual(encPlainBytes, Int64(payload.count))
        XCTAssertEqual(decPlainBytes, Int64(payload.count))
        XCTAssertEqual(encSha, decSha)
        XCTAssertEqual(try Data(contentsOf: outURL), payload)

        // Test file da 0 byte
        try Data().write(to: inURL)
        let (zeroEncLen, zeroEncSha) = try DirectSwitchCrypto.encryptFileCSGCM1(inputURL: inURL, outputURL: encURL, key: key)
        let (zeroDecLen, zeroDecSha) = try DirectSwitchCrypto.decryptFileCSGCM1(inputURL: encURL, outputURL: outURL, key: key)
        XCTAssertEqual(zeroEncLen, 0)
        XCTAssertEqual(zeroDecLen, 0)
        XCTAssertEqual(zeroEncSha, zeroDecSha)
    }

    func testOddAndMalformedHexReturnsNilWithoutCrashing() {
        XCTAssertNil(Data(fromHex: "abc"))
        XCTAssertNil(Data(fromHex: "zzzz"))
        XCTAssertEqual(Data(fromHex: "0a1b"), Data([0x0a, 0x1b]))
    }

    func testPublicBeaconStripsSessionKeyAndWifiPassword() throws {
        let qr = QrPairingPayload(
            sessionId: "ds_test_beacon",
            receiverName: "iPhone 16 Pro",
            receiverPlatform: .IOS,
            ips: ["192.168.1.20"],
            port: 49443,
            sessionKeyHex: String(repeating: "ef", count: 32),
            wifiSsid: "AndroidShare_5G",
            wifiPass: "SuperSecretPass",
            receiverHasPro: true
        )
        let beaconJson = qr.toPublicBeacon().toCompactJson()
        XCTAssertFalse(beaconJson.contains("sessionKeyHex"))
        XCTAssertFalse(beaconJson.contains("efefefef"))
        XCTAssertFalse(beaconJson.contains("SuperSecretPass"))

        let parsed = try DiscoveryBeaconPayload.fromJson(beaconJson)
        XCTAssertEqual(parsed.sessionId, "ds_test_beacon")
        XCTAssertEqual(parsed.receiverPlatform, .IOS)
    }

    func testPinKeyDerivationRoundTripAndWrongPinFails() throws {
        let rightKey = try DirectSwitchCrypto.derivePinSymmetricKey(sessionId: "ds_pin_01", pin: "482910")
        let wrongKey = try DirectSwitchCrypto.derivePinSymmetricKey(sessionId: "ds_pin_01", pin: "482911")
        let sealed = try DirectSwitchCrypto.sealJsonEnvelope("{\"sessionId\":\"ds_pin_01\"}", key: rightKey)

        XCTAssertEqual(try DirectSwitchCrypto.openJsonEnvelope(sealed, key: rightKey), "{\"sessionId\":\"ds_pin_01\"}")
        XCTAssertThrowsError(try DirectSwitchCrypto.openJsonEnvelope(sealed, key: wrongKey))
    }

    func testConstantTimeTokenComparison() {
        let tok = DirectSwitchCrypto.randomTokenHex(byteCount: 16)
        XCTAssertEqual(tok.count, 32)
        XCTAssertTrue(DirectSwitchCrypto.constantTimeEquals(tok, tok))
        XCTAssertFalse(DirectSwitchCrypto.constantTimeEquals(tok, "00000000000000000000000000000000"))
        XCTAssertFalse(DirectSwitchCrypto.constantTimeEquals("", ""))
        XCTAssertFalse(DirectSwitchCrypto.constantTimeEquals(tok, "short"))
    }

    func testLicenseSingleSideUnlockAndPreviewCap() {
        XCTAssertEqual(
            LicensePolicyEvaluator.resolveTier(
                senderPlatform: .IOS,
                receiverPlatform: .IOS,
                senderHasPro: false,
                receiverHasPro: false
            ),
            .INTRA_OS_FREE
        )
        XCTAssertEqual(
            LicensePolicyEvaluator.resolveTier(
                senderPlatform: .ANDROID,
                receiverPlatform: .IOS,
                senderHasPro: true,
                receiverHasPro: false
            ),
            .CROSS_OS_PRO_UNLOCKED
        )
        XCTAssertEqual(
            LicensePolicyEvaluator.resolveTier(
                senderPlatform: .IOS,
                receiverPlatform: .ANDROID,
                senderHasPro: false,
                receiverHasPro: false
            ),
            .CROSS_OS_PREVIEW
        )

        var sampleItems: [ManifestItem] = []
        for i in 0..<30 {
            sampleItems.append(
                ManifestItem(
                    id: "p_\(i)",
                    category: .PHOTOS,
                    fileName: "IMG_\(i).HEIC",
                    sizeBytes: 1024,
                    dedupKey: "k_\(i)"
                )
            )
        }
        sampleItems.append(
            ManifestItem(
                id: "doc_1",
                category: .DOCUMENTS,
                fileName: "contratto.pdf",
                sizeBytes: 2048,
                dedupKey: "d_1"
            )
        )
        sampleItems.append(
            ManifestItem(
                id: "wa_1",
                category: .WHATSAPP_VAULT,
                fileName: "WhatsApp_Chat.zip",
                sizeBytes: 4096,
                dedupKey: "w_1"
            )
        )
        let (allowed, gated) = LicensePolicyEvaluator.filterItemsForTier(sampleItems, tier: .CROSS_OS_PREVIEW)
        XCTAssertEqual(allowed.count, 26)
        XCTAssertTrue(allowed.contains(where: { $0.id == "wa_1" }))
        XCTAssertEqual(gated, 6)
    }

    func testPhoneNormalizerAndPhotoMimeMapping() {
        XCTAssertEqual(PhoneNormalizer.normalizeKey("+39 333 123 4567"), PhoneNormalizer.normalizeKey("3331234567"))
        XCTAssertEqual(iOSPhotoKitMigrator.mimeTypeForFileName("IMG_0012.HEIC", isVideo: false), "image/heic")
        XCTAssertEqual(iOSPhotoKitMigrator.mimeTypeForFileName("CLIP_4K.MOV", isVideo: true), "video/quicktime")
        XCTAssertEqual(iOSPhotoKitMigrator.mimeTypeForFileName("VID_01.mp4", isVideo: true), "video/mp4")
    }

    func testTransferManifestNativeWhatsAppMigrationFlagAndLegacyCompat() throws {
        let manifest = TransferManifest(
            sessionId: "ds_wa_sync",
            senderPlatform: .IOS,
            items: [],
            requestNativeWhatsAppMigration: true
        )
        let encoded = try JSONEncoder().encode(manifest)
        let decoded = try JSONDecoder().decode(TransferManifest.self, from: encoded)
        XCTAssertEqual(decoded.requestNativeWhatsAppMigration, true)

        let legacyJson = Data(#"{"sessionId":"ds_old","senderPlatform":"ANDROID","items":[]}"#.utf8)
        let legacyDecoded = try JSONDecoder().decode(TransferManifest.self, from: legacyJson)
        XCTAssertNil(legacyDecoded.requestNativeWhatsAppMigration)
        XCTAssertNil(legacyDecoded.installedAppsPayload)
    }

    func testDiscoveryBeaconDeduplicatesSamePhysicalDeviceAcrossSessionRotation() {
        let oldBeacon = DiscoveryBeaconPayload(
            sessionId: "ds_session_old",
            receiverName: "iPhone",
            receiverPlatform: .IOS,
            ips: ["192.168.1.42"],
            port: 49443
        )
        let rotatedBeacon = DiscoveryBeaconPayload(
            sessionId: "ds_session_new",
            receiverName: "iPhone",
            receiverPlatform: .IOS,
            ips: ["192.168.1.42"],
            port: 49443
        )
        let distinctPhoneBeacon = DiscoveryBeaconPayload(
            sessionId: "ds_session_second_phone",
            receiverName: "iPhone",
            receiverPlatform: .IOS,
            ips: ["192.168.1.99"],
            port: 49443
        )

        XCTAssertTrue(rotatedBeacon.representsSameDevice(as: oldBeacon))
        XCTAssertFalse(distinctPhoneBeacon.representsSameDevice(as: oldBeacon))
    }

    func testInstalledAppsCatalogManifestRoundTripAndZeroBytesFormat() throws {
        let apps = [
            InstalledAppRecord(packageName: "com.whatsapp", appName: "WhatsApp"),
            InstalledAppRecord(packageName: "com.spotify.music", appName: "Spotify")
        ]
        let manifest = TransferManifest(
            sessionId: "ds_apps_sync",
            senderPlatform: .ANDROID,
            items: [],
            installedAppsPayload: apps
        )
        let encoded = try JSONEncoder().encode(manifest)
        let decoded = try JSONDecoder().decode(TransferManifest.self, from: encoded)
        XCTAssertEqual(decoded.installedAppsPayload, apps)
        XCTAssertEqual(DirectSwitchUIHelpers.formatBytes(0), "0 MB")
    }

    func testRichZeroCloudiOSPayloadRoundTrip() throws {
        let richContact = ContactTransferRecord(
            id: "c_1",
            displayName: "Mario Rossi",
            phones: ["+393331112233"],
            emails: ["mario@example.it"],
            organization: "Studio Rossi",
            givenName: "Mario",
            familyName: "Rossi",
            nickname: "Marietto",
            jobTitle: "Architetto",
            birthdayYear: 1988,
            birthdayMonth: 5,
            birthdayDay: 14,
            labeledPhones: [LabeledValueRecord(label: "iphone", value: "+393331112233")],
            labeledEmails: [LabeledValueRecord(label: "work", value: "mario@example.it")],
            urls: ["https://studiorossi.it"],
            postalAddresses: [
                PostalAddressTransferRecord(
                    label: "work",
                    street: "Via Roma 10",
                    city: "Milano",
                    state: "MI",
                    postalCode: "20121",
                    country: "Italia"
                )
            ],
            avatarJpegBase64: Data([0xff, 0xd8, 0xff, 0xd9]).base64EncodedString()
        )

        let richCalendar = CalendarEventRecord(
            id: "ev_1",
            title: "Compleanno Giulia",
            description: "Festa",
            location: "Milano",
            startEpochMillis: 1_760_000_000_000,
            endEpochMillis: 1_760_003_600_000,
            allDay: true,
            calendarTitle: "Famiglia",
            recurrenceFrequency: "yearly",
            recurrenceInterval: 1,
            alarmOffsetSeconds: -3600
        )

        let reminder = ReminderTransferRecord(
            id: "rem_1",
            title: "Pagare F24",
            notes: "Entro il 16",
            listName: " Casa ",
            isCompleted: false,
            priority: 1,
            dueEpochMillis: 1_760_500_000_000
        )

        let livePhotoItem = ManifestItem(
            id: "photos_0",
            category: .PHOTOS,
            fileName: "IMG_2048.HEIC",
            relativeAlbumOrFolder: "Vacanze Sardegna",
            sizeBytes: 3_145_728,
            capturedEpochMillis: 1_755_000_000_000,
            dedupKey: "img_2048.heic_3145728_1755000000000",
            mimeType: "image/heic",
            isFavorite: true,
            latitude: 41.1171,
            longitude: 9.5332,
            isLivePhoto: true,
            livePhotoVideoFileName: "IMG_2048.MOV"
        )

        let manifest = TransferManifest(
            sessionId: "ds_ios_full",
            senderPlatform: .IOS,
            items: [livePhotoItem],
            contactsPayload: [richContact],
            calendarsPayload: [richCalendar],
            remindersPayload: [reminder],
            requestNativeWhatsAppMigration: true
        )

        let data = try JSONEncoder().encode(manifest)
        let decoded = try JSONDecoder().decode(TransferManifest.self, from: data)

        XCTAssertEqual(decoded.contactsPayload.first?.birthdayYear, 1988)
        XCTAssertEqual(decoded.contactsPayload.first?.postalAddresses?.first?.city, "Milano")
        XCTAssertEqual(decoded.contactsPayload.first?.labeledPhones?.first?.label, "iphone")
        XCTAssertEqual(decoded.calendarsPayload.first?.recurrenceFrequency, "yearly")
        XCTAssertEqual(decoded.calendarsPayload.first?.alarmOffsetSeconds, -3600)
        XCTAssertEqual(decoded.remindersPayload, [reminder])
        XCTAssertEqual(decoded.items.first?.isLivePhoto, true)
        XCTAssertEqual(decoded.items.first?.livePhotoVideoFileName, "IMG_2048.MOV")
        XCTAssertEqual(decoded.items.first?.isFavorite, true)
        XCTAssertEqual(decoded.items.first?.latitude, 41.1171)
    }

    func testRecursiveFolderImportAndPasswordCsvDetection() throws {
        XCTAssertTrue(iOSDocumentsSandboxBridge.isPasswordsCsvFile("SafariPasswords.csv"))
        XCTAssertTrue(iOSDocumentsSandboxBridge.isPasswordsCsvFile("PASSWORDS_APPLE.CSV"))
        XCTAssertFalse(iOSDocumentsSandboxBridge.isPasswordsCsvFile("contratto.pdf"))

        XCTAssertEqual(
            iOSDocumentsSandboxBridge.sanitizedRelativeComponents("../Progetti/2026\\Fatture/./"),
            ["Progetti", "2026", "Fatture"]
        )

        let rootFolder = FileManager.default.temporaryDirectory
            .appendingPathComponent("DirectSwitchFolderTest_\(UUID().uuidString)", isDirectory: true)
        let nestedSub = rootFolder.appendingPathComponent("Fatture/2026", isDirectory: true)
        try FileManager.default.createDirectory(at: nestedSub, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: rootFolder)
            iOSDocumentsSandboxBridge.clearStagedVault()
        }

        let pdfURL = nestedSub.appendingPathComponent("fattura_01.pdf")
        let audioURL = rootFolder.appendingPathComponent("memo_vocale.m4a")
        try Data("PDF_CONTENT".utf8).write(to: pdfURL)
        try Data("AUDIO_CONTENT".utf8).write(to: audioURL)

        let staged = iOSDocumentsSandboxBridge.importPickedDocumentURLs([rootFolder])
        XCTAssertEqual(staged.count, 2)

        let byName = Dictionary(uniqueKeysWithValues: staged.map { ($0.0.fileName, $0.0) })
        XCTAssertNotNil(byName["fattura_01.pdf"])
        XCTAssertNotNil(byName["memo_vocale.m4a"])
        XCTAssertTrue(byName["fattura_01.pdf"]?.relativeAlbumOrFolder.hasSuffix("Fatture/2026") == true)
        XCTAssertEqual(byName["memo_vocale.m4a"]?.mimeType, "audio/mp4")

        XCTAssertEqual(iOSBackgroundTransferKeepAlive.bgTaskIdentifier, "com.directswitch.ios.transfer.keepalive")
    }

    func testDeterministicAssetManifestIdIsUrlSafeAcrossNewScreenshots() {
        let rawLocalId = "B84E8479-475C-4727-A4A4-B77AA9980897/L0/001"
        let idBeforeNewScreenshot = iOSPhotoKitMigrator.stableManifestItemId(
            localIdentifier: rawLocalId,
            category: .PHOTOS,
            fallbackIndex: 4354
        )
        let idAfterNewScreenshot = iOSPhotoKitMigrator.stableManifestItemId(
            localIdentifier: rawLocalId,
            category: .PHOTOS,
            fallbackIndex: 4355
        )
        XCTAssertEqual(idBeforeNewScreenshot, idAfterNewScreenshot)
        XCTAssertEqual(idBeforeNewScreenshot, "photos_B84E8479-475C-4727-A4A4-B77AA9980897_L0_001")
        XCTAssertNotNil(URL(string: "http://192.168.1.20:49443/v1/item/\(idBeforeNewScreenshot)"))

        let fallbackId = iOSPhotoKitMigrator.stableManifestItemId(
            localIdentifier: "",
            category: .VIDEOS,
            fallbackIndex: 99
        )
        XCTAssertEqual(fallbackId, "videos_99")
    }

    func testRichAppCatalogMetadataOcrFilteringAndWhatsAppPersonalSeparation() throws {
        // Verifica rispetto rigoroso del tetto Apple di 50 schemi totali in Info.plist
        XCTAssertLessThanOrEqual(iOSInstalledAppsScanner.knownProbes.count, 48)

        let personalProbe = iOSInstalledAppsScanner.knownProbes.first { $0.bundleId == "net.whatsapp.WhatsApp" }
        let businessProbe = iOSInstalledAppsScanner.knownProbes.first { $0.bundleId == "net.whatsapp.WhatsAppSMB" }
        XCTAssertEqual(personalProbe?.urlScheme, "whatsapp-consumer")
        XCTAssertEqual(personalProbe?.appStoreId, 310633997)
        XCTAssertEqual(businessProbe?.urlScheme, "whatsapp-smb")
        XCTAssertEqual(businessProbe?.appStoreId, 1386412985)

        let richApp = InstalledAppRecord(
            packageName: "com.spotify.client",
            appName: "Spotify",
            appStoreId: 324684580,
            iconUrl: "https://is1-ssl.mzstatic.com/image/thumb/icon100.jpg",
            urlScheme: "spotify"
        )
        let encoded = try JSONEncoder().encode([richApp])
        let decoded = try JSONDecoder().decode([InstalledAppRecord].self, from: encoded)
        XCTAssertEqual(decoded.first?.appStoreId, 324684580)
        XCTAssertEqual(decoded.first?.urlScheme, "spotify")

        // Retrocompatibilità JSON Android privo dei campi opzionali iOS
        let androidAppsJson = Data(#"[{"packageName":"com.instagram.android","appName":"Instagram"}]"#.utf8)
        let androidDecoded = try JSONDecoder().decode([InstalledAppRecord].self, from: androidAppsJson)
        XCTAssertEqual(androidDecoded.first?.packageName, "com.instagram.android")
        XCTAssertNil(androidDecoded.first?.appStoreId)

        // Filtro OCR screenshot Home / Impostazioni -> App
        let rawOcr = ["21:34", "87%", "5G", "Impostazioni", "Safari", "Mail", "Intesa Sanpaolo", "Spotify", "Aruba PEC", "Spotify"]
        let filtered = iOSInstalledAppsScanner.filterPlausibleAppNames(rawOcr)
        XCTAssertEqual(filtered, ["Intesa Sanpaolo", "Spotify", "Aruba PEC"])

        XCTAssertEqual(
            iOSAppStoreCatalogResolver.sanitizeIconUrl("http://is1.mzstatic.com/icon.png"),
            "https://is1.mzstatic.com/icon.png"
        )
    }

    func testActiveTransferScopeIsolationAndRepeatableHandshakeRoundTrip() throws {
        let waOnly = ActiveTransferScope(whatsApp: true)
        XCTAssertTrue(waOnly.isWhatsAppOnly)
        XCTAssertFalse(waOnly.hasAnyStandardDataCategory)

        let appsOnly = ActiveTransferScope(apps: true)
        XCTAssertTrue(appsOnly.isAppsOnly)
        XCTAssertTrue(appsOnly.hasAnyStandardDataCategory)
        XCTAssertFalse(appsOnly.isWhatsAppOnly)

        let hs = HandshakeRequest(
            sessionId: "ds_repeat_01",
            senderName: "iPhone Vecchio",
            senderPlatform: .IOS,
            senderHasPro: true,
            totalEstimatedBytes: 0,
            isResume: false,
            transferScope: waOnly
        )
        let hsData = try JSONEncoder().encode(hs)
        let hsDecoded = try JSONDecoder().decode(HandshakeRequest.self, from: hsData)
        XCTAssertEqual(hsDecoded.isResume, false)
        XCTAssertEqual(hsDecoded.transferScope, waOnly)

        let manifestOnlyApps = TransferManifest(
            sessionId: "ds_repeat_02",
            senderPlatform: .IOS,
            items: [],
            installedAppsPayload: [InstalledAppRecord(packageName: "com.spotify.client", appName: "Spotify")],
            requestNativeWhatsAppMigration: false
        )
        let inferred = ActiveTransferScope.inferred(from: manifestOnlyApps)
        XCTAssertTrue(inferred.isAppsOnly)
        XCTAssertFalse(inferred.contacts)
        XCTAssertFalse(inferred.photos)
        XCTAssertFalse(inferred.whatsApp)
    }

    @MainActor
    func testFastOverlayAppInstallerQueueAndBackNavigation() {
        let installer = iOSSequentialAppInstaller()
        installer.dryRunPresentationForTesting = true

        let sampleApps = [
            InstalledAppRecord(packageName: "com.test.alpha", appName: "Alpha", appStoreId: 100001),
            InstalledAppRecord(packageName: "com.test.beta", appName: "Beta", appStoreId: 100002),
            InstalledAppRecord(packageName: "com.test.gamma", appName: "Gamma", appStoreId: 100003)
        ]

        installer.configure(with: sampleApps)
        XCTAssertEqual(installer.pendingInstallableCount, 3)

        installer.startAutomaticSequence()
        XCTAssertTrue(installer.isRunningSequence)
        XCTAssertTrue(installer.showsFloatingBottomBar)
        XCTAssertEqual(installer.currentQueuePosition, 1)
        XCTAssertEqual(installer.totalQueueCount, 3)
        XCTAssertEqual(installer.currentActiveApp?.packageName, "com.test.alpha")
        XCTAssertFalse(installer.canGoBackInQueue)

        // Conferma 1ª app -> passa subito alla 2ª nello stesso banner in basso
        installer.confirmCurrentAndAdvance()
        XCTAssertEqual(installer.currentQueuePosition, 2)
        XCTAssertEqual(installer.currentActiveApp?.packageName, "com.test.beta")
        XCTAssertTrue(installer.completedIds.contains("com.test.alpha"))
        XCTAssertTrue(installer.canGoBackInQueue)

        // Torna indietro alla 1ª app se si era premuto Prossima troppo presto
        installer.goBackToPreviousApp()
        XCTAssertEqual(installer.currentQueuePosition, 1)
        XCTAssertEqual(installer.currentActiveApp?.packageName, "com.test.alpha")
        XCTAssertFalse(installer.completedIds.contains("com.test.alpha"))

        // Avanza fino a fine coda
        installer.confirmCurrentAndAdvance() // -> Beta
        installer.skipCurrentAndContinue()   // salta Beta -> Gamma
        XCTAssertEqual(installer.currentActiveApp?.packageName, "com.test.gamma")
        XCTAssertFalse(installer.completedIds.contains("com.test.beta"))

        installer.confirmCurrentAndAdvance() // fine coda -> chiusura automatica pulita
        XCTAssertFalse(installer.isRunningSequence)
        XCTAssertFalse(installer.showsFloatingBottomBar)
        XCTAssertNil(installer.currentActiveApp)
        XCTAssertTrue(installer.completedIds.contains("com.test.gamma"))
    }

    func testAutoScrollScreenshotFilterHandlesOver100AppsAndIgnoresSystemLabels() {
        var ocrLines = [
            "App di default", "App nascoste", "348,2 MB", "1.24 GB", "Ultimo utilizzo: ieri",
            "Registrazione schermo", "BANCOMAT", "NexiPay", "Ryanair", "Klarna", "Speedtest", "Shelly", "EZVIZ"
        ]
        for idx in 1...110 {
            ocrLines.append("CustomApp\(idx)")
        }
        let filtered = iOSInstalledAppsScanner.filterPlausibleAppNames(ocrLines)
        XCTAssertEqual(filtered.count, 117)
        XCTAssertTrue(filtered.contains("BANCOMAT"))
        XCTAssertTrue(filtered.contains("NexiPay"))
        XCTAssertTrue(filtered.contains("Ryanair"))
        XCTAssertFalse(filtered.contains("App di default"))
        XCTAssertFalse(filtered.contains("348,2 MB"))
        XCTAssertFalse(filtered.contains("1.24 GB"))
    }

    @MainActor
    func testLiveCameraAppStabilizerTruncatedLabelsAndRemoteScannerProtocol() throws {
        // 1. Etichette troncate dalla schermata Home di iOS (`…`) e alias brevi italiani
        let truncatedBank = iOSInstalledAppsScanner.cleanHomeScreenAppLabel("Intesa Sanpa…")
        XCTAssertEqual(truncatedBank.cleaned, "Intesa Sanpa")
        XCTAssertTrue(truncatedBank.wasTruncated)
        XCTAssertEqual(
            iOSInstalledAppsScanner.canonicalAppQuery(for: "Intesa Sanpa…"),
            "Intesa Sanpaolo Mobile"
        )
        XCTAssertEqual(iOSInstalledAppsScanner.canonicalAppQuery(for: "NexiPay"), "Nexi Pay")
        XCTAssertEqual(iOSInstalledAppsScanner.canonicalAppQuery(for: "Maps"), "Google Maps")

        // 2. Stabilizzatore multi-fotogramma della fotocamera live:
        //    - richiede SEMPRE almeno 2 fotogrammi coerenti per qualsiasi candidato (zero falsi positivi da sfocatura/movimento)
        //    - scarta rumore transitorio da movimento (1 solo frame), categorie, date calendario, barra di stato e pulsanti 2 lettere
        //    - conferma al 2° fotogramma coerente senza mai riemettere duplicati ai fotogrammi successivi
        var stabilizer = LiveCameraCandidateStabilizer()
        let frame1 = stabilizer.ingestFrameLines([
            "BANCOMAT", "Instagrx", "ClasseViva", "Produttività e finanza", "18°", "GIO 12", "Iliad IT", "Lavoro", "PRO", "Nessun evento"
        ])
        XCTAssertTrue(frame1.isEmpty)

        let frame2 = stabilizer.ingestFrameLines([
            "BANCOMAT", "ClasseViva", "Ryanair", "Giochi", "21°C", "OK", "A B C"
        ])
        XCTAssertEqual(frame2, ["BANCOMAT", "ClasseViva"])

        let frame3 = stabilizer.ingestFrameLines([
            "BANCOMAT", "ClasseViva", "Ryanair"
        ])
        XCTAssertEqual(frame3, ["Ryanair"])

        let frame4 = stabilizer.ingestFrameLines([
            "BANCOMAT", "ClasseViva", "Ryanair"
        ])
        XCTAssertTrue(frame4.isEmpty)

        // 3. Protocollo cifrato AES-GCM per apertura/sincronizzazione fotocamera live sul nuovo iPhone + deduplica
        let keyHex = DirectSwitchCrypto.generateSessionKeyHex()
        let symKey = try DirectSwitchCrypto.deriveSessionSymmetricKey(sessionKeyHex: keyHex)

        let seedApp = InstalledAppRecord(packageName: "com.spotify.client", appName: "Spotify", appStoreId: 324684580)
        let startReq = RemoteAppScannerStartRequest(
            sessionId: "sess-live-scan",
            senderName: "iPhone Vecchio",
            seedApps: [seedApp],
            replaceExisting: true
        )
        let startJson = String(data: try JSONEncoder().encode(startReq), encoding: .utf8)!
        let sealedStart = try DirectSwitchCrypto.sealJsonEnvelope(startJson, key: symKey)
        let openedStart = try DirectSwitchCrypto.openJsonEnvelope(sealedStart, key: symKey)
        let decodedStart = try JSONDecoder().decode(RemoteAppScannerStartRequest.self, from: Data(openedStart.utf8))
        XCTAssertEqual(decodedStart, startReq)

        let scannedApp = InstalledAppRecord(packageName: "eu.spaggiari.classeviva", appName: "ClasseViva", appStoreId: 948135147)
        let duplicateSeed = InstalledAppRecord(packageName: "COM.SPOTIFY.CLIENT", appName: "Spotify", appStoreId: 324684580)
        let merged = DirectSwitchTransportViewModel.mergeUniqueApps([seedApp], [duplicateSeed, scannedApp])
        XCTAssertEqual(merged.count, 2)

        let statusResp = RemoteAppScannerStatusResponse(
            isScannerOpen: false,
            isCompleted: true,
            senderName: "iPhone Vecchio",
            discoveredApps: merged
        )
        let statusJson = String(data: try JSONEncoder().encode(statusResp), encoding: .utf8)!
        let sealedStatus = try DirectSwitchCrypto.sealJsonEnvelope(statusJson, key: symKey)
        let openedStatus = try DirectSwitchCrypto.openJsonEnvelope(sealedStatus, key: symKey)
        let decodedStatus = try JSONDecoder().decode(RemoteAppScannerStatusResponse.self, from: Data(openedStatus.utf8))
        XCTAssertEqual(decodedStatus, statusResp)

        // 4. Append dinamico sul Ricevente nella coda `SKOverlay`
        let installer = iOSSequentialAppInstaller()
        installer.dryRunPresentationForTesting = true
        installer.configure(with: [seedApp])
        installer.appendAdditionalApps([scannedApp, duplicateSeed])
        XCTAssertEqual(installer.apps.count, 2)
        XCTAssertTrue(installer.selectedIds.contains(scannedApp.id))
    }

    func testZeroHallucinationTitleMatcherAndSpatialBoundingBoxParser() {
        // 1. Verifica rigorosa titoli App Store: rifiuta parole generiche/sottotitoli, accetta titoli veri e troncamenti Home
        XCTAssertFalse(
            iOSAppStoreCatalogResolver.isVerifiedAppStoreTitleMatch(
                candidateQuery: "IO",
                wasTruncated: false,
                storeAppName: "Pioggia prevista"
            )
        )
        XCTAssertFalse(
            iOSAppStoreCatalogResolver.isVerifiedAppStoreTitleMatch(
                candidateQuery: "Lavoro",
                wasTruncated: false,
                storeAppName: "InfoJobs - Offerte di Lavoro"
            )
        )
        XCTAssertFalse(
            iOSAppStoreCatalogResolver.isVerifiedAppStoreTitleMatch(
                candidateQuery: "PRO",
                wasTruncated: false,
                storeAppName: "PRO - Fitness Tracker"
            )
        )
        XCTAssertFalse(
            iOSAppStoreCatalogResolver.isVerifiedAppStoreTitleMatch(
                candidateQuery: "Condividi",
                wasTruncated: false,
                storeAppName: "Condividi Spese"
            )
        )

        XCTAssertTrue(
            iOSAppStoreCatalogResolver.isVerifiedAppStoreTitleMatch(
                candidateQuery: "Subito",
                wasTruncated: false,
                storeAppName: "Subito - Annunci e shopping"
            )
        )
        XCTAssertTrue(
            iOSAppStoreCatalogResolver.isVerifiedAppStoreTitleMatch(
                candidateQuery: "Banca Mediol",
                wasTruncated: true,
                storeAppName: "Banca Mediolanum"
            )
        )
        XCTAssertTrue(
            iOSAppStoreCatalogResolver.isVerifiedAppStoreTitleMatch(
                candidateQuery: "Too Good To",
                wasTruncated: true,
                storeAppName: "Too Good To Go: End Food Waste"
            )
        )
        XCTAssertTrue(
            iOSAppStoreCatalogResolver.isVerifiedAppStoreTitleMatch(
                candidateQuery: "ClasseViva",
                wasTruncated: false,
                storeAppName: "ClasseViva Studenti"
            )
        )
        XCTAssertTrue(
            iOSAppStoreCatalogResolver.isVerifiedAppStoreTitleMatch(
                candidateQuery: "Claude",
                wasTruncated: false,
                storeAppName: "Claude by Anthropic"
            )
        )
        XCTAssertTrue(
            iOSAppStoreCatalogResolver.isVerifiedAppStoreTitleMatch(
                candidateQuery: "Disney+",
                wasTruncated: false,
                storeAppName: "Disney+"
            )
        )

        // 2. Filtro candidati: accetta etichette vere incluse sigle note (`IO`, `H&M`, `N26`), scarta date/UI/A-Z bar
        let parsed = iOSInstalledAppsScanner.parsePlausibleAppCandidates([
            "Aruba PEC", "Intesa Sanpa…", "IO", "H&M", "N26",
            "GIO 12", "GIO 12 NOV", "12 NOV", "OK", "AM", "PM", "A B C",
            "Iliad IT", "TIM 5G", "Raccolta smart", "Cerca app", "Istruzione"
        ])
        XCTAssertEqual(parsed.map(\.cleaned), ["Aruba PEC", "Intesa Sanpa", "IO", "H&M", "N26"])
        XCTAssertEqual(parsed.first(where: { $0.cleaned == "Intesa Sanpa" })?.wasTruncated, true)

        // 3. OCR spaziale: taglia barra di stato (y > 0.942), unisce etichette centrate su 2 righe sotto la stessa icona,
        //    mantiene separate icone affiancate e NON fonde righe consecutive allineate a sinistra dell'elenco A–Z
        let boxes: [RecognizedAppTextBox] = [
            RecognizedAppTextBox(text: "Iliad IT", boundingBox: CGRect(x: 0.06, y: 0.96, width: 0.14, height: 0.016), confidence: 0.99),
            RecognizedAppTextBox(text: "Intesa", boundingBox: CGRect(x: 0.11, y: 0.78, width: 0.08, height: 0.015), confidence: 0.98),
            RecognizedAppTextBox(text: "Sanpaolo", boundingBox: CGRect(x: 0.09, y: 0.758, width: 0.12, height: 0.015), confidence: 0.98),
            RecognizedAppTextBox(text: "Subito", boundingBox: CGRect(x: 0.35, y: 0.78, width: 0.09, height: 0.015), confidence: 0.98),
            RecognizedAppTextBox(text: "Vinted", boundingBox: CGRect(x: 0.60, y: 0.78, width: 0.09, height: 0.015), confidence: 0.98),
            RecognizedAppTextBox(text: "Aruba PEC", boundingBox: CGRect(x: 0.20, y: 0.50, width: 0.16, height: 0.018), confidence: 0.99),
            RecognizedAppTextBox(text: "ASOS", boundingBox: CGRect(x: 0.20, y: 0.468, width: 0.08, height: 0.018), confidence: 0.99)
        ]
        let spatialLines = iOSInstalledAppsScanner.mergeAndSplitSpatialTextBoxes(boxes, stripTopStatusBar: true)
        XCTAssertFalse(spatialLines.contains("Iliad IT"))
        XCTAssertEqual(spatialLines, ["Intesa Sanpaolo", "Subito", "Vinted", "Aruba PEC", "ASOS"])
    }

    @MainActor
    func testSequentialInstallerExcludesMissingCatalogNeverAutoLoopsOnForegroundAndStopsCleanly() {
        let installer = iOSSequentialAppInstaller()
        installer.dryRunPresentationForTesting = true

        let catalogApps = [
            InstalledAppRecord(packageName: "com.test.first", appName: "FirstApp", appStoreId: 111001),
            InstalledAppRecord(packageName: "scan.missing.one", appName: "UnmatchedApp", appStoreId: nil),
            InstalledAppRecord(packageName: "com.test.second", appName: "SecondApp", appStoreId: 222002),
            InstalledAppRecord(packageName: "scan.zero.id", appName: "ZeroIdApp", appStoreId: 0)
        ]

        installer.configure(with: catalogApps)

        XCTAssertEqual(installer.queueableApps.map(\.packageName), ["com.test.first", "com.test.second"])
        XCTAssertEqual(installer.missingCatalogApps.map(\.packageName), ["scan.missing.one", "scan.zero.id"])
        XCTAssertFalse(installer.selectedIds.contains("scan.missing.one"))
        XCTAssertFalse(installer.selectedIds.contains("scan.zero.id"))

        installer.startAutomaticSequence()
        XCTAssertEqual(installer.totalQueueCount, 2)
        XCTAssertTrue(installer.isRunningSequence)
        XCTAssertTrue(installer.showsFloatingBottomBar)
        XCTAssertEqual(installer.currentActiveApp?.packageName, "com.test.first")

        installer.confirmCurrentAndAdvance()
        XCTAssertTrue(installer.activeDownloadingIds.contains("com.test.first"))
        XCTAssertEqual(installer.currentActiveApp?.packageName, "com.test.second")

        // Il ritorno in primo piano non deve mai avanzare o aprire un App Store esterno da solo
        installer.handleSceneBecameActive()
        XCTAssertTrue(installer.isRunningSequence)
        XCTAssertEqual(installer.currentActiveApp?.packageName, "com.test.second")

        // Il tasto Interrompi ferma istantaneamente la coda e chiude la barra inferiore
        installer.stopSequence()
        XCTAssertFalse(installer.isRunningSequence)
        XCTAssertFalse(installer.showsFloatingBottomBar)
        XCTAssertFalse(installer.isWaitingInlineNextConfirmation)
        XCTAssertNil(installer.currentActiveApp)
    }

    func testItalianShortAppsAndTruncatedPrefixesWithoutEllipsis() {
        let candidates = iOSInstalledAppsScanner.parsePlausibleAppCandidates([
            "NOW",
            "now",
            "IO",
            "io",
            "⬇️ Aruba OTP"
        ])
        let titles = candidates.map(\.cleaned)

        XCTAssertTrue(titles.contains("NOW"))
        XCTAssertFalse(titles.contains("now"))
        XCTAssertTrue(titles.contains("IO"))
        XCTAssertTrue(titles.contains("Aruba OTP"))

        XCTAssertTrue(
            iOSAppStoreCatalogResolver.isVerifiedAppStoreTitleMatch(
                candidateQuery: "Banca Mediol",
                wasTruncated: false,
                storeAppName: "Banca Mediolanum"
            )
        )
        XCTAssertTrue(
            iOSAppStoreCatalogResolver.isVerifiedAppStoreTitleMatch(
                candidateQuery: "GialloZaffer",
                wasTruncated: false,
                storeAppName: "GialloZafferano: le ricette"
            )
        )
        XCTAssertFalse(
            iOSAppStoreCatalogResolver.isVerifiedAppStoreTitleMatch(
                candidateQuery: "WhatsApp",
                wasTruncated: false,
                storeAppName: "Random Utility Pro"
            )
        )
    }

    func testDocumentsSandboxBridgePreservesExactSubfoldersAndDeduplicates() throws {
        guard let docsRoot = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            XCTFail("Missing iOS Documents directory in test host")
            return
        }

        let uniqueTag = "DirectSwitchTest_\(UUID().uuidString.prefix(8))"
        let testRootDir = docsRoot.appendingPathComponent(uniqueTag, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: testRootDir)
        }

        let relFolder = "\(uniqueTag)/Lavoro/2026/Fatture"
        let item = ManifestItem(
            id: "doc_test_1",
            category: .DOCUMENTS,
            fileName: "Fattura_01.pdf",
            relativeAlbumOrFolder: relFolder,
            sizeBytes: 15,
            capturedEpochMillis: 1_700_000_000_000,
            dedupKey: "doc_test_1_dedup",
            mimeType: "application/pdf"
        )

        let targetDir = try XCTUnwrap(iOSDocumentsSandboxBridge.targetDirectory(for: item))
        XCTAssertFalse(targetDir.path.contains("DirectSwitch_Documenti"))
        XCTAssertTrue(targetDir.path.hasSuffix("/\(relFolder)"), "Unexpected path: \(targetDir.path)")

        let tmpSrc1 = FileManager.default.temporaryDirectory.appendingPathComponent("src1_\(UUID().uuidString).pdf")
        let tmpSrc2 = FileManager.default.temporaryDirectory.appendingPathComponent("src2_\(UUID().uuidString).pdf")
        defer {
            try? FileManager.default.removeItem(at: tmpSrc1)
            try? FileManager.default.removeItem(at: tmpSrc2)
        }
        let payload = Data("ContenutoPDF123".utf8)
        try payload.write(to: tmpSrc1)
        try payload.write(to: tmpSrc2)

        XCTAssertTrue(iOSDocumentsSandboxBridge.saveDocumentFile(item: item, sourceFileURL: tmpSrc1))
        XCTAssertTrue(iOSDocumentsSandboxBridge.saveDocumentFile(item: item, sourceFileURL: tmpSrc2))

        let savedEntries = try FileManager.default.contentsOfDirectory(atPath: targetDir.path)
        XCTAssertEqual(savedEntries, ["Fattura_01.pdf"])

        let dedupKeys = iOSDocumentsSandboxBridge.existingDocumentDedupKeys()
        XCTAssertTrue(iOSDocumentsSandboxBridge.matchesExistingDocumentDedup(item: item, existingKeys: dedupKeys))

        let differentFolderItem = ManifestItem(
            id: "doc_test_2",
            category: .DOCUMENTS,
            fileName: "Fattura_01.pdf",
            relativeAlbumOrFolder: "\(uniqueTag)/AltraCartella",
            sizeBytes: 15,
            capturedEpochMillis: 1_700_000_000_000,
            dedupKey: "doc_test_2_dedup",
            mimeType: "application/pdf"
        )
        XCTAssertFalse(iOSDocumentsSandboxBridge.matchesExistingDocumentDedup(item: differentFolderItem, existingKeys: dedupKeys))

        let report = iOSDocumentsSandboxBridge.inspectPreTransferDocuments(stagedItems: [], includeWhatsAppVault: false)
        let matchingFolder = report.folderSummaries.first(where: { $0.folderPath == relFolder })
        XCTAssertNotNil(matchingFolder)
        XCTAssertEqual(matchingFolder?.fileCount, 1)
        XCTAssertEqual(matchingFolder?.totalBytes, Int64(payload.count))
    }

    func testDocumentsSandboxBridgeClassifiesWholePositionsWithoutContainerLeak() throws {
        let onIPhoneRoot = URL(fileURLWithPath: "/private/var/mobile/Containers/Shared/AppGroup/ABC/File Provider Storage")
        let onIPhoneClassified = iOSDocumentsSandboxBridge.classifyPositionBaseFolder(for: onIPhoneRoot, isDirectory: true)
        XCTAssertEqual(onIPhoneClassified.baseFolder, "")
        XCTAssertEqual(onIPhoneClassified.locationLabel, "Su iPhone")

        let onIPhoneSub = URL(fileURLWithPath: "/private/var/mobile/Containers/Shared/AppGroup/ABC/File Provider Storage/Lavoro")
        let subClassified = iOSDocumentsSandboxBridge.classifyPositionBaseFolder(for: onIPhoneSub, isDirectory: true)
        XCTAssertEqual(subClassified.baseFolder, "Lavoro")
        XCTAssertEqual(subClassified.locationLabel, "Su iPhone")

        let iCloudFolder = URL(fileURLWithPath: "/private/var/mobile/Library/Mobile Documents/com~apple~CloudDocs/Azienda")
        let iCloudClassified = iOSDocumentsSandboxBridge.classifyPositionBaseFolder(for: iCloudFolder, isDirectory: true)
        XCTAssertEqual(iCloudClassified.baseFolder, "iCloud_Drive/Azienda")
        XCTAssertEqual(iCloudClassified.locationLabel, "iCloud Drive")

        guard let docsRoot = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            XCTFail("Missing iOS Documents directory in test host")
            return
        }
        let tag = "PosTest_\(UUID().uuidString.prefix(8))"
        let testRoot = docsRoot.appendingPathComponent(tag, isDirectory: true)
        let nestedDir = testRoot.appendingPathComponent("Contratti/2026", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: testRoot) }
        try FileManager.default.createDirectory(at: nestedDir, withIntermediateDirectories: true)
        try Data("ABCDE".utf8).write(to: nestedDir.appendingPathComponent("accordo.pdf"))

        let report = iOSDocumentsSandboxBridge.inspectPreTransferDocuments(stagedItems: [], includeWhatsAppVault: false)
        let localPos = report.locationSummaries.first(where: { $0.locationName == "DirectSwitch (Su iPhone)" })
        XCTAssertNotNil(localPos)
        XCTAssertGreaterThanOrEqual(localPos?.fileCount ?? 0, 1)
        XCTAssertGreaterThanOrEqual(localPos?.folderCount ?? 0, 1)
    }

    func testReceiverDestinationSessionPlacesFoldersIntoOriginalPositionsOutsideDirectSwitch() throws {
        let fm = FileManager.default
        let tempBase = fm.temporaryDirectory.appendingPathComponent("DS_RecvPos_\(UUID().uuidString.prefix(8))", isDirectory: true)
        defer { try? fm.removeItem(at: tempBase) }

        let downloadDestDir = tempBase.appendingPathComponent("Download", isDirectory: true)
        let documentiDestDir = tempBase.appendingPathComponent("Documenti", isDirectory: true)
        let iCloudLavoroDir = tempBase.appendingPathComponent("Mobile Documents/com~apple~CloudDocs/Lavoro", isDirectory: true)
        let fallbackBaseDir = tempBase.appendingPathComponent("Archivio_Esterno", isDirectory: true)
        try fm.createDirectory(at: downloadDestDir, withIntermediateDirectories: true)
        try fm.createDirectory(at: documentiDestDir, withIntermediateDirectories: true)
        try fm.createDirectory(at: iCloudLavoroDir, withIntermediateDirectories: true)
        try fm.createDirectory(at: fallbackBaseDir, withIntermediateDirectories: true)

        guard let dDest = iOSDocumentsSandboxBridge.buildAuthorizedDestination(for: downloadDestDir),
              let docDest = iOSDocumentsSandboxBridge.buildAuthorizedDestination(for: documentiDestDir),
              let icloudDest = iOSDocumentsSandboxBridge.buildAuthorizedDestination(for: iCloudLavoroDir),
              let fbDest = iOSDocumentsSandboxBridge.buildAuthorizedDestination(for: fallbackBaseDir) else {
            XCTFail("Expected valid ReceiverAuthorizedDestination objects")
            return
        }

        let destinations = [dDest, docDest, icloudDest]

        // 1. Download/Fatture/2026 deve finire dentro <tempBase>/Download/Fatture/2026 (NON in DirectSwitch/)
        let dlItem = ManifestItem(
            id: "doc_1", category: .DOCUMENTS, fileName: "gennaio.pdf",
            relativeAlbumOrFolder: "Download/Fatture/2026", sizeBytes: 5,
            capturedEpochMillis: 1_700_000_000_000, dedupKey: "k1", mimeType: "application/pdf"
        )
        let dlResolved = iOSDocumentsSandboxBridge.resolveWritableTargetDirectory(for: dlItem, destinations: destinations, fallbackRoot: fbDest)
        XCTAssertEqual(dlResolved?.directoryURL.standardizedFileURL.path, downloadDestDir.appendingPathComponent("Fatture/2026").standardizedFileURL.path)
        XCTAssertFalse(dlResolved?.displayFolder.contains("DirectSwitch") ?? true)

        // 2. Alias cross-OS: Android Downloads/Note & Documents/Contratti -> iPhone Download/Note & Documenti/Contratti
        let androidDlItem = ManifestItem(
            id: "doc_2", category: .DOCUMENTS, fileName: "nota.txt",
            relativeAlbumOrFolder: "Downloads/Note", sizeBytes: 4,
            capturedEpochMillis: 0, dedupKey: "k2", mimeType: "text/plain"
        )
        let androidDlResolved = iOSDocumentsSandboxBridge.resolveWritableTargetDirectory(for: androidDlItem, destinations: destinations, fallbackRoot: fbDest)
        XCTAssertEqual(androidDlResolved?.directoryURL.standardizedFileURL.path, downloadDestDir.appendingPathComponent("Note").standardizedFileURL.path)

        let androidDocsItem = ManifestItem(
            id: "doc_3", category: .DOCUMENTS, fileName: "affitto.pdf",
            relativeAlbumOrFolder: "Documents/Contratti", sizeBytes: 4,
            capturedEpochMillis: 0, dedupKey: "k3", mimeType: "application/pdf"
        )
        let androidDocsResolved = iOSDocumentsSandboxBridge.resolveWritableTargetDirectory(for: androidDocsItem, destinations: destinations, fallbackRoot: fbDest)
        XCTAssertEqual(androidDocsResolved?.directoryURL.standardizedFileURL.path, documentiDestDir.appendingPathComponent("Contratti").standardizedFileURL.path)

        // 3. iCloud_Drive/Lavoro/Preventivi deve andare dentro <iCloudLavoroDir>/Preventivi
        let icloudItem = ManifestItem(
            id: "doc_4", category: .DOCUMENTS, fileName: "offerta.docx",
            relativeAlbumOrFolder: "iCloud_Drive/Lavoro/Preventivi", sizeBytes: 4,
            capturedEpochMillis: 0, dedupKey: "k4", mimeType: "application/octet-stream"
        )
        let icloudResolved = iOSDocumentsSandboxBridge.resolveWritableTargetDirectory(for: icloudItem, destinations: destinations, fallbackRoot: fbDest)
        XCTAssertEqual(icloudResolved?.directoryURL.standardizedFileURL.path, iCloudLavoroDir.appendingPathComponent("Preventivi").standardizedFileURL.path)
        XCTAssertTrue(icloudResolved?.displayFolder.hasPrefix("iCloud Drive") ?? false)

        // 4. Cartella nuova non ancora autorizzata usa fallbackRoot esterno invece di app/DirectSwitch
        let customItem = ManifestItem(
            id: "doc_5", category: .DOCUMENTS, fileName: "progetto.pdf",
            relativeAlbumOrFolder: "Progetti_Nuovi/2026", sizeBytes: 4,
            capturedEpochMillis: 0, dedupKey: "k5", mimeType: "application/pdf"
        )
        let customResolved = iOSDocumentsSandboxBridge.resolveWritableTargetDirectory(for: customItem, destinations: destinations, fallbackRoot: fbDest)
        XCTAssertEqual(customResolved?.directoryURL.standardizedFileURL.path, fallbackBaseDir.appendingPathComponent("Progetti_Nuovi/2026").standardizedFileURL.path)

        // 5. Verifica scrittura reale + anti-duplicato senza " (1)" su sessione attiva
        let sourceTemp = tempBase.appendingPathComponent("src_gennaio.pdf")
        try Data("HELLO".utf8).write(to: sourceTemp)
        let session = iOSDocumentsSandboxBridge.ReceiverDestinationSession(destinations: destinations, fallbackRoot: fbDest)
        let firstWrite = iOSDocumentsSandboxBridge.saveDocumentFileToDestination(item: dlItem, sourceFileURL: sourceTemp, session: session)
        XCTAssertTrue(firstWrite.saved)
        XCTAssertFalse(firstWrite.displayFolder.contains("DirectSwitch"))
        let expectedDestFile = downloadDestDir.appendingPathComponent("Fatture/2026/gennaio.pdf")
        XCTAssertTrue(fm.fileExists(atPath: expectedDestFile.path))

        let secondWrite = iOSDocumentsSandboxBridge.saveDocumentFileToDestination(item: dlItem, sourceFileURL: sourceTemp, session: session)
        XCTAssertTrue(secondWrite.saved)
        let dupFile = downloadDestDir.appendingPathComponent("Fatture/2026/gennaio (1).pdf")
        XCTAssertFalse(fm.fileExists(atPath: dupFile.path))

        let dedupKeys = iOSDocumentsSandboxBridge.existingDocumentDedupKeys(including: session)
        XCTAssertTrue(iOSDocumentsSandboxBridge.matchesExistingDocumentDedup(item: dlItem, existingKeys: dedupKeys))
        XCTAssertTrue(iOSDocumentsSandboxBridge.matchesExistingDocumentDedup(
            item: ManifestItem(
                id: "doc_alias", category: .DOCUMENTS, fileName: "gennaio.pdf",
                relativeAlbumOrFolder: "Downloads/Fatture/2026", sizeBytes: 5,
                capturedEpochMillis: 1_700_000_000_000, dedupKey: "k1", mimeType: "application/pdf"
            ),
            existingKeys: dedupKeys
        ))
        session.close()
    }

    func testSelectablePositionsLoadEvenWhenEmptyFilterTransferAndProtectRealFiles() throws {
        let fm = FileManager.default
        let tempBase = fm.temporaryDirectory.appendingPathComponent("DS_SelectPos_\(UUID().uuidString.prefix(8))", isDirectory: true)
        defer {
            iOSDocumentsSandboxBridge.clearAllPickedDocumentsAndBookmarks()
            try? fm.removeItem(at: tempBase)
        }

        let posLavoro = tempBase.appendingPathComponent("Posizione_Lavoro", isDirectory: true)
        let posVuota = tempBase.appendingPathComponent("Posizione_Vuota", isDirectory: true)
        try fm.createDirectory(at: posLavoro.appendingPathComponent("Contratti"), withIntermediateDirectories: true)
        try fm.createDirectory(at: posVuota, withIntermediateDirectories: true)

        let realUserFile = posLavoro.appendingPathComponent("Contratti/contratto_2026.pdf")
        try Data("CONTRATTO_VERO".utf8).write(to: realUserFile)

        // I file reali dell'utente NON devono mai essere considerati temporanei da cancellare a fine invio
        XCTAssertFalse(iOSDocumentsSandboxBridge.isTemporaryStagedFile(realUserFile))

        let authResult = iOSDocumentsSandboxBridge.authorizePositionBookmarks([posLavoro, posVuota])
        XCTAssertEqual(authResult.addedBookmarks, 2)
        XCTAssertTrue(authResult.stagedFallback.isEmpty)

        // Entrambe le posizioni (anche quella con 0 file) devono comparire subito in locationSummaries ed essere selezionate
        let initialReport = iOSDocumentsSandboxBridge.inspectPreTransferDocuments(stagedItems: [], includeWhatsAppVault: false)
        let lavoroLoc = try XCTUnwrap(initialReport.locationSummaries.first(where: { $0.locationName.contains("Posizione_Lavoro") }))
        let vuotaLoc = try XCTUnwrap(initialReport.locationSummaries.first(where: { $0.locationName.contains("Posizione_Vuota") }))
        XCTAssertTrue(lavoroLoc.isSelected)
        XCTAssertTrue(lavoroLoc.isRemovableBookmark)
        XCTAssertEqual(lavoroLoc.fileCount, 1)
        XCTAssertTrue(vuotaLoc.isSelected)
        XCTAssertEqual(vuotaLoc.fileCount, 0)

        let initialCollected = iOSDocumentsSandboxBridge.collectAllVerifiedDocumentsForTransfer(
            explicitPicked: [],
            includeDocuments: true,
            includeWhatsAppVault: false
        )
        for s in initialCollected.activeSecurityScopes { s.stopAccessingSecurityScopedResource() }
        XCTAssertTrue(initialCollected.items.contains(where: { $0.0.fileName == "contratto_2026.pdf" }))

        // Deselezionando Posizione_Lavoro, resta visibile nell'elenco con isSelected = false ma viene esclusa dall'invio
        iOSDocumentsSandboxBridge.setPositionSelected(locationId: lavoroLoc.locationId, isSelected: false)
        let deselectedReport = iOSDocumentsSandboxBridge.inspectPreTransferDocuments(stagedItems: [], includeWhatsAppVault: false)
        let lavoroAfterDeselect = try XCTUnwrap(deselectedReport.locationSummaries.first(where: { $0.locationId == lavoroLoc.locationId }))
        XCTAssertFalse(lavoroAfterDeselect.isSelected)

        let filteredCollected = iOSDocumentsSandboxBridge.collectAllVerifiedDocumentsForTransfer(
            explicitPicked: [],
            includeDocuments: true,
            includeWhatsAppVault: false
        )
        for s in filteredCollected.activeSecurityScopes { s.stopAccessingSecurityScopedResource() }
        XCTAssertFalse(filteredCollected.items.contains(where: { $0.0.fileName == "contratto_2026.pdf" }))

        // Rimozione singola della posizione vuota
        iOSDocumentsSandboxBridge.removeAuthorizedPosition(locationId: vuotaLoc.locationId)
        let afterRemoveReport = iOSDocumentsSandboxBridge.inspectPreTransferDocuments(stagedItems: [], includeWhatsAppVault: false)
        XCTAssertNil(afterRemoveReport.locationSummaries.first(where: { $0.locationId == vuotaLoc.locationId }))

        // Verifica che la radice «Su iPhone» (File Provider Storage) sia trattata come contenitore sul ricevente
        let onIPhoneRoot = URL(fileURLWithPath: "/private/var/mobile/Containers/Shared/AppGroup/ABC/File Provider Storage")
        let rootDest = try XCTUnwrap(iOSDocumentsSandboxBridge.buildAuthorizedDestination(for: onIPhoneRoot))
        XCTAssertTrue(rootDest.isContainerRoot)
        XCTAssertEqual(rootDest.displayRoot, "Su iPhone")
    }

    func testWhatsAppOnlyVsCombinedTransferScopeParityWithAndroid() throws {
        let waOnly = ActiveTransferScope(whatsApp: true)
        XCTAssertTrue(waOnly.isWhatsAppOnly)
        XCTAssertFalse(waOnly.hasAnyStandardDataCategory)

        let combined = ActiveTransferScope(contacts: true, apps: true, whatsApp: true)
        XCTAssertFalse(combined.isWhatsAppOnly)
        XCTAssertTrue(combined.hasAnyStandardDataCategory)

        let encoded = try JSONEncoder().encode(combined)
        let decoded = try JSONDecoder().decode(ActiveTransferScope.self, from: encoded)
        XCTAssertEqual(decoded, combined)
    }

    func testAndroidToIosAppMappingAndCanonicalQuery() {
        XCTAssertEqual(iOSAppStoreCatalogResolver.androidPackageToiOSBundleId["com.whatsapp"], "net.whatsapp.WhatsApp")
        XCTAssertEqual(iOSAppStoreCatalogResolver.androidPackageToiOSBundleId["com.whatsapp.w4b"], "net.whatsapp.WhatsAppSMB")
        XCTAssertEqual(iOSAppStoreCatalogResolver.androidPackageToiOSBundleId["com.instagram.android"], "com.burbn.instagram")
        XCTAssertEqual(iOSAppStoreCatalogResolver.androidPackageToiOSBundleId["com.spotify.music"], "com.spotify.client")
        XCTAssertEqual(iOSAppStoreCatalogResolver.androidPackageToiOSBundleId["org.telegram.messenger"], "ph.telegra.Telegraph")
        XCTAssertEqual(iOSAppStoreCatalogResolver.androidPackageToiOSBundleId["com.openai.chatgpt"], "com.openai.chat")

        XCTAssertEqual(iOSInstalledAppsScanner.canonicalAppQuery(for: "WA Business"), "WhatsApp Business")
        XCTAssertEqual(iOSInstalledAppsScanner.canonicalAppQuery(for: "WhatsApp"), "WhatsApp Messenger")
    }
}
