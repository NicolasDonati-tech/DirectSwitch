//
//  DirectSwitchAppsTransferViews.swift
//  DirectSwitch-iOS
//
//  Created by Nicolas Donati.
//  Copyright © 2026 Nicolas Donati. Tutti i diritti riservati.
//

import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import UIKit

private struct PickedScrollVideoFile: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("ds_appscroll_\(UUID().uuidString).mov")
            try? FileManager.default.removeItem(at: tempURL)
            try FileManager.default.copyItem(at: received.file, to: tempURL)
            return Self(url: tempURL)
        }
    }
}

// MARK: - Sheet Guidata Passo 1: Screenshot Automatici a Scorrimento di Tutte le App

struct AutoAppScrollCaptureGuideSheet: View {
    @Environment(\.dismiss) private var dismiss
    var onArmAndOpenSettings: () -> Void

    var body: some View {
        NavigationView {
            ZStack {
                AppleTheme.backgroundGradient
                    .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 10) {
                                AppleSettingsIcon(systemName: "rectangle.stack.badge.play.fill", color: AppleTheme.blue)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Passo 1: Screenshot Automatici")
                                        .font(.system(size: 18, weight: .bold))
                                        .foregroundColor(AppleTheme.textPrimary)
                                    Text("Cattura il 100% delle tue App in 5 secondi senza scattare foto a mano")
                                        .font(.system(size: 13))
                                        .foregroundColor(AppleTheme.textSecondary)
                                }
                            }
                        }
                        .appleCard(padding: 14, selected: true)

                        VStack(alignment: .leading, spacing: 14) {
                            guideStepRow(
                                number: "1",
                                title: "Avvia Registrazione Schermo ⏺ dal Centro di Controllo",
                                detail: "Scorri col dito dall'angolo in alto a destra dello schermo e tocca il pallino «Registrazione schermo»."
                            )
                            Divider()
                            guideStepRow(
                                number: "2",
                                title: "Scorri l'elenco completo delle tue App",
                                detail: "Tocca il pulsante blu qui sotto, vai in «◀ Impostazioni → App» (oppure nella «Libreria app» A–Z in fondo alla Home) e scorri fino in fondo per 5 secondi."
                            )
                            Divider()
                            guideStepRow(
                                number: "3",
                                title: "Torna su DirectSwitch: estrazione automatica!",
                                detail: "Tocca l'indicatore rosso in alto per fermare e riapri DirectSwitch: l'app genererà da sola tutti gli screenshot dello scorrimento e selezionerà tutte le tue App in blu!"
                            )
                        }
                        .appleCard(padding: 16)

                        ApplePrimaryButton(
                            title: "Attiva Cattura Automatica e Apri Elenco App",
                            icon: "arrow.up.forward.app.fill",
                            color: AppleTheme.blue
                        ) {
                            onArmAndOpenSettings()
                            dismiss()
                        }

                        AppleSecondaryButton(
                            title: "Rimani qui (scorro io la Home / Libreria App)",
                            icon: "hand.draw.fill",
                            tint: AppleTheme.teal
                        ) {
                            dismiss()
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                }
            }
            .navigationTitle("Screenshot Automatici App")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Chiudi") {
                        dismiss()
                    }
                }
            }
        }
        .preferredColorScheme(.light)
    }

    private func guideStepRow(number: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(number)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .frame(width: 26, height: 26)
                .background(AppleTheme.blue)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(AppleTheme.textPrimary)
                Text(detail)
                    .font(.system(size: 13))
                    .foregroundColor(AppleTheme.textSecondary)
            }
        }
    }
}

// MARK: - Miniatura Icona App Store arrotondata in stile iOS

struct AppIconThumbnailView: View {
    let iconUrl: String?
    var size: CGFloat = 38

    var body: some View {
        Group {
            if let raw = iconUrl, let url = URL(string: raw) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    default:
                        fallbackBadge
                    }
                }
            } else {
                fallbackBadge
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.225, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
                .stroke(AppleTheme.cardBorder, lineWidth: 0.7)
        )
    }

    private var fallbackBadge: some View {
        ZStack {
            LinearGradient(
                colors: [AppleTheme.blue.opacity(0.16), AppleTheme.teal.opacity(0.12)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: "app.fill")
                .font(.system(size: size * 0.46, weight: .semibold))
                .foregroundColor(AppleTheme.blue)
        }
    }
}

// MARK: - Sheet Mittente: Tutte le App dell'iPhone da trasferire (Auto-Scan + Vision Screenshot + Ricerca App Store)

