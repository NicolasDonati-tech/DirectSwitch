package com.directswitch.android

import com.directswitch.android.migrators.PublicDownloadsSaver
import com.directswitch.android.protocol.ActiveTransferScope
import com.directswitch.android.protocol.DevicePlatform
import com.directswitch.android.protocol.DirectSwitchCrypto
import com.directswitch.android.protocol.DirectSwitchJson
import com.directswitch.android.protocol.DiscoveryBeaconPayload
import com.directswitch.android.protocol.HandshakeRequest
import com.directswitch.android.protocol.InstalledAppRecord
import com.directswitch.android.protocol.LicensePolicyEvaluator
import com.directswitch.android.protocol.ManifestItem
import com.directswitch.android.protocol.PhoneNormalizer
import com.directswitch.android.protocol.QrPairingPayload
import com.directswitch.android.protocol.SessionLicenseTier
import com.directswitch.android.protocol.SmsTransferRecord
import com.directswitch.android.protocol.TransferCategory
import com.directswitch.android.protocol.TransferManifest
import kotlinx.serialization.encodeToString
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream

class DirectSwitchProtocolTest {

    @Test
    fun intraOsAndroidToAndroidAndIosToIosAreAlwaysFree() {
        assertEquals(
            SessionLicenseTier.INTRA_OS_FREE,
            LicensePolicyEvaluator.resolveTier(
                senderPlatform = DevicePlatform.ANDROID,
                receiverPlatform = DevicePlatform.ANDROID,
                senderHasPro = false,
                receiverHasPro = false
            )
        )
        assertEquals(
            SessionLicenseTier.INTRA_OS_FREE,
            LicensePolicyEvaluator.resolveTier(
                senderPlatform = DevicePlatform.IOS,
                receiverPlatform = DevicePlatform.IOS,
                senderHasPro = false,
                receiverHasPro = false
            )
        )
    }

    @Test
    fun crossOsSingleSideUnlockWorksFromEitherDeviceOrVerifiedCloudSavePro() {
        assertEquals(
            SessionLicenseTier.CROSS_OS_PREVIEW,
            LicensePolicyEvaluator.resolveTier(
                senderPlatform = DevicePlatform.ANDROID,
                receiverPlatform = DevicePlatform.IOS,
                senderHasPro = false,
                receiverHasPro = false
            )
        )

        assertEquals(
            SessionLicenseTier.CROSS_OS_PRO_UNLOCKED,
            LicensePolicyEvaluator.resolveTier(
                senderPlatform = DevicePlatform.ANDROID,
                receiverPlatform = DevicePlatform.IOS,
                senderHasPro = true,
                receiverHasPro = false
            )
        )

        assertEquals(
            SessionLicenseTier.CROSS_OS_PRO_UNLOCKED,
            LicensePolicyEvaluator.resolveTier(
                senderPlatform = DevicePlatform.ANDROID,
                receiverPlatform = DevicePlatform.IOS,
                senderHasPro = false,
                receiverHasPro = true
            )
        )

        assertEquals(
            SessionLicenseTier.CROSS_OS_PRO_UNLOCKED,
            LicensePolicyEvaluator.resolveTier(
                senderPlatform = DevicePlatform.IOS,
                receiverPlatform = DevicePlatform.ANDROID,
                senderHasPro = false,
                receiverHasPro = false,
                senderHasCloudSavePro = true
            )
        )
    }

    @Test
    fun crossOsPreviewGatesCalendarsFullCategoriesAndMediaOver25() {
        assertFalse(LicensePolicyEvaluator.allowsFullCategories(SessionLicenseTier.CROSS_OS_PREVIEW))
        assertTrue(LicensePolicyEvaluator.allowsFullCategories(SessionLicenseTier.INTRA_OS_FREE))
        assertTrue(LicensePolicyEvaluator.allowsFullCategories(SessionLicenseTier.CROSS_OS_PRO_UNLOCKED))

        val photos = (1..40).map { i ->
            ManifestItem(
                id = "photo_$i",
                category = TransferCategory.PHOTOS,
                fileName = "IMG_$i.JPG",
                sizeBytes = 1024L,
                dedupKey = "img_$i"
            )
        }
        val (allowed, gated) = LicensePolicyEvaluator.filterItemsForTier(
            photos,
            SessionLicenseTier.CROSS_OS_PREVIEW
        )
        assertEquals(25, allowed.size)
        assertEquals(15, gated)
    }

    @Test
    fun rfc5869OfficialHkdfVectorMatchesAppleCryptoKit() {
        // RFC 5869 Test Case 1
        val ikm = DirectSwitchCrypto.fromHex("0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b")
        val salt = DirectSwitchCrypto.fromHex("000102030405060708090a0b0c")
        val info = DirectSwitchCrypto.fromHex("f0f1f2f3f4f5f6f7f8f9")
        val okm = DirectSwitchCrypto.hkdfSha256(ikm, salt, info, 42)
        assertEquals(
            "3cb25f25faacd57a90434f64d0362f2a2d2d0a90cf1a5a4c5db02d56ecc4c5bf34007208d5b887185865",
            DirectSwitchCrypto.toHexLower(okm)
        )
    }

