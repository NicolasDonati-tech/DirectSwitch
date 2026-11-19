//
//  DirectSwitchAdvancedEngines.swift
//  DirectSwitch-iOS
//
//  Created by Nicolas Donati.
//  Copyright © 2026 Nicolas Donati. Tutti i diritti riservati.
//

import Foundation
import UIKit
import CryptoKit
import Contacts
import Photos
import ImageIO
import AVFoundation
import CoreMedia
import UniformTypeIdentifiers

// ============================================================================
// 1. TIMELINE & CODEC HEALER (Ricostruzione data reale + EXIF + Android Motion -> Apple Live Photo)
// ============================================================================

struct HealedTimelineResult: Equatable, Sendable {
    let epochMillis: Int64
    let wasHealedFromFilename: Bool
    let sourcePattern: String?
}

enum MediaTimelineHealer {
    private static let oneDayMs: Int64 = 86_400_000
    private static let minYear = 2000
    private static let maxYear = 2035

    private static let whatsappLongRegex = try! NSRegularExpression(
        pattern: #"WhatsApp\s+(?:Image|Video|Audio)\s+(\d{4})-(\d{2})-(\d{2})\s+(?:at|alle)\s+(\d{1,2})\.(\d{2})\.(\d{2})"#,
        options: [.caseInsensitive]
    )
    private static let whatsappWaRegex = try! NSRegularExpression(
        pattern: #"(?:IMG|VID|PTT|AUD|DOC)-(\d{4})(\d{2})(\d{2})-WA\d+"#,
        options: [.caseInsensitive]
    )
    private static let ymdHmsDashedRegex = try! NSRegularExpression(
        pattern: #"(?:^|[_\-\s])(\d{4})[-.](\d{2})[-.](\d{2})[_\-\sT](\d{2})[-.:](\d{2})[-.:](\d{2})(?:\D|$)"#
    )
    private static let ymdHmsCompactRegex = try! NSRegularExpression(
        pattern: #"(?:^|[_\-\s])(\d{4})(\d{2})(\d{2})[_\-T](\d{2})(\d{2})(\d{2})(?:\D|$)"#
    )
    private static let ymdDashedOnlyRegex = try! NSRegularExpression(
        pattern: #"(?:^|[_\-\s])(\d{4})-(\d{2})-(\d{2})(?:\D|$)"#
    )

    static func extractTimestampFromFilename(
        _ fileName: String,
        nowEpochMillis: Int64 = Int64(Date().timeIntervalSince1970 * 1000.0)
    ) -> (Int64, String)? {
        let base = URL(fileURLWithPath: fileName).lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !base.isEmpty else { return nil }
        let maxAllowed = nowEpochMillis + oneDayMs
        let nsRange = NSRange(base.startIndex..., in: base)

        func groupInt(_ m: NSTextCheckingResult, _ idx: Int) -> Int? {
            guard idx < m.numberOfRanges, let r = Range(m.range(at: idx), in: base) else { return nil }
            return Int(base[r])
        }

        if let m = whatsappLongRegex.firstMatch(in: base, range: nsRange),
           let y = groupInt(m, 1), let mo = groupInt(m, 2), let d = groupInt(m, 3),
           let h = groupInt(m, 4), let mi = groupInt(m, 5), let s = groupInt(m, 6),
           let ts = buildEpochMillis(year: y, month: mo, day: d, hour: h, minute: mi, second: s),
           ts <= maxAllowed {
            return (ts, "whatsapp_long")
        }

        if let m = whatsappWaRegex.firstMatch(in: base, range: nsRange),
           let y = groupInt(m, 1), let mo = groupInt(m, 2), let d = groupInt(m, 3),
           let ts = buildEpochMillis(year: y, month: mo, day: d, hour: 12, minute: 0, second: 0),
           ts <= maxAllowed {
            return (ts, "whatsapp_wa")
        }

        if let m = ymdHmsDashedRegex.firstMatch(in: base, range: nsRange),
           let y = groupInt(m, 1), let mo = groupInt(m, 2), let d = groupInt(m, 3),
           let h = groupInt(m, 4), let mi = groupInt(m, 5), let s = groupInt(m, 6),
           let ts = buildEpochMillis(year: y, month: mo, day: d, hour: h, minute: mi, second: s),
           ts <= maxAllowed {
            return (ts, "ymd_hms_dashed")
        }

        if let m = ymdHmsCompactRegex.firstMatch(in: base, range: nsRange),
           let y = groupInt(m, 1), let mo = groupInt(m, 2), let d = groupInt(m, 3),
           let h = groupInt(m, 4), let mi = groupInt(m, 5), let s = groupInt(m, 6),
           let ts = buildEpochMillis(year: y, month: mo, day: d, hour: h, minute: mi, second: s),
           ts <= maxAllowed {
            return (ts, "ymd_hms_compact")
        }

        if let m = ymdDashedOnlyRegex.firstMatch(in: base, range: nsRange),
           let y = groupInt(m, 1), let mo = groupInt(m, 2), let d = groupInt(m, 3),
           let ts = buildEpochMillis(year: y, month: mo, day: d, hour: 12, minute: 0, second: 0),
           ts <= maxAllowed {
            return (ts, "ymd_dashed")
        }

        let stem = URL(fileURLWithPath: base).deletingPathExtension().lastPathComponent
        if stem.count == 13, stem.allSatisfy(\.isNumber), let ts = Int64(stem), ts >= 946_684_800_000, ts <= maxAllowed {
            return (ts, "unix_ms")
        }
        if stem.count == 10, stem.allSatisfy(\.isNumber), let sec = Int64(stem) {
            let ts = sec * 1000
            if ts >= 946_684_800_000 && ts <= maxAllowed {
                return (ts, "unix_sec")
            }
        }
        return nil
    }

