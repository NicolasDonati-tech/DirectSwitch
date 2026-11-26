import Foundation
import CryptoKit
import ImageIO
import UniformTypeIdentifiers

// MARK: - 1. Guardia Termica Adattiva (iOS ProcessInfo.thermalState)

enum ThermalGuardState: String, Codable, Sendable {
    case normal = "NORMAL"
    case warmThrottle = "WARM_THROTTLE"
    case criticalCooldown = "CRITICAL_COOLDOWN"
}

enum iOSThermalGuardMonitor {
    static func evaluate(state: ProcessInfo.ThermalState = ProcessInfo.processInfo.thermalState) -> ThermalGuardState {
        switch state {
        case .critical:
            return .criticalCooldown
        case .serious:
            return .warmThrottle
        case .nominal, .fair:
            return .normal
        @unknown default:
            return .normal
        }
    }
}

// MARK: - 2. Smart Clean Pre-Migrazione (Merge Contatti E.164 + Dedup SHA-256 + Filtro Screenshot)

struct SmartCleanOptions: Codable, Equatable, Sendable {
    var mergeDuplicateContacts: Bool = true
    var skipExactDuplicatePhotosSha256: Bool = false
    var skipOldScreenshotsOlderThanMonths: Int = 0
}

struct SmartCleanMediaResult<T> {
    let kept: [T]
    let skippedDuplicatesCount: Int
    let skippedOldScreenshotsCount: Int
    let savedBytes: Int64
}

enum SmartCleanPreTransferEngine {