    @Test
    fun controlPlaneJsonEnvelopeRejectsWrongKeyOrTampering() {
        val validKey = DirectSwitchCrypto.deriveSessionAesKey(DirectSwitchCrypto.generateSessionKeyHex())
        val attackerKey = DirectSwitchCrypto.deriveSessionAesKey(DirectSwitchCrypto.generateSessionKeyHex())
        val req = HandshakeRequest(
            sessionId = "ds_secure_session",
            senderName = "Pixel 9 Pro",
            senderPlatform = DevicePlatform.ANDROID,
            senderHasPro = true,
            totalEstimatedBytes = 1024_000L
        )
        val rawJson = DirectSwitchJson.instance.encodeToString(req)
        val envelope = DirectSwitchCrypto.sealJsonEnvelope(rawJson, validKey)

        // Chiave corretta -> decifra perfettamente
        val opened = DirectSwitchCrypto.openJsonEnvelope(envelope, validKey)
        assertEquals(rawJson, opened)

        // Chiave attaccante senza QR -> deve fallire
        try {
            DirectSwitchCrypto.openJsonEnvelope(envelope, attackerKey)
            fail("Un attaccante senza la chiave del QR non deve poter aprire o falsificare la busta")
        } catch (_: Throwable) {
            // Atteso: AEADBadTagException
        }
    }

    @Test
    fun csgcm1MultiChunkStreamingRoundTripVerifiesByteCountAndSha256() {
        val sessionKeyHex = DirectSwitchCrypto.generateSessionKeyHex()
        val aesKey = DirectSwitchCrypto.deriveSessionAesKey(sessionKeyHex)
        // 5.2 MiB payload (> 4 MiB chunk boundary -> testa multi-blocco CSGCM1 reale)
        val original = DirectSwitchCrypto.randomBytes(5 * 1024 * 1024 + 200_000)

        val encOut = ByteArrayOutputStream()
        val (encPlainBytes, encSha256) = DirectSwitchCrypto.encryptStreamCsgcm1(
            ByteArrayInputStream(original),
            encOut,
            aesKey
        )

        val decOut = ByteArrayOutputStream()
        val (decPlainBytes, decSha256) = DirectSwitchCrypto.decryptStreamCsgcm1(
            ByteArrayInputStream(encOut.toByteArray()),
            decOut,
            aesKey
        )

        assertEquals(original.size.toLong(), encPlainBytes)
        assertEquals(encPlainBytes, decPlainBytes)
        assertEquals(encSha256, decSha256)
        assertArrayEquals(original, decOut.toByteArray())
    }

    @Test
    fun emptyZeroByteCsgcm1StreamIsAuthenticatedAndRejectsBareHeaderOrWrongKey() {
        val validKey = DirectSwitchCrypto.deriveSessionAesKey(DirectSwitchCrypto.generateSessionKeyHex())
        val wrongKey = DirectSwitchCrypto.deriveSessionAesKey(DirectSwitchCrypto.generateSessionKeyHex())

        val encOut = ByteArrayOutputStream()
        val (encBytes, encSha) = DirectSwitchCrypto.encryptStreamCsgcm1(
            ByteArrayInputStream(ByteArray(0)),
            encOut,
            validKey
        )
        val ciphertext = encOut.toByteArray()
        assertEquals(0L, encBytes)
        assertEquals("e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", encSha)
        // 6 byte magic + 4 byte len + 28 byte IV/GCM tag = 38 byte autenticati
        assertEquals(38, ciphertext.size)

        val decOut = ByteArrayOutputStream()
        val (decBytes, decSha) = DirectSwitchCrypto.decryptStreamCsgcm1(
            ByteArrayInputStream(ciphertext),
            decOut,
            validKey
        )
        assertEquals(0L, decBytes)
        assertEquals(encSha, decSha)
        assertEquals(0, decOut.size())

        // Deve rifiutare uno stream "CSGCM1" nudo privo di blocco GCM autenticato
        try {
            DirectSwitchCrypto.decryptStreamCsgcm1(
                ByteArrayInputStream("CSGCM1".toByteArray(Charsets.US_ASCII)),
                ByteArrayOutputStream(),
                validKey
            )
            fail("Lo stream CSGCM1 privo di blocchi autenticati deve essere rifiutato")
        } catch (_: IllegalArgumentException) {
            // Atteso: require(blockCount >= 1)
        }

        // Deve rifiutare lo stream da 0 byte se la chiave AES-256 non corrisponde
        try {
            DirectSwitchCrypto.decryptStreamCsgcm1(
                ByteArrayInputStream(ciphertext),
                ByteArrayOutputStream(),
                wrongKey
            )
            fail("Lo stream da 0 byte cifrato con un'altra chiave deve fallire la verifica GCM")
        } catch (_: Throwable) {
            // Atteso: AEADBadTagException
        }
    }