struct SenderAppsSelectionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var appsCatalog: [InstalledAppRecord]
    @Binding var deselectedAppIds: Set<String>
    var onStartGuidedAutoCapture: (() -> Void)? = nil

    @State private var searchQuery: String = ""
    @State private var searchResults: [InstalledAppRecord] = []
    @State private var isSearching: Bool = false
    @State private var screenshotPickerItems: [PhotosPickerItem] = []
    @State private var isScanningScreenshots: Bool = false
    @State private var ocrStatusNote: String? = nil
    @State private var temporaryRecordingAssetId: String? = nil
    @State private var showLocalAutoGuideSheet: Bool = false

    private var selectedCount: Int {
        appsCatalog.filter { !deselectedAppIds.contains($0.id) }.count
    }

    private var availableQuickSuggestions: [InstalledAppRecord] {
        let existingBundles = Set(appsCatalog.map { $0.packageName.lowercased() })
        let existingIds = Set(appsCatalog.compactMap(\.appStoreId))
        return iOSInstalledAppsScanner.italianQuickSuggestions.filter { item in
            if existingBundles.contains(item.packageName.lowercased()) { return false }
            if let sid = item.appStoreId, existingIds.contains(sid) { return false }
            return true
        }
    }

    var body: some View {
        NavigationView {
            ZStack {
                AppleTheme.backgroundGradient
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 16) {
                        // PASSO 1: Screenshot Automatici a Scorrimento di tutte le App del telefono
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 10) {
                                AppleSettingsIcon(systemName: "rectangle.stack.badge.play.fill", color: AppleTheme.blue)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Passo 1: Screenshot automatici di tutte le App")
                                        .font(.system(size: 15, weight: .bold))
                                        .foregroundColor(AppleTheme.textPrimary)
                                    Text("Scorri per 5 sec «Impostazioni → App» o la Home: estrazione automatica!")
                                        .font(.system(size: 12))
                                        .foregroundColor(AppleTheme.textSecondary)
                                }
                                Spacer()
                                InfoCircleButton(
                                    title: "Screenshot automatici da scorrimento",
                                    message: "Non devi scattare 15 screenshot a mano:\n\n1. Tocca «Avvia Screenshot Automatici a Scorrimento».\n2. Attiva 5 secondi la Registrazione Schermo ⏺ mentre scorri «Impostazioni → App» (o la «Libreria app» A–Z).\n3. Appena torni su DirectSwitch, il motore video estrae da solo fino a 30 screenshot nitidi, riconosce fino a 200 app con le icone ufficiali e le seleziona tutte!"
                                )
                            }

                            Button(action: {
                                if let external = onStartGuidedAutoCapture {
                                    dismiss()
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                                        external()
                                    }
                                } else {
                                    showLocalAutoGuideSheet = true
                                }
                            }) {
                                HStack(spacing: 8) {
                                    Image(systemName: "record.circle.fill")
                                        .font(.system(size: 15, weight: .bold))
                                    Text("Avvia Screenshot Automatici a Scorrimento")
                                        .font(.system(size: 14, weight: .bold))
                                }
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 44)
                                .background(AppleTheme.blue)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .disabled(isScanningScreenshots)

                            HStack(spacing: 8) {
                                Button(action: scanRecentScreenshotsAutomatically) {
                                    HStack(spacing: 6) {
                                        if isScanningScreenshots {
                                            ProgressView()
                                                .scaleEffect(0.82)
                                                .tint(AppleTheme.blue)
                                        } else {
                                            Image(systemName: "bolt.viewfinder")
                                                .font(.system(size: 13, weight: .bold))
                                        }
                                        Text(isScanningScreenshots ? "Estrazione..." : "Estrai da ultima cattura")
                                            .font(.system(size: 12, weight: .bold))
                                            .lineLimit(1)
                                    }
                                    .foregroundColor(AppleTheme.blue)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 38)
                                    .background(AppleTheme.cardSelected)
                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                }
                                .buttonStyle(.plain)
                                .disabled(isScanningScreenshots)

                                PhotosPicker(
                                    selection: $screenshotPickerItems,
                                    maxSelectionCount: 14,
                                    matching: .any(of: [.videos, .images])
                                ) {
                                    HStack(spacing: 5) {
                                        Image(systemName: "photo.on.rectangle.angled")
                                            .font(.system(size: 12, weight: .semibold))
                                        Text("Scegli video/foto")
                                            .font(.system(size: 12, weight: .bold))
                                            .lineLimit(1)
                                    }
                                    .foregroundColor(AppleTheme.teal)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 38)
                                    .background(AppleTheme.teal.opacity(0.10))
                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                }
                                .disabled(isScanningScreenshots)
                            }

                            if let note = ocrStatusNote, !note.isEmpty {
                                Text(note)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(AppleTheme.green)
                            }

                            if let tempVidId = temporaryRecordingAssetId {
                                Button(action: {
                                    Task {
                                        if await iOSInstalledAppsScanner.deleteTemporaryRecordingAsset(localIdentifier: tempVidId) {
                                            temporaryRecordingAssetId = nil
                                        }
                                    }
                                }) {
                                    HStack(spacing: 5) {
                                        Image(systemName: "trash")
                                            .font(.system(size: 11, weight: .bold))
                                        Text("Elimina registrazione temporanea dal Rullino")
                                            .font(.system(size: 12, weight: .semibold))
                                    }
                                    .foregroundColor(AppleTheme.textSecondary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .appleCard(padding: 14, selected: true)

                        // PASSO 2: Elenco completo app rilevate e selezionate su questo iPhone
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("Passo 2: App selezionate (\(selectedCount)/\(appsCatalog.count))")
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundColor(AppleTheme.textPrimary)
                                Spacer()
                                if !appsCatalog.isEmpty {
                                    Button(action: {
                                        if deselectedAppIds.isEmpty {
                                            deselectedAppIds = Set(appsCatalog.map(\.id))
                                        } else {
                                            deselectedAppIds.removeAll()
                                        }
                                    }) {
                                        Text(deselectedAppIds.isEmpty ? "Deseleziona" : "Seleziona tutte")
                                            .font(.system(size: 13, weight: .semibold))
                                            .foregroundColor(AppleTheme.blue)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }

                            if appsCatalog.isEmpty {
                                Text("Avvia il Passo 1 qui sopra per catturare automaticamente tutte le tue app.")
                                    .font(.system(size: 13))
                                    .foregroundColor(AppleTheme.textSecondary)
                                    .padding(.vertical, 6)
                            } else {
                                VStack(spacing: 0) {
                                    ForEach(Array(appsCatalog.enumerated()), id: \.element.id) { index, app in
                                        let isSelected = !deselectedAppIds.contains(app.id)
                                        Button(action: {
                                            if isSelected {
                                                deselectedAppIds.insert(app.id)
                                            } else {
                                                deselectedAppIds.remove(app.id)
                                            }
                                        }) {
                                            HStack(spacing: 12) {
                                                AppIconThumbnailView(iconUrl: app.iconUrl, size: 38)
                                                Text(app.appName)
                                                    .font(.system(size: 15, weight: .medium))
                                                    .foregroundColor(AppleTheme.textPrimary)
                                                    .lineLimit(1)
                                                Spacer()
                                                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                                    .font(.system(size: 21))
                                                    .foregroundColor(isSelected ? AppleTheme.blue : AppleTheme.textTertiary)
                                            }
                                            .padding(.vertical, 9)
                                            .contentShape(Rectangle())
                                        }
                                        .buttonStyle(.plain)

                                        if index < appsCatalog.count - 1 {
                                            Divider().padding(.leading, 50)
                                        }
                                    }
                                }
                            }
                        }
                        .appleCard(padding: 14)

                        // Card 3: Ricerca rapida opzionale su App Store + Chip suggeriti italiani
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Aggiungi singole app manualmente (opzionale)")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundColor(AppleTheme.textPrimary)

                            HStack(spacing: 8) {
                                Image(systemName: "magnifyingglass")
                                    .foregroundColor(AppleTheme.textSecondary)
                                TextField("Cerca un'app (es. banca, SPID, giochi)...", text: $searchQuery)
                                    .font(.system(size: 14))
                                    .textInputAutocapitalization(.never)
                                    .disableAutocorrection(true)
                                    .onSubmit {
                                        triggerSearch()
                                    }
                                if !searchQuery.isEmpty {
                                    Button(action: {
                                        searchQuery = ""
                                        searchResults = []
                                    }) {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundColor(AppleTheme.textTertiary)
                                    }
                                    .buttonStyle(.plain)
                                }
                                Button(action: triggerSearch) {
                                    Text(isSearching ? "..." : "Cerca")
                                        .font(.system(size: 13, weight: .bold))
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 7)
                                        .background(AppleTheme.blue)
                                        .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)
                                .disabled(searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSearching)
                            }
                            .padding(.horizontal, 12)
                            .frame(height: 44)
                            .background(AppleTheme.inputSurface)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                            if !searchResults.isEmpty {
                                VStack(spacing: 8) {
                                    ForEach(searchResults) { found in
                                        let alreadyAdded = appsCatalog.contains {
                                            $0.packageName.caseInsensitiveCompare(found.packageName) == .orderedSame
                                                || ($0.appStoreId != nil && $0.appStoreId == found.appStoreId)
                                        }
                                        HStack(spacing: 10) {
                                            AppIconThumbnailView(iconUrl: found.iconUrl, size: 34)
                                            Text(found.appName)
                                                .font(.system(size: 14, weight: .semibold))
                                                .foregroundColor(AppleTheme.textPrimary)
                                                .lineLimit(1)
                                            Spacer()
                                            Button(action: {
                                                addAppToSenderCatalog(found)
                                            }) {
                                                HStack(spacing: 4) {
                                                    Image(systemName: alreadyAdded ? "checkmark" : "plus")
                                                        .font(.system(size: 11, weight: .bold))
                                                    Text(alreadyAdded ? "Aggiunta" : "Aggiungi")
                                                        .font(.system(size: 12, weight: .bold))
                                                }
                                                .foregroundColor(alreadyAdded ? AppleTheme.green : AppleTheme.blue)
                                                .padding(.horizontal, 10)
                                                .padding(.vertical, 6)
                                                .background(alreadyAdded ? AppleTheme.green.opacity(0.12) : AppleTheme.cardSelected)
                                                .clipShape(Capsule())
                                            }
                                            .buttonStyle(.plain)
                                            .disabled(alreadyAdded)
                                        }
                                    }
                                }
                                .padding(.top, 4)
                            } else if !availableQuickSuggestions.isEmpty {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 8) {
                                        ForEach(availableQuickSuggestions) { suggestion in
                                            Button(action: {
                                                Task {
                                                    let enriched = await iOSAppStoreCatalogResolver.enrichAppsWithStoreMetadata([suggestion])
                                                    if let first = enriched.first {
                                                        addAppToSenderCatalog(first)
                                                    } else {
                                                        addAppToSenderCatalog(suggestion)
                                                    }
                                                }
                                            }) {
                                                HStack(spacing: 5) {
                                                    Image(systemName: "plus.circle.fill")
                                                        .font(.system(size: 12))
                                                    Text(suggestion.appName)
                                                        .font(.system(size: 12, weight: .semibold))
                                                }
                                                .foregroundColor(AppleTheme.blue)
                                                .padding(.horizontal, 10)
                                                .padding(.vertical, 6)
                                                .background(AppleTheme.cardSelected)
                                                .clipShape(Capsule())
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                }
                            }
                        }
                        .appleCard(padding: 14)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
            }
            .navigationTitle("App su questo iPhone")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Conferma (\(selectedCount))") {
                        dismiss()
                    }
                    .font(.system(size: 15, weight: .bold))
                }
            }
        }
        .preferredColorScheme(.light)
        .sheet(isPresented: $showLocalAutoGuideSheet) {
            AutoAppScrollCaptureGuideSheet {
                iOSPermissionsHelper.openDirectSwitchSettings()
            }
        }
        .onChange(of: screenshotPickerItems) { picked in
            guard !picked.isEmpty else { return }
            processPickedScreenshots(picked)
        }
    }

    private func triggerSearch() {
        let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        isSearching = true
        Task {
            let found = await iOSAppStoreCatalogResolver.searchAppStore(query: q, limit: 10)
            isSearching = false
            searchResults = found
        }
    }

    private func addAppToSenderCatalog(_ app: InstalledAppRecord) {
        let exists = appsCatalog.contains {
            $0.packageName.caseInsensitiveCompare(app.packageName) == .orderedSame
                || ($0.appStoreId != nil && $0.appStoreId == app.appStoreId)
        }
        if !exists {
            appsCatalog.append(app)
        }
        deselectedAppIds.remove(app.id)
        iOSInstalledAppsScanner.appendCustomApps([app])
    }

    private func scanRecentScreenshotsAutomatically() {
        isScanningScreenshots = true
        ocrStatusNote = nil
        Task {
            let result = await iOSInstalledAppsScanner.extractAutomaticScreenshotsAndRecognizeApps(since: nil)
            temporaryRecordingAssetId = result.analyzedVideoAssetLocalIdentifier
            guard result.generatedScreenshotsCount > 0 else {
                isScanningScreenshots = false
                ocrStatusNote = "Nessuna registrazione schermo o screenshot recente trovato (oppure permesso Foto disattivato). Avvia il Passo 1 qui sopra!"
                return
            }
            mergeDiscoveredAppsIntoCatalog(result.discoveredApps, generatedFramesCount: result.generatedScreenshotsCount)
        }
    }

    private func processPickedScreenshots(_ items: [PhotosPickerItem]) {
        isScanningScreenshots = true
        ocrStatusNote = nil
        Task {
            var allDiscovered: [InstalledAppRecord] = []
            var totalFrames = 0
            var uiImages: [UIImage] = []

            for item in items {
                if let pickedVideo = try? await item.loadTransferable(type: PickedScrollVideoFile.self) {
                    let (videoApps, videoFrames) = await iOSInstalledAppsScanner.recognizeAppsFromScrollVideoURL(pickedVideo.url)
                    allDiscovered.append(contentsOf: videoApps)
                    totalFrames += videoFrames
                    try? FileManager.default.removeItem(at: pickedVideo.url)
                } else if let data = try? await item.loadTransferable(type: Data.self),
                          let img = UIImage(data: data) {
                    uiImages.append(img)
                }
            }

            if !uiImages.isEmpty {
                let imageApps = await iOSInstalledAppsScanner.recognizeAppsFromScreenshots(uiImages)
                allDiscovered.append(contentsOf: imageApps)
                totalFrames += uiImages.count
            }

            screenshotPickerItems = []
            mergeDiscoveredAppsIntoCatalog(allDiscovered, generatedFramesCount: totalFrames)
        }
    }

    private func mergeDiscoveredAppsIntoCatalog(_ discovered: [InstalledAppRecord], generatedFramesCount: Int) {
        var newlyAdded = 0
        for app in discovered {
            let exists = appsCatalog.contains {
                $0.packageName.caseInsensitiveCompare(app.packageName) == .orderedSame
                    || ($0.appStoreId != nil && $0.appStoreId == app.appStoreId)
            }
            if !exists {
                appsCatalog.append(app)
                newlyAdded += 1
            }
            deselectedAppIds.remove(app.id)
        }
        if !discovered.isEmpty {
            iOSInstalledAppsScanner.appendCustomApps(discovered)
        }
        isScanningScreenshots = false
        if newlyAdded > 0 {
            ocrStatusNote = "Estratti \(generatedFramesCount) screenshot automatici: aggiunte \(newlyAdded) nuove app (totale \(appsCatalog.count))!"
        } else if !discovered.isEmpty {
            ocrStatusNote = "Analizzati \(generatedFramesCount) fotogrammi: tutte le app trovate sono già selezionate."
        } else {
            ocrStatusNote = "Analizzati \(generatedFramesCount) fotogrammi: nessuna nuova app rilevata."
        }
    }
}

