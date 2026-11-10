//
//  DirectSwitchTransportEngine.kt
//  DirectSwitch-Android
//
//  Created by Nicolas Donati.
//  Copyright © 2026 Nicolas Donati. Tutti i diritti riservati.
//

package com.directswitch.android.transport

import android.annotation.SuppressLint
import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.net.Uri
import android.net.wifi.WifiManager
import android.net.wifi.WifiNetworkSpecifier
import android.os.Build
import android.os.Handler
import android.os.Looper
import com.directswitch.android.DirectSwitchLog
import com.directswitch.android.migrators.CalendarMigrator
import com.directswitch.android.migrators.CloudSaveEntitlementDetector
import com.directswitch.android.migrators.ContactsSmartMerger
import com.directswitch.android.migrators.DocumentsAndWhatsAppScanner
import com.directswitch.android.migrators.MediaExifScannerAndImporter
import com.directswitch.android.migrators.PublicDownloadsSaver
import com.directswitch.android.migrators.SmsSystemScanner
import com.directswitch.android.migrators.StorageCapacityChecker
import com.directswitch.android.protocol.ContactTransferRecord
import com.directswitch.android.protocol.DevicePlatform
import com.directswitch.android.protocol.DirectSwitchCrypto
import com.directswitch.android.protocol.DirectSwitchJson
import com.directswitch.android.protocol.DiscoveryBeaconPayload
import com.directswitch.android.protocol.HandshakeRequest
import com.directswitch.android.protocol.HandshakeResponse
import com.directswitch.android.protocol.LicensePolicyEvaluator
import com.directswitch.android.protocol.ManifestItem
import com.directswitch.android.protocol.ManifestResponse
import com.directswitch.android.protocol.PinPairingRequest
import com.directswitch.android.protocol.QrPairingPayload
import com.directswitch.android.protocol.SessionLicenseTier
import com.directswitch.android.protocol.TransferCategory
import com.directswitch.android.protocol.TransferCompletionReport
import com.directswitch.android.protocol.TransferManifest
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull
import kotlinx.serialization.encodeToString
import kotlin.coroutines.resume
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody
import okhttp3.RequestBody.Companion.toRequestBody
import okio.BufferedSink
import java.io.BufferedInputStream
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.InputStream
import java.io.OutputStream
import java.net.Inet4Address
import java.net.InetSocketAddress
import java.net.NetworkInterface
import java.net.ServerSocket
import java.net.Socket
import java.util.Collections
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.atomic.AtomicLong

data class LiveTransferProgress(
    val phaseLabel: String = "In attesa di connessione...",
    val peerDeviceName: String = "",
    val peerPlatform: DevicePlatform? = null,
    val licenseTier: SessionLicenseTier? = null,
    val currentFileName: String = "",
    val completedItems: Int = 0,
    val totalItems: Int = 0,
    val transferredBytes: Long = 0L,
    val totalBytes: Long = 0L,
    val speedMegabytesPerSec: Double = 0.0,
    val mergedContacts: Int = 0,
    val importedCalendars: Int = 0,
    val importedSms: Int = 0,
    val skippedDuplicates: Int = 0,
    val isCompleted: Boolean = false,
    val errorMessage: String? = null
)

object LocalNetworkAddresses {
    /**
     * Il canale HTTP è in chiaro solo sul trasporto locale (il payload è interamente cifrato AES-256-GCM):
     * accettiamo ESCLUSIVAMENTE destinazioni di rete locale privata (10/8, 172.16/12, 192.168/16, link-local 169.254/16).
     */
    fun isLocalNetworkIpv4(ip: String): Boolean {
        val parts = ip.split(".")
        if (parts.size != 4) return false
        val o = parts.map { it.toIntOrNull() ?: return false }
        if (o.any { it !in 0..255 }) return false
        return o[0] == 10 ||
            (o[0] == 172 && o[1] in 16..31) ||
            (o[0] == 192 && o[1] == 168) ||
            (o[0] == 169 && o[1] == 254)
    }

    fun listPrivateIpv4Addresses(): List<String> {
        val out = mutableListOf<String>()
        try {
            val interfaces = Collections.list(NetworkInterface.getNetworkInterfaces())
            for (nif in interfaces) {
                if (!nif.isUp || nif.isLoopback) continue
                for (addr in Collections.list(nif.inetAddresses)) {
                    if (addr is Inet4Address && !addr.isLoopbackAddress) {
                        val ip = addr.hostAddress ?: continue
                        if (isLocalNetworkIpv4(ip) && !ip.startsWith("169.254.")) {
                            out.add(ip)
                        }
                    }
                }
            }
        } catch (t: Throwable) {
            DirectSwitchLog.warn("Lettura indirizzi di rete fallita", t)
        }
        return out.distinct()
    }
}

/**
 * Controller per l'Hotspot 5GHz locale diretto (offline, senza consumare dati mobili).
 * Attende brevemente la configurazione dell'interfaccia `ap0`/`wlan1` così l'IP reale dell'Hotspot
 * (randomizzato su Android 12+) è subito disponibile per il QR Code.
 */
class LocalOnlyHotspotController(private val context: Context) {
    private var reservation: WifiManager.LocalOnlyHotspotReservation? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    @SuppressLint("MissingPermission")
    fun startHotspot(onResult: (ssid: String?, password: String?, error: String?) -> Unit) {
        val wifiManager = context.applicationContext.getSystemService(Context.WIFI_SERVICE) as? WifiManager
        if (wifiManager == null) {
            onResult(null, null, "Servizio Wi-Fi non disponibile")
            return
        }
        try {
            wifiManager.startLocalOnlyHotspot(
                object : WifiManager.LocalOnlyHotspotCallback() {
                    override fun onStarted(res: WifiManager.LocalOnlyHotspotReservation?) {
                        reservation = res
                        @Suppress("DEPRECATION")
                        val ssid = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                            res?.softApConfiguration?.ssid
                        } else {
                            res?.wifiConfiguration?.SSID
                        }
                        @Suppress("DEPRECATION")
                        val pass = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                            res?.softApConfiguration?.passphrase
                        } else {
                            res?.wifiConfiguration?.preSharedKey
                        }
                        // Attende 450ms affinché il kernel assegni l'IPv4 all'interfaccia softAP
                        mainHandler.postDelayed({
                            onResult(ssid, pass, null)
                        }, 450L)
                    }

                    override fun onFailed(reason: Int) {
                        onResult(null, null, "Hotspot locale non avviato (codice $reason). Usa la Wi-Fi locale.")
                    }
                },
                mainHandler
            )
        } catch (_: SecurityException) {
            onResult(null, null, "Permesso Dispositivi Wi-Fi vicini / Posizione mancante per Hotspot locale")
        } catch (t: Throwable) {
            onResult(null, null, t.localizedMessage ?: "Errore avvio Hotspot locale")
        }
    }

    fun stopHotspot() {
        try {
            reservation?.close()
        } catch (t: Throwable) {
            DirectSwitchLog.warn("Chiusura hotspot fallita", t)
        } finally {
            reservation = null
        }
    }
}

