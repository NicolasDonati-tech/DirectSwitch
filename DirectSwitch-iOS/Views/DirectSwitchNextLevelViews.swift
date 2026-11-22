//
//  DirectSwitchNextLevelViews.swift
//  DirectSwitch-iOS
//
//  Created by Nicolas Donati.
//  Copyright © 2026 Nicolas Donati. Tutti i diritti riservati.
//

import SwiftUI

// MARK: - Selettore Lingua (Sistema / IT / EN / FR)

struct LanguageSelectorPill: View {
    @ObservedObject var store = DirectSwitchLocalizationStore.shared

    var body: some View {
        Menu {
            ForEach(DirectSwitchLanguage.allCases) { lang in
                Button {
                    store.language = lang
                } label: {
                    if store.language == lang {
                        Label(lang.displayName, systemImage: "checkmark")
                    } else {
                        Text(lang.displayName)
                    }
                }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "globe")
                    .font(.system(size: 12, weight: .semibold))
                Text(store.language.shortCode)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
            }
            .foregroundColor(AppleTheme.blue)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(AppleTheme.cardSurface)
            .clipShape(Capsule())
            .overlay(
                Capsule().stroke(AppleTheme.cardBorder, lineWidth: 0.9)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Card Ripresa Trasferimento Interrotto (Checkpoint su disco)

struct ResumableCheckpointCard: View {
    @ObservedObject var l10n = DirectSwitchLocalizationStore.shared
    let checkpoint: TransferCheckpointRecord
    var onResume: () -> Void
    var onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 10) {
                AppleSettingsIcon(systemName: "arrow.clockwise.circle.fill", color: AppleTheme.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text(l10n.tr("Trasferimento interrotto (\(checkpoint.completionPercent)%)", en: "Interrupted transfer (\(checkpoint.completionPercent)%)", fr: "Transfert interrompu (\(checkpoint.completionPercent)%)"))
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(AppleTheme.textPrimary)
                    Text(l10n.tr("Verso \(checkpoint.receiverName) • \(checkpoint.completedItemIds.count)/\(max(checkpoint.totalItems, checkpoint.completedItemIds.count)) file già salvati", en: "To \(checkpoint.receiverName) • \(checkpoint.completedItemIds.count)/\(max(checkpoint.totalItems, checkpoint.completedItemIds.count)) files already saved", fr: "Vers \(checkpoint.receiverName) • \(checkpoint.completedItemIds.count)/\(max(checkpoint.totalItems, checkpoint.completedItemIds.count)) fichiers déjà enregistrés"))
                        .font(.system(size: 12.5))
                        .foregroundColor(AppleTheme.textSecondary)
                        .lineLimit(2)
                }
                Spacer()
            }

            HStack(spacing: 10) {
                Button(action: onResume) {
                    HStack(spacing: 6) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 12, weight: .bold))
                        Text(l10n.tr("Riprendi ora"))
                            .font(.system(size: 13.5, weight: .bold))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 40)
                    .background(AppleTheme.blue)
                    .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                }
                .buttonStyle(.plain)

                Button(action: onDismiss) {
                    Text(l10n.tr("Ignora"))
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundColor(AppleTheme.textSecondary)
                        .padding(.horizontal, 14)
                        .frame(height: 40)
                        .background(AppleTheme.inputSurface)
                        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background(AppleTheme.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(AppleTheme.orange.opacity(0.45), lineWidth: 1.1)
        )
    }
}

// MARK: - Badge Canale di Connessione (USB-C / AWDL P2P / Wi-Fi Locale)

struct ConnectionMediumPill: View {
    @ObservedObject var l10n = DirectSwitchLocalizationStore.shared
    let medium: TransferConnectionMedium

    private var tint: Color {
        switch medium {
        case .usbCable: return AppleTheme.green
        case .peerToPeerWifi: return AppleTheme.teal
        case .localWifi: return AppleTheme.blue
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: medium.systemImage)
                .font(.system(size: 11.5, weight: .semibold))
            Text(l10n.tr(medium.badgeLabel))
                .font(.system(size: 11.5, weight: .semibold))
        }
        .foregroundColor(tint)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(tint.opacity(0.12))
        .clipShape(Capsule())
    }
}

// MARK: - Filtri Rapidi Foto e Video (Ultimo anno, Album, ≤ 500 MB, HEVC 1080p, iCloud)

