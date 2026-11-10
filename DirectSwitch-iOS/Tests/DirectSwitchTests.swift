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
    }
}