    @Test
    fun publicDiscoveryBeaconStripsSessionKeyAndWifiPassword() {
        val secretHex = DirectSwitchCrypto.generateSessionKeyHex()
        val qr = QrPairingPayload(
            sessionId = "ds_beacon_secure",
            receiverName = "Samsung S25 Ultra",
            receiverPlatform = DevicePlatform.ANDROID,
            ips = listOf("192.168.1.44"),
            port = 49443,
            sessionKeyHex = secretHex,
            wifiSsid = "AndroidShare_5G",
            wifiPass = "TopSecretHotspotPass",
            receiverHasPro = true
        )
        val beaconJson = qr.toPublicBeacon().toCompactJson()
        assertFalse("Il beacon UDP non deve contenere sessionKeyHex", beaconJson.contains("sessionKeyHex"))
        assertFalse("Il beacon UDP non deve contenere la chiave segreta", beaconJson.contains(secretHex))
        assertFalse("Il beacon UDP non deve contenere wifiPass", beaconJson.contains("TopSecretHotspotPass"))

        val parsed = DiscoveryBeaconPayload.fromJson(beaconJson)
        assertEquals("ds_beacon_secure", parsed.sessionId)
        assertEquals("Samsung S25 Ultra", parsed.receiverName)
        assertTrue(parsed.receiverHasPro)
    }

    @Test
    fun pinKeyDerivationSealsAndOpensQrPayloadAndRejectsWrongPin() {
        val pin = DirectSwitchCrypto.generatePairingPin()
        assertEquals(6, pin.length)
        assertTrue(pin.all { it.isDigit() })

        val rightKey = DirectSwitchCrypto.derivePinAesKey("ds_pin_session_01", "482910")
        val sameRightKey = DirectSwitchCrypto.derivePinAesKey("ds_pin_session_01", "482910")
        val wrongKey = DirectSwitchCrypto.derivePinAesKey("ds_pin_session_01", "482911")
        assertArrayEquals(rightKey, sameRightKey)

        val sealed = DirectSwitchCrypto.sealJsonEnvelope("""{"sessionId":"ds_pin_session_01"}""", rightKey)
        assertEquals("""{"sessionId":"ds_pin_session_01"}""", DirectSwitchCrypto.openJsonEnvelope(sealed, rightKey))

        try {
            DirectSwitchCrypto.openJsonEnvelope(sealed, wrongKey)
            fail("Un PIN errato non deve mai decifrare il payload di accoppiamento")
        } catch (_: Throwable) {
            // Atteso
        }
    }

    @Test
    fun fromHexRejectsOddLengthAndNonHexCharacters() {
        assertArrayEquals(byteArrayOf(0x0a, 0x1b, 0xff.toByte()), DirectSwitchCrypto.fromHex("0a1bff"))
        for (invalid in listOf("abc", "zzzz", "0g", "12 34")) {
            try {
                DirectSwitchCrypto.fromHex(invalid)
                fail("Stringa esadecimale non valida non rifiutata: $invalid")
            } catch (_: IllegalArgumentException) {
                // Atteso
            }
        }
    }

    @Test
    fun constantTimeEqualsVerifiesTokensSafely() {
        assertTrue(DirectSwitchCrypto.constantTimeEquals("a1b2c3d4e5f6", "a1b2c3d4e5f6"))
        assertFalse(DirectSwitchCrypto.constantTimeEquals("a1b2c3d4e5f6", "a1b2c3d4e5f7"))
        assertFalse(DirectSwitchCrypto.constantTimeEquals("a1b2c3d4e5f6", "a1b2c3"))
    }

    @Test
    fun smartMergePhoneNormalizerMatchesInternationalAndLocalFormats() {
        val itWithPrefix = PhoneNormalizer.normalizeKey("+39 333 123 4567")
        val itLocal = PhoneNormalizer.normalizeKey("333-1234567")
        assertEquals(itWithPrefix, itLocal)
    }

    @Test
    fun qrPairingJsonRoundTripPreservesHotspotAndSession() {
        val original = QrPairingPayload(
            sessionId = "ds_test1234",
            receiverName = "iPhone 16 Pro",
            receiverPlatform = DevicePlatform.IOS,
            ips = listOf("192.168.1.25", "192.168.43.1"),
            port = 49443,
            sessionKeyHex = DirectSwitchCrypto.generateSessionKeyHex(),
            wifiSsid = "AndroidShare_9912",
            wifiPass = "Secret5GhzPass",
            receiverHasPro = true
        )
        val decoded = QrPairingPayload.fromJson(original.toCompactJson())
        assertEquals(original, decoded)
    }

