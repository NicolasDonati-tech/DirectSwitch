package com.directswitch.android

import com.directswitch.android.protocol.AndroidHeicCompatibilityConverter
import com.directswitch.android.protocol.ContactTransferRecord
import com.directswitch.android.protocol.DirectSwitchL10n
import com.directswitch.android.protocol.DirectSwitchLanguage
import com.directswitch.android.protocol.ManifestItem
import com.directswitch.android.protocol.NetworkIsolationDiagnostics
import com.directswitch.android.protocol.ReconciliationDiffCore
import com.directswitch.android.protocol.SmartCleanOptions
import com.directswitch.android.protocol.SmartCleanPreTransferEngine
import com.directswitch.android.protocol.ThermalGuardCore
import com.directswitch.android.protocol.ThermalGuardState
import com.directswitch.android.protocol.ThermalReading
import com.directswitch.android.protocol.TransferCategory
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class DirectSwitchPracticalProTest {

    @Test
    fun thermalGuard_triggersWarmThrottleAndCriticalCooldownAtThresholds() {
        assertEquals(ThermalGuardState.NORMAL, ThermalGuardCore.evaluate(ThermalReading(tempCelsius = 36.5, thermalStatusLevel = 0)))
        assertEquals(ThermalGuardState.WARM_THROTTLE, ThermalGuardCore.evaluate(ThermalReading(tempCelsius = 40.5, thermalStatusLevel = 1)))
        assertEquals(ThermalGuardState.WARM_THROTTLE, ThermalGuardCore.evaluate(ThermalReading(tempCelsius = 35.0, thermalStatusLevel = 2)))
        assertEquals(ThermalGuardState.CRITICAL_COOLDOWN, ThermalGuardCore.evaluate(ThermalReading(tempCelsius = 44.2, thermalStatusLevel = 2)))
        assertEquals(ThermalGuardState.CRITICAL_COOLDOWN, ThermalGuardCore.evaluate(ThermalReading(tempCelsius = null, thermalStatusLevel = 3)))
    }

    @Test
    fun smartClean_mergesDuplicateContactsAndFiltersExactPhotosAndOldScreenshots() {
        val c1 = ContactTransferRecord(
            id = "1",
            displayName = "Mario",
            phones = listOf("333 123 4567"),
            emails = listOf("mario@example.com")
        )
        val c2 = ContactTransferRecord(
            id = "2",
            displayName = "Mario Rossi",
            phones = listOf("+393331234567", "+39 02 5550199"),
            organization = "Acme Srl",
            birthdayYear = 1990
        )
        val c3 = ContactTransferRecord(
            id = "3",
            displayName = "Luca Verdi",
            phones = listOf("+393409998877")
        )
        val (merged, dupCount) = SmartCleanPreTransferEngine.mergeDuplicateContacts(listOf(c1, c2, c3))
        assertEquals(1, dupCount)
        assertEquals(2, merged.size)
        val mario = merged.first { it.displayName == "Mario Rossi" }
        assertEquals(2, mario.phones.size)
        assertEquals("Acme Srl", mario.organization)
        assertEquals(1990, mario.birthdayYear)

        val nowMs = 1_800_000_000_000L
        val twoYearsAgoMs = nowMs - 2L * 365L * 86_400_000L
        val items = listOf(
            ManifestItem("p1", TransferCategory.PHOTOS, "IMG_001.jpg", "Camera", 1_000_000L, nowMs - 10_000L, "d1"),
            ManifestItem("p2", TransferCategory.PHOTOS, "IMG_001_copy.jpg", "Download", 1_000_000L, nowMs - 5_000L, "d2"),
            ManifestItem("s1", TransferCategory.PHOTOS, "Screenshot_2024.png", "Screenshots", 500_000L, twoYearsAgoMs, "d3")
        )
        val hashes = mapOf("p1" to "aaa111", "p2" to "aaa111", "s1" to "bbb222")
        val filtered = SmartCleanPreTransferEngine.filterMediaSmartClean(
            entries = items,
            options = SmartCleanOptions(
                mergeDuplicateContacts = true,
                skipExactDuplicatePhotosSha256 = true,
                skipOldScreenshotsOlderThanMonths = 12
            ),
            nowMillis = nowMs,
            itemOf = { it },
            sha256Of = { hashes[it.id] }
        )
        assertEquals(listOf("p1"), filtered.kept.map { it.id })
        assertEquals(1, filtered.skippedDuplicatesCount)
        assertEquals(1, filtered.skippedOldScreenshotsCount)
        assertEquals(1_500_000L, filtered.savedBytes)
    }

    @Test
    fun reconciliationDiff_identifiesCommittedMissingAndHashMismatch() {
        val resp = ReconciliationDiffCore.evaluate(
            sentItemIds = listOf("ok1", "missing1", "corrupt1"),
            expectedHashesById = mapOf("ok1" to "h1", "missing1" to "h2", "corrupt1" to "h3"),
            committedHashesById = mapOf("ok1" to "h1", "corrupt1" to "h3_bad")
        )
        assertEquals(listOf("ok1"), resp.committedIds)
        assertEquals(listOf("missing1"), resp.missingIds)
        assertEquals(listOf("corrupt1"), resp.hashMismatchIds)
        assertEquals(1, resp.totalVerified)
    }

    @Test
    fun networkDiagnostics_andHeicDetector_workAccurately() {
        val apIso = NetworkIsolationDiagnostics.analyzePairingFailure(
            localIp = "192.168.1.45",
            targetIps = listOf("192.168.1.120"),
            isWifiConnected = true,
            errorMessage = "SocketTimeoutException: failed to connect"
        )
        assertTrue(apIso.likelyApClientIsolation)
        assertFalse(apIso.subnetMismatch)

        val diffSubnet = NetworkIsolationDiagnostics.analyzePairingFailure(
            localIp = "192.168.1.45",
            targetIps = listOf("10.0.0.12"),
            isWifiConnected = true,
            errorMessage = "timeout"
        )
        assertFalse(diffSubnet.likelyApClientIsolation)
        assertTrue(diffSubnet.subnetMismatch)

        assertTrue(AndroidHeicCompatibilityConverter.isHeicPhoto("IMG_1234.HEIC", "image/jpeg"))
        assertTrue(AndroidHeicCompatibilityConverter.isHeicPhoto("IMG_1234", "image/heif"))
        assertFalse(AndroidHeicCompatibilityConverter.isHeicPhoto("IMG_1234.jpg", "image/jpeg"))
    }

    @Test
    fun smartClean_skipsSha256HashingForUniquePhotoSizes() {
        val nowMs = 1_800_000_000_000L
        val items = listOf(
            ManifestItem("u1", TransferCategory.PHOTOS, "IMG_U1.jpg", "Camera", 1_111_111L, nowMs, "du1"),
            ManifestItem("u2", TransferCategory.PHOTOS, "IMG_U2.jpg", "Camera", 2_222_222L, nowMs, "du2"),
            ManifestItem("c1", TransferCategory.PHOTOS, "IMG_C1.jpg", "Camera", 3_333_333L, nowMs, "dc1"),
            ManifestItem("c2", TransferCategory.PHOTOS, "IMG_C2.jpg", "Camera", 3_333_333L, nowMs, "dc2")
        )
        val hashedIds = mutableListOf<String>()
        val res = SmartCleanPreTransferEngine.filterMediaSmartClean(
            entries = items,
            options = SmartCleanOptions(skipExactDuplicatePhotosSha256 = true),
            nowMillis = nowMs,
            itemOf = { it },
            sha256Of = {
                hashedIds.add(it.id)
                if (it.id.startsWith("c")) "same_hash" else "unique_${it.id}"
            }
        )
        assertEquals(listOf("c1", "c2"), hashedIds)
        assertEquals(listOf("u1", "u2", "c1"), res.kept.map { it.id })
        assertEquals(1, res.skippedDuplicatesCount)
    }

    @Test
    fun practicalProLocalization_translatesUiAndDiagnosticsInEnAndFr() {
        assertEquals(
            "Smart Clean & Pro Compatibility",
            DirectSwitchL10n.tr("Smart Clean & Compatibilità Pro", DirectSwitchLanguage.ENGLISH)
        )
        assertEquals(
            "Smart Clean & Compatibilité Pro",
            DirectSwitchL10n.tr("Smart Clean & Compatibilità Pro", DirectSwitchLanguage.FRENCH)
        )
        assertEquals(
            "Thermal cooldown (45s)",
            DirectSwitchL10n.tr("Raffreddamento termico (45s)", DirectSwitchLanguage.ENGLISH)
        )
        assertEquals(
            "Vérification SHA-256 Post-Migration : 100 % Intègre",
            DirectSwitchL10n.tr("Verifica SHA-256 Post-Migrazione: 100% Integro", DirectSwitchLanguage.FRENCH)
        )

        val enVerdict = NetworkIsolationDiagnostics.analyzePairingFailure(
            localIp = "192.168.1.45",
            targetIps = listOf("192.168.1.120"),
            isWifiConnected = true,
            errorMessage = "timeout",
            language = DirectSwitchLanguage.ENGLISH
        )
        assertTrue(enVerdict.title.contains("AP Client Isolation"))
        assertTrue(enVerdict.description.contains("same network"))

        val frVerdict = NetworkIsolationDiagnostics.analyzePairingFailure(
            localIp = "192.168.1.45",
            targetIps = listOf("10.0.0.12"),
            isWifiConnected = true,
            errorMessage = "timeout",
            language = DirectSwitchLanguage.FRENCH
        )
        assertTrue(frVerdict.title.contains("réseaux Wi-Fi différents"))

        val iosErrVerdict = NetworkIsolationDiagnostics.analyzePairingFailure(
            localIp = "192.168.1.45",
            targetIps = listOf("192.168.1.120"),
            isWifiConnected = true,
            errorMessage = "Impossibile collegarsi a iPhone sulla rete locale"
        )
        assertTrue(iosErrVerdict.likelyApClientIsolation)
    }

    @Test
    fun smartClean_filtersNativeIosScreenshotFlagEvenWithGenericCameraFilename() {
        val nowMs = 1_800_000_000_000L
        val twoYearsAgoMs = nowMs - 2L * 365L * 86_400_000L
        val items = listOf(
            ManifestItem(
                id = "ios_shot_1",
                category = TransferCategory.PHOTOS,
                fileName = "IMG_9999.PNG",
                relativeAlbumOrFolder = "iPhone_Camera",
                sizeBytes = 750_000L,
                capturedEpochMillis = twoYearsAgoMs,
                dedupKey = "img9999",
                isScreenshot = true
            ),
            ManifestItem(
                id = "fr_shot_1",
                category = TransferCategory.PHOTOS,
                fileName = "IMG_0002.PNG",
                relativeAlbumOrFolder = "Captures d\u2019écran",
                sizeBytes = 500_000L,
                capturedEpochMillis = twoYearsAgoMs,
                dedupKey = "img0002",
                isScreenshot = null
            ),
            ManifestItem(
                id = "ios_cam_1",
                category = TransferCategory.PHOTOS,
                fileName = "IMG_9998.HEIC",
                relativeAlbumOrFolder = "iPhone_Camera",
                sizeBytes = 2_500_000L,
                capturedEpochMillis = twoYearsAgoMs,
                dedupKey = "img9998",
                isScreenshot = null
            ),
            ManifestItem(
                id = "capture_one_keep",
                category = TransferCategory.PHOTOS,
                fileName = "IMG_5001.JPG",
                relativeAlbumOrFolder = "Capture One",
                sizeBytes = 1_800_000L,
                capturedEpochMillis = twoYearsAgoMs,
                dedupKey = "img5001",
                isScreenshot = null
            )
        )
        val res = SmartCleanPreTransferEngine.filterMediaSmartClean(
            entries = items,
            options = SmartCleanOptions(skipOldScreenshotsOlderThanMonths = 12),
            nowMillis = nowMs,
            itemOf = { it },
            sha256Of = { null }
        )
        assertEquals(listOf("ios_cam_1", "capture_one_keep"), res.kept.map { it.id })
        assertEquals(2, res.skippedOldScreenshotsCount)
        assertEquals(1_250_000L, res.savedBytes)
    }
}