struct PhotoFilterChipsBar: View {
    @ObservedObject var l10n = DirectSwitchLocalizationStore.shared
    @Binding var filters: MediaTransferFilterOptions
    let availableAlbums: [String]
    @State private var showAlbumsPicker: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(l10n.tr("Filtri rapidi Foto"))
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(AppleTheme.textSecondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    filterChip(
                        title: l10n.tr("Tutte le foto"),
                        isSelected: !filters.photosLastYearOnly && filters.selectedPhotoAlbums.isEmpty
                    ) {
                        filters.photosLastYearOnly = false
                        filters.selectedPhotoAlbums = []
                    }

                    filterChip(
                        title: l10n.tr("Solo ultimo anno"),
                        isSelected: filters.photosLastYearOnly
                    ) {
                        filters.photosLastYearOnly.toggle()
                    }

                    filterChip(
                        title: l10n.tr("Includi anche iCloud"),
                        isSelected: filters.includeICloudOnlyMedia
                    ) {
                        filters.includeICloudOnlyMedia.toggle()
                    }

                    if !availableAlbums.isEmpty {
                        filterChip(
                            title: filters.selectedPhotoAlbums.isEmpty
                                ? l10n.tr("Scegli Album (\(availableAlbums.count))", en: "Choose Albums (\(availableAlbums.count))", fr: "Choisir albums (\(availableAlbums.count))")
                                : l10n.tr("Album: \(filters.selectedPhotoAlbums.count) scelti", en: "Albums: \(filters.selectedPhotoAlbums.count) picked", fr: "Albums : \(filters.selectedPhotoAlbums.count) choisis"),
                            isSelected: !filters.selectedPhotoAlbums.isEmpty || showAlbumsPicker
                        ) {
                            withAnimation(.easeInOut(duration: 0.18)) {
                                showAlbumsPicker.toggle()
                            }
                        }
                    }
                }
            }

            if showAlbumsPicker && !availableAlbums.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(availableAlbums, id: \.self) { album in
                            let selected = filters.selectedPhotoAlbums.contains(album)
                            Button {
                                if selected {
                                    filters.selectedPhotoAlbums.removeAll { $0 == album }
                                } else {
                                    filters.selectedPhotoAlbums.append(album)
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: selected ? "checkmark.circle.fill" : "folder")
                                        .font(.system(size: 11, weight: .semibold))
                                    Text(album)
                                        .font(.system(size: 11.5, weight: .semibold))
                                        .lineLimit(1)
                                }
                                .foregroundColor(selected ? .white : AppleTheme.textPrimary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(selected ? AppleTheme.orange : AppleTheme.cardSurface)
                                .clipShape(Capsule())
                                .overlay(
                                    Capsule().stroke(selected ? AppleTheme.orange : AppleTheme.cardBorder, lineWidth: 0.8)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .padding(.top, 4)
    }

    private func filterChip(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(isSelected ? .white : AppleTheme.textPrimary)
                .padding(.horizontal, 11)
                .padding(.vertical, 6)
                .background(isSelected ? AppleTheme.blue : AppleTheme.cardSurface)
                .clipShape(Capsule())
                .overlay(
                    Capsule().stroke(isSelected ? AppleTheme.blue : AppleTheme.cardBorder, lineWidth: 0.8)
                )
        }
        .buttonStyle(.plain)
    }
}

struct VideoFilterChipsBar: View {
    @ObservedObject var l10n = DirectSwitchLocalizationStore.shared
    @Binding var filters: MediaTransferFilterOptions