    @Test
    fun transferManifestPreservesSmsDocumentsAndWhatsAppVaultEntries() {
        val manifest = TransferManifest(
            sessionId = "ds_full_manifest",
            senderPlatform = DevicePlatform.ANDROID,
            items = listOf(
                ManifestItem(
                    id = "documents_1",
                    category = TransferCategory.DOCUMENTS,
                    fileName = "Contratto.pdf",
                    relativeAlbumOrFolder = "Documenti",
                    sizeBytes = 250_000L,
                    dedupKey = "contratto.pdf_250000"
                ),
                ManifestItem(
                    id = "whatsapp_vault_1",
                    category = TransferCategory.WHATSAPP_VAULT,
                    fileName = "Chat WhatsApp con Marco.zip",
                    relativeAlbumOrFolder = "WhatsApp_Vault",
                    sizeBytes = 14_200_000L,
                    dedupKey = "chat_marco.zip_14200000"
                )
            ),
            smsPayload = listOf(
                SmsTransferRecord(
                    id = "101",
                    address = "+393331234567",
                    body = "Codice conferma DirectSwitch",
                    dateEpochMillis = 1762600000000L,
                    messageType = 1
                )
            ),
            requestNativeWhatsAppMigration = true
        )
        val raw = DirectSwitchJson.instance.encodeToString(manifest)
        val decoded = DirectSwitchJson.instance.decodeFromString<TransferManifest>(raw)
        assertEquals(2, decoded.items.size)
        assertEquals(1, decoded.smsPayload.size)
        assertEquals("+393331234567", decoded.smsPayload.first().address)
        assertEquals(true, decoded.requestNativeWhatsAppMigration)

        val legacyRaw = """{"sessionId":"ds_legacy","senderPlatform":"IOS","items":[]}"""
        val legacyDecoded = DirectSwitchJson.instance.decodeFromString<TransferManifest>(legacyRaw)
        assertEquals(false, legacyDecoded.requestNativeWhatsAppMigration)
        assertTrue(legacyDecoded.installedAppsPayload.isEmpty())
    }

    @Test
    fun discoveryBeaconDeduplicatesSamePhysicalDeviceAcrossSessionRotation() {
        val oldBeacon = DiscoveryBeaconPayload(
            sessionId = "ds_old_01",
            receiverName = "iPhone",
            receiverPlatform = DevicePlatform.IOS,
            ips = listOf("192.168.1.42"),
            port = 49443
        )
        val rotatedBeacon = DiscoveryBeaconPayload(
            sessionId = "ds_new_02",
            receiverName = "iPhone",
            receiverPlatform = DevicePlatform.IOS,
            ips = listOf("192.168.1.42"),
            port = 49443
        )
        val otherPhoneBeacon = DiscoveryBeaconPayload(
            sessionId = "ds_other_03",
            receiverName = "iPhone",
            receiverPlatform = DevicePlatform.IOS,
            ips = listOf("192.168.1.99"),
            port = 49443
        )

        assertTrue(rotatedBeacon.representsSameDevice(oldBeacon))
        assertFalse(otherPhoneBeacon.representsSameDevice(oldBeacon))
    }

    @Test
    fun transferManifestPreservesInstalledAppsCatalog() {
        val apps = listOf(
            InstalledAppRecord(packageName = "com.whatsapp", appName = "WhatsApp"),
            InstalledAppRecord(packageName = "com.instagram.android", appName = "Instagram")
        )
        val manifest = TransferManifest(
            sessionId = "ds_apps_01",
            senderPlatform = DevicePlatform.ANDROID,
            items = emptyList(),
            installedAppsPayload = apps
        )
        val raw = DirectSwitchJson.instance.encodeToString(manifest)
        val decoded = DirectSwitchJson.instance.decodeFromString<TransferManifest>(raw)
        assertEquals(apps, decoded.installedAppsPayload)
    }

    @Test
    fun sanitizedRelativeSegmentsPreservesNestedFoldersAndStripsTraversal() {
        assertEquals(
            listOf("Lavoro", "2026", "Fatture"),
            PublicDownloadsSaver.sanitizedRelativeSegments("../Lavoro\\2026/Fatture/./")
        )
        assertEquals(
            listOf("Documents", "Contratti_2026"),
            PublicDownloadsSaver.sanitizedRelativeSegments("Documents/Contratti:2026")
        )
        assertEquals(
            emptyList<String>(),
            PublicDownloadsSaver.sanitizedRelativeSegments(" / .. / . ")
        )
    }

    @Test
    fun manifestItemPreservesDeepDocumentFolderPath() {
        val item = ManifestItem(
            id = "doc_001",
            category = TransferCategory.DOCUMENTS,
            fileName = "Contratto.pdf",
            relativeAlbumOrFolder = "Lavoro/2026/Clienti/Contratti",
            sizeBytes = 4096L,
            capturedEpochMillis = 1_700_000_000_000L,
            dedupKey = "doc_dedup_001",
            mimeType = "application/pdf"
        )
        val raw = DirectSwitchJson.instance.encodeToString(item)
        val decoded = DirectSwitchJson.instance.decodeFromString<ManifestItem>(raw)
        assertEquals("Lavoro/2026/Clienti/Contratti", decoded.relativeAlbumOrFolder)
        assertEquals("Contratto.pdf", decoded.fileName)
        assertEquals(4096L, decoded.sizeBytes)
    }