/**
 * Server TCP/HTTP1.1 locale ad alte prestazioni:
 * - Tutti gli endpoint di trasferimento (`/v1/handshake`, `/v1/manifest`, `/v1/item/{id}`, `/v1/complete`)
 *   sono cifrati e autenticati tramite `CSGCM1` AES-256-GCM.
 * - L'accoppiamento da Auto-Discovery (`/v1/pair-pin`) richiede il PIN a 6 cifre mostrato sul ricevente,
 *   è monouso e si blocca dopo 3 tentativi errati.
 * - Il portale di installazione guidata (`/start`, `/download/directswitch.apk`, `/download/contacts.vcf`)
 *   è disabilitato per default e si attiva SOLO su richiesta esplicita protetto da token segreto a 128 bit.
 */
class DirectSwitchTransferServer(
    private val context: Context,
    private val port: Int = 49443
) {
    companion object {
        private const val MAX_PIN_ATTEMPTS = 3
    }

    private val running = AtomicBoolean(false)
    private var serverSocket: ServerSocket? = null
    private val executor = Executors.newCachedThreadPool()

    private val _progress = MutableStateFlow(LiveTransferProgress())
    val progress: StateFlow<LiveTransferProgress> = _progress

    private val _activePairingPin = MutableStateFlow("")
    val activePairingPin: StateFlow<String> = _activePairingPin

    private var activeSessionId: String = ""
    private var activeQrPayloadSnapshot: QrPairingPayload? = null
    private var sessionAesKey: ByteArray = ByteArray(32)
    private var bootstrapSecretToken: String? = null
    private var activeTier: SessionLicenseTier = SessionLicenseTier.INTRA_OS_FREE
    private val handshakeCompleted = AtomicBoolean(false)
    private val pinPairingConsumed = AtomicBoolean(false)
    private val pinFailedAttempts = AtomicInteger(0)
    private val manifestMap = ConcurrentHashMap<String, ManifestItem>()
    private val completedIds = ConcurrentHashMap.newKeySet<String>()
    private val transferredBytesCounter = AtomicLong(0L)
    private val completedFilesCounter = AtomicInteger(0)
    private var transferStartMillis = 0L

    fun startReceiverSession(
        wifiSsid: String? = null,
        wifiPass: String? = null
    ): QrPairingPayload {
        stop()
        bootstrapSecretToken = null
        val sessionId = "ds_${DirectSwitchCrypto.toHexLower(DirectSwitchCrypto.randomBytes(8))}"
        val sessionKeyHex = DirectSwitchCrypto.generateSessionKeyHex()
        val pin = DirectSwitchCrypto.generatePairingPin()
        activeSessionId = sessionId
        _activePairingPin.value = pin
        pinPairingConsumed.set(false)
        pinFailedAttempts.set(0)
        sessionAesKey = DirectSwitchCrypto.deriveSessionAesKey(sessionKeyHex)
        handshakeCompleted.set(false)
        manifestMap.clear()
        completedIds.clear()
        transferredBytesCounter.set(0L)
        completedFilesCounter.set(0)

        val boundPort = bindAndAcceptLoop()
        DirectSwitchKeepAliveService.start(context, "Ricezione dati attiva sulla rete locale")
        val candidateIps = LocalNetworkAddresses.listPrivateIpv4Addresses().ifEmpty { listOf("192.168.43.1") }
        val receiverHasPro = CloudSaveEntitlementDetector.isLocalProUnlocked(context) ||
            CloudSaveEntitlementDetector.hasVerifiedCloudSaveProEntitlement(context)
        val modelName = "${Build.MANUFACTURER.replaceFirstChar { it.uppercase() }} ${Build.MODEL}".trim()

        _progress.value = LiveTransferProgress(
            phaseLabel = "In ascolto sulla porta $boundPort — Inquadra il QR o inserisci il PIN $pin"
        )

        val payload = QrPairingPayload(
            sessionId = sessionId,
            receiverName = modelName,
            receiverPlatform = DevicePlatform.ANDROID,
            ips = candidateIps,
            port = boundPort,
            sessionKeyHex = sessionKeyHex,
            wifiSsid = wifiSsid,
            wifiPass = wifiPass,
            receiverHasPro = receiverHasPro
        )
        activeQrPayloadSnapshot = payload
        return payload
    }

    /**
     * Avvia esclusivamente il portale di installazione guidata sul Vecchio Telefono protetto da token a 128 bit,
     * restituendo l'URL completo da codificare nel QR di Bootstrap.
     */
    fun startBootstrapPortalSession(): String {
        stop()
        val token = DirectSwitchCrypto.toHexLower(DirectSwitchCrypto.randomBytes(16))
        bootstrapSecretToken = token
        activeSessionId = ""
        _activePairingPin.value = ""
        activeQrPayloadSnapshot = null
        handshakeCompleted.set(false)

        val boundPort = bindAndAcceptLoop()
        DirectSwitchKeepAliveService.start(context, "Portale di installazione guidata attivo")
        val ip = LocalNetworkAddresses.listPrivateIpv4Addresses().firstOrNull() ?: "192.168.43.1"
        return "http://$ip:$boundPort/start?token=$token"
    }

    private fun bindAndAcceptLoop(): Int {
        val socket = ServerSocket()
        socket.reuseAddress = true
        socket.bind(InetSocketAddress(port))
        val boundPort = socket.localPort
        serverSocket = socket
        running.set(true)

        executor.execute {
            while (running.get()) {
                try {
                    val client = socket.accept()
                    client.tcpNoDelay = true
                    executor.execute { handleClientSocket(client) }
                } catch (t: Throwable) {
                    if (running.get()) {
                        DirectSwitchLog.warn("Accept connessione fallito", t)
                    }
                    if (!running.get()) break
                }
            }
        }
        return boundPort
    }

    fun stop() {
        running.set(false)
        bootstrapSecretToken = null
        _activePairingPin.value = ""
        activeQrPayloadSnapshot = null
        DirectSwitchKeepAliveService.stop(context)
        try {
            serverSocket?.close()
        } catch (t: Throwable) {
            DirectSwitchLog.warn("Chiusura server fallita", t)
        } finally {
            serverSocket = null
        }
    }

    private fun isValidBootstrapRequest(rawPathAndQuery: String): Boolean {
        val expected = bootstrapSecretToken ?: return false
        val provided = runCatching {
            Uri.parse("http://localhost$rawPathAndQuery").getQueryParameter("token")
        }.getOrNull() ?: return false
        return DirectSwitchCrypto.constantTimeEquals(expected, provided)
    }

    private fun handleClientSocket(socket: Socket) {
        socket.use { sock ->
            val remoteIp = (sock.inetAddress as? Inet4Address)?.hostAddress
            if (remoteIp != null && !LocalNetworkAddresses.isLocalNetworkIpv4(remoteIp)) {
                return
            }
            sock.soTimeout = 60_000
            val input = BufferedInputStream(sock.getInputStream())
            val output = sock.getOutputStream()

            val requestLine = readAsciiLine(input) ?: return
            val parts = requestLine.split(" ")
            if (parts.size < 2) return
            val method = parts[0].uppercase()
            val fullTarget = parts[1]
            val pathOnly = fullTarget.substringBefore('?')

            val headers = HashMap<String, String>()
            while (true) {
                val line = readAsciiLine(input) ?: break
                if (line.isEmpty()) break
                val colon = line.indexOf(':')
                if (colon > 0) {
                    val k = line.substring(0, colon).trim().lowercase()
                    val v = line.substring(colon + 1).trim()
                    headers[k] = v
                }
            }

            val contentLength = headers["content-length"]?.toLongOrNull() ?: 0L

            when {
                method == "GET" && pathOnly == "/v1/ping" -> {
                    writeJsonResponse(output, 200, """{"ok":true,"proto":"DSWITCH_V1"}""")
                }

                method == "GET" && pathOnly == "/start" -> {
                    if (!isValidBootstrapRequest(fullTarget)) {
                        writeJsonResponse(output, 403, """{"error":"Token portale mancante o non valido"}""")
                        return
                    }
                    val token = bootstrapSecretToken.orEmpty()
                    val deviceTitle = "${Build.MANUFACTURER.replaceFirstChar { it.uppercase() }} ${Build.MODEL}".trim()
                    val contactsCount = ContactsSmartMerger.readAllContacts(context).size
                    val html = buildBootstrapPortalHtml(deviceTitle, contactsCount, token)
                    writeCustomBytesResponse(output, "text/html; charset=utf-8", null, html.toByteArray(Charsets.UTF_8))
                }

                method == "GET" && pathOnly == "/download/directswitch.apk" -> {
                    if (!isValidBootstrapRequest(fullTarget)) {
                        writeJsonResponse(output, 403, """{"error":"Token download mancante o non valido"}""")
                        return
                    }
                    val apkFile = File(context.applicationInfo.sourceDir)
                    if (!apkFile.exists()) {
                        writeJsonResponse(output, 404, """{"error":"APK sorgente non disponibile"}""")
                        return
                    }
                    writeFileStreamResponse(
                        output = output,
                        contentType = "application/vnd.android.package-archive",
                        attachmentName = "DirectSwitch.apk",
                        file = apkFile
                    )
                }

                method == "GET" && pathOnly == "/download/contacts.vcf" -> {
                    if (!isValidBootstrapRequest(fullTarget)) {
                        writeJsonResponse(output, 403, """{"error":"Token rubrica mancante o non valido"}""")
                        return
                    }
                    val contacts = ContactsSmartMerger.readAllContacts(context)
                    val vcf = buildVcardBundle(contacts)
                    writeCustomBytesResponse(
                        output = output,
                        contentType = "text/vcard; charset=utf-8",
                        attachmentName = "Rubrica_DirectSwitch.vcf",
                        bodyBytes = vcf.toByteArray(Charsets.UTF_8)
                    )
                }

                method == "POST" && pathOnly == "/v1/pair-pin" -> {
                    val snapshot = activeQrPayloadSnapshot
                    val currentPin = _activePairingPin.value
                    if (snapshot == null || currentPin.length != 6 || activeSessionId.isBlank()) {
                        writeJsonResponse(output, 403, """{"error":"Accoppiamento PIN non attivo"}""")
                        return
                    }
                    if (pinPairingConsumed.get() || pinFailedAttempts.get() >= MAX_PIN_ATTEMPTS) {
                        writeJsonResponse(output, 429, """{"error":"PIN scaduto o troppi tentativi: inquadra il codice QR"}""")
                        return
                    }
                    if (contentLength <= 0L || contentLength > 64 * 1024) {
                        writeJsonResponse(output, 400, """{"error":"Richiesta PIN non valida"}""")
                        return
                    }
                    val encryptedBody = readFixedBytes(input, contentLength.toInt())
                    val pinKey = DirectSwitchCrypto.derivePinAesKey(activeSessionId, currentPin)
                    val plainJson = try {
                        DirectSwitchCrypto.openJsonEnvelope(encryptedBody, pinKey)
                    } catch (_: Throwable) {
                        pinFailedAttempts.incrementAndGet()
                        writeJsonResponse(output, 401, """{"error":"PIN errato"}""")
                        return
                    }
                    val req = runCatching {
                        DirectSwitchJson.instance.decodeFromString<PinPairingRequest>(plainJson)
                    }.getOrNull()
                    if (req == null || req.sessionId != activeSessionId || !pinPairingConsumed.compareAndSet(false, true)) {
                        pinFailedAttempts.incrementAndGet()
                        writeJsonResponse(output, 401, """{"error":"Sessione PIN non valida"}""")
                        return
                    }
                    val sealedPayload = DirectSwitchCrypto.sealJsonEnvelope(snapshot.toCompactJson(), pinKey)
                    writeRawEncryptedResponse(output, 200, sealedPayload)
                }

                method == "POST" && pathOnly == "/v1/handshake" -> {
                    if (activeSessionId.isBlank()) {
                        writeJsonResponse(output, 403, """{"error":"Sessione ricevente non attiva"}""")
                        return
                    }
                    if (contentLength <= 0L || contentLength > 1024 * 1024) {
                        writeJsonResponse(output, 400, """{"error":"Dimensione handshake non valida"}""")
                        return
                    }
                    val encryptedBody = readFixedBytes(input, contentLength.toInt())
                    val plainJson = try {
                        DirectSwitchCrypto.openJsonEnvelope(encryptedBody, sessionAesKey)
                    } catch (_: Throwable) {
                        writeJsonResponse(output, 401, """{"error":"Firma crittografica QR non valida"}""")
                        return
                    }
                    val req = DirectSwitchJson.instance.decodeFromString<HandshakeRequest>(plainJson)
                    if (req.sessionId != activeSessionId) {
                        writeJsonResponse(output, 401, """{"error":"SessionId non corrispondente"}""")
                        return
                    }

                    val receiverHasPro = CloudSaveEntitlementDetector.isLocalProUnlocked(context)
                    val receiverHasCloudSavePro = CloudSaveEntitlementDetector.hasVerifiedCloudSaveProEntitlement(context)
                    val (freeBytes, _) = StorageCapacityChecker.getFreeAndTotalBytes(context)

                    activeTier = LicensePolicyEvaluator.resolveTier(
                        senderPlatform = req.senderPlatform,
                        receiverPlatform = DevicePlatform.ANDROID,
                        senderHasPro = req.senderHasPro,
                        receiverHasPro = receiverHasPro,
                        senderHasCloudSavePro = req.senderHasCloudSavePro,
                        receiverHasCloudSavePro = receiverHasCloudSavePro
                    )
                    val enoughSpace = req.totalEstimatedBytes < (freeBytes - 200L * 1024L * 1024L)
                    transferStartMillis = System.currentTimeMillis()
                    handshakeCompleted.set(enoughSpace)

                    _progress.value = _progress.value.copy(
                        phaseLabel = "Connesso in modo sicuro a ${req.senderName}!",
                        peerDeviceName = req.senderName,
                        peerPlatform = req.senderPlatform,
                        licenseTier = activeTier
                    )

                    val resp = HandshakeResponse(
                        accepted = enoughSpace,
                        receiverName = "${Build.MANUFACTURER} ${Build.MODEL}".trim(),
                        receiverPlatform = DevicePlatform.ANDROID,
                        freeStorageBytes = freeBytes,
                        licenseTier = activeTier,
                        hasEnoughSpace = enoughSpace,
                        statusMessage = if (enoughSpace) "Pronto al trasferimento diretto" else "Spazio su disco insufficiente"
                    )
                    writeEncryptedJsonResponse(output, 200, DirectSwitchJson.instance.encodeToString(resp))
                }

                method == "POST" && pathOnly == "/v1/manifest" -> {
                    if (!handshakeCompleted.get()) {
                        writeJsonResponse(output, 401, """{"error":"Handshake non completato"}""")
                        return
                    }
                    if (contentLength <= 0L || contentLength > 64L * 1024L * 1024L) {
                        writeJsonResponse(output, 400, """{"error":"Dimensione manifesto non valida"}""")
                        return
                    }
                    val encryptedBody = readFixedBytes(input, contentLength.toInt())
                    val plainJson = try {
                        DirectSwitchCrypto.openJsonEnvelope(encryptedBody, sessionAesKey)
                    } catch (_: Throwable) {
                        writeJsonResponse(output, 401, """{"error":"Manifesto non autenticato"}""")
                        return
                    }
                    val manifest = DirectSwitchJson.instance.decodeFromString<TransferManifest>(plainJson)
                    if (manifest.sessionId != activeSessionId) {
                        writeJsonResponse(output, 401, """{"error":"SessionId manifesto non valido"}""")
                        return
                    }

                    // 1. Smart Merge Contatti (sempre abilitato), Calendari & SMS (se consentito dal tier)
                    val (mergedContacts, skippedContacts) = ContactsSmartMerger.mergeIncomingContacts(
                        context,
                        manifest.contactsPayload
                    )
                    val importedCalendars = if (LicensePolicyEvaluator.allowsFullCategories(activeTier)) {
                        CalendarMigrator.importEventsDeduplicated(context, manifest.calendarsPayload)
                    } else {
                        0
                    }
                    val importedSms = if (LicensePolicyEvaluator.allowsFullCategories(activeTier)) {
                        SmsSystemScanner.importSmsIntoSystemOrArchive(context, manifest.smsPayload)
                    } else {
                        0
                    }

                    // 2. Filtro Licenza (Intra-OS Free vs Cross-OS Pro/Preview) + Dedup Media
                    val (tierFilteredItems, gatedCount) = LicensePolicyEvaluator.filterItemsForTier(
                        manifest.items,
                        activeTier
                    )
                    val existingMediaKeys = MediaExifScannerAndImporter.buildExistingDedupKeys(context)
                    val acceptedItems = mutableListOf<ManifestItem>()
                    var skippedMediaDups = 0

                    for (item in tierFilteredItems) {
                        if (item.id in completedIds || item.dedupKey in existingMediaKeys) {
                            skippedMediaDups++
                        } else {
                            manifestMap[item.id] = item
                            acceptedItems.add(item)
                        }
                    }

                    val totalBytesToReceive = acceptedItems.sumOf { it.sizeBytes }
                    _progress.value = _progress.value.copy(
                        phaseLabel = "Ricezione file in streaming cifrato...",
                        totalItems = acceptedItems.size,
                        totalBytes = totalBytesToReceive,
                        mergedContacts = mergedContacts,
                        importedCalendars = importedCalendars,
                        importedSms = importedSms,
                        skippedDuplicates = skippedContacts + skippedMediaDups
                    )

                    val resp = ManifestResponse(
                        acceptedItemIds = acceptedItems.map { it.id },
                        skippedDuplicateCount = skippedContacts + skippedMediaDups,
                        contactsMergedCount = mergedContacts,
                        contactsSkippedDuplicates = skippedContacts,
                        calendarsImportedCount = importedCalendars,
                        smsImportedCount = importedSms,
                        gatedByCrossOsPreviewCount = gatedCount
                    )
                    writeEncryptedJsonResponse(output, 200, DirectSwitchJson.instance.encodeToString(resp))
                }

                method == "PUT" && pathOnly.startsWith("/v1/item/") -> {
                    if (!handshakeCompleted.get()) {
                        writeJsonResponse(output, 401, """{"error":"Sessione non autorizzata"}""")
                        return
                    }
                    val itemId = pathOnly.removePrefix("/v1/item/")
                    val item = manifestMap[itemId]
                    if (item == null) {
                        writeJsonResponse(output, 404, """{"error":"Item non trovato nel manifesto"}""")
                        return
                    }
                    val expectedSha256 = headers["x-ds-sha256"]?.lowercase()
                    val expectedPlainLen = headers["x-ds-plain-length"]?.toLongOrNull() ?: item.sizeBytes

                    val boundedCipherStream = BoundedInputStream(input, contentLength)
                    val safeTempId = item.id.replace(Regex("[^a-zA-Z0-9_-]"), "_")
                    val tempDecrypted = File(context.cacheDir, "rx_${safeTempId}.tmp")
                    try {
                        val (plainBytes, actualSha256) = try {
                            tempDecrypted.outputStream().use { fileOut ->
                                DirectSwitchCrypto.decryptStreamCsgcm1(boundedCipherStream, fileOut, sessionAesKey)
                            }
                        } catch (_: Throwable) {
                            writeJsonResponse(output, 401, """{"error":"Decifratura CSGCM1 fallita"}""")
                            return
                        }

                        if (plainBytes != expectedPlainLen ||
                            (!expectedSha256.isNullOrBlank() && actualSha256 != expectedSha256)
                        ) {
                            writeJsonResponse(output, 422, """{"error":"Integrità SHA-256 o lunghezza file non valida"}""")
                            return
                        }

                        val sanitizedFileName = File(item.fileName).name
                            .replace(Regex("[\\\\/:*?\"<>|]"), "_")
                            .ifBlank { "file_${safeTempId}" }
                        val safeItem = item.copy(fileName = sanitizedFileName)

                        val importedOk = if (safeItem.category == TransferCategory.PHOTOS || safeItem.category == TransferCategory.VIDEOS) {
                            tempDecrypted.inputStream().use { plainIn ->
                                MediaExifScannerAndImporter.importMediaStream(context, safeItem, plainIn)
                            }
                        } else {
                            val subFolder = if (safeItem.category == TransferCategory.WHATSAPP_VAULT) {
                                "WhatsApp_Vault"
                            } else {
                                "Documenti"
                            }
                            tempDecrypted.inputStream().use { plainIn ->
                                PublicDownloadsSaver.saveStream(
                                    context = context,
                                    subFolder = subFolder,
                                    fileName = sanitizedFileName,
                                    mimeType = safeItem.mimeType,
                                    inputStream = plainIn
                                )
                            }
                        }

                        if (!importedOk) {
                            writeJsonResponse(output, 500, """{"error":"Impossibile salvare il file su archivio pubblico"}""")
                            return
                        }

                        completedIds.add(itemId)
                        val doneFiles = completedFilesCounter.incrementAndGet()
                        val doneBytes = transferredBytesCounter.addAndGet(plainBytes)
                        val elapsedSec = ((System.currentTimeMillis() - transferStartMillis).coerceAtLeast(250L)) / 1000.0
                        val speedMbs = (doneBytes / (1024.0 * 1024.0)) / elapsedSec

                        _progress.value = _progress.value.copy(
                            currentFileName = sanitizedFileName,
                            completedItems = doneFiles,
                            transferredBytes = doneBytes,
                            speedMegabytesPerSec = speedMbs
                        )
                        writeJsonResponse(output, 200, """{"ok":true,"bytes":$plainBytes,"sha256":"$actualSha256"}""")
                    } finally {
                        tempDecrypted.delete()
                    }
                }

                method == "POST" && pathOnly == "/v1/complete" -> {
                    if (!handshakeCompleted.get()) {
                        writeJsonResponse(output, 401, """{"error":"Sessione non autorizzata"}""")
                        return
                    }
                    if (contentLength > 0L) {
                        val encryptedBody = readFixedBytes(input, contentLength.toInt())
                        try {
                            DirectSwitchCrypto.openJsonEnvelope(encryptedBody, sessionAesKey)
                        } catch (_: Throwable) {
                            writeJsonResponse(output, 401, """{"error":"Chiusura sessione non autenticata"}""")
                            return
                        }
                    }

                    _progress.value = _progress.value.copy(
                        phaseLabel = "Trasferimento completato con successo!",
                        isCompleted = true
                    )
                    val report = TransferCompletionReport(
                        sessionId = activeSessionId,
                        licenseTier = activeTier,
                        transferredFilesCount = completedFilesCounter.get(),
                        transferredBytes = transferredBytesCounter.get(),
                        mergedContactsCount = _progress.value.mergedContacts,
                        importedCalendarsCount = _progress.value.importedCalendars,
                        importedSmsCount = _progress.value.importedSms,
                        skippedDuplicatesCount = _progress.value.skippedDuplicates,
                        elapsedMillis = (System.currentTimeMillis() - transferStartMillis).coerceAtLeast(1L)
                    )
                    writeEncryptedJsonResponse(output, 200, DirectSwitchJson.instance.encodeToString(report))
                }

                else -> {
                    writeJsonResponse(output, 404, """{"error":"Endpoint sconosciuto"}""")
                }
            }
        }
    }

    private fun readAsciiLine(input: InputStream): String? {
        val bos = ByteArrayOutputStream(128)
        var sawByte = false
        while (true) {
            val b = input.read()
            if (b < 0) return if (sawByte) bos.toString(Charsets.US_ASCII.name()) else null
            sawByte = true
            if (b == '\n'.code) break
            if (b != '\r'.code) bos.write(b)
        }
        return bos.toString(Charsets.US_ASCII.name())
    }

    private fun readFixedBytes(input: InputStream, count: Int): ByteArray {
        val buf = ByteArray(count)
        var offset = 0
        while (offset < count) {
            val r = input.read(buf, offset, count - offset)
            if (r < 0) break
            offset += r
        }
        return if (offset == count) buf else buf.copyOf(offset)
    }

    private fun writeJsonResponse(output: OutputStream, statusCode: Int, jsonBody: String) {
        val bodyBytes = jsonBody.toByteArray(Charsets.UTF_8)
        val statusText = if (statusCode == 200) "OK" else "Error"
        val header = buildString {
            append("HTTP/1.1 $statusCode $statusText\r\n")
            append("Content-Type: application/json; charset=utf-8\r\n")
            append("Content-Length: ${bodyBytes.size}\r\n")
            append("Connection: close\r\n\r\n")
        }
        output.write(header.toByteArray(Charsets.US_ASCII))
        output.write(bodyBytes)
        output.flush()
    }

    private fun writeRawEncryptedResponse(output: OutputStream, statusCode: Int, encryptedBytes: ByteArray) {
        val statusText = if (statusCode == 200) "OK" else "Error"
        val header = buildString {
            append("HTTP/1.1 $statusCode $statusText\r\n")
            append("Content-Type: application/octet-stream\r\n")
            append("Content-Length: ${encryptedBytes.size}\r\n")
            append("Connection: close\r\n\r\n")
        }
        output.write(header.toByteArray(Charsets.US_ASCII))
        output.write(encryptedBytes)
        output.flush()
    }

    private fun writeEncryptedJsonResponse(output: OutputStream, statusCode: Int, plainJson: String) {
        val encryptedBytes = DirectSwitchCrypto.sealJsonEnvelope(plainJson, sessionAesKey)
        writeRawEncryptedResponse(output, statusCode, encryptedBytes)
    }

    private fun writeCustomBytesResponse(
        output: OutputStream,
        contentType: String,
        attachmentName: String?,
        bodyBytes: ByteArray
    ) {
        val header = buildString {
            append("HTTP/1.1 200 OK\r\n")
            append("Content-Type: $contentType\r\n")
            if (!attachmentName.isNullOrBlank()) {
                append("Content-Disposition: attachment; filename=\"$attachmentName\"\r\n")
            }
            append("Content-Length: ${bodyBytes.size}\r\n")
            append("Connection: close\r\n\r\n")
        }
        output.write(header.toByteArray(Charsets.US_ASCII))
        output.write(bodyBytes)
        output.flush()
    }

    private fun writeFileStreamResponse(
        output: OutputStream,
        contentType: String,
        attachmentName: String,
        file: File
    ) {
        val header = buildString {
            append("HTTP/1.1 200 OK\r\n")
            append("Content-Type: $contentType\r\n")
            append("Content-Disposition: attachment; filename=\"$attachmentName\"\r\n")
            append("Content-Length: ${file.length()}\r\n")
            append("Connection: close\r\n\r\n")
        }
        output.write(header.toByteArray(Charsets.US_ASCII))
        file.inputStream().use { fileIn ->
            fileIn.copyTo(output, bufferSize = 256 * 1024)
        }
        output.flush()
    }

    private fun buildVcardBundle(contacts: List<ContactTransferRecord>): String {
        val sb = StringBuilder()
        for (c in contacts) {
            sb.append("BEGIN:VCARD\r\nVERSION:3.0\r\n")
            val safeName = c.displayName.replace("\r", " ").replace("\n", " ")
            sb.append("FN:").append(safeName).append("\r\n")
            sb.append("N:").append(safeName).append(";;;;\r\n")
            for (phone in c.phones) {
                sb.append("TEL;TYPE=CELL:").append(phone.trim()).append("\r\n")
            }
            for (mail in c.emails) {
                sb.append("EMAIL;TYPE=INTERNET:").append(mail.trim()).append("\r\n")
            }
            sb.append("END:VCARD\r\n")
        }
        return sb.toString()
    }

    private fun buildBootstrapPortalHtml(deviceName: String, contactsCount: Int, token: String): String {
        val safeTitle = deviceName
            .replace("&", "&amp;")
            .replace("<", "&lt;")
            .replace(">", "&gt;")
            .replace("\"", "&quot;")
        return """
            <!DOCTYPE html>
            <html lang="it">
            <head>
              <meta charset="utf-8">
              <meta name="viewport" content="width=device-width,initial-scale=1">
              <title>DirectSwitch — Configurazione Guidata Nuovo Telefono</title>
              <style>
                body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; background: #e8f0f5; color: #0f172a; margin: 0; padding: 20px; }
                .card { background: #ffffff; border-radius: 18px; padding: 20px; margin-bottom: 16px; box-shadow: 0 4px 14px rgba(0,0,0,0.06); }
                h1 { font-size: 22px; margin: 0 0 6px 0; color: #008f7a; }
                p { font-size: 14px; color: #475569; line-height: 1.45; margin: 6px 0 14px 0; }
                .btn { display: block; text-align: center; text-decoration: none; font-weight: 600; font-size: 16px; padding: 14px 16px; border-radius: 14px; margin-top: 10px; }
                .btn-teal { background: #008f7a; color: #ffffff; }
                .btn-blue { background: #007aff; color: #ffffff; }
                .badge { display: inline-block; background: #e6f6f3; color: #008f7a; font-size: 12px; font-weight: 700; padding: 4px 10px; border-radius: 12px; margin-bottom: 8px; }
              </style>
            </head>
            <body>
              <div class="card">
                <span class="badge">CONNESSO IN WI-FI LOCALE PROTETTA</span>
                <h1>DirectSwitch da $safeTitle</h1>
                <p>Questo telefono nuovo ha rilevato correttamente <b>$safeTitle</b> senza bisogno di cavi o cloud.</p>
              </div>
              <div class="card">
                <h1>1. Sei su un nuovo Android?</h1>
                <p>Scarica l'app DirectSwitch direttamente dal vecchio telefono via Wi-Fi locale (zero consumo internet). Appena aperta, i due telefoni si collegheranno in automatico!</p>
                <a class="btn btn-teal" href="/download/directswitch.apk?token=$token">Scarica e Avvia DirectSwitch (.APK)</a>
              </div>
              <div class="card">
                <h1>2. Sei su un nuovo iPhone?</h1>
                <p>Importa subito con 1 tocco tutti i <b>$contactsCount contatti</b> nell'app Contatti nativa di iPhone e avvia l'app guidata iOS per Foto, Video 4K e Album.</p>
                <a class="btn btn-blue" href="/download/contacts.vcf?token=$token">Importa Subito Rubrica ($contactsCount Contatti)</a>
              </div>
            </body>
            </html>
        """.trimIndent()
    }
}