    private static let halfGbBytes: Int64 = 500 * 1024 * 1024

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(l10n.tr("Filtri e Salva-Spazio Video"))
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(AppleTheme.textSecondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    chip(
                        title: l10n.tr("Tutti i video"),
                        isSelected: !filters.videosLastYearOnly && filters.maxVideoBytes == 0
                    ) {
                        filters.videosLastYearOnly = false
                        filters.maxVideoBytes = 0
                    }
                    chip(
                        title: l10n.tr("Solo ultimo anno"),
                        isSelected: filters.videosLastYearOnly
                    ) {
                        filters.videosLastYearOnly.toggle()
                    }
                    chip(
                        title: l10n.tr("Solo ≤ 500 MB"),
                        isSelected: filters.maxVideoBytes == Self.halfGbBytes
                    ) {
                        filters.maxVideoBytes = (filters.maxVideoBytes == Self.halfGbBytes) ? 0 : Self.halfGbBytes
                    }
                    chip(
                        title: l10n.tr("Includi anche iCloud"),
                        isSelected: filters.includeICloudOnlyMedia
                    ) {
                        filters.includeICloudOnlyMedia.toggle()
                    }
                }
            }

            Toggle(isOn: $filters.compactVideo1080pHevc) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(l10n.tr("Modalità Salva-Spazio HEVC 1080p (-55%)"))
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundColor(AppleTheme.textPrimary)
                    Text(l10n.tr("Ottimizza al volo i video pesanti (> 40 MB) senza toccare gli originali su questo iPhone.", en: "Optimizes large videos (> 40 MB) on the fly without touching originals on this iPhone.", fr: "Optimise les vidéos lourdes (> 40 Mo) à la volée sans modifier les originaux."))
                        .font(.system(size: 11))
                        .foregroundColor(AppleTheme.textSecondary)
                }
            }
            .tint(AppleTheme.green)
        }
        .padding(.top, 4)
    }

    private func chip(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(isSelected ? .white : AppleTheme.textPrimary)
                .padding(.horizontal, 11)
                .padding(.vertical, 6)
                .background(isSelected ? AppleTheme.red : AppleTheme.cardSurface)
                .clipShape(Capsule())
                .overlay(
                    Capsule().stroke(isSelected ? AppleTheme.red : AppleTheme.cardBorder, lineWidth: 0.8)
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Tendina Audio, Memo Vocali & Note + Helper Password CSV Protetto

struct AudioAndNotesDropdownBody: View {
    @ObservedObject var l10n = DirectSwitchLocalizationStore.shared
    let pickedAudioFiles: [(ManifestItem, URL)]
    var onPickAudioOrNotes: () -> Void
    var onClearAudio: () -> Void

    private var totalBytes: Int64 {
        pickedAudioFiles.reduce(0) { $0 + $1.0.sizeBytes }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Image(systemName: pickedAudioFiles.isEmpty ? "waveform" : "checkmark.circle.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(pickedAudioFiles.isEmpty ? AppleTheme.teal : AppleTheme.green)
                VStack(alignment: .leading, spacing: 2) {
                    Text(pickedAudioFiles.isEmpty
                         ? l10n.tr("Seleziona Memo Vocali, Audio o Note esportate", en: "Select Voice Memos, Audio or exported Notes", fr: "Sélectionnez Mémos vocaux, Audio ou Notes")
                         : l10n.tr("\(pickedAudioFiles.count) file pronti (\(TransferDisplayFormatting.formatBytes(totalBytes)))", en: "\(pickedAudioFiles.count) files ready (\(TransferDisplayFormatting.formatBytes(totalBytes)))", fr: "\(pickedAudioFiles.count) fichiers prêts (\(TransferDisplayFormatting.formatBytes(totalBytes)))"))
                        .font(.system(size: 13.5, weight: .bold))
                        .foregroundColor(AppleTheme.textPrimary)
                    Text(l10n.tr("Supporta .m4a, .mp3, .wav, .aac, .txt, .md e PDF esportati da Memo Vocali o Note.", en: "Supports .m4a, .mp3, .wav, .aac, .txt, .md and PDFs exported from Voice Memos or Notes.", fr: "Compatible .m4a, .mp3, .wav, .aac, .txt, .md et PDF depuis Mémos vocaux ou Notes."))
                        .font(.system(size: 11.5))
                        .foregroundColor(AppleTheme.textSecondary)
                }
                Spacer()
            }

            if !pickedAudioFiles.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(pickedAudioFiles.prefix(5), id: \.0.id) { entry in
                        HStack(spacing: 8) {
                            Image(systemName: iOSAudioAndCallLogMigrator.isAudioFileName(entry.0.fileName) ? "music.note" : "doc.text")
                                .font(.system(size: 12))
                                .foregroundColor(AppleTheme.teal)
                            Text(entry.0.fileName)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(AppleTheme.textPrimary)
                                .lineLimit(1)
                            Spacer()
                            Text(TransferDisplayFormatting.formatBytes(entry.0.sizeBytes))
                                .font(.system(size: 11.5))
                                .foregroundColor(AppleTheme.textSecondary)
                        }
                        .padding(.horizontal, 9)
                        .padding(.vertical, 6)
                        .background(AppleTheme.cardSurface)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    if pickedAudioFiles.count > 5 {
                        Text(l10n.tr("…e altri \(pickedAudioFiles.count - 5) file audio/note", en: "…and \(pickedAudioFiles.count - 5) more audio/note files", fr: "…et \(pickedAudioFiles.count - 5) autres fichiers"))
                            .font(.system(size: 11.5))
                            .foregroundColor(AppleTheme.textSecondary)
                    }
                }
            }

            HStack(spacing: 10) {
                AppleSecondaryButton(
                    title: pickedAudioFiles.isEmpty ? l10n.tr("Scegli Memo Vocali / Audio / Note", en: "Pick Voice Memos / Audio / Notes", fr: "Choisir Mémos / Audio / Notes") : l10n.tr("Aggiungi altri file", en: "Add more files", fr: "Ajouter d'autres fichiers"),
                    icon: "plus.circle.fill",
                    tint: AppleTheme.teal,
                    action: onPickAudioOrNotes
                )
            }

            if !pickedAudioFiles.isEmpty {
                HStack {
                    Spacer()
                    Button(l10n.tr("Svuota elenco", en: "Clear list", fr: "Vider la liste"), action: onClearAudio)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(AppleTheme.red)
                        .buttonStyle(.plain)
                }
            }
        }
    }
}