// MARK: - Card Ricevente: Installazione Rapida 1-Tocco Fissa in Basso (`SKOverlay`) + Zero Face ID / Stesso ID Apple

struct ReceiverAppsAutoInstallCard: View {
    private enum AppleAccountMode: String {
        case differentAppleId
        case sameAppleId
    }

    let incomingApps: [InstalledAppRecord]
    @ObservedObject var installer: iOSSequentialAppInstaller
    @AppStorage("directswitch_zero_faceid_setup_done_v1") private var zeroFaceIdSetupDone: Bool = false
    @State private var accountMode: AppleAccountMode = .differentAppleId
    @State private var showZeroFaceIdSteps: Bool = true
    @State private var showFullList: Bool = false

    private var visibleApps: [InstalledAppRecord] {
        showFullList ? installer.apps : Array(installer.apps.prefix(10))
    }

    private var alreadyCount: Int {
        installer.alreadyInstalledIds.count
    }

    private var pendingCount: Int {
        installer.pendingInstallableCount
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                AppleSettingsIcon(systemName: "square.grid.2x2.fill", color: AppleTheme.blue)
                VStack(alignment: .leading, spacing: 2) {
                    Text(installer.apps.isEmpty
                         ? "Installa le tue App"
                         : "App dal vecchio telefono (\(installer.apps.count))")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(AppleTheme.textPrimary)

                    if !installer.apps.isEmpty {
                        Text("\(pendingCount) da installare • \(alreadyCount) già presenti")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(AppleTheme.textSecondary)
                    }
                }
                Spacer()
                InfoCircleButton(
                    title: "Sincronizzazione iCloud & Installazione Rapida",
                    message: "• Con un NUOVO / ALTRO ID Apple: disattiva una sola volta Face ID per App Store seguendo i 2 passaggi qui sotto, poi avvia la barra rapida in basso. Il pulsante «Ottieni» resta fisso sotto il pollice senza aprire 100 schede e lega ogni app al nuovo iCloud.\n\n• Con lo STESSO ID Apple: apri direttamente «Non su questo iPhone» in App Store per scaricarle dalla lista unica con l'icona ☁️."
                )
            }

