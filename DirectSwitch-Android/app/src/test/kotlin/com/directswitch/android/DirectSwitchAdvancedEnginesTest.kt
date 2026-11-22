//
//  DirectSwitchAdvancedEnginesTest.kt
//  DirectSwitch-Android
//
//  Created by Nicolas Donati.
//  Copyright © 2026 Nicolas Donati. Tutti i diritti riservati.
//

package com.directswitch.android

import com.directswitch.android.protocol.ActiveTransferScope
import com.directswitch.android.protocol.BatteryTriagePlanner
import com.directswitch.android.protocol.CallLogTransferRecord
import com.directswitch.android.protocol.CompletedMigrationRecord
import com.directswitch.android.protocol.CompletedMigrationStore
import com.directswitch.android.protocol.CrossOsCodecCompatibilityHelper
import com.directswitch.android.protocol.DevicePlatform
import com.directswitch.android.protocol.DirectSwitchMotionPhotoCodec
import com.directswitch.android.protocol.ManifestItem
import com.directswitch.android.protocol.MediaTimelineHealer
import com.directswitch.android.protocol.SmsTransferRecord
import com.directswitch.android.protocol.SpaceReliefActionKind
import com.directswitch.android.protocol.SpaceReliefPlanner
import com.directswitch.android.protocol.TransferCategory
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.ByteArrayOutputStream
import java.io.File
import java.util.Calendar

class DirectSwitchAdvancedEnginesTest {

    @Test
    fun timelineHealer_reconstructsWhatsAppPixelScreenshotAndOverridesCopyDate() {
        val nowMs = 1_795_000_000_000L // Nov 2026

        val wa = MediaTimelineHealer.resolveBestCaptureEpochMillis(
            fileName = "IMG-20210814-WA0023.jpg",
            reportedEpochMillis = nowMs - 1_000L, // sembra copiata oggi
            nowEpochMillis = nowMs
        )
        assertTrue(wa.wasHealedFromFilename)
        assertEquals("whatsapp_wa", wa.sourcePattern)
        val calWa = Calendar.getInstance().apply { timeInMillis = wa.epochMillis }
        assertEquals(2021, calWa.get(Calendar.YEAR))
        assertEquals(Calendar.AUGUST, calWa.get(Calendar.MONTH))
        assertEquals(14, calWa.get(Calendar.DAY_OF_MONTH))

        val pxl = MediaTimelineHealer.resolveBestCaptureEpochMillis(
            fileName = "PXL_20230719_182205.jpg",
            reportedEpochMillis = 0L,
            nowEpochMillis = nowMs
        )
        assertTrue(pxl.wasHealedFromFilename)
        val calPxl = Calendar.getInstance().apply { timeInMillis = pxl.epochMillis }
        assertEquals(2023, calPxl.get(Calendar.YEAR))
        assertEquals(Calendar.JULY, calPxl.get(Calendar.MONTH))
        assertEquals(19, calPxl.get(Calendar.DAY_OF_MONTH))
        assertEquals(18, calPxl.get(Calendar.HOUR_OF_DAY))

        // Se l'EXIF ha già una data storica valida non viene sovrascritta
        val authenticOldMs = 1_600_000_000_000L
        val untouched = MediaTimelineHealer.resolveBestCaptureEpochMillis(
            fileName = "IMG-20210814-WA0023.jpg",
            reportedEpochMillis = authenticOldMs,
            nowEpochMillis = nowMs
        )
        assertFalse(untouched.wasHealedFromFilename)
        assertEquals(authenticOldMs, untouched.epochMillis)
    }

    @Test
    fun audioCodecHealer_identifiesIosHostileFormats() {
        assertTrue(CrossOsCodecCompatibilityHelper.needsAudioTranscodeForIos("PTT-20260101-WA0001.opus", "audio/ogg"))
        assertTrue(CrossOsCodecCompatibilityHelper.needsAudioTranscodeForIos("memo.amr", "audio/amr"))
        assertFalse(CrossOsCodecCompatibilityHelper.needsAudioTranscodeForIos("voice.m4a", "audio/mp4"))
        assertFalse(CrossOsCodecCompatibilityHelper.needsAudioTranscodeForIos("song.mp3", "audio/mpeg"))
        assertEquals("PTT-20260101-WA0001.m4a", CrossOsCodecCompatibilityHelper.healedM4aFileName("PTT-20260101-WA0001.opus"))
    }