struct GuidedPasswordsSectionBody: View {
    @ObservedObject var l10n = DirectSwitchLocalizationStore.shared
    let stagedCsvCount: Int
    var onPickPasswordCsv: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(AppleTheme.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text(stagedCsvCount > 0
                         ? l10n.tr("Password CSV pronto (\(stagedCsvCount) file) • Auto-cancellazione sicura", en: "Password CSV ready (\(stagedCsvCount) file) • Secure auto-wipe", fr: "CSV Mots de passe prêt (\(stagedCsvCount)) • Suppression sécurisée")
                         : l10n.tr("Trasferisci Password (Safari / Chrome CSV)", en: "Transfer Passwords (Safari / Chrome CSV)", fr: "Transférer les mots de passe (CSV Safari / Chrome)"))
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(AppleTheme.textPrimary)
                    Text(l10n.tr("Esporta le password in .csv da Password/Safari o Chrome, selezionalo qui: il file temporaneo viene cifrato in transito e sovrascritto a zeri a fine copia.", en: "Export passwords as .csv from Passwords/Safari or Chrome and pick it here: encrypted in transit and securely zero-wiped afterwards.", fr: "Exportez vos mots de passe en .csv depuis Safari ou Chrome : chiffré en transit et effacé à zéro après la copie."))
                        .font(.system(size: 11.5))
                        .foregroundColor(AppleTheme.textSecondary)
                }
                Spacer()
            }

            AppleSecondaryButton(
                title: stagedCsvCount > 0 ? l10n.tr("Aggiungi un altro file CSV Password", en: "Add another Password CSV", fr: "Ajouter un autre CSV") : l10n.tr("Seleziona file .csv Password", en: "Select Password .csv file", fr: "Sélectionner le fichier .csv"),
                icon: "key.fill",
                tint: AppleTheme.orange,
                action: onPickPasswordCsv
            )
        }
        .padding(11)
        .background(AppleTheme.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(AppleTheme.orange.opacity(0.35), lineWidth: 0.9)
        )
    }
}

// MARK: - Assistente Salva-Spazio (quando il ricevente ha meno spazio libero del necessario)