    @Test
    fun sanitizedRelativeSegmentsPreservesWholeStorageLocations() {
        assertEquals(
            listOf("Scheda_SD", "Backup_Foto", "2026"),
            PublicDownloadsSaver.sanitizedRelativeSegments("Scheda_SD/Backup_Foto/2026")
        )
        assertEquals(
            listOf("iCloud_Drive", "Azienda", "Preventivi"),
            PublicDownloadsSaver.sanitizedRelativeSegments("iCloud_Drive\\Azienda/Preventivi")
        )
    }

    @Test
    fun documentLocationSummaryDefaultsToSelectedAndSupportsToggling() {
        val primary = com.directswitch.android.migrators.DocumentLocationSummary(
            locationId = "vol:primary",
            locationName = "Memoria interna",
            folderCount = 4,
            fileCount = 12,
            totalBytes = 102400L,
            isAccessible = true
        )
        assertTrue(primary.isSelected)
        assertFalse(primary.isRemovableSaf)

        val deselected = primary.copy(isSelected = false)
        assertFalse(deselected.isSelected)
        assertEquals("vol:primary", deselected.locationId)
    }

    @Test
    fun activeTransferScopeWhatsAppOnlyAndCrossOsPremiumGate() {
        val waOnly = ActiveTransferScope(whatsApp = true)
        assertTrue(waOnly.isWhatsAppOnly)
        assertFalse(waOnly.hasAnyStandardDataCategory)

        val mixed = ActiveTransferScope(contacts = true, whatsApp = true)
        assertFalse(mixed.isWhatsAppOnly)
        assertTrue(mixed.hasAnyStandardDataCategory)

        assertFalse(LicensePolicyEvaluator.allowsFullCategories(SessionLicenseTier.CROSS_OS_PREVIEW))
        assertTrue(LicensePolicyEvaluator.allowsFullCategories(SessionLicenseTier.CROSS_OS_PRO_UNLOCKED))
        assertTrue(LicensePolicyEvaluator.allowsFullCategories(SessionLicenseTier.INTRA_OS_FREE))

        val previewItems = listOf(
            ManifestItem(
                id = "wa_free",
                category = TransferCategory.WHATSAPP_VAULT,
                fileName = "WhatsApp_Chat.zip",
                sizeBytes = 2048L,
                dedupKey = "wa_1"
            ),
            ManifestItem(
                id = "doc_paid",
                category = TransferCategory.DOCUMENTS,
                fileName = "Contratto.pdf",
                sizeBytes = 4096L,
                dedupKey = "doc_1"
            )
        )
        val (allowed, gated) = LicensePolicyEvaluator.filterItemsForTier(
            previewItems,
            SessionLicenseTier.CROSS_OS_PREVIEW
        )
        assertEquals(listOf("wa_free"), allowed.map { it.id })
        assertEquals(1, gated)
    }

    @Test
    fun androidToIphoneMirrorFiltersSystemUtilitiesAndFallsBackToModifiedDate() {
        val scanner = com.directswitch.android.migrators.InstalledAppsScanner
        assertFalse(scanner.isMirrorableAndroidPackage("com.google.android.gms", isPureSystem = false))
        assertFalse(scanner.isMirrorableAndroidPackage("com.android.settings", isPureSystem = false))
        assertFalse(scanner.isMirrorableAndroidPackage("com.google.android.deskclock", isPureSystem = false))
        assertFalse(scanner.isMirrorableAndroidPackage("com.sec.android.app.camera", isPureSystem = false))

        assertTrue(scanner.isMirrorableAndroidPackage("com.google.android.apps.maps", isPureSystem = true))
        assertTrue(scanner.isMirrorableAndroidPackage("com.android.chrome", isPureSystem = true))
        assertTrue(scanner.isMirrorableAndroidPackage("com.whatsapp", isPureSystem = false))
        assertTrue(scanner.isMirrorableAndroidPackage("com.instagram.android", isPureSystem = false))

        val mediaScanner = com.directswitch.android.migrators.MediaExifScannerAndImporter
        assertEquals(1_700_000_000_000L, mediaScanner.resolveEffectiveTimestampMillis(1_700_000_000_000L, 1_800_000_000L))
        assertEquals(1_800_000_000_000L, mediaScanner.resolveEffectiveTimestampMillis(0L, 1_800_000_000L))
        assertEquals(0L, mediaScanner.resolveEffectiveTimestampMillis(0L, 0L))
    }