private class BoundedInputStream(
    private val delegate: InputStream,
    private var remaining: Long
) : InputStream() {
    override fun read(): Int {
        if (remaining <= 0L) return -1
        val b = delegate.read()
        if (b >= 0) remaining--
        return b
    }

    override fun read(b: ByteArray, off: Int, len: Int): Int {
        if (remaining <= 0L) return -1
        val maxRead = minOf(len.toLong(), remaining).toInt()
        val r = delegate.read(b, off, maxRead)
        if (r > 0) remaining -= r
        return r
    }
}

/**
 * Client HTTP ad alta velocità eseguito sul Vecchio Telefono (Sorgente):
 * - Aggancia in automatico l'Hotspot 5GHz Offline del ricevente (`WifiNetworkSpecifier` su Android 10+)
 *   e instrada i socket direttamente sull'interfaccia `TRANSPORT_WIFI` anche quando la rete non ha internet
 *   (evitando che Android devii il traffico sulla rete dati 4G/5G).
 * - Mantiene attivo `DirectSwitchKeepAliveService` (`WifiLock` + `WakeLock`) per trasferimenti multi-GB.
 */
class DirectSwitchTransferClient(private val context: Context) {

    private data class BoundHttpChannel(
        val reachableIp: String,
        val client: OkHttpClient,
        val cleanup: () -> Unit = {}
    )