struct SpaceReliefAssistantCard: View {
    @ObservedObject var l10n = DirectSwitchLocalizationStore.shared
    let offer: SpaceReliefOffer
    var onSelectAction: (SpaceReliefActionKind) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                AppleSettingsIcon(systemName: "externaldrive.badge.exclamationmark", color: AppleTheme.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text(l10n.tr("Assistente Salva-Spazio"))
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(AppleTheme.textPrimary)
                    Text(l10n.tr("Su \(offer.receiverName) mancano circa \(TransferDisplayFormatting.formatBytes(offer.shortfallBytes)) per copiare tutto.", en: "\(offer.receiverName) needs about \(TransferDisplayFormatting.formatBytes(offer.shortfallBytes)) more free space to copy everything.", fr: "Il manque environ \(TransferDisplayFormatting.formatBytes(offer.shortfallBytes)) sur \(offer.receiverName) pour tout copier."))
                        .font(.system(size: 12.5))
                        .foregroundColor(AppleTheme.textSecondary)
                }
                Spacer()
            }

            Text(l10n.tr("Scegli una soluzione rapida con 1 tocco per ripartire subito:", en: "Pick a 1-tap quick option to restart right away:", fr: "Choisissez une solution rapide en 1 geste pour repartir :"))
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundColor(AppleTheme.textPrimary)

            VStack(spacing: 8) {
                ForEach(offer.options) { opt in
                    Button {
                        onSelectAction(opt.kind)
                    } label: {
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(l10n.tr(opt.title))
                                        .font(.system(size: 13.5, weight: .bold))
                                        .foregroundColor(AppleTheme.textPrimary)
                                    if opt.fitsAvailableSpace {
                                        Text(l10n.tr("Rientra ✓", en: "Fits ✓", fr: "Compatible ✓"))
                                            .font(.system(size: 10.5, weight: .bold))
                                            .foregroundColor(AppleTheme.green)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(AppleTheme.green.opacity(0.14))
                                            .clipShape(Capsule())
                                    }
                                }
                                Text(l10n.tr(opt.subtitle))
                                    .font(.system(size: 12))
                                    .foregroundColor(AppleTheme.textSecondary)
                            }
                            Spacer()
                            Image(systemName: "arrow.right.circle.fill")
                                .font(.system(size: 20))
                                .foregroundColor(AppleTheme.blue)
                        }
                        .padding(11)
                        .background(AppleTheme.inputSurface)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(14)
        .background(AppleTheme.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(AppleTheme.orange.opacity(0.45), lineWidth: 1.2)
        )
    }
}

// MARK: - Report Interattivo Elementi Saltati + "Riprova solo i mancanti"

struct SkippedItemsReportCard: View {
    @ObservedObject var l10n = DirectSwitchLocalizationStore.shared
    let items: [SkippedTransferItemRecord]
    let canRetry: Bool
    var onRetrySkippedOnly: () -> Void

    @State private var isExpanded: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 10) {
                    AppleSettingsIcon(systemName: "exclamationmark.triangle.fill", color: AppleTheme.orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(items.count == 1
                             ? l10n.tr("1 file saltato", en: "1 skipped file", fr: "1 fichier ignoré")
                             : l10n.tr("\(items.count) file saltati", en: "\(items.count) skipped files", fr: "\(items.count) fichiers ignorés"))
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(AppleTheme.textPrimary)
                        Text(l10n.tr("Tocca per vedere i dettagli e riprovare solo i mancanti", en: "Tap to inspect details and retry only missing items", fr: "Touchez pour voir les détails et réessayer les manquants"))
                            .font(.system(size: 12))
                            .foregroundColor(AppleTheme.textSecondary)
                    }
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(AppleTheme.textTertiary)
                }
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(items.prefix(25)) { rec in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(rec.fileName)
                                    .font(.system(size: 12.5, weight: .semibold))
                                    .foregroundColor(AppleTheme.textPrimary)
                                    .lineLimit(1)
                                Spacer()
                                if rec.sizeBytes > 0 {
                                    Text(TransferDisplayFormatting.formatBytes(rec.sizeBytes))
                                        .font(.system(size: 11))
                                        .foregroundColor(AppleTheme.textTertiary)
                                }
                            }
                            Text(rec.reason)
                                .font(.system(size: 11.5))
                                .foregroundColor(AppleTheme.orange)
                        }
                        .padding(8)
                        .background(AppleTheme.inputSurface)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    if items.count > 25 {
                        Text(l10n.tr("…e altri \(items.count - 25) elementi", en: "…and \(items.count - 25) more items", fr: "…et \(items.count - 25) autres éléments"))
                            .font(.system(size: 11.5))
                            .foregroundColor(AppleTheme.textSecondary)
                    }
                }
            }

            if canRetry {
                AppleSecondaryButton(
                    title: l10n.tr("Riprova solo questi \(items.count) file", en: "Retry only these \(items.count) files", fr: "Réessayer ces \(items.count) fichiers"),
                    icon: "arrow.clockwise.circle.fill",
                    tint: AppleTheme.orange,
                    action: onRetrySkippedOnly
                )
            }
        }
        .padding(14)
        .background(AppleTheme.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(AppleTheme.orange.opacity(0.42), lineWidth: 1.0)
        )
    }
}

// MARK: - Recupero Delta 14–30 Giorni ("Copia solo le novità")