    static func normalizePhoneE164(_ raw: String, defaultCountryPrefix: String = "+39") -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        let digits = trimmed.filter(\.isNumber)
        if digits.count < 5 { return digits }
        if trimmed.hasPrefix("+") { return "+\(digits)" }
        if trimmed.hasPrefix("00") && digits.count > 4 {
            return "+\(digits.dropFirst(2))"
        }
        if defaultCountryPrefix == "+39" && (digits.count == 9 || digits.count == 10) && (digits.hasPrefix("3") || digits.hasPrefix("0")) {
            return "+39\(digits)"
        }
        return "+\(digits)"
    }

    static func mergeDuplicateContacts(_ contacts: [ContactTransferRecord]) -> (merged: [ContactTransferRecord], mergedDuplicatesCount: Int) {
        if contacts.count <= 1 { return (contacts, 0) }
        let n = contacts.count
        var parent = Array(0..<n)

        func find(_ x: Int) -> Int {
            var cur = x
            while parent[cur] != cur {
                parent[cur] = parent[parent[cur]]
                cur = parent[cur]
            }
            return cur
        }

        func union(_ a: Int, _ b: Int) {
            let ra = find(a)
            let rb = find(b)
            if ra != rb { parent[rb] = ra }
        }

        var phoneOwner: [String: Int] = [:]
        var nameEmailOwner: [String: Int] = [:]

        for i in 0..<n {
            let c = contacts[i]
            let allPhones = c.phones + (c.labeledPhones ?? []).map(\.value)
            for p in allPhones {
                let norm = normalizePhoneE164(p)
                guard norm.count >= 7 else { continue }
                if let prev = phoneOwner[norm] {
                    union(prev, i)
                } else {
                    phoneOwner[norm] = i
                }
            }
            let normName = c.displayName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let allEmails = c.emails + (c.labeledEmails ?? []).map(\.value)
            if !normName.isEmpty {
                for em in allEmails {
                    let cleanEm = em.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                    guard !cleanEm.isEmpty else { continue }
                    let key = "\(normName)|\(cleanEm)"
                    if let prev = nameEmailOwner[key] {
                        union(prev, i)
                    } else {
                        nameEmailOwner[key] = i
                    }
                }
            }
        }

        var groupOrder: [Int] = []
        var groups: [Int: [ContactTransferRecord]] = [:]
        for i in 0..<n {
            let root = find(i)
            if groups[root] == nil { groupOrder.append(root) }
            groups[root, default: []].append(contacts[i])
        }

        var mergedDuplicates = 0
        var result: [ContactTransferRecord] = []
        result.reserveCapacity(groupOrder.count)

        for root in groupOrder {
            guard let group = groups[root], let first = group.first else { continue }
            if group.count == 1 {
                result.append(first)
                continue
            }
            mergedDuplicates += (group.count - 1)

            var seenPhoneKeys = Set<String>()
            var outPhones: [String] = []
            var seenEmails = Set<String>()
            var outEmails: [String] = []
            var seenLabeledPhones = Set<String>()
            var outLabeledPhones: [LabeledValueRecord] = []
            var seenLabeledEmails = Set<String>()
            var outLabeledEmails: [LabeledValueRecord] = []
            var seenUrls = Set<String>()
            var outUrls: [String] = []
            var seenAddresses = Set<String>()
            var outAddresses: [PostalAddressTransferRecord] = []
            var notes: [String] = []

            for c in group {
                for p in c.phones {
                    let trimmed = p.trimmingCharacters(in: .whitespacesAndNewlines)
                    let key = normalizePhoneE164(trimmed)
                    let effKey = key.isEmpty ? trimmed : key
                    if !effKey.isEmpty && seenPhoneKeys.insert(effKey).inserted {
                        outPhones.append(trimmed)
                    }
                }
                for lp in (c.labeledPhones ?? []) {
                    let trimmed = lp.value.trimmingCharacters(in: .whitespacesAndNewlines)
                    let key = normalizePhoneE164(trimmed)
                    let effKey = key.isEmpty ? trimmed : key
                    if !effKey.isEmpty && seenLabeledPhones.insert(effKey).inserted {
                        outLabeledPhones.append(lp)
                    }
                }
                for e in c.emails {
                    let trimmed = e.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty && seenEmails.insert(trimmed.lowercased()).inserted {
                        outEmails.append(trimmed)
                    }
                }
                for le in (c.labeledEmails ?? []) {
                    let k = le.value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                    if !k.isEmpty && seenLabeledEmails.insert(k).inserted {
                        outLabeledEmails.append(le)
                    }
                }
                for u in (c.urls ?? []) {
                    let trimmed = u.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty && seenUrls.insert(trimmed).inserted {
                        outUrls.append(trimmed)
                    }
                }
                for pa in (c.postalAddresses ?? []) {
                    let k = "\(pa.street)|\(pa.city)|\(pa.postalCode)".lowercased()
                    if seenAddresses.insert(k).inserted {
                        outAddresses.append(pa)
                    }
                }
                if let note = c.note?.trimmingCharacters(in: .whitespacesAndNewlines), !note.isEmpty, !notes.contains(note) {
                    notes.append(note)
                }
            }

            let bestName = group.max(by: { $0.displayName.count < $1.displayName.count })?.displayName ?? first.displayName
            result.append(
                ContactTransferRecord(
                    id: first.id,
                    displayName: bestName,
                    phones: outPhones,
                    emails: outEmails,
                    organization: group.compactMap(\.organization).first { !$0.trimmingCharacters(in: .whitespaces).isEmpty },
                    note: notes.isEmpty ? nil : notes.joined(separator: "\n"),
                    givenName: group.compactMap(\.givenName).first { !$0.isEmpty },
                    familyName: group.compactMap(\.familyName).first { !$0.isEmpty },
                    nickname: group.compactMap(\.nickname).first { !$0.isEmpty },
                    jobTitle: group.compactMap(\.jobTitle).first { !$0.isEmpty },
                    birthdayYear: group.compactMap(\.birthdayYear).first,
                    birthdayMonth: group.compactMap(\.birthdayMonth).first,
                    birthdayDay: group.compactMap(\.birthdayDay).first,
                    labeledPhones: outLabeledPhones.isEmpty ? nil : outLabeledPhones,
                    labeledEmails: outLabeledEmails.isEmpty ? nil : outLabeledEmails,
                    urls: outUrls.isEmpty ? nil : outUrls,
                    postalAddresses: outAddresses.isEmpty ? nil : outAddresses,
                    avatarJpegBase64: group.compactMap(\.avatarJpegBase64).first { !$0.isEmpty }
                )
            )
        }
        return (result, mergedDuplicates)
    }

    private static let screenshotTokens: [String] = [
        "screenshot",
        "screen_shot",
        "screen shot",
        "screencapture",
        "screen_capture",
        "screen capture",
        "schermata",
        "schermate",
        "capture d'écran",
        "capture d\u{2019}écran",
        "captures d'écran",
        "captures d\u{2019}écran",
        "capture d'ecran",
        "captures d'ecran",
        "capture_d_ecran"
    ]

    static func looksLikeScreenshotNameOrAlbum(fileName: String, albumOrFolder: String) -> Bool {
        let lowFile = fileName.lowercased()
        let lowAlbum = albumOrFolder.lowercased()
        return screenshotTokens.contains { token in
            lowFile.contains(token) || lowAlbum.contains(token)
        }
    }

    static func isOldScreenshot(
        fileName: String,
        albumOrFolder: String,
        capturedEpochMillis: Int64,
        nowMillis: Int64,
        olderThanMonths: Int,
        isScreenshotFlag: Bool = false
    ) -> Bool {
        guard olderThanMonths > 0, capturedEpochMillis > 0 else { return false }
        let isShot = isScreenshotFlag || looksLikeScreenshotNameOrAlbum(fileName: fileName, albumOrFolder: albumOrFolder)
        guard isShot else { return false }
        let thresholdMs = Int64(olderThanMonths) * 30 * 86_400_000
        return (nowMillis - capturedEpochMillis) > thresholdMs
    }

    static func filterMediaSmartClean<T>(
        entries: [T],
        options: SmartCleanOptions,
        nowMillis: Int64 = Int64(Date().timeIntervalSince1970 * 1000.0),
        itemOf: (T) -> ManifestItem,
        sha256Of: (T) -> String?
    ) -> SmartCleanMediaResult<T> {
        guard options.skipExactDuplicatePhotosSha256 || options.skipOldScreenshotsOlderThanMonths > 0 else {
            return SmartCleanMediaResult(kept: entries, skippedDuplicatesCount: 0, skippedOldScreenshotsCount: 0, savedBytes: 0)
        }
        var photoSizeCounts: [Int64: Int] = [:]
        if options.skipExactDuplicatePhotosSha256 {
            for entry in entries {
                let item = itemOf(entry)
                if item.category == .PHOTOS && item.sizeBytes > 0 {
                    photoSizeCounts[item.sizeBytes, default: 0] += 1
                }
            }
        }
        var kept: [T] = []
        kept.reserveCapacity(entries.count)
        var seenHashes = Set<String>()
        var skippedDups = 0
        var skippedShots = 0
        var savedBytes: Int64 = 0

        for entry in entries {
            let item = itemOf(entry)
            if options.skipOldScreenshotsOlderThanMonths > 0,
               item.category == .PHOTOS || item.category == .VIDEOS,
               isOldScreenshot(
                   fileName: item.fileName,
                   albumOrFolder: item.relativeAlbumOrFolder,
                   capturedEpochMillis: item.capturedEpochMillis,
                   nowMillis: nowMillis,
                   olderThanMonths: options.skipOldScreenshotsOlderThanMonths,
                   isScreenshotFlag: item.isScreenshot == true
               ) {
                skippedShots += 1
                savedBytes += item.sizeBytes
                continue
            }

            if options.skipExactDuplicatePhotosSha256 &&
               item.category == .PHOTOS &&
               (item.sizeBytes <= 0 || (photoSizeCounts[item.sizeBytes] ?? 0) > 1),
               let h = sha256Of(entry), !h.isEmpty {
                if !seenHashes.insert(h).inserted {
                    skippedDups += 1
                    savedBytes += item.sizeBytes
                    continue
                }
            }
            kept.append(entry)
        }
        return SmartCleanMediaResult(
            kept: kept,
            skippedDuplicatesCount: skippedDups,
            skippedOldScreenshotsCount: skippedShots,
            savedBytes: savedBytes
        )
    }

    static func computeFileSha256Hex(url: URL) -> String? {
        guard let fh = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? fh.close() }
        var hasher = SHA256()
        while autoreleasepool(invoking: {
            let chunk = try? fh.read(upToCount: 65536)
            if let chunk, !chunk.isEmpty {
                hasher.update(data: chunk)
                return true
            }
            return false
        }) {}
        let digest = hasher.finalize()
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - 3. Verifica Integrità Post-Migrazione & Diff

