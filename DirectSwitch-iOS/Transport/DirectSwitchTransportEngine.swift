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
        try? tempBodyFileHandle?.close()
        tempBodyFileHandle = nil
    }

    func cleanupTempFile() {
        closeHandle()
        if let url = tempBodyFileURL {
            try? FileManager.default.removeItem(at: url)
            tempBodyFileURL = nil
        }
    }
}

@MainActor
final class DirectSwitchTransportViewModel: ObservableObject {
    private static let maxPinAttempts = 3
    private static let maxHeaderBytes = 32 * 1024
    private static let maxControlBodyBytes: Int64 = 32 * 1024 * 1024
    private static let maxStreamItemBytes: Int64 = 32 * 1024 * 1024 * 1024

    @Published var statusLabel: String = "Pronto al trasferimento diretto"
    @Published var peerName: String = ""
    @Published var licenseTier: SessionLicenseTier? = nil
    @Published var completedItems: Int = 0
    @Published var totalItems: Int = 0
    @Published var transferredBytesCount: Int64 = 0
    @Published var totalBytesCount: Int64 = 0
    @Published var speedMegabytesPerSec: Double = 0.0
    @Published var mergedContacts: Int = 0
    @Published var importedCalendars: Int = 0
    @Published var importedSms: Int = 0
    @Published var skippedDuplicates: Int = 0
    @Published var isCompleted: Bool = false
    @Published var errorMessage: String? = nil
    @Published var activePairingPin: String = ""
    @Published var discoveredBeacons: [DiscoveryBeaconPayload] = []
    @Published var bootstrapPortalUrl: String? = nil

    private var listener: NWListener?
    private var udpDiscoveryListener: NWListener?
    private var beaconBroadcastTask: Task<Void, Never>?
    private var activeSessionId: String = ""
    private var activeQrPayloadSnapshot: QrPairingPayload?
    private var bootstrapSecretToken: String? = nil
    private var symmetricKey: SymmetricKey?
    private var handshakeAuthenticated: Bool = false
    private var pinPairingConsumed: Bool = false
    private var pinFailedAttempts: Int = 0
    private var manifestItems: [String: ManifestItem] = [:]
    private var completedItemIds: Set<String> = []
    private var transferredBytes: Int64 = 0
    private var transferStartDate: Date = Date()

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
        completedItems = 0
        totalItems = 0
        transferredBytesCount = 0
        totalBytesCount = 0
        mergedContacts = 0
        importedCalendars = 0
        importedSms = 0
        skippedDuplicates = 0
        transferredBytes = 0
        isCompleted = false
        errorMessage = nil

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

    private func startHttpListener(port: UInt16, advertiseBonjour: Bool) {
        guard let nwPort = NWEndpoint.Port(rawValue: port),
              let nwListener = try? NWListener(using: .tcp, on: nwPort) else {
            errorMessage = "Impossibile aprire la porta locale \(port)."
            return
        }
        if advertiseBonjour {
            nwListener.service = NWListener.Service(name: UIDevice.current.name, type: "_directswitch._tcp")
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
            conn.start(queue: .global(qos: .userInitiated))
            let streamState = IncomingHttpStreamState()
            self.receiveHttpStream(on: conn, state: streamState)
        }
        nwListener.start(queue: .global(qos: .userInitiated))
        listener = nwListener
    }

    func stopReceiverServer() {
        UIApplication.shared.isIdleTimerDisabled = false
        beaconBroadcastTask?.cancel()
        beaconBroadcastTask = nil
        listener?.cancel()
        listener = nil
        activePairingPin = ""
        activeQrPayloadSnapshot = nil
        bootstrapSecretToken = nil
        bootstrapPortalUrl = nil
        handshakeAuthenticated = false
    }

