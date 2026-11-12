//
//  DirectSwitchTransportEngine.swift
//  DirectSwitch-iOS
//
//  Created by Nicolas Donati.
//  Copyright © 2026 Nicolas Donati. Tutti i diritti riservati.
//

import Foundation
import Darwin
import Network
import NetworkExtension
import CryptoKit
import Photos
import UIKit

/// Stato mutabile per una singola connessione HTTP in ingresso sul ricevente iOS:
/// evita copie ricorsive O(N^2) in memoria e scrive gli upload `PUT /v1/item/...` direttamente su disco.
private final class IncomingHttpStreamState: @unchecked Sendable {
    private let fileLock = NSLock()
    var headerBuffer = Data()
    var headersParsed = false
    var method = ""
    var rawTarget = ""
    var path = ""
    var headers: [String: String] = [:]
    var expectedBodyLength: Int64 = 0
    var receivedBodyBytes: Int64 = 0
    var inMemoryBody = Data()
    var tempBodyFileURL: URL? = nil
    var tempBodyFileHandle: FileHandle? = nil

    func closeHandle() {
        fileLock.lock()
        defer { fileLock.unlock() }
        try? tempBodyFileHandle?.close()
        tempBodyFileHandle = nil
    }

    func takeBodyFileOwnership() -> URL? {
        fileLock.lock()
        defer { fileLock.unlock() }
        try? tempBodyFileHandle?.close()
        tempBodyFileHandle = nil
        let owned = tempBodyFileURL
        tempBodyFileURL = nil
        return owned
    }

    func cleanupTempFile() {
        fileLock.lock()
        try? tempBodyFileHandle?.close()
        tempBodyFileHandle = nil
        let urlToDelete = tempBodyFileURL
        tempBodyFileURL = nil
        fileLock.unlock()
        if let url = urlToDelete {
            try? FileManager.default.removeItem(at: url)
        }
    }
}

@MainActor
final class DirectSwitchTransportViewModel: ObservableObject {
    private nonisolated static let maxPinAttempts = 3
    private nonisolated static let maxHeaderBytes = 32 * 1024
    private nonisolated static let maxControlBodyBytes: Int64 = 32 * 1024 * 1024
    private nonisolated static let maxStreamItemBytes: Int64 = 32 * 1024 * 1024 * 1024

    @Published var statusLabel: String = "Pronto al trasferimento diretto"
    @Published var peerName: String = ""
    @Published var peerPlatform: DevicePlatform? = nil
    @Published var licenseTier: SessionLicenseTier? = nil
    @Published var completedItems: Int = 0
    @Published var totalItems: Int = 0
    @Published var transferredBytesCount: Int64 = 0
    @Published var totalBytesCount: Int64 = 0
    @Published var speedMegabytesPerSec: Double = 0.0
    @Published var mergedContacts: Int = 0
    @Published var importedCalendars: Int = 0
    @Published var importedReminders: Int = 0
    @Published var importedSms: Int = 0
    @Published var savedLivePhotos: Int = 0
    @Published var iCloudOptimizedSkippedHint: Int = 0
    @Published var receivedPasswordsCsvCount: Int = 0
    @Published var skippedDuplicates: Int = 0
    @Published var gatedPreviewCount: Int = 0
    @Published var isSessionConnected: Bool = false
    @Published var isTransferring: Bool = false
    @Published var isBackgroundKeepAliveActive: Bool = false
    @Published var canResumeInterruptedTransfer: Bool = false
    @Published var currentItemName: String = ""
    @Published var isCompleted: Bool = false
    @Published var pendingNativeWhatsAppMigration: Bool = false
    @Published var isLocalNetworkDenied: Bool = false
    @Published var needsLocalNetworkRedirect: Bool = false
    @Published var failedItemsCount: Int = 0
    @Published var contactsAlreadyPresentCount: Int = 0
    @Published var receivedInstalledApps: [InstalledAppRecord] = []
    @Published var sentInstalledAppsCount: Int = 0
    @Published var activeTransferScope: ActiveTransferScope = ActiveTransferScope()
    @Published var visualStepProgress: Double = 0.0
    @Published var errorMessage: String? = nil
    @Published var activePairingPin: String = ""
    @Published var discoveredBeacons: [DiscoveryBeaconPayload] = []
    @Published var bootstrapPortalUrl: String? = nil

    private var listener: NWListener?
    private var activeRunIsResume: Bool = false
    private var activeReceiverPort: UInt16 = 49443
    private var activeReceiverAdvertiseBonjour: Bool = true
    private var udpDiscoveryListener: NWListener?
    private var bonjourBrowser: NWBrowser?
    private var beaconBroadcastTask: Task<Void, Never>?
    private var beaconPruneTask: Task<Void, Never>?
    private var beaconLastSeen: [String: Date] = [:]
    private var activeSessionId: String = ""
    private var activeQrPayloadSnapshot: QrPairingPayload?
    private var bootstrapSecretToken: String? = nil
    private var symmetricKey: SymmetricKey?
    private var handshakeAuthenticated: Bool = false
    private var pinPairingConsumed: Bool = false
    private var pinFailedAttempts: Int = 0
    private var requestedWhatsAppMigration: Bool = false
    private var manifestItems: [String: ManifestItem] = [:]
    private var completedItemIds: Set<String> = []
    private var pendingLiveVideoTempURLs: [String: URL] = [:]
    private var senderUploadedIdsBySession: [String: Set<String>] = [:]
    private var senderUploadedBytesBySession: [String: Int64] = [:]
    private var transferredBytes: Int64 = 0
    private var transferStartDate: Date = Date()

    /// Innalza il limite soft dei file descriptor aperti da 256 (default iOS) fino a 4096 per evitare errori `EMFILE`
    /// e blocchi socket oltre i 4.000+ file trasferiti consecutivamente.
    private nonisolated static func raiseOpenFileDescriptorLimitIfNeeded() {
        var rl = rlimit()
        guard getrlimit(RLIMIT_NOFILE, &rl) == 0 else { return }
        let desired: rlim_t = 4096
        let target = min(rl.rlim_max, desired)
        if rl.rlim_cur < target {
            rl.rlim_cur = target
            _ = setrlimit(RLIMIT_NOFILE, &rl)
        }
    }

    private func cleanupPendingLiveVideos() {
        for (_, url) in pendingLiveVideoTempURLs {
            try? FileManager.default.removeItem(at: url)
        }
        pendingLiveVideoTempURLs.removeAll()
    }

    /// Aggancia automaticamente l'iPhone all'Hotspot 5GHz generato da Android nel QR Code.
    /// Se installato con Apple ID gratuito (`Free-Install.ipa`, privo della capability a pagamento `HotspotConfiguration`),
    /// copia automaticamente la password Wi-Fi negli appunti e restituisce un promemoria guidato qualora l'IP non sia già raggiungibile.
    @discardableResult
    func joinAndroidHotspotIfPresent(payload: QrPairingPayload) async -> String? {
        guard let ssid = payload.wifiSsid, !ssid.isEmpty,
              let pass = payload.wifiPass, !pass.isEmpty else {
            return nil
        }
        statusLabel = "Connessione all'Hotspot 5GHz \(ssid)..."
        let config = NEHotspotConfiguration(ssid: ssid, passphrase: pass, isWEP: false)
        config.joinOnce = true
        let applyError: Error? = await withCheckedContinuation { (cont: CheckedContinuation<Error?, Never>) in
            NEHotspotConfigurationManager.shared.apply(config) { err in
                cont.resume(returning: err)
            }
        }
        if applyError != nil {
            UIPasteboard.general.string = pass
            return "Collega questo iPhone al Wi-Fi '\(ssid)' in Impostazioni → Wi-Fi (password '\(pass)' già copiata negli appunti!) e premi di nuovo Avvia."
        }
        try? await Task.sleep(nanoseconds: 800_000_000)
        return nil
    }

