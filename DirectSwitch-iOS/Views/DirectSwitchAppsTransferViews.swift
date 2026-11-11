//
//  DirectSwitchAppsTransferViews.swift
//  DirectSwitch-iOS
//
//  Created by Nicolas Donati.
//  Copyright © 2026 Nicolas Donati. Tutti i diritti riservati.
//

import SwiftUI
import PhotosUI
import UIKit

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

    @State private var searchQuery: String = ""
    @State private var searchResults: [InstalledAppRecord] = []
    @State private var isSearching: Bool = false
    @State private var screenshotPickerItems: [PhotosPickerItem] = []
    @State private var isScanningScreenshots: Bool = false
    @State private var ocrStatusNote: String? = nil

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
                        // Card 1: Scansione automatica da Screenshot (per includere il 100% delle app anche oltre il limite Apple di 50 schemi)
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 10) {
                                AppleSettingsIcon(systemName: "text.viewfinder", color: AppleTheme.blue)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Importa tutte le app da Screenshot")
                                        .font(.system(size: 15, weight: .bold))
                                        .foregroundColor(AppleTheme.textPrimary)
                                    Text("Fai lo screenshot della Home o di «Impostazioni → App»")
                                        .font(.system(size: 12))
                                        .foregroundColor(AppleTheme.textSecondary)
                                }
                                Spacer()
                                InfoCircleButton(
                                    title: "Come rilevare il 100% delle tue App",
                                    message: "Per privacy Apple consente il rilevamento diretto immediato fino a 50 schemi di sistema (già eseguito qui sotto!).\n\nSe hai altre app bancarie, giochi o utility sulla Home o in «Impostazioni → App», fai 1 o 2 screenshot e selezionali qui: il motore Vision di iPhone legge tutti i nomi in 2 secondi senza inviare foto sul cloud e le aggiunge con la loro icona ufficiale!"
                                )
                            }

                            PhotosPicker(
                                selection: $screenshotPickerItems,
                                maxSelectionCount: 10,
                                matching: .images
                            ) {
                                HStack(spacing: 8) {
                                    if isScanningScreenshots {
                                        ProgressView()
                                            .scaleEffect(0.85)
                                            .tint(AppleTheme.blue)
                                    } else {
                                        Image(systemName: "photo.badge.plus")
                                            .font(.system(size: 14, weight: .semibold))
                                    }
                                    Text(isScanningScreenshots
                                         ? "Lettura nomi app dagli screenshot..."
                                         : "Scegli screenshot Home o Impostazioni → App")
                                        .font(.system(size: 14, weight: .semibold))
                                }
                                .foregroundColor(AppleTheme.blue)
                                .frame(maxWidth: .infinity)
                                .frame(height: 44)
                                .background(AppleTheme.cardSelected)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                            .disabled(isScanningScreenshots)

                            if let note = ocrStatusNote, !note.isEmpty {
                                Text(note)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(AppleTheme.green)
                            }
                        }
                        .appleCard(padding: 14)

                        // Card 2: Ricerca istantanea su App Store + Chip suggeriti italiani
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Aggiungi altre app manualmente")
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

                        // Card 3: Elenco completo app rilevate su questo iPhone
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("App da passare al nuovo telefono (\(selectedCount)/\(appsCatalog.count))")
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
                                        Text(deselectedAppIds.isEmpty ? "Deseleziona" : "Tutte")
                                            .font(.system(size: 13, weight: .semibold))
                                            .foregroundColor(AppleTheme.blue)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }

                            if appsCatalog.isEmpty {
                                Text("Nessuna app aggiuntiva rilevata: usa la ricerca o importa uno screenshot della Home qui sopra.")
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

    private func processPickedScreenshots(_ items: [PhotosPickerItem]) {
        isScanningScreenshots = true
        ocrStatusNote = nil
        Task {
            var uiImages: [UIImage] = []
            for item in items {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let img = UIImage(data: data) {
                    uiImages.append(img)
                }
            }
            let discovered = await iOSInstalledAppsScanner.recognizeAppsFromScreenshots(uiImages)
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
            screenshotPickerItems = []
            ocrStatusNote = newlyAdded > 0
                ? "Aggiunte \(newlyAdded) nuove app rilevate dagli screenshot!"
                : "Tutte le app leggibili negli screenshot sono già presenti nell'elenco."
        }
    }
}

// MARK: - Card Ricevente: Catalogo App ricevute + Installazione Automatica in Sequenza 1-dopo-l'altra

struct ReceiverAppsAutoInstallCard: View {
    let incomingApps: [InstalledAppRecord]
    @ObservedObject var installer: iOSSequentialAppInstaller
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
                         ? "Scarica le tue App"
                         : "App dal telefono precedente (\(installer.apps.count))")
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
                    title: "Installazione automatica in sequenza",
                    message: "Tocca «Installa tutte una dopo l'altra» per avviare la coda automatica:\n\n• DirectSwitch apre subito la scheda ufficiale della 1ª app pronta sul pulsante «Ottieni / ☁️».\n• Appena confermi e chiudi la scheda (o torni a DirectSwitch con «◀ DirectSwitch» in alto a sinistra), si apre automaticamente l'app successiva senza cercare nulla manualmente!\n• Le app già installate su questo iPhone vengono saltate in automatico."
                )
            }

            if installer.apps.isEmpty {
                Text("Puoi caricare subito le app principali in coda automatica oppure aprire la sezione gratuita «Non su questo iPhone» di App Store.")
                    .font(.system(size: 13))
                    .foregroundColor(AppleTheme.textSecondary)

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
                // Banner attivo durante la sequenza automatica 1-dopo-l'altra
                if installer.isRunningSequence {
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
                            Button(action: {
                                installer.skipCurrentAndContinue()
                            }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "forward.fill")
                                        .font(.system(size: 11, weight: .bold))
                                    Text("Salta questa")
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
                                    Text("Ferma coda")
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
                } else if pendingCount > 0 {
                    ApplePrimaryButton(
                        title: "Installa tutte una dopo l'altra (\(pendingCount) app)",
                        icon: "arrow.down.app.fill",
                        color: AppleTheme.blue
                    ) {
                        installer.startAutomaticSequence()
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

                // Lista app trasferite con icone reali, selezione e stato
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
                                    Text("Già presente")
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
                                        Text(isDone ? "Aperta" : "Ottieni")
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

            Divider()

            Button(action: {
                iOSPermissionsHelper.openAppStorePurchasedSection()
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "bag")
                        .font(.system(size: 12, weight: .semibold))
                    Text("Hai lo stesso ID Apple? Apri anche «Non su questo iPhone»")
                        .font(.system(size: 12, weight: .semibold))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundColor(AppleTheme.textSecondary)
            }
            .buttonStyle(.plain)
        }
        .appleCard(padding: 14)
        .onAppear {
            installer.configure(with: incomingApps)
        }
        .onChange(of: incomingApps) { updated in
            installer.configure(with: updated)
        }
    }
}
