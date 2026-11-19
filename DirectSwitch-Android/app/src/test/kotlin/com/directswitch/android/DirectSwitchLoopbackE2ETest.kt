//
//  DirectSwitchLoopbackE2ETest.kt
//  DirectSwitch-Android
//
//  Created by Nicolas Donati.
//  Copyright © 2026 Nicolas Donati. Tutti i diritti riservati.
//

package com.directswitch.android

import com.directswitch.android.migrators.AndroidMediaFilterHelper
import com.directswitch.android.migrators.InstalledAppsScanner
import com.directswitch.android.protocol.ActiveTransferScope
import com.directswitch.android.protocol.CallLogTransferRecord
import com.directswitch.android.protocol.ContactTransferRecord
import com.directswitch.android.protocol.DevicePlatform
import com.directswitch.android.protocol.DirectSwitchCrypto
import com.directswitch.android.protocol.DirectSwitchJson
import com.directswitch.android.protocol.DirectSwitchL10n
import com.directswitch.android.protocol.DirectSwitchLanguage
import com.directswitch.android.protocol.HandshakeRequest
import com.directswitch.android.protocol.HandshakeResponse
import com.directswitch.android.protocol.ManifestItem
import com.directswitch.android.protocol.ManifestResponse
import com.directswitch.android.protocol.MediaTransferFilterOptions
import com.directswitch.android.protocol.MigrationReceiptBuilder
import com.directswitch.android.protocol.SecureTempFileShredder
import com.directswitch.android.protocol.SessionLicenseTier
import com.directswitch.android.protocol.SkippedTransferItemRecord
import com.directswitch.android.protocol.SpaceReliefActionKind
import com.directswitch.android.protocol.SpaceReliefPlanner
import com.directswitch.android.protocol.TransferCategory
import com.directswitch.android.protocol.TransferCheckpointRecord
import com.directswitch.android.protocol.TransferCheckpointStore
import com.directswitch.android.protocol.TransferCompletionReport
import com.directswitch.android.protocol.TransferConnectionMedium
import com.directswitch.android.protocol.TransferManifest
import com.directswitch.android.transport.LocalNetworkAddresses
import kotlinx.serialization.encodeToString
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.BufferedInputStream
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.File
import java.net.InetAddress
import java.net.ServerSocket
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import kotlin.random.Random

class DirectSwitchLoopbackE2ETest {