    func startReceiverServer(port: UInt16 = 49443) -> QrPairingPayload {
        stopReceiverServer()
        UIApplication.shared.isIdleTimerDisabled = true
        let sessionId = "ds_\(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(16).lowercased())"
        let keyHex = DirectSwitchCrypto.generateSessionKeyHex()
        let pin = DirectSwitchCrypto.generatePairingPin()

        bootstrapSecretToken = nil
        bootstrapPortalUrl = nil
        activeSessionId = sessionId
        activePairingPin = pin
        pinPairingConsumed = false
        pinFailedAttempts = 0
        symmetricKey = try? DirectSwitchCrypto.deriveSessionSymmetricKey(sessionKeyHex: keyHex)
        handshakeAuthenticated = false
        manifestItems.removeAll()
        completedItemIds.removeAll()
        cleanupPendingLiveVideos()
        peerName = ""
        peerPlatform = nil
        licenseTier = nil
        completedItems = 0
        totalItems = 0
        transferredBytesCount = 0
        totalBytesCount = 0
        speedMegabytesPerSec = 0.0
        mergedContacts = 0
        importedCalendars = 0
        importedReminders = 0
        importedSms = 0
        savedLivePhotos = 0
        iCloudOptimizedSkippedHint = 0
        receivedPasswordsCsvCount = 0
        skippedDuplicates = 0
        gatedPreviewCount = 0
        transferredBytes = 0
        isSessionConnected = false
        isTransferring = false
        isBackgroundKeepAliveActive = true
        canResumeInterruptedTransfer = false
        currentItemName = ""
        isCompleted = false
        pendingNativeWhatsAppMigration = false
        requestedWhatsAppMigration = false
        needsLocalNetworkRedirect = false
        failedItemsCount = 0
        contactsAlreadyPresentCount = 0
        receivedInstalledApps = []
        sentInstalledAppsCount = 0
        activeTransferScope = ActiveTransferScope()
        visualStepProgress = 0.0
        activeRunIsResume = false
        errorMessage = nil

        Self.raiseOpenFileDescriptorLimitIfNeeded()
        activeReceiverPort = port
        activeReceiverAdvertiseBonjour = true
        iOSBackgroundTransferKeepAlive.shared.onReturnToForegroundWhileActive = { [weak self] in
            self?.reviveReceiverListenerIfNeeded()
        }
        iOSBackgroundTransferKeepAlive.shared.beginActiveSession(roleLabel: "Ricezione dati su questo iPhone")
        startHttpListener(port: port, advertiseBonjour: true)

        let ips = Self.localIPv4Addresses()
        let effectiveIps = ips.isEmpty ? ["192.168.1.2"] : ips
        statusLabel = "In ascolto — Inquadra il QR o inserisci il PIN \(pin)"

        let payload = QrPairingPayload(
            sessionId: sessionId,
            receiverName: UIDevice.current.name,
            receiverPlatform: .IOS,
            ips: effectiveIps,
            port: Int(port),
            sessionKeyHex: keyHex,
            receiverHasPro: iOSLicenseStore.isLocalProUnlocked || iOSLicenseStore.hasVerifiedCloudSaveProEntitlement
        )
        activeQrPayloadSnapshot = payload

        // Trasmette il beacon pubblico (privo di chiavi segrete) via UDP 49444 per l'Auto-Discovery da Android o iPhone
        let beaconData = Data(payload.toPublicBeacon().toCompactJson().utf8)
        beaconBroadcastTask = Task.detached(priority: .utility) {
            while !Task.isCancelled {
                Self.sendUdpBroadcastPacket(beaconData, localIps: effectiveIps, port: 49444)
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }

        return payload
    }

    /// Avvia il Portale Web di Bootstrap rapido protetto da token casuale a 128 bit per esportare la Rubrica (`.vcf`)
    /// su qualsiasi telefono (Android o iPhone) tramite semplice browser Wi-Fi locale.
    func startBootstrapPortalSession(port: UInt16 = 49443) async -> String? {
        stopReceiverServer()
        _ = await iOSContactsSmartMerger.requestAccessIfNeeded()
        UIApplication.shared.isIdleTimerDisabled = true

        let token = DirectSwitchCrypto.randomTokenHex(byteCount: 16)
        bootstrapSecretToken = token
        activeSessionId = ""
        activePairingPin = ""
        activeQrPayloadSnapshot = nil
        handshakeAuthenticated = false
        errorMessage = nil

        startHttpListener(port: port, advertiseBonjour: false)
        let ip = Self.localIPv4Addresses().first ?? "192.168.1.2"
        let url = "http://\(ip):\(port)/start?token=\(token)"
        bootstrapPortalUrl = url
        statusLabel = "Portale Rubrica Wi-Fi attivo su \(ip):\(port)"
        return url
    }

    private func reviveReceiverListenerIfNeeded() {
        guard !activeSessionId.isEmpty else { return }
        if listener == nil {
            startHttpListener(port: activeReceiverPort, advertiseBonjour: activeReceiverAdvertiseBonjour)
            return
        }
        if let state = listener?.state {
            switch state {
            case .failed, .cancelled:
                listener?.cancel()
                listener = nil
                startHttpListener(port: activeReceiverPort, advertiseBonjour: activeReceiverAdvertiseBonjour)
            default:
                break
            }
        }
    }

    private func startHttpListener(port: UInt16, advertiseBonjour: Bool) {
        activeReceiverPort = port
        activeReceiverAdvertiseBonjour = advertiseBonjour

        let tcpOptions = NWProtocolTCP.Options()
        tcpOptions.noDelay = true
        tcpOptions.enableKeepalive = true
        tcpOptions.keepaliveIdle = 15
        let tcpParams = NWParameters(tls: nil, tcp: tcpOptions)
        tcpParams.allowLocalEndpointReuse = true

        guard let nwPort = Network.NWEndpoint.Port(rawValue: port),
              let nwListener = try? NWListener(using: tcpParams, on: nwPort) else {
            errorMessage = "Impossibile aprire la porta locale \(port)."
            return
        }
        if advertiseBonjour {
            nwListener.service = NWListener.Service(name: UIDevice.current.name, type: "_directswitch._tcp")
        }
        nwListener.stateUpdateHandler = { [weak self] newState in
            switch newState {
            case .ready:
                Task { @MainActor [weak self] in
                    self?.isLocalNetworkDenied = false
                }
            case .waiting(let err):
                if Self.isLocalNetworkPolicyDenied(err) {
                    Task { @MainActor [weak self] in
                        self?.isLocalNetworkDenied = true
                        self?.needsLocalNetworkRedirect = true
                    }
                }
            case .failed(let err):
                if Self.isLocalNetworkPolicyDenied(err) {
                    Task { @MainActor [weak self] in
                        self?.isLocalNetworkDenied = true
                        self?.needsLocalNetworkRedirect = true
                    }
                } else {
                    // Self-healing automatico se iOS chiude il socket in seguito a standby/cambio AP durante maxi-trasferimenti
                    Task { @MainActor [weak self] in
                        guard let self, !self.activeSessionId.isEmpty, !self.isCompleted else { return }
                        self.listener?.cancel()
                        self.listener = nil
                        try? await Task.sleep(nanoseconds: 400_000_000)
                        guard !self.activeSessionId.isEmpty, !self.isCompleted else { return }
                        self.startHttpListener(port: self.activeReceiverPort, advertiseBonjour: self.activeReceiverAdvertiseBonjour)
                    }
                }
            default:
                break
            }
        }
        nwListener.newConnectionHandler = { [weak self] conn in
            guard let self else {
                conn.cancel()
                return
            }
            if !Self.isAllowedPeerEndpoint(conn.endpoint) {
                conn.cancel()
                return
            }
            let streamState = IncomingHttpStreamState()
            conn.stateUpdateHandler = { connState in
                switch connState {
                case .failed, .cancelled:
                    streamState.cleanupTempFile()
                default:
                    break
                }
            }
            conn.start(queue: .global(qos: .userInitiated))
            self.receiveHttpStream(on: conn, state: streamState)
        }
        nwListener.start(queue: .global(qos: .userInitiated))
        listener = nwListener
    }

    func stopReceiverServer() {
        UIApplication.shared.isIdleTimerDisabled = false
        cleanupPendingLiveVideos()
        activeSessionId = ""
        beaconBroadcastTask?.cancel()
        beaconBroadcastTask = nil
        listener?.cancel()
        listener = nil
        activePairingPin = ""
        activeQrPayloadSnapshot = nil
        bootstrapSecretToken = nil
        bootstrapPortalUrl = nil
        handshakeAuthenticated = false
        if !isTransferring {
            isBackgroundKeepAliveActive = false
            iOSBackgroundTransferKeepAlive.shared.endActiveSession(completed: isCompleted)
        }
    }

    func resetSession() {
        stopReceiverServer()
        stopUdpAutoDiscovery()
        cleanupPendingLiveVideos()
        senderUploadedIdsBySession.removeAll()
        senderUploadedBytesBySession.removeAll()
        peerName = ""
        peerPlatform = nil
        licenseTier = nil
        completedItems = 0
        totalItems = 0
        transferredBytesCount = 0
        totalBytesCount = 0
        speedMegabytesPerSec = 0.0
        mergedContacts = 0
        importedCalendars = 0
        importedReminders = 0
        importedSms = 0
        savedLivePhotos = 0
        iCloudOptimizedSkippedHint = 0
        receivedPasswordsCsvCount = 0
        skippedDuplicates = 0
        gatedPreviewCount = 0
        transferredBytes = 0
        isSessionConnected = false
        isTransferring = false
        isBackgroundKeepAliveActive = false
        canResumeInterruptedTransfer = false
        currentItemName = ""
        isCompleted = false
        pendingNativeWhatsAppMigration = false
        requestedWhatsAppMigration = false
        needsLocalNetworkRedirect = false
        failedItemsCount = 0
        contactsAlreadyPresentCount = 0
        receivedInstalledApps = []
        sentInstalledAppsCount = 0
        activeTransferScope = ActiveTransferScope()
        visualStepProgress = 0.0
        activeRunIsResume = false
        errorMessage = nil
        statusLabel = "Pronto al trasferimento diretto"
        iOSBackgroundTransferKeepAlive.shared.endActiveSession(completed: false)
    }

    /// Apre direttamente la schermata di DirectSwitch nelle Impostazioni iOS (dove attivare lo switch «Rete locale»).
    @MainActor
    static func openAppSettings() {
        iOSPermissionsHelper.openDirectSwitchSettings()
    }

    private nonisolated static func isLocalNetworkPolicyDenied(_ error: NWError) -> Bool {
        if case .dns(let code) = error, Int(code) == -65570 {
            return true
        }
        return false
    }

    /// Apre esclusivamente WhatsApp Personale (Messenger) senza mai attivare per errore WhatsApp Business:
    /// usa lo schema dedicato `whatsapp-consumer://` (o Universal Link `wa.me`), altrimenti apre la scheda ufficiale App Store (`id310633997`).
    @MainActor
    static func openPersonalWhatsAppOrStore() {
        let consumerSchemes = ["whatsapp-consumer://app", "whatsapp-consumer://"]
        for scheme in consumerSchemes {
            if let url = URL(string: scheme), UIApplication.shared.canOpenURL(url) {
                UIApplication.shared.open(url)
                return
            }
        }

        let businessInstalled = iOSInstalledAppsScanner.isWhatsAppBusinessInstalled()
        if !businessInstalled {
            for generic in ["whatsapp://app", "whatsapp://"] {
                if let url = URL(string: generic), UIApplication.shared.canOpenURL(url) {
                    UIApplication.shared.open(url)
                    return
                }
            }
        }

        // Se Business è installato e sta intercettando `whatsapp://`, prova Universal Link verso Messenger; se fallisce apre App Store Messenger
        if let universalURL = URL(string: "https://wa.me/") {
            UIApplication.shared.open(universalURL, options: [.universalLinksOnly: true]) { opened in
                if !opened {
                    Self.openPersonalWhatsAppStorePage()
                }
            }
            return
        }
        openPersonalWhatsAppStorePage()
    }

    @MainActor
    static func openPersonalWhatsAppStorePage() {
        if let nativeStore = URL(string: "itms-apps://itunes.apple.com/app/id310633997"),
           UIApplication.shared.canOpenURL(nativeStore) {
            UIApplication.shared.open(nativeStore)
            return
        }
        if let webStore = URL(string: "https://apps.apple.com/it/app/whatsapp-messenger/id310633997") {
            UIApplication.shared.open(webStore)
        }
    }

    /// Prepara e azzera in modo sincrono tutti i contatori prima di ogni nuovo trasferimento singolo o multiplo,
    /// così ogni avvio parte rigorosamente da 0% senza mai mostrare dati o stati residui di un trasferimento precedente.
    func prepareForFreshTransfer(
        sessionId: String,
        scope: ActiveTransferScope,
        receiverName: String,
        receiverPlatform: DevicePlatform
    ) {
        senderUploadedIdsBySession.removeValue(forKey: sessionId)
        senderUploadedBytesBySession.removeValue(forKey: sessionId)
        cleanupPendingLiveVideos()
        activeTransferScope = scope
        visualStepProgress = 0.0
        peerName = receiverName
        peerPlatform = receiverPlatform
        completedItems = 0
        totalItems = 0
        transferredBytesCount = 0
        totalBytesCount = 0
        transferredBytes = 0
        speedMegabytesPerSec = 0.0
        mergedContacts = 0
        contactsAlreadyPresentCount = 0
        importedCalendars = 0
        importedReminders = 0
        importedSms = 0
        savedLivePhotos = 0
        iCloudOptimizedSkippedHint = 0
        receivedPasswordsCsvCount = 0
        skippedDuplicates = 0
        gatedPreviewCount = 0
        failedItemsCount = 0
        receivedInstalledApps = []
        sentInstalledAppsCount = 0
        canResumeInterruptedTransfer = false
        currentItemName = ""
        isCompleted = false
        pendingNativeWhatsAppMigration = false
        requestedWhatsAppMigration = false
        needsLocalNetworkRedirect = false
        errorMessage = nil
        isSessionConnected = true
        isTransferring = true
        statusLabel = scope.isWhatsAppOnly
            ? "Connessione per il passaggio Chat WhatsApp..."
            : "Preparazione trasferimento (0%)..."
    }

    /// Legge il codice QR mostrato da WhatsApp sul nuovo telefono e apre direttamente la schermata
    /// «Trasferisci la cronologia chat» dentro WhatsApp Personale sul vecchio iPhone, saltando la Fotocamera di sistema e il bottone giallo.
    @MainActor
    static func openWhatsAppMigrationQrPayload(
        _ rawQr: String,
        completion: @escaping @MainActor (Bool, String?) -> Void
    ) {
        let trimmed = rawQr.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            completion(false, "Codice QR vuoto: riprova inquadrando il QR mostrato da WhatsApp sul nuovo telefono.")
            return
        }

        // Se per sbaglio l'utente inquadra il QR di collegamento di DirectSwitch anziché il QR di WhatsApp
        if trimmed.hasPrefix("{") && (trimmed.contains("sessionKeyHex") || trimmed.contains("DSWITCH")) {
            completion(false, "Questo è il QR di DirectSwitch: apri WhatsApp sul nuovo telefono fino al codice QR del trasferimento chat e inquadra quello!")
            return
        }

        let normalizedCandidate: String
        if trimmed.lowercased().hasPrefix("wa.me/") || trimmed.lowercased().hasPrefix("www.whatsapp.com/") || trimmed.lowercased().hasPrefix("v.whatsapp.com/") {
            normalizedCandidate = "https://\(trimmed)"
        } else {
            normalizedCandidate = trimmed
        }

        if let url = URL(string: normalizedCandidate), let scheme = url.scheme?.lowercased(), !scheme.isEmpty {
            if scheme == "http" || scheme == "https" {
                // Identico al bottone giallo «Apri in WhatsApp» della Fotocamera di iOS (Universal Link diretto senza passare da Safari)
                UIApplication.shared.open(url, options: [.universalLinksOnly: true]) { openedUniversal in
                    Task { @MainActor in
                        if openedUniversal {
                            completion(true, nil)
                        } else {
                            UIApplication.shared.open(url, options: [:]) { openedFallback in
                                Task { @MainActor in
                                    if openedFallback {
                                        completion(true, nil)
                                    } else {
                                        Self.openPersonalWhatsAppOrStore()
                                        completion(true, nil)
                                    }
                                }
                            }
                        }
                    }
                }
                return
            }

            if scheme == "whatsapp" && iOSInstalledAppsScanner.isWhatsAppBusinessInstalled() && iOSInstalledAppsScanner.isPersonalWhatsAppInstalled() {
                let suffix = String(normalizedCandidate.dropFirst("whatsapp://".count))
                if let consumerURL = URL(string: "whatsapp-consumer://\(suffix)"), UIApplication.shared.canOpenURL(consumerURL) {
                    UIApplication.shared.open(consumerURL, options: [:]) { openedConsumer in
                        Task { @MainActor in
                            if openedConsumer {
                                completion(true, nil)
                            } else {
                                UIApplication.shared.open(url, options: [:]) { openedOrig in
                                    Task { @MainActor in
                                        completion(openedOrig, openedOrig ? nil : "Impossibile aprire il link di WhatsApp.")
                                    }
                                }
                            }
                        }
                    }
                    return
                }
            }

            UIApplication.shared.open(url, options: [:]) { opened in
                Task { @MainActor in
                    if opened {
                        completion(true, nil)
                    } else {
                        Self.openPersonalWhatsAppOrStore()
                        completion(true, nil)
                    }
                }
            }
            return
        }

        // Payload QR non-URL (es. QR opaco Android Switch): apre WhatsApp Personale e avvisa chiaramente
        openPersonalWhatsAppOrStore()
        completion(true, nil)
    }