    private val baseHttpClient = OkHttpClient.Builder()
        .connectTimeout(4, TimeUnit.SECONDS)
        .readTimeout(120, TimeUnit.SECONDS)
        .writeTimeout(120, TimeUnit.SECONDS)
        .build()

    private val _progress = MutableStateFlow(LiveTransferProgress())
    val progress: StateFlow<LiveTransferProgress> = _progress

    /**
     * Scambia in modo autenticato il PIN a 6 cifre letto sullo schermo del ricevente con il
     * [QrPairingPayload] completo (contenente la chiave di sessione a 256 bit).
     */
    suspend fun pairWithBeaconUsingPin(
        beacon: DiscoveryBeaconPayload,
        pin: String
    ): Result<QrPairingPayload> = withContext(Dispatchers.IO) {
        try {
            val cleanPin = pin.filter { it.isDigit() }
            require(cleanPin.length == 6) { "Inserisci il codice PIN a 6 cifre mostrato sul nuovo telefono." }
            val channel = resolveChannel(beacon.ips, beacon.port, null, null)
                ?: return@withContext Result.failure(
                    IllegalStateException("Impossibile raggiungere ${beacon.receiverName} sulla rete Wi-Fi locale.")
                )
            try {
                val pinAesKey = DirectSwitchCrypto.derivePinAesKey(beacon.sessionId, cleanPin)
                val reqJson = DirectSwitchJson.instance.encodeToString(
                    PinPairingRequest(
                        sessionId = beacon.sessionId,
                        senderName = "${Build.MANUFACTURER} ${Build.MODEL}".trim()
                    )
                )
                val respJson = postEncryptedJson(
                    client = channel.client,
                    url = "http://${channel.reachableIp}:${beacon.port}/v1/pair-pin",
                    plainJson = reqJson,
                    aesKey = pinAesKey
                )
                val payload = QrPairingPayload.fromJson(respJson)
                val mergedIps = (listOf(channel.reachableIp) + payload.ips).distinct()
                Result.success(payload.copy(ips = mergedIps))
            } finally {
                channel.cleanup()
            }
        } catch (t: Throwable) {
            Result.failure(t)
        }
    }