    @Test
    fun realTcpLoopbackEncryptedHandshakeManifestCsgcm1UploadAndComplete() {
        val sessionId = "ds_e2e_loopback_01"
        val sessionKeyHex = DirectSwitchCrypto.generateSessionKeyHex()
        val aesKey = DirectSwitchCrypto.deriveSessionAesKey(sessionKeyHex)

        // Payload audio simulato da 320 KB (copre più chunk CSGCM1)
        val originalPayload = Random(42).nextBytes(320 * 1024)
        val expectedItemId = "aud_voice_memo_01"
        val receivedBytesHolder = ByteArrayOutputStream()
        var receivedCallLogsCount = 0

        val serverSocket = ServerSocket(0, 16, InetAddress.getByName("127.0.0.1"))
        val port = serverSocket.localPort
        val executor = Executors.newSingleThreadExecutor()

        val serverFuture = executor.submit {
            var done = false
            while (!done) {
                val sock = serverSocket.accept()
                sock.use { s ->
                    val input = BufferedInputStream(s.getInputStream())
                    val output = s.getOutputStream()

                    fun readLineAscii(): String {
                        val bos = ByteArrayOutputStream()
                        while (true) {
                            val b = input.read()
                            if (b < 0 || b == '\n'.code) break
                            if (b != '\r'.code) bos.write(b)
                        }
                        return bos.toString("US-ASCII")
                    }

                    val reqLine = readLineAscii()
                    val parts = reqLine.split(" ")
                    val method = parts[0]
                    val path = parts[1]
                    val headers = mutableMapOf<String, String>()
                    while (true) {
                        val line = readLineAscii()
                        if (line.isEmpty()) break
                        val colon = line.indexOf(':')
                        if (colon > 0) {
                            headers[line.substring(0, colon).trim().lowercase()] = line.substring(colon + 1).trim()
                        }
                    }
                    val contentLen = headers["content-length"]?.toIntOrNull() ?: 0
                    val body = ByteArray(contentLen)
                    var read = 0
                    while (read < contentLen) {
                        val r = input.read(body, read, contentLen - read)
                        if (r < 0) break
                        read += r
                    }

                    fun sendResp(status: Int, contentType: String, payload: ByteArray) {
                        val head = "HTTP/1.1 $status OK\r\nContent-Type: $contentType\r\nContent-Length: ${payload.size}\r\nConnection: close\r\n\r\n"
                        output.write(head.toByteArray(Charsets.US_ASCII))
                        output.write(payload)
                        output.flush()
                    }

                    when {
                        method == "POST" && path == "/v1/handshake" -> {
                            val plain = DirectSwitchCrypto.openJsonEnvelope(body, aesKey)
                            val req = DirectSwitchJson.instance.decodeFromString<HandshakeRequest>(plain)
                            assertEquals(sessionId, req.sessionId)
                            val resp = HandshakeResponse(
                                accepted = true,
                                receiverName = "Loopback Receiver",
                                receiverPlatform = DevicePlatform.ANDROID,
                                freeStorageBytes = 64L * 1024L * 1024L * 1024L,
                                licenseTier = SessionLicenseTier.INTRA_OS_FREE,
                                hasEnoughSpace = true,
                                statusMessage = "OK"
                            )
                            val sealed = DirectSwitchCrypto.sealJsonEnvelope(DirectSwitchJson.instance.encodeToString(resp), aesKey)
                            sendResp(200, "application/octet-stream", sealed)
                        }

                        method == "POST" && path == "/v1/manifest" -> {
                            val plain = DirectSwitchCrypto.openJsonEnvelope(body, aesKey)
                            val manifest = DirectSwitchJson.instance.decodeFromString<TransferManifest>(plain)
                            receivedCallLogsCount = manifest.callLogsPayload?.size ?: 0
                            val resp = ManifestResponse(
                                acceptedItemIds = manifest.items.map { it.id },
                                skippedDuplicateCount = 0,
                                contactsMergedCount = manifest.contactsPayload.size,
                                contactsSkippedDuplicates = 0,
                                calendarsImportedCount = manifest.calendarsPayload.size,
                                smsImportedCount = manifest.smsPayload.size,
                                callLogsImportedCount = receivedCallLogsCount
                            )
                            val sealed = DirectSwitchCrypto.sealJsonEnvelope(DirectSwitchJson.instance.encodeToString(resp), aesKey)
                            sendResp(200, "application/octet-stream", sealed)
                        }

                        method == "PUT" && path == "/v1/item/$expectedItemId" -> {
                            val expectedSha = headers["x-ds-sha256"]!!
                            val expectedLen = headers["x-ds-plain-length"]!!.toLong()
                            val (plainBytes, shaHex) = DirectSwitchCrypto.decryptStreamCsgcm1(
                                ByteArrayInputStream(body),
                                receivedBytesHolder,
                                aesKey
                            )
                            assertEquals(expectedLen, plainBytes)
                            assertEquals(expectedSha, shaHex)
                            sendResp(200, "application/json", """{"ok":true,"bytes":$plainBytes}""".toByteArray())
                        }

                        method == "POST" && path == "/v1/complete" -> {
                            DirectSwitchCrypto.openJsonEnvelope(body, aesKey)
                            val report = TransferCompletionReport(
                                sessionId = sessionId,
                                licenseTier = SessionLicenseTier.INTRA_OS_FREE,
                                transferredFilesCount = 1,
                                transferredBytes = receivedBytesHolder.size().toLong(),
                                mergedContactsCount = 1,
                                importedCalendarsCount = 0,
                                importedSmsCount = 0,
                                callLogsImportedCount = receivedCallLogsCount,
                                skippedDuplicatesCount = 0,
                                elapsedMillis = 25L
                            )
                            val sealed = DirectSwitchCrypto.sealJsonEnvelope(DirectSwitchJson.instance.encodeToString(report), aesKey)
                            sendResp(200, "application/octet-stream", sealed)
                            done = true
                        }
                    }
                }
            }
        }

        try {
            val http = OkHttpClient.Builder()
                .connectTimeout(3, TimeUnit.SECONDS)
                .readTimeout(10, TimeUnit.SECONDS)
                .build()
            val baseUrl = "http://127.0.0.1:$port"

            fun postEnc(path: String, json: String): String {
                val sealed = DirectSwitchCrypto.sealJsonEnvelope(json, aesKey)
                val req = Request.Builder()
                    .url("$baseUrl$path")
                    .post(sealed.toRequestBody("application/octet-stream".toMediaType()))
                    .build()
                http.newCall(req).execute().use { resp ->
                    assertEquals(200, resp.code)
                    return DirectSwitchCrypto.openJsonEnvelope(resp.body!!.bytes(), aesKey)
                }
            }

            // 1. Handshake
            val hsJson = postEnc(
                "/v1/handshake",
                DirectSwitchJson.instance.encodeToString(
                    HandshakeRequest(
                        sessionId = sessionId,
                        senderName = "Loopback Sender",
                        senderPlatform = DevicePlatform.ANDROID,
                        senderHasPro = true,
                        totalEstimatedBytes = originalPayload.size.toLong(),
                        transferScope = ActiveTransferScope(contacts = true, audio = true, callLogs = true)
                    )
                )
            )
            val hsResp = DirectSwitchJson.instance.decodeFromString<HandshakeResponse>(hsJson)
            assertTrue(hsResp.accepted)
            assertTrue(hsResp.hasEnoughSpace)

            // 2. Manifest (contatti + chiamate + audio)
            val audioItem = ManifestItem(
                id = expectedItemId,
                category = TransferCategory.AUDIO,
                fileName = "Nota_Vocale.m4a",
                relativeAlbumOrFolder = "Audio_e_Memo",
                sizeBytes = originalPayload.size.toLong(),
                capturedEpochMillis = 1_760_000_000_000L,
                dedupKey = "audio_nota_vocale_${originalPayload.size}",
                mimeType = "audio/mp4"
            )
            val manifestJson = postEnc(
                "/v1/manifest",
                DirectSwitchJson.instance.encodeToString(
                    TransferManifest(
                        sessionId = sessionId,
                        senderPlatform = DevicePlatform.ANDROID,
                        items = listOf(audioItem),
                        contactsPayload = listOf(ContactTransferRecord("c1", "Mario Rossi", listOf("+393331234567"))),
                        callLogsPayload = listOf(
                            CallLogTransferRecord("cl1", "+393331234567", "Mario Rossi", 2, 1_760_000_000_000L, 45L),
                            CallLogTransferRecord("cl2", "+393409876543", null, 3, 1_760_000_100_000L, 0L)
                        ),
                        transferScope = ActiveTransferScope(contacts = true, audio = true, callLogs = true)
                    )
                )
            )
            val manifestResp = DirectSwitchJson.instance.decodeFromString<ManifestResponse>(manifestJson)
            assertEquals(listOf(expectedItemId), manifestResp.acceptedItemIds)
            assertEquals(1, manifestResp.contactsMergedCount)
            assertEquals(2, manifestResp.callLogsImportedCount)

            // 3. Upload streaming CSGCM1
            val encOut = ByteArrayOutputStream()
            val (plainLen, sha256Hex) = DirectSwitchCrypto.encryptStreamCsgcm1(
                ByteArrayInputStream(originalPayload),
                encOut,
                aesKey
            )
            val putReq = Request.Builder()
                .url("$baseUrl/v1/item/$expectedItemId")
                .header("X-DS-Plain-Length", plainLen.toString())
                .header("X-DS-Sha256", sha256Hex)
                .put(encOut.toByteArray().toRequestBody("application/octet-stream".toMediaType()))
                .build()
            http.newCall(putReq).execute().use { resp ->
                assertEquals(200, resp.code)
            }

            // 4. Complete
            val completeJson = postEnc("/v1/complete", """{"sessionId":"$sessionId"}""")
            val report = DirectSwitchJson.instance.decodeFromString<TransferCompletionReport>(completeJson)
            assertEquals(1, report.transferredFilesCount)
            assertEquals(originalPayload.size.toLong(), report.transferredBytes)
            assertEquals(2, report.callLogsImportedCount)
            assertArrayEquals(originalPayload, receivedBytesHolder.toByteArray())

            serverFuture.get(5, TimeUnit.SECONDS)
        } finally {
            runCatching { serverSocket.close() }
            executor.shutdownNow()
        }
    }

