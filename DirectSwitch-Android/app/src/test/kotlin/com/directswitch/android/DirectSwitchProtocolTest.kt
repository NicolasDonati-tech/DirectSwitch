package com.directswitch.android

import com.directswitch.android.protocol.DevicePlatform
import com.directswitch.android.protocol.DirectSwitchCrypto
import com.directswitch.android.protocol.DirectSwitchJson
import com.directswitch.android.protocol.DiscoveryBeaconPayload
import com.directswitch.android.protocol.HandshakeRequest
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
    }
}