    static func resolveBestCaptureEpochMillis(
        fileName: String,
        reportedEpochMillis: Int64,
        nowEpochMillis: Int64 = Int64(Date().timeIntervalSince1970 * 1000.0)
    ) -> HealedTimelineResult {
        let fromName = extractTimestampFromFilename(fileName, nowEpochMillis: nowEpochMillis)
        if reportedEpochMillis <= 0 {
            if let hit = fromName {
                return HealedTimelineResult(epochMillis: hit.0, wasHealedFromFilename: true, sourcePattern: hit.1)
            }
            return HealedTimelineResult(epochMillis: 0, wasHealedFromFilename: false, sourcePattern: nil)
        }
        if let hit = fromName {
            let looksLikeCopyDate = abs(nowEpochMillis - reportedEpochMillis) <= oneDayMs
            let filenameOlder = hit.0 < reportedEpochMillis - (2 * oneDayMs)
            if looksLikeCopyDate && filenameOlder {
                return HealedTimelineResult(epochMillis: hit.0, wasHealedFromFilename: true, sourcePattern: hit.1)
            }
        }
        return HealedTimelineResult(epochMillis: reportedEpochMillis, wasHealedFromFilename: false, sourcePattern: nil)
    }

    static func formatExifDateTime(_ epochMillis: Int64) -> String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "yyyy:MM:dd HH:mm:ss"
        return df.string(from: Date(timeIntervalSince1970: TimeInterval(epochMillis) / 1000.0))
    }

    /// Inietta `DateTimeOriginal` in una foto statica se assente o ricostruita dal nome file,
    /// restituendo l'URL temporaneo aggiornato (o `nil` se non necessario).
    static func injectExifDateIntoImageIfNeeded(
        sourceURL: URL,
        epochMillis: Int64,
        forceOverwrite: Bool
    ) -> URL? {
        guard epochMillis > 0,
              let src = CGImageSourceCreateWithURL(sourceURL as CFURL, nil),
              let uti = CGImageSourceGetType(src) else {
            return nil
        }
        let existingProps = (CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any]) ?? [:]
        var exifDict = (existingProps[kCGImagePropertyExifDictionary] as? [CFString: Any]) ?? [:]
        let existingOrig = (exifDict[kCGImagePropertyExifDateTimeOriginal] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !forceOverwrite && !existingOrig.isEmpty {
            return nil
        }
        let formatted = formatExifDateTime(epochMillis)
        exifDict[kCGImagePropertyExifDateTimeOriginal] = formatted
        exifDict[kCGImagePropertyExifDateTimeDigitized] = formatted

        var tiffDict = (existingProps[kCGImagePropertyTIFFDictionary] as? [CFString: Any]) ?? [:]
        tiffDict[kCGImagePropertyTIFFDateTime] = formatted

        var merged = existingProps
        merged[kCGImagePropertyExifDictionary] = exifDict
        merged[kCGImagePropertyTIFFDictionary] = tiffDict

        let ext = sourceURL.pathExtension.isEmpty ? "jpg" : sourceURL.pathExtension
        let outURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ds_healed_exif_\(UUID().uuidString).\(ext)")
        guard let dest = CGImageDestinationCreateWithURL(outURL as CFURL, uti, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImageFromSource(dest, src, 0, merged as CFDictionary)
        guard CGImageDestinationFinalize(dest) else {
            try? FileManager.default.removeItem(at: outURL)
            return nil
        }
        return outURL
    }

    private static func buildEpochMillis(year: Int, month: Int, day: Int, hour: Int, minute: Int, second: Int) -> Int64? {
        guard (minYear...maxYear).contains(year),
              (1...12).contains(month),
              (1...31).contains(day),
              (0...23).contains(hour),
              (0...59).contains(minute),
              (0...59).contains(second) else {
            return nil
        }
        var comps = DateComponents()
        comps.calendar = Calendar(identifier: .gregorian)
        comps.year = year
        comps.month = month
        comps.day = day
        comps.hour = hour
        comps.minute = minute
        comps.second = second
        guard let dt = comps.calendar?.date(from: comps) else { return nil }
        let check = comps.calendar?.dateComponents([.year, .month, .day], from: dt)
        guard check?.year == year, check?.month == month, check?.day == day else { return nil }
        return Int64(dt.timeIntervalSince1970 * 1000.0)
    }
}

private final class DirectSwitchLiveCopyState: @unchecked Sendable {
    var finished = false
}

/// Prepara uno still + video `.mp4` provenienti da una Android Motion Photo con i tag QuickTime/MakerApple
/// necessari affinché `PHAssetCreationRequest` li salvi come vera Apple Live Photo nativa.
enum iOSCrossOsLiveMotionBridge {
    static func prepareCrossOsLivePhotoPairIfNeeded(
        stillURL: URL,
        liveVideoURL: URL
    ) async -> (stillURL: URL, movURL: URL, cleanupDir: URL)? {
        let ext = liveVideoURL.pathExtension.lowercased()
        // Se è già un .mov nativo iPhone -> iPhone con content identifier Apple, non serve ri-taggarlo
        if ext == "mov", await quickTimeHasContentIdentifier(liveVideoURL) {
            return nil
        }
        let workDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ds_live_pair_\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)

        let contentId = UUID().uuidString.uppercased()
        let stillExt = stillURL.pathExtension.isEmpty ? "jpg" : stillURL.pathExtension
        let stampedStill = workDir.appendingPathComponent("still.\(stillExt)")
        let stampedMov = workDir.appendingPathComponent("motion.mov")