    @Test
    fun installedAppsCrossOsMirrorMappingAndSnapshotDetection() {
        val scanner = com.directswitch.android.migrators.InstalledAppsScanner

        assertEquals(
            com.directswitch.android.migrators.InstalledAppsScanner.PlayStoreTarget.ExactPackage("com.instagram.android"),
            scanner.resolvePlayStoreTarget(
                InstalledAppRecord(packageName = "com.burbn.instagram", appName = "Instagram"),
                DevicePlatform.IOS
            )
        )
        assertEquals(
            com.directswitch.android.migrators.InstalledAppsScanner.PlayStoreTarget.ExactPackage("com.whatsapp.w4b"),
            scanner.resolvePlayStoreTarget(
                InstalledAppRecord(packageName = "scan.ocr.01", appName = "WA Business"),
                DevicePlatform.IOS
            )
        )
        assertEquals(
            com.directswitch.android.migrators.InstalledAppsScanner.PlayStoreTarget.SearchByName("BancaLocale"),
            scanner.resolvePlayStoreTarget(
                InstalledAppRecord(packageName = "scan.ocr.02", appName = "BancaLocale"),
                DevicePlatform.IOS
            )
        )
        assertEquals(
            com.directswitch.android.migrators.InstalledAppsScanner.PlayStoreTarget.SearchByName("Custom iOS App"),
            scanner.resolvePlayStoreTarget(
                InstalledAppRecord(packageName = "it.custom.iosapp", appName = "Custom iOS App"),
                DevicePlatform.IOS
            )
        )
        assertEquals(
            com.directswitch.android.migrators.InstalledAppsScanner.PlayStoreTarget.ExactPackage("org.example.androidapp"),
            scanner.resolvePlayStoreTarget(
                InstalledAppRecord(packageName = "org.example.androidapp", appName = "Android App"),
                DevicePlatform.ANDROID
            )
        )

        assertFalse(scanner.isMirrorableAndroidPackage("com.google.android.webview", isPureSystem = false))
        assertFalse(scanner.isMirrorableAndroidPackage("com.miui.securitycenter", isPureSystem = false))
        assertFalse(scanner.isMirrorableAndroidPackage("com.google.android.ext.services", isPureSystem = false))
        assertTrue(scanner.isMirrorableAndroidPackage("com.google.android.apps.bard", isPureSystem = true))

        val snapshot = com.directswitch.android.migrators.InstalledAppsScanner.InstalledAppsSnapshot(
            packageNames = setOf("com.whatsapp"),
            normalizedLabels = setOf(scanner.normalizeAppLabel("Poste ID"))
        )
        assertTrue(
            scanner.isAppInstalled(
                snapshot,
                InstalledAppRecord(packageName = "net.whatsapp.WhatsApp", appName = "WhatsApp"),
                DevicePlatform.IOS
            )
        )
        assertTrue(
            scanner.isAppInstalled(
                snapshot,
                InstalledAppRecord(packageName = "scan.ocr.03", appName = "PosteID"),
                DevicePlatform.IOS
            )
        )
        assertFalse(
            scanner.isAppInstalled(
                snapshot,
                InstalledAppRecord(packageName = "com.spotify.client", appName = "Spotify"),
                DevicePlatform.IOS
            )
        )

        // Verifica mappatura esatta italiana + editor foto/video + Campo detectionSource retrocompatibile
        val expectedItalianMappings = listOf(
            "com.intesasanpaolo.ibiphone" to "com.latuabancaperandroid",
            "com.internet.unicredit.iphoneapp" to "com.unicredit",
            "it.poste.spim" to "com.posteitaliane.spim",
            "it.ipzs.cieID" to "it.ipzs.cieid",
            "it.poste.postebuy2" to "posteitaliane.posteapp.appposteid",
            "com.promptu.ProntoTreno" to "com.lynxspa.prontotreno",
            "it.telepass" to "it.telepass.prod.TelepassPyng",
            "com.booking.BookingApp" to "com.booking",
            "com.einnovation.temu" to "com.einnovation.temu",
            "zzkko.com.ZZKKO" to "com.zzkko",
            "com.camerasideas.InstaShot" to "com.camerasideas.instashot",
            "com.niksoftware.snapseedforipad" to "com.niksoftware.snapseed",
            "com.adobe.lrmobilephone" to "com.adobe.lrmobile",
            "com.strava.stravaride" to "com.strava",
            "com.tplink.tapo" to "com.tplink.iot",
            "com.hikvision.ezviz" to "com.ezviz",
            "it.rainet.ipad.raitv" to "it.rainet",
            "it.sky.skygoitalia" to "it.sky.anywhere",
            "com.nowtv.it" to "com.nowtv.it"
        )
        for ((iosBundle, expectedAndroidPkg) in expectedItalianMappings) {
            assertEquals(
                com.directswitch.android.migrators.InstalledAppsScanner.PlayStoreTarget.ExactPackage(expectedAndroidPkg),
                scanner.resolvePlayStoreTarget(
                    InstalledAppRecord(
                        packageName = iosBundle,
                        appName = iosBundle,
                        detectionSource = "da Album Foto • oggi"
                    ),
                    DevicePlatform.IOS
                )
            )
        }
    }

    @Test
    fun mediaRelativePathPreservesAlbumsAndCameraRoll() {
        val mediaScanner = com.directswitch.android.migrators.MediaExifScannerAndImporter
        assertEquals("DCIM/Camera", mediaScanner.resolveRelativeMediaPath("iPhone_Camera", isVideo = false))
        assertEquals("DCIM/Camera", mediaScanner.resolveRelativeMediaPath("Camera", isVideo = true))
        assertEquals("DCIM/Camera", mediaScanner.resolveRelativeMediaPath("Recenti", isVideo = false))
        assertEquals("DCIM/Camera", mediaScanner.resolveRelativeMediaPath("DCIM/Camera", isVideo = false))
        assertEquals(
            "Pictures/Città & Mare/Sicilia '25",
            mediaScanner.resolveRelativeMediaPath("Città & Mare/Sicilia '25", isVideo = false)
        )
        assertEquals("Movies/Vacanze", mediaScanner.resolveRelativeMediaPath("../Vacanze", isVideo = true))
    }