            // Selettore rapido: Nuovo / Altro ID Apple vs Stesso ID Apple
            HStack(spacing: 6) {
                accountModeTab(
                    title: "Altro / Nuovo ID Apple",
                    icon: "person.crop.circle.badge.plus",
                    mode: .differentAppleId
                )
                accountModeTab(
                    title: "Stesso ID Apple",
                    icon: "icloud.and.arrow.down",
                    mode: .sameAppleId
                )
            }
            .padding(4)
            .background(AppleTheme.inputSurface)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            if accountMode == .sameAppleId {
                sameAppleIdSection
            } else {
                differentAppleIdZeroFaceIdSection
            }

            if installer.apps.isEmpty {
                ApplePrimaryButton(
                    title: "Carica elenco App principali in coda",
                    icon: "square.stack.3d.down.right.fill",
                    color: AppleTheme.blue
                ) {
                    let defaults = iOSInstalledAppsScanner.knownProbes.prefix(16).map {
                        InstalledAppRecord(
                            packageName: $0.bundleId,
                            appName: $0.appName,
                            appStoreId: $0.appStoreId,
                            iconUrl: nil,
                            urlScheme: $0.urlScheme
                        )
                    }
                    installer.configure(with: defaults)
                }
            } else {
                activeInstallerSection
                appsChecklistSection
            }
        }
        .appleCard(padding: 14)
        .onAppear {
            showZeroFaceIdSteps = !zeroFaceIdSetupDone
            installer.configure(with: incomingApps)
        }
        .onChange(of: incomingApps) { updated in
            installer.configure(with: updated)
        }
    }

    private func accountModeTab(title: String, icon: String, mode: AppleAccountMode) -> some View {
        let selected = accountMode == mode
        return Button(action: {
            withAnimation(.easeInOut(duration: 0.18)) {
                accountMode = mode
            }
        }) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .bold))
                Text(title)
                    .font(.system(size: 12, weight: .bold))
                    .lineLimit(1)
            }
            .foregroundColor(selected ? AppleTheme.blue : AppleTheme.textSecondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(selected ? Color.white : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .shadow(color: selected ? Color.black.opacity(0.06) : .clear, radius: 3, y: 1)
        }
        .buttonStyle(.plain)
    }

    private var sameAppleIdSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Con lo stesso ID Apple tutte le app del vecchio iPhone sono già registrate sul tuo account iCloud: puoi scaricarle subito dall'elenco unico con l'icona ☁️ senza Face ID né password.")
                .font(.system(size: 13))
                .foregroundColor(AppleTheme.textSecondary)

            Text("In App Store tocca la tua **foto profilo in alto a destra → App → Non su questo iPhone**.")
                .font(.system(size: 12))
                .foregroundColor(AppleTheme.textPrimary)

            ApplePrimaryButton(
                title: "Apri «Non su questo iPhone» in App Store",
                icon: "icloud.and.arrow.down.fill",
                color: AppleTheme.teal
            ) {
                iOSPermissionsHelper.openAppStorePurchasedSection()
            }
        }
        .padding(12)
        .background(AppleTheme.teal.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .stroke(AppleTheme.teal.opacity(0.30), lineWidth: 1.0)
        )
    }

    private var differentAppleIdZeroFaceIdSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            Button(action: {
                withAnimation(.easeInOut(duration: 0.18)) {
                    showZeroFaceIdSteps.toggle()
                }
            }) {
                HStack(spacing: 8) {
                    Image(systemName: zeroFaceIdSetupDone ? "checkmark.seal.fill" : "bolt.shield.fill")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(zeroFaceIdSetupDone ? AppleTheme.green : AppleTheme.orange)
                    Text(zeroFaceIdSetupDone
                         ? "Zero Face ID / Doppio Clic attivo per app gratuite"
                         : "Prima di iniziare: togli Doppio Clic e Face ID (15 sec)")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(AppleTheme.textPrimary)
                    Spacer()
                    Image(systemName: showZeroFaceIdSteps ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(AppleTheme.textSecondary)
                }
            }
            .buttonStyle(.plain)

            if showZeroFaceIdSteps {
                VStack(alignment: .leading, spacing: 6) {
                    Text("1. Apri **Impostazioni** (tocca «◀ Impostazioni» in alto a sinistra) → **Face ID e codice** → spegni **iTunes Store e App Store**.")
                        .font(.system(size: 12))
                        .foregroundColor(AppleTheme.textPrimary)
                    Text("2. Tocca il **tuo Nome (Apple Account)** in alto → **File multimediali e acquisti → Impostazioni password** → metti **Richiedi password: No** sotto *Download gratuiti*.")
                        .font(.system(size: 12))
                        .foregroundColor(AppleTheme.textPrimary)
                    Text("Così ogni tocco su «Ottieni» scarica subito l'app sulla Home e la sincronizza col nuovo iCloud senza doppio clic né Face ID!")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(AppleTheme.textSecondary)
                }

                HStack(spacing: 8) {
                    Button(action: {
                        iOSPermissionsHelper.openDirectSwitchSettings()
                    }) {
                        HStack(spacing: 5) {
                            Image(systemName: "gearshape.fill")
                                .font(.system(size: 12, weight: .bold))
                            Text("Apri Impostazioni")
                                .font(.system(size: 12, weight: .bold))
                        }
                        .foregroundColor(AppleTheme.blue)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)

                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            zeroFaceIdSetupDone = true
                            showZeroFaceIdSteps = false
                        }
                    }) {
                        HStack(spacing: 5) {
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .bold))
                            Text("Fatto, nascondi")
                                .font(.system(size: 12, weight: .bold))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(AppleTheme.green)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(12)
        .background(zeroFaceIdSetupDone ? AppleTheme.green.opacity(0.08) : AppleTheme.orange.opacity(0.09))
        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .stroke((zeroFaceIdSetupDone ? AppleTheme.green : AppleTheme.orange).opacity(0.32), lineWidth: 1.0)
        )
    }

    @ViewBuilder
    private var activeInstallerSection: some View {
        if installer.isRunningSequence {
            if installer.activeDeliveryMode == .fastBottomOverlay {
                HStack(spacing: 10) {
                    ProgressView()
                        .scaleEffect(0.85)
                        .tint(AppleTheme.blue)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Barra rapida attiva in basso (\(installer.currentQueuePosition) di \(installer.totalQueueCount))")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(AppleTheme.blue)
                        Text("Usa il mini-banner Apple e il tasto «Prossima →» fissi in fondo allo schermo.")
                            .font(.system(size: 11))
                            .foregroundColor(AppleTheme.textSecondary)
                    }
                    Spacer()
                    Button("Ferma") {
                        installer.stopSequence()
                    }
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(AppleTheme.red)
                }
                .padding(11)
                .background(AppleTheme.cardSelected)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        if let active = installer.currentActiveApp {
                            AppIconThumbnailView(iconUrl: active.iconUrl, size: 36)
                        } else {
                            ProgressView()
                                .tint(AppleTheme.blue)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Coda automatica \(installer.currentQueuePosition) di \(installer.totalQueueCount)")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(AppleTheme.blue)
                            Text(installer.currentActiveApp?.appName ?? "Preparazione...")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundColor(AppleTheme.textPrimary)
                                .lineLimit(1)
                        }
                        Spacer()
                        if installer.isLoadingInlineCard {
                            ProgressView()
                                .scaleEffect(0.85)
                                .tint(AppleTheme.blue)
                        }
                    }

                    Text(installer.waitingForExternalReturn
                         ? "Tocca «Ottieni / ☁️» in App Store, poi tocca «◀ DirectSwitch» in alto a sinistra: la prossima app partirà da sola!"
                         : "Tocca «Ottieni / ☁️» sulla scheda e chiudila per passare in automatico alla successiva.")
                        .font(.system(size: 12))
                        .foregroundColor(AppleTheme.textSecondary)

                    HStack(spacing: 8) {
                        if installer.canGoBackInQueue {
                            Button(action: {
                                installer.goBackToPreviousApp()
                            }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "backward.fill")
                                        .font(.system(size: 11, weight: .bold))
                                    Text("Precedente")
                                        .font(.system(size: 12, weight: .bold))
                                }
                                .foregroundColor(AppleTheme.textPrimary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(Color.white)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }

                        Button(action: {
                            installer.skipCurrentAndContinue()
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "forward.fill")
                                    .font(.system(size: 11, weight: .bold))
                                Text("Salta")
                                    .font(.system(size: 13, weight: .bold))
                            }
                            .foregroundColor(AppleTheme.blue)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                        .buttonStyle(.plain)

                        Button(action: {
                            installer.stopSequence()
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "stop.fill")
                                    .font(.system(size: 11, weight: .bold))
                                Text("Ferma")
                                    .font(.system(size: 13, weight: .bold))
                            }
                            .foregroundColor(AppleTheme.red)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(AppleTheme.red.opacity(0.10))
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(12)
                .background(AppleTheme.cardSelected)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(AppleTheme.blue.opacity(0.45), lineWidth: 1.1)
                )
            }
        } else if pendingCount > 0 {
            VStack(alignment: .leading, spacing: 6) {
                ApplePrimaryButton(
                    title: "Avvia Barra Rapida 1-Tocco (\(pendingCount) app)",
                    icon: "bolt.horizontal.circle.fill",
                    color: AppleTheme.blue
                ) {
                    installer.startAutomaticSequence()
                }
                Text("Il tasto «Ottieni» compare fisso in basso senza aprire e chiudere pagine: sincronizza tutte le app col nuovo iCloud in pochi secondi.")
                    .font(.system(size: 11))
                    .foregroundColor(AppleTheme.textSecondary)
            }
        } else {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundColor(AppleTheme.green)
                Text("Tutte le app selezionate sono state avviate o sono già presenti!")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(AppleTheme.green)
            }
            .padding(.vertical, 4)
        }
    }

    private var appsChecklistSection: some View {
        VStack(spacing: 8) {
            VStack(spacing: 0) {
                ForEach(Array(visibleApps.enumerated()), id: \.element.id) { index, app in
                    let isAlready = installer.alreadyInstalledIds.contains(app.id)
                    let isDone = installer.completedIds.contains(app.id)
                    let isSelected = installer.selectedIds.contains(app.id)

                    HStack(spacing: 10) {
                        if !isAlready {
                            Button(action: {
                                installer.toggleSelection(for: app)
                            }) {
                                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 19))
                                    .foregroundColor(isSelected ? AppleTheme.blue : AppleTheme.textTertiary)
                            }
                            .buttonStyle(.plain)
                        }

                        AppIconThumbnailView(iconUrl: app.iconUrl, size: 36)

                        Text(app.appName)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(AppleTheme.textPrimary)
                            .lineLimit(1)

                        Spacer()

                        if isAlready {
                            HStack(spacing: 4) {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 10, weight: .bold))
                                Text("Installata")
                                    .font(.system(size: 11, weight: .bold))
                            }
                            .foregroundColor(AppleTheme.green)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(AppleTheme.green.opacity(0.12))
                            .clipShape(Capsule())
                        } else {
                            Button(action: {
                                installer.installSingleApp(app)
                            }) {
                                HStack(spacing: 4) {
                                    Image(systemName: isDone ? "checkmark.circle.fill" : "icloud.and.arrow.down")
                                        .font(.system(size: 12, weight: .semibold))
                                    Text(isDone ? "Avviata" : "Ottieni")
                                        .font(.system(size: 12, weight: .bold))
                                }
                                .foregroundColor(isDone ? AppleTheme.teal : AppleTheme.blue)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(isDone ? AppleTheme.teal.opacity(0.12) : AppleTheme.cardSelected)
                                .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 8)

                    if index < visibleApps.count - 1 {
                        Divider().padding(.leading, 56)
                    }
                }
            }

            if installer.apps.count > 10 {
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showFullList.toggle()
                    }
                }) {
                    HStack(spacing: 4) {
                        Text(showFullList ? "Mostra meno" : "Mostra tutte le \(installer.apps.count) app")
                            .font(.system(size: 13, weight: .semibold))
                        Image(systemName: showFullList ? "chevron.up" : "chevron.down")
                            .font(.system(size: 11, weight: .bold))
                    }
                    .foregroundColor(AppleTheme.blue)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 2)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Console Flottante Sopra il Mini-Banner di Sistema `SKOverlay` (Ottieni fisso + Prossima sotto il pollice)