    /// Apre esplicitamente WhatsApp Business solo quando l'utente tocca la voce secondaria dedicata.
    @MainActor
    static func openWhatsAppBusiness() {
        for scheme in ["whatsapp-smb://app", "whatsapp-smb://"] {
            if let url = URL(string: scheme), UIApplication.shared.canOpenURL(url) {
                UIApplication.shared.open(url)
                return
            }
        }
    }

    private nonisolated static func isAllowedPeerEndpoint(_ endpoint: Network.NWEndpoint) -> Bool {
        if case .hostPort(let host, _) = endpoint {
            let raw = "\(host)"
            let cleanIp = raw.components(separatedBy: "%").first ?? raw
            if !cleanIp.contains(":") && cleanIp.split(separator: ".").count == 4 {
                return DirectSwitchLocalNetwork.isLocalIPv4(cleanIp)
            }
        }
        return true
    }

    private nonisolated static func sendUdpBroadcastPacket(_ data: Data, localIps: [String], port: UInt16) {
        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard fd >= 0 else { return }
        defer { close(fd) }

        var broadcastEnable: Int32 = 1
        _ = setsockopt(fd, SOL_SOCKET, SO_BROADCAST, &broadcastEnable, socklen_t(MemoryLayout<Int32>.size))

        var targets = Set<String>(["255.255.255.255"])
        for ip in localIps {
            let parts = ip.split(separator: ".")
            if parts.count == 4 {
                targets.insert("\(parts[0]).\(parts[1]).\(parts[2]).255")
            }
        }

        for target in targets {
            var addr = sockaddr_in()
            addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            addr.sin_family = sa_family_t(AF_INET)
            addr.sin_port = port.bigEndian
            guard inet_pton(AF_INET, target, &addr.sin_addr) == 1 else { continue }

            data.withUnsafeBytes { rawBuf in
                guard let base = rawBuf.baseAddress else { return }
                withUnsafePointer(to: &addr) { addrPtr in
                    addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { saPtr in
                        _ = sendto(fd, base, rawBuf.count, 0, saPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
                    }
                }
            }
        }
    }

    /// Legge la richiesta HTTP/1.1 in streaming: i file grandi (`PUT /v1/item/...`) vengono scritti direttamente
    /// su file temporaneo su disco per mantenere l'occupazione RAM sotto 1 MiB anche con video 4K multi-GB.
    private nonisolated func receiveHttpStream(on connection: NWConnection, state: IncomingHttpStreamState) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 512 * 1024) { [weak self] chunk, _, isComplete, error in
            guard let self else {
                state.cleanupTempFile()
                connection.cancel()
                return
            }

            if let chunk, !chunk.isEmpty {
                if !state.headersParsed {
                    state.headerBuffer.append(chunk)
                    if let sepRange = state.headerBuffer.range(of: Data("\r\n\r\n".utf8)) {
                        let headerData = state.headerBuffer.subdata(in: 0..<sepRange.lowerBound)
                        let leftover = state.headerBuffer.subdata(in: sepRange.upperBound..<state.headerBuffer.count)
                        state.headerBuffer.removeAll(keepingCapacity: false)

                        guard Self.parseRequestHeaders(headerData: headerData, into: state) else {
                            state.cleanupTempFile()
                            connection.cancel()
                            return
                        }
                        state.headersParsed = true

                        let isStreamingItem = state.method == "PUT"
                            && (state.path.hasPrefix("/v1/item/") || state.path.hasPrefix("/v1/item-live-video/"))
                        let maxAllowed = isStreamingItem ? Self.maxStreamItemBytes : Self.maxControlBodyBytes
                        if state.expectedBodyLength < 0 || state.expectedBodyLength > maxAllowed {
                            state.cleanupTempFile()
                            self.sendPlainJson(connection: connection, status: 413, json: #"{"error":"payload_too_large"}"#)
                            return
                        }

                        if let expectHeader = state.headers["expect"]?.lowercased(),
                           expectHeader.contains("100-continue") {
                            connection.send(content: Data("HTTP/1.1 100 Continue\r\n\r\n".utf8), completion: .idempotent)
                        }

                        if isStreamingItem {
                            let tempURL = FileManager.default.temporaryDirectory
                                .appendingPathComponent("ds_rx_\(UUID().uuidString).enc")
                            FileManager.default.createFile(atPath: tempURL.path, contents: nil)
                            guard let handle = try? FileHandle(forWritingTo: tempURL) else {
                                state.cleanupTempFile()
                                self.sendPlainJson(connection: connection, status: 500, json: #"{"error":"temp_file_error"}"#)
                                return
                            }
                            state.tempBodyFileURL = tempURL
                            state.tempBodyFileHandle = handle
                        } else if state.expectedBodyLength > 0 {
                            state.inMemoryBody.reserveCapacity(Int(state.expectedBodyLength))
                        }

                        if !leftover.isEmpty {
                            guard Self.appendBodyBytes(leftover, into: state) else {
                                state.cleanupTempFile()
                                connection.cancel()
                                return
                            }
                        }
                    } else if state.headerBuffer.count > Self.maxHeaderBytes {
                        state.cleanupTempFile()
                        connection.cancel()
                        return
                    }
                } else {
                    guard Self.appendBodyBytes(chunk, into: state) else {
                        state.cleanupTempFile()
                        connection.cancel()
                        return
                    }
                }
            }

            if state.headersParsed && state.receivedBodyBytes >= state.expectedBodyLength {
                let bodyFileURL = state.takeBodyFileOwnership()
                let method = state.method
                let rawTarget = state.rawTarget
                let path = state.path
                let headers = state.headers
                let bodyData = state.inMemoryBody
                Task { @MainActor in
                    await self.routeIncomingHttp(
                        method: method,
                        rawTarget: rawTarget,
                        path: path,
                        headers: headers,
                        body: bodyData,
                        bodyFileURL: bodyFileURL,
                        connection: connection
                    )
                }
                return
            }

            if isComplete || error != nil {
                state.cleanupTempFile()
                connection.cancel()
                return
            }

            self.receiveHttpStream(on: connection, state: state)
        }
    }

    private nonisolated static func parseRequestHeaders(headerData: Data, into state: IncomingHttpStreamState) -> Bool {
        guard let headerStr = String(data: headerData, encoding: .utf8) else { return false }
        let lines = headerStr.components(separatedBy: "\r\n")
        guard let firstLine = lines.first else { return false }
        let parts = firstLine.split(separator: " ")
        guard parts.count >= 2 else { return false }
        state.method = String(parts[0]).uppercased()
        let rawTarget = String(parts[1])
        state.rawTarget = rawTarget
        state.path = rawTarget.components(separatedBy: "?").first ?? rawTarget

        var parsedHeaders: [String: String] = [:]
        for line in lines.dropFirst() {
            if let idx = line.firstIndex(of: ":") {
                let k = line[..<idx].trimmingCharacters(in: .whitespaces).lowercased()
                let v = line[line.index(after: idx)...].trimmingCharacters(in: .whitespaces)
                parsedHeaders[k] = v
            }
        }
        state.headers = parsedHeaders
        state.expectedBodyLength = Int64(parsedHeaders["content-length"] ?? "0") ?? 0
        return true
    }

    private nonisolated static func appendBodyBytes(_ bytes: Data, into state: IncomingHttpStreamState) -> Bool {
        let remaining = max(0, state.expectedBodyLength - state.receivedBodyBytes)
        let slice = bytes.count > Int(remaining) ? bytes.prefix(Int(remaining)) : bytes
        if let handle = state.tempBodyFileHandle {
            do {
                if !slice.isEmpty {
                    try handle.write(contentsOf: slice)
                }
            } catch {
                return false
            }
        } else if !slice.isEmpty {
            state.inMemoryBody.append(slice)
        }
        state.receivedBodyBytes += Int64(slice.count)
        return true
    }

    private func isValidBootstrapRequest(_ rawTarget: String) -> Bool {
        guard let expected = bootstrapSecretToken, !expected.isEmpty,
              let comps = URLComponents(string: "http://localhost\(rawTarget)"),
              let provided = comps.queryItems?.first(where: { $0.name == "token" })?.value else {
            return false
        }
        return DirectSwitchCrypto.constantTimeEquals(expected, provided)
    }

    private func routeIncomingHttp(
        method: String,
        rawTarget: String,
        path: String,
        headers: [String: String],
        body: Data,
        bodyFileURL: URL?,
        connection: NWConnection
    ) async {
        defer {
            if let tempURL = bodyFileURL {
                try? FileManager.default.removeItem(at: tempURL)
            }
        }

        if method == "GET" && path == "/v1/ping" {
            sendPlainJson(connection: connection, status: 200, json: #"{"ok":true,"proto":"DSWITCH_V1"}"#)
            return
        }

        if method == "GET" && path == "/start" {
            guard isValidBootstrapRequest(rawTarget), let token = bootstrapSecretToken else {
                sendPlainJson(connection: connection, status: 403, json: #"{"error":"invalid_bootstrap_token"}"#)
                return
            }
            let count = iOSContactsSmartMerger.readAllContacts().count
            let devName = UIDevice.current.name
                .replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")
            let html = """
            <!DOCTYPE html><html lang="it"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>DirectSwitch da \(devName)</title><style>body{font-family:-apple-system,sans-serif;background:#e8f0f5;color:#0f172a;margin:0;padding:20px}.card{background:#fff;border-radius:18px;padding:20px;margin-bottom:16px;box-shadow:0 4px 14px rgba(0,0,0,0.06)}h1{font-size:21px;margin:0 0 8px 0;color:#008f7a}p{font-size:14px;color:#475569;line-height:1.45}.btn{display:block;text-align:center;text-decoration:none;font-weight:600;font-size:16px;padding:14px 16px;border-radius:14px;background:#007aff;color:#fff;margin-top:12px}</style></head><body><div class="card"><h1>DirectSwitch — Rubrica Rapida da \(devName)</h1><p>Scarica e importa immediatamente tutti i <b>\(count) contatti</b> in Wi-Fi locale senza passare da iCloud o Google.</p><a class="btn" href="/download/contacts.vcf?token=\(token)">Importa Subito Rubrica (\(count) Contatti)</a></div></body></html>
            """
            sendCustomResponse(
                connection: connection,
                contentType: "text/html; charset=utf-8",
                attachmentName: nil,
                body: Data(html.utf8)
            )
            return
        }

        if method == "GET" && path == "/download/contacts.vcf" {
            guard isValidBootstrapRequest(rawTarget) else {
                sendPlainJson(connection: connection, status: 403, json: #"{"error":"invalid_bootstrap_token"}"#)
                return
            }
            let vcf = iOSContactsSmartMerger.exportVCardBundle()
            sendCustomResponse(
                connection: connection,
                contentType: "text/vcard; charset=utf-8",
                attachmentName: "Rubrica_DirectSwitch.vcf",
                body: Data(vcf.utf8)
            )
            return
        }

        if method == "POST" && path == "/v1/pair-pin" {
            guard let snapshot = activeQrPayloadSnapshot,
                  activePairingPin.count == 6,
                  !activeSessionId.isEmpty else {
                sendPlainJson(connection: connection, status: 403, json: #"{"error":"pin_pairing_inactive"}"#)
                return
            }
            if pinPairingConsumed || pinFailedAttempts >= Self.maxPinAttempts {
                sendPlainJson(connection: connection, status: 429, json: #"{"error":"pin_locked_use_qr"}"#)
                return
            }
            guard !body.isEmpty, body.count <= 64 * 1024,
                  let pinKey = try? DirectSwitchCrypto.derivePinSymmetricKey(sessionId: activeSessionId, pin: activePairingPin),
                  let plainJson = try? DirectSwitchCrypto.openJsonEnvelope(body, key: pinKey),
                  let reqData = plainJson.data(using: .utf8),
                  let req = try? JSONDecoder().decode(PinPairingRequest.self, from: reqData),
                  req.sessionId == activeSessionId else {
                pinFailedAttempts += 1
                sendPlainJson(connection: connection, status: 401, json: #"{"error":"invalid_pin"}"#)
                return
            }
            pinPairingConsumed = true
            sendEncryptedJson(connection: connection, status: 200, plainJson: snapshot.toCompactJson(), key: pinKey)
            return
        }

        guard let key = symmetricKey else {
            sendPlainJson(connection: connection, status: 401, json: #"{"error":"no_session_key"}"#)
            return
        }

        if method == "POST" && path == "/v1/handshake" {
            guard let plainJson = try? DirectSwitchCrypto.openJsonEnvelope(body, key: key),
                  let reqData = plainJson.data(using: .utf8),
                  let req = try? JSONDecoder().decode(HandshakeRequest.self, from: reqData),
                  req.sessionId == activeSessionId else {
                sendPlainJson(connection: connection, status: 401, json: #"{"error":"handshake_unauthorized"}"#)
                return
            }
            let free = iOSStorageCapacityChecker.freeStorageBytes()
            let tier = LicensePolicyEvaluator.resolveTier(
                senderPlatform: req.senderPlatform,
                receiverPlatform: .IOS,
                senderHasPro: req.senderHasPro,
                receiverHasPro: iOSLicenseStore.isLocalProUnlocked,
                senderHasCloudSavePro: req.senderHasCloudSavePro,
                receiverHasCloudSavePro: iOSLicenseStore.hasVerifiedCloudSaveProEntitlement
            )
            peerName = req.senderName
            peerPlatform = req.senderPlatform
            licenseTier = tier
            transferStartDate = Date()
            activeRunIsResume = (req.isResume == true)

            // Se NON è una ripresa di errore di rete (ma un nuovo trasferimento singolo o successivo),
            // azzera tutti i contatori del ricevente così riparte sempre da 0% e mostra solo le categorie di QUESTO invio!
            if !activeRunIsResume {
                cleanupPendingLiveVideos()
                manifestItems.removeAll()
                completedItemIds.removeAll()
                completedItems = 0
                totalItems = 0
                transferredBytes = 0
                transferredBytesCount = 0
                totalBytesCount = 0
                speedMegabytesPerSec = 0.0
                visualStepProgress = 0.0
                mergedContacts = 0
                contactsAlreadyPresentCount = 0
                importedCalendars = 0
                importedReminders = 0
                importedSms = 0
                savedLivePhotos = 0
                iCloudOptimizedSkippedHint = 0
                receivedPasswordsCsvCount = 0
                skippedDuplicates = 0
                gatedPreviewCount = 0
                failedItemsCount = 0
                receivedInstalledApps = []
                sentInstalledAppsCount = 0
                isCompleted = false
                pendingNativeWhatsAppMigration = false
                requestedWhatsAppMigration = false
                currentItemName = ""
                if let incomingScope = req.transferScope {
                    activeTransferScope = incomingScope
                } else {
                    activeTransferScope = ActiveTransferScope()
                }
            } else if let incomingScope = req.transferScope {
                activeTransferScope = incomingScope
            }

            // In fase di handshake verifichiamo un margine operativo minimo (250 MB):
            // il controllo esatto sui byte da scrivere viene eseguito in /v1/manifest DOPO aver escluso i file già presenti (fondamentale per il Resume all'85%!).
            let hasMinimalWorkingRoom = free > 250 * 1024 * 1024
            let enough = hasMinimalWorkingRoom && (completedItemIds.isEmpty ? req.totalEstimatedBytes < max(0, free - 150 * 1024 * 1024) || req.totalEstimatedBytes == 0 : true)
            // Se anche su nuova sessione molti file sono già nel Rullino, consentiamo comunque l'analisi del manifest se c'è almeno 250 MB liberi
            let allowProceedToManifest = hasMinimalWorkingRoom
            handshakeAuthenticated = allowProceedToManifest
            if allowProceedToManifest {
                isSessionConnected = true
                isTransferring = true
                errorMessage = nil
            } else {
                errorMessage = "Spazio su iPhone insufficiente (meno di 250 MB liberi)."
            }
            statusLabel = allowProceedToManifest
                ? "Connesso in modo sicuro a \(req.senderName)!"
                : "Spazio su iPhone insufficiente per completare il trasferimento."

            let resp = HandshakeResponse(
                accepted: allowProceedToManifest,
                receiverName: UIDevice.current.name,
                receiverPlatform: .IOS,
                freeStorageBytes: free,
                licenseTier: tier,
                hasEnoughSpace: enough || allowProceedToManifest,
                statusMessage: allowProceedToManifest ? "iPhone pronto a ricevere" : "Spazio su iPhone insufficiente"
            )
            if let encoded = try? JSONEncoder().encode(resp),
               let jsonStr = String(data: encoded, encoding: .utf8) {
                sendEncryptedJson(connection: connection, status: 200, plainJson: jsonStr, key: key)
            }
            return
        }

        guard handshakeAuthenticated else {
            sendPlainJson(connection: connection, status: 401, json: #"{"error":"session_not_authenticated"}"#)
            return
        }

        if method == "POST" && path == "/v1/manifest" {
            guard let plainJson = try? DirectSwitchCrypto.openJsonEnvelope(body, key: key),
                  let manifestData = plainJson.data(using: .utf8),
                  let manifest = try? JSONDecoder().decode(TransferManifest.self, from: manifestData),
                  manifest.sessionId == activeSessionId else {
                sendPlainJson(connection: connection, status: 401, json: #"{"error":"manifest_unauthorized"}"#)
                return
            }
            if !manifest.contactsPayload.isEmpty {
                _ = await iOSContactsSmartMerger.requestAccessIfNeeded()
            }
            let (insContacts, skipContacts) = iOSContactsSmartMerger.mergeIncomingContacts(manifest.contactsPayload)
            let currentTier = licenseTier ?? .INTRA_OS_FREE
            let fullAllowed = LicensePolicyEvaluator.allowsFullCategories(currentTier)
            requestedWhatsAppMigration = (manifest.requestNativeWhatsAppMigration == true) && fullAllowed

            if fullAllowed && !manifest.calendarsPayload.isEmpty {
                _ = await iOSCalendarMigrator.requestAccessIfNeeded()
            }
            let insCal = fullAllowed ? iOSCalendarMigrator.importEvents(manifest.calendarsPayload) : 0

            let incomingReminders = manifest.remindersPayload ?? []
            if fullAllowed && !incomingReminders.isEmpty {
                _ = await iOSRemindersMigrator.requestAccessIfNeeded()
            }
            let insRem = fullAllowed ? await iOSRemindersMigrator.importReminders(incomingReminders) : 0
            let insSms = fullAllowed ? iOSSmsArchiveStore.saveIncomingSmsArchive(manifest.smsPayload) : 0

            let (tierFiltered, gated) = LicensePolicyEvaluator.filterItemsForTier(manifest.items, tier: currentTier)
            let hasMedia = tierFiltered.contains { $0.category == .PHOTOS || $0.category == .VIDEOS }
            let existingMediaKeys = hasMedia ? await iOSPhotoKitMigrator.existingDedupKeys() : Set<String>()

            var acceptedItems: [ManifestItem] = []
            var skippedMediaDuplicates = 0
            for item in tierFiltered {
                if completedItemIds.contains(item.id) ||
                    ((item.category == .PHOTOS || item.category == .VIDEOS) && existingMediaKeys.contains(item.dedupKey)) {
                    skippedMediaDuplicates += 1
                } else {
                    acceptedItems.append(item)
                    manifestItems[item.id] = item
                }
            }

            let remainingBytesToWrite = acceptedItems.reduce(Int64(0)) { $0 + $1.sizeBytes }
            let freeNow = iOSStorageCapacityChecker.freeStorageBytes()
            if remainingBytesToWrite > max(0, freeNow - 150 * 1024 * 1024) {
                errorMessage = "Spazio libero insufficiente su questo iPhone per i restanti \(DirectSwitchUIHelpers.formatBytes(remainingBytesToWrite))."
                sendPlainJson(connection: connection, status: 507, json: #"{"error":"insufficient_storage"}"#)
                return
            }

            let totalSkipped = skipContacts + skippedMediaDuplicates
            let previouslyCompletedInSession = completedItemIds.count
            completedItems = previouslyCompletedInSession
            totalItems = previouslyCompletedInSession + acceptedItems.count
            totalBytesCount = transferredBytes + remainingBytesToWrite
            mergedContacts += insContacts
            contactsAlreadyPresentCount = skipContacts
            importedCalendars += insCal
            importedReminders += insRem
            importedSms += insSms
            skippedDuplicates = totalSkipped
            gatedPreviewCount = gated
            activeTransferScope = manifest.transferScope ?? ActiveTransferScope.inferred(from: manifest)
            visualStepProgress = acceptedItems.isEmpty ? 0.75 : 0.05
            if fullAllowed {
                if let incomingApps = manifest.installedAppsPayload, !incomingApps.isEmpty {
                    receivedInstalledApps = incomingApps
                } else if !activeRunIsResume {
                    receivedInstalledApps = []
                }
            } else {
                receivedInstalledApps = []
            }

            let resp = ManifestResponse(
                acceptedItemIds: acceptedItems.map(\.id),
                skippedDuplicateCount: totalSkipped,
                contactsMergedCount: mergedContacts,
                contactsSkippedDuplicates: skipContacts,
                calendarsImportedCount: importedCalendars,
                remindersImportedCount: importedReminders,
                smsImportedCount: importedSms,
                gatedByCrossOsPreviewCount: gated
            )
            if let encoded = try? JSONEncoder().encode(resp),
               let jsonStr = String(data: encoded, encoding: .utf8) {
                sendEncryptedJson(connection: connection, status: 200, plainJson: jsonStr, key: key)
            }
            return
        }

        // Componente video accoppiata (.MOV) di una Live Photo iPhone -> iPhone
        if method == "PUT" && path.hasPrefix("/v1/item-live-video/") {
            let itemId = String(path.dropFirst("/v1/item-live-video/".count))
            guard let item = manifestItems[itemId], let encryptedFileURL = bodyFileURL else {
                sendPlainJson(connection: connection, status: 404, json: #"{"error":"item_not_found"}"#)
                return
            }
            let rawLiveExt = URL(fileURLWithPath: item.livePhotoVideoFileName ?? "live.mov").pathExtension
            let liveExt = rawLiveExt.isEmpty ? "mov" : rawLiveExt
            let tempLivePlainURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("ds_live_dec_\(UUID().uuidString).\(liveExt)")

            let decryptResult = await Task.detached(priority: .userInitiated) {
                try? DirectSwitchCrypto.decryptFileCSGCM1(inputURL: encryptedFileURL, outputURL: tempLivePlainURL, key: key)
            }.value

            guard let (plainBytes, actualSha) = decryptResult else {
                try? FileManager.default.removeItem(at: tempLivePlainURL)
                sendPlainJson(connection: connection, status: 401, json: #"{"error":"csgcm1_decrypt_failed"}"#)
                return
            }

            let expectedLen = Int64(headers["x-ds-plain-length"] ?? "")
            let expectedSha = headers["x-ds-sha256"]?.lowercased()
            if (expectedLen != nil && plainBytes != expectedLen) || (expectedSha != nil && expectedSha != actualSha) {
                try? FileManager.default.removeItem(at: tempLivePlainURL)
                sendPlainJson(connection: connection, status: 422, json: #"{"error":"sha256_or_length_mismatch"}"#)
                return
            }

            if let prev = pendingLiveVideoTempURLs[itemId] {
                try? FileManager.default.removeItem(at: prev)
            }
            pendingLiveVideoTempURLs[itemId] = tempLivePlainURL
            sendPlainJson(connection: connection, status: 200, json: #"{"ok":true}"#)
            return
        }

        if method == "PUT" && path.hasPrefix("/v1/item/") {
            let itemId = String(path.dropFirst("/v1/item/".count))
            let pairedLiveURL = pendingLiveVideoTempURLs.removeValue(forKey: itemId)
            defer {
                if let pairedLiveURL {
                    try? FileManager.default.removeItem(at: pairedLiveURL)
                }
            }
            guard let item = manifestItems[itemId], let encryptedFileURL = bodyFileURL else {
                sendPlainJson(connection: connection, status: 404, json: #"{"error":"item_not_found"}"#)
                return
            }

            let safeExt = URL(fileURLWithPath: item.fileName).pathExtension
            let tempPlainURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("ds_dec_\(UUID().uuidString)\(safeExt.isEmpty ? "" : ".\(safeExt)")")
            defer { try? FileManager.default.removeItem(at: tempPlainURL) }

            let decryptResult = await Task.detached(priority: .userInitiated) {
                try? DirectSwitchCrypto.decryptFileCSGCM1(inputURL: encryptedFileURL, outputURL: tempPlainURL, key: key)
            }.value

            guard let (plainBytes, actualSha) = decryptResult else {
                sendPlainJson(connection: connection, status: 401, json: #"{"error":"csgcm1_decrypt_failed"}"#)
                return
            }

            let expectedLen = Int64(headers["x-ds-plain-length"] ?? "") ?? item.sizeBytes
            let expectedSha = headers["x-ds-sha256"]?.lowercased()
            if plainBytes != expectedLen || (expectedSha != nil && expectedSha != actualSha) {
                sendPlainJson(connection: connection, status: 422, json: #"{"error":"sha256_or_length_mismatch"}"#)
                return
            }

            let savedOk: Bool
            var saveErrorCode: String? = nil
            if item.category == .PHOTOS || item.category == .VIDEOS {
                let res = await iOSPhotoKitMigrator.saveMediaFileToLibraryWithReason(
                    item: item,
                    fileURL: tempPlainURL,
                    pairedLiveVideoURL: pairedLiveURL
                )
                savedOk = res.saved
                saveErrorCode = res.errorCode
                if res.savedAsLivePhoto {
                    savedLivePhotos += 1
                }
            } else {
                let isPasswordsCsv = iOSDocumentsSandboxBridge.isPasswordsCsvFile(item.fileName)
                savedOk = iOSDocumentsSandboxBridge.saveDocumentFile(item: item, sourceFileURL: tempPlainURL)
                if savedOk && isPasswordsCsv {
                    receivedPasswordsCsvCount += 1
                }
            }
            guard savedOk else {
                if saveErrorCode == "photo_permission_denied" {
                    errorMessage = "Permesso Foto disattivato su questo iPhone: tocca il pulsante qui sotto per aprire Impostazioni → DirectSwitch → Foto."
                    sendPlainJson(connection: connection, status: 403, json: #"{"error":"photo_permission_denied"}"#)
                } else {
                    sendPlainJson(connection: connection, status: 500, json: #"{"error":"save_failed"}"#)
                }
                return
            }

            completedItemIds.insert(itemId)
            completedItems += 1
            currentItemName = item.fileName
            transferredBytes += plainBytes
            transferredBytesCount = transferredBytes
            let elapsed = max(0.25, Date().timeIntervalSince(transferStartDate))
            speedMegabytesPerSec = (Double(transferredBytes) / (1024.0 * 1024.0)) / elapsed
            statusLabel = "Ricevuto \(item.fileName) (\(completedItems)/\(totalItems))"
            let pct = totalItems > 0 ? Int((Double(completedItems) / Double(totalItems)) * 100.0) : 50
            iOSBackgroundTransferKeepAlive.shared.updateProgress(percent: pct, detail: statusLabel)
            sendPlainJson(connection: connection, status: 200, json: #"{"ok":true}"#)
            return
        }

        if method == "POST" && path == "/v1/complete" {
            if !body.isEmpty {
                guard (try? DirectSwitchCrypto.openJsonEnvelope(body, key: key)) != nil else {
                    sendPlainJson(connection: connection, status: 401, json: #"{"error":"complete_unauthorized"}"#)
                    return
                }
            }
            cleanupPendingLiveVideos()
            isTransferring = false
            isBackgroundKeepAliveActive = false
            currentItemName = ""
            visualStepProgress = 1.0
            pendingNativeWhatsAppMigration = requestedWhatsAppMigration
            isCompleted = true
            statusLabel = "Trasferimento su iPhone completato!"
            iOSBackgroundTransferKeepAlive.shared.endActiveSession(
                completed: true,
                completionSummary: "Ricevuti \(completedItems) file e \(mergedContacts) contatti su questo iPhone."
            )
            let elapsedMs = Int64(max(1.0, Date().timeIntervalSince(transferStartDate) * 1000.0))
            let report = TransferCompletionReport(
                sessionId: activeSessionId,
                licenseTier: licenseTier ?? .INTRA_OS_FREE,
                transferredFilesCount: completedItems,
                transferredBytes: transferredBytes,
                mergedContactsCount: mergedContacts,
                importedCalendarsCount: importedCalendars,
                remindersImportedCount: importedReminders,
                livePhotosSavedCount: savedLivePhotos,
                importedSmsCount: importedSms,
                skippedDuplicatesCount: skippedDuplicates,
                elapsedMillis: elapsedMs
            )
            if let encoded = try? JSONEncoder().encode(report),
               let jsonStr = String(data: encoded, encoding: .utf8) {
                sendEncryptedJson(connection: connection, status: 200, plainJson: jsonStr, key: key)
            }
            return
        }

        sendPlainJson(connection: connection, status: 404, json: #"{"error":"not_found"}"#)
    }

    /// Avvia l'ascolto automatico UDP sulla porta 49444 e il browser Bonjour `_directswitch._tcp` per:
    /// 1) Far comparire e verificare subito il permesso iOS «Rete locale» (`kDNSServiceErr_PolicyDenied`).
    /// 2) Rilevare i dispositivi riceventi senza mai duplicare lo stesso telefono fisico sulla rete.
    func startUdpAutoDiscovery() {
        stopUdpAutoDiscovery()
        discoveredBeacons.removeAll()
        beaconLastSeen.removeAll()
        needsLocalNetworkRedirect = false

        // Browser Bonjour: attiva la voce «Rete locale» di DirectSwitch in Impostazioni iOS e ne rileva l'eventuale blocco
        let browser = NWBrowser(for: .bonjour(type: "_directswitch._tcp", domain: nil), using: .tcp)
        browser.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                Task { @MainActor [weak self] in
                    self?.isLocalNetworkDenied = false
                }
            case .waiting(let err), .failed(let err):
                if Self.isLocalNetworkPolicyDenied(err) {
                    Task { @MainActor [weak self] in
                        self?.isLocalNetworkDenied = true
                        self?.needsLocalNetworkRedirect = true
                    }
                }
            default:
                break
            }
        }
        browser.start(queue: .global(qos: .utility))
        bonjourBrowser = browser

        guard let port = Network.NWEndpoint.Port(rawValue: 49444),
              let udpListener = try? NWListener(using: .udp, on: port) else { return }

        udpListener.stateUpdateHandler = { [weak self] state in
            if case .waiting(let err) = state, Self.isLocalNetworkPolicyDenied(err) {
                Task { @MainActor [weak self] in
                    self?.isLocalNetworkDenied = true
                }
            }
        }

        udpListener.newConnectionHandler = { [weak self] conn in
            let remoteIp = Self.extractIPv4FromEndpoint(conn.endpoint)
            conn.start(queue: .global(qos: .userInitiated))
            conn.receiveMessage { [weak self] data, _, _, _ in
                if let d = data,
                   let str = String(data: d, encoding: .utf8),
                   let rawBeacon = try? DiscoveryBeaconPayload.fromJson(str) {
                    var safeIps = rawBeacon.ips.filter { DirectSwitchLocalNetwork.isLocalIPv4($0) }
                    if let rIp = remoteIp, DirectSwitchLocalNetwork.isLocalIPv4(rIp), !safeIps.contains(rIp) {
                        safeIps.insert(rIp, at: 0)
                    }
                    if !safeIps.isEmpty {
                        let sanitized = DiscoveryBeaconPayload(
                            proto: rawBeacon.proto,
                            sessionId: rawBeacon.sessionId,
                            receiverName: rawBeacon.receiverName,
                            receiverPlatform: rawBeacon.receiverPlatform,
                            ips: safeIps,
                            port: rawBeacon.port,
                            receiverHasPro: rawBeacon.receiverHasPro
                        )
                        Task { @MainActor [weak self] in
                            guard let self else { return }
                            // Ignora eventuali pacchetti broadcast provenienti da questo stesso iPhone
                            if !self.activeSessionId.isEmpty && sanitized.sessionId == self.activeSessionId {
                                return
                            }
                            let myLocalIps = Set(Self.localIPv4Addresses())
                            if !myLocalIps.isEmpty && Set(sanitized.ips).isSubset(of: myLocalIps) {
                                return
                            }
                            self.isLocalNetworkDenied = false
                            self.beaconLastSeen[sanitized.sessionId] = Date()

                            // Deduplicazione per stesso dispositivo fisico (anche se Ricevi ha rigenerato sessionId)
                            if let idx = self.discoveredBeacons.firstIndex(where: { $0.representsSameDevice(as: sanitized) }) {
                                let previousId = self.discoveredBeacons[idx].sessionId
                                if previousId != sanitized.sessionId {
                                    self.beaconLastSeen.removeValue(forKey: previousId)
                                }
                                self.discoveredBeacons[idx] = sanitized
                            } else {
                                self.discoveredBeacons.append(sanitized)
                            }
                        }
                    }
                }
                conn.cancel()
            }
        }
        udpListener.start(queue: .global(qos: .userInitiated))
        udpDiscoveryListener = udpListener

        // Pulizia automatica dei dispositivi non più attivi (> 8,5 secondi senza beacon)
        beaconPruneTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_500_000_000)
                guard let self, !Task.isCancelled else { break }
                let cutoff = Date().addingTimeInterval(-8.5)
                self.discoveredBeacons.removeAll { beacon in
                    guard let seen = self.beaconLastSeen[beacon.sessionId] else { return false }
                    if seen < cutoff {
                        self.beaconLastSeen.removeValue(forKey: beacon.sessionId)
                        return true
                    }
                    return false
                }
            }
        }
    }

    func stopUdpAutoDiscovery() {
        beaconPruneTask?.cancel()
        beaconPruneTask = nil
        bonjourBrowser?.cancel()
        bonjourBrowser = nil
        udpDiscoveryListener?.cancel()
        udpDiscoveryListener = nil
        beaconLastSeen.removeAll()
    }

    private nonisolated static func extractIPv4FromEndpoint(_ endpoint: Network.NWEndpoint) -> String? {
        guard case .hostPort(let host, _) = endpoint else { return nil }
        let raw = "\(host)"
        let clean = raw.components(separatedBy: "%").first ?? raw
        if !clean.contains(":") && DirectSwitchLocalNetwork.isLocalIPv4(clean) {
            return clean
        }
        return nil
    }

    /// Scambia in modo autenticato il PIN a 6 cifre mostrato sul ricevente con il `QrPairingPayload` completo.
    func pairWithBeaconUsingPin(beacon: DiscoveryBeaconPayload, pin: String) async throws -> QrPairingPayload {
        let cleanPin = pin.filter { $0.isNumber }
        guard cleanPin.count == 6 else {
            throw NSError(domain: "DirectSwitch", code: -20, userInfo: [NSLocalizedDescriptionKey: "Inserisci il codice PIN a 6 cifre mostrato sul nuovo telefono."])
        }
        guard let reachableIp = await findReachableIp(ips: beacon.ips, port: beacon.port) else {
            needsLocalNetworkRedirect = true
            throw NSError(
                domain: "DirectSwitch",
                code: -21,
                userInfo: [
                    NSLocalizedDescriptionKey: "Il trasferimento non si avvia perché DirectSwitch non è abilitata per le reti locali (oppure i due telefoni sono su reti Wi-Fi diverse). Tocca il pulsante qui sotto per attivare la voce «Rete locale» nelle Impostazioni di DirectSwitch."
                ]
            )
        }
        isLocalNetworkDenied = false
        needsLocalNetworkRedirect = false
        let pinKey = try DirectSwitchCrypto.derivePinSymmetricKey(sessionId: beacon.sessionId, pin: cleanPin)
        let req = PinPairingRequest(sessionId: beacon.sessionId, senderName: UIDevice.current.name)
        let respData = try await postEncryptedJson(url: "http://\(reachableIp):\(beacon.port)/v1/pair-pin", payload: req, key: pinKey)
        guard let respStr = String(data: respData, encoding: .utf8) else {
            throw NSError(domain: "DirectSwitch", code: -22, userInfo: [NSLocalizedDescriptionKey: "Risposta PIN non valida."])
        }
        let decoded = try QrPairingPayload.fromJson(respStr)
        var mergedIps = [reachableIp]
        for ip in decoded.ips where !mergedIps.contains(ip) {
            mergedIps.append(ip)
        }
        return QrPairingPayload(
            proto: decoded.proto,
            sessionId: decoded.sessionId,
            receiverName: decoded.receiverName,
            receiverPlatform: decoded.receiverPlatform,
            ips: mergedIps,
            port: decoded.port,
            sessionKeyHex: decoded.sessionKeyHex,
            wifiSsid: decoded.wifiSsid,
            wifiPass: decoded.wifiPass,
            receiverHasPro: decoded.receiverHasPro
        )
    }

    /// Modalità Mittente (iPhone -> Android oppure iPhone -> iPhone) con cifratura, Live Photos, Promemoria, Keep-Alive in background e Resume automatico.
    func executeSenderTransfer(
        qrPayload: QrPairingPayload,
        includeContacts: Bool,
        includePhotos: Bool = true,
        includeVideos: Bool = true,
        includeCalendars: Bool,
        includeReminders: Bool = true,
        includeDocuments: Bool = true,
        includeApps: Bool = false,
        includeWhatsAppVault: Bool = true,
        installedApps: [InstalledAppRecord] = [],
        pickedDocuments: [(ManifestItem, URL)] = [],
        isResume: Bool = false
    ) async {
        Self.raiseOpenFileDescriptorLimitIfNeeded()
        var didAuthenticateSession = false
        let transferScope = ActiveTransferScope(
            contacts: includeContacts,
            photos: includePhotos,
            videos: includeVideos,
            calendars: includeCalendars,
            reminders: includeReminders,
            documents: includeDocuments,
            apps: includeApps,
            whatsApp: includeWhatsAppVault
        )
        if !isResume {
            prepareForFreshTransfer(
                sessionId: qrPayload.sessionId,
                scope: transferScope,
                receiverName: qrPayload.receiverName,
                receiverPlatform: qrPayload.receiverPlatform
            )
        } else {
            activeTransferScope = transferScope
        }
        let previouslySentIds = isResume ? (senderUploadedIdsBySession[qrPayload.sessionId] ?? []) : []
        let previouslySentBytes = isResume ? (senderUploadedBytesBySession[qrPayload.sessionId] ?? 0) : 0
        do {
            errorMessage = nil
            needsLocalNetworkRedirect = false
            canResumeInterruptedTransfer = false
            failedItemsCount = 0
            if !isResume {
                contactsAlreadyPresentCount = 0
                receivedInstalledApps = []
                sentInstalledAppsCount = 0
            }
            isCompleted = false
            pendingNativeWhatsAppMigration = false
            isSessionConnected = true
            isTransferring = true
            isBackgroundKeepAliveActive = true
            currentItemName = ""
            peerName = qrPayload.receiverName
            peerPlatform = qrPayload.receiverPlatform
            completedItems = previouslySentIds.count
            if isResume {
                if totalItems < completedItems {
                    totalItems = completedItems
                }
                transferredBytesCount = previouslySentBytes
                if totalBytesCount < transferredBytesCount {
                    totalBytesCount = transferredBytesCount
                }
            } else {
                totalItems = 0
                transferredBytesCount = 0
                totalBytesCount = 0
                visualStepProgress = 0.0
                mergedContacts = 0
                importedCalendars = 0
                importedReminders = 0
                importedSms = 0
                savedLivePhotos = 0
                skippedDuplicates = 0
                gatedPreviewCount = 0
            }
            speedMegabytesPerSec = 0.0
            iCloudOptimizedSkippedHint = 0
            receivedPasswordsCsvCount = 0
            UIApplication.shared.isIdleTimerDisabled = true
            iOSBackgroundTransferKeepAlive.shared.beginActiveSession(
                roleLabel: "Invio dati a \(qrPayload.receiverName)"
            )
            defer {
                isTransferring = false
                isBackgroundKeepAliveActive = false
                UIApplication.shared.isIdleTimerDisabled = false
                iOSBackgroundTransferKeepAlive.shared.endActiveSession(
                    completed: isCompleted,
                    completionSummary: isCompleted ? "Trasferimento completato verso \(peerName)." : nil
                )
            }

            let hotspotFallbackHint = await joinAndroidHotspotIfPresent(payload: qrPayload)
            statusLabel = previouslySentIds.isEmpty
                ? (transferScope.isWhatsAppOnly
                    ? "Connessione con \(qrPayload.receiverName) per il passaggio WhatsApp..."
                    : "Connessione diretta con \(qrPayload.receiverName)...")
                : "Ripresa canale diretto verso \(qrPayload.receiverName)..."

            var candidateIps = qrPayload.ips
            for b in discoveredBeacons where b.sessionId == qrPayload.sessionId || b.receiverName == qrPayload.receiverName {
                for ip in b.ips where !candidateIps.contains(ip) {
                    candidateIps.insert(ip, at: 0)
                }
            }

            guard var activeIp = await findReachableIp(ips: candidateIps, port: qrPayload.port) else {
                needsLocalNetworkRedirect = (hotspotFallbackHint == nil)
                if !previouslySentIds.isEmpty {
                    canResumeInterruptedTransfer = true
                }
                errorMessage = hotspotFallbackHint
                    ?? "Impossibile collegarsi a \(qrPayload.receiverName). Assicurati che DirectSwitch sia aperta sull'altro telefono e che «Rete locale» sia attiva nelle Impostazioni."
                return
            }
            isLocalNetworkDenied = false
            needsLocalNetworkRedirect = false
            var baseUrl = "http://\(activeIp):\(qrPayload.port)"
            let key = try DirectSwitchCrypto.deriveSessionSymmetricKey(sessionKeyHex: qrPayload.sessionKeyHex)

            if includeContacts && previouslySentIds.isEmpty { _ = await iOSContactsSmartMerger.requestAccessIfNeeded() }
            if includeCalendars && previouslySentIds.isEmpty { _ = await iOSCalendarMigrator.requestAccessIfNeeded() }
            if includeReminders && previouslySentIds.isEmpty { _ = await iOSRemindersMigrator.requestAccessIfNeeded() }

            let contacts = (includeContacts && previouslySentIds.isEmpty) ? iOSContactsSmartMerger.readAllContacts() : []
            let calendars = (includeCalendars && previouslySentIds.isEmpty) ? iOSCalendarMigrator.readEvents() : []
            let reminders = (includeReminders && previouslySentIds.isEmpty) ? await iOSRemindersMigrator.readReminders() : []
            let scanResult = await iOSPhotoKitMigrator.scanLibraryAssetsWithMetadata(
                includePhotos: includePhotos,
                includeVideos: includeVideos
            )
            let scannedAssets = scanResult.items
            iCloudOptimizedSkippedHint = scanResult.iCloudOptimizedCount

            let filteredPickedDocs = pickedDocuments.filter { pair in
                switch pair.0.category {
                case .WHATSAPP_VAULT: return includeWhatsAppVault
                case .DOCUMENTS: return includeDocuments
                default: return includeDocuments
                }
            }
            let allItems = scannedAssets.map(\.0) + filteredPickedDocs.map(\.0)
            let currentSentIds = isResume ? (senderUploadedIdsBySession[qrPayload.sessionId] ?? []) : []
            let remainingEstimatedBytes = allItems
                .filter { !currentSentIds.contains($0.id) }
                .reduce(Int64(0)) { $0 + $1.sizeBytes }

            let hsReq = HandshakeRequest(
                sessionId: qrPayload.sessionId,
                senderName: UIDevice.current.name,
                senderPlatform: .IOS,
                senderHasPro: iOSLicenseStore.isLocalProUnlocked,
                senderHasCloudSavePro: iOSLicenseStore.hasVerifiedCloudSaveProEntitlement,
                totalEstimatedBytes: remainingEstimatedBytes,
                isResume: isResume,
                transferScope: transferScope
            )
            let hsRespData = try await postEncryptedJson(url: "\(baseUrl)/v1/handshake", payload: hsReq, key: key)
            let hsResp = try JSONDecoder().decode(HandshakeResponse.self, from: hsRespData)
            peerName = hsResp.receiverName
            peerPlatform = hsResp.receiverPlatform
            licenseTier = hsResp.licenseTier

            guard hsResp.accepted && hsResp.hasEnoughSpace else {
                errorMessage = hsResp.statusMessage.isEmpty
                    ? "Spazio di archiviazione insufficiente su \(hsResp.receiverName)."
                    : hsResp.statusMessage
                statusLabel = "Trasferimento annullato: spazio insufficiente sul ricevente."
                return
            }
            didAuthenticateSession = true
            if !transferScope.isWhatsAppOnly {
                visualStepProgress = 0.25
            }

            let fullCategoriesAllowed = LicensePolicyEvaluator.allowsFullCategories(hsResp.licenseTier)
            let wantNativeWa = includeWhatsAppVault && fullCategoriesAllowed
            let appsToSend: [InstalledAppRecord]? = (fullCategoriesAllowed && includeApps && !installedApps.isEmpty) ? installedApps : nil
            sentInstalledAppsCount = appsToSend?.count ?? 0
            let manifest = TransferManifest(
                sessionId: qrPayload.sessionId,
                senderPlatform: .IOS,
                items: allItems,
                contactsPayload: contacts,
                calendarsPayload: calendars,
                remindersPayload: reminders.isEmpty ? nil : reminders,
                installedAppsPayload: appsToSend,
                requestNativeWhatsAppMigration: wantNativeWa,
                transferScope: transferScope
            )
            let mfRespData = try await postEncryptedJson(url: "\(baseUrl)/v1/manifest", payload: manifest, key: key)
            let mfResp = try JSONDecoder().decode(ManifestResponse.self, from: mfRespData)
            if mfResp.contactsMergedCount > 0 || mergedContacts == 0 {
                mergedContacts = mfResp.contactsMergedCount
            }
            if mfResp.contactsSkippedDuplicates > 0 || contactsAlreadyPresentCount == 0 {
                contactsAlreadyPresentCount = mfResp.contactsSkippedDuplicates
            }
            if mfResp.calendarsImportedCount > 0 || importedCalendars == 0 {
                importedCalendars = mfResp.calendarsImportedCount
            }
            if let remCount = mfResp.remindersImportedCount, remCount > 0 || importedReminders == 0 {
                importedReminders = remCount
            }
            importedSms = mfResp.smsImportedCount
            skippedDuplicates = mfResp.skippedDuplicateCount
            gatedPreviewCount = mfResp.gatedByCrossOsPreviewCount

            var uploadedIdSet = isResume ? (senderUploadedIdsBySession[qrPayload.sessionId] ?? []) : []
            var cumulativeSentBytes = isResume ? (senderUploadedBytesBySession[qrPayload.sessionId] ?? 0) : 0

            let acceptedSet = Set(mfResp.acceptedItemIds)
            let assetsToUpload = scannedAssets.filter { acceptedSet.contains($0.0.id) && !uploadedIdSet.contains($0.0.id) }
            let docsToUpload = filteredPickedDocs.filter { acceptedSet.contains($0.0.id) && !uploadedIdSet.contains($0.0.id) }

            let remainingBytesToUpload = assetsToUpload.reduce(Int64(0)) { $0 + $1.0.sizeBytes }
                + docsToUpload.reduce(Int64(0)) { $0 + $1.0.sizeBytes }

            completedItems = uploadedIdSet.count
            totalItems = uploadedIdSet.count + assetsToUpload.count + docsToUpload.count
            transferredBytesCount = cumulativeSentBytes
            totalBytesCount = cumulativeSentBytes + remainingBytesToUpload

            if !transferScope.isWhatsAppOnly && totalItems == 0 {
                statusLabel = "Sincronizzazione in corso..."
                visualStepProgress = 0.72
                try? await Task.sleep(nanoseconds: 280_000_000)
            }

            let runStartTime = Date()
            var runBytesSent: Int64 = 0
            var sessionFilesCounter = 0

            var uploadSession = Self.makeUploadSession()
            defer { uploadSession.finishTasksAndInvalidate() }

            let reconnectHandshakeReq = HandshakeRequest(
                sessionId: qrPayload.sessionId,
                senderName: UIDevice.current.name,
                senderPlatform: .IOS,
                senderHasPro: iOSLicenseStore.isLocalProUnlocked,
                senderHasCloudSavePro: iOSLicenseStore.hasVerifiedCloudSaveProEntitlement,
                totalEstimatedBytes: remainingEstimatedBytes,
                isResume: true,
                transferScope: transferScope
            )

            // Helper interno: invia un singolo file distinguendo errori di rete (con riconnessione automatica 45s) da singoli file corrotti
            func sendFileResiliently(item: ManifestItem, plainFileURL: URL) async throws -> Int64? {
                var quickAttempt = 0
                var didTryFullReconnect = false

                while true {
                    do {
                        return try await self.encryptAndStreamFileItem(
                            item: item,
                            plainFileURL: plainFileURL,
                            baseUrl: baseUrl,
                            key: key,
                            session: uploadSession
                        )
                    } catch {
                        let nsErr = error as NSError
                        // Permesso Foto negato sul ricevente -> interrompi subito con avviso chiaro
                        if nsErr.code == 403 {
                            throw error
                        }

                        // Se è un errore HTTP 422/500 sul singolo file ma il server è vivo, riprova 1 volta e poi salta SOLO questo file
                        if nsErr.domain == "DirectSwitchHttp" && (nsErr.code == 422 || nsErr.code == 500) {
                            if quickAttempt == 0 {
                                quickAttempt += 1
                                try? await Task.sleep(nanoseconds: 350_000_000)
                                continue
                            }
                            return nil
                        }

                        // Errore di RETE / CONNESSIONE (es. -1004 Impossibile connettersi al server, -1005 Connessione persa, -1001 Timeout):
                        // NON marcare MAI i file rimanenti come illeggibili!
                        if quickAttempt < 2 {
                            let backoffNs: UInt64 = quickAttempt == 0 ? 450_000_000 : 1_200_000_000
                            quickAttempt += 1
                            try? await Task.sleep(nanoseconds: backoffNs)
                            continue
                        }

                        if !didTryFullReconnect {
                            didTryFullReconnect = true
                            if let recoveredIp = await self.waitForReceiverReconnection(
                                qrPayload: qrPayload,
                                preferredIp: activeIp,
                                timeoutSeconds: 45
                            ) {
                                activeIp = recoveredIp
                                baseUrl = "http://\(recoveredIp):\(qrPayload.port)"
                                uploadSession.finishTasksAndInvalidate()
                                uploadSession = Self.makeUploadSession()
                                // Ri-autentica in modalità Resume così il ricevente conserva tutti i file già salvati
                                _ = try? await self.postEncryptedJson(url: "\(baseUrl)/v1/handshake", payload: reconnectHandshakeReq, key: key)
                                _ = try? await self.postEncryptedJson(url: "\(baseUrl)/v1/manifest", payload: manifest, key: key)
                                quickAttempt = 0
                                continue
                            }
                        }

                        // Il ricevente è rimasto irraggiungibile oltre 45 secondi: ferma subito il ciclo senza bruciare i restanti file!
                        let pctNow = self.totalItems > 0 ? Int((Double(self.completedItems) / Double(self.totalItems)) * 100.0) : 0
                        throw NSError(
                            domain: "DirectSwitchNetwork",
                            code: -1004,
                            userInfo: [
                                NSLocalizedDescriptionKey: "Connessione con \(self.peerName) in pausa al \(pctNow)% (\(self.completedItems)/\(self.totalItems) file già salvati). Mantieni aperto DirectSwitch sull'altro telefono e tocca «Riprendi trasferimento da dove era rimasto»."
                            ]
                        )
                    }
                }
            }

            // 1. Upload streaming Foto, Live Photos (.HEIC + .MOV) & Video 4K
            for (item, phAsset) in assetsToUpload {
                // Rinnova periodicamente URLSession ogni 400 file per azzerare il pool CFNetwork nei trasferimenti da 5.000+ file
                if sessionFilesCounter > 0 && sessionFilesCounter % 400 == 0 {
                    uploadSession.finishTasksAndInvalidate()
                    uploadSession = Self.makeUploadSession()
                }
                sessionFilesCounter += 1

                currentItemName = item.fileName
                statusLabel = "Invio \(item.fileName) (\(completedItems + 1)/\(totalItems))..."
                guard let plainTempURL = await iOSPhotoKitMigrator.exportAssetToTempFile(phAsset) else {
                    // Solo i file realmente non esportabili da PhotoKit incrementano questo contatore
                    failedItemsCount += 1
                    continue
                }
                defer { try? FileManager.default.removeItem(at: plainTempURL) }

                // Se il destinatario è un altro iPhone e lo scatto è una Live Photo, invia prima la clip .MOV accoppiata (best-effort)
                if hsResp.receiverPlatform == .IOS && item.isLivePhoto == true {
                    if let liveTempURL = await iOSPhotoKitMigrator.exportLivePairedVideoToTempFile(phAsset) {
                        defer { try? FileManager.default.removeItem(at: liveTempURL) }
                        _ = try? await encryptAndStreamToEndpoint(
                            endpointPath: "/v1/item-live-video/\(item.id)",
                            itemLabel: item.livePhotoVideoFileName ?? item.fileName,
                            plainFileURL: liveTempURL,
                            baseUrl: baseUrl,
                            key: key,
                            session: uploadSession
                        )
                    }
                }

                if let sentBytes = try await sendFileResiliently(item: item, plainFileURL: plainTempURL) {
                    uploadedIdSet.insert(item.id)
                    cumulativeSentBytes += sentBytes
                    senderUploadedIdsBySession[qrPayload.sessionId] = uploadedIdSet
                    senderUploadedBytesBySession[qrPayload.sessionId] = cumulativeSentBytes

                    completedItems = uploadedIdSet.count
                    runBytesSent += sentBytes
                    transferredBytesCount = cumulativeSentBytes
                    let elapsed = max(0.25, Date().timeIntervalSince(runStartTime))
                    speedMegabytesPerSec = (Double(runBytesSent) / (1024.0 * 1024.0)) / elapsed
                    let pct = totalItems > 0 ? Int((Double(completedItems) / Double(totalItems)) * 100.0) : 50
                    iOSBackgroundTransferKeepAlive.shared.updateProgress(percent: pct, detail: statusLabel)
                } else {
                    failedItemsCount += 1
                }
            }

            // 2. Upload streaming Documenti, Cartelle «Su iPhone», Password .csv & Archivi WhatsApp
            var succeededDocURLs: [URL] = []
            for (item, docURL) in docsToUpload {
                if sessionFilesCounter > 0 && sessionFilesCounter % 400 == 0 {
                    uploadSession.finishTasksAndInvalidate()
                    uploadSession = Self.makeUploadSession()
                }
                sessionFilesCounter += 1

                currentItemName = item.fileName
                statusLabel = "Invio \(item.fileName) (\(completedItems + 1)/\(totalItems))..."

                if let sentBytes = try await sendFileResiliently(item: item, plainFileURL: docURL) {
                    uploadedIdSet.insert(item.id)
                    cumulativeSentBytes += sentBytes
                    senderUploadedIdsBySession[qrPayload.sessionId] = uploadedIdSet
                    senderUploadedBytesBySession[qrPayload.sessionId] = cumulativeSentBytes

                    completedItems = uploadedIdSet.count
                    runBytesSent += sentBytes
                    transferredBytesCount = cumulativeSentBytes
                    succeededDocURLs.append(docURL)
                    let elapsed = max(0.25, Date().timeIntervalSince(runStartTime))
                    speedMegabytesPerSec = (Double(runBytesSent) / (1024.0 * 1024.0)) / elapsed
                    let pct = totalItems > 0 ? Int((Double(completedItems) / Double(totalItems)) * 100.0) : 50
                    iOSBackgroundTransferKeepAlive.shared.updateProgress(percent: pct, detail: statusLabel)
                } else {
                    failedItemsCount += 1
                }
            }

            // Chiusura sessione con riconnessione se il Wi-Fi oscilla proprio al 99%
            var completeData: Data? = nil
            do {
                completeData = try await postEncryptedJson(
                    url: "\(baseUrl)/v1/complete",
                    payload: ["sessionId": qrPayload.sessionId],
                    key: key
                )
            } catch {
                if let recoveredIp = await waitForReceiverReconnection(qrPayload: qrPayload, preferredIp: activeIp, timeoutSeconds: 20) {
                    activeIp = recoveredIp
                    baseUrl = "http://\(recoveredIp):\(qrPayload.port)"
                    completeData = try await postEncryptedJson(
                        url: "\(baseUrl)/v1/complete",
                        payload: ["sessionId": qrPayload.sessionId],
                        key: key
                    )
                } else {
                    throw error
                }
            }

            if let completeData,
               let report = try? JSONDecoder().decode(TransferCompletionReport.self, from: completeData) {
                if report.mergedContactsCount > 0 { mergedContacts = report.mergedContactsCount }
                if report.importedCalendarsCount > 0 { importedCalendars = report.importedCalendarsCount }
                if let rem = report.remindersImportedCount, rem > 0 { importedReminders = rem }
                if let live = report.livePhotosSavedCount, live > 0 { savedLivePhotos = live }
                importedSms = report.importedSmsCount
                skippedDuplicates = report.skippedDuplicatesCount
            }
            for docURL in succeededDocURLs {
                try? FileManager.default.removeItem(at: docURL)
            }
            currentItemName = ""
            senderUploadedIdsBySession.removeValue(forKey: qrPayload.sessionId)
            senderUploadedBytesBySession.removeValue(forKey: qrPayload.sessionId)
            visualStepProgress = 1.0
            statusLabel = "Trasferimento da iPhone a \(hsResp.receiverName) completato!"
            pendingNativeWhatsAppMigration = wantNativeWa
            isCompleted = true
        } catch {
            if didAuthenticateSession || !(senderUploadedIdsBySession[qrPayload.sessionId] ?? []).isEmpty {
                canResumeInterruptedTransfer = true
            }
            errorMessage = error.localizedDescription
        }
    }

    private nonisolated static func makeUploadSession() -> URLSession {
        let uploadConfig = URLSessionConfiguration.ephemeral
        uploadConfig.timeoutIntervalForRequest = 180.0
        uploadConfig.timeoutIntervalForResource = 900.0
        uploadConfig.httpMaximumConnectionsPerHost = 2
        uploadConfig.waitsForConnectivity = false
        return URLSession(configuration: uploadConfig)
    }

    /// Attende fino a `timeoutSeconds` che il ricevente torni raggiungibile (ad es. dopo uno sblocco schermo o cambio AP Wi-Fi),
    /// ascoltando anche eventuali nuovi IP pubblicati dal beacon UDP dello stesso dispositivo.
    private func waitForReceiverReconnection(
        qrPayload: QrPairingPayload,
        preferredIp: String,
        timeoutSeconds: Int
    ) async -> String? {
        let wasListeningDiscovery = (udpDiscoveryListener != nil)
        if !wasListeningDiscovery {
            startUdpAutoDiscovery()
        }
        defer {
            if !wasListeningDiscovery {
                stopUdpAutoDiscovery()
            }
        }

        let deadline = Date().addingTimeInterval(TimeInterval(timeoutSeconds))
        while Date() < deadline {
            let remaining = max(1, Int(deadline.timeIntervalSinceNow.rounded()))
            statusLabel = "Riconnessione automatica a \(peerName.isEmpty ? qrPayload.receiverName : peerName) (\(remaining)s)..."

            var ipsToProbe: [String] = [preferredIp]
            for ip in qrPayload.ips where !ipsToProbe.contains(ip) {
                ipsToProbe.append(ip)
            }
            for beacon in discoveredBeacons where beacon.sessionId == qrPayload.sessionId || beacon.receiverName == qrPayload.receiverName {
                for ip in beacon.ips where !ipsToProbe.contains(ip) {
                    ipsToProbe.insert(ip, at: 0)
                }
            }

            if let aliveIp = await findReachableIp(ips: ipsToProbe, port: qrPayload.port) {
                return aliveIp
            }
            try? await Task.sleep(nanoseconds: 1_500_000_000)
        }
        return nil
    }

    private func encryptAndStreamFileItem(
        item: ManifestItem,
        plainFileURL: URL,
        baseUrl: String,
        key: SymmetricKey,
        session: URLSession
    ) async throws -> Int64 {
        try await encryptAndStreamToEndpoint(
            endpointPath: "/v1/item/\(item.id)",
            itemLabel: item.fileName,
            plainFileURL: plainFileURL,
            baseUrl: baseUrl,
            key: key,
            session: session
        )
    }

    private func encryptAndStreamToEndpoint(
        endpointPath: String,
        itemLabel: String,
        plainFileURL: URL,
        baseUrl: String,
        key: SymmetricKey,
        session: URLSession
    ) async throws -> Int64 {
        let tempEncURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ds_tx_\(UUID().uuidString).csgcm1")
        defer {
            try? FileManager.default.removeItem(at: tempEncURL)
        }

        let (plainBytes, sha256Hex) = try await Task.detached(priority: .userInitiated) {
            try DirectSwitchCrypto.encryptFileCSGCM1(inputURL: plainFileURL, outputURL: tempEncURL, key: key)
        }.value

        guard let putUrl = URL(string: "\(baseUrl)\(endpointPath)") else {
            throw NSError(domain: "DirectSwitch", code: -13, userInfo: [NSLocalizedDescriptionKey: "URL upload non valido"])
        }
        let encAttrs = try? FileManager.default.attributesOfItem(atPath: tempEncURL.path)
        let encSize = (encAttrs?[.size] as? Int64) ?? (encAttrs?[.size] as? NSNumber)?.int64Value ?? 0

        var putReq = URLRequest(url: putUrl, timeoutInterval: 600.0)
        putReq.httpMethod = "PUT"
        putReq.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        putReq.setValue("close", forHTTPHeaderField: "Connection")
        putReq.setValue("\(plainBytes)", forHTTPHeaderField: "X-DS-Plain-Length")
        putReq.setValue(sha256Hex, forHTTPHeaderField: "X-DS-Sha256")
        if encSize > 0 {
            putReq.setValue("\(encSize)", forHTTPHeaderField: "Content-Length")
        }

        let (_, resp) = try await session.upload(for: putReq, fromFile: tempEncURL)
        guard let httpResp = resp as? HTTPURLResponse else {
            throw NSError(domain: "DirectSwitch", code: -12, userInfo: [NSLocalizedDescriptionKey: "Errore invio \(itemLabel)"])
        }
        if httpResp.statusCode == 403 {
            throw NSError(
                domain: "DirectSwitch",
                code: 403,
                userInfo: [
                    NSLocalizedDescriptionKey: "Permesso Foto disattivato sul telefono ricevente: sull'altro iPhone apri Impostazioni → DirectSwitch → Foto e abilita l'accesso."
                ]
            )
        }
        if httpResp.statusCode == 422 || httpResp.statusCode == 500 || httpResp.statusCode == 404 {
            throw NSError(
                domain: "DirectSwitchHttp",
                code: httpResp.statusCode,
                userInfo: [NSLocalizedDescriptionKey: "Errore salvataggio \(itemLabel) (HTTP \(httpResp.statusCode))"]
            )
        }
        guard httpResp.statusCode == 200 else {
            throw NSError(
                domain: "DirectSwitchNetwork",
                code: httpResp.statusCode,
                userInfo: [NSLocalizedDescriptionKey: "Errore comunicazione \(itemLabel) (HTTP \(httpResp.statusCode))"]
            )
        }
        return plainBytes
    }

    private func findReachableIp(ips: [String], port: Int) async -> String? {
        for ip in ips {
            guard DirectSwitchLocalNetwork.isLocalIPv4(ip) else { continue }
            guard let url = URL(string: "http://\(ip):\(port)/v1/ping") else { continue }
            var req = URLRequest(url: url, timeoutInterval: 3.0)
            req.httpMethod = "GET"
            if let (_, resp) = try? await URLSession.shared.data(for: req),
               let httpResp = resp as? HTTPURLResponse,
               httpResp.statusCode == 200 {
                return ip
            }
        }
        return nil
    }

    private func postEncryptedJson<T: Encodable>(url: String, payload: T, key: SymmetricKey) async throws -> Data {
        guard let targetUrl = URL(string: url) else {
            throw NSError(domain: "DirectSwitch", code: -10, userInfo: nil)
        }
        let plainData = try JSONEncoder().encode(payload)
        let plainStr = String(data: plainData, encoding: .utf8) ?? "{}"
        let sealed = try DirectSwitchCrypto.sealJsonEnvelope(plainStr, key: key)

        var req = URLRequest(url: targetUrl, timeoutInterval: 60.0)
        req.httpMethod = "POST"
        req.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        req.httpBody = sealed

        let (respBody, resp) = try await URLSession.shared.data(for: req)
        guard let httpResp = resp as? HTTPURLResponse, httpResp.statusCode == 200 else {
            let status = (resp as? HTTPURLResponse)?.statusCode ?? -1
            if status == 401 {
                let msg = url.hasSuffix("/v1/pair-pin")
                    ? "Codice PIN a 6 cifre non valido: controlla le cifre mostrate sull'altro telefono."
                    : "Sessione o PIN cambiato sull'altro telefono: usa «Ricollega con nuovo codice / QR» (i file già salvati non verranno duplicati)."
                throw NSError(domain: "DirectSwitch", code: 401, userInfo: [NSLocalizedDescriptionKey: msg])
            } else if status == 429 {
                throw NSError(domain: "DirectSwitch", code: 429, userInfo: [NSLocalizedDescriptionKey: "PIN scaduto o troppi tentativi: inquadra il codice QR."])
            }
            throw NSError(domain: "DirectSwitch", code: -11, userInfo: [NSLocalizedDescriptionKey: "Errore comunicazione DirectSwitch (HTTP \(status))."])
        }
        let openedStr = try DirectSwitchCrypto.openJsonEnvelope(respBody, key: key)
        return Data(openedStr.utf8)
    }

    private nonisolated func sendPlainJson(connection: NWConnection, status: Int, json: String) {
        let body = Data(json.utf8)
        let statusText = status == 200 ? "OK" : "Error"
        let header = "HTTP/1.1 \(status) \(statusText)\r\nContent-Type: application/json; charset=utf-8\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
        var packet = Data(header.utf8)
        packet.append(body)
        connection.send(content: packet, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private nonisolated func sendCustomResponse(
        connection: NWConnection,
        contentType: String,
        attachmentName: String?,
        body: Data
    ) {
        var header = "HTTP/1.1 200 OK\r\nContent-Type: \(contentType)\r\n"
        if let name = attachmentName, !name.isEmpty {
            header += "Content-Disposition: attachment; filename=\"\(name)\"\r\n"
        }
        header += "Content-Length: \(body.count)\r\nConnection: close\r\n\r\n"
        var packet = Data(header.utf8)
        packet.append(body)
        connection.send(content: packet, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private nonisolated func sendEncryptedJson(connection: NWConnection, status: Int, plainJson: String, key: SymmetricKey) {
        guard let encrypted = try? DirectSwitchCrypto.sealJsonEnvelope(plainJson, key: key) else {
            sendPlainJson(connection: connection, status: 500, json: #"{"error":"seal_failed"}"#)
            return
        }
        let header = "HTTP/1.1 \(status) OK\r\nContent-Type: application/octet-stream\r\nContent-Length: \(encrypted.count)\r\nConnection: close\r\n\r\n"
        var packet = Data(header.utf8)
        packet.append(encrypted)
        connection.send(content: packet, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    static func localIPv4Addresses() -> [String] {
        var addresses: [String] = []
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        if getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr {
            for ptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
                let flags = Int32(ptr.pointee.ifa_flags)
                let addr = ptr.pointee.ifa_addr.pointee
                if (flags & (IFF_UP | IFF_RUNNING | IFF_LOOPBACK)) == (IFF_UP | IFF_RUNNING),
                   addr.sa_family == UInt8(AF_INET) {
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    if getnameinfo(ptr.pointee.ifa_addr, socklen_t(addr.sa_len), &hostname, socklen_t(hostname.count), nil, 0, NI_NUMERICHOST) == 0 {
                        let ip = String(cString: hostname)
                        if DirectSwitchLocalNetwork.isLocalIPv4(ip) && !ip.hasPrefix("169.254.") {
                            addresses.append(ip)
                        }
                    }
                }
            }
            freeifaddrs(ifaddr)
        }
        return Array(Set(addresses))
    }
}