    @Test
    fun richContactTransferRecordRoundTrip() {
        val rich = com.directswitch.android.protocol.ContactTransferRecord(
            id = "c1",
            displayName = "Mario Rossi",
            phones = listOf("+393331234567"),
            emails = listOf("mario@example.com"),
            organization = "Studio Rossi",
            note = "Contatto principale",
            givenName = "Mario",
            familyName = "Rossi",
            nickname = "SuperMario",
            jobTitle = "Ingegnere",
            birthdayYear = 1990,
            birthdayMonth = 5,
            birthdayDay = 14,
            labeledPhones = listOf(com.directswitch.android.protocol.LabeledValueRecord("mobile", "+393331234567")),
            labeledEmails = listOf(com.directswitch.android.protocol.LabeledValueRecord("work", "mario@example.com")),
            urls = listOf("https://example.com"),
            postalAddresses = listOf(
                com.directswitch.android.protocol.PostalAddressTransferRecord(
                    label = "home",
                    street = "Via Roma 10",
                    city = "Milano",
                    state = "MI",
                    postalCode = "20100",
                    country = "Italia"
                )
            ),
            avatarJpegBase64 = "ZmFrZUF2YXRhcg=="
        )
        val encoded = DirectSwitchJson.instance.encodeToString(rich)
        val decoded = DirectSwitchJson.instance.decodeFromString<com.directswitch.android.protocol.ContactTransferRecord>(encoded)
        assertEquals(rich, decoded)

        val legacyJson = """{"id":"c2","displayName":"Luigi Verdi","phones":["+393409998877"],"emails":[],"organization":"","note":""}"""
        val legacyDecoded = DirectSwitchJson.instance.decodeFromString<com.directswitch.android.protocol.ContactTransferRecord>(legacyJson)
        assertEquals("Luigi Verdi", legacyDecoded.displayName)
        assertEquals(null, legacyDecoded.birthdayMonth)
        assertEquals(null, legacyDecoded.labeledPhones)
        assertEquals(null, legacyDecoded.postalAddresses)
    }

    @Test
    fun transferProgressAccountingReconcilesFailuresAndSlidingSpeedMeterWorks() {
        val acc = com.directswitch.android.protocol.TransferProgressAccounting(
            queuedItemsCount = 4,
            remainingEstimatedBytes = 8_000_000L
        )
        assertEquals(8_000_000L, acc.totalBytesForProgress)
        assertEquals(0f, acc.progressFraction, 0.0001f)

        acc.recordUploaded(estimatedBytes = 2_000_000L, actualBytes = 1_800_000L)
        acc.recordFailedOrSkipped(estimatedBytes = 2_000_000L)
        acc.recordUploaded(estimatedBytes = 2_000_000L, actualBytes = 2_200_000L)
        acc.recordFailedOrSkipped(estimatedBytes = 2_000_000L)

        assertEquals(2, acc.succeededItemsCount)
        assertEquals(2, acc.failedItemsCount)
        assertEquals(4_000_000L, acc.totalBytesForProgress)
        assertEquals(1.0f, acc.progressFraction, 0.0001f)

        val allFailed = com.directswitch.android.protocol.TransferProgressAccounting(
            queuedItemsCount = 2,
            remainingEstimatedBytes = 4_000_000L
        )
        allFailed.recordFailedOrSkipped(2_000_000L)
        assertEquals(0.5f, allFailed.progressFraction, 0.001f)
        allFailed.recordFailedOrSkipped(2_000_000L)
        assertEquals(0L, allFailed.totalBytesForProgress)
        assertEquals(1.0f, allFailed.progressFraction, 0.0001f)

        val meter = com.directswitch.android.protocol.SlidingTransferSpeedMeter(startMillis = 10_000L, windowMillis = 4_500L)
        meter.record(bytes = 1_048_576L, nowMillis = 11_000L)
        meter.record(bytes = 20L * 1024L * 1024L, nowMillis = 18_000L)
        val recentSpeed = meter.record(bytes = 20L * 1024L * 1024L, nowMillis = 20_000L)
        assertTrue(recentSpeed > 10.0)
    }