        guard stampStillWithAppleContentId(srcURL: stillURL, dstURL: stampedStill, contentId: contentId) else {
            try? FileManager.default.removeItem(at: workDir)
            return nil
        }
        let movOk = await writePairedQuickTimeMov(srcVideoURL: liveVideoURL, dstMovURL: stampedMov, contentId: contentId)
        guard movOk else {
            try? FileManager.default.removeItem(at: workDir)
            return nil
        }
        return (stampedStill, stampedMov, workDir)
    }

    private static func quickTimeHasContentIdentifier(_ url: URL) async -> Bool {
        let asset = AVURLAsset(url: url)
        guard let meta = try? await asset.load(.metadata) else { return false }
        return meta.contains { item in
            (item.key as? String) == "com.apple.quicktime.content.identifier"
        }
    }

    private static func stampStillWithAppleContentId(srcURL: URL, dstURL: URL, contentId: String) -> Bool {
        guard let src = CGImageSourceCreateWithURL(srcURL as CFURL, nil),
              let uti = CGImageSourceGetType(src),
              let dest = CGImageDestinationCreateWithURL(dstURL as CFURL, uti, 1, nil) else {
            return false
        }
        var props = (CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any]) ?? [:]
        var maker = (props[kCGImagePropertyMakerAppleDictionary] as? [String: Any]) ?? [:]
        maker["17"] = contentId
        props[kCGImagePropertyMakerAppleDictionary] = maker
        CGImageDestinationAddImageFromSource(dest, src, 0, props as CFDictionary)
        return CGImageDestinationFinalize(dest)
    }

    private static func writePairedQuickTimeMov(srcVideoURL: URL, dstMovURL: URL, contentId: String) async -> Bool {
        try? FileManager.default.removeItem(at: dstMovURL)
        let asset = AVURLAsset(url: srcVideoURL)
        guard let tracks = try? await asset.load(.tracks),
              let videoTrack = tracks.first(where: { $0.mediaType == .video }),
              let duration = try? await asset.load(.duration),
              let reader = try? AVAssetReader(asset: asset),
              let writer = try? AVAssetWriter(outputURL: dstMovURL, fileType: .mov) else {
            return false
        }

        let idItem = AVMutableMetadataItem()
        idItem.key = "com.apple.quicktime.content.identifier" as NSString
        idItem.keySpace = .quickTimeMetadata
        idItem.value = contentId as NSString
        idItem.dataType = kCMMetadataBaseDataType_UTF8 as String
        writer.metadata = [idItem]

        let vFormatDesc = (try? await videoTrack.load(.formatDescriptions))?.first
        let vTransform = (try? await videoTrack.load(.preferredTransform)) ?? .identity
        let rVideo = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: nil)
        rVideo.alwaysCopiesSampleData = false
        let wVideo = AVAssetWriterInput(mediaType: .video, outputSettings: nil, sourceFormatHint: vFormatDesc)
        wVideo.expectsMediaDataInRealTime = false
        wVideo.transform = vTransform
        guard reader.canAdd(rVideo), writer.canAdd(wVideo) else { return false }
        reader.add(rVideo)
        writer.add(wVideo)

        var rAudioOpt: AVAssetReaderTrackOutput? = nil
        var wAudioOpt: AVAssetWriterInput? = nil
        if let audioTrack = tracks.first(where: { $0.mediaType == .audio }) {
            let aDesc = (try? await audioTrack.load(.formatDescriptions))?.first
            let rAudio = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: nil)
            rAudio.alwaysCopiesSampleData = false
            let wAudio = AVAssetWriterInput(mediaType: .audio, outputSettings: nil, sourceFormatHint: aDesc)
            wAudio.expectsMediaDataInRealTime = false
            if reader.canAdd(rAudio), writer.canAdd(wAudio) {
                reader.add(rAudio)
                writer.add(wAudio)
                rAudioOpt = rAudio
                wAudioOpt = wAudio
            }
        }

        let metaSpecs: [[String: Any]] = [[
            kCMMetadataFormatDescriptionMetadataSpecificationKey_Identifier as String: "mdta/com.apple.quicktime.still-image-time",
            kCMMetadataFormatDescriptionMetadataSpecificationKey_DataType as String: kCMMetadataBaseDataType_SInt8 as String
        ]]
        var metaFmt: CMFormatDescription? = nil
        CMMetadataFormatDescriptionCreateWithMetadataSpecifications(
            allocator: kCFAllocatorDefault,
            metadataType: kCMMetadataFormatType_Boxed,
            metadataSpecifications: metaSpecs as CFArray,
            formatDescriptionOut: &metaFmt
        )
        var metaAdaptor: AVAssetWriterInputMetadataAdaptor? = nil
        if let fmt = metaFmt {
            let wMeta = AVAssetWriterInput(mediaType: .metadata, outputSettings: nil, sourceFormatHint: fmt)
            let adaptor = AVAssetWriterInputMetadataAdaptor(assetWriterInput: wMeta)
            if writer.canAdd(wMeta) {
                writer.add(wMeta)
                metaAdaptor = adaptor
            }
        }

        guard reader.startReading(), writer.startWriting() else {
            reader.cancelReading()
            writer.cancelWriting()
            return false
        }
        writer.startSession(atSourceTime: .zero)

        if let adaptor = metaAdaptor {
            let durUs = max(100_000, Int64((duration.seconds.isFinite ? duration.seconds : 1.5) * 1_000_000.0))
            let ptsTime = CMTime(value: min(0, durUs - 33_333), timescale: 1_000_000)
            let frameDur = CMTime(value: 33_333, timescale: 1_000_000)
            let stillItem = AVMutableMetadataItem()
            stillItem.key = "com.apple.quicktime.still-image-time" as NSString
            stillItem.keySpace = .quickTimeMetadata
            stillItem.value = 0 as NSNumber
            stillItem.dataType = kCMMetadataBaseDataType_SInt8 as String
            adaptor.append(AVTimedMetadataGroup(items: [stillItem], timeRange: CMTimeRange(start: ptsTime, duration: frameDur)))
            adaptor.assetWriterInput.markAsFinished()
        }

        let copyGroup = DispatchGroup()
        let vQueue = DispatchQueue(label: "com.directswitch.live.video")
        let vState = DirectSwitchLiveCopyState()
        copyGroup.enter()
        wVideo.requestMediaDataWhenReady(on: vQueue) {
            while !vState.finished && wVideo.isReadyForMoreMediaData {
                if let sample = rVideo.copyNextSampleBuffer() {
                    if !wVideo.append(sample) {
                        vState.finished = true
                        wVideo.markAsFinished()
                        copyGroup.leave()
                        break
                    }
                } else {
                    vState.finished = true
                    wVideo.markAsFinished()
                    copyGroup.leave()
                    break
                }
            }
        }

        if let rAudio = rAudioOpt, let wAudio = wAudioOpt {
            let aQueue = DispatchQueue(label: "com.directswitch.live.audio")
            let aState = DirectSwitchLiveCopyState()
            copyGroup.enter()
            wAudio.requestMediaDataWhenReady(on: aQueue) {
                while !aState.finished && wAudio.isReadyForMoreMediaData {
                    if let sample = rAudio.copyNextSampleBuffer() {
                        if !wAudio.append(sample) {
                            aState.finished = true
                            wAudio.markAsFinished()
                            copyGroup.leave()
                            break
                        }
                    } else {
                        aState.finished = true
                        wAudio.markAsFinished()
                        copyGroup.leave()
                        break
                    }
                }
            }
        }

        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            copyGroup.notify(queue: DispatchQueue.global(qos: .userInitiated)) {
                cont.resume()
            }
        }
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            writer.finishWriting { cont.resume() }
        }
        return writer.status == .completed && FileManager.default.fileExists(atPath: dstMovURL.path)
    }
}

