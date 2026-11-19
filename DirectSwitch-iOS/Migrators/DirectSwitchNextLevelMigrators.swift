//
//  DirectSwitchNextLevelMigrators.swift
//  DirectSwitch-iOS
//
//  Created by Nicolas Donati.
//  Copyright © 2026 Nicolas Donati. Tutti i diritti riservati.
//

import Foundation
import Photos
import AVFoundation

/// Filtri intelligenti per Foto e Video (Ultimo anno, Album selezionati, Soglia MB e Compressione HEVC 1080p Salva-Spazio).
enum iOSPhotoFilterHelper {
    static func fetchUserAlbumTitles() -> [String] {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard status == .authorized || status == .limited else { return [] }
        var titles: [String] = []
        var seen = Set<String>()
        let collections = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .albumRegular, options: nil)
        collections.enumerateObjects { col, _, _ in
            let name = (col.localizedTitle ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return }
            let count = PHAsset.fetchAssets(in: col, options: nil).count
            guard count > 0 else { return }
            let key = name.lowercased()
            if seen.insert(key).inserted {
                titles.append(name)
            }
        }
        return titles.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    static func matchesFilter(
        item: ManifestItem,
        options: MediaTransferFilterOptions,
        nowEpochMillis: Int64 = Int64(Date().timeIntervalSince1970 * 1000.0)
    ) -> Bool {
        let oneYearCutoff = nowEpochMillis - Int64(365) * 86_400_000
        if item.category == .PHOTOS {
            if options.photosLastYearOnly && item.capturedEpochMillis > 0 && item.capturedEpochMillis < oneYearCutoff {
                return false
            }
            if !options.selectedPhotoAlbums.isEmpty {
                let allowed = Set(options.selectedPhotoAlbums.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() })
                let itemAlbum = item.relativeAlbumOrFolder.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                if !allowed.contains(itemAlbum) {
                    return false
                }
            }
        } else if item.category == .VIDEOS {
            if options.videosLastYearOnly && item.capturedEpochMillis > 0 && item.capturedEpochMillis < oneYearCutoff {
                return false
            }
            if options.maxVideoBytes > 0 && item.sizeBytes > options.maxVideoBytes {
                return false
            }
        }
        return true
    }

    /// Transcodifica un video pesante in HEVC 1080p (`AVAssetExportPresetHEVC1920x1080`) per la modalità Salva-Spazio (-55% circa).
    static func transcodeVideoToCompactHevc1080pIfBeneficial(
        sourceURL: URL,
        minSizeBytes: Int64 = 40 * 1024 * 1024
    ) async -> URL? {
        let attrs = try? FileManager.default.attributesOfItem(atPath: sourceURL.path)
        let origSize = (attrs?[.size] as? NSNumber)?.int64Value ?? 0
        guard origSize >= minSizeBytes else { return nil }

        let asset = AVURLAsset(url: sourceURL)
        let preset = AVAssetExportSession.exportPresets(compatibleWith: asset)
            .contains(AVAssetExportPresetHEVC1920x1080)
            ? AVAssetExportPresetHEVC1920x1080
            : AVAssetExportPreset1920x1080
        guard let exporter = AVAssetExportSession(asset: asset, presetName: preset) else { return nil }
        let outURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ds_compact_\(UUID().uuidString).mp4")
        exporter.outputURL = outURL
        exporter.outputFileType = .mp4
        exporter.shouldOptimizeForNetworkUse = true

        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            exporter.exportAsynchronously {
                cont.resume()
            }
        }
        guard exporter.status == .completed,
              let outAttrs = try? FileManager.default.attributesOfItem(atPath: outURL.path),
              let newSize = (outAttrs[.size] as? NSNumber)?.int64Value,
              newSize > 0, newSize < origSize else {
            try? FileManager.default.removeItem(at: outURL)
            return nil
        }
        return outURL
    }
}

/// Migratore per Audio / Memo Vocali / Note e Archivio Cronologia Chiamate ricevuto da Android su iPhone.
enum iOSAudioAndCallLogMigrator {
    private static let audioExtensions: Set<String> = [
        "m4a", "mp3", "wav", "aac", "flac", "ogg", "opus", "aiff", "caf", "wma", "amr"
    ]

    static func isAudioFileName(_ fileName: String) -> Bool {
        let ext = URL(fileURLWithPath: fileName).pathExtension.lowercased()
        return audioExtensions.contains(ext)
    }