    @Test
    fun motionPhotoCodec_roundTripsStillAndMp4Cleanly() {
        val dir = java.nio.file.Files.createTempDirectory("ds_motion_test").toFile()
        try {
            val stillBytes = ByteArrayOutputStream().apply {
                write(byteArrayOf(0xFF.toByte(), 0xD8.toByte(), 0xFF.toByte(), 0xDB.toByte(), 0x00, 0x06, 1, 2, 3, 4))
                write(ByteArray(2048) { (it % 200).toByte() })
                write(byteArrayOf(0xFF.toByte(), 0xD9.toByte()))
            }.toByteArray()
            val mp4Bytes = ByteArrayOutputStream().apply {
                write(byteArrayOf(0x00, 0x00, 0x00, 0x18))
                write("ftypisom".toByteArray(Charsets.US_ASCII))
                write(ByteArray(3000) { ((it * 7) % 251).toByte() })
            }.toByteArray()

            val stillFile = File(dir, "still.jpg").apply { writeBytes(stillBytes) }
            val mp4File = File(dir, "clip.mp4").apply { writeBytes(mp4Bytes) }
            val builtFile = File(dir, "motion.jpg")

            DirectSwitchMotionPhotoCodec.buildMotionPhotoJpegToFile(stillFile, mp4File, 450_000L, builtFile)
            assertTrue(DirectSwitchMotionPhotoCodec.looksLikeMotionPhotoCandidateQuick(builtFile))

            val extractedStill = File(dir, "out_still.jpg")
            val extractedVideo = File(dir, "out_clip.mp4")
            val parsed = DirectSwitchMotionPhotoCodec.parseMotionPhotoFile(builtFile, extractedStill, extractedVideo)
            assertNotNull(parsed)
            assertEquals("xmp_container", parsed!!.detectionSource)
            assertEquals(450_000L, parsed.presentationTimestampUs)
            assertTrue(mp4Bytes.contentEquals(extractedVideo.readBytes()))
        } finally {
            dir.deleteRecursively()
        }
    }

    @Test
    fun batteryTriagePlanner_activatesUnder15AndPrioritizesVitalDataFirst() {
        assertTrue(BatteryTriagePlanner.shouldAutoActivate(12, isCharging = false))
        assertFalse(BatteryTriagePlanner.shouldAutoActivate(12, isCharging = true))
        assertFalse(BatteryTriagePlanner.shouldAutoActivate(25, isCharging = false))

        val items = listOf(
            ManifestItem("v_heavy", TransferCategory.VIDEOS, "4k.mp4", "Camera", 250_000_000L, 5000L, "k1"),
            ManifestItem("p_old", TransferCategory.PHOTOS, "old.jpg", "Camera", 2_000_000L, 1000L, "k2"),
            ManifestItem("p_fav", TransferCategory.PHOTOS, "fav.jpg", "Camera", 3_000_000L, 2000L, "k3", isFavorite = true),
            ManifestItem("doc_big", TransferCategory.DOCUMENTS, "manual.pdf", "Docs", 10_000_000L, 1000L, "k4"),
            ManifestItem("doc_small", TransferCategory.DOCUMENTS, "iban.pdf", "Docs", 120_000L, 1000L, "k5"),
            ManifestItem("pwd", TransferCategory.DOCUMENTS, "passwords.csv", "Password_e_Accessi", 15_000L, 1000L, "k6"),
            ManifestItem("aud", TransferCategory.AUDIO, "memo.m4a", "Audio", 500_000L, 3000L, "k7")
        )
        val sortedIds = BatteryTriagePlanner.sortByTriagePriority(items) { it }.map { it.id }
        assertEquals(listOf("pwd", "doc_small", "doc_big", "aud", "p_fav", "p_old", "v_heavy"), sortedIds)
    }