    suspend fun executeTransfer(
        qrPayload: QrPairingPayload,
        includeContacts: Boolean,
        includePhotos: Boolean,
        includeVideos: Boolean,
        includeCalendars: Boolean,
        includeSms: Boolean = true,
        includeDocuments: Boolean = true,
        includeWhatsAppVault: Boolean = true
    ): Result<TransferCompletionReport> = withContext(Dispatchers.IO) {
        var boundChannel: BoundHttpChannel? = null
        DirectSwitchKeepAliveService.start(context, "Invio dati verso ${qrPayload.receiverName}...")
        try {
            _progress.value = LiveTransferProgress(phaseLabel = "Ricerca canale diretto più veloce verso ${qrPayload.receiverName}...")

            val channel = resolveChannel(
                candidateIps = qrPayload.ips,
                port = qrPayload.port,
                wifiSsid = qrPayload.wifiSsid,
                wifiPass = qrPayload.wifiPass
            ) ?: return@withContext Result.failure(
                IllegalStateException("Impossibile raggiungere ${qrPayload.receiverName}. Verifica che entrambi i telefoni siano sulla stessa Wi-Fi o accetta la connessione all'Hotspot DirectSwitch.")
            )
            boundChannel = channel
            val activeClient = channel.client

            val baseUrl = "http://${channel.reachableIp}:${qrPayload.port}"
            val sessionAesKey = DirectSwitchCrypto.deriveSessionAesKey(qrPayload.sessionKeyHex)

            // 1. Raccolta dati locali selezionati
            val contacts = if (includeContacts) ContactsSmartMerger.readAllContacts(context) else emptyList()
            val calendars = if (includeCalendars) CalendarMigrator.readEvents(context) else emptyList()
            val smsList = if (includeSms) SmsSystemScanner.readAllSms(context) else emptyList()
            val mediaEntries = MediaExifScannerAndImporter.scanMediaEntries(
                context = context,
                includePhotos = includePhotos,
                includeVideos = includeVideos
            ) + DocumentsAndWhatsAppScanner.scanDocumentAndWhatsAppEntries(
                context = context,
                includeDocuments = includeDocuments,
                includeWhatsAppVault = includeWhatsAppVault
            )
            val estimatedBytes = mediaEntries.sumOf { it.manifestItem.sizeBytes }

            // 2. Handshake Cifrato + Verifica Single-Side Pro License + Spazio Disco
            val handshakeReq = HandshakeRequest(
                sessionId = qrPayload.sessionId,
                senderName = "${Build.MANUFACTURER} ${Build.MODEL}".trim(),
                senderPlatform = DevicePlatform.ANDROID,
                senderHasPro = CloudSaveEntitlementDetector.isLocalProUnlocked(context),
                senderHasCloudSavePro = CloudSaveEntitlementDetector.hasVerifiedCloudSaveProEntitlement(context),
                totalEstimatedBytes = estimatedBytes
            )
            val handshakeJson = postEncryptedJson(
                client = activeClient,
                url = "$baseUrl/v1/handshake",
                plainJson = DirectSwitchJson.instance.encodeToString(handshakeReq),
                aesKey = sessionAesKey
            )
            val handshakeResp = DirectSwitchJson.instance.decodeFromString<HandshakeResponse>(handshakeJson)

            if (!handshakeResp.hasEnoughSpace) {
                val neededMb = (estimatedBytes / (1024 * 1024)).coerceAtLeast(1L)
                val msg = "Spazio insufficiente su ${handshakeResp.receiverName}: servono circa $neededMb MB liberi."
                _progress.value = _progress.value.copy(errorMessage = msg)
                return@withContext Result.failure(IllegalStateException(msg))
            }

            _progress.value = _progress.value.copy(
                phaseLabel = "Sincronizzazione Smart Merge (Zero Duplicati)...",
                peerDeviceName = handshakeResp.receiverName,
                peerPlatform = handshakeResp.receiverPlatform,
                licenseTier = handshakeResp.licenseTier
            )

            // 3. Invio Manifesto Cifrato & Merge immediato Contatti / Calendari / SMS
            val manifest = TransferManifest(
                sessionId = qrPayload.sessionId,
                senderPlatform = DevicePlatform.ANDROID,
                items = mediaEntries.map { it.manifestItem },
                contactsPayload = contacts,
                calendarsPayload = calendars,
                smsPayload = smsList
            )
            val manifestRespJson = postEncryptedJson(
                client = activeClient,
                url = "$baseUrl/v1/manifest",
                plainJson = DirectSwitchJson.instance.encodeToString(manifest),
                aesKey = sessionAesKey
            )
            val manifestResp = DirectSwitchJson.instance.decodeFromString<ManifestResponse>(manifestRespJson)

            val acceptedSet = manifestResp.acceptedItemIds.toHashSet()
            val entriesToUpload = mediaEntries.filter { it.manifestItem.id in acceptedSet }
            val totalBytes = entriesToUpload.sumOf { it.manifestItem.sizeBytes }
            val startTime = System.currentTimeMillis()
            var uploadedBytes = 0L

            _progress.value = _progress.value.copy(
                phaseLabel = "Trasferimento diretto cifrato in corso...",
                totalItems = entriesToUpload.size,
                totalBytes = totalBytes,
                mergedContacts = manifestResp.contactsMergedCount,
                importedCalendars = manifestResp.calendarsImportedCount,
                importedSms = manifestResp.smsImportedCount,
                skippedDuplicates = manifestResp.skippedDuplicateCount
            )

            // 4. Upload Streaming CSGCM1 elemento per elemento con verifica SHA-256
            for ((index, entry) in entriesToUpload.withIndex()) {
                val safeTempId = entry.manifestItem.id.replace(Regex("[^a-zA-Z0-9_-]"), "_")
                val tempEncrypted = File(context.cacheDir, "tx_${safeTempId}.csgcm1")
                try {
                    val (plainLen, sha256Hex) = context.contentResolver.openInputStream(entry.contentUri)?.use { rawIn ->
                        tempEncrypted.outputStream().use { encOut ->
                            DirectSwitchCrypto.encryptStreamCsgcm1(rawIn, encOut, sessionAesKey)
                        }
                    } ?: continue

                    val body = object : RequestBody() {
                        override fun contentType() = "application/octet-stream".toMediaType()
                        override fun contentLength(): Long = tempEncrypted.length()
                        override fun writeTo(sink: BufferedSink) {
                            tempEncrypted.inputStream().use { fileIn ->
                                val buf = ByteArray(256 * 1024)
                                while (true) {
                                    val r = fileIn.read(buf)
                                    if (r <= 0) break
                                    sink.write(buf, 0, r)
                                }
                            }
                        }
                    }

                    val putReq = Request.Builder()
                        .url("$baseUrl/v1/item/${entry.manifestItem.id}")
                        .header("X-DS-Plain-Length", plainLen.toString())
                        .header("X-DS-Sha256", sha256Hex)
                        .put(body)
                        .build()

                    activeClient.newCall(putReq).execute().use { resp ->
                        if (!resp.isSuccessful) {
                            throw IllegalStateException("Errore upload ${entry.manifestItem.fileName}: HTTP ${resp.code}")
                        }
                    }

                    uploadedBytes += plainLen
                    val elapsedSec = ((System.currentTimeMillis() - startTime).coerceAtLeast(250L)) / 1000.0
                    val speedMbs = (uploadedBytes / (1024.0 * 1024.0)) / elapsedSec

                    _progress.value = _progress.value.copy(
                        currentFileName = entry.manifestItem.fileName,
                        completedItems = index + 1,
                        transferredBytes = uploadedBytes,
                        speedMegabytesPerSec = speedMbs
                    )
                } finally {
                    tempEncrypted.delete()
                }
            }

            // 5. Chiusura sessione cifrata e Report certificato
            val completeJson = postEncryptedJson(
                client = activeClient,
                url = "$baseUrl/v1/complete",
                plainJson = """{"sessionId":"${qrPayload.sessionId}"}""",
                aesKey = sessionAesKey
            )
            val report = DirectSwitchJson.instance.decodeFromString<TransferCompletionReport>(completeJson)

            _progress.value = _progress.value.copy(
                phaseLabel = "Trasferimento completato!",
                isCompleted = true
            )
            Result.success(report)
        } catch (t: Throwable) {
            _progress.value = _progress.value.copy(
                errorMessage = t.localizedMessage ?: "Errore durante il trasferimento"
            )
            Result.failure(t)
        } finally {
            boundChannel?.cleanup?.invoke()
            DirectSwitchKeepAliveService.stop(context)
        }
    }