struct DeltaCatchUpCard: View {
    @ObservedObject var l10n = DirectSwitchLocalizationStore.shared
    let record: CompletedMigrationRecord
    var onStartDeltaSync: () -> Void
    var onDismiss: () -> Void

    private var formattedDate: String {
        let df = DateFormatter()
        df.locale = Locale(identifier: l10n.effectiveCode)
        df.dateFormat = "dd/MM HH:mm"
        return df.string(from: Date(timeIntervalSince1970: TimeInterval(record.completedAtEpochMillis) / 1000.0))
    }

    var body: some View {
        let days = record.daysSinceCompleted()
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 10) {
                AppleSettingsIcon(systemName: "clock.arrow.circlepath", color: AppleTheme.teal)
                VStack(alignment: .leading, spacing: 2) {
                    Text(l10n.tr("Recupero Delta — Solo novità dal \(formattedDate)", en: "Delta Catch-Up — New items since \(formattedDate)", fr: "Rattrapage Delta — Nouveautés depuis \(formattedDate)"))
                        .font(.system(size: 14.5, weight: .bold))
                        .foregroundColor(AppleTheme.textPrimary)
                    Text(days == 0
                         ? l10n.tr("Già migrato verso \(record.peerName) (oggi). Copia solo foto, calendari e file nuovi.", en: "Already migrated to \(record.peerName) (today). Copy only new photos, calendars and files.", fr: "Déjà migré vers \(record.peerName) (aujourd'hui). Copiez uniquement les nouveautés.")
                         : l10n.tr("Già migrato verso \(record.peerName) (\(days) gg fa). Copia solo foto, calendari e file nuovi.", en: "Already migrated to \(record.peerName) (\(days)d ago). Copy only new photos, calendars and files.", fr: "Déjà migré vers \(record.peerName) (il y a \(days) j). Copiez uniquement les nouveautés."))
                        .font(.system(size: 12))
                        .foregroundColor(AppleTheme.textSecondary)
                }
                Spacer()
            }

            HStack(spacing: 10) {
                Button(action: onStartDeltaSync) {
                    HStack(spacing: 6) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 12, weight: .bold))
                        Text(l10n.tr("Copia solo novità"))
                            .font(.system(size: 13.5, weight: .bold))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 40)
                    .background(AppleTheme.teal)
                    .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                }
                .buttonStyle(.plain)

                Button(action: onDismiss) {
                    Text(l10n.tr("Chiudi"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(AppleTheme.textSecondary)
                        .padding(.horizontal, 14)
                        .frame(height: 40)
                        .background(AppleTheme.inputSurface)
                        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background(AppleTheme.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(AppleTheme.teal.opacity(0.45), lineWidth: 1.1)
        )
    }
}

// MARK: - Triage Batteria Critica

struct BatteryTriageActivePill: View {
    @ObservedObject var l10n = DirectSwitchLocalizationStore.shared
    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "battery.25")
                .font(.system(size: 11.5, weight: .semibold))
            Text(l10n.tr("Triage Batteria Critica"))
                .font(.system(size: 11.5, weight: .semibold))
        }
        .foregroundColor(AppleTheme.orange)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(AppleTheme.orange.opacity(0.14))
        .clipShape(Capsule())
    }
}

// MARK: - 11. Componenti Practical Pro (#1–#5): Termica, Smart Clean, HEIC, Riconciliazione, AP Isolation

struct ThermalGuardBannerPill: View {
    @ObservedObject var l10n = DirectSwitchLocalizationStore.shared
    let state: ThermalGuardState
    let bannerText: String?

    var body: some View {
        if state != .normal {
            let isCritical = (state == .criticalCooldown)
            let accent = isCritical ? AppleTheme.red : AppleTheme.orange
            let rawLabel = (bannerText?.isEmpty == false)
                ? (bannerText ?? "")
                : (isCritical ? "Raffreddamento termico (45s)" : "Limite termico (1 flusso)")
            let label = l10n.tr(rawLabel)
            HStack(spacing: 6) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 12, weight: .semibold))
                Text(label)
                    .font(.system(size: 11.5, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundColor(accent)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(accent.opacity(0.14))
            .clipShape(Capsule())
            .overlay(
                Capsule().stroke(accent.opacity(0.45), lineWidth: 1)
            )
        }
    }
}

struct NetworkIsolationHotspotCard: View {
    @ObservedObject var l10n = DirectSwitchLocalizationStore.shared
    let verdict: NetworkDiagnosticVerdict
    var onRetry: () -> Void