// ============================================================================
// 2. TRIAGE BATTERIA CRITICA + RECUPERO DELTA 14–30 GIORNI
// ============================================================================

struct BatterySnapshot: Equatable, Sendable {
    let percent: Int
    let isCharging: Bool
    let recommendsAutoTriage: Bool
}

enum BatteryTriagePlanner {
    static let criticalBatteryPercent = 15
    private static let smallVideoThresholdBytes: Int64 = 50 * 1024 * 1024

    static func shouldAutoActivate(batteryPercent: Int, isCharging: Bool) -> Bool {
        batteryPercent >= 1 && batteryPercent <= criticalBatteryPercent && !isCharging
    }

    static func priorityBucket(for item: ManifestItem) -> Int {
        if item.relativeAlbumOrFolder.caseInsensitiveCompare("Password_e_Accessi") == .orderedSame ||
            (item.category == .DOCUMENTS && item.fileName.lowercased().hasSuffix(".csv")) {
            return 0
        }
        switch item.category {
        case .DOCUMENTS, .WHATSAPP_VAULT: return 1
        case .AUDIO: return 2
        case .PHOTOS: return (item.isFavorite == true) ? 3 : 4
        case .VIDEOS: return item.sizeBytes <= smallVideoThresholdBytes ? 5 : 6
        default: return 1
        }
    }

    static func sortByTriagePriority<T>(_ entries: [T], itemSelector: (T) -> ManifestItem) -> [T] {
        entries.sorted { a, b in
            let ia = itemSelector(a)
            let ib = itemSelector(b)
            let ba = priorityBucket(for: ia)
            let bb = priorityBucket(for: ib)
            if ba != bb { return ba < bb }
            if ba <= 1 {
                if ia.sizeBytes != ib.sizeBytes { return ia.sizeBytes < ib.sizeBytes }
            } else {
                if ia.capturedEpochMillis != ib.capturedEpochMillis { return ia.capturedEpochMillis > ib.capturedEpochMillis }
            }
            return ia.sizeBytes < ib.sizeBytes
        }
    }

    @MainActor
    static func readCurrentBatterySnapshot() -> BatterySnapshot {
        let dev = UIDevice.current
        let prev = dev.isBatteryMonitoringEnabled
        if !prev { dev.isBatteryMonitoringEnabled = true }
        let rawLevel = dev.batteryLevel
        let state = dev.batteryState
        let pct = rawLevel < 0 ? 100 : max(0, min(100, Int((rawLevel * 100.0).rounded())))
        let charging = (state == .charging || state == .full)
        return BatterySnapshot(
            percent: pct,
            isCharging: charging,
            recommendsAutoTriage: shouldAutoActivate(batteryPercent: pct, isCharging: charging)
        )
    }
}

struct CompletedMigrationRecord: Codable, Equatable, Sendable {
    let sessionId: String
    let peerName: String
    let peerPlatform: DevicePlatform
    let completedAtEpochMillis: Int64
    let transferredFilesCount: Int
    let transferredBytes: Int64
    var transferredDedupKeys: [String] = []
    var lastScope: ActiveTransferScope = ActiveTransferScope()

    func daysSinceCompleted(nowEpochMillis: Int64 = Int64(Date().timeIntervalSince1970 * 1000.0)) -> Int {
        let diff = max(Int64(0), nowEpochMillis - completedAtEpochMillis)
        return Int(diff / 86_400_000)
    }
}

enum CompletedMigrationStore {
    private static let retentionMs: Int64 = 30 * 24 * 60 * 60 * 1000
    private static let maxKeys = 25_000

    static func defaultFileURL() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = appSupport.appendingPathComponent("DirectSwitch", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("completed_migration_delta_v1.json")
    }