    private fun clientBoundTo(network: Network?): OkHttpClient =
        if (network != null) {
            baseHttpClient.newBuilder().socketFactory(network.socketFactory).build()
        } else {
            baseHttpClient
        }

    private fun findActiveWifiNetworks(): List<Network> {
        val cm = context.applicationContext.getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager
            ?: return emptyList()
        return runCatching {
            cm.allNetworks.filter { net ->
                cm.getNetworkCapabilities(net)?.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) == true
            }
        }.getOrDefault(emptyList())
    }

    private suspend fun resolveChannel(
        candidateIps: List<String>,
        port: Int,
        wifiSsid: String?,
        wifiPass: String?
    ): BoundHttpChannel? {
        // 1. Prova prima su tutte le reti TRANSPORT_WIFI attive (anche prive di internet)
        for (wifiNet in findActiveWifiNetworks()) {
            val wifiClient = clientBoundTo(wifiNet)
            val hit = findReachableIp(wifiClient, candidateIps, port)
            if (hit != null) {
                return BoundHttpChannel(reachableIp = hit, client = wifiClient)
            }
        }

        // 2. Fallback sul routing predefinito di sistema (es. tethering inverso / Ethernet USB)
        findReachableIp(baseHttpClient, candidateIps, port)?.let { hit ->
            return BoundHttpChannel(reachableIp = hit, client = baseHttpClient)
        }

        // 3. Se il QR contiene le credenziali dell'Hotspot 5GHz Offline, aggancialo in automatico (Android 10+)
        if (!wifiSsid.isNullOrBlank() && !wifiPass.isNullOrBlank() && Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            _progress.value = _progress.value.copy(
                phaseLabel = "Connessione automatica all'Hotspot 5GHz $wifiSsid..."
            )
            val hotspotPair = requestPeerHotspotNetworkApi29(wifiSsid, wifiPass)
            if (hotspotPair != null) {
                val (hotspotNet, releaseFn) = hotspotPair
                val hotspotClient = clientBoundTo(hotspotNet)
                val hit = findReachableIp(hotspotClient, candidateIps, port)
                if (hit != null) {
                    return BoundHttpChannel(reachableIp = hit, client = hotspotClient, cleanup = releaseFn)
                }
                releaseFn()
            }
        }
        return null
    }

    private suspend fun requestPeerHotspotNetworkApi29(
        ssid: String,
        passphrase: String
    ): Pair<Network, () -> Unit>? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return null
        val cm = context.applicationContext.getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager
            ?: return null
        return withTimeoutOrNull(25_000L) {
            suspendCancellableCoroutine { cont ->
                val resumed = AtomicBoolean(false)
                val specifier = WifiNetworkSpecifier.Builder()
                    .setSsid(ssid)
                    .setWpa2Passphrase(passphrase)
                    .build()
                val request = NetworkRequest.Builder()
                    .addTransportType(NetworkCapabilities.TRANSPORT_WIFI)
                    .removeCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
                    .setNetworkSpecifier(specifier)
                    .build()

                val callback = object : ConnectivityManager.NetworkCallback() {
                    override fun onAvailable(network: Network) {
                        if (resumed.compareAndSet(false, true)) {
                            val cleanup: () -> Unit = {
                                runCatching { cm.unregisterNetworkCallback(this) }
                            }
                            cont.resume(network to cleanup)
                        }
                    }

                    override fun onUnavailable() {
                        if (resumed.compareAndSet(false, true)) {
                            runCatching { cm.unregisterNetworkCallback(this) }
                            cont.resume(null)
                        }
                    }
                }

                cont.invokeOnCancellation {
                    runCatching { cm.unregisterNetworkCallback(callback) }
                }

                try {
                    cm.requestNetwork(request, callback)
                } catch (t: Throwable) {
                    DirectSwitchLog.warn("Richiesta Hotspot WifiNetworkSpecifier fallita", t)
                    if (resumed.compareAndSet(false, true)) {
                        cont.resume(null)
                    }
                }
            }
        }
    }

    private fun findReachableIp(client: OkHttpClient, candidateIps: List<String>, port: Int): String? {
        for (ip in candidateIps) {
            if (!LocalNetworkAddresses.isLocalNetworkIpv4(ip)) {
                DirectSwitchLog.warn("Indirizzo non locale scartato dal QR")
                continue
            }
            try {
                val req = Request.Builder()
                    .url("http://$ip:$port/v1/ping")
                    .get()
                    .build()
                client.newCall(req).execute().use { resp ->
                    if (resp.isSuccessful) return ip
                }
            } catch (t: Throwable) {
                DirectSwitchLog.warn("Ping IP candidato fallito", t)
            }
        }
        return null
    }

    private fun postEncryptedJson(
        client: OkHttpClient,
        url: String,
        plainJson: String,
        aesKey: ByteArray
    ): String {
        val sealed = DirectSwitchCrypto.sealJsonEnvelope(plainJson, aesKey)
        val body = sealed.toRequestBody("application/octet-stream".toMediaType())
        val req = Request.Builder().url(url).post(body).build()
        client.newCall(req).execute().use { resp ->
            if (!resp.isSuccessful) {
                val hint = if (resp.code == 401) "PIN o chiave QR non validi"
                else if (resp.code == 429) "Troppi tentativi PIN errati: inquadra il QR Code"
                else "HTTP ${resp.code}"
                throw IllegalStateException("Richiesta rifiutata ($hint)")
            }
            val respBytes = resp.body?.bytes() ?: ByteArray(0)
            return DirectSwitchCrypto.openJsonEnvelope(respBytes, aesKey)
        }
    }
}
