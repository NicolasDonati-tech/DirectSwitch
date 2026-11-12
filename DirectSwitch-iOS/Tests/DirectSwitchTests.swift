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
        let (allowed, gated) = LicensePolicyEvaluator.filterItemsForTier(sampleItems, tier: .CROSS_OS_PREVIEW)
        XCTAssertEqual(allowed.count, 25)
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
        //    - conferma al 1° frame le app note
        //    - scarta rumore transitorio da movimento (1 solo frame) e categorie/widget Home
        //    - conferma al 2° frame le app arbitrarie senza mai riemetterle al 3° frame
        var stabilizer = LiveCameraCandidateStabilizer()
        let frame1 = stabilizer.ingestFrameLines([
            "BANCOMAT", "Instagrx", "ClasseViva", "Produttività e finanza", "18°", "Nessun evento"
        ])
        XCTAssertEqual(frame1, ["BANCOMAT"])

        let frame2 = stabilizer.ingestFrameLines([
            "ClasseViva", "Ryanair", "Giochi", "21°C"
        ])
        XCTAssertEqual(frame2, ["ClasseViva", "Ryanair"])

        let frame3 = stabilizer.ingestFrameLines([
            "BANCOMAT", "ClasseViva", "Ryanair"
        ])
        XCTAssertTrue(frame3.isEmpty)

        // 3. Protocollo cifrato AES-GCM per apertura/sincronizzazione fotocamera live sul nuovo iPhone + deduplica
        let keyHex = DirectSwitchCrypto.generateSessionKeyHex()
        let symKey = try DirectSwitchCrypto.deriveSessionSymmetricKey(sessionKeyHex: keyHex)

        let seedApp = InstalledAppRecord(packageName: "com.spotify.client", appName: "Spotify", appStoreId: 324684580)
        let startReq = RemoteAppScannerStartRequest(
            sessionId: "sess-live-scan",
            senderName: "iPhone Vecchio",
            seedApps: [seedApp]
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
}