enum ReconciliationDiffCore {
    static func evaluate(
        sentItemIds: [String],
        expectedSha256ById: [String: String],
        committedHashesById: [String: String]
    ) -> ReconcileManifestResponse {
        var committed: [String] = []
        var missing: [String] = []
        var mismatch: [String] = []
        for id in sentItemIds {
            guard let rxHash = committedHashesById[id] else {
                missing.append(id)
                continue
            }
            if let exp = expectedSha256ById[id], !exp.isEmpty, exp.lowercased() != rxHash.lowercased() {
                mismatch.append(id)
            } else {
                committed.append(id)
            }
        }
        return ReconcileManifestResponse(
            committedIds: committed,
            missingIds: missing,
            hashMismatchIds: mismatch,
            totalVerified: committed.count
        )
    }
}

// MARK: - 4. Rilevamento AP Client Isolation + Fallback Hotspot Guidato

struct NetworkDiagnosticVerdict: Equatable, Sendable {
    let likelyApClientIsolation: Bool
    let subnetMismatch: Bool
    let title: String
    let description: String
    let guidanceSteps: [String]
}

enum NetworkIsolationDiagnostics {
    private static func pick(_ it: String, en: String, fr: String, code: String) -> String {
        switch code {
        case "en": return en
        case "fr": return fr
        default: return it
        }
    }