    static func save(_ record: CompletedMigrationRecord, to fileURL: URL? = nil) {
        let target = fileURL ?? defaultFileURL()
        var trimmed = record
        if trimmed.transferredDedupKeys.count > maxKeys {
            trimmed.transferredDedupKeys = Array(trimmed.transferredDedupKeys.suffix(maxKeys))
        }
        try? FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(trimmed) else { return }
        try? data.write(to: target, options: .atomic)
    }

    static func load(
        from fileURL: URL? = nil,
        nowEpochMillis: Int64 = Int64(Date().timeIntervalSince1970 * 1000.0)
    ) -> CompletedMigrationRecord? {
        let target = fileURL ?? defaultFileURL()
        guard let data = try? Data(contentsOf: target),
              let rec = try? JSONDecoder().decode(CompletedMigrationRecord.self, from: data) else {
            return nil
        }
        if nowEpochMillis - rec.completedAtEpochMillis > retentionMs {
            clear(at: target)
            return nil
        }
        return rec
    }

    static func clear(at fileURL: URL? = nil) {
        let target = fileURL ?? defaultFileURL()
        try? FileManager.default.removeItem(at: target)
    }

    static func filterDeltaEntries<T>(
        _ entries: [T],
        record: CompletedMigrationRecord,
        itemSelector: (T) -> ManifestItem
    ) -> [T] {
        let seen = Set(record.transferredDedupKeys)
        let cutoff = max(Int64(0), record.completedAtEpochMillis - 5 * 60 * 1000)
        return entries.filter { entry in
            let item = itemSelector(entry)
            if seen.contains(item.dedupKey) { return false }
            if item.capturedEpochMillis > 0 {
                return item.capturedEpochMillis >= cutoff
            }
            return true
        }
    }

    static func filterDeltaCalendars(_ list: [CalendarEventRecord], record: CompletedMigrationRecord) -> [CalendarEventRecord] {
        let cutoff = max(Int64(0), record.completedAtEpochMillis - 5 * 60 * 1000)
        return list.filter { $0.endEpochMillis >= cutoff || $0.startEpochMillis >= cutoff }
    }

    static func filterDeltaReminders(_ list: [ReminderTransferRecord], record: CompletedMigrationRecord) -> [ReminderTransferRecord] {
        let cutoff = max(Int64(0), record.completedAtEpochMillis - 5 * 60 * 1000)
        return list.filter { ($0.dueEpochMillis ?? cutoff) >= cutoff || !$0.isCompleted }
    }
}

// ============================================================================
// 3. AUDIT ANTI-LOCKOUT DINAMICO + CERTIFICATO PRONTO PER RESET
// ============================================================================

enum SensitiveAppRiskKind: String, Codable, Sendable {
    case spidIdentity = "SPID / Identità Digitale"
    case twoFactorAuth = "Authenticator / 2FA"
    case bankingPayments = "Banca / Pagamenti"
    case cryptoWallet = "Wallet Crypto"
    case esimCarrier = "eSIM / Operatore"
}

struct SensitiveAppAuditItem: Identifiable, Codable, Equatable, Sendable {
    var id: String { "\(canonicalId)_\(appName)" }
    let canonicalId: String
    let appName: String
    let riskKind: SensitiveAppRiskKind
    let isPresentOnReceiver: Bool
    let guidance: String
}

enum DecommissionReadinessLevel: String, Equatable, Sendable {
    case blockedRed
    case cautionAmber
    case readyForResetGreen
}

struct DecommissionAuditReport: Equatable, Sendable {
    let sessionId: String
    let peerName: String
    let peerPlatform: DevicePlatform
    let checkedWithLiveReceiver: Bool
    let missingCriticalApps: [SensitiveAppAuditItem]
    let verifiedCriticalApps: [SensitiveAppAuditItem]
    let localOnlyContactsCount: Int
    let contactsWereMigrated: Bool
    let icloudPhantomMediaCount: Int
    let unresolvedSkippedItemsCount: Int
    let readinessLevel: DecommissionReadinessLevel
    let completedFilesCount: Int
    let transferredBytes: Int64
    let certificateSha256: String
    let generatedAtEpochMillis: Int64
}

enum SensitiveAppRiskClassifier {
    private struct Rule {
        let canonicalId: String
        let riskKind: SensitiveAppRiskKind
        let identifiers: Set<String>
        let keywords: Set<String>
        let guidance: String
    }