    static func importPickedAudioOrNoteURLs(_ urls: [URL]) -> [(ManifestItem, URL)] {
        var results: [(ManifestItem, URL)] = []
        let fm = FileManager.default
        let stagingDir = fm.temporaryDirectory.appendingPathComponent("DirectSwitchAudioStage", isDirectory: true)
        try? fm.createDirectory(at: stagingDir, withIntermediateDirectories: true)

        for url in urls {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let cleanName = url.lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleanName.isEmpty else { continue }
            let dest = stagingDir.appendingPathComponent("\(UUID().uuidString)_\(cleanName)")
            guard (try? fm.copyItem(at: url, to: dest)) != nil,
                  let attrs = try? fm.attributesOfItem(atPath: dest.path),
                  let size = (attrs[.size] as? NSNumber)?.int64Value, size > 0 else {
                try? fm.removeItem(at: dest)
                continue
            }
            let ext = url.pathExtension.lowercased()
            let mime: String = {
                switch ext {
                case "m4a", "aac": return "audio/mp4"
                case "mp3": return "audio/mpeg"
                case "wav": return "audio/wav"
                case "txt", "md": return "text/plain"
                case "pdf": return "application/pdf"
                default: return "application/octet-stream"
                }
            }()
            let item = ManifestItem(
                id: "aud_\(UUID().uuidString.prefix(12))",
                category: .AUDIO,
                fileName: cleanName,
                relativeAlbumOrFolder: "Audio_e_Memo",
                sizeBytes: size,
                capturedEpochMillis: Int64(Date().timeIntervalSince1970 * 1000.0),
                dedupKey: "audio_\(cleanName.lowercased())_\(size)",
                mimeType: mime
            )
            results.append((item, dest))
        }
        return results
    }

    static func saveIncomingAudioFile(item: ManifestItem, sourceFileURL: URL) -> Bool {
        guard let docsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return false
        }
        let sub = item.relativeAlbumOrFolder.trimmingCharacters(in: .whitespacesAndNewlines)
        let folderName = sub.isEmpty ? "Audio_e_Memo" : sub
        let targetDir = docsDir.appendingPathComponent(folderName, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: targetDir, withIntermediateDirectories: true)
            let safeName = item.fileName.replacingOccurrences(of: "/", with: "_")
            var dest = targetDir.appendingPathComponent(safeName)
            if FileManager.default.fileExists(atPath: dest.path) {
                let stem = dest.deletingPathExtension().lastPathComponent
                let ext = dest.pathExtension
                dest = targetDir.appendingPathComponent("\(stem)_\(Int(Date().timeIntervalSince1970)).\(ext)")
            }
            try FileManager.default.copyItem(at: sourceFileURL, to: dest)
            return true
        } catch {
            return false
        }
    }

    static func saveIncomingCallLogsArchive(_ incoming: [CallLogTransferRecord]) -> Int {
        guard !incoming.isEmpty,
              let docsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return 0
        }
        let dir = docsDir.appendingPathComponent("Cronologia_Chiamate", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let jsonURL = dir.appendingPathComponent("Chiamate_DirectSwitch.json")
        if let jsonData = try? JSONEncoder().encode(incoming) {
            try? jsonData.write(to: jsonURL, options: .atomic)
        }

        let df = DateFormatter()
        df.locale = Locale(identifier: "it_IT")
        df.dateStyle = .medium
        df.timeStyle = .short

        var html = "<!DOCTYPE html><html lang='it'><head><meta charset='utf-8'><meta name='viewport' content='width=device-width,initial-scale=1'><title>Cronologia Chiamate (\(incoming.count))</title><style>body{font-family:-apple-system,sans-serif;background:#f4f7f9;padding:16px}.row{background:#fff;border-radius:12px;padding:12px;margin-bottom:8px;box-shadow:0 1px 4px rgba(0,0,0,0.06)}.meta{font-size:12px;color:#007aff;font-weight:600}</style></head><body><h2>Cronologia Chiamate DirectSwitch (\(incoming.count))</h2>"
        for call in incoming {
            let kind: String = {
                switch call.callType {
                case 2: return "Effettuata"
                case 3: return "Persa"
                case 5: return "Rifiutata"
                default: return "Ricevuta"
                }
            }()
            let who = (call.cachedName?.isEmpty == false ? "\(call.cachedName!) (\(call.number))" : call.number)
                .replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")
            let when = df.string(from: Date(timeIntervalSince1970: TimeInterval(call.dateEpochMillis) / 1000.0))
            html += "<div class='row'><div class='meta'>\(kind) • \(when) • \(call.durationSeconds)s</div><div>\(who)</div></div>"
        }
        html += "</body></html>"

        let htmlURL = dir.appendingPathComponent("Chiamate_DirectSwitch.html")
        do {
            try Data(html.utf8).write(to: htmlURL, options: .atomic)
            return incoming.count
        } catch {
            return 0
        }
    }
}