    @Test
    fun completedMigrationStore_persistsAndFiltersOnlyDeltaItems() {
        val dir = java.nio.file.Files.createTempDirectory("ds_delta_test").toFile()
        try {
            val file = File(dir, "completed.json")
            val completedAt = 1_790_000_000_000L
            val rec = CompletedMigrationRecord(
                sessionId = "ds_abc",
                peerName = "iPhone 16 Pro",
                peerPlatform = DevicePlatform.IOS,
                completedAtEpochMillis = completedAt,
                transferredFilesCount = 120,
                transferredBytes = 500_000_000L,
                transferredDedupKeys = listOf("old_seen_key"),
                lastScope = ActiveTransferScope(contacts = true, photos = true)
            )
            CompletedMigrationStore.save(file, rec)
            val loaded = CompletedMigrationStore.load(file, nowEpochMillis = completedAt + 3L * 86_400_000L)
            assertNotNull(loaded)
            assertEquals(3, loaded!!.daysSinceCompleted(completedAt + 3L * 86_400_000L))

            val candidates = listOf(
                ManifestItem("1", TransferCategory.PHOTOS, "old.jpg", "", 1000L, completedAt - 86_400_000L, "old_unseen"),
                ManifestItem("2", TransferCategory.PHOTOS, "dup.jpg", "", 1000L, completedAt + 60_000L, "old_seen_key"),
                ManifestItem("3", TransferCategory.PHOTOS, "new.jpg", "", 1000L, completedAt + 3_600_000L, "brand_new_key")
            )
            val delta = CompletedMigrationStore.filterDeltaEntries(candidates, loaded) { it }
            assertEquals(listOf("3"), delta.map { it.id })

            val smsDelta = CompletedMigrationStore.filterDeltaSms(
                listOf(
                    SmsTransferRecord("s1", "+39333", "vecchio", completedAt - 10_000_000L),
                    SmsTransferRecord("s2", "+39333", "nuovo", completedAt + 120_000L)
                ),
                loaded
            )
            assertEquals(listOf("s2"), smsDelta.map { it.id })

            val callDelta = CompletedMigrationStore.filterDeltaCallLogs(
                listOf(
                    CallLogTransferRecord("c1", "+39333", null, 1, completedAt - 10_000_000L, 10L),
                    CallLogTransferRecord("c2", "+39333", null, 2, completedAt + 120_000L, 30L)
                ),
                loaded
            )
            assertEquals(listOf("c2"), callDelta.map { it.id })

            // Scade dopo 30 giorni
            val expired = CompletedMigrationStore.load(file, nowEpochMillis = completedAt + 31L * 86_400_000L)
            assertNull(expired)
        } finally {
            dir.deleteRecursively()
        }
    }

    @Test
    fun motionPhotoZeroWriteProbe_detectsHeaderAndSamsungTailMarkers() {
        val plainJpegHead = byteArrayOf(0xFF.toByte(), 0xD8.toByte(), 0xFF.toByte(), 0xE0.toByte()) +
            "JFIF normal static photo".toByteArray(Charsets.US_ASCII)
        assertFalse(DirectSwitchMotionPhotoCodec.looksLikeMotionPhotoHeaderBytes(plainJpegHead))
        assertFalse(DirectSwitchMotionPhotoCodec.looksLikeMotionPhotoTailBytes(plainJpegHead))

        val xmpHead = "http://ns.adobe.com/xap/1.0/ <Camera:MotionPhoto>1</Camera:MotionPhoto>".toByteArray(Charsets.US_ASCII)
        assertTrue(DirectSwitchMotionPhotoCodec.looksLikeMotionPhotoHeaderBytes(xmpHead))

        val samsungTail = "padding...MotionPhoto_Data...SEFT".toByteArray(Charsets.US_ASCII)
        assertTrue(DirectSwitchMotionPhotoCodec.looksLikeMotionPhotoTailBytes(samsungTail))
    }

    @Test
    fun spaceReliefPlanner_proposesOnlyLocalPhoneToPhoneOptions() {
        val now = 1_795_000_000_000L
        val oldMs = now - 500L * 86_400_000L
        val recentMs = now - 30L * 86_400_000L
        val items = listOf(
            ManifestItem("recent_1", TransferCategory.PHOTOS, "r1.jpg", "Camera", 400_000_000L, recentMs, "r1"),
            ManifestItem("old_1", TransferCategory.VIDEOS, "o1.mp4", "Camera", 900_000_000L, oldMs, "o1")
        )
        val freeBytes = 800_000_000L
        val offer = SpaceReliefPlanner.evaluate("iPhone 16", freeBytes, items, now)
        assertNotNull(offer)
        assertTrue(offer!!.options.any { it.kind == SpaceReliefActionKind.LAST_YEAR_MEDIA_ONLY && it.fitsAvailableSpace })
        assertTrue(offer.options.any { it.kind == SpaceReliefActionKind.EXCLUDE_HEAVY_VIDEOS_300MB && it.fitsAvailableSpace })
        assertFalse(offer.options.any { it.title.contains("CloudSave", ignoreCase = true) })
    }
}