    private static let rules: [Rule] = [
        Rule(canonicalId: "posteid", riskKind: .spidIdentity, identifiers: ["posteitaliane.posteapp.appposteid", "it.poste.postebuy2", "posteid"], keywords: ["posteid"], guidance: "Attiva PosteID sul nuovo telefono prima di rimuoverlo dal vecchio (eviti il blocco SPID)."),
        Rule(canonicalId: "cieid", riskKind: .spidIdentity, identifiers: ["it.ipzs.cieid", "cieid"], keywords: ["cieid", "cie id"], guidance: "Registra la Carta d'Identità Elettronica (CIE) sul nuovo telefono con PIN e NFC."),
        Rule(canonicalId: "app_io", riskKind: .spidIdentity, identifiers: ["it.pagopa.io.app", "it.pagopa.app.io", "ioit"], keywords: ["app io"], guidance: "Accedi ad App IO sul nuovo telefono con SPID o CIE."),
        Rule(canonicalId: "aruba_otp", riskKind: .spidIdentity, identifiers: ["it.aruba.otp", "it.aruba.pec.mobile", "it.aruba.mobilepec"], keywords: ["aruba otp", "aruba pec"], guidance: "Trasferisci il token Aruba OTP finché il vecchio dispositivo genera ancora codici."),
        Rule(canonicalId: "lepida_id", riskKind: .spidIdentity, identifiers: ["it.lepida.lepidaid"], keywords: ["lepidaid"], guidance: "Riassocia LepidaID sul nuovo telefono prima del reset."),
        Rule(canonicalId: "sielte_id", riskKind: .spidIdentity, identifiers: ["it.sielte.mysielteid"], keywords: ["sielteid", "mysielteid"], guidance: "Trasferisci MySielteID prima di disattivare il vecchio telefono."),
        Rule(canonicalId: "infocert_id", riskKind: .spidIdentity, identifiers: ["it.infocert.myinfocert"], keywords: ["infocert"], guidance: "Configura InfoCert ID sul nuovo telefono autorizzandolo dal vecchio."),
        Rule(canonicalId: "google_auth", riskKind: .twoFactorAuth, identifiers: ["com.google.android.apps.authenticator2", "com.google.authenticator", "googleauthenticator"], keywords: ["google authenticator"], guidance: "Esporta i codici 2FA tramite QR (Menu → Trasferisci account) prima di formattare!"),
        Rule(canonicalId: "ms_auth", riskKind: .twoFactorAuth, identifiers: ["com.azure.authenticator", "com.microsoft.azureauthenticator"], keywords: ["microsoft authenticator"], guidance: "Verifica il Backup Cloud o trasferisci gli account 2FA sul nuovo telefono."),
        Rule(canonicalId: "authy", riskKind: .twoFactorAuth, identifiers: ["com.authy.authy"], keywords: ["authy"], guidance: "Abilita Multi-Device su Authy e controlla i codici sul nuovo smartphone."),
        Rule(canonicalId: "twofas", riskKind: .twoFactorAuth, identifiers: ["com.twofasapp"], keywords: ["2fas"], guidance: "Esporta il backup cifrato di 2FAS e importalo sul nuovo telefono."),
        Rule(canonicalId: "bitwarden", riskKind: .twoFactorAuth, identifiers: ["com.x8bit.bitwarden", "com.agilebits.onepassword", "com.onepassword.android"], keywords: ["bitwarden", "1password", "proton pass"], guidance: "Verifica l'accesso al gestore password sul nuovo telefono prima del reset."),
        Rule(canonicalId: "intesa", riskKind: .bankingPayments, identifiers: ["com.latuabancaperandroid", "com.intesasanpaolo.mobile"], keywords: ["intesa sanpaolo", "isybank"], guidance: "Attiva O-Key Smart sul nuovo telefono autorizzandolo dal vecchio."),
        Rule(canonicalId: "unicredit", riskKind: .bankingPayments, identifiers: ["com.unicredit", "it.unicredit.mobile"], keywords: ["unicredit", "buddybank"], guidance: "Attiva Mobile Token sul nuovo smartphone finché il vecchio è attivo."),
        Rule(canonicalId: "fineco", riskKind: .bankingPayments, identifiers: ["com.fineco.it", "it.fineco.mobile"], keywords: ["fineco"], guidance: "Trasferisci Mobile Code Fineco sul nuovo telefono prima del reset."),
        Rule(canonicalId: "postepay", riskKind: .bankingPayments, identifiers: ["posteitaliane.posteapp.apppostepay", "posteitaliane.posteapp.appbpol", "it.poste.postepay", "it.poste.bancoposta"], keywords: ["postepay", "bancoposta"], guidance: "Autorizza PostePay/BancoPosta sul nuovo telefono prima del reset."),
        Rule(canonicalId: "revolut", riskKind: .bankingPayments, identifiers: ["com.revolut.revolut", "revolut"], keywords: ["revolut"], guidance: "Accedi a Revolut sul nuovo telefono e conferma il dispositivo."),
        Rule(canonicalId: "satispay", riskKind: .bankingPayments, identifiers: ["com.satispay.customer", "satispay"], keywords: ["satispay"], guidance: "Attiva Satispay sul nuovo telefono confermando il codice di sicurezza."),
        Rule(canonicalId: "paypal", riskKind: .bankingPayments, identifiers: ["com.paypal.android.p2pmobile", "com.yourcompany.ppclient", "paypal"], keywords: ["paypal"], guidance: "Accedi a PayPal sul nuovo telefono per spostare le conferme 2FA."),
        Rule(canonicalId: "bper_bpm_ing_bbva", riskKind: .bankingPayments, identifiers: ["it.bper.smart", "it.bancobpm.youapp", "com.ing.mobile", "com.bbva.bbvacontigo", "de.number26.android", "it.hype.app", "it.nexi.nexipay", "it.mediolanum.android", "it.credem.mobile", "it.illimity.bank", "it.bnl.mobile"], keywords: ["bper", "youapp", "banco bpm", "ing", "bbva", "n26", "hype", "nexi", "mediolanum", "illimity", "credem", "bnl", "widiba", "sella", "mediobanca", "mps"], guidance: "Attiva il token bancario sul nuovo telefono prima di formattare il vecchio."),
        Rule(canonicalId: "crypto_wallet", riskKind: .cryptoWallet, identifiers: ["io.metamask", "com.wallet.crypto.trustapp", "com.coinbase.android", "com.binance.dev", "com.ledger.live"], keywords: ["metamask", "trust wallet", "coinbase", "binance", "ledger"], guidance: "Verifica la seed phrase offline e il login del wallet sul nuovo dispositivo!"),
        Rule(canonicalId: "esim_carrier", riskKind: .esimCarrier, identifiers: ["it.telecomitalia.mytim", "it.vodafone.my190", "it.windtre.app", "it.iliad.android", "it.fastweb.myfastweb", "com.mobillium.airalo"], keywords: ["mytim", "myvodafone", "windtre", "very mobile", "ho. mobile", "airalo"], guidance: "Se usi una eSIM, ricorda di trasferirla o scaricare il nuovo QR prima di resettare.")
    ]