struct FastOverlayFloatingControlBar: View {
    @ObservedObject var installer: iOSSequentialAppInstaller

    private var progressFraction: Double {
        guard installer.totalQueueCount > 0 else { return 0 }
        return min(1.0, max(0.05, Double(installer.currentQueuePosition) / Double(installer.totalQueueCount)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 10) {
                if let active = installer.currentActiveApp {
                    AppIconThumbnailView(iconUrl: active.iconUrl, size: 34)
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(installer.isSingleOverlaySession
                             ? "Installazione rapida"
                             : "App \(installer.currentQueuePosition) di \(installer.totalQueueCount)")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(AppleTheme.blue)
                        if installer.isLoadingInlineCard {
                            ProgressView()
                                .scaleEffect(0.7)
                                .tint(AppleTheme.blue)
                        }
                    }
                    Text(installer.currentActiveApp?.appName ?? "")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(AppleTheme.textPrimary)
                        .lineLimit(1)
                }

                Spacer()

                Button(action: {
                    installer.stopSequence()
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(AppleTheme.textTertiary)
                }
                .buttonStyle(.plain)
            }

            if !installer.isSingleOverlaySession {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(AppleTheme.inputSurface)
                            .frame(height: 5)
                        Capsule()
                            .fill(AppleTheme.blue)
                            .frame(width: geo.size.width * progressFraction, height: 5)
                    }
                }
                .frame(height: 5)
            }