    private nonisolated static func isAllowedPeerEndpoint(_ endpoint: NWEndpoint) -> Bool {
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

                        let isStreamingItem = state.method == "PUT" && state.path.hasPrefix("/v1/item/")
                        let maxAllowed = isStreamingItem ? Self.maxStreamItemBytes : Self.maxControlBodyBytes
                        if state.expectedBodyLength < 0 || state.expectedBodyLength > maxAllowed {
                            state.cleanupTempFile()
                            self.sendPlainJson(connection: connection, status: 413, json: #"{"error":"payload_too_large"}"#)
                            return
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

            if state.headersParsed && (state.receivedBodyBytes >= state.expectedBodyLength || isComplete) {
                state.closeHandle()
                let method = state.method
                let rawTarget = state.rawTarget
                let path = state.path
                let headers = state.headers
                let bodyData = state.inMemoryBody
                let bodyFileURL = state.tempBodyFileURL
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
            licenseTier = tier
            transferStartDate = Date()
            let enough = req.totalEstimatedBytes < max(0, free - 200 * 1024 * 1024)
            handshakeAuthenticated = enough
            statusLabel = enough
                ? "Connesso in modo sicuro a \(req.senderName)!"
                : "Spazio su iPhone insufficiente per completare il trasferimento."

            let resp = HandshakeResponse(
                accepted: enough,
                receiverName: UIDevice.current.name,
                receiverPlatform: .IOS,
                freeStorageBytes: free,
                licenseTier: tier,
                hasEnoughSpace: enough,
                statusMessage: enough ? "iPhone pronto a ricevere" : "Spazio su iPhone insufficiente"
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

            if fullAllowed && !manifest.calendarsPayload.isEmpty {
                _ = await iOSCalendarMigrator.requestAccessIfNeeded()
            }
            let insCal = fullAllowed ? iOSCalendarMigrator.importEvents(manifest.calendarsPayload) : 0
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

            let totalSkipped = skipContacts + skippedMediaDuplicates
            totalItems = acceptedItems.count
            totalBytesCount = acceptedItems.reduce(Int64(0)) { $0 + $1.sizeBytes }
            mergedContacts = insContacts
            importedCalendars = insCal
            importedSms = insSms
            skippedDuplicates = totalSkipped

            let resp = ManifestResponse(
                acceptedItemIds: acceptedItems.map(\.id),
                skippedDuplicateCount: totalSkipped,
                contactsMergedCount: insContacts,
                contactsSkippedDuplicates: skipContacts,
                calendarsImportedCount: insCal,
                smsImportedCount: insSms,
                gatedByCrossOsPreviewCount: gated
            )
            if let encoded = try? JSONEncoder().encode(resp),
               let jsonStr = String(data: encoded, encoding: .utf8) {
                sendEncryptedJson(connection: connection, status: 200, plainJson: jsonStr, key: key)
            }
            return
        }

        if method == "PUT" && path.hasPrefix("/v1/item/") {
            let itemId = String(path.dropFirst("/v1/item/".count))
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
            if item.category == .PHOTOS || item.category == .VIDEOS {
                savedOk = await iOSPhotoKitMigrator.saveMediaFileToLibrary(item: item, fileURL: tempPlainURL)
            } else {
                savedOk = iOSDocumentsSandboxBridge.saveDocumentFile(item: item, sourceFileURL: tempPlainURL)
            }
            guard savedOk else {
                sendPlainJson(connection: connection, status: 500, json: #"{"error":"save_failed"}"#)
                return
            }

            completedItemIds.insert(itemId)
            completedItems += 1
            transferredBytes += plainBytes
            transferredBytesCount = transferredBytes
            let elapsed = max(0.25, Date().timeIntervalSince(transferStartDate))
            speedMegabytesPerSec = (Double(transferredBytes) / (1024.0 * 1024.0)) / elapsed
            statusLabel = "Ricevuto \(item.fileName) (\(completedItems)/\(totalItems))"
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
            isCompleted = true
            statusLabel = "Trasferimento su iPhone completato!"
            let elapsedMs = Int64(max(1.0, Date().timeIntervalSince(transferStartDate) * 1000.0))
            let report = TransferCompletionReport(
                sessionId: activeSessionId,
                licenseTier: licenseTier ?? .INTRA_OS_FREE,
                transferredFilesCount: completedItems,
                transferredBytes: transferredBytes,
                mergedContactsCount: mergedContacts,
                importedCalendarsCount: importedCalendars,
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

    /// Avvia l'ascolto automatico UDP sulla porta 49444 per rilevare i beacon pubblici (`DiscoveryBeaconPayload`)
    /// del telefono ricevente senza esporre alcuna chiave segreta sulla rete.
    func startUdpAutoDiscovery() {
        stopUdpAutoDiscovery()
        discoveredBeacons.removeAll()
        guard let port = NWEndpoint.Port(rawValue: 49444),
              let udpListener = try? NWListener(using: .udp, on: port) else { return }
        udpListener.newConnectionHandler = { [weak self] conn in
            conn.start(queue: .global(qos: .userInitiated))
            conn.receiveMessage { data, _, _, _ in
                if let d = data,
                   let str = String(data: d, encoding: .utf8),
                   let rawBeacon = try? DiscoveryBeaconPayload.fromJson(str) {
                    let safeIps = rawBeacon.ips.filter { DirectSwitchLocalNetwork.isLocalIPv4($0) }
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
                        Task { @MainActor in
                            guard let self else { return }
                            if let idx = self.discoveredBeacons.firstIndex(where: { $0.sessionId == sanitized.sessionId }) {
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
    }

    func stopUdpAutoDiscovery() {
        udpDiscoveryListener?.cancel()
        udpDiscoveryListener = nil
    }

    /// Scambia in modo autenticato il PIN a 6 cifre mostrato sul ricevente con il `QrPairingPayload` completo.
    func pairWithBeaconUsingPin(beacon: DiscoveryBeaconPayload, pin: String) async throws -> QrPairingPayload {
        let cleanPin = pin.filter { $0.isNumber }
        guard cleanPin.count == 6 else {
            throw NSError(domain: "DirectSwitch", code: -20, userInfo: [NSLocalizedDescriptionKey: "Inserisci il codice PIN a 6 cifre mostrato sul nuovo telefono."])
        }
        guard let reachableIp = await findReachableIp(ips: beacon.ips, port: beacon.port) else {
            throw NSError(domain: "DirectSwitch", code: -21, userInfo: [NSLocalizedDescriptionKey: "Impossibile raggiungere \(beacon.receiverName) sulla rete Wi-Fi locale."])
        }
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

    /// Modalità Mittente (iPhone -> Android oppure iPhone -> iPhone) con cifratura e upload streaming su disco.
    func executeSenderTransfer(
        qrPayload: QrPairingPayload,
        includeContacts: Bool,
        includePhotos: Bool = true,
        includeVideos: Bool = true,
        includeCalendars: Bool,
        pickedDocuments: [(ManifestItem, URL)] = []
    ) async {
        do {
            errorMessage = nil
            isCompleted = false
            transferredBytesCount = 0
            totalBytesCount = 0
            UIApplication.shared.isIdleTimerDisabled = true
            defer { UIApplication.shared.isIdleTimerDisabled = false }

            let hotspotFallbackHint = await joinAndroidHotspotIfPresent(payload: qrPayload)
            statusLabel = "Ricerca canale diretto verso \(qrPayload.receiverName)..."

            guard let reachableIp = await findReachableIp(ips: qrPayload.ips, port: qrPayload.port) else {
                errorMessage = hotspotFallbackHint
                    ?? "Impossibile raggiungere \(qrPayload.receiverName). Verifica che i due telefoni siano sulla stessa rete Wi-Fi o Hotspot."
                return
            }
            let baseUrl = "http://\(reachableIp):\(qrPayload.port)"
            let key = try DirectSwitchCrypto.deriveSessionSymmetricKey(sessionKeyHex: qrPayload.sessionKeyHex)

            if includeContacts { _ = await iOSContactsSmartMerger.requestAccessIfNeeded() }
            if includeCalendars { _ = await iOSCalendarMigrator.requestAccessIfNeeded() }

            let contacts = includeContacts ? iOSContactsSmartMerger.readAllContacts() : []
            let calendars = includeCalendars ? iOSCalendarMigrator.readEvents() : []
            let scannedAssets = await iOSPhotoKitMigrator.scanLibraryAssets(
                includePhotos: includePhotos,
                includeVideos: includeVideos
            )
            let allItems = scannedAssets.map(\.0) + pickedDocuments.map(\.0)
            let estimatedBytes = allItems.reduce(Int64(0)) { $0 + $1.sizeBytes }

            let hsReq = HandshakeRequest(
                sessionId: qrPayload.sessionId,
                senderName: UIDevice.current.name,
                senderPlatform: .IOS,
                senderHasPro: iOSLicenseStore.isLocalProUnlocked,
                senderHasCloudSavePro: iOSLicenseStore.hasVerifiedCloudSaveProEntitlement,
                totalEstimatedBytes: estimatedBytes
            )
            let hsRespData = try await postEncryptedJson(url: "\(baseUrl)/v1/handshake", payload: hsReq, key: key)
            let hsResp = try JSONDecoder().decode(HandshakeResponse.self, from: hsRespData)
            peerName = hsResp.receiverName
            licenseTier = hsResp.licenseTier

            guard hsResp.accepted && hsResp.hasEnoughSpace else {
                errorMessage = hsResp.statusMessage.isEmpty
                    ? "Spazio di archiviazione insufficiente su \(hsResp.receiverName)."
                    : hsResp.statusMessage
                statusLabel = "Trasferimento annullato: spazio insufficiente sul ricevente."
                return
            }

            let manifest = TransferManifest(
                sessionId: qrPayload.sessionId,
                senderPlatform: .IOS,
                items: allItems,
                contactsPayload: contacts,
                calendarsPayload: calendars
            )
            let mfRespData = try await postEncryptedJson(url: "\(baseUrl)/v1/manifest", payload: manifest, key: key)
            let mfResp = try JSONDecoder().decode(ManifestResponse.self, from: mfRespData)
            mergedContacts = mfResp.contactsMergedCount
            importedCalendars = mfResp.calendarsImportedCount
            importedSms = mfResp.smsImportedCount
            skippedDuplicates = mfResp.skippedDuplicateCount

            let acceptedSet = Set(mfResp.acceptedItemIds)
            let assetsToUpload = scannedAssets.filter { acceptedSet.contains($0.0.id) }
            let docsToUpload = pickedDocuments.filter { acceptedSet.contains($0.0.id) }

            totalItems = assetsToUpload.count + docsToUpload.count
            totalBytesCount = assetsToUpload.reduce(Int64(0)) { $0 + $1.0.sizeBytes }
                + docsToUpload.reduce(Int64(0)) { $0 + $1.0.sizeBytes }
            completedItems = 0
            let startTime = Date()
            var uploadedBytes: Int64 = 0

            // 1. Upload streaming Foto & Video 4K (esportati e cifrati su file temporanei a blocchi da 4 MiB)
            for (item, phAsset) in assetsToUpload {
                statusLabel = "Invio \(item.fileName) (\(completedItems + 1)/\(totalItems))..."
                guard let plainTempURL = await iOSPhotoKitMigrator.exportAssetToTempFile(phAsset) else { continue }
                let sentBytes = try await encryptAndStreamFileItem(
                    item: item,
                    plainFileURL: plainTempURL,
                    deletePlainAfter: true,
                    baseUrl: baseUrl,
                    key: key
                )
                completedItems += 1
                uploadedBytes += sentBytes
                transferredBytesCount = uploadedBytes
                let elapsed = max(0.25, Date().timeIntervalSince(startTime))
                speedMegabytesPerSec = (Double(uploadedBytes) / (1024.0 * 1024.0)) / elapsed
            }

            // 2. Upload streaming Documenti & Archivi WhatsApp selezionati dall'utente o ricevuti da Share Sheet
            for (item, docURL) in docsToUpload {
                statusLabel = "Invio \(item.fileName) (\(completedItems + 1)/\(totalItems))..."
                let sentBytes = try await encryptAndStreamFileItem(
                    item: item,
                    plainFileURL: docURL,
                    deletePlainAfter: true,
                    baseUrl: baseUrl,
                    key: key
                )
                completedItems += 1
                uploadedBytes += sentBytes
                transferredBytesCount = uploadedBytes
                let elapsed = max(0.25, Date().timeIntervalSince(startTime))
                speedMegabytesPerSec = (Double(uploadedBytes) / (1024.0 * 1024.0)) / elapsed
            }

            let completeData = try await postEncryptedJson(
                url: "\(baseUrl)/v1/complete",
                payload: ["sessionId": qrPayload.sessionId],
                key: key
            )
            if let report = try? JSONDecoder().decode(TransferCompletionReport.self, from: completeData) {
                mergedContacts = report.mergedContactsCount
                importedCalendars = report.importedCalendarsCount
                importedSms = report.importedSmsCount
                skippedDuplicates = report.skippedDuplicatesCount
            }
            statusLabel = "Trasferimento da iPhone a \(hsResp.receiverName) completato!"
            isCompleted = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func encryptAndStreamFileItem(
        item: ManifestItem,
        plainFileURL: URL,
        deletePlainAfter: Bool,
        baseUrl: String,
        key: SymmetricKey
    ) async throws -> Int64 {
        let tempEncURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ds_tx_\(UUID().uuidString).csgcm1")
        defer {
            try? FileManager.default.removeItem(at: tempEncURL)
            if deletePlainAfter {
                try? FileManager.default.removeItem(at: plainFileURL)
            }
        }

        let (plainBytes, sha256Hex) = try await Task.detached(priority: .userInitiated) {
            try DirectSwitchCrypto.encryptFileCSGCM1(inputURL: plainFileURL, outputURL: tempEncURL, key: key)
        }.value

        guard let putUrl = URL(string: "\(baseUrl)/v1/item/\(item.id)") else {
            throw NSError(domain: "DirectSwitch", code: -13, userInfo: [NSLocalizedDescriptionKey: "URL upload non valido"])
        }
        let encAttrs = try? FileManager.default.attributesOfItem(atPath: tempEncURL.path)
        let encSize = (encAttrs?[.size] as? Int64) ?? (encAttrs?[.size] as? NSNumber)?.int64Value ?? 0

        var putReq = URLRequest(url: putUrl, timeoutInterval: 600.0)
        putReq.httpMethod = "PUT"
        putReq.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        putReq.setValue("\(plainBytes)", forHTTPHeaderField: "X-DS-Plain-Length")
        putReq.setValue(sha256Hex, forHTTPHeaderField: "X-DS-Sha256")
        if encSize > 0 {
            putReq.setValue("\(encSize)", forHTTPHeaderField: "Content-Length")
        }

        let (_, resp) = try await URLSession.shared.upload(for: putReq, fromFile: tempEncURL)
        guard let httpResp = resp as? HTTPURLResponse, httpResp.statusCode == 200 else {
            throw NSError(domain: "DirectSwitch", code: -12, userInfo: [NSLocalizedDescriptionKey: "Errore invio \(item.fileName)"])
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
                throw NSError(domain: "DirectSwitch", code: 401, userInfo: [NSLocalizedDescriptionKey: "PIN o chiave di sessione non validi."])
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