    static func classifyApp(_ app: InstalledAppRecord) -> (String, SensitiveAppRiskKind, String)? {
        let pkg = app.packageName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let scheme = (app.urlScheme ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let name = app.appName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        for r in rules {
            if r.identifiers.contains(pkg) || (!scheme.isEmpty && r.identifiers.contains(scheme)) {
                return (r.canonicalId, r.riskKind, r.guidance)
            }
            if r.keywords.contains(where: { name.contains($0) }) {
                return (r.canonicalId, r.riskKind, r.guidance)
            }
        }
        return nil
    }

    static func resolveCanonicalKeys(appIds: [String], appNames: [String] = []) -> Set<String> {
        var out = Set<String>()
        for raw in appIds {
            let low = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !low.isEmpty else { continue }
            out.insert(low)
            for r in rules where r.identifiers.contains(low) {
                out.insert(r.canonicalId)
            }
        }
        for rawName in appNames {
            let low = rawName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !low.isEmpty else { continue }
            for r in rules where r.keywords.contains(where: { low.contains($0) }) {
                out.insert(r.canonicalId)
            }
        }
        return out
    }
}

enum iOSDecommissionScanner {
    static func countLocalOnlyContacts() -> Int {
        let status = CNContactStore.authorizationStatus(for: .contacts)
        guard status == .authorized else { return 0 }
        let store = CNContactStore()
        guard let containers = try? store.containers(matching: nil) else { return 0 }
        var total = 0
        for c in containers where c.type == .local {
            let pred = CNContact.predicateForContactsInContainer(withIdentifier: c.identifier)
            if let list = try? store.unifiedContacts(matching: pred, keysToFetch: [CNContactIdentifierKey as CNKeyDescriptor]) {
                total += list.count
            }
        }
        return total
    }
}

enum DecommissionReadinessEvaluator {
    static func evaluate(
        sessionId: String,
        peerName: String,
        peerPlatform: DevicePlatform,
        senderInstalledApps: [InstalledAppRecord],
        receiverInstalledAppIds: [String]?,
        receiverInstalledAppNames: [String] = [],
        localOnlyContactsCount: Int,
        contactsWereMigrated: Bool,
        icloudPhantomMediaCount: Int = 0,
        unresolvedSkippedItemsCount: Int = 0,
        completedFilesCount: Int = 0,
        transferredBytes: Int64 = 0,
        acknowledgedAppIds: Set<String> = [],
        nowEpochMillis: Int64 = Int64(Date().timeIntervalSince1970 * 1000.0)
    ) -> DecommissionAuditReport {
        let hasLiveReceiver = receiverInstalledAppIds != nil
        let receiverKeys = SensitiveAppRiskClassifier.resolveCanonicalKeys(
            appIds: receiverInstalledAppIds ?? [],
            appNames: receiverInstalledAppNames
        )
        var missing: [SensitiveAppAuditItem] = []
        var verified: [SensitiveAppAuditItem] = []
        var seen = Set<String>()

        for app in senderInstalledApps {
            guard let (canonical, kind, guidance) = SensitiveAppRiskClassifier.classifyApp(app) else { continue }
            let unique = "\(canonical):\(app.packageName.lowercased())"
            if !seen.insert(canonical).inserted && kind != .bankingPayments { continue }
            if !seen.insert(unique).inserted { continue }

            let onReceiver = hasLiveReceiver && (receiverKeys.contains(canonical) || receiverKeys.contains(app.packageName.lowercased()))
            let ok = onReceiver || acknowledgedAppIds.contains(canonical)
            let item = SensitiveAppAuditItem(
                canonicalId: canonical,
                appName: app.appName,
                riskKind: kind,
                isPresentOnReceiver: ok,
                guidance: guidance
            )
            if ok { verified.append(item) } else { missing.append(item) }
        }

        let hasUnmigratedLocalContacts = localOnlyContactsCount > 0 && !contactsWereMigrated
        let level: DecommissionReadinessLevel = {
            if !missing.isEmpty { return .blockedRed }
            if hasUnmigratedLocalContacts || icloudPhantomMediaCount > 0 || unresolvedSkippedItemsCount > 0 {
                return .cautionAmber
            }
            return .readyForResetGreen
        }()

        let digestStr = [
            sessionId, peerName, peerPlatform.rawValue,
            "\(completedFilesCount)", "\(transferredBytes)",
            "\(missing.count)", "\(verified.count)",
            "\(localOnlyContactsCount)", "\(icloudPhantomMediaCount)",
            level.rawValue, "\(nowEpochMillis / 1000)"
        ].joined(separator: "|")
        let shaHex = SHA256.hash(data: Data(digestStr.utf8)).map { String(format: "%02x", $0) }.joined()

        return DecommissionAuditReport(
            sessionId: sessionId,
            peerName: peerName,
            peerPlatform: peerPlatform,
            checkedWithLiveReceiver: hasLiveReceiver,
            missingCriticalApps: missing,
            verifiedCriticalApps: verified,
            localOnlyContactsCount: localOnlyContactsCount,
            contactsWereMigrated: contactsWereMigrated,
            icloudPhantomMediaCount: icloudPhantomMediaCount,
            unresolvedSkippedItemsCount: unresolvedSkippedItemsCount,
            readinessLevel: level,
            completedFilesCount: completedFilesCount,
            transferredBytes: transferredBytes,
            certificateSha256: shaHex,
            generatedAtEpochMillis: nowEpochMillis
        )
    }