    var body: some View {
        let accent = verdict.likelyApClientIsolation ? AppleTheme.orange : AppleTheme.blue
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                AppleSettingsIcon(systemName: "antenna.radiowaves.left.and.right", color: accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verdict.title)
                        .font(.system(size: 14.5, weight: .bold))
                        .foregroundColor(AppleTheme.textPrimary)
                    Text(verdict.description)
                        .font(.system(size: 12))
                        .foregroundColor(AppleTheme.textSecondary)
                }
                Spacer()
            }

            ForEach(verdict.guidanceSteps, id: \.self) { step in
                Text(step)
                    .font(.system(size: 12))
                    .foregroundColor(AppleTheme.textPrimary)
                    .padding(.leading, 4)
            }

            AppleSecondaryButton(
                title: l10n.tr("Ho attivato l'Hotspot • Riprova collegamento"),
                icon: "arrow.clockwise",
                tint: accent,
                action: onRetry
            )
        }
        .padding(14)
        .background(accent.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(accent.opacity(0.45), lineWidth: 1.2)
        )
    }
}

struct SmartCleanAndCompatCard: View {
    @ObservedObject var l10n = DirectSwitchLocalizationStore.shared
    @Binding var smartClean: SmartCleanOptions
    @Binding var convertHeicToJpeg: Bool
    let showHeicOption: Bool
    @State private var expanded: Bool = false

    private var activeCount: Int {
        var count = 0
        if smartClean.mergeDuplicateContacts { count += 1 }
        if smartClean.skipExactDuplicatePhotosSha256 { count += 1 }
        if smartClean.skipOldScreenshotsOlderThanMonths > 0 { count += 1 }
        if showHeicOption && convertHeicToJpeg { count += 1 }
        return count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(action: {
                withAnimation(.easeInOut(duration: 0.18)) {
                    expanded.toggle()
                }
            }) {
                HStack(spacing: 12) {
                    AppleSettingsIcon(systemName: "sparkles", color: AppleTheme.teal)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(l10n.tr("Smart Clean & Compatibilità Pro"))
                            .font(.system(size: 14.5, weight: .semibold))
                            .foregroundColor(AppleTheme.textPrimary)
                        Text(l10n.tr(
                            "\(activeCount) protezioni attive prima dell'invio",
                            en: "\(activeCount) active protections before sending",
                            fr: "\(activeCount) protections actives avant l'envoi"
                        ))
                            .font(.system(size: 12))
                            .foregroundColor(AppleTheme.textSecondary)
                    }
                    Spacer()
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(AppleTheme.textSecondary)
                }
            }
            .buttonStyle(.plain)

            if expanded {
                Toggle(isOn: $smartClean.mergeDuplicateContacts) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(l10n.tr("Unisci contatti duplicati (+39)"))
                            .font(.system(size: 13, weight: .medium))
                        Text(l10n.tr("Fonde numeri e note in memoria senza toccare il vecchio telefono"))
                            .font(.system(size: 11))
                            .foregroundColor(AppleTheme.textSecondary)
                    }
                }
                .tint(AppleTheme.teal)

                Toggle(isOn: $smartClean.skipExactDuplicatePhotosSha256) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(l10n.tr("Salta foto duplicate esatte (SHA-256)"))
                            .font(.system(size: 13, weight: .medium))
                        Text(l10n.tr("Evita di copiare file identici pixel-per-pixel"))
                            .font(.system(size: 11))
                            .foregroundColor(AppleTheme.textSecondary)
                    }
                }
                .tint(AppleTheme.teal)

                Toggle(isOn: Binding(
                    get: { smartClean.skipOldScreenshotsOlderThanMonths > 0 },
                    set: { smartClean.skipOldScreenshotsOlderThanMonths = $0 ? 12 : 0 }
                )) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(l10n.tr("Escludi vecchi screenshot (> 12 mesi)"))
                            .font(.system(size: 13, weight: .medium))
                        Text(l10n.tr("Libera spazio evitando schermate datate"))
                            .font(.system(size: 11))
                            .foregroundColor(AppleTheme.textSecondary)
                    }
                }
                .tint(AppleTheme.teal)

                if showHeicOption {
                    Toggle(isOn: $convertHeicToJpeg) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(l10n.tr("Massima compatibilità HEIC → JPEG"))
                                .font(.system(size: 13, weight: .medium))
                            Text(l10n.tr("Converte foto iPhone in JPEG preservando data scatto, rotazione e GPS"))
                                .font(.system(size: 11))
                                .foregroundColor(AppleTheme.textSecondary)
                        }
                    }
                    .tint(AppleTheme.teal)
                }
            }
        }
        .appleCard()
    }
}