    static func analyzePairingFailure(
        localIp: String?,
        targetIps: [String],
        isWifiConnected: Bool,
        errorMessage: String,
        languageCode: String = DirectSwitchLocalizationStore.currentEffectiveCodeNonisolated()
    ) -> NetworkDiagnosticVerdict {
        let localParts = localIp?.split(separator: ".").map(String.init)
        let targetPartsList = targetIps.map { $0.split(separator: ".").map(String.init) }.filter { $0.count == 4 }
        let same24Subnet: Bool = {
            guard let lp = localParts, lp.count == 4 else { return false }
            return targetPartsList.contains { $0[0] == lp[0] && $0[1] == lp[1] && $0[2] == lp[2] }
        }()
        let subnetDiffers = (localParts?.count == 4) && !targetPartsList.isEmpty && !same24Subnet
        let errLow = errorMessage.lowercased()
        let isTimeoutOrBlocked = errLow.contains("timeout") ||
            errLow.contains("timed out") ||
            errLow.contains("refused") ||
            errLow.contains("raggiungere") ||
            errLow.contains("unreachable") ||
            errLow.contains("route") ||
            errLow.contains("impossibile") ||
            errLow.contains("collegarsi") ||
            errLow.contains("non si avvia") ||
            errLow.contains("connessione")

        if isWifiConnected && same24Subnet && isTimeoutOrBlocked, let lp = localParts {
            let subnetLabel = "\(lp[0]).\(lp[1]).\(lp[2]).x"
            return NetworkDiagnosticVerdict(
                likelyApClientIsolation: true,
                subnetMismatch: false,
                title: pick(
                    "Router Wi-Fi con AP Client Isolation rilevato",
                    en: "Wi-Fi router with AP Client Isolation detected",
                    fr: "Routeur Wi-Fi avec isolation client AP détecté",
                    code: languageCode
                ),
                description: pick(
                    "Entrambi i telefoni sono sulla stessa rete (\(subnetLabel)) ma il router blocca la comunicazione diretta tra dispositivi.",
                    en: "Both phones are on the same network (\(subnetLabel)), but the router blocks direct device-to-device traffic.",
                    fr: "Les deux téléphones sont sur le même réseau (\(subnetLabel)), mais le routeur bloque la communication directe.",
                    code: languageCode
                ),
                guidanceSteps: [
                    pick(
                        "1. Sul telefono ricevente attiva l'Hotspot Personale (non consuma Giga perché i dati viaggiano in locale).",
                        en: "1. Turn on Personal Hotspot on the receiving phone (uses 0 mobile data; transfer stays local).",
                        fr: "1. Activez le Partage de connexion sur le téléphone récepteur (ne consomme aucune donnée mobile).",
                        code: languageCode
                    ),
                    pick(
                        "2. Collega questo iPhone al Wi-Fi dell'Hotspot.",
                        en: "2. Connect this iPhone to the Hotspot Wi-Fi.",
                        fr: "2. Connectez cet iPhone au Wi-Fi du partage de connexion.",
                        code: languageCode
                    ),
                    pick(
                        "3. Tocca Riprova o inquadra di nuovo il QR: la velocità salirà al massimo.",
                        en: "3. Tap Retry or scan the QR again for maximum speed.",
                        fr: "3. Touchez Réessayer ou scannez à nouveau le QR pour une vitesse maximale.",
                        code: languageCode
                    )
                ]
            )
        }
        if subnetDiffers {
            let peerIp = targetIps.first ?? ""
            return NetworkDiagnosticVerdict(
                likelyApClientIsolation: false,
                subnetMismatch: true,
                title: pick(
                    "I due telefoni sono su reti Wi-Fi diverse",
                    en: "Both phones are on different Wi-Fi networks",
                    fr: "Les deux téléphones sont sur des réseaux Wi-Fi différents",
                    code: languageCode
                ),
                description: pick(
                    "Questo iPhone è su una sottorete diversa da \(peerIp).",
                    en: "This iPhone is on a different subnet from \(peerIp).",
                    fr: "Cet iPhone est sur un sous-réseau différent de \(peerIp).",
                    code: languageCode
                ),
                guidanceSteps: [
                    pick(
                        "1. Collega entrambi i telefoni alla stessa rete Wi-Fi, oppure",
                        en: "1. Connect both phones to the same Wi-Fi network, or",
                        fr: "1. Connectez les deux téléphones au même Wi-Fi, ou",
                        code: languageCode
                    ),
                    pick(
                        "2. Collega questo iPhone direttamente all'Hotspot Personale del nuovo telefono.",
                        en: "2. Connect this iPhone directly to the new phone's Personal Hotspot.",
                        fr: "2. Connectez cet iPhone directement au partage de connexion du nouveau téléphone.",
                        code: languageCode
                    )
                ]
            )
        }
        return NetworkDiagnosticVerdict(
            likelyApClientIsolation: false,
            subnetMismatch: false,
            title: pick(
                "Connessione diretta non riuscita",
                en: "Direct connection failed",
                fr: "Échec de la connexion directe",
                code: languageCode
            ),
            description: pick(
                "Controlla che Rete locale sia attiva in Impostazioni → DirectSwitch e disattiva eventuali VPN.",
                en: "Check that Local Network is enabled in Settings → DirectSwitch and turn off any VPN.",
                fr: "Vérifiez que Réseau local est activé dans Réglages → DirectSwitch et désactivez tout VPN.",
                code: languageCode
            ),
            guidanceSteps: [
                pick(
                    "1. Disattiva temporaneamente eventuali VPN su entrambi i telefoni.",
                    en: "1. Temporarily disable any VPN on both phones.",
                    fr: "1. Désactivez temporairement tout VPN sur les deux téléphones.",
                    code: languageCode
                ),
                pick(
                    "2. In alternativa usa l'Hotspot Personale diretto tra i due dispositivi.",
                    en: "2. Alternatively, connect directly via Personal Hotspot between both devices.",
                    fr: "2. Sinon, utilisez le Partage de connexion direct entre les deux appareils.",
                    code: languageCode
                )
            ]
        )
    }
}