    static func buildResetCertificateText(report: DecommissionAuditReport, senderDeviceName: String) -> String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "it_IT")
        df.dateStyle = .medium
        df.timeStyle = .short
        let status: String = {
            switch report.readinessLevel {
            case .readyForResetGreen: return "PRONTO PER RESET / PERMUTA ✓"
            case .cautionAmber: return "ATTENZIONE — VERIFICA ELEMENTI SECONDARI"
            case .blockedRed: return "NON FORMATTARE — APP CRITICHE MANCANTI"
            }
        }()
        var lines = [
            "DirectSwitch — Certificato Audit Pre-Reset",
            "Stato: \(status)",
            "Data: \(df.string(from: Date(timeIntervalSince1970: TimeInterval(report.generatedAtEpochMillis) / 1000.0)))",
            "Vecchio dispositivo: \(senderDeviceName)",
            "Nuovo dispositivo: \(report.peerName) (\(report.peerPlatform.rawValue))",
            "----------------------------------------",
            "File migrati: \(report.completedFilesCount) (\(TransferDisplayFormatting.formatBytes(report.transferredBytes)))",
            "App critiche verificate sul nuovo telefono: \(report.verifiedCriticalApps.count)",
            "App critiche ancora mancanti: \(report.missingCriticalApps.count)"
        ]
        for m in report.missingCriticalApps {
            lines.append("  [!] \(m.appName) (\(m.riskKind.rawValue))")
        }
        if report.localOnlyContactsCount > 0 {
            lines.append("Contatti solo su iPhone: \(report.localOnlyContactsCount) (\(report.contactsWereMigrated ? "migrati ✓" : "NON ancora migrati"))")
        }
        if report.icloudPhantomMediaCount > 0 {
            lines.append("Media solo su iCloud non scaricati: \(report.icloudPhantomMediaCount)")
        }
        lines.append("Elementi saltati non risolti: \(report.unresolvedSkippedItemsCount)")
        lines.append("----------------------------------------")
        lines.append("Impronta SHA-256 Audit: \(report.certificateSha256.prefix(24).uppercased())")
        return lines.joined(separator: "\n")
    }
}

// ============================================================================
// 5. OVERFLOW BRIDGE DIRECTSWITCH -> CLOUDSAVE (iOS Free-Install & Release)
// ============================================================================

struct OverflowSplitPlan: Equatable, Sendable {
    let directItems: [ManifestItem]
    let overflowItems: [ManifestItem]
    let cutoffEpochMillis: Int64
    let maxVideoBytes: Int64
    let directTotalBytes: Int64
    let overflowTotalBytes: Int64
    let fitsAvailableSpace: Bool
}

enum OverflowBridgePlanner {
    static func buildSplitPlan(
        availableFreeBytes: Int64,
        items: [ManifestItem],
        nowEpochMillis: Int64 = Int64(Date().timeIntervalSince1970 * 1000.0)
    ) -> OverflowSplitPlan {
        let usableFree = max(Int64(0), availableFreeBytes - SpaceReliefPlanner.safetyMarginBytes)
        let oneYearCutoff = nowEpochMillis - Int64(365) * 86_400_000
        let olderMedia = items.filter {
            ($0.category == .PHOTOS || $0.category == .VIDEOS) &&
                $0.capturedEpochMillis > 0 && $0.capturedEpochMillis < oneYearCutoff
        }
        let overflow: [ManifestItem]
        let cutoff: Int64
        let maxVid: Int64
        if !olderMedia.isEmpty {
            overflow = olderMedia
            cutoff = oneYearCutoff
            maxVid = 0
        } else {
            overflow = items.filter { $0.category == .VIDEOS && $0.sizeBytes > SpaceReliefPlanner.heavyVideoThresholdBytes }
            cutoff = 0
            maxVid = SpaceReliefPlanner.heavyVideoThresholdBytes
        }
        let overflowIds = Set(overflow.map(\.id))
        let direct = items.filter { !overflowIds.contains($0.id) }
        let directBytes = direct.reduce(Int64(0)) { $0 + max(0, $1.sizeBytes) }
        let overflowBytes = overflow.reduce(Int64(0)) { $0 + max(0, $1.sizeBytes) }
        return OverflowSplitPlan(
            directItems: direct,
            overflowItems: overflow,
            cutoffEpochMillis: cutoff,
            maxVideoBytes: maxVid,
            directTotalBytes: directBytes,
            overflowTotalBytes: overflowBytes,
            fitsAvailableSpace: directBytes <= usableFree
        )
    }
}

enum iOSCloudSaveOverflowBridge {
    @MainActor
    static func buildDeepLinkURL(plan: OverflowSplitPlan, targetDeviceName: String) -> URL? {
        var comps = URLComponents()
        comps.scheme = "com.cloudsave.ios"
        comps.host = "overflow-bridge"
        comps.queryItems = [
            URLQueryItem(name: "count", value: "\(plan.overflowItems.count)"),
            URLQueryItem(name: "bytes", value: "\(plan.overflowTotalBytes)"),
            URLQueryItem(name: "cutoffMs", value: "\(plan.cutoffEpochMillis)"),
            URLQueryItem(name: "maxVideoBytes", value: "\(plan.maxVideoBytes)"),
            URLQueryItem(name: "receiver", value: targetDeviceName)
        ]
        return comps.url
    }

    @MainActor
    static func launchCloudSaveOverflow(plan: OverflowSplitPlan, targetDeviceName: String) -> (launched: Bool, message: String) {
        guard let url = buildDeepLinkURL(plan: plan, targetDeviceName: targetDeviceName) else {
            return (false, "Impossibile preparare il collegamento verso CloudSave.")
        }
        guard UIApplication.shared.canOpenURL(url) else {
            return (false, "Installa CloudSave su questo iPhone per archiviare cifrati i \(plan.overflowItems.count) file eccedenti.")
        }
        UIApplication.shared.open(url, options: [:], completionHandler: nil)
        return (true, "CloudSave aperto con \(plan.overflowItems.count) file pronti per il backup cifrato AES-256!")
    }
}