struct PostTransferReconciliationCard: View {
    @ObservedObject var l10n = DirectSwitchLocalizationStore.shared
    let verifiedCount: Int
    let missingIds: [String]
    var failedCount: Int = 0
    let heicConvertedCount: Int
    let smartCleanMergedContacts: Int
    let smartCleanSkippedDuplicates: Int
    let smartCleanSkippedScreenshots: Int
    var onRepairMissing: ([String]) -> Void

    var body: some View {
        let allClean = missingIds.isEmpty
        let accent = allClean ? AppleTheme.green : AppleTheme.orange
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                AppleSettingsIcon(
                    systemName: allClean ? "checkmark.shield.fill" : "exclamationmark.triangle.fill",
                    color: accent
                )
                VStack(alignment: .leading, spacing: 2) {
                    Text(allClean
                         ? (failedCount == 0
                            ? l10n.tr("Verifica SHA-256 Post-Migrazione: 100% Integro")
                            : l10n.tr(
                                "Verifica SHA-256: \(verifiedCount) file ricevuti integri",
                                en: "SHA-256 Check: \(verifiedCount) received files verified",
                                fr: "Vérification SHA-256 : \(verifiedCount) fichiers reçus intègres"
                            ))
                         : l10n.tr(
                            "Rilevati \(missingIds.count) file mancanti o alterati",
                            en: "\(missingIds.count) missing or altered files detected",
                            fr: "\(missingIds.count) fichiers manquants ou altérés détectés"
                         ))
                        .font(.system(size: 14.5, weight: .bold))
                        .foregroundColor(AppleTheme.textPrimary)
                    Text(l10n.tr(
                        "\(verifiedCount) file verificati con impronta crittografica end-to-end.",
                        en: "\(verifiedCount) files verified with end-to-end cryptographic hash.",
                        fr: "\(verifiedCount) fichiers vérifiés par empreinte cryptographique de bout en bout."
                    ))
                        .font(.system(size: 12))
                        .foregroundColor(AppleTheme.textSecondary)
                }
                Spacer()
            }

            if smartCleanMergedContacts > 0 || smartCleanSkippedDuplicates > 0 || smartCleanSkippedScreenshots > 0 || heicConvertedCount > 0 {
                let parts = [
                    smartCleanMergedContacts > 0 ? l10n.tr(
                        "\(smartCleanMergedContacts) contatti uniti",
                        en: "\(smartCleanMergedContacts) contacts merged",
                        fr: "\(smartCleanMergedContacts) contacts fusionnés"
                    ) : nil,
                    smartCleanSkippedDuplicates > 0 ? l10n.tr(
                        "\(smartCleanSkippedDuplicates) foto duplicate saltate",
                        en: "\(smartCleanSkippedDuplicates) duplicate photos skipped",
                        fr: "\(smartCleanSkippedDuplicates) photos en double ignorées"
                    ) : nil,
                    smartCleanSkippedScreenshots > 0 ? l10n.tr(
                        "\(smartCleanSkippedScreenshots) screenshot esclusi",
                        en: "\(smartCleanSkippedScreenshots) old screenshots excluded",
                        fr: "\(smartCleanSkippedScreenshots) anciennes captures exclues"
                    ) : nil,
                    heicConvertedCount > 0 ? "\(heicConvertedCount) HEIC→JPEG" : nil
                ].compactMap { $0 }
                Text("Smart Clean: \(parts.joined(separator: " • "))")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundColor(AppleTheme.teal)
            }

            if !missingIds.isEmpty {
                ApplePrimaryButton(
                    title: l10n.tr(
                        "Ripara \(missingIds.count) file mancanti (1 tocco)",
                        en: "Repair \(missingIds.count) missing files (1 tap)",
                        fr: "Réparer \(missingIds.count) fichiers manquants (1 geste)"
                    ),
                    icon: "arrow.clockwise",
                    color: AppleTheme.orange
                ) {
                    onRepairMissing(missingIds)
                }
            }
        }
        .padding(14)
        .background(accent.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(accent.opacity(0.45), lineWidth: 1.2)
        )
    }
}
