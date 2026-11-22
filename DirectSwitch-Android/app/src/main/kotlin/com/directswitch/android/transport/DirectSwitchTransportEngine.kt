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
import android.os.Environment
import android.os.Handler
import android.os.Looper
import com.directswitch.android.DirectSwitchLog
import com.directswitch.android.migrators.AndroidAudioCodecHealer
import com.directswitch.android.migrators.AndroidBatteryTriageMonitor
import com.directswitch.android.migrators.AndroidLiveMotionBridge
import com.directswitch.android.migrators.AndroidMediaFilterHelper
import com.directswitch.android.migrators.AndroidRemindersMigrator
import com.directswitch.android.migrators.AndroidTimelineExifInjector
import com.directswitch.android.migrators.AudioAndMemoMigrator
import com.directswitch.android.migrators.CalendarMigrator
import com.directswitch.android.migrators.CallLogMigrator
import com.directswitch.android.migrators.ContactsSmartMerger
import com.directswitch.android.migrators.DocumentsAndWhatsAppScanner
import com.directswitch.android.migrators.InstalledAppsScanner
import com.directswitch.android.migrators.LocalMediaEntry
import com.directswitch.android.migrators.MediaExifScannerAndImporter
import com.directswitch.android.migrators.PublicDownloadsSaver
import com.directswitch.android.migrators.SmsSystemScanner
import com.directswitch.android.migrators.StorageCapacityChecker
import com.directswitch.android.migrators.WhatsAppVaultReader
import com.directswitch.android.protocol.ActiveTransferScope
import com.directswitch.android.protocol.AndroidHeicCompatibilityConverter
import com.directswitch.android.protocol.AndroidThermalMonitor
import com.directswitch.android.protocol.BatteryTriagePlanner
import com.directswitch.android.protocol.CompletedMigrationRecord
import com.directswitch.android.protocol.CompletedMigrationStore
import com.directswitch.android.protocol.CrossOsCodecCompatibilityHelper
import com.directswitch.android.protocol.DevicePlatform
import com.directswitch.android.protocol.DirectSwitchCrypto
import com.directswitch.android.protocol.DirectSwitchJson
import com.directswitch.android.protocol.DiscoveryBeaconPayload
import com.directswitch.android.protocol.HandshakeRequest
import com.directswitch.android.protocol.HandshakeResponse
import com.directswitch.android.protocol.InstalledAppRecord
import com.directswitch.android.protocol.LicensePolicyEvaluator
import com.directswitch.android.protocol.ManifestItem
import com.directswitch.android.protocol.ManifestResponse
import com.directswitch.android.protocol.MediaFallbackNaming
import com.directswitch.android.protocol.MediaTimelineHealer
import com.directswitch.android.protocol.MediaTransferFilterOptions
import com.directswitch.android.protocol.NetworkDiagnosticVerdict
import com.directswitch.android.protocol.NetworkIsolationDiagnostics
import com.directswitch.android.protocol.PairAckRequest
import com.directswitch.android.protocol.PinPairingRequest
import com.directswitch.android.protocol.QrPairingPayload
import com.directswitch.android.protocol.ReconcileManifestRequest
import com.directswitch.android.protocol.ReconcileManifestResponse
import com.directswitch.android.protocol.ReconciliationDiffCore
import com.directswitch.android.protocol.SecureTempFileShredder
import com.directswitch.android.protocol.SessionLicenseTier
import com.directswitch.android.protocol.SkippedTransferItemRecord
import com.directswitch.android.protocol.SlidingTransferSpeedMeter
import com.directswitch.android.protocol.SmartCleanMediaResult
import com.directswitch.android.protocol.SmartCleanOptions
import com.directswitch.android.protocol.SmartCleanPreTransferEngine
import com.directswitch.android.protocol.SpaceReliefOffer
import com.directswitch.android.protocol.SpaceReliefPlanner
import com.directswitch.android.protocol.TenPercentSteppedEtaTracker
import com.directswitch.android.protocol.ThermalGuardCore
import com.directswitch.android.protocol.ThermalGuardState
import com.directswitch.android.protocol.TransferCategory
import com.directswitch.android.protocol.TransferCheckpointRecord
import com.directswitch.android.protocol.TransferCheckpointStore
import com.directswitch.android.protocol.TransferCompletionReport
import com.directswitch.android.protocol.TransferConnectionMedium
import com.directswitch.android.protocol.TransferDisplayFormatting
import com.directswitch.android.protocol.TransferManifest
import com.directswitch.android.protocol.TransferPreparationItem
import com.directswitch.android.protocol.TransferPrepareRequest
import com.directswitch.android.protocol.TransferProgressAccounting
import com.directswitch.android.protocol.TransferSessionStage
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.Semaphore
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull
import kotlinx.serialization.encodeToString
import kotlin.coroutines.resume
import okhttp3.Dispatcher
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
import java.util.concurrent.atomic.AtomicReference

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
    val etaLabel: String? = null,
    val mergedContacts: Int = 0,
    val contactsAlreadyPresent: Int = 0,
    val importedCalendars: Int = 0,
    val calendarsAlreadyPresent: Int = 0,
    val importedReminders: Int = 0,
    val remindersAlreadyPresent: Int = 0,
    val importedSms: Int = 0,
    val importedCallLogs: Int = 0,
    val skippedDuplicates: Int = 0,
    val failedItemsCount: Int = 0,
    val skippedItems: List<SkippedTransferItemRecord> = emptyList(),
    val spaceReliefOffer: SpaceReliefOffer? = null,
    val connectionMedium: TransferConnectionMedium = TransferConnectionMedium.LOCAL_WIFI,
    val receivedInstalledApps: List<InstalledAppRecord> = emptyList(),
    val receivedDocumentFolders: Map<String, Int> = emptyMap(),
    val activeTransferScope: ActiveTransferScope = ActiveTransferScope(),
    val sessionStage: TransferSessionStage = TransferSessionStage.WAITING_PAIRING,
    val preparationItems: List<TransferPreparationItem> = emptyList(),
    val arePreparationItemsReady: Boolean = false,
    val isCompleted: Boolean = false,
    val pendingNativeWhatsAppMigration: Boolean = false,
    val gatedPreviewCount: Int = 0,
    val healedTimelineCount: Int = 0,
    val healedCodecCount: Int = 0,
    val convertedLiveMotionCount: Int = 0,
    val batteryTriageActive: Boolean = false,
    val deltaSyncModeActive: Boolean = false,
    val heicConvertedCount: Int = 0,
    val thermalGuardState: ThermalGuardState = ThermalGuardState.NORMAL,
    val thermalBanner: String? = null,
    val smartCleanMergedContactsCount: Int = 0,
    val smartCleanSkippedDuplicatesCount: Int = 0,
    val smartCleanSkippedScreenshotsCount: Int = 0,
    val reconciliationMissingIds: List<String> = emptyList(),
    val reconciliationVerifiedCount: Int = 0,
    val errorMessage: String? = null
)

object LocalNetworkAddresses {
    private val wiredInterfacePrefixes = listOf("rndis", "usb", "eth", "ncm", "enx")
    private val p2pInterfacePrefixes = listOf("ap", "p2p", "swlan", "softap")

    fun isWiredInterfaceName(name: String): Boolean {
        val lower = name.lowercase()
        return wiredInterfacePrefixes.any { lower.startsWith(it) }
    }

    fun isP2pInterfaceName(name: String): Boolean {
        val lower = name.lowercase()
        return p2pInterfacePrefixes.any { lower.startsWith(it) }
    }

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

    /** Restituisce gli IPv4 locali dando priorità assoluta a Cavo USB-C / Ethernet / Tethering, poi Hotspot P2P, poi Wi-Fi. */
    fun listPrivateIpv4Addresses(): List<String> {
        val ranked = mutableListOf<Pair<Int, String>>()
        try {
            val interfaces = Collections.list(NetworkInterface.getNetworkInterfaces())
            for (nif in interfaces) {
                if (!nif.isUp || nif.isLoopback) continue
                val name = nif.name.orEmpty()
                val wired = isWiredInterfaceName(name)
                val p2p = isP2pInterfaceName(name)
                val priority = when {
                    wired -> 0
                    p2p -> 1
                    name.lowercase().startsWith("wlan") -> 2
                    else -> 3
                }
                for (addr in Collections.list(nif.inetAddresses)) {
                    if (addr is Inet4Address && !addr.isLoopbackAddress) {
                        val ip = addr.hostAddress ?: continue
                        val allowLinkLocal = wired
                        if (isLocalNetworkIpv4(ip) && (allowLinkLocal || !ip.startsWith("169.254."))) {
                            ranked.add(priority to ip)
                        }
                    }
                }
            }
        } catch (t: Throwable) {
            DirectSwitchLog.warn("Lettura indirizzi di rete fallita", t)
        }
        return ranked.sortedBy { it.first }.map { it.second }.distinct()
    }