// MARK: - 5. Compatibilità Media HEIC -> JPEG preservando EXIF

enum iOSHeicCompatibilityConverter {
    private static let heicExts: Set<String> = ["heic", "heif"]
    private static let decodeLock = NSLock()

    static func isHeicPhoto(fileName: String, mimeType: String) -> Bool {
        let ext = URL(fileURLWithPath: fileName).pathExtension.lowercased()
        let lowMime = mimeType.lowercased()
        return heicExts.contains(ext) || lowMime.contains("heic") || lowMime.contains("heif")
    }

    static func convertHeicToJpegPreservingExif(sourceURL: URL, destinationURL: URL) -> Bool {
        decodeLock.lock()
        defer { decodeLock.unlock() }
        let finalizedOk: Bool = autoreleasepool {
            guard let src = CGImageSourceCreateWithURL(sourceURL as CFURL, nil),
                  CGImageSourceGetCount(src) > 0,
                  let dest = CGImageDestinationCreateWithURL(destinationURL as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else {
                return false
            }
            let options: [CFString: Any] = [
                kCGImageDestinationLossyCompressionQuality: 0.92
            ]
            CGImageDestinationAddImageFromSource(dest, src, 0, options as CFDictionary)
            return CGImageDestinationFinalize(dest)
        }
        guard finalizedOk else { return false }
        let size = (try? FileManager.default.attributesOfItem(atPath: destinationURL.path)[.size] as? Int64) ?? 0
        return size > 0
    }
}

actor ThermalGuardCoordinator {
    private var currentState: ThermalGuardState = .normal
    private var cooldownUntil: Date? = nil
    private var itemCounter: Int = 0

    func checkThermalGate(
        onStateChange: @Sendable (ThermalGuardState, String?) async -> Void
    ) async -> Int {
        itemCounter += 1
        if let until = cooldownUntil, Date() < until {
            while Date() < until && !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
            cooldownUntil = nil
            let next = iOSThermalGuardMonitor.evaluate()
            currentState = next
            let banner: String? = next == .criticalCooldown
                ? "Raffreddamento termico in corso (pausa automatica 45s)..."
                : (next == .warmThrottle ? "Temperatura elevata — 1 flusso alla volta" : nil)
            await onStateChange(next, banner)
            return next != .normal ? 3 : 1
        }
        if itemCounter == 1 || itemCounter % 5 == 0 || currentState != .normal {
            let next = iOSThermalGuardMonitor.evaluate()
            if next != currentState || next == .criticalCooldown {
                currentState = next
                if next == .criticalCooldown {
                    let until = Date().addingTimeInterval(45.0)
                    cooldownUntil = until
                    await onStateChange(.criticalCooldown, "Raffreddamento termico in corso (pausa automatica 45s)...")
                    while Date() < until && !Task.isCancelled {
                        try? await Task.sleep(nanoseconds: 1_000_000_000)
                    }
                    cooldownUntil = nil
                    let afterCool = iOSThermalGuardMonitor.evaluate()
                    currentState = afterCool
                    let banner: String? = afterCool == .criticalCooldown
                        ? "Raffreddamento termico in corso (pausa automatica 45s)..."
                        : (afterCool == .warmThrottle ? "Temperatura elevata — 1 flusso alla volta" : nil)
                    await onStateChange(afterCool, banner)
                    return afterCool != .normal ? 3 : 1
                } else if next == .warmThrottle {
                    await onStateChange(.warmThrottle, "Temperatura elevata — 1 flusso alla volta")
                } else {
                    await onStateChange(.normal, nil)
                }
            }
        }
        return currentState != .normal ? 3 : 1
    }
}