    @Test
    fun transferCheckpointStoreSaveLoadAndAutoExpiry() {
        val tempFile = File.createTempFile("ds_cp_test_", ".json")
        tempFile.delete()
        try {
            val nowMs = 1_760_000_000_000L
            val record = TransferCheckpointRecord(
                sessionId = "ds_cp_1",
                qrPayloadJson = """{"sessionId":"ds_cp_1","receiverName":"Pixel","receiverPlatform":"ANDROID","ips":["192.168.1.20"],"port":49443,"sessionKeyHex":"00"}""",
                receiverName = "Pixel",
                receiverPlatform = DevicePlatform.ANDROID,
                scope = ActiveTransferScope(photos = true, videos = true, audio = true),
                completedItemIds = listOf("p1", "p2", "p3"),
                uploadedBytes = 600_000_000L,
                totalItems = 10,
                totalBytes = 1_000_000_000L,
                skippedItems = listOf(SkippedTransferItemRecord("p4", "bad.jpg", TransferCategory.PHOTOS, 1024L, "Non leggibile")),
                filterOptions = MediaTransferFilterOptions(photosLastYearOnly = true),
                savedAtEpochMillis = nowMs
            )
            assertEquals(60, record.completionPercent())
            TransferCheckpointStore.save(tempFile, record)

            val loaded = TransferCheckpointStore.load(tempFile, nowEpochMillis = nowMs + 60_000L)
            assertNotNull(loaded)
            assertEquals("ds_cp_1", loaded!!.sessionId)
            assertEquals(3, loaded.completedItemIds.size)
            assertEquals(1, loaded.skippedItems.size)
            assertTrue(loaded.filterOptions.photosLastYearOnly)

            // Scaduto dopo > 24 ore -> restituisce null e pulisce
            val expired = TransferCheckpointStore.load(tempFile, nowEpochMillis = nowMs + 25L * 3_600_000L)
            assertNull(expired)
            assertFalse(tempFile.exists())
        } finally {
            tempFile.delete()
        }
    }