    fun detectConnectionMedium(targetIp: String? = null, isHotspotOrP2p: Boolean = false): TransferConnectionMedium {
        val targetPrefix = targetIp?.split(".")?.take(3)?.joinToString(".")
        runCatching {
            val interfaces = Collections.list(NetworkInterface.getNetworkInterfaces())
            for (nif in interfaces) {
                if (!nif.isUp || nif.isLoopback) continue
                val name = nif.name.orEmpty()
                for (addr in Collections.list(nif.inetAddresses)) {
                    if (addr is Inet4Address && !addr.isLoopbackAddress) {
                        val ip = addr.hostAddress ?: continue
                        val matches = targetIp == null || ip == targetIp ||
                            (targetPrefix != null && ip.startsWith("$targetPrefix."))
                        if (matches) {
                            if (isWiredInterfaceName(name)) return TransferConnectionMedium.USB_CABLE
                            if (isP2pInterfaceName(name)) return TransferConnectionMedium.PEER_TO_PEER_WIFI
                        }
                    }
                }
            }
        }
        return if (isHotspotOrP2p) TransferConnectionMedium.PEER_TO_PEER_WIFI else TransferConnectionMedium.LOCAL_WIFI
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
 * Server TCP/HTTP1.1 locale ad alte prestazioni (telefono ↔ telefono):
 * - Tutti gli endpoint di trasferimento (`/v1/handshake`, `/v1/manifest`, `/v1/item/{id}`, `/v1/reconcile-manifest`, `/v1/complete`)
 *   sono cifrati e autenticati tramite `CSGCM1` AES-256-GCM.
 * - L'accoppiamento da Auto-Discovery (`/v1/pair-pin`) richiede il PIN a 6 cifre mostrato sul ricevente,
 *   è monouso e si blocca dopo 3 tentativi errati.
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
    private var activeTier: SessionLicenseTier = SessionLicenseTier.INTRA_OS_FREE
    private val handshakeCompleted = AtomicBoolean(false)
    private val activeRunIsResume = AtomicBoolean(false)
    private val requestedWhatsAppMigration = AtomicBoolean(false)
    private val pinPairingConsumed = AtomicBoolean(false)
    private val pinFailedAttempts = AtomicInteger(0)
    private val manifestMap = ConcurrentHashMap<String, ManifestItem>()
    private val pendingLiveVideoTempFiles = ConcurrentHashMap<String, File>()
    private val completedIds = ConcurrentHashMap.newKeySet<String>()
    private val committedItemHashes = ConcurrentHashMap<String, String>()
    private val skippedIds = ConcurrentHashMap.newKeySet<String>()
    private val liveVideoAccountedIds = ConcurrentHashMap.newKeySet<String>()
    private val transferredBytesCounter = AtomicLong(0L)
    private val completedFilesCounter = AtomicInteger(0)
    private val healedTimelineCounter = AtomicInteger(0)
    private val convertedLiveMotionCounter = AtomicInteger(0)
    private val docFolderCounts = ConcurrentHashMap<String, Int>()
    private val rxProgressLock = Any()
    private var rxProgressAccounting: TransferProgressAccounting? = null
    private var rxSpeedMeter = SlidingTransferSpeedMeter()
    private val rxEtaTracker = TenPercentSteppedEtaTracker()
    private var transferStartMillis = 0L

    fun startReceiverSession(
        wifiSsid: String? = null,
        wifiPass: String? = null
    ): QrPairingPayload {
        stop()
        val sessionId = "ds_${DirectSwitchCrypto.toHexLower(DirectSwitchCrypto.randomBytes(8))}"
        val sessionKeyHex = DirectSwitchCrypto.generateSessionKeyHex()
        val pin = DirectSwitchCrypto.generatePairingPin()
        activeSessionId = sessionId
        _activePairingPin.value = pin
        pinPairingConsumed.set(false)
        pinFailedAttempts.set(0)
        sessionAesKey = DirectSwitchCrypto.deriveSessionAesKey(sessionKeyHex)
        handshakeCompleted.set(false)
        activeRunIsResume.set(false)
        requestedWhatsAppMigration.set(false)
        manifestMap.clear()
        cleanupPendingLiveVideoFiles()
        completedIds.clear()
        skippedIds.clear()
        liveVideoAccountedIds.clear()
        docFolderCounts.clear()
        transferredBytesCounter.set(0L)
        completedFilesCounter.set(0)
        healedTimelineCounter.set(0)
        convertedLiveMotionCounter.set(0)
        synchronized(rxProgressLock) {
            rxProgressAccounting = null
            rxSpeedMeter = SlidingTransferSpeedMeter()
            rxEtaTracker.reset()
        }

        val boundPort = bindAndAcceptLoop()
        DirectSwitchKeepAliveService.start(context, "Ricezione dati attiva sulla rete locale")
        val candidateIps = LocalNetworkAddresses.listPrivateIpv4Addresses().ifEmpty { listOf("192.168.43.1") }
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
            receiverHasPro = true
        )
        activeQrPayloadSnapshot = payload
        return payload
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

    fun resetProgress() {
        requestedWhatsAppMigration.set(false)
        _progress.value = LiveTransferProgress()
    }

    private fun cleanupPendingLiveVideoFiles() {
        for ((_, f) in pendingLiveVideoTempFiles) {
            runCatching { f.delete() }
        }
        pendingLiveVideoTempFiles.clear()
    }

    fun stop() {
        running.set(false)
        _activePairingPin.value = ""
        activeQrPayloadSnapshot = null
        cleanupPendingLiveVideoFiles()
        DirectSwitchKeepAliveService.stop(context)
        try {
            serverSocket?.close()
        } catch (t: Throwable) {
            DirectSwitchLog.warn("Chiusura server fallita", t)
        } finally {
            serverSocket = null
        }
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
            if (headers["expect"]?.lowercase()?.contains("100-continue") == true) {
                output.write("HTTP/1.1 100 Continue\r\n\r\n".toByteArray(Charsets.US_ASCII))
                output.flush()
            }

            when {
                method == "GET" && pathOnly == "/v1/ping" -> {
                    writeJsonResponse(output, 200, """{"ok":true,"proto":"DSWITCH_V1"}""")
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
                    _progress.value = _progress.value.copy(
                        phaseLabel = "Collegato a ${req.senderName}! Prosegui sull'altro telefono.",
                        peerDeviceName = req.senderName,
                        sessionStage = TransferSessionStage.PAIRED_WAITING_SELECTION
                    )
                    val sealedPayload = DirectSwitchCrypto.sealJsonEnvelope(snapshot.toCompactJson(), pinKey)
                    writeRawEncryptedResponse(output, 200, sealedPayload)
                }

                method == "POST" && pathOnly == "/v1/pair-ack" -> {
                    if (activeSessionId.isBlank()) {
                        writeJsonResponse(output, 403, """{"error":"Sessione ricevente non attiva"}""")
                        return
                    }
                    if (contentLength <= 0L || contentLength > 64L * 1024L) {
                        writeJsonResponse(output, 400, """{"error":"Richiesta non valida"}""")
                        return
                    }
                    val encryptedBody = readFixedBytes(input, contentLength.toInt())
                    val plainJson = try {
                        DirectSwitchCrypto.openJsonEnvelope(encryptedBody, sessionAesKey)
                    } catch (_: Throwable) {
                        writeJsonResponse(output, 401, """{"error":"Conferma non autenticata"}""")
                        return
                    }
                    val req = runCatching {
                        DirectSwitchJson.instance.decodeFromString<PairAckRequest>(plainJson)
                    }.getOrNull()
                    if (req == null || req.sessionId != activeSessionId) {
                        writeJsonResponse(output, 401, """{"error":"SessionId non valido"}""")
                        return
                    }
                    if (_progress.value.isCompleted) {
                        manifestMap.clear()
                        completedIds.clear()
                        skippedIds.clear()
                        docFolderCounts.clear()
                        transferredBytesCounter.set(0L)
                        completedFilesCounter.set(0)
                        synchronized(rxProgressLock) {
                            rxProgressAccounting = null
                            rxSpeedMeter = SlidingTransferSpeedMeter()
                            rxEtaTracker.reset()
                        }
                    }
                    _progress.value = LiveTransferProgress(
                        phaseLabel = "Collegato a ${req.senderName}! Prosegui sull'altro telefono.",
                        peerDeviceName = req.senderName,
                        peerPlatform = req.senderPlatform,
                        sessionStage = TransferSessionStage.PAIRED_WAITING_SELECTION
                    )
                    writeEncryptedJsonResponse(output, 200, """{"ok":true}""")
                }

                method == "POST" && pathOnly == "/v1/pair-reset" -> {
                    if (activeSessionId.isNotBlank() && contentLength > 0L && contentLength <= 64L * 1024L) {
                        val encryptedBody = readFixedBytes(input, contentLength.toInt())
                        runCatching { DirectSwitchCrypto.openJsonEnvelope(encryptedBody, sessionAesKey) }.onSuccess {
                            if (_progress.value.sessionStage == TransferSessionStage.PAIRED_WAITING_SELECTION) {
                                pinPairingConsumed.set(false)
                                _progress.value = LiveTransferProgress(
                                    phaseLabel = "In ascolto — Inquadra il QR o inserisci il PIN ${_activePairingPin.value}",
                                    sessionStage = TransferSessionStage.WAITING_PAIRING
                                )
                            }
                        }
                    }
                    writeEncryptedJsonResponse(output, 200, """{"ok":true}""")
                }

                method == "POST" && pathOnly == "/v1/prepare" -> {
                    if (activeSessionId.isBlank()) {
                        writeJsonResponse(output, 403, """{"error":"Sessione ricevente non attiva"}""")
                        return
                    }
                    if (contentLength <= 0L || contentLength > 128L * 1024L) {
                        writeJsonResponse(output, 400, """{"error":"Payload prepare non valido"}""")
                        return
                    }
                    val encryptedBody = readFixedBytes(input, contentLength.toInt())
                    val plainJson = try {
                        DirectSwitchCrypto.openJsonEnvelope(encryptedBody, sessionAesKey)
                    } catch (_: Throwable) {
                        writeJsonResponse(output, 401, """{"error":"Prepare non autenticato"}""")
                        return
                    }
                    val req = DirectSwitchJson.instance.decodeFromString<TransferPrepareRequest>(plainJson)
                    if (req.sessionId != activeSessionId) {
                        writeJsonResponse(output, 401, """{"error":"SessionId non valido"}""")
                        return
                    }
                    manifestMap.clear()
                    completedIds.clear()
                    skippedIds.clear()
                    docFolderCounts.clear()
                    transferredBytesCounter.set(0L)
                    completedFilesCounter.set(0)
                    activeRunIsResume.set(false)
                    requestedWhatsAppMigration.set(req.transferScope.whatsApp)
                    synchronized(rxProgressLock) {
                        rxProgressAccounting = null
                        rxSpeedMeter = SlidingTransferSpeedMeter()
                        rxEtaTracker.reset()
                    }
                    _progress.value = LiveTransferProgress(
                        phaseLabel = "Sto preparando la ricezione da ${req.senderName}...",
                        peerDeviceName = req.senderName,
                        peerPlatform = req.senderPlatform,
                        activeTransferScope = req.transferScope,
                        sessionStage = if (req.transferScope.isWhatsAppOnly) {
                            TransferSessionStage.TRANSFERRING
                        } else {
                            TransferSessionStage.PREPARING
                        }
                    )
                    writeEncryptedJsonResponse(output, 200, """{"ok":true}""")
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

                    val (freeBytes, _) = StorageCapacityChecker.getFreeAndTotalBytes(context)

                    activeTier = LicensePolicyEvaluator.resolveTier(
                        senderPlatform = req.senderPlatform,
                        receiverPlatform = DevicePlatform.ANDROID,
                        senderHasPro = true,
                        receiverHasPro = true,
                        senderHasCloudSavePro = false,
                        receiverHasCloudSavePro = false
                    )
                    val isResume = req.isResume == true
                    activeRunIsResume.set(isResume)

                    // Su nuovo trasferimento azzeriamo lo stato precedente; su ripresa (`isResume = true`)
                    // conserviamo file completati, byte già scritti e contatori così la barra prosegue senza tornare a 0%.
                    if (!isResume) {
                        manifestMap.clear()
                        completedIds.clear()
                        committedItemHashes.clear()
                        skippedIds.clear()
                        liveVideoAccountedIds.clear()
                        docFolderCounts.clear()
                        transferredBytesCounter.set(0L)
                        completedFilesCounter.set(0)
                        requestedWhatsAppMigration.set(false)
                        synchronized(rxProgressLock) {
                            rxProgressAccounting = null
                            rxSpeedMeter = SlidingTransferSpeedMeter()
                            rxEtaTracker.reset()
                        }
                        transferStartMillis = System.currentTimeMillis()
                    } else if (transferStartMillis == 0L) {
                        transferStartMillis = System.currentTimeMillis()
                    }

                    // All'handshake verifichiamo un margine minimo operativo (250 MB): il controllo esatto
                    // sui byte ancora da scrivere viene eseguito in `/v1/manifest` dopo la deduplica (fondamentale su Resume!).
                    val hasMinimalWorkingRoom = freeBytes > 250L * 1024L * 1024L
                    val enoughSpace = hasMinimalWorkingRoom && (
                        if (completedIds.isEmpty()) {
                            req.totalEstimatedBytes < (freeBytes - 150L * 1024L * 1024L).coerceAtLeast(0L) ||
                                req.totalEstimatedBytes == 0L
                        } else {
                            true
                        }
                    )
                    val allowProceedToManifest = hasMinimalWorkingRoom || req.totalEstimatedBytes == 0L
                    handshakeCompleted.set(allowProceedToManifest)

                    val nextScope = req.transferScope ?: _progress.value.activeTransferScope
                    val spaceError = if (!allowProceedToManifest) {
                        "Spazio su dispositivo insufficiente (meno di 250 MB liberi)."
                    } else {
                        null
                    }
                    val detectedMedium = LocalNetworkAddresses.detectConnectionMedium(
                        targetIp = socket.localAddress?.hostAddress,
                        isHotspotOrP2p = !activeQrPayloadSnapshot?.wifiSsid.isNullOrBlank()
                    )
                    if (!isResume) {
                        _progress.value = LiveTransferProgress(
                            phaseLabel = if (allowProceedToManifest) {
                                "Sto preparando la ricezione da ${req.senderName}..."
                            } else {
                                "Spazio su disco insufficiente per completare il trasferimento."
                            },
                            peerDeviceName = req.senderName,
                            peerPlatform = req.senderPlatform,
                            licenseTier = activeTier,
                            connectionMedium = detectedMedium,
                            activeTransferScope = nextScope,
                            sessionStage = if (nextScope.isWhatsAppOnly) {
                                TransferSessionStage.TRANSFERRING
                            } else {
                                TransferSessionStage.PREPARING
                            },
                            errorMessage = spaceError
                        )
                    } else {
                        val prev = _progress.value
                        _progress.value = prev.copy(
                            phaseLabel = if (allowProceedToManifest) {
                                "Ripresa connessione con ${req.senderName}..."
                            } else {
                                "Spazio su disco insufficiente per riprendere il trasferimento."
                            },
                            peerDeviceName = req.senderName,
                            peerPlatform = req.senderPlatform,
                            licenseTier = activeTier,
                            connectionMedium = detectedMedium,
                            activeTransferScope = nextScope,
                            sessionStage = if (prev.sessionStage == TransferSessionStage.TRANSFERRING || nextScope.isWhatsAppOnly) {
                                TransferSessionStage.TRANSFERRING
                            } else {
                                TransferSessionStage.PREPARING
                            },
                            errorMessage = spaceError
                        )
                    }

                    val receiverApps = runCatching {
                        InstalledAppsScanner.scanUserInstalledApps(context).map { it.packageName }
                    }.getOrDefault(emptyList())

                    val resp = HandshakeResponse(
                        accepted = allowProceedToManifest,
                        receiverName = "${Build.MANUFACTURER} ${Build.MODEL}".trim(),
                        receiverPlatform = DevicePlatform.ANDROID,
                        freeStorageBytes = freeBytes,
                        licenseTier = activeTier,
                        hasEnoughSpace = enoughSpace || allowProceedToManifest,
                        statusMessage = if (allowProceedToManifest) "Pronto al trasferimento diretto" else "Spazio su disco insufficiente",
                        supportsCrossOsLiveMotion = true,
                        supportsReconcile = true,
                        receiverInstalledAppIds = receiverApps
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
                    val isResume = activeRunIsResume.get()
                    val effectiveScope = manifest.transferScope ?: ActiveTransferScope.inferred(manifest)
                    val wantsWa = manifest.requestNativeWhatsAppMigration || effectiveScope.whatsApp
                    if (!isResume || wantsWa) {
                        requestedWhatsAppMigration.set(wantsWa)
                    }

                    // 1. Smart Merge Contatti (sempre abilitato), Calendari & SMS (se consentito dal tier)
                    val (mergedContacts, skippedContacts) = ContactsSmartMerger.mergeIncomingContacts(
                        context,
                        manifest.contactsPayload
                    )
                    val (importedCalendars, calendarsAlreadyPresent) = if (LicensePolicyEvaluator.allowsFullCategories(activeTier)) {
                        CalendarMigrator.importEventsDeduplicatedWithStats(context, manifest.calendarsPayload)
                    } else {
                        0 to 0
                    }
                    val (importedReminders, remindersAlreadyPresent) = if (
                        LicensePolicyEvaluator.allowsFullCategories(activeTier) &&
                        !manifest.remindersPayload.isNullOrEmpty()
                    ) {
                        AndroidRemindersMigrator.importRemindersWithStats(context, manifest.remindersPayload)
                    } else {
                        0 to 0
                    }
                    val importedSms = if (LicensePolicyEvaluator.allowsFullCategories(activeTier)) {
                        SmsSystemScanner.importSmsIntoSystemOrArchive(context, manifest.smsPayload)
                    } else {
                        0
                    }
                    val importedCallLogs = if (
                        LicensePolicyEvaluator.allowsFullCategories(activeTier) &&
                        !manifest.callLogsPayload.isNullOrEmpty()
                    ) {
                        CallLogMigrator.importCallLogsWithArchive(context, manifest.callLogsPayload)
                    } else {
                        0
                    }

                    // 2. Filtro Licenza (Intra-OS Free vs Cross-OS Pro/Preview) + Dedup Media
                    val (tierFilteredItems, gatedCount) = LicensePolicyEvaluator.filterItemsForTier(
                        manifest.items,
                        activeTier
                    )
                    val existingMediaKeys = MediaExifScannerAndImporter.buildExistingDedupKeys(context)
                    val existingDocKeys = DocumentsAndWhatsAppScanner.buildExistingDocumentDedupKeys(context)
                    val acceptedItems = mutableListOf<ManifestItem>()
                    var skippedMediaDups = 0

                    for (item in tierFilteredItems) {
                        val isMediaDup = (item.category == TransferCategory.PHOTOS || item.category == TransferCategory.VIDEOS) &&
                            item.dedupKey in existingMediaKeys
                        val docKey = "${PublicDownloadsSaver.sanitizedRelativeSegments(item.relativeAlbumOrFolder).joinToString("/").lowercase()}/${item.fileName.lowercase()}_${item.sizeBytes}"
                        val isDocDup = (item.category == TransferCategory.DOCUMENTS || item.category == TransferCategory.WHATSAPP_VAULT) &&
                            docKey in existingDocKeys

                        if (item.id in completedIds || item.id in skippedIds || isMediaDup || isDocDup) {
                            skippedMediaDups++
                        } else {
                            manifestMap[item.id] = item
                            acceptedItems.add(item)
                        }
                    }

                    val receivedApps = if (LicensePolicyEvaluator.allowsFullCategories(activeTier)) {
                        manifest.installedAppsPayload
                    } else {
                        emptyList()
                    }
                    val remainingBytesToReceive = acceptedItems.sumOf { it.sizeBytes }
                    val remainingLiveBytesToReceive = acceptedItems.sumOf { item ->
                        if (item.isLivePhoto == true && item.id !in liveVideoAccountedIds) {
                            (item.livePhotoVideoSizeBytes ?: 0L).coerceAtLeast(0L)
                        } else {
                            0L
                        }
                    }
                    val totalRemainingToReceive = remainingBytesToReceive + remainingLiveBytesToReceive
                    val (freeNow, _) = StorageCapacityChecker.getFreeAndTotalBytes(context)
                    if (totalRemainingToReceive > 0L &&
                        totalRemainingToReceive > (freeNow - 150L * 1024L * 1024L).coerceAtLeast(0L)
                    ) {
                        val neededText = TransferDisplayFormatting.formatBytes(totalRemainingToReceive)
                        _progress.value = _progress.value.copy(
                            errorMessage = "Spazio libero insufficiente su questo telefono per i restanti $neededText."
                        )
                        writeJsonResponse(output, 507, """{"error":"insufficient_storage"}""")
                        return
                    }

                    val previouslyCompletedInSession = completedIds.size
                    val previouslyFailedInSession = skippedIds.size
                    val previouslySentBytes = transferredBytesCounter.get()
                    val (acc, initialEtaLabel) = synchronized(rxProgressLock) {
                        val accounting = TransferProgressAccounting(
                            queuedItemsCount = acceptedItems.size,
                            remainingEstimatedBytes = remainingBytesToReceive,
                            previouslyCompletedItems = previouslyCompletedInSession,
                            previouslySentBytes = previouslySentBytes,
                            previouslyFailedItems = previouslyFailedInSession,
                            remainingEstimatedLiveBytes = remainingLiveBytesToReceive
                        )
                        rxProgressAccounting = accounting
                        rxSpeedMeter = SlidingTransferSpeedMeter()
                        rxEtaTracker.reset(initialFraction = accounting.progressFraction)
                        val eta = rxEtaTracker.currentLabel(
                            isCompleted = false,
                            hasTransferableItems = accounting.initialTotalItems > 0
                        )
                        accounting to eta
                    }

                    val prev = _progress.value
                    val totalMergedContacts = if (isResume) prev.mergedContacts + mergedContacts else mergedContacts
                    val totalImportedCalendars = if (isResume) prev.importedCalendars + importedCalendars else importedCalendars
                    val totalCalendarsAlreadyPresent = if (isResume) maxOf(prev.calendarsAlreadyPresent, calendarsAlreadyPresent) else calendarsAlreadyPresent
                    val totalImportedReminders = if (isResume) prev.importedReminders + importedReminders else importedReminders
                    val totalRemindersAlreadyPresent = if (isResume) maxOf(prev.remindersAlreadyPresent, remindersAlreadyPresent) else remindersAlreadyPresent
                    val totalImportedSms = if (isResume) prev.importedSms + importedSms else importedSms
                    val totalImportedCallLogs = if (isResume) prev.importedCallLogs + importedCallLogs else importedCallLogs
                    val finalApps = if (isResume && receivedApps.isEmpty()) prev.receivedInstalledApps else receivedApps

                    _progress.value = prev.copy(
                        phaseLabel = when {
                            isResume && acceptedItems.isNotEmpty() -> "Ripresa ricezione (${acceptedItems.size} elementi rimanenti)..."
                            acceptedItems.isEmpty() -> "Finalizzazione dati ricevuti..."
                            else -> "Pronto per la ricezione (${acceptedItems.size} elementi)..."
                        },
                        completedItems = previouslyCompletedInSession,
                        totalItems = previouslyCompletedInSession + previouslyFailedInSession + acceptedItems.size,
                        transferredBytes = previouslySentBytes,
                        totalBytes = acc.totalBytesForProgress,
                        failedItemsCount = previouslyFailedInSession,
                        etaLabel = initialEtaLabel,
                        mergedContacts = totalMergedContacts,
                        contactsAlreadyPresent = skippedContacts,
                        importedCalendars = totalImportedCalendars,
                        calendarsAlreadyPresent = totalCalendarsAlreadyPresent,
                        importedReminders = totalImportedReminders,
                        remindersAlreadyPresent = totalRemindersAlreadyPresent,
                        importedSms = totalImportedSms,
                        importedCallLogs = totalImportedCallLogs,
                        skippedDuplicates = skippedContacts + skippedMediaDups,
                        receivedInstalledApps = finalApps,
                        activeTransferScope = effectiveScope,
                        gatedPreviewCount = gatedCount,
                        errorMessage = null
                    )

                    val resp = ManifestResponse(
                        acceptedItemIds = acceptedItems.map { it.id },
                        skippedDuplicateCount = skippedContacts + skippedMediaDups,
                        contactsMergedCount = totalMergedContacts,
                        contactsSkippedDuplicates = skippedContacts,
                        calendarsImportedCount = totalImportedCalendars,
                        calendarsAlreadyPresentCount = totalCalendarsAlreadyPresent,
                        remindersImportedCount = totalImportedReminders,
                        remindersAlreadyPresentCount = totalRemindersAlreadyPresent,
                        smsImportedCount = totalImportedSms,
                        callLogsImportedCount = totalImportedCallLogs,
                        gatedByCrossOsPreviewCount = gatedCount
                    )
                    writeEncryptedJsonResponse(output, 200, DirectSwitchJson.instance.encodeToString(resp))
                }

                method == "POST" && pathOnly == "/v1/begin-transfer" -> {
                    if (!handshakeCompleted.get()) {
                        writeJsonResponse(output, 401, """{"error":"Sessione non autorizzata"}""")
                        return
                    }
                    if (contentLength > 0L) {
                        val encryptedBody = readFixedBytes(input, contentLength.toInt())
                        try {
                            DirectSwitchCrypto.openJsonEnvelope(encryptedBody, sessionAesKey)
                        } catch (_: Throwable) {
                            writeJsonResponse(output, 401, """{"error":"Begin non autenticato"}""")
                            return
                        }
                    }
                    if (!_progress.value.isCompleted) {
                        val initialEtaLabel = synchronized(rxProgressLock) {
                            val acc = rxProgressAccounting
                            if (acc != null) {
                                rxEtaTracker.reset(initialFraction = acc.progressFraction)
                                rxEtaTracker.currentLabel(
                                    isCompleted = false,
                                    hasTransferableItems = acc.initialTotalItems > 0
                                )
                            } else {
                                _progress.value.etaLabel
                            }
                        }
                        _progress.value = _progress.value.copy(
                            phaseLabel = if (_progress.value.totalItems > 0) "Copia diretta cifrata in corso..." else "Finalizzazione...",
                            sessionStage = TransferSessionStage.TRANSFERRING,
                            etaLabel = initialEtaLabel
                        )
                    }
                    writeEncryptedJsonResponse(output, 200, """{"ok":true}""")
                }

                method == "PUT" && pathOnly.startsWith("/v1/item-live-video/") -> {
                    if (!handshakeCompleted.get()) {
                        writeJsonResponse(output, 401, """{"error":"Sessione non autorizzata"}""")
                        return
                    }
                    val itemId = pathOnly.removePrefix("/v1/item-live-video/")
                    val item = manifestMap[itemId]
                    if (item == null) {
                        writeJsonResponse(output, 404, """{"error":"Item Live non trovato nel manifesto"}""")
                        return
                    }
                    val expectedSha256 = headers["x-ds-sha256"]?.lowercase()
                    val expectedPlainLen = headers["x-ds-plain-length"]?.toLongOrNull()
                    val boundedCipherStream = BoundedInputStream(input, contentLength)
                    val safeTempId = item.id.replace(Regex("[^a-zA-Z0-9_-]"), "_")
                    val liveExt = headers["x-ds-live-ext"]?.lowercase()?.takeIf { it.matches(Regex("[a-z0-9]{2,5}")) }
                        ?: File(item.livePhotoVideoFileName ?: "live.mov").extension.lowercase().ifBlank { "mov" }
                    val tempLiveFile = File(context.cacheDir, "rx_live_${safeTempId}.$liveExt")
                    val decRes = runCatching {
                        tempLiveFile.outputStream().use { fout ->
                            DirectSwitchCrypto.decryptStreamCsgcm1(boundedCipherStream, fout, sessionAesKey)
                        }
                    }.getOrNull()
                    if (decRes == null) {
                        tempLiveFile.delete()
                        writeJsonResponse(output, 401, """{"error":"Decifratura Live Video CSGCM1 fallita"}""")
                        return
                    }
                    val (plainBytes, actualSha256) = decRes
                    if ((expectedPlainLen != null && plainBytes != expectedPlainLen) ||
                        (!expectedSha256.isNullOrBlank() && actualSha256 != expectedSha256)
                    ) {
                        tempLiveFile.delete()
                        writeJsonResponse(output, 422, """{"error":"Integrità Live Video SHA-256 non valida"}""")
                        return
                    }
                    pendingLiveVideoTempFiles.put(itemId, tempLiveFile)?.delete()
                    val (doneBytesNow, totBytesNow, speedMbs, etaLabelStr, pctInt) = synchronized(rxProgressLock) {
                        val firstLive = liveVideoAccountedIds.add(itemId)
                        val estLive = if (firstLive) (item.livePhotoVideoSizeBytes ?: 0L).coerceAtLeast(0L) else 0L
                        rxProgressAccounting?.recordLiveVideoUploaded(estLive, plainBytes)
                        val acc = rxProgressAccounting
                        val done = acc?.transferredBytes ?: transferredBytesCounter.addAndGet(plainBytes)
                        if (acc != null) transferredBytesCounter.set(done)
                        val tot = acc?.totalBytesForProgress?.coerceAtLeast(done) ?: done
                        val spd = rxSpeedMeter.record(plainBytes)
                        val frac = acc?.progressFraction ?: 0f
                        val eta = rxEtaTracker.update(
                            progressFraction = frac,
                            isCompleted = false,
                            hasTransferableItems = (acc?.initialTotalItems ?: 0) > 0
                        )
                        val pct = TransferDisplayFormatting.percentageInt(frac.toDouble(), false)
                        listOf(done, tot, spd, eta, pct)
                    }
                    val liveDoneLong = doneBytesNow as Long
                    val liveTotLong = totBytesNow as Long
                    val liveSpd = speedMbs as Double
                    val liveEta = etaLabelStr as String?
                    val livePct = pctInt as Int
                    _progress.value = _progress.value.copy(
                        transferredBytes = liveDoneLong,
                        totalBytes = liveTotLong,
                        speedMegabytesPerSec = liveSpd,
                        etaLabel = liveEta,
                        sessionStage = TransferSessionStage.TRANSFERRING
                    )
                    DirectSwitchKeepAliveService.updateProgress(
                        context = context,
                        percent = livePct,
                        statusText = "Ricezione: ${TransferDisplayFormatting.formatBytes(liveDoneLong)} / ${TransferDisplayFormatting.formatBytes(liveTotLong)}",
                        etaSubText = liveEta
                    )
                    writeJsonResponse(output, 200, """{"ok":true,"bytes":$plainBytes}""")
                }

                method == "PUT" && pathOnly.startsWith("/v1/item/") -> {
                    if (!handshakeCompleted.get()) {
                        writeJsonResponse(output, 401, """{"error":"Sessione non autorizzata"}""")
                        return
                    }
                    val itemId = pathOnly.removePrefix("/v1/item/")
                    val pairedLiveVideoFile = pendingLiveVideoTempFiles.remove(itemId)
                    if (itemId in completedIds) {
                        pairedLiveVideoFile?.delete()
                        writeJsonResponse(output, 200, """{"ok":true,"alreadyCompleted":true}""")
                        return
                    }
                    val item = manifestMap[itemId]
                    if (item == null) {
                        pairedLiveVideoFile?.delete()
                        writeJsonResponse(output, 404, """{"error":"Item non trovato nel manifesto"}""")
                        return
                    }
                    val expectedSha256 = headers["x-ds-sha256"]?.lowercase()
                    val expectedPlainLen = headers["x-ds-plain-length"]?.toLongOrNull() ?: item.sizeBytes

                    val boundedCipherStream = BoundedInputStream(input, contentLength)
                    val safeTempId = item.id.replace(Regex("[^a-zA-Z0-9_-]"), "_")
                    val tempDecrypted = File(context.cacheDir, "rx_${safeTempId}.tmp")
                    var assembledMotionTemp: File? = null
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

                        val baseSanitizedFileName = File(item.fileName).name
                            .replace(Regex("[\\\\/:*?\"<>|]"), "_")
                            .ifBlank { "file_${safeTempId}" }
                        val actualExtHeader = headers["x-ds-actual-ext"]?.trim()?.lowercase()
                        val reconciledMedia = when (item.category) {
                            TransferCategory.PHOTOS, TransferCategory.VIDEOS -> {
                                MediaFallbackNaming.reconcileFileNameAndMime(
                                    fileName = baseSanitizedFileName,
                                    originalMime = item.mimeType,
                                    actualExtension = actualExtHeader
                                )
                            }
                            TransferCategory.AUDIO -> {
                                if (actualExtHeader == "m4a") {
                                    Triple(CrossOsCodecCompatibilityHelper.healedM4aFileName(baseSanitizedFileName), "audio/mp4", "m4a")
                                } else {
                                    Triple(baseSanitizedFileName, item.mimeType, "")
                                }
                            }
                            else -> Triple(baseSanitizedFileName, item.mimeType, "")
                        }
                        var sanitizedFileName = reconciledMedia.first
                        var effectiveMime = reconciledMedia.second

                        // Timeline Healer: ricostruisce data scatto reale da nome file se mancante/copiata oggi
                        val healedTimeline = if (item.category == TransferCategory.PHOTOS || item.category == TransferCategory.VIDEOS) {
                            MediaTimelineHealer.resolveBestCaptureEpochMillis(sanitizedFileName, item.capturedEpochMillis)
                        } else null
                        val effectiveCapturedMs = healedTimeline?.epochMillis ?: item.capturedEpochMillis
                        if (healedTimeline?.wasHealedFromFilename == true) {
                            healedTimelineCounter.incrementAndGet()
                        }

                        // Live Photo (iOS) -> Android Motion Photo JPEG nativa
                        var fileToImport = tempDecrypted
                        if (item.category == TransferCategory.PHOTOS && pairedLiveVideoFile != null && pairedLiveVideoFile.exists()) {
                            val motionOut = File(context.cacheDir, "rx_motion_${safeTempId}.jpg")
                            val assembledOk = AndroidLiveMotionBridge.assembleIncomingIosLivePhotoToMotionJpeg(
                                context = context,
                                stillFile = tempDecrypted,
                                stillFileName = sanitizedFileName,
                                liveVideoFile = pairedLiveVideoFile,
                                outMotionJpegFile = motionOut
                            )
                            if (assembledOk) {
                                assembledMotionTemp = motionOut
                                fileToImport = motionOut
                                val stem = sanitizedFileName.substringBeforeLast('.', sanitizedFileName)
                                sanitizedFileName = "$stem.jpg"
                                effectiveMime = "image/jpeg"
                                convertedLiveMotionCounter.incrementAndGet()
                            }
                        }

                        // Iniezione EXIF DateTimeOriginal & GPS su foto statiche (evitando di rovinare la coda MP4 delle Motion Photo)
                        if (item.category == TransferCategory.PHOTOS && assembledMotionTemp == null && effectiveCapturedMs > 0L) {
                            AndroidTimelineExifInjector.injectCaptureMetadataIfNeeded(
                                mediaFile = fileToImport,
                                fileName = sanitizedFileName,
                                targetEpochMillis = effectiveCapturedMs,
                                forceOverwriteDate = healedTimeline?.wasHealedFromFilename == true,
                                latitude = item.latitude,
                                longitude = item.longitude
                            )
                        }

                        val safeItem = item.copy(
                            fileName = sanitizedFileName,
                            mimeType = effectiveMime,
                            capturedEpochMillis = effectiveCapturedMs,
                            sizeBytes = fileToImport.length().coerceAtLeast(item.sizeBytes)
                        )

                        val subFolder = if (safeItem.category == TransferCategory.WHATSAPP_VAULT) {
                            val cleanWaRel = PublicDownloadsSaver.sanitizedRelativeSegments(safeItem.relativeAlbumOrFolder)
                                .joinToString("/")
                            if (cleanWaRel.startsWith("Android/media/com.whatsapp", ignoreCase = true)) {
                                cleanWaRel
                            } else {
                                "WhatsApp_Vault"
                            }
                        } else {
                            PublicDownloadsSaver.sanitizedRelativeSegments(safeItem.relativeAlbumOrFolder)
                                .joinToString("/")
                                .ifBlank { Environment.DIRECTORY_DOCUMENTS }
                        }

                        if (safeItem.category == TransferCategory.WHATSAPP_VAULT &&
                            (sanitizedFileName.endsWith(".zip", ignoreCase = true) ||
                                sanitizedFileName.endsWith(".txt", ignoreCase = true))
                        ) {
                            WhatsAppVaultReader.ingestReceivedArchive(context, sanitizedFileName, fileToImport)
                        }

                        val importedOk = when (safeItem.category) {
                            TransferCategory.PHOTOS, TransferCategory.VIDEOS -> {
                                fileToImport.inputStream().use { plainIn ->
                                    MediaExifScannerAndImporter.importMediaStream(context, safeItem, plainIn)
                                }
                            }
                            TransferCategory.AUDIO -> {
                                AudioAndMemoMigrator.saveIncomingAudioFile(context, safeItem, fileToImport)
                            }
                            else -> {
                                fileToImport.inputStream().use { plainIn ->
                                    PublicDownloadsSaver.saveStream(
                                        context = context,
                                        subFolder = subFolder,
                                        fileName = sanitizedFileName,
                                        mimeType = safeItem.mimeType,
                                        inputStream = plainIn,
                                        expectedSizeBytes = safeItem.sizeBytes
                                    )
                                }
                            }
                        }

                        if (!importedOk) {
                            writeJsonResponse(output, 500, """{"error":"Impossibile salvare il file su archivio pubblico"}""")
                            return
                        }

                        committedItemHashes[itemId] = actualSha256
                        if (completedIds.add(itemId)) {
                            if (safeItem.category != TransferCategory.PHOTOS && safeItem.category != TransferCategory.VIDEOS) {
                                docFolderCounts[subFolder] = (docFolderCounts[subFolder] ?: 0) + 1
                            }

                            val doneFiles = completedFilesCounter.incrementAndGet()
                            val (doneBytesAny, reconciledTotalBytes, speedMbs, etaStr, pctNow) = synchronized(rxProgressLock) {
                                val estLive = (item.livePhotoVideoSizeBytes ?: 0L).coerceAtLeast(0L)
                                if (item.isLivePhoto == true && estLive > 0L && liveVideoAccountedIds.add(itemId)) {
                                    // La clip Live Photo non è arrivata (saltata lato mittente): detraiamo la stima in modo identico
                                    rxProgressAccounting?.recordLiveVideoSkipped(estLive)
                                }
                                rxProgressAccounting?.recordPrimaryItemUploaded(item.sizeBytes, plainBytes)
                                val acc = rxProgressAccounting
                                val done = acc?.transferredBytes ?: transferredBytesCounter.addAndGet(plainBytes)
                                if (acc != null) transferredBytesCounter.set(done)
                                val tot = acc?.totalBytesForProgress?.coerceAtLeast(done) ?: done
                                val spd = rxSpeedMeter.record(plainBytes)
                                val frac = acc?.progressFraction ?: 0f
                                val eta = rxEtaTracker.update(
                                    progressFraction = frac,
                                    isCompleted = false,
                                    hasTransferableItems = (acc?.initialTotalItems ?: 0) > 0
                                )
                                val pct = TransferDisplayFormatting.percentageInt(frac.toDouble(), false)
                                listOf(done, tot, spd, eta, pct)
                            }
                            val doneBytes = doneBytesAny as Long
                            val totBytesLong = reconciledTotalBytes as Long
                            val speedDouble = speedMbs as Double
                            val etaLabelStr = etaStr as String?
                            val pctInt = pctNow as Int

                            _progress.value = _progress.value.copy(
                                currentFileName = sanitizedFileName,
                                completedItems = doneFiles,
                                transferredBytes = doneBytes,
                                totalBytes = totBytesLong,
                                speedMegabytesPerSec = speedDouble,
                                etaLabel = etaLabelStr,
                                healedTimelineCount = healedTimelineCounter.get(),
                                convertedLiveMotionCount = convertedLiveMotionCounter.get(),
                                sessionStage = TransferSessionStage.TRANSFERRING,
                                receivedDocumentFolders = docFolderCounts.toMap()
                            )
                            DirectSwitchKeepAliveService.updateProgress(
                                context = context,
                                percent = pctInt,
                                statusText = "Ricezione: ${TransferDisplayFormatting.formatBytes(doneBytes)} / ${TransferDisplayFormatting.formatBytes(totBytesLong)}",
                                etaSubText = etaLabelStr
                            )
                        }
                        writeJsonResponse(output, 200, """{"ok":true,"bytes":$plainBytes,"sha256":"$actualSha256"}""")
                    } finally {
                        tempDecrypted.delete()
                        assembledMotionTemp?.delete()
                        pairedLiveVideoFile?.delete()
                    }
                }

                method == "POST" && pathOnly.startsWith("/v1/item-skip/") -> {
                    if (!handshakeCompleted.get()) {
                        writeJsonResponse(output, 401, """{"error":"Sessione non autorizzata"}""")
                        return
                    }
                    if (contentLength > 0L) {
                        if (contentLength > 64L * 1024L) {
                            writeJsonResponse(output, 400, """{"error":"Payload skip troppo grande"}""")
                            return
                        }
                        val encryptedBody = readFixedBytes(input, contentLength.toInt())
                        try {
                            DirectSwitchCrypto.openJsonEnvelope(encryptedBody, sessionAesKey)
                        } catch (_: Throwable) {
                            writeJsonResponse(output, 401, """{"error":"Skip non autenticato"}""")
                            return
                        }
                    }
                    val itemId = pathOnly.removePrefix("/v1/item-skip/")
                    val item = manifestMap[itemId]
                    if (item != null && itemId !in completedIds && skippedIds.add(itemId)) {
                        val (reconciledTotal, failedNow, etaStr) = synchronized(rxProgressLock) {
                            val estLive = if (item.isLivePhoto == true && liveVideoAccountedIds.add(itemId)) {
                                (item.livePhotoVideoSizeBytes ?: 0L).coerceAtLeast(0L)
                            } else {
                                0L
                            }
                            rxProgressAccounting?.recordItemFailedOrSkipped(item.sizeBytes, estLive)
                            val acc = rxProgressAccounting
                            val doneBytes = acc?.transferredBytes ?: transferredBytesCounter.get()
                            val tot = acc?.totalBytesForProgress?.coerceAtLeast(doneBytes) ?: _progress.value.totalBytes
                            val failed = acc?.failedItemsCount ?: (_progress.value.failedItemsCount + 1)
                            val eta = rxEtaTracker.update(
                                progressFraction = acc?.progressFraction ?: 0f,
                                isCompleted = false,
                                hasTransferableItems = (acc?.initialTotalItems ?: 0) > 0
                            )
                            Triple(tot, failed, eta)
                        }
                        _progress.value = _progress.value.copy(
                            totalBytes = reconciledTotal,
                            failedItemsCount = failedNow,
                            etaLabel = etaStr
                        )
                    }
                    writeEncryptedJsonResponse(output, 200, """{"ok":true}""")
                }

                method == "POST" && pathOnly == "/v1/reconcile-manifest" -> {
                    if (!handshakeCompleted.get()) {
                        writeJsonResponse(output, 401, """{"error":"Sessione non autorizzata"}""")
                        return
                    }
                    val encryptedBody = readFixedBytes(input, contentLength.toInt())
                    val plainJson = try {
                        DirectSwitchCrypto.openJsonEnvelope(encryptedBody, sessionAesKey)
                    } catch (_: Throwable) {
                        writeJsonResponse(output, 401, """{"error":"Riconciliazione non autenticata"}""")
                        return
                    }
                    val req = DirectSwitchJson.instance.decodeFromString<ReconcileManifestRequest>(plainJson)
                    val diffResp = ReconciliationDiffCore.evaluate(
                        sentItemIds = req.sentItemIds,
                        expectedHashesById = req.expectedSha256ById,
                        committedHashesById = committedItemHashes.toMap()
                    )
                    writeEncryptedJsonResponse(output, 200, DirectSwitchJson.instance.encodeToString(diffResp))
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
                        etaLabel = null,
                        sessionStage = TransferSessionStage.COMPLETED,
                        isCompleted = true,
                        pendingNativeWhatsAppMigration = requestedWhatsAppMigration.get()
                    )
                    DirectSwitchKeepAliveService.updateProgress(
                        context = context,
                        percent = 100,
                        statusText = "Tutti i dati ricevuti e salvati sul dispositivo!",
                        etaSubText = null,
                        force = true
                    )
                    val report = TransferCompletionReport(
                        sessionId = activeSessionId,
                        licenseTier = activeTier,
                        transferredFilesCount = completedFilesCounter.get(),
                        transferredBytes = transferredBytesCounter.get(),
                        mergedContactsCount = _progress.value.mergedContacts,
                        importedCalendarsCount = _progress.value.importedCalendars,
                        calendarsAlreadyPresentCount = _progress.value.calendarsAlreadyPresent,
                        remindersImportedCount = _progress.value.importedReminders,
                        remindersAlreadyPresentCount = _progress.value.remindersAlreadyPresent,
                        importedSmsCount = _progress.value.importedSms,
                        callLogsImportedCount = _progress.value.importedCallLogs,
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
        val medium: TransferConnectionMedium = TransferConnectionMedium.LOCAL_WIFI,
        val cleanup: () -> Unit = {}
    )

    private val baseHttpClient = OkHttpClient.Builder()
        .dispatcher(
            Dispatcher().apply {
                maxRequests = 16
                maxRequestsPerHost = 6
            }
        )
        .connectTimeout(4, TimeUnit.SECONDS)
        .readTimeout(120, TimeUnit.SECONDS)
        .writeTimeout(120, TimeUnit.SECONDS)
        .build()

    private val _progress = MutableStateFlow(LiveTransferProgress())
    val progress: StateFlow<LiveTransferProgress> = _progress

    private val _networkDiagnostic = MutableStateFlow<NetworkDiagnosticVerdict?>(null)
    val networkDiagnostic: StateFlow<NetworkDiagnosticVerdict?> = _networkDiagnostic

    @Volatile
    private var prepAnimDeferred: CompletableDeferred<Unit>? = null

    fun markPreparationAnimationCompleted() {
        prepAnimDeferred?.complete(Unit)
    }

    fun resetProgress() {
        prepAnimDeferred?.complete(Unit)
        prepAnimDeferred = null
        _networkDiagnostic.value = null
        _progress.value = LiveTransferProgress()
    }

    suspend fun sendPairAck(qrPayload: QrPairingPayload) = withContext(Dispatchers.IO) {
        val channel = resolveChannel(
            candidateIps = qrPayload.ips,
            port = qrPayload.port,
            wifiSsid = qrPayload.wifiSsid,
            wifiPass = qrPayload.wifiPass
        ) ?: return@withContext
        try {
            val sessionAesKey = DirectSwitchCrypto.deriveSessionAesKey(qrPayload.sessionKeyHex)
            val ack = PairAckRequest(
                sessionId = qrPayload.sessionId,
                senderName = "${Build.MANUFACTURER} ${Build.MODEL}".trim(),
                senderPlatform = DevicePlatform.ANDROID
            )
            runCatching {
                postEncryptedJson(
                    client = channel.client,
                    url = "http://${channel.reachableIp}:${qrPayload.port}/v1/pair-ack",
                    plainJson = DirectSwitchJson.instance.encodeToString(ack),
                    aesKey = sessionAesKey
                )
            }
        } finally {
            channel.cleanup()
        }
    }

    suspend fun sendPairReset(qrPayload: QrPairingPayload) = withContext(Dispatchers.IO) {
        val channel = resolveChannel(qrPayload.ips, qrPayload.port, null, null) ?: return@withContext
        try {
            val sessionAesKey = DirectSwitchCrypto.deriveSessionAesKey(qrPayload.sessionKeyHex)
            runCatching {
                postEncryptedJson(
                    client = channel.client,
                    url = "http://${channel.reachableIp}:${qrPayload.port}/v1/pair-reset",
                    plainJson = """{"sessionId":"${qrPayload.sessionId}"}""",
                    aesKey = sessionAesKey
                )
            }
        } finally {
            channel.cleanup()
        }
    }

    private fun buildInitialPreparationItems(
        scope: ActiveTransferScope,
        includeSms: Boolean
    ): List<TransferPreparationItem> = buildList {
        if (scope.contacts) add(TransferPreparationItem("contacts", "Rubrica contatti", "contatto", "contatti"))
        if (scope.photos) add(TransferPreparationItem("photos", "Foto e Album", "foto", "foto"))
        if (scope.videos) add(TransferPreparationItem("videos", "Video originali", "video", "video"))
        if (scope.calendars) add(TransferPreparationItem("calendars", "Calendari", "evento", "eventi"))
        if (includeSms) add(TransferPreparationItem("sms", "Messaggi SMS", "messaggio", "messaggi"))
        if (scope.callLogs) add(TransferPreparationItem("callLogs", "Cronologia Chiamate", "chiamata", "chiamate"))
        if (scope.audio) add(TransferPreparationItem("audio", "Audio e Memo Vocali", "traccia", "tracce"))
        if (scope.documents) add(TransferPreparationItem("documents", "Documenti e File", "file", "file"))
        if (scope.apps) add(TransferPreparationItem("apps", "App scaricate", "app", "app"))
    }

    private fun updatePreparationItem(id: String, targetCount: Int, isReady: Boolean) {
        val updated = _progress.value.preparationItems.map { item ->
            if (item.id == id) item.copy(targetCount = targetCount.coerceAtLeast(0), isReady = isReady) else item
        }
        _progress.value = _progress.value.copy(preparationItems = updated)
    }

    /**
     * Scambia in modo autenticato il PIN a 6 cifre letto sullo schermo del ricevente con il
     * [QrPairingPayload] completo (contenente la chiave di sessione a 256 bit).
     */
    suspend fun pairWithBeaconUsingPin(
        beacon: DiscoveryBeaconPayload,
        pin: String
    ): Result<QrPairingPayload> = withContext(Dispatchers.IO) {
        _networkDiagnostic.value = null
        try {
            val cleanPin = pin.filter { it.isDigit() }
            require(cleanPin.length == 6) { "Inserisci il codice PIN a 6 cifre mostrato sul nuovo telefono." }
            val channel = resolveChannel(beacon.ips, beacon.port, null, null)
                ?: run {
                    val errMsg = if (beacon.receiverPlatform == DevicePlatform.IOS) {
                        "Impossibile raggiungere ${beacon.receiverName}: assicurati che su iPhone sia attiva Impostazioni → App → DirectSwitch → Rete locale."
                    } else {
                        "Impossibile raggiungere ${beacon.receiverName} sulla rete Wi-Fi locale."
                    }
                    val privIps = LocalNetworkAddresses.listPrivateIpv4Addresses()
                    _networkDiagnostic.value = NetworkIsolationDiagnostics.analyzePairingFailure(
                        localIp = privIps.firstOrNull(),
                        targetIps = beacon.ips,
                        isWifiConnected = privIps.isNotEmpty(),
                        errorMessage = errMsg
                    )
                    return@withContext Result.failure(IllegalStateException(errMsg))
                }
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
                _networkDiagnostic.value = null
                Result.success(payload.copy(ips = mergedIps))
            } finally {
                channel.cleanup()
            }
        } catch (t: Throwable) {
            if (t !is IllegalArgumentException && (t is java.net.SocketException || t is java.net.SocketTimeoutException || t is java.io.InterruptedIOException || (t.message?.contains("timeout", ignoreCase = true) == true) || (t.message?.contains("connect", ignoreCase = true) == true))) {
                val privIps = LocalNetworkAddresses.listPrivateIpv4Addresses()
                _networkDiagnostic.value = NetworkIsolationDiagnostics.analyzePairingFailure(
                    localIp = privIps.firstOrNull(),
                    targetIps = beacon.ips,
                    isWifiConnected = privIps.isNotEmpty(),
                    errorMessage = t.localizedMessage ?: t.javaClass.simpleName
                )
            }
            Result.failure(t)
        }
    }

    suspend fun executeTransfer(
        qrPayload: QrPairingPayload,
        includeContacts: Boolean,
        includePhotos: Boolean,
        includeVideos: Boolean,
        includeCalendars: Boolean,
        calendarsUpToTodayOnly: Boolean = false,
        includeSms: Boolean = true,
        smsUpToTodayOnly: Boolean = false,
        includeDocuments: Boolean = true,
        includeWhatsAppVault: Boolean = true,
        includeInstalledApps: Boolean = true,
        installedAppsOverride: List<InstalledAppRecord>? = null,
        includeAudio: Boolean = false,
        includeCallLogs: Boolean = false,
        mediaFilters: MediaTransferFilterOptions = MediaTransferFilterOptions(),
        onlyRetryItemIds: Set<String>? = null,
        resumeCheckpoint: TransferCheckpointRecord? = null,
        stagedPasswordCsvFiles: List<File> = emptyList(),
        deltaBaseline: CompletedMigrationRecord? = null,
        forceBatteryTriage: Boolean = false,
        smartCleanOptions: SmartCleanOptions = SmartCleanOptions(),
        convertHeicToJpeg: Boolean = false
    ): Result<TransferCompletionReport> = withContext(Dispatchers.IO) {
        val channelCleanups = Collections.synchronizedList(mutableListOf<() -> Unit>())
        DirectSwitchKeepAliveService.start(context, "Invio dati verso ${qrPayload.receiverName}...")
        val isTargetedRetry = !onlyRetryItemIds.isNullOrEmpty()
        val effectiveIncludeContacts = if (isTargetedRetry) false else includeContacts
        val effectiveIncludeCalendars = if (isTargetedRetry) false else includeCalendars
        val effectiveIncludeSms = if (isTargetedRetry) false else includeSms
        val effectiveIncludeCallLogs = if (isTargetedRetry) false else includeCallLogs
        val effectiveIncludeApps = if (isTargetedRetry) false else includeInstalledApps
        val senderScope = ActiveTransferScope(
            contacts = effectiveIncludeContacts,
            photos = includePhotos,
            videos = includeVideos,
            calendars = effectiveIncludeCalendars,
            documents = includeDocuments || stagedPasswordCsvFiles.isNotEmpty(),
            apps = effectiveIncludeApps,
            whatsApp = if (isTargetedRetry) false else includeWhatsAppVault,
            audio = includeAudio,
            callLogs = effectiveIncludeCallLogs
        )
        val initialPrepItems = if (senderScope.isWhatsAppOnly) {
            emptyList()
        } else {
            buildInitialPreparationItems(senderScope, effectiveIncludeSms)
        }
        val completedItemIdsSet = Collections.synchronizedSet(
            linkedSetOf<String>().apply {
                resumeCheckpoint?.completedItemIds?.let { addAll(it) }
            }
        )
        val skippedItemsList = Collections.synchronizedList(mutableListOf<SkippedTransferItemRecord>())
        var checkpointTotalItems = resumeCheckpoint?.totalItems ?: 0
        var checkpointTotalBytes = resumeCheckpoint?.totalBytes ?: 0L
        var checkpointUploadedBytes = resumeCheckpoint?.uploadedBytes ?: 0L

        fun saveDiskCheckpoint() {
            if (isTargetedRetry) return
            val completedCopy = synchronized(completedItemIdsSet) { completedItemIdsSet.toList() }
            if (completedCopy.isEmpty()) return
            val skippedCopy = synchronized(skippedItemsList) { skippedItemsList.toList() }
            TransferCheckpointStore.save(
                context = context,
                record = TransferCheckpointRecord(
                    sessionId = qrPayload.sessionId,
                    qrPayloadJson = DirectSwitchJson.instance.encodeToString(qrPayload),
                    receiverName = qrPayload.receiverName,
                    receiverPlatform = qrPayload.receiverPlatform,
                    scope = senderScope,
                    completedItemIds = completedCopy,
                    uploadedBytes = checkpointUploadedBytes,
                    totalItems = checkpointTotalItems,
                    totalBytes = checkpointTotalBytes,
                    skippedItems = skippedCopy,
                    filterOptions = mediaFilters,
                    savedAtEpochMillis = System.currentTimeMillis()
                )
            )
        }

        val prepDeferred = CompletableDeferred<Unit>()
        prepAnimDeferred = prepDeferred
        try {
            _progress.value = LiveTransferProgress(
                phaseLabel = if (senderScope.isWhatsAppOnly) {
                    "Connessione con ${qrPayload.receiverName}..."
                } else {
                    "Sto preparando il trasferimento verso ${qrPayload.receiverName}..."
                },
                peerDeviceName = qrPayload.receiverName,
                peerPlatform = qrPayload.receiverPlatform,
                activeTransferScope = senderScope,
                sessionStage = if (senderScope.isWhatsAppOnly) {
                    TransferSessionStage.TRANSFERRING
                } else {
                    TransferSessionStage.PREPARING
                },
                preparationItems = initialPrepItems,
                arePreparationItemsReady = senderScope.isWhatsAppOnly
            )

            _networkDiagnostic.value = null
            val channel = resolveChannel(
                candidateIps = qrPayload.ips,
                port = qrPayload.port,
                wifiSsid = qrPayload.wifiSsid,
                wifiPass = qrPayload.wifiPass
            ) ?: run {
                val msg = if (qrPayload.receiverPlatform == DevicePlatform.IOS) {
                    "Impossibile raggiungere ${qrPayload.receiverName}. Verifica che sull'iPhone sia attiva Impostazioni → App → DirectSwitch → Rete locale e che entrambi i telefoni siano sulla stessa Wi-Fi."
                } else {
                    "Impossibile raggiungere ${qrPayload.receiverName}. Verifica che entrambi i telefoni siano sulla stessa Wi-Fi o accetta la connessione all'Hotspot DirectSwitch."
                }
                val privIps = LocalNetworkAddresses.listPrivateIpv4Addresses()
                _networkDiagnostic.value = NetworkIsolationDiagnostics.analyzePairingFailure(
                    localIp = privIps.firstOrNull(),
                    targetIps = qrPayload.ips,
                    isWifiConnected = privIps.isNotEmpty(),
                    errorMessage = msg
                )
                _progress.value = _progress.value.copy(
                    sessionStage = TransferSessionStage.TRANSFERRING,
                    errorMessage = msg
                )
                return@withContext Result.failure(IllegalStateException(msg))
            }
            var activeChannel = channel
            channelCleanups.add(channel.cleanup)
            var activeClient = channel.client
            var baseUrl = "http://${channel.reachableIp}:${qrPayload.port}"
            val sessionAesKey = DirectSwitchCrypto.deriveSessionAesKey(qrPayload.sessionKeyHex)
            _progress.value = _progress.value.copy(connectionMedium = channel.medium)

            if (!senderScope.isWhatsAppOnly) {
                val prepReq = TransferPrepareRequest(
                    sessionId = qrPayload.sessionId,
                    senderName = "${Build.MANUFACTURER} ${Build.MODEL}".trim(),
                    senderPlatform = DevicePlatform.ANDROID,
                    transferScope = senderScope
                )
                runCatching {
                    postEncryptedJson(
                        client = activeClient,
                        url = "$baseUrl/v1/prepare",
                        plainJson = DirectSwitchJson.instance.encodeToString(prepReq),
                        aesKey = sessionAesKey
                    )
                }
            }

            // 1. Raccolta dati locali selezionati con conteggio progressivo per la schermata di preparazione
            val endOfTodayCutoff = CalendarMigrator.endOfDayMillis()
            val rawContacts = if (effectiveIncludeContacts) ContactsSmartMerger.readAllContacts(context) else emptyList()
            val (contacts, smartCleanMergedContactsCount) = if (effectiveIncludeContacts && smartCleanOptions.mergeDuplicateContacts) {
                SmartCleanPreTransferEngine.mergeDuplicateContacts(rawContacts)
            } else {
                rawContacts to 0
            }
            if (effectiveIncludeContacts) updatePreparationItem("contacts", contacts.size, isReady = true)

            val photoEntries = if (includePhotos) {
                MediaExifScannerAndImporter.scanMediaEntries(context, includePhotos = true, includeVideos = false)
                    .filter { AndroidMediaFilterHelper.matchesFilter(it.manifestItem, mediaFilters) }
            } else emptyList()
            if (includePhotos) updatePreparationItem("photos", photoEntries.size, isReady = true)

            val videoEntries = if (includeVideos) {
                MediaExifScannerAndImporter.scanMediaEntries(context, includePhotos = false, includeVideos = true)
                    .filter { AndroidMediaFilterHelper.matchesFilter(it.manifestItem, mediaFilters) }
            } else emptyList()
            if (includeVideos) updatePreparationItem("videos", videoEntries.size, isReady = true)

            val rawCalendars = if (effectiveIncludeCalendars) {
                CalendarMigrator.readEvents(context, upToEpochMillis = if (calendarsUpToTodayOnly) endOfTodayCutoff else null)
            } else emptyList()
            val calendars = if (deltaBaseline != null) CompletedMigrationStore.filterDeltaCalendars(rawCalendars, deltaBaseline) else rawCalendars
            if (effectiveIncludeCalendars) updatePreparationItem("calendars", calendars.size, isReady = true)

            val rawSmsList = if (effectiveIncludeSms) {
                SmsSystemScanner.readAllSms(context, upToEpochMillis = if (smsUpToTodayOnly) endOfTodayCutoff else null)
            } else emptyList()
            val smsList = if (deltaBaseline != null) CompletedMigrationStore.filterDeltaSms(rawSmsList, deltaBaseline) else rawSmsList
            if (effectiveIncludeSms) updatePreparationItem("sms", smsList.size, isReady = true)

            val rawCallLogs = if (effectiveIncludeCallLogs) {
                CallLogMigrator.readCallLogs(context)
            } else emptyList()
            val callLogs = if (deltaBaseline != null) CompletedMigrationStore.filterDeltaCallLogs(rawCallLogs, deltaBaseline) else rawCallLogs
            if (effectiveIncludeCallLogs) updatePreparationItem("callLogs", callLogs.size, isReady = true)

            val audioEntries = if (includeAudio) {
                AudioAndMemoMigrator.scanAudioAndVoiceMemos(context)
            } else emptyList()
            if (includeAudio) updatePreparationItem("audio", audioEntries.size, isReady = true)

            val passwordEntries = stagedPasswordCsvFiles.mapIndexedNotNull { idx, file ->
                if (!file.exists() || !file.isFile || file.length() <= 0L) return@mapIndexedNotNull null
                val item = ManifestItem(
                    id = "pwd_csv_${idx}_${file.name.hashCode().toUInt()}",
                    category = TransferCategory.DOCUMENTS,
                    fileName = file.name,
                    relativeAlbumOrFolder = "Password_e_Accessi",
                    sizeBytes = file.length(),
                    capturedEpochMillis = file.lastModified(),
                    dedupKey = "pwd_${file.name.lowercase()}_${file.length()}",
                    mimeType = "text/csv"
                )
                LocalMediaEntry(manifestItem = item, contentUri = Uri.fromFile(file))
            }

            val docEntries = DocumentsAndWhatsAppScanner.scanDocumentAndWhatsAppEntries(
                context = context,
                includeDocuments = includeDocuments,
                includeWhatsAppVault = false
            ) + passwordEntries
            if (senderScope.documents) updatePreparationItem("documents", docEntries.size, isReady = true)

            val installedApps = if (effectiveIncludeApps) {
                installedAppsOverride ?: InstalledAppsScanner.scanUserInstalledApps(context)
            } else emptyList()
            if (effectiveIncludeApps) updatePreparationItem("apps", installedApps.size, isReady = true)

            val rawMediaEntries = photoEntries + videoEntries + audioEntries + docEntries
            val batterySnapshot = AndroidBatteryTriageMonitor.readSnapshot(context)
            val isBatteryTriageActive = forceBatteryTriage || batterySnapshot.recommendsAutoTriage

            val filteredMediaEntries = when {
                isTargetedRetry -> {
                    val retryIds = onlyRetryItemIds.orEmpty()
                    rawMediaEntries.filter { it.manifestItem.id in retryIds }
                }
                resumeCheckpoint != null -> {
                    val doneBefore = resumeCheckpoint.completedItemIds.toHashSet()
                    rawMediaEntries.filterNot { it.manifestItem.id in doneBefore }
                }
                deltaBaseline != null -> {
                    CompletedMigrationStore.filterDeltaEntries(rawMediaEntries, deltaBaseline) { it.manifestItem }
                }
                else -> rawMediaEntries
            }
            val smartCleanMedia = if (!isTargetedRetry &&
                (smartCleanOptions.skipExactDuplicatePhotosSha256 || smartCleanOptions.skipOldScreenshotsOlderThanMonths > 0)
            ) {
                SmartCleanPreTransferEngine.filterMediaSmartClean(
                    entries = filteredMediaEntries,
                    options = smartCleanOptions,
                    itemOf = { it.manifestItem },
                    sha256Of = { SmartCleanPreTransferEngine.computeContentUriSha256(context, it.contentUri) }
                )
            } else {
                SmartCleanMediaResult(filteredMediaEntries, 0, 0, 0L)
            }
            val mediaEntries = if (isBatteryTriageActive) {
                BatteryTriagePlanner.sortByTriagePriority(smartCleanMedia.kept) { it.manifestItem }
            } else {
                smartCleanMedia.kept
            }
            val estimatedBytes = mediaEntries.sumOf { it.manifestItem.sizeBytes }

            // 2. Handshake Cifrato + Spazio Disco
            val handshakeReq = HandshakeRequest(
                sessionId = qrPayload.sessionId,
                senderName = "${Build.MANUFACTURER} ${Build.MODEL}".trim(),
                senderPlatform = DevicePlatform.ANDROID,
                senderHasPro = true,
                senderHasCloudSavePro = false,
                totalEstimatedBytes = estimatedBytes,
                transferScope = senderScope,
                isResume = resumeCheckpoint != null
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
                val relief = SpaceReliefPlanner.evaluate(
                    receiverName = handshakeResp.receiverName,
                    availableFreeBytes = handshakeResp.freeStorageBytes,
                    items = mediaEntries.map { it.manifestItem }
                )
                _progress.value = _progress.value.copy(
                    sessionStage = TransferSessionStage.TRANSFERRING,
                    spaceReliefOffer = relief,
                    errorMessage = msg
                )
                return@withContext Result.failure(IllegalStateException(msg))
            }

            _progress.value = _progress.value.copy(
                peerDeviceName = handshakeResp.receiverName,
                peerPlatform = handshakeResp.receiverPlatform,
                licenseTier = handshakeResp.licenseTier,
                activeTransferScope = senderScope,
                batteryTriageActive = isBatteryTriageActive,
                deltaSyncModeActive = deltaBaseline != null,
                smartCleanMergedContactsCount = smartCleanMergedContactsCount,
                smartCleanSkippedDuplicatesCount = smartCleanMedia.skippedDuplicatesCount,
                smartCleanSkippedScreenshotsCount = smartCleanMedia.skippedOldScreenshotsCount
            )

            // 3. Invio Manifesto Cifrato & Merge immediato Contatti / Calendari / SMS / Chiamate / Catalogo App
            val allowFull = LicensePolicyEvaluator.allowsFullCategories(handshakeResp.licenseTier)
            val wantNativeWa = !isTargetedRetry && includeWhatsAppVault
            val manifest = TransferManifest(
                sessionId = qrPayload.sessionId,
                senderPlatform = DevicePlatform.ANDROID,
                items = mediaEntries.map { it.manifestItem },
                contactsPayload = contacts,
                calendarsPayload = calendars,
                smsPayload = smsList,
                callLogsPayload = callLogs,
                requestNativeWhatsAppMigration = wantNativeWa,
                installedAppsPayload = if (allowFull) installedApps else emptyList(),
                transferScope = senderScope
            )
            val manifestRespJson = try {
                postEncryptedJson(
                    client = activeClient,
                    url = "$baseUrl/v1/manifest",
                    plainJson = DirectSwitchJson.instance.encodeToString(manifest),
                    aesKey = sessionAesKey
                )
            } catch (manifestErr: Throwable) {
                if (manifestErr.message?.contains("Spazio di archiviazione esaurito") == true) {
                    val relief = SpaceReliefPlanner.evaluate(
                        receiverName = handshakeResp.receiverName,
                        availableFreeBytes = handshakeResp.freeStorageBytes,
                        items = mediaEntries.map { it.manifestItem }
                    )
                    _progress.value = _progress.value.copy(
                        sessionStage = TransferSessionStage.TRANSFERRING,
                        spaceReliefOffer = relief,
                        errorMessage = manifestErr.localizedMessage
                    )
                }
                throw manifestErr
            }
            val manifestResp = DirectSwitchJson.instance.decodeFromString<ManifestResponse>(manifestRespJson)

            val acceptedSet = manifestResp.acceptedItemIds.toHashSet()
            val entriesToUpload = mediaEntries.filter { it.manifestItem.id in acceptedSet }
            val totalBytes = entriesToUpload.sumOf { it.manifestItem.sizeBytes }
            val prevCompleted = if (isTargetedRetry) 0 else (resumeCheckpoint?.completedItemIds?.size ?: 0)
            val prevBytes = if (isTargetedRetry) 0L else (resumeCheckpoint?.uploadedBytes ?: 0L)
            val accounting = TransferProgressAccounting(
                queuedItemsCount = entriesToUpload.size,
                remainingEstimatedBytes = totalBytes,
                previouslyCompletedItems = prevCompleted,
                previouslySentBytes = prevBytes
            )
            checkpointTotalItems = accounting.initialTotalItems
            checkpointTotalBytes = accounting.totalBytesForProgress
            checkpointUploadedBytes = accounting.transferredBytes
            val speedMeter = SlidingTransferSpeedMeter()
            val etaTracker = TenPercentSteppedEtaTracker()
            val progressLock = Mutex()

            if (!senderScope.isWhatsAppOnly) {
                _progress.value = _progress.value.copy(arePreparationItemsReady = true)
                withTimeoutOrNull(1_100L) {
                    prepDeferred.await()
                }
                runCatching {
                    postEncryptedJson(
                        client = activeClient,
                        url = "$baseUrl/v1/begin-transfer",
                        plainJson = """{"sessionId":"${qrPayload.sessionId}"}""",
                        aesKey = sessionAesKey
                    )
                }
            }

            etaTracker.reset(initialFraction = accounting.progressFraction)
            _progress.value = _progress.value.copy(
                phaseLabel = if (entriesToUpload.isNotEmpty()) "Trasferimento diretto cifrato in corso..." else "Sincronizzazione completata!",
                sessionStage = TransferSessionStage.TRANSFERRING,
                completedItems = accounting.succeededItemsCount,
                totalItems = accounting.initialTotalItems,
                transferredBytes = accounting.transferredBytes,
                totalBytes = accounting.totalBytesForProgress,
                etaLabel = etaTracker.currentLabel(
                    isCompleted = false,
                    hasTransferableItems = accounting.initialTotalItems > 0
                ),
                mergedContacts = manifestResp.contactsMergedCount,
                contactsAlreadyPresent = manifestResp.contactsSkippedDuplicates,
                importedCalendars = manifestResp.calendarsImportedCount,
                calendarsAlreadyPresent = manifestResp.calendarsAlreadyPresentCount ?: 0,
                importedReminders = manifestResp.remindersImportedCount ?: 0,
                remindersAlreadyPresent = manifestResp.remindersAlreadyPresentCount ?: 0,
                importedSms = manifestResp.smsImportedCount,
                importedCallLogs = manifestResp.callLogsImportedCount ?: 0,
                skippedDuplicates = manifestResp.skippedDuplicateCount,
                gatedPreviewCount = manifestResp.gatedByCrossOsPreviewCount,
                spaceReliefOffer = null
            )

            // 4. Upload streaming parallelo CSGCM1 con pool fisso di 3 worker (evita migliaia di coroutine simultanee)
            //    + riconnessione Wi-Fi automatica fino a 45s in caso di caduta temporanea di rete.
            val reconnectHandshakeReq = handshakeReq.copy(isResume = true)
            val reconnectMutex = Mutex()
            val reconnectGeneration = AtomicLong(0L)
            val abortedError = AtomicReference<Throwable?>(null)

            fun buildNetworkPausedException(): IllegalStateException {
                val snap = _progress.value
                val pctNow = if (snap.totalItems > 0) {
                    ((snap.completedItems * 100.0) / snap.totalItems).toInt().coerceIn(0, 99)
                } else {
                    0
                }
                return IllegalStateException(
                    "Connessione con ${handshakeResp.receiverName} in pausa al $pctNow% (${snap.completedItems}/${snap.totalItems} file già salvati). Mantieni aperto DirectSwitch sull'altro telefono e riprova per riprendere da dove eri rimasto."
                )
            }

            suspend fun ensureReconnected(failedGeneration: Long): Pair<String, OkHttpClient> {
                return reconnectMutex.withLock {
                    abortedError.get()?.let { throw it }
                    if (reconnectGeneration.get() != failedGeneration) {
                        return@withLock baseUrl to activeClient
                    }
                    val recovered = waitForReceiverReconnection(
                        qrPayload = qrPayload,
                        currentChannel = activeChannel,
                        timeoutMillis = 45_000L
                    )
                    if (recovered == null) {
                        val err = buildNetworkPausedException()
                        abortedError.set(err)
                        throw err
                    }
                    if (recovered !== activeChannel && recovered.client !== activeChannel.client) {
                        channelCleanups.add(recovered.cleanup)
                    }
                    activeChannel = recovered
                    activeClient = recovered.client
                    baseUrl = "http://${recovered.reachableIp}:${qrPayload.port}"

                    val hsRes = runCatching {
                        postEncryptedJson(
                            client = activeClient,
                            url = "$baseUrl/v1/handshake",
                            plainJson = DirectSwitchJson.instance.encodeToString(reconnectHandshakeReq),
                            aesKey = sessionAesKey
                        )
                    }
                    val hsErr = hsRes.exceptionOrNull()
                    if (hsErr != null && hsErr.message?.contains("PIN o chiave QR non validi") == true) {
                        val err = IllegalStateException(
                            "La sessione su ${handshakeResp.receiverName} è stata chiusa o riavviata. Ricollega i due telefoni per riprendere i file rimanenti."
                        )
                        abortedError.set(err)
                        throw err
                    }
                    val manRes = runCatching {
                        postEncryptedJson(
                            client = activeClient,
                            url = "$baseUrl/v1/manifest",
                            plainJson = DirectSwitchJson.instance.encodeToString(manifest),
                            aesKey = sessionAesKey
                        )
                    }
                    val manErr = manRes.exceptionOrNull()
                    if (manErr != null && manErr.message?.contains("Spazio di archiviazione esaurito") == true) {
                        abortedError.set(manErr)
                        throw manErr
                    }
                    runCatching {
                        postEncryptedJson(
                            client = activeClient,
                            url = "$baseUrl/v1/begin-transfer",
                            plainJson = """{"sessionId":"${qrPayload.sessionId}"}""",
                            aesKey = sessionAesKey
                        )
                    }
                    reconnectGeneration.incrementAndGet()
                    _progress.value = _progress.value.copy(
                        phaseLabel = "Connessione ripristinata! Ripresa trasferimento..."
                    )
                    baseUrl to activeClient
                }
            }

            val permitSemaphore = Semaphore(3)
            val heavyAcquireLock = Mutex()
            val thermalCheckLock = Mutex()
            val nextIndex = AtomicInteger(0)
            val healedCodecCounter = AtomicInteger(0)
            val convertedMotionCounter = AtomicInteger(0)
            val heicConvertedCounter = AtomicInteger(0)
            val sentSha256ById = ConcurrentHashMap<String, String>()
            val currentThermalState = AtomicReference(ThermalGuardState.NORMAL)
            val thermalCooldownUntilMs = AtomicLong(0L)
            val workerCount = minOf(3, entriesToUpload.size)
            if (workerCount > 0) {
                coroutineScope {
                    repeat(workerCount) {
                        launch(Dispatchers.IO) {
                            while (true) {
                                abortedError.get()?.let { throw it }
                                val idx = nextIndex.getAndIncrement()
                                if (idx >= entriesToUpload.size) break
                                val entry = entriesToUpload[idx]

                                if (idx % 5 == 0 || currentThermalState.get() != ThermalGuardState.NORMAL) {
                                    thermalCheckLock.withLock {
                                        val evaluated = ThermalGuardCore.evaluate(AndroidThermalMonitor.read(context))
                                        currentThermalState.set(evaluated)
                                        when (evaluated) {
                                            ThermalGuardState.CRITICAL_COOLDOWN -> {
                                                val now = System.currentTimeMillis()
                                                if (thermalCooldownUntilMs.get() < now) {
                                                    thermalCooldownUntilMs.set(now + 45_000L)
                                                }
                                                _progress.value = _progress.value.copy(
                                                    thermalGuardState = ThermalGuardState.CRITICAL_COOLDOWN,
                                                    thermalBanner = "Raffreddamento termico in corso (pausa automatica 45s)..."
                                                )
                                            }
                                            ThermalGuardState.WARM_THROTTLE -> {
                                                _progress.value = _progress.value.copy(
                                                    thermalGuardState = ThermalGuardState.WARM_THROTTLE,
                                                    thermalBanner = "Temperatura elevata — 1 flusso alla volta"
                                                )
                                            }
                                            ThermalGuardState.NORMAL -> {
                                                _progress.value = _progress.value.copy(
                                                    thermalGuardState = ThermalGuardState.NORMAL,
                                                    thermalBanner = null
                                                )
                                            }
                                        }
                                    }
                                    while (System.currentTimeMillis() < thermalCooldownUntilMs.get() &&
                                        abortedError.get() == null &&
                                        currentCoroutineContext().isActive
                                    ) {
                                        delay(1000L)
                                    }
                                    val untilSnap = thermalCooldownUntilMs.get()
                                    if (untilSnap > 0L && System.currentTimeMillis() >= untilSnap) {
                                        thermalCheckLock.withLock {
                                            val untilLocked = thermalCooldownUntilMs.get()
                                            if (untilLocked > 0L && System.currentTimeMillis() >= untilLocked) {
                                                thermalCooldownUntilMs.set(0L)
                                                val afterCool = ThermalGuardCore.evaluate(AndroidThermalMonitor.read(context))
                                                currentThermalState.set(afterCool)
                                                _progress.value = _progress.value.copy(
                                                    thermalGuardState = afterCool,
                                                    thermalBanner = when (afterCool) {
                                                        ThermalGuardState.CRITICAL_COOLDOWN -> "Raffreddamento termico in corso (pausa automatica 45s)..."
                                                        ThermalGuardState.WARM_THROTTLE -> "Temperatura elevata — 1 flusso alla volta"
                                                        ThermalGuardState.NORMAL -> null
                                                    }
                                                )
                                            }
                                        }
                                    }
                                }

                                val permitsNeeded = if (currentThermalState.get() == ThermalGuardState.WARM_THROTTLE ||
                                    entry.manifestItem.sizeBytes >= 50L * 1024L * 1024L
                                ) 3 else 1
                                var acquiredPermits = 0
                                val safeTempId = entry.manifestItem.id.replace(Regex("[^a-zA-Z0-9_-]"), "_")
                                val tempEncrypted = File(context.cacheDir, "tx_${safeTempId}.csgcm1")
                                var healedAudioTemp: File? = null
                                var heicConvTemp: File? = null
                                var extractedMotion: AndroidLiveMotionBridge.ExtractedAndroidMotionPhoto? = null
                                var tempLiveEncrypted: File? = null
                                try {
                                    if (permitsNeeded == 3) {
                                        heavyAcquireLock.withLock {
                                            repeat(3) {
                                                permitSemaphore.acquire()
                                                acquiredPermits++
                                            }
                                        }
                                    } else {
                                        permitSemaphore.acquire()
                                        acquiredPermits = 1
                                    }

                                    // 1) Audio Codec Healer: converte .opus/.ogg/.amr in .m4a AAC verso iOS
                                    var actualExtHeader: String? = null
                                    if (entry.manifestItem.category == TransferCategory.AUDIO &&
                                        handshakeResp.receiverPlatform == DevicePlatform.IOS
                                    ) {
                                        healedAudioTemp = AndroidAudioCodecHealer.transcodeAudioToM4aIfNeeded(
                                            context = context,
                                            sourceUri = entry.contentUri,
                                            fileName = entry.manifestItem.fileName,
                                            mimeType = entry.manifestItem.mimeType,
                                            sizeBytes = entry.manifestItem.sizeBytes
                                        )
                                        if (healedAudioTemp != null) {
                                            actualExtHeader = "m4a"
                                            healedCodecCounter.incrementAndGet()
                                        }
                                    }

                                    // 2) Motion Photo (Android) -> Live Photo (iOS): estrae still + clip MP4 e invia /v1/item-live-video/
                                    var sentMotionSplitLiveBytes = 0L
                                    if (entry.manifestItem.category == TransferCategory.PHOTOS &&
                                        handshakeResp.receiverPlatform == DevicePlatform.IOS
                                    ) {
                                        extractedMotion = AndroidLiveMotionBridge.tryExtractAndroidMotionPhoto(
                                            context = context,
                                            sourceUri = entry.contentUri,
                                            fileName = entry.manifestItem.fileName,
                                            sizeBytes = entry.manifestItem.sizeBytes
                                        )
                                        val motion = extractedMotion
                                        if (motion != null) {
                                            val liveEncFile = File(context.cacheDir, "tx_live_${safeTempId}.csgcm1")
                                            tempLiveEncrypted = liveEncFile
                                            val liveEncPair = runCatching {
                                                motion.videoMp4File.inputStream().use { mp4In ->
                                                    liveEncFile.outputStream().use { encOut ->
                                                        DirectSwitchCrypto.encryptStreamCsgcm1(mp4In, encOut, sessionAesKey)
                                                    }
                                                }
                                            }.getOrNull()
                                            if (liveEncPair != null) {
                                                val (livePlainLen, liveSha) = liveEncPair
                                                val liveBody = object : RequestBody() {
                                                    override fun contentType() = "application/octet-stream".toMediaType()
                                                    override fun contentLength(): Long = liveEncFile.length()
                                                    override fun writeTo(sink: BufferedSink) {
                                                        liveEncFile.inputStream().use { fin ->
                                                            val buf = ByteArray(256 * 1024)
                                                            while (true) {
                                                                val r = fin.read(buf)
                                                                if (r <= 0) break
                                                                sink.write(buf, 0, r)
                                                            }
                                                        }
                                                    }
                                                }
                                                val liveReq = Request.Builder()
                                                    .url("$baseUrl/v1/item-live-video/${entry.manifestItem.id}")
                                                    .header("X-DS-Plain-Length", livePlainLen.toString())
                                                    .header("X-DS-Sha256", liveSha)
                                                    .header("X-DS-Live-Ext", "mp4")
                                                    .header("X-DS-Motion-Split", "1")
                                                    .header("Connection", "close")
                                                    .put(liveBody)
                                                    .build()
                                                val liveCode = runCatching {
                                                    activeClient.newCall(liveReq).execute().use { it.code }
                                                }.getOrDefault(-1)
                                                if (liveCode in 200..299) {
                                                    sentMotionSplitLiveBytes = livePlainLen
                                                    convertedMotionCounter.incrementAndGet()
                                                } else {
                                                    // Se il ricevente non supporta /v1/item-live-video, inviamo lo still originale intatto
                                                    extractedMotion = null
                                                }
                                            }
                                        }
                                    }

                                    // 3) Massima compatibilità HEIC -> JPEG preservando data scatto, rotazione e GPS
                                    if (convertHeicToJpeg &&
                                        entry.manifestItem.category == TransferCategory.PHOTOS &&
                                        extractedMotion == null &&
                                        AndroidHeicCompatibilityConverter.isHeicPhoto(entry.manifestItem.fileName, entry.manifestItem.mimeType)
                                    ) {
                                        val tmpJpg = File(context.cacheDir, "heic_compat_${safeTempId}.jpg")
                                        if (AndroidHeicCompatibilityConverter.convertHeicToJpegPreservingExif(context, entry.contentUri, tmpJpg)) {
                                            heicConvTemp = tmpJpg
                                            actualExtHeader = "jpg"
                                            heicConvertedCounter.incrementAndGet()
                                        } else {
                                            runCatching { tmpJpg.delete() }
                                        }
                                    }

                                    val encPair = runCatching {
                                        val primaryFile = healedAudioTemp ?: extractedMotion?.stillFile ?: heicConvTemp
                                        if (primaryFile != null) {
                                            primaryFile.inputStream().use { rawIn ->
                                                tempEncrypted.outputStream().use { encOut ->
                                                    DirectSwitchCrypto.encryptStreamCsgcm1(rawIn, encOut, sessionAesKey)
                                                }
                                            }
                                        } else {
                                            context.contentResolver.openInputStream(entry.contentUri)?.use { rawIn ->
                                                tempEncrypted.outputStream().use { encOut ->
                                                    DirectSwitchCrypto.encryptStreamCsgcm1(rawIn, encOut, sessionAesKey)
                                                }
                                            }
                                        }
                                    }.getOrNull()

                                    if (encPair == null) {
                                        val skipUrl = "$baseUrl/v1/item-skip/${entry.manifestItem.id}"
                                        val skipClient = activeClient
                                        runCatching {
                                            postEncryptedJson(
                                                client = skipClient,
                                                url = skipUrl,
                                                plainJson = """{"sessionId":"${qrPayload.sessionId}"}""",
                                                aesKey = sessionAesKey
                                            )
                                        }
                                        val skipRec = SkippedTransferItemRecord(
                                            id = entry.manifestItem.id,
                                            fileName = entry.manifestItem.fileName,
                                            category = entry.manifestItem.category,
                                            sizeBytes = entry.manifestItem.sizeBytes,
                                            reason = "File non leggibile o rimosso sul dispositivo sorgente"
                                        )
                                        skippedItemsList.add(skipRec)
                                        progressLock.withLock {
                                            accounting.recordFailedOrSkipped(entry.manifestItem.sizeBytes)
                                            checkpointTotalBytes = accounting.totalBytesForProgress
                                            val eta = etaTracker.update(
                                                progressFraction = accounting.progressFraction,
                                                isCompleted = false,
                                                hasTransferableItems = accounting.initialTotalItems > 0
                                            )
                                            val skippedSnapshot = synchronized(skippedItemsList) { skippedItemsList.toList() }
                                            _progress.value = _progress.value.copy(
                                                completedItems = accounting.succeededItemsCount,
                                                transferredBytes = accounting.transferredBytes,
                                                totalBytes = accounting.totalBytesForProgress,
                                                speedMegabytesPerSec = speedMeter.currentMegabytesPerSec(),
                                                etaLabel = eta,
                                                failedItemsCount = accounting.failedItemsCount,
                                                skippedItems = skippedSnapshot,
                                                phaseLabel = "Saltato file non leggibile (${entry.manifestItem.fileName}), proseguo..."
                                            )
                                        }
                                        continue
                                    }

                                    val (plainLen, sha256Hex) = encPair
                                    var uploadedSingleOk = false
                                    var quickAttempt = 0
                                    var itemRetryCount = 0
                                    var didTryFullReconnect = false

                                    while (true) {
                                        abortedError.get()?.let { throw it }
                                        val genBeforeAttempt = reconnectGeneration.get()
                                        val reqBaseUrl = baseUrl
                                        val reqClient = activeClient

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
                                            .url("$reqBaseUrl/v1/item/${entry.manifestItem.id}")
                                            .header("X-DS-Plain-Length", plainLen.toString())
                                            .header("X-DS-Sha256", sha256Hex)
                                            .apply {
                                                if (!actualExtHeader.isNullOrBlank()) {
                                                    header("X-DS-Actual-Ext", actualExtHeader)
                                                }
                                            }
                                            .header("Connection", "close")
                                            .put(body)
                                            .build()

                                        val code = runCatching {
                                            reqClient.newCall(putReq).execute().use { resp -> resp.code }
                                        }.getOrDefault(-1)

                                        if (code in 200..299) {
                                            uploadedSingleOk = true
                                            break
                                        }
                                        if (code == 403) {
                                            val err = IllegalStateException(
                                                "Permesso Foto/Libreria negato sul telefono ricevente (${handshakeResp.receiverName}). Abilitalo nelle Impostazioni del ricevente."
                                            )
                                            abortedError.set(err)
                                            throw err
                                        }
                                        if (code == 507) {
                                            val err = IllegalStateException(
                                                "Spazio di archiviazione esaurito su ${handshakeResp.receiverName}. Libera spazio e riprova per riprendere dai file rimanenti."
                                            )
                                            abortedError.set(err)
                                            throw err
                                        }

                                        val isTransportOrSessionFailure = code == -1 || code == 401 || code == 408 || code == 502 || code == 503 || code == 504
                                        if (isTransportOrSessionFailure) {
                                            if (quickAttempt < 2 && code != 401) {
                                                val backoffMs = if (quickAttempt == 0) 400L else 1_000L
                                                quickAttempt++
                                                delay(backoffMs)
                                                continue
                                            }
                                            if (!didTryFullReconnect) {
                                                didTryFullReconnect = true
                                                ensureReconnected(genBeforeAttempt)
                                                quickAttempt = 0
                                                continue
                                            }
                                            val err = buildNetworkPausedException()
                                            abortedError.set(err)
                                            throw err
                                        }

                                        // Errore applicativo sul singolo file (404 / 422 / 500): 1 retry rapido poi salta solo questo file
                                        if (itemRetryCount < 1) {
                                            itemRetryCount++
                                            delay(300L)
                                            continue
                                        }
                                        break
                                    }

                                    if (!uploadedSingleOk) {
                                        DirectSwitchLog.warn("Impossibile inviare ${entry.manifestItem.fileName}, passo al successivo")
                                        val skipUrl = "$baseUrl/v1/item-skip/${entry.manifestItem.id}"
                                        val skipClient = activeClient
                                        runCatching {
                                            postEncryptedJson(
                                                client = skipClient,
                                                url = skipUrl,
                                                plainJson = """{"sessionId":"${qrPayload.sessionId}"}""",
                                                aesKey = sessionAesKey
                                            )
                                        }
                                        val skipRec = SkippedTransferItemRecord(
                                            id = entry.manifestItem.id,
                                            fileName = entry.manifestItem.fileName,
                                            category = entry.manifestItem.category,
                                            sizeBytes = entry.manifestItem.sizeBytes,
                                            reason = "Errore salvataggio sul telefono ricevente"
                                        )
                                        skippedItemsList.add(skipRec)
                                        progressLock.withLock {
                                            accounting.recordFailedOrSkipped(entry.manifestItem.sizeBytes)
                                            checkpointTotalBytes = accounting.totalBytesForProgress
                                            val eta = etaTracker.update(
                                                progressFraction = accounting.progressFraction,
                                                isCompleted = false,
                                                hasTransferableItems = accounting.initialTotalItems > 0
                                            )
                                            val skippedSnapshot = synchronized(skippedItemsList) { skippedItemsList.toList() }
                                            _progress.value = _progress.value.copy(
                                                completedItems = accounting.succeededItemsCount,
                                                transferredBytes = accounting.transferredBytes,
                                                totalBytes = accounting.totalBytesForProgress,
                                                speedMegabytesPerSec = speedMeter.currentMegabytesPerSec(),
                                                etaLabel = eta,
                                                failedItemsCount = accounting.failedItemsCount,
                                                skippedItems = skippedSnapshot,
                                                phaseLabel = "Saltato ${entry.manifestItem.fileName}, proseguo col resto..."
                                            )
                                        }
                                        continue
                                    }

                                    completedItemIdsSet.add(entry.manifestItem.id)
                                    sentSha256ById[entry.manifestItem.id] = sha256Hex
                                    var shouldSaveCheckpoint = false
                                    progressLock.withLock {
                                        val effectiveSentBytes = plainLen + sentMotionSplitLiveBytes
                                        accounting.recordPrimaryItemUploaded(entry.manifestItem.sizeBytes, effectiveSentBytes)
                                        checkpointUploadedBytes = accounting.transferredBytes
                                        checkpointTotalBytes = accounting.totalBytesForProgress
                                        val speedMbs = speedMeter.record(effectiveSentBytes)
                                        val frac = accounting.progressFraction
                                        val eta = etaTracker.update(
                                            progressFraction = frac,
                                            isCompleted = false,
                                            hasTransferableItems = accounting.initialTotalItems > 0
                                        )
                                        val pctNow = TransferDisplayFormatting.percentageInt(frac.toDouble(), false)
                                        _progress.value = _progress.value.copy(
                                            currentFileName = entry.manifestItem.fileName,
                                            completedItems = accounting.succeededItemsCount,
                                            transferredBytes = accounting.transferredBytes,
                                            totalBytes = accounting.totalBytesForProgress,
                                            speedMegabytesPerSec = speedMbs,
                                            etaLabel = eta,
                                            failedItemsCount = accounting.failedItemsCount
                                        )
                                        DirectSwitchKeepAliveService.updateProgress(
                                            context = context,
                                            percent = pctNow,
                                            statusText = "Invio: ${TransferDisplayFormatting.formatBytes(accounting.transferredBytes)} / ${TransferDisplayFormatting.formatBytes(accounting.totalBytesForProgress)}",
                                            etaSubText = eta
                                        )
                                        shouldSaveCheckpoint = accounting.succeededItemsCount % 15 == 0
                                    }
                                    if (shouldSaveCheckpoint) {
                                        saveDiskCheckpoint()
                                    }
                                } finally {
                                    tempEncrypted.delete()
                                    tempLiveEncrypted?.delete()
                                    healedAudioTemp?.delete()
                                    heicConvTemp?.delete()
                                    extractedMotion?.stillFile?.delete()
                                    extractedMotion?.videoMp4File?.delete()
                                    repeat(acquiredPermits) { permitSemaphore.release() }
                                }
                            }
                        }
                    }
                }
            }
            val failedCount = accounting.failedItemsCount

            // 5. Verifica integrità post-migrazione (Diff manifest + SHA-256) PRIMA di /v1/complete
            //    così il ricevente è ancora in sessione attiva (keep-alive acceso e schermo non chiuso).
            var reconcileVerifiedCount = 0
            var reconcileMissingIds: List<String> = emptyList()
            if (handshakeResp.supportsReconcile && sentSha256ById.isNotEmpty()) {
                val sentHashesSnapshot = sentSha256ById.toMap()
                val reconcileReq = ReconcileManifestRequest(
                    sessionId = qrPayload.sessionId,
                    sentItemIds = sentHashesSnapshot.keys.toList(),
                    expectedSha256ById = sentHashesSnapshot
                )
                val reconcilePayloadJson = DirectSwitchJson.instance.encodeToString(reconcileReq)
                val reconcileResp = runCatching {
                    val recJson = try {
                        postEncryptedJson(
                            client = activeClient,
                            url = "$baseUrl/v1/reconcile-manifest",
                            plainJson = reconcilePayloadJson,
                            aesKey = sessionAesKey
                        )
                    } catch (_: Throwable) {
                        val (recoveredUrl, recoveredClient) = ensureReconnected(reconnectGeneration.get())
                        postEncryptedJson(
                            client = recoveredClient,
                            url = "$recoveredUrl/v1/reconcile-manifest",
                            plainJson = reconcilePayloadJson,
                            aesKey = sessionAesKey
                        )
                    }
                    DirectSwitchJson.instance.decodeFromString<ReconcileManifestResponse>(recJson)
                }.getOrNull()
                if (reconcileResp != null) {
                    reconcileVerifiedCount = reconcileResp.totalVerified
                    reconcileMissingIds = (reconcileResp.missingIds + reconcileResp.hashMismatchIds).distinct()
                }
            }

            // 6. Chiusura sessione cifrata e Report certificato (con 1 fallback di riconnessione se la rete cade all'ultimo)
            val completeJson = try {
                postEncryptedJson(
                    client = activeClient,
                    url = "$baseUrl/v1/complete",
                    plainJson = """{"sessionId":"${qrPayload.sessionId}"}""",
                    aesKey = sessionAesKey
                )
            } catch (_: Throwable) {
                val (recoveredUrl, recoveredClient) = ensureReconnected(reconnectGeneration.get())
                postEncryptedJson(
                    client = recoveredClient,
                    url = "$recoveredUrl/v1/complete",
                    plainJson = """{"sessionId":"${qrPayload.sessionId}"}""",
                    aesKey = sessionAesKey
                )
            }
            val report = DirectSwitchJson.instance.decodeFromString<TransferCompletionReport>(completeJson)

            if (failedCount == 0 && !isTargetedRetry) {
                TransferCheckpointStore.clear(context)
            } else if (failedCount > 0) {
                saveDiskCheckpoint()
            }

            // Salva impronta di migrazione completata (valida 30 giorni) per la modalità "Recupero Delta 14-30gg"
            if (!isTargetedRetry) {
                val previousKeys = deltaBaseline?.transferredDedupKeys.orEmpty()
                val newKeys = mediaEntries.filter { it.manifestItem.id in completedItemIdsSet }
                    .map { it.manifestItem.dedupKey }
                CompletedMigrationStore.save(
                    file = CompletedMigrationStore.defaultFile(context.filesDir),
                    record = CompletedMigrationRecord(
                        sessionId = qrPayload.sessionId,
                        peerName = handshakeResp.receiverName,
                        peerPlatform = handshakeResp.receiverPlatform,
                        completedAtEpochMillis = System.currentTimeMillis(),
                        transferredFilesCount = report.transferredFilesCount,
                        transferredBytes = report.transferredBytes,
                        transferredDedupKeys = (previousKeys + newKeys).distinct(),
                        lastScope = senderScope
                    )
                )
            }

            val doneLabel = if (failedCount > 0) {
                "Trasferimento completato ($failedCount file non disponibili saltati)"
            } else {
                "Trasferimento completato!"
            }
            val finalSkipped = synchronized(skippedItemsList) { skippedItemsList.toList() }
            _progress.value = _progress.value.copy(
                phaseLabel = doneLabel,
                etaLabel = null,
                sessionStage = TransferSessionStage.COMPLETED,
                isCompleted = true,
                failedItemsCount = failedCount,
                skippedItems = finalSkipped,
                healedCodecCount = healedCodecCounter.get(),
                convertedLiveMotionCount = convertedMotionCounter.get(),
                heicConvertedCount = heicConvertedCounter.get(),
                thermalGuardState = ThermalGuardState.NORMAL,
                thermalBanner = null,
                smartCleanMergedContactsCount = smartCleanMergedContactsCount,
                smartCleanSkippedDuplicatesCount = smartCleanMedia.skippedDuplicatesCount,
                smartCleanSkippedScreenshotsCount = smartCleanMedia.skippedOldScreenshotsCount,
                reconciliationMissingIds = reconcileMissingIds,
                reconciliationVerifiedCount = reconcileVerifiedCount,
                pendingNativeWhatsAppMigration = wantNativeWa
            )
            DirectSwitchKeepAliveService.updateProgress(
                context = context,
                percent = 100,
                statusText = doneLabel,
                etaSubText = null,
                force = true
            )
            Result.success(report)
        } catch (t: Throwable) {
            saveDiskCheckpoint()
            prepAnimDeferred?.complete(Unit)
            _progress.value = _progress.value.copy(
                sessionStage = TransferSessionStage.TRANSFERRING,
                errorMessage = t.localizedMessage ?: "Errore durante il trasferimento"
            )
            Result.failure(t)
        } finally {
            for (pwdFile in stagedPasswordCsvFiles) {
                SecureTempFileShredder.shredAndDelete(pwdFile)
            }
            synchronized(channelCleanups) {
                for (cleanup in channelCleanups) {
                    runCatching { cleanup() }
                }
                channelCleanups.clear()
            }
            DirectSwitchKeepAliveService.stop(context)
        }
    }

    private suspend fun waitForReceiverReconnection(
        qrPayload: QrPairingPayload,
        currentChannel: BoundHttpChannel,
        timeoutMillis: Long = 45_000L
    ): BoundHttpChannel? {
        val prioritizedIps = (listOf(currentChannel.reachableIp) + qrPayload.ips).distinct()
        val startMs = System.currentTimeMillis()
        val deadlineMs = startMs + timeoutMillis
        var lastHotspotRetryMs = 0L

        while (System.currentTimeMillis() < deadlineMs) {
            val remainingSec = (((deadlineMs - System.currentTimeMillis()) + 999L) / 1000L).coerceAtLeast(1L)
            _progress.value = _progress.value.copy(
                phaseLabel = "Connessione interrotta — riconnessione automatica con ${qrPayload.receiverName} (${remainingSec}s)..."
            )

            // 1. Prova prima sullo stesso socket/interfaccia già agganciata
            findReachableIp(currentChannel.client, prioritizedIps, qrPayload.port)?.let { hit ->
                return currentChannel.copy(reachableIp = hit)
            }

            // 2. Prova su tutte le interfacce Wi-Fi attive
            for (wifiNet in findActiveWifiNetworks()) {
                val wifiClient = clientBoundTo(wifiNet)
                val hit = findReachableIp(wifiClient, prioritizedIps, qrPayload.port)
                if (hit != null) {
                    return BoundHttpChannel(reachableIp = hit, client = wifiClient)
                }
            }

            // 3. Fallback sul routing predefinito
            findReachableIp(baseHttpClient, prioritizedIps, qrPayload.port)?.let { hit ->
                return BoundHttpChannel(reachableIp = hit, client = baseHttpClient)
            }

            // 4. Se stiamo usando l'Hotspot 5GHz Offline, riprova l'aggancio ogni ~15s
            val nowMs = System.currentTimeMillis()
            if (!qrPayload.wifiSsid.isNullOrBlank() &&
                !qrPayload.wifiPass.isNullOrBlank() &&
                Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q &&
                nowMs - startMs >= 6_000L &&
                nowMs - lastHotspotRetryMs >= 15_000L
            ) {
                lastHotspotRetryMs = nowMs
                val hotspotPair = requestPeerHotspotNetworkApi29(qrPayload.wifiSsid, qrPayload.wifiPass)
                if (hotspotPair != null) {
                    val (hotspotNet, releaseFn) = hotspotPair
                    val hotspotClient = clientBoundTo(hotspotNet)
                    val hit = findReachableIp(hotspotClient, prioritizedIps, qrPayload.port)
                    if (hit != null) {
                        return BoundHttpChannel(reachableIp = hit, client = hotspotClient, cleanup = releaseFn)
                    }
                    releaseFn()
                }
            }

            delay(1_200L)
        }
        return null
    }

    private fun clientBoundTo(network: Network?): OkHttpClient =
        if (network != null) {
            baseHttpClient.newBuilder().socketFactory(network.socketFactory).build()
        } else {
            baseHttpClient
        }

    private fun findActiveWiredNetworks(): List<Network> {
        val cm = context.applicationContext.getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager
            ?: return emptyList()
        return runCatching {
            cm.allNetworks.filter { net ->
                val caps = cm.getNetworkCapabilities(net) ?: return@filter false
                caps.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET) ||
                    (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && caps.hasTransport(NetworkCapabilities.TRANSPORT_USB))
            }
        }.getOrDefault(emptyList())
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
        // 0. Priorità massima al Cavo USB-C / Ethernet / Tethering cablato (fino a 5 Gbps)
        for (wiredNet in findActiveWiredNetworks()) {
            val wiredClient = clientBoundTo(wiredNet)
            val hit = findReachableIp(wiredClient, candidateIps, port)
            if (hit != null) {
                return BoundHttpChannel(
                    reachableIp = hit,
                    client = wiredClient,
                    medium = TransferConnectionMedium.USB_CABLE
                )
            }
        }

        // 1. Prova su tutte le reti TRANSPORT_WIFI attive (anche prive di internet)
        for (wifiNet in findActiveWifiNetworks()) {
            val wifiClient = clientBoundTo(wifiNet)
            val hit = findReachableIp(wifiClient, candidateIps, port)
            if (hit != null) {
                return BoundHttpChannel(
                    reachableIp = hit,
                    client = wifiClient,
                    medium = LocalNetworkAddresses.detectConnectionMedium(hit, isHotspotOrP2p = false)
                )
            }
        }

        // 2. Fallback sul routing predefinito di sistema (es. tethering inverso / Ethernet USB)
        findReachableIp(baseHttpClient, candidateIps, port)?.let { hit ->
            return BoundHttpChannel(
                reachableIp = hit,
                client = baseHttpClient,
                medium = LocalNetworkAddresses.detectConnectionMedium(hit, isHotspotOrP2p = false)
            )
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
                    return BoundHttpChannel(
                        reachableIp = hit,
                        client = hotspotClient,
                        medium = TransferConnectionMedium.PEER_TO_PEER_WIFI,
                        cleanup = releaseFn
                    )
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
                val hint = when (resp.code) {
                    401 -> "PIN o chiave QR non validi"
                    429 -> "Troppi tentativi PIN errati: inquadra il QR Code"
                    507 -> "Spazio di archiviazione esaurito sul telefono ricevente"
                    else -> "HTTP ${resp.code}"
                }
                throw IllegalStateException("Richiesta rifiutata ($hint)")
            }
            val respBytes = resp.body?.bytes() ?: ByteArray(0)
            return DirectSwitchCrypto.openJsonEnvelope(respBytes, aesKey)
        }
    }
}