            Text("1. Tocca **OTTIENI** nel banner Apple qui sotto  •  2. Tocca **Prossima →**")
                .font(.system(size: 11))
                .foregroundColor(AppleTheme.textSecondary)
                .lineLimit(1)

            HStack(spacing: 8) {
                if installer.canGoBackInQueue {
                    Button(action: {
                        installer.goBackToPreviousApp()
                    }) {
                        HStack(spacing: 3) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 11, weight: .bold))
                            Text("Indietro")
                                .font(.system(size: 12, weight: .bold))
                        }
                        .foregroundColor(AppleTheme.textPrimary)
                        .padding(.horizontal, 11)
                        .frame(height: 40)
                        .background(AppleTheme.inputSurface)
                        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                    }
                    .buttonStyle(.plain)
                } else if !installer.isSingleOverlaySession {
                    Button(action: {
                        installer.skipCurrentAndContinue()
                    }) {
                        Text("Salta")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(AppleTheme.textSecondary)
                            .padding(.horizontal, 12)
                            .frame(height: 40)
                            .background(AppleTheme.inputSurface)
                            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }

                if !installer.isOverlayVisible && !installer.isLoadingInlineCard {
                    Button(action: {
                        installer.reopenCurrentOverlay()
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.up.square.fill")
                                .font(.system(size: 12, weight: .bold))
                            Text("Mostra Ottieni")
                                .font(.system(size: 12, weight: .bold))
                        }
                        .foregroundColor(AppleTheme.blue)
                        .padding(.horizontal, 11)
                        .frame(height: 40)
                        .background(AppleTheme.cardSelected)
                        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }

                Button(action: {
                    installer.confirmCurrentAndAdvance()
                }) {
                    HStack(spacing: 6) {
                        Text(installer.isSingleOverlaySession ? "Fatto • Chiudi" : "Fatto Ottieni → Prossima")
                            .font(.system(size: 13, weight: .bold))
                        if !installer.isSingleOverlaySession {
                            Image(systemName: "arrow.right.circle.fill")
                                .font(.system(size: 14, weight: .bold))
                        }
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 40)
                    .background(AppleTheme.blue)
                    .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(Color.white.opacity(0.98))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(AppleTheme.blue.opacity(0.35), lineWidth: 1.2)
        )
        .shadow(color: Color.black.opacity(0.14), radius: 12, x: 0, y: 4)
    }
}