    @Test
    fun spaceReliefPlannerComputesActionableOptions() {
        val nowMs = 1_760_000_000_000L
        val twoYearsAgo = nowMs - 730L * 86_400_000L
        val items = listOf(
            ManifestItem("v_heavy", TransferCategory.VIDEOS, "4k.mp4", "Camera", 900_000_000L, nowMs, "k1"),
            ManifestItem("v_small", TransferCategory.VIDEOS, "clip.mp4", "Camera", 150_000_000L, twoYearsAgo, "k2"),
            ManifestItem("p_old", TransferCategory.PHOTOS, "old.jpg", "Camera", 400_000_000L, twoYearsAgo, "k3"),
            ManifestItem("p_new", TransferCategory.PHOTOS, "new.jpg", "Camera", 100_000_000L, nowMs, "k4")
        )
        // Spazio libero sufficiente (5 GB) -> nessuna offerta
        assertNull(SpaceReliefPlanner.evaluate("Pixel", 5_000_000_000L, items, nowMs))

        // Spazio libero insufficiente (1 GB) -> genera opzioni Salva-Spazio
        val offer = SpaceReliefPlanner.evaluate("Pixel", 1_000_000_000L, items, nowMs)
        assertNotNull(offer)
        assertTrue(offer!!.options.any { it.kind == SpaceReliefActionKind.EXCLUDE_HEAVY_VIDEOS_300MB && it.fitsAvailableSpace })
        assertTrue(offer.options.any { it.kind == SpaceReliefActionKind.LAST_YEAR_MEDIA_ONLY })
        assertTrue(offer.options.any { it.kind == SpaceReliefActionKind.EXCLUDE_ALL_VIDEOS && it.fitsAvailableSpace })
    }

    @Test
    fun secureTempFileShredderOverwritesAndDeletesFile() {
        val tmp = File.createTempFile("ds_pwd_test_", ".csv")
        tmp.writeText("name,url,username,password\nBank,https://bank.it,user,supersecret123")
        assertTrue(tmp.exists())
        assertTrue(SecureTempFileShredder.shredAndDelete(tmp))
        assertFalse(tmp.exists())
        assertFalse(SecureTempFileShredder.shredAndDelete(tmp))
    }