    @Test
    fun androidExtendedCategoriesAndPreloadStateModelsWork() {
        assertEquals(
            "social_messaging",
            com.directswitch.android.migrators.InstalledAppsScanner.classifyAppCategoryId("com.whatsapp", "WhatsApp")
        )
        assertEquals(
            "banks_payments",
            com.directswitch.android.migrators.InstalledAppsScanner.classifyAppCategoryId("com.latuabancaperandroid", "Intesa Sanpaolo")
        )
        assertEquals(
            "spid_office",
            com.directswitch.android.migrators.InstalledAppsScanner.classifyAppCategoryId("it.ipzs.cieid", "CieID")
        )
        assertEquals(
            "transport_travel",
            com.directswitch.android.migrators.InstalledAppsScanner.classifyAppCategoryId("com.lynxspa.prontotreno", "Trenitalia")
        )
        assertEquals(
            "shopping_food",
            com.directswitch.android.migrators.InstalledAppsScanner.classifyAppCategoryId("com.einnovation.temu", "Temu")
        )
        assertEquals(
            "music_streaming",
            com.directswitch.android.migrators.InstalledAppsScanner.classifyAppCategoryId("com.spotify.music", "Spotify")
        )
        assertEquals(
            "photo_video_sport",
            com.directswitch.android.migrators.InstalledAppsScanner.classifyAppCategoryId("com.lemon.lvoverseas", "CapCut")
        )
        assertEquals(
            "operators_home_ai",
            com.directswitch.android.migrators.InstalledAppsScanner.classifyAppCategoryId("com.openai.chatgpt", "ChatGPT")
        )

        val endOfDay = com.directswitch.android.migrators.CalendarMigrator.endOfDayMillis(1_700_000_000_000L)
        assertTrue(endOfDay >= 1_700_000_000_000L)

        val contactsPreload = com.directswitch.android.migrators.ContactsPreloadState(loadedCount = 120, totalCount = 120, isLoading = false, isCompleted = true)
        assertEquals(120, contactsPreload.totalCount)
        assertTrue(contactsPreload.isCompleted)
    }

    @Test
    fun decimalByteFormattingAndPercentageConsistencyAcrossOs() {
        val fmt = com.directswitch.android.protocol.TransferDisplayFormatting
        assertEquals("0 MB", fmt.formatBytes(0L))
        assertEquals("0,1 MB", fmt.formatBytes(50_000L))
        assertEquals("150,0 MB", fmt.formatBytes(150_000_000L))
        assertEquals("11,15 GB", fmt.formatBytes(11_150_000_000L))

        assertEquals(0, fmt.percentageInt(0.0, isCompleted = false))
        assertEquals(14, fmt.percentageInt(0.149, isCompleted = false))
        assertEquals(30, fmt.percentageInt(0.30, isCompleted = false))
        assertEquals(99, fmt.percentageInt(0.999, isCompleted = false))
        assertEquals(99, fmt.percentageInt(1.0, isCompleted = false))
        assertEquals(100, fmt.percentageInt(1.0, isCompleted = true))
    }

    @Test
    fun tenPercentSteppedEtaTrackerUpdatesOnlyEveryTenPercentWithoutOscillation() {
        val tracker = com.directswitch.android.protocol.TenPercentSteppedEtaTracker(
            initialFraction = 0.0,
            startMillis = 1_000_000L
        )
        assertEquals("Calcolo tempo rimanente…", tracker.currentLabel(isCompleted = false, hasTransferableItems = true))
        assertEquals("Calcolo tempo rimanente…", tracker.update(0.04, isCompleted = false, nowMillis = 1_020_000L))
        assertEquals("Calcolo tempo rimanente…", tracker.update(0.099, isCompleted = false, nowMillis = 1_055_000L))

        // Raggiunge il 10% dopo 60s -> 9 * 60s = 540s = 9 min
        assertEquals("Circa 9 min rimanenti", tracker.update(0.10, isCompleted = false, nowMillis = 1_060_000L))

        // Tra 11% e 19% non oscilla mai
        assertEquals("Circa 9 min rimanenti", tracker.update(0.12, isCompleted = false, nowMillis = 1_061_000L))
        assertEquals("Circa 9 min rimanenti", tracker.update(0.17, isCompleted = false, nowMillis = 1_088_000L))
        assertEquals("Circa 9 min rimanenti", tracker.update(0.199, isCompleted = false, nowMillis = 1_089_000L))

        // Raggiunge il 20% a +30s dal 10% -> 8 * 30s = 240s = 4 min
        assertEquals("Circa 4 min rimanenti", tracker.update(0.20, isCompleted = false, nowMillis = 1_090_000L))

        // Verso il 90% in 4s -> meno di un minuto rimanente
        tracker.update(0.80, isCompleted = false, nowMillis = 1_200_000L)
        assertEquals("Meno di un minuto rimanente", tracker.update(0.90, isCompleted = false, nowMillis = 1_204_000L))

        // Resume al 34%: attende il 40%
        tracker.reset(initialFraction = 0.34, atMillis = 2_000_000L)
        assertEquals("Calcolo tempo rimanente…", tracker.update(0.38, isCompleted = false, nowMillis = 2_020_000L))
        assertEquals("Circa 5 min rimanenti", tracker.update(0.40, isCompleted = false, nowMillis = 2_030_000L))

        // Completato -> null
        assertEquals(null, tracker.update(1.0, isCompleted = true, nowMillis = 2_100_000L))
    }
}