    @Test
    fun mediaFilterHelperFiltersByLastYearAlbumsAndMaxVideoBytes() {
        val nowMs = 1_760_000_000_000L
        val oldMs = nowMs - 400L * 86_400_000L
        val recentPhotoVacanze = ManifestItem("p1", TransferCategory.PHOTOS, "a.jpg", "Vacanze", 2_000_000L, nowMs - 10_000L, "k1")
        val oldPhotoCamera = ManifestItem("p2", TransferCategory.PHOTOS, "b.jpg", "Camera", 2_000_000L, oldMs, "k2")
        val heavyVideo = ManifestItem("v1", TransferCategory.VIDEOS, "big.mp4", "Camera", 600_000_000L, nowMs, "k3")
        val lightVideo = ManifestItem("v2", TransferCategory.VIDEOS, "ok.mp4", "Camera", 100_000_000L, nowMs, "k4")

        val opts = MediaTransferFilterOptions(
            photosLastYearOnly = true,
            selectedPhotoAlbums = listOf("Vacanze"),
            videosLastYearOnly = true,
            maxVideoBytes = 500_000_000L
        )
        assertTrue(AndroidMediaFilterHelper.matchesFilter(recentPhotoVacanze, opts, nowMs))
        assertFalse(AndroidMediaFilterHelper.matchesFilter(oldPhotoCamera, opts, nowMs))
        assertFalse(AndroidMediaFilterHelper.matchesFilter(heavyVideo, opts, nowMs))
        assertTrue(AndroidMediaFilterHelper.matchesFilter(lightVideo, opts, nowMs))
    }

    @Test
    fun multilingualLocalizationReceiptAndCuratedCatalogUniqueness() {
        assertEquals("Receive data", DirectSwitchL10n.text("nav_receive", DirectSwitchLanguage.ENGLISH, "Ricevi dati"))
        assertEquals("Recibir datos", DirectSwitchL10n.text("nav_receive", DirectSwitchLanguage.SPANISH, "Ricevi dati"))
        assertEquals("Recevoir", DirectSwitchL10n.text("nav_receive", DirectSwitchLanguage.FRENCH, "Ricevi dati"))
        assertEquals("Empfangen", DirectSwitchL10n.text("nav_receive", DirectSwitchLanguage.GERMAN, "Ricevi dati"))
        assertEquals("Ricevi dati", DirectSwitchL10n.text("nav_receive", DirectSwitchLanguage.ITALIAN, "Ricevi dati"))

        val checklist = MigrationReceiptBuilder.defaultChecklist(hasWhatsApp = true, hasApps = true, hasSkipped = true)
        assertEquals(6, checklist.size)
        val receipt = MigrationReceiptBuilder.buildReceiptText(
            peerName = "iPhone di Nicolas",
            isReceiver = false,
            connectionMedium = TransferConnectionMedium.USB_CABLE,
            completedFiles = 120,
            totalBytes = 4_500_000_000L,
            mergedContacts = 350,
            importedCalendars = 42,
            importedReminders = 15,
            importedSms = 88,
            importedCallLogs = 64,
            appsCount = 40,
            skippedCount = 0
        )
        assertTrue(receipt.contains("Cavo USB-C diretto"))
        assertTrue(receipt.contains("Chiamate salvate: 64"))
        assertTrue(receipt.contains("AES-256-GCM"))

        // Catalogo extra Android esteso e privo di duplicati
        val curated = InstalledAppsScanner.curatedExtraAndroidCategories
        assertTrue("Attese almeno 9 categorie extra Android", curated.size >= 9)
        val seenPkgs = HashSet<String>()
        for (cat in curated) {
            assertTrue("Categoria ${cat.id} non deve essere vuota", cat.apps.isNotEmpty())
            for (app in cat.apps) {
                assertTrue("Package duplicato nel catalogo extra Android: ${app.packageName}", seenPkgs.add(app.packageName.lowercase()))
            }
        }
        assertTrue("Attese almeno 100 app nel catalogo extra Android, trovate ${seenPkgs.size}", seenPkgs.size >= 100)

        // Priorità interfacce cablate USB-C / Ethernet / P2P
        assertTrue(LocalNetworkAddresses.isWiredInterfaceName("rndis0"))
        assertTrue(LocalNetworkAddresses.isWiredInterfaceName("eth0"))
        assertTrue(LocalNetworkAddresses.isWiredInterfaceName("usb0"))
        assertFalse(LocalNetworkAddresses.isWiredInterfaceName("wlan0"))
        assertTrue(LocalNetworkAddresses.isP2pInterfaceName("p2p-wlan0-0"))
        assertTrue(LocalNetworkAddresses.isP2pInterfaceName("ap0"))
    }
}
