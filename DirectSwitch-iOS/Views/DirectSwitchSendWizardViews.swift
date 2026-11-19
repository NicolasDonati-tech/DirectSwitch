//
//  DirectSwitchSendWizardViews.swift
//  DirectSwitch-iOS
//
//  Created by Nicolas Donati.
//  Copyright © 2026 Nicolas Donati. Tutti i diritti riservati.
//

import SwiftUI
import AVFoundation
import UIKit
import UniformTypeIdentifiers

enum iOSDocumentPickerMode: String, Identifiable {
    case positions
    case folders
    case files
    case audioOrNotes
    case passwordCsv
    case receiverDestinations
    case receiverFallbackRoot

    var id: String { rawValue }
}

@MainActor
final class iOSNativeDocumentPickerPresenter: NSObject, UIDocumentPickerDelegate {
    static let shared = iOSNativeDocumentPickerPresenter()

    private var pendingCallback: (([URL]) -> Void)?
    private var pendingCancelCallback: (() -> Void)?

    func present(
        mode: iOSDocumentPickerMode,
        onPickedURLs: @escaping ([URL]) -> Void,
        onCancelled: (() -> Void)? = nil
    ) {
        guard let topVC = Self.topMostViewController() else {
            onCancelled?()
            return
        }
        if topVC is UIDocumentPickerViewController {
            return
        }
        if topVC is UIAlertController || topVC.isBeingDismissed || topVC.presentedViewController?.isBeingDismissed == true {
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 280_000_000)
                self.present(mode: mode, onPickedURLs: onPickedURLs, onCancelled: onCancelled)
            }
            return
        }
        self.pendingCallback = onPickedURLs
        self.pendingCancelCallback = onCancelled

        let contentTypes: [UTType]
        let asCopy: Bool
        switch mode {
        case .files:
            contentTypes = [.item]
            asCopy = false
        case .audioOrNotes:
            contentTypes = [.audio, .plainText, .pdf, .item]
            asCopy = false
        case .passwordCsv:
            contentTypes = [.commaSeparatedText, .plainText]
            asCopy = false
        case .positions, .folders, .receiverDestinations, .receiverFallbackRoot:
            contentTypes = [.folder]
            asCopy = false
        }
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: contentTypes, asCopy: asCopy)
        picker.allowsMultipleSelection = (mode == .files || mode == .audioOrNotes)
        picker.shouldShowFileExtensions = true
        picker.delegate = self
        picker.modalPresentationStyle = .formSheet
        topVC.present(picker, animated: true)
    }

    nonisolated func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        let picked = urls
        Task { @MainActor in
            let cb = self.pendingCallback
            self.pendingCallback = nil
            self.pendingCancelCallback = nil
            cb?(picked)
        }
    }

    nonisolated func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        Task { @MainActor in
            let cancel = self.pendingCancelCallback
            self.pendingCallback = nil
            self.pendingCancelCallback = nil
            cancel?()
        }
    }

    private static func topMostViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let activeScene = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first
        guard let root = activeScene?.windows.first(where: { $0.isKeyWindow })?.rootViewController
            ?? activeScene?.windows.first?.rootViewController else {
            return nil
        }
        var top = root
        while let presented = top.presentedViewController, !presented.isBeingDismissed {
            top = presented
        }
        return top
    }
}

enum SendTargetDestination: Equatable {
    case newIPhone
    case newAndroid
}

// MARK: - Passo 1 Mittente: Collega il nuovo iPhone o Passa a Android (tutto dentro DirectSwitch)

struct SendConnectStepView: View {
    let targetDestination: SendTargetDestination
    let discoveredBeacons: [DiscoveryBeaconPayload]
    @Binding var selectedBeacon: DiscoveryBeaconPayload?
    @Binding var pinInput: String
    @Binding var showCameraScanner: Bool
    @Binding var manualCodeInput: String
    let isPairingBusy: Bool
    let isLocalNetworkDenied: Bool
    let needsLocalNetworkRedirect: Bool
    let errorNote: String?

    var onConfirmPin: () -> Void
    var onScannedQrCode: (String) -> Void
    var onApplyManualCode: () -> Void
    var onOpenAppSettings: () -> Void

    @State private var showManualField: Bool = false
    @State private var showWifiQrSheet: Bool = false

    private var headerTitle: String {
        "Invia"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                VStack(spacing: 12) {
                    AppleSettingsIcon(systemName: "arrow.right", color: AppleTheme.blue, size: 52)
                        .padding(.top, 12)

                    HStack(spacing: 6) {
                        Text(headerTitle)
                            .font(.system(size: 23, weight: .bold))
                            .foregroundColor(AppleTheme.textPrimary)
                        InfoCircleButton(
                            title: "Come inviare i dati",
                            message: "Sull'altro telefono (iPhone o Android) apri DirectSwitch e tocca 'Ricevi'. Comparirà qui in automatico: toccalo e inserisci il codice a 6 cifre, oppure inquadra il codice QR.\n\nSe il collegamento non parte, assicurati che la voce «Rete locale» sia attiva in Impostazioni → DirectSwitch."
                        )
                    }
                }

                if isLocalNetworkDenied || needsLocalNetworkRedirect {
                    LocalNetworkRedirectBanner(
                        detailMessage: errorNote,
                        onOpenSettings: onOpenAppSettings
                    )
                }

                // Card 1: Rilevamento automatico + Codice a 6 cifre (stile Passa a iOS / Passa a Android, sottotitoli dentro ⓘ)
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 6) {
                        Text("Dispositivi rilevati")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(AppleTheme.textPrimary)
                        InfoCircleButton(
                            title: "Rilevamento automatico",
                            message: "Assicurati che sull'altro telefono sia aperta la schermata 'Ricevi' di DirectSwitch sulla stessa rete Wi-Fi o Hotspot e che «Rete locale» sia attiva."
                        )
                        Spacer()
                        if discoveredBeacons.isEmpty {
                            ProgressView()
                                .scaleEffect(0.85)
                                .tint(AppleTheme.blue)
                        } else {
                            Text(discoveredBeacons.count == 1 ? "1 pronto" : "\(discoveredBeacons.count) pronti")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(AppleTheme.green)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(AppleTheme.green.opacity(0.12))
                                .clipShape(Capsule())
                        }
                    }

                    if discoveredBeacons.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 12) {
                                AppleSettingsIcon(systemName: "wifi", color: AppleTheme.blue)
                                Text("Ricerca dell'altro telefono...")
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundColor(AppleTheme.textPrimary)
                                Spacer()
                            }

                            if !isLocalNetworkDenied && !needsLocalNetworkRedirect {
                                Button(action: onOpenAppSettings) {
                                    HStack(spacing: 6) {
                                        Image(systemName: "gearshape")
                                            .font(.system(size: 12, weight: .semibold))
                                        Text("Non trova il telefono? Verifica «Rete locale» in Impostazioni")
                                            .font(.system(size: 12, weight: .semibold))
                                    }
                                    .foregroundColor(AppleTheme.blue)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 4)
                    } else {
                        VStack(spacing: 8) {
                            ForEach(discoveredBeacons, id: \.sessionId) { beacon in
                                let isSelected = selectedBeacon?.sessionId == beacon.sessionId
                                Button(action: {
                                    withAnimation(.easeInOut(duration: 0.18)) {
                                        selectedBeacon = beacon
                                        showCameraScanner = false
                                    }
                                }) {
                                    HStack(spacing: 12) {
                                        AppleSettingsIcon(
                                            systemName: beacon.receiverPlatform == .IOS ? "iphone" : "apps.iphone",
                                            color: isSelected ? AppleTheme.blue : AppleTheme.slate
                                        )
                                        Text(beacon.receiverName)
                                            .font(.system(size: 16, weight: .semibold))
                                            .foregroundColor(AppleTheme.textPrimary)
                                        Spacer()
                                        Image(systemName: isSelected ? "checkmark.circle.fill" : "chevron.right")
                                            .font(.system(size: isSelected ? 19 : 14, weight: .semibold))
                                            .foregroundColor(isSelected ? AppleTheme.blue : AppleTheme.textTertiary)
                                    }
                                    .padding(12)
                                    .background(isSelected ? AppleTheme.cardSelected : AppleTheme.inputSurface.opacity(0.65))
                                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .stroke(isSelected ? AppleTheme.blue.opacity(0.5) : AppleTheme.cardBorder, lineWidth: 1)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    if let activeBeacon = selectedBeacon {
                        Divider()

                        VStack(spacing: 12) {
                            HStack(spacing: 6) {
                                Text("Codice a 6 cifre")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(AppleTheme.textPrimary)
                                InfoCircleButton(
                                    title: "Codice a 6 cifre",
                                    message: "Inserisci il codice monouso a 6 cifre mostrato sullo schermo di \(activeBeacon.receiverName)."
                                )
                            }

                            PassaAiOSPinInputView(pin: $pinInput) {
                                if !isPairingBusy {
                                    onConfirmPin()
                                }
                            }

                            ApplePrimaryButton(
                                title: isPairingBusy ? "Collegamento in corso..." : "Continua",
                                icon: isPairingBusy ? nil : "arrow.right",
                                color: AppleTheme.blue,
                                isDisabled: pinInput.filter({ $0.isNumber }).count < 6 || isPairingBusy,
                                action: onConfirmPin
                            )
                        }
                        .padding(.top, 4)
                    }
                }
                .appleCard()
                .onChange(of: discoveredBeacons) { updatedList in
                    if let current = selectedBeacon {
                        if let refreshed = updatedList.first(where: { $0.representsSameDevice(as: current) }) {
                            if refreshed != current {
                                selectedBeacon = refreshed
                            }
                        } else {
                            selectedBeacon = updatedList.first
                        }
                    } else if let first = updatedList.first {
                        selectedBeacon = first
                    }
                }

                // Card 2: Fotocamera QR (inquadra direttamente il QR del nuovo iPhone o Android)
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 6) {
                        Text("Collega con codice QR")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(AppleTheme.textPrimary)
                        InfoCircleButton(
                            title: "Collegamento tramite codice QR",
                            message: targetDestination == .newAndroid
                                ? "Inquadra il codice QR mostrato nella schermata 'Ricevi' del nuovo Android (funziona anche in Hotspot 5GHz senza rete Wi-Fi di casa)."
                                : "Inquadra il codice QR mostrato nella schermata 'Ricevi' del nuovo iPhone."
                        )
                        Spacer()
                    }

                    AppleSecondaryButton(
                        title: showCameraScanner ? "Chiudi fotocamera" : "Inquadra codice QR",
                        icon: showCameraScanner ? "xmark" : "camera.viewfinder",
                        tint: AppleTheme.blue
                    ) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showCameraScanner.toggle()
                        }
                    }

                    if showCameraScanner {
                        QrCameraScannerView { code in
                            onScannedQrCode(code)
                        }
                        .frame(height: 230)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(AppleTheme.blue.opacity(0.45), lineWidth: 1.5)
                        )
                    }

                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            showManualField.toggle()
                        }
                    }) {
                        HStack(spacing: 4) {
                            Text(showManualField ? "Nascondi inserimento manuale" : "Incolla codice di collegamento")
                                .font(.system(size: 13, weight: .medium))
                            Image(systemName: showManualField ? "chevron.up" : "chevron.down")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundColor(AppleTheme.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 2)
                    }
                    .buttonStyle(.plain)

                    if showManualField {
                        HStack(spacing: 8) {
                            TextField("Incolla qui il codice", text: $manualCodeInput)
                                .font(.system(size: 14))
                                .padding(.horizontal, 12)
                                .frame(height: 42)
                                .background(AppleTheme.inputSurface)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                            Button(action: onApplyManualCode) {
                                Text("Collega")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 14)
                                    .frame(height: 42)
                                    .background(AppleTheme.blue)
                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .disabled(manualCodeInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                }
                .appleCard()

                // Card 3: Condividi Wi-Fi via QR (per collegare subito il nuovo iPhone al Wi-Fi senza iCloud)
                HStack(spacing: 12) {
                    AppleSettingsIcon(systemName: "wifi.circle.fill", color: AppleTheme.teal)
                    Button(action: { showWifiQrSheet = true }) {
                        Text("Condividi Wi-Fi al nuovo telefono via QR")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(AppleTheme.blue)
                    }
                    .buttonStyle(.plain)
                    Spacer()
                    InfoCircleButton(
                        title: "Condividi Wi-Fi senza iCloud",
                        message: "Se il nuovo iPhone non è ancora collegato al tuo Wi-Fi di casa, genera qui un codice QR Wi-Fi standard: basterà inquadrarlo con l'app Fotocamera del nuovo iPhone per connetterlo in 1 tocco senza digitare la password."
                    )
                }
                .appleCard(padding: 13)

                if let err = errorNote, !err.isEmpty, !(isLocalNetworkDenied || needsLocalNetworkRedirect) {
                    HStack(spacing: 10) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .foregroundColor(AppleTheme.red)
                        Text(err)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(AppleTheme.red)
                        Spacer()
                    }
                    .appleCard(padding: 14)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 28)
        }
        .sheet(isPresented: $showWifiQrSheet) {
            WiFiShareQrSheetView()
        }
        .onAppear {
            if selectedBeacon == nil, let first = discoveredBeacons.first {
                selectedBeacon = first
            }
        }
    }
}

// MARK: - Generatore QR Wi-Fi standard (inquadrabile dalla Fotocamera nativa iOS senza iCloud)

private struct WiFiShareQrSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var ssid: String = ""
    @State private var password: String = ""

    private static func escapeWifiField(_ raw: String) -> String {
        raw
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: ";", with: "\\;")
            .replacingOccurrences(of: ",", with: "\\,")
            .replacingOccurrences(of: ":", with: "\\:")
    }

    private var wifiPayload: String {
        let s = Self.escapeWifiField(ssid.trimmingCharacters(in: .whitespacesAndNewlines))
        let p = Self.escapeWifiField(password)
        if p.isEmpty {
            return "WIFI:T:nopass;S:\(s);;"
        }
        return "WIFI:T:WPA;S:\(s);P:\(p);;"
    }

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text("QR Wi-Fi Rapido")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(AppleTheme.textPrimary)
                Spacer()
                Button("Chiudi") { dismiss() }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(AppleTheme.blue)
            }
            .padding(.top, 6)

            Text("Inserisci il nome della rete Wi-Fi e la password: sul nuovo iPhone apri l'app Fotocamera e inquadra il QR per collegarti subito.")
                .font(.system(size: 13))
                .foregroundColor(AppleTheme.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: 10) {
                TextField("Nome rete Wi-Fi (SSID)", text: $ssid)
                    .font(.system(size: 15))
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
                    .padding(.horizontal, 12)
                    .frame(height: 44)
                    .background(AppleTheme.inputSurface)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                SecureField("Password Wi-Fi", text: $password)
                    .font(.system(size: 15))
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
                    .padding(.horizontal, 12)
                    .frame(height: 44)
                    .background(AppleTheme.inputSurface)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            if !ssid.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               let qrImg = DirectSwitchUIHelpers.generateQrImage(from: wifiPayload) {
                Image(uiImage: qrImg)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 190, height: 190)
                    .padding(12)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(AppleTheme.cardBorder, lineWidth: 0.8)
                    )
            } else {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(AppleTheme.inputSurface)
                    .frame(width: 190, height: 190)
                    .overlay(
                        VStack(spacing: 8) {
                            Image(systemName: "qrcode")
                                .font(.system(size: 36))
                                .foregroundColor(AppleTheme.textTertiary)
                            Text("Digita il nome Wi-Fi")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(AppleTheme.textTertiary)
                        }
                    )
            }

            Spacer(minLength: 0)
        }
        .padding(20)
        .background(AppleTheme.backgroundGradient.ignoresSafeArea())
        .presentationDetents([.height(470), .large])
        .presentationDragIndicator(.visible)
    }
}

// MARK: - Passo 2 Mittente: Scegli cosa copiare (tendine inline stile iPhone, tutto da spuntare)

struct SendCategoriesStepView: View {
    let pairedPayload: QrPairingPayload
    let scanSummary: iOSLocalDeviceScanSummary?
    let isLocalProUnlocked: Bool
    let pickedDocuments: [(ManifestItem, URL)]
    let pickedAudioFiles: [(ManifestItem, URL)]
    let availablePhotoAlbums: [String]
    let documentPrecheck: iOSDocumentsPrecheckReport?
    var isLoadingPositions: Bool = false

    let contactsPreload: ContactsPreloadState
    let photosPreload: PhotosPreloadState
    let videosPreload: VideosPreloadState
    let calendarsSync: DateSyncPreloadState
    let remindersSync: DateSyncPreloadState

    let senderAppsCatalog: [InstalledAppRecord]
    let deselectedSenderAppIds: Set<String>
    let verifiedLocalAppsCount: Int
    let photoDetectedAppsCount: Int
    let selectedBundleIdsSet: Set<String>
    let selectedStoreIdsSet: Set<Int>
    let categoryIconOverrides: [String: String]
    let isLoadingAppsCatalog: Bool
    let appImportStatusNote: String?

    @Binding var includeContacts: Bool
    @Binding var includePhotos: Bool
    @Binding var includeVideos: Bool
    @Binding var includeCalendars: Bool
    @Binding var calendarsUpToTodayOnly: Bool
    @Binding var includeReminders: Bool
    @Binding var remindersUpToTodayOnly: Bool
    @Binding var includeDocuments: Bool
    @Binding var includeAudio: Bool
    @Binding var includeApps: Bool
    @Binding var includeWhatsApp: Bool
    @Binding var mediaFilters: MediaTransferFilterOptions
    var activeDeltaBaseline: CompletedMigrationRecord? = nil
    @Binding var forceBatteryTriage: Bool

    var onPreloadContacts: () -> Void
    var onPreloadPhotos: () -> Void
    var onPreloadVideos: () -> Void
    var onRefreshCalendars: () -> Void
    var onRefreshReminders: () -> Void
    var onToggleCatalogApp: (InstalledAppRecord) -> Void
    var onToggleCategoryAllApps: (AppQuickCategory, Bool) -> Void
    var onToggleCategorySingleApp: (InstalledAppRecord, Bool) -> Void
    var onAddSearchApp: (InstalledAppRecord) -> Void
    var onRescanAutomaticApps: () -> Void
    var onRequestPhotoScanForApps: () -> Void
    var onResetAppsToDetectedOnly: (() -> Void)? = nil
    var onAddFolders: () -> Void
    var onPickAudioOrNotes: () -> Void
    var onClearAudioFiles: () -> Void
    var onPickPasswordCsv: () -> Void
    var onTogglePositionSelection: ((String, Bool) -> Void)? = nil
    var onRemovePosition: ((String) -> Void)? = nil
    var onRefreshDocumentCheck: () -> Void
    var onClearStagedFiles: () -> Void
    var onOpenProSheet: () -> Void
    var onChangePairedDevice: () -> Void
    var onStartCopy: () -> Void

    @State private var expandedAppCategoryIds: Set<String> = ["social_messaging", "banks_payments"]
    @State private var catalogFilterQuery: String = ""
    @State private var appSearchQuery: String = ""
    @State private var appSearchResults: [AppStoreSearchHit] = []
    @State private var isSearchingAppStore: Bool = false

    private var allSelected: Bool {
        includeContacts && includePhotos && includeVideos && includeCalendars && includeReminders && includeDocuments && includeAudio && includeApps && includeWhatsApp
    }

    private var anySelected: Bool {
        includeContacts || includePhotos || includeVideos || includeCalendars || includeReminders || includeDocuments || includeAudio || includeApps || includeWhatsApp
    }

    private var isOnlyWhatsAppSelected: Bool {
        includeWhatsApp && !includeContacts && !includePhotos && !includeVideos && !includeCalendars && !includeReminders && !includeDocuments && !includeAudio && !includeApps
    }

    private var isCrossOs: Bool {
        pairedPayload.receiverPlatform == .ANDROID
    }

    private var docsCount: Int {
        documentPrecheck?.totalFiles
            ?? scanSummary?.documentsCount
            ?? pickedDocuments.filter { $0.0.category == .DOCUMENTS }.count
    }

    private var docFoldersCount: Int {
        documentPrecheck?.folderSummaries.count
            ?? scanSummary?.documentFoldersCount
            ?? 0
    }

    private var displayedCatalogApps: [InstalledAppRecord] {
        senderAppsCatalog.filter {
            !isCrossOs || !iOSInstalledAppsScanner.isGoogleAppPreinstalledOnAndroid($0)
        }
    }

    private var selectedAppsCount: Int {
        displayedCatalogApps.filter { !deselectedSenderAppIds.contains($0.id) }.count
    }

    private var visibleQuickCategories: [AppQuickCategory] {
        iOSInstalledAppsScanner.curatedCategories.filter {
            !isCrossOs || !$0.isGoogleAndroidPreinstalledCategory
        }
    }

    private var shortTodayLabel: String {
        Self.shortDateFormatter.string(from: Date())
    }

    private static let shortDateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.locale = Locale(identifier: "it_IT")
        df.dateStyle = .medium
        df.timeStyle = .none
        return df
    }()

    private static let syncDateTimeFormatter: DateFormatter = {
        let df = DateFormatter()
        df.locale = Locale(identifier: "it_IT")
        df.dateStyle = .medium
        df.timeStyle = .short
        return df
    }()

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                HStack {
                    Text("Passo 2 di 3")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(AppleTheme.blue)
                    Spacer()
                    Button(action: {
                        let target = !allSelected
                        withAnimation(.easeInOut(duration: 0.22)) {
                            includeContacts = target
                            includePhotos = target
                            includeVideos = target
                            includeCalendars = target
                            includeReminders = target
                            includeDocuments = target
                            includeAudio = target
                            includeApps = target
                            includeWhatsApp = target
                        }
                    }) {
                        Text(allSelected ? "Deseleziona tutto" : "Seleziona tutto")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(AppleTheme.blue)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 8)

                // Dispositivo collegato
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        ZStack {
                            Circle()
                                .fill(AppleTheme.green.opacity(0.15))
                                .frame(width: 36, height: 36)
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 19, weight: .semibold))
                                .foregroundColor(AppleTheme.green)
                        }

                        Text("Collegato a \(pairedPayload.receiverName)")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(AppleTheme.textPrimary)

                        InfoCircleButton(
                            title: "Stato collegamento",
                            message: !isCrossOs
                                ? "Collegamento diretto attivo e pronto alla copia speculare dei dati selezionati."
                                : "Collegamento diretto attivo iPhone ↔ Android per copiare tutto gratuitamente su telefoni già configurati, senza formattare."
                        )

                        Spacer()

                        Button(action: onChangePairedDevice) {
                            Text("Cambia")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(AppleTheme.blue)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .appleCard(padding: 14, selected: true)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Cosa inviare")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(AppleTheme.textPrimary)
                    Text("Spunta ogni voce per aprire la configurazione del passaggio al nuovo telefono.")
                        .font(.system(size: 12.5))
                        .foregroundColor(AppleTheme.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // 1. Rubrica contatti
                categoryDropdownCard(
                    icon: "person.crop.circle.fill",
                    iconColor: AppleTheme.blue,
                    title: "Rubrica contatti",
                    countBadge: badgeForCount(
                        max(contactsPreload.totalCount, scanSummary?.contactsCount ?? 0),
                        unit: "contatti"
                    ),
                    infoMessage: "Trasferisce tutti i contatti completi di foto profilo, compleanni, indirizzi di casa/lavoro, azienda, siti web ed etichette dei numeri unendo eventuali duplicati.",
                    isOn: $includeContacts
                ) {
                    contactsDropdownContent
                }

                // 2. Foto, Live Photos e Album
                categoryDropdownCard(
                    icon: "photo.fill",
                    iconColor: AppleTheme.orange,
                    title: "Foto, Live Photos e Album",
                    countBadge: badgeForPhotos(
                        count: max(photosPreload.totalCount, scanSummary?.photosCount ?? 0),
                        liveCount: max(photosPreload.livePhotosCount, scanSummary?.livePhotosCount ?? 0),
                        bytes: max(photosPreload.estimatedBytes, scanSummary?.photosBytes ?? 0)
                    ),
                    infoMessage: "Copia tutte le foto nella qualità originale HEIC/RAW preservando Live Photos animate (.HEIC + .MOV), Preferiti, data di scatto, posizione GPS e Album utente.",
                    isOn: $includePhotos
                ) {
                    photosDropdownContent
                }

                // 3. Video originali
                categoryDropdownCard(
                    icon: "video.fill",
                    iconColor: AppleTheme.red,
                    title: "Video originali",
                    countBadge: badgeForMedia(
                        count: max(videosPreload.totalCount, scanSummary?.videosCount ?? 0),
                        bytes: max(videosPreload.estimatedBytes, scanSummary?.videosBytes ?? 0),
                        unit: "video"
                    ),
                    infoMessage: "Copia tutti i video in risoluzione originale (inclusi 4K 60fps e Slow-Motion) in streaming su disco senza compressione.",
                    isOn: $includeVideos
                ) {
                    videosDropdownContent
                }

                // 4. Calendari
                categoryDropdownCard(
                    icon: "calendar",
                    iconColor: AppleTheme.slate,
                    title: "Calendari",
                    countBadge: badgeForCount(
                        calendarsUpToTodayOnly ? calendarsSync.totalUpToTodayCount : max(calendarsSync.totalAllCount, scanSummary?.calendarEventsCount ?? 0),
                        unit: "eventi"
                    ),
                    infoMessage: "Importa lo storico completo degli appuntamenti (-10/+10 anni) con ricorrenze annuali/settimanali e avvisi oppure fino alla data odierna.",
                    isOn: $includeCalendars
                ) {
                    calendarsDropdownContent
                }

                // 5. Promemoria
                categoryDropdownCard(
                    icon: "checklist",
                    iconColor: AppleTheme.blue,
                    title: "Promemoria",
                    countBadge: badgeForCount(
                        remindersUpToTodayOnly ? remindersSync.totalUpToTodayCount : max(remindersSync.totalAllCount, scanSummary?.remindersCount ?? 0),
                        unit: "promemoria"
                    ),
                    infoMessage: "Trasferisce le tue liste di Promemoria Apple con scadenze, note, priorità e stato di completamento senza usare iCloud.",
                    isOn: $includeReminders
                ) {
                    remindersDropdownContent
                }

                // 6. Documenti e File
                categoryDropdownCard(
                    icon: "doc.fill",
                    iconColor: AppleTheme.teal,
                    title: "Documenti e Posizioni File",
                    countBadge: docsCount > 0 ? "\(max(1, docFoldersCount)) cartelle • \(docsCount) file" : "iCloud Drive, Su iPhone, Chrome",
                    infoMessage: "Copia intere posizioni (iCloud Drive, Su iPhone, Chrome o altra posizione aggiunta dall'utente) ricreando identica tutta la gerarchia sul nuovo telefono.",
                    isOn: $includeDocuments
                ) {
                    documentsDropdownContent
                }

                // 6b. Audio, Memo Vocali & Note
                categoryDropdownCard(
                    icon: "waveform",
                    iconColor: AppleTheme.teal,
                    title: "Audio, Memo Vocali & Note",
                    countBadge: pickedAudioFiles.isEmpty ? "Memo vocali, MP3, Note" : "\(pickedAudioFiles.count) file pronti",
                    infoMessage: "Trasferisce registrazioni vocali, file audio (.m4a, .mp3, .wav) e Note esportate (.txt, .pdf) nella cartella dedicata del nuovo telefono.",
                    isOn: $includeAudio
                ) {
                    AudioAndNotesDropdownBody(
                        pickedAudioFiles: pickedAudioFiles,
                        onPickAudioOrNotes: onPickAudioOrNotes,
                        onClearAudio: onClearAudioFiles
                    )
                }

                // 7. App scaricate
                categoryDropdownCard(
                    icon: "square.grid.2x2.fill",
                    iconColor: AppleTheme.blue,
                    title: "App scaricate",
                    countBadge: selectedAppsCount > 0 ? "\(selectedAppsCount) app pronte" : nil,
                    infoMessage: "Rileva automaticamente le app installate su questo iPhone tramite verifica schemi iOS + Album/Foto e permette di aggiungerne altre dalle categorie in stile iPhone.",
                    isOn: $includeApps
                ) {
                    appsDropdownContent
                }

                // 8. Chat WhatsApp
                categoryDropdownCard(
                    icon: "bubble.left.and.bubble.right.fill",
                    iconColor: AppleTheme.green,
                    title: "Chat WhatsApp",
                    countBadge: "Gratuito • Codice QR",
                    infoMessage: isCrossOs
                        ? "Guida gratuita al passaggio delle chat dentro WhatsApp sul nuovo Android tramite una sola scansione QR (senza Android Switch e senza formattare)."
                        : "Apre una schermata dedicata gratuita per trasferire la cronologia chat dentro WhatsApp tramite Codice QR.",
                    isOn: $includeWhatsApp
                ) {
                    whatsAppDropdownContent
                }

                // Modalità Recupero Delta attiva (salta i file già copiati)
                if let delta = activeDeltaBaseline {
                    HStack(spacing: 10) {
                        AppleSettingsIcon(systemName: "clock.arrow.circlepath", color: AppleTheme.teal)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Recupero Delta attivo")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(AppleTheme.textPrimary)
                            Text("Salta i \(delta.transferredDedupKeys.count) elementi già copiati su \(delta.peerName): trasferisce solo le novità.")
                                .font(.system(size: 12))
                                .foregroundColor(AppleTheme.textSecondary)
                        }
                        Spacer()
                    }
                    .appleCard()
                }

                // Triage Batteria Critica (auto ≤ 15% o attivabile manualmente)
                HStack(spacing: 12) {
                    AppleSettingsIcon(systemName: "battery.25", color: AppleTheme.orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Triage Batteria Critica")
                            .font(.system(size: 14.5, weight: .semibold))
                            .foregroundColor(AppleTheme.textPrimary)
                        Text("Salva prima Password, Documenti, Audio e Foto Preferite (auto ≤ 15%).")
                            .font(.system(size: 12))
                            .foregroundColor(AppleTheme.textSecondary)
                    }
                    Spacer()
                    Toggle("", isOn: $forceBatteryTriage)
                        .labelsHidden()
                        .tint(AppleTheme.orange)
                }
                .appleCard()

                ApplePrimaryButton(
                    title: isOnlyWhatsAppSelected
                        ? "Vai al passaggio Chat WhatsApp"
                        : (activeDeltaBaseline != nil ? "Copia solo le novità (Delta)" : "Copia le voci selezionate"),
                    icon: isOnlyWhatsAppSelected
                        ? "bubble.left.and.bubble.right.fill"
                        : "arrow.right",
                    color: isOnlyWhatsAppSelected
                        ? AppleTheme.green
                        : AppleTheme.blue,
                    isDisabled: !anySelected,
                    action: onStartCopy
                )
                .padding(.top, 4)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 28)
        }
    }

    // MARK: - Contenitore fisarmonica inline per ogni voce

    @ViewBuilder
    private func categoryDropdownCard<Content: View>(
        icon: String,
        iconColor: Color,
        title: String,
        countBadge: String? = nil,
        infoMessage: String,
        premiumBadge: Bool = false,
        isOn: Binding<Bool>,
        @ViewBuilder dropdownContent: () -> Content
    ) -> some View {
        VStack(spacing: 0) {
            CleanCategoryToggleRow(
                icon: icon,
                iconColor: iconColor,
                title: title,
                countBadge: countBadge,
                infoMessage: infoMessage,
                premiumBadge: premiumBadge,
                isOn: isOn
            )

            if isOn.wrappedValue {
                Divider()
                    .padding(.horizontal, 14)

                VStack(alignment: .leading, spacing: 10) {
                    dropdownContent()
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AppleTheme.inputSurface.opacity(0.45))
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .appleCard(padding: 0, selected: isOn.wrappedValue)
        .animation(.easeInOut(duration: 0.22), value: isOn.wrappedValue)
    }

    // MARK: - Tendina 1: Rubrica contatti

    @ViewBuilder
    private var contactsDropdownContent: some View {
        if scanSummary?.contactsDenied == true {
            permissionDeniedInlineView(
                message: "Permesso Contatti disattivato su questo iPhone.",
                buttonTitle: "Abilita Contatti in Impostazioni"
            )
        } else {
            let total = max(contactsPreload.totalCount, scanSummary?.contactsCount ?? 0)
            let loaded = contactsPreload.isCompleted ? total : contactsPreload.loadedCount

            HStack(spacing: 8) {
                Image(systemName: contactsPreload.isLoading ? "arrow.triangle.2.circlepath" : "checkmark.circle.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(contactsPreload.isLoading ? AppleTheme.blue : AppleTheme.green)

                Text(contactsPreload.isLoading
                    ? "Precaricamento rubrica: \(loaded) / \(max(loaded, total)) contatti"
                    : "\(total) contatti totali preparati")
                    .font(.system(size: 13.5, weight: .bold))
                    .foregroundColor(AppleTheme.textPrimary)

                Spacer()

                if !contactsPreload.isLoading {
                    Button(action: onPreloadContacts) {
                        Text("Ricarica")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(AppleTheme.blue)
                    }
                    .buttonStyle(.plain)
                }
            }

            if contactsPreload.isLoading || total > 0 {
                ProgressView(
                    value: Double(min(loaded, max(1, total))),
                    total: Double(max(1, total))
                )
                .tint(contactsPreload.isLoading ? AppleTheme.blue : AppleTheme.green)
            }

            Text("Include numeri con etichette, foto profilo, email, indirizzi, compleanni ed eventuale unione duplicati.")
                .font(.system(size: 12))
                .foregroundColor(AppleTheme.textSecondary)
        }
    }

    // MARK: - Tendina 2: Foto, Live Photos e Album

    @ViewBuilder
    private var photosDropdownContent: some View {
        if scanSummary?.photosDenied == true {
            permissionDeniedInlineView(
                message: "Permesso Foto disattivato su questo iPhone.",
                buttonTitle: "Abilita Foto in Impostazioni"
            )
        } else {
            let total = max(photosPreload.totalCount, scanSummary?.photosCount ?? 0)
            let loaded = photosPreload.isCompleted ? total : photosPreload.loadedCount
            let live = max(photosPreload.livePhotosCount, scanSummary?.livePhotosCount ?? 0)
            let albums = max(photosPreload.albumsCount, scanSummary?.photoAlbumsCount ?? 0)
            let iCloud = max(photosPreload.iCloudCount, scanSummary?.iCloudPhotosCount ?? 0)
            let bytes = max(photosPreload.estimatedBytes, scanSummary?.photosBytes ?? 0)

            HStack(spacing: 8) {
                Image(systemName: photosPreload.isLoading ? "photo.stack.fill" : "checkmark.circle.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(photosPreload.isLoading ? AppleTheme.orange : AppleTheme.green)

                Text(photosPreload.isLoading
                    ? "Precaricamento immagini: \(loaded) / \(max(loaded, total)) foto"
                    : "\(total) foto totali preparate")
                    .font(.system(size: 13.5, weight: .bold))
                    .foregroundColor(AppleTheme.textPrimary)

                Spacer()

                if !photosPreload.isLoading {
                    Button(action: onPreloadPhotos) {
                        Text("Ricarica")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(AppleTheme.blue)
                    }
                    .buttonStyle(.plain)
                }
            }

            if photosPreload.isLoading || total > 0 {
                ProgressView(
                    value: Double(min(loaded, max(1, total))),
                    total: Double(max(1, total))
                )
                .tint(photosPreload.isLoading ? AppleTheme.orange : AppleTheme.green)
            }

            Text("\(live) Live Photos • \(albums) album utente • \(bytes > 0 ? DirectSwitchUIHelpers.formatBytes(bytes) : "qualità originale HEIC/RAW")")
                .font(.system(size: 12))
                .foregroundColor(AppleTheme.textSecondary)

            if iCloud > 0 {
                Text("\(iCloud) foto ottimizzate su iCloud: verranno scaricate automaticamente durante la copia (mantieni attiva Internet su questo iPhone).")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundColor(AppleTheme.blue)
            }

            PhotoFilterChipsBar(filters: $mediaFilters, availableAlbums: availablePhotoAlbums)
        }
    }

    // MARK: - Tendina 3: Video originali

    @ViewBuilder
    private var videosDropdownContent: some View {
        if scanSummary?.photosDenied == true {
            permissionDeniedInlineView(
                message: "Permesso Foto e Video disattivato su questo iPhone.",
                buttonTitle: "Abilita Foto in Impostazioni"
            )
        } else {
            let total = max(videosPreload.totalCount, scanSummary?.videosCount ?? 0)
            let loaded = videosPreload.isCompleted ? total : videosPreload.loadedCount
            let iCloud = max(videosPreload.iCloudCount, scanSummary?.iCloudVideosCount ?? 0)
            let bytes = max(videosPreload.estimatedBytes, scanSummary?.videosBytes ?? 0)

            HStack(spacing: 8) {
                Image(systemName: videosPreload.isLoading ? "video.fill" : "checkmark.circle.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(videosPreload.isLoading ? AppleTheme.red : AppleTheme.green)

                Text(videosPreload.isLoading
                    ? "Precaricamento video: \(loaded) / \(max(loaded, total)) video"
                    : "\(total) video originali preparati")
                    .font(.system(size: 13.5, weight: .bold))
                    .foregroundColor(AppleTheme.textPrimary)

                Spacer()

                if !videosPreload.isLoading {
                    Button(action: onPreloadVideos) {
                        Text("Ricarica")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(AppleTheme.blue)
                    }
                    .buttonStyle(.plain)
                }
            }

            if videosPreload.isLoading || total > 0 {
                ProgressView(
                    value: Double(min(loaded, max(1, total))),
                    total: Double(max(1, total))
                )
                .tint(videosPreload.isLoading ? AppleTheme.red : AppleTheme.green)
            }

            Text("Qualità 4K 60fps e Slow-Motion preservata\(bytes > 0 ? " • \(DirectSwitchUIHelpers.formatBytes(bytes))" : "").")
                .font(.system(size: 12))
                .foregroundColor(AppleTheme.textSecondary)

            if iCloud > 0 {
                Text("\(iCloud) video su iCloud: verranno scaricati automaticamente uno alla volta durante la copia (mantieni attiva Internet su questo iPhone).")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundColor(AppleTheme.blue)
            }

            VideoFilterChipsBar(filters: $mediaFilters)
        }
    }

    // MARK: - Tendina 4: Calendari

    @ViewBuilder
    private var calendarsDropdownContent: some View {
        if scanSummary?.calendarsDenied == true {
            permissionDeniedInlineView(
                message: "Permesso Calendari disattivato su questo iPhone.",
                buttonTitle: "Abilita Calendari in Impostazioni"
            )
        } else {
            let activeCount = calendarsUpToTodayOnly
                ? calendarsSync.totalUpToTodayCount
                : max(calendarsSync.totalAllCount, scanSummary?.calendarEventsCount ?? 0)

            HStack(spacing: 8) {
                if calendarsSync.isLoading {
                    ProgressView().scaleEffect(0.85)
                } else {
                    Image(systemName: "calendar.badge.checkmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(AppleTheme.green)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(calendarsSync.isLoading
                        ? "Aggiornamento alla data odierna in corso..."
                        : "Aggiornato al \(formattedSyncTimestamp(calendarsSync.lastUpdatedAt))")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(AppleTheme.textPrimary)
                    Text("\(activeCount) eventi pronti al passaggio")
                        .font(.system(size: 12))
                        .foregroundColor(AppleTheme.textSecondary)
                }

                Spacer()

                if !calendarsSync.isLoading {
                    Button(action: onRefreshCalendars) {
                        Text("Aggiorna")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(AppleTheme.blue)
                    }
                    .buttonStyle(.plain)
                }
            }

            Toggle(isOn: $calendarsUpToTodayOnly) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Trasferisci solo fino ad oggi (\(shortTodayLabel))")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundColor(AppleTheme.textPrimary)
                    Text("Se spento trasferisce sia storico sia eventi futuri (-10/+10 anni).")
                        .font(.system(size: 11))
                        .foregroundColor(AppleTheme.textSecondary)
                }
            }
            .tint(AppleTheme.green)
        }
    }

    // MARK: - Tendina 5: Promemoria

    @ViewBuilder
    private var remindersDropdownContent: some View {
        if scanSummary?.remindersDenied == true {
            permissionDeniedInlineView(
                message: "Permesso Promemoria disattivato su questo iPhone.",
                buttonTitle: "Abilita Promemoria in Impostazioni"
            )
        } else {
            let activeCount = remindersUpToTodayOnly
                ? remindersSync.totalUpToTodayCount
                : max(remindersSync.totalAllCount, scanSummary?.remindersCount ?? 0)

            HStack(spacing: 8) {
                if remindersSync.isLoading {
                    ProgressView().scaleEffect(0.85)
                } else {
                    Image(systemName: "checklist.checked")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(AppleTheme.green)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(remindersSync.isLoading
                        ? "Aggiornamento alla data odierna in corso..."
                        : "Aggiornato al \(formattedSyncTimestamp(remindersSync.lastUpdatedAt))")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(AppleTheme.textPrimary)
                    Text("\(activeCount) promemoria pronti al passaggio")
                        .font(.system(size: 12))
                        .foregroundColor(AppleTheme.textSecondary)
                }

                Spacer()

                if !remindersSync.isLoading {
                    Button(action: onRefreshReminders) {
                        Text("Aggiorna")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(AppleTheme.blue)
                    }
                    .buttonStyle(.plain)
                }
            }

            Toggle(isOn: $remindersUpToTodayOnly) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Solo scadenze fino ad oggi (\(shortTodayLabel))")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundColor(AppleTheme.textPrimary)
                    Text("Se spento trasferisce tutte le liste complete anche con scadenze future.")
                        .font(.system(size: 11))
                        .foregroundColor(AppleTheme.textSecondary)
                }
            }
            .tint(AppleTheme.green)
        }
    }

    // MARK: - Tendina 6: Documenti e Posizioni File (solo iCloud Drive, Su iPhone, Chrome + aggiungi posizione)

    @ViewBuilder
    private var documentsDropdownContent: some View {
        let activePrecheck = documentPrecheck
        let locationSummaries = activePrecheck?.locationSummaries ?? scanSummary?.documentLocationSummaries ?? []
        let customLocations = locationSummaries.filter {
            iOSDocumentPresetKind.match(for: $0) == nil && ($0.isRemovableBookmark || $0.fileCount > 0)
        }
        let unreadableCount = activePrecheck?.unreadableFilesCount ?? 0
        let hasAuthorizedAnyPositions = (activePrecheck?.authorizedBookmarkFoldersCount ?? 0) > 0 || !pickedDocuments.isEmpty

        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Aggiungi e spunta le posizioni")
                    .font(.system(size: 13.5, weight: .bold))
                    .foregroundColor(AppleTheme.textPrimary)
                Text(isLoadingPositions
                    ? "Caricamento posizione e cartelle in corso…"
                    : (docsCount > 0
                        ? "\(max(1, docFoldersCount)) cartelle preparate • \(docsCount) file • \(DirectSwitchUIHelpers.formatBytes(activePrecheck?.totalBytes ?? scanSummary?.documentsBytes ?? 0))"
                        : "Seleziona iCloud Drive, Su iPhone, Chrome o un'altra posizione"))
                    .font(.system(size: 12))
                    .foregroundColor(isLoadingPositions ? AppleTheme.blue : AppleTheme.textSecondary)
            }

            Spacer()

            if isLoadingPositions {
                ProgressView().scaleEffect(0.85)
            } else {
                Button(action: onRefreshDocumentCheck) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.clockwise")
                        Text("Ricontrolla")
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(AppleTheme.blue)
                }
                .buttonStyle(.plain)
            }

            InfoCircleButton(
                title: "Posizioni File su iPhone",
                message: "Scegli direttamente le posizioni intere invece dei singoli file:\n\n• iCloud Drive\n• Su iPhone\n• Chrome (Su iPhone → Chrome)\n• Altra posizione (Google Drive / USB / Cartella)\n\nTocca una posizione non ancora collegata, entra dentro nell'app File e premi «Apri» in alto a destra per preparare tutte le sue cartelle."
            )
        }

        if unreadableCount > 0 {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(AppleTheme.orange)
                    .font(.system(size: 14))
                Text("\(unreadableCount) file sono solo su iCloud e non scaricati in locale: scaricali in File prima di avviare.")
                    .font(.system(size: 12))
                    .foregroundColor(AppleTheme.textPrimary)
            }
            .padding(10)
            .background(AppleTheme.orange.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }

        VStack(spacing: 7) {
            ForEach(iOSDocumentPresetKind.allCases) { preset in
                let matched = locationSummaries.first { iOSDocumentPresetKind.match(for: $0) == preset }
                documentPositionRow(
                    title: preset.title,
                    iconName: preset.systemIcon,
                    summary: matched
                )
            }

            ForEach(customLocations) { custom in
                documentPositionRow(
                    title: custom.locationName,
                    iconName: "folder.fill",
                    summary: custom
                )
            }
        }

        AppleSecondaryButton(
            title: "Aggiungi altra posizione",
            icon: "externaldrive.fill",
            tint: AppleTheme.blue,
            action: onAddFolders
        )

        GuidedPasswordsSectionBody(
            stagedCsvCount: pickedDocuments.filter { $0.0.fileName.lowercased().hasSuffix(".csv") }.count,
            onPickPasswordCsv: onPickPasswordCsv
        )

        if hasAuthorizedAnyPositions {
            HStack {
                Spacer()
                Button("Rimuovi posizioni aggiunte", action: onClearStagedFiles)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(AppleTheme.red)
                    .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private func documentPositionRow(
        title: String,
        iconName: String,
        summary: iOSDocumentLocationSummary?
    ) -> some View {
        if let loc = summary {
            HStack(spacing: 10) {
                Button {
                    onTogglePositionSelection?(loc.locationId, !loc.isSelected)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: loc.isSelected ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 19, weight: .semibold))
                            .foregroundColor(loc.isSelected ? AppleTheme.blue : AppleTheme.textTertiary)

                        Image(systemName: iconName)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(loc.isSelected ? AppleTheme.teal : AppleTheme.textSecondary)
                            .frame(width: 24)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(title)
                                .font(.system(size: 13.5, weight: .bold))
                                .foregroundColor(loc.isSelected ? AppleTheme.textPrimary : AppleTheme.textSecondary)
                                .lineLimit(1)
                            Text(preparedFoldersSubtitle(for: loc))
                                .font(.system(size: 12))
                                .foregroundColor(loc.isSelected ? AppleTheme.green : AppleTheme.textSecondary)
                        }
                        Spacer(minLength: 4)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if loc.isRemovableBookmark {
                    Button {
                        onRemovePosition?(loc.locationId)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundColor(AppleTheme.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .background(loc.isSelected ? AppleTheme.cardSurface : AppleTheme.cardSurface.opacity(0.6))
            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .stroke(loc.isSelected ? AppleTheme.blue.opacity(0.35) : AppleTheme.cardBorder, lineWidth: 0.9)
            )
        } else {
            Button(action: onAddFolders) {
                HStack(spacing: 10) {
                    Image(systemName: iconName)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(AppleTheme.blue)
                        .frame(width: 24)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.system(size: 13.5, weight: .bold))
                            .foregroundColor(AppleTheme.textPrimary)
                        Text("Tocca per aggiungere posizione e preparare tutto")
                            .font(.system(size: 11.5))
                            .foregroundColor(AppleTheme.textSecondary)
                    }
                    Spacer()
                    Text("Aggiungi")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundColor(AppleTheme.textPrimary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(AppleTheme.inputSurface)
                        .clipShape(Capsule())
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 9)
                .background(AppleTheme.cardSurface)
                .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .stroke(AppleTheme.cardBorder, lineWidth: 0.9)
                )
            }
            .buttonStyle(.plain)
        }
    }

    private func preparedFoldersSubtitle(for loc: iOSDocumentLocationSummary) -> String {
        let foldersCount = max(loc.folderCount, loc.fileCount > 0 ? 1 : 0)
        let foldersPart = foldersCount == 1
            ? "1 cartella preparata"
            : "\(foldersCount) cartelle preparate"
        if loc.fileCount > 0 {
            return "\(foldersPart) • \(loc.fileCount) file • \(DirectSwitchUIHelpers.formatBytes(loc.totalBytes))"
        }
        return foldersPart
    }

    // MARK: - Tendina 7: App scaricate (tutto inline: rilevate con icona+nome + categorie estese iPhone + ricerca)

    @ViewBuilder
    private var appsDropdownContent: some View {
        // Blocco 1: App rilevate automaticamente su questo iPhone
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                if isLoadingAppsCatalog {
                    ProgressView().scaleEffect(0.85)
                } else {
                    Image(systemName: "checkmark.shield.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(AppleTheme.green)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("App verificate su questo iPhone (\(selectedAppsCount))")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(AppleTheme.textPrimary)
                    Text(photoDetectedAppsCount > 0
                        ? "\(verifiedLocalAppsCount) schemi iOS + \(photoDetectedAppsCount) da Album/Foto"
                        : "\(verifiedLocalAppsCount) app rilevate in automatico su iPhone")
                        .font(.system(size: 11.5))
                        .foregroundColor(AppleTheme.textSecondary)
                }
                Spacer()
                Button(action: onRescanAutomaticApps) {
                    Text("Aggiorna")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(AppleTheme.blue)
                }
                .buttonStyle(.plain)
                .disabled(isLoadingAppsCatalog)
            }

            if !iOSPhotoKitMigrator.isAuthorized() && scanSummary?.photosDenied != true {
                Button(action: onRequestPhotoScanForApps) {
                    HStack(spacing: 8) {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(AppleTheme.blue)
                        Text("Rileva altre app anche da Album e Metadati Foto")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(AppleTheme.blue)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(AppleTheme.blue)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(AppleTheme.cardSelected)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
            }

            if isCrossOs {
                Text("Le app Google di sistema (Gmail, Maps, Chrome, YouTube, Drive) restano escluse perché già su Android.")
                    .font(.system(size: 11.5))
                    .foregroundColor(AppleTheme.textTertiary)
            }

            if let note = appImportStatusNote, !note.isEmpty {
                Text(note)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(note.hasPrefix("⚠") ? AppleTheme.orange : AppleTheme.green)
            }

            if !displayedCatalogApps.isEmpty {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 10, alignment: .top), count: 4),
                    spacing: 12
                ) {
                    ForEach(displayedCatalogApps) { app in
                        let checked = !deselectedSenderAppIds.contains(app.id)
                        let icon = app.iconUrl ?? categoryIconOverrides[app.packageName.lowercased()]
                        iPhoneAppGridTile(
                            appName: app.appName,
                            iconUrl: icon,
                            isSelected: checked,
                            iconSize: 52
                        ) {
                            onToggleCatalogApp(app)
                        }
                    }
                }
                .padding(.top, 2)
            } else {
                Text("Nessuna app extra rilevata finora in automatico. Scegli dalle categorie qui sotto oppure usa la ricerca.")
                    .font(.system(size: 12))
                    .foregroundColor(AppleTheme.textSecondary)
            }

            if let resetAction = onResetAppsToDetectedOnly,
               displayedCatalogApps.count > verifiedLocalAppsCount + photoDetectedAppsCount {
                HStack {
                    Spacer()
                    Button(action: resetAction) {
                        Text("Ripristina solo rilevate")
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundColor(AppleTheme.orange)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(12)
        .background(AppleTheme.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))

        // Blocco 2: Categorie estese in stile iPhone (icona + nome per ogni app)
        VStack(alignment: .leading, spacing: 9) {
            let totalCuratedAppsCount = visibleQuickCategories.reduce(0) { $0 + $1.apps.count }
            HStack {
                Text("Categorie estese stile iPhone")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(AppleTheme.textPrimary)
                Spacer()
                Text("\(visibleQuickCategories.count) cat. • \(totalCuratedAppsCount) app")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundColor(AppleTheme.blue)
            }

            HStack(spacing: 8) {
                Image(systemName: "line.3.horizontal.decrease.circle")
                    .foregroundColor(AppleTheme.textSecondary)
                TextField("Filtra velocemente tra le \(totalCuratedAppsCount) app del catalogo...", text: $catalogFilterQuery)
                    .font(.system(size: 13))
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
                if !catalogFilterQuery.isEmpty {
                    Button {
                        catalogFilterQuery = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(AppleTheme.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 11)
            .frame(height: 38)
            .background(AppleTheme.cardSurface)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(AppleTheme.cardBorder, lineWidth: 0.8)
            )

            let cleanFilter = catalogFilterQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let filteredQuickCategories: [AppQuickCategory] = {
                guard !cleanFilter.isEmpty else { return visibleQuickCategories }
                return visibleQuickCategories.compactMap { cat in
                    if cat.title.lowercased().contains(cleanFilter) { return cat }
                    let matching = cat.apps.filter { $0.appName.lowercased().contains(cleanFilter) || $0.packageName.lowercased().contains(cleanFilter) }
                    guard !matching.isEmpty else { return nil }
                    return AppQuickCategory(
                        id: cat.id,
                        title: cat.title,
                        iconName: cat.iconName,
                        isGoogleAndroidPreinstalledCategory: cat.isGoogleAndroidPreinstalledCategory,
                        apps: matching
                    )
                }
            }()

            VStack(spacing: 8) {
                ForEach(filteredQuickCategories) { category in
                    let isExpanded = !cleanFilter.isEmpty || expandedAppCategoryIds.contains(category.id)
                    iPhoneAppCategoryAccordionCard(
                        category: category,
                        iconOverrides: categoryIconOverrides,
                        isExpanded: isExpanded,
                        isAppSelected: isQuickAppSelected,
                        onToggleExpand: {
                            withAnimation(.easeInOut(duration: 0.18)) {
                                if expandedAppCategoryIds.contains(category.id) {
                                    expandedAppCategoryIds.remove(category.id)
                                } else {
                                    expandedAppCategoryIds.insert(category.id)
                                }
                            }
                        },
                        onToggleWholeCategory: { currentlyAllSelected in
                            onToggleCategoryAllApps(category, currentlyAllSelected)
                        },
                        onToggleApp: { item, currentlySelected in
                            onToggleCategorySingleApp(item, currentlySelected)
                        }
                    )
                }
            }
        }

        // Blocco 3: Ricerca esatta su App Store (icona + nome, zero "+" blu)
        VStack(alignment: .leading, spacing: 8) {
            Text("Cerca altre app su App Store")
                .font(.system(size: 13.5, weight: .bold))
                .foregroundColor(AppleTheme.textPrimary)

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(AppleTheme.textSecondary)
                TextField("Cerca un'app (es. banca, SPID, utility)...", text: $appSearchQuery)
                    .font(.system(size: 13.5))
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
                    .onSubmit {
                        triggerInlineAppStoreSearch()
                    }
                if !appSearchQuery.isEmpty {
                    Button(action: {
                        appSearchQuery = ""
                        appSearchResults = []
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(AppleTheme.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
                Button(action: triggerInlineAppStoreSearch) {
                    Text(isSearchingAppStore ? "..." : "Cerca")
                        .font(.system(size: 12.5, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(AppleTheme.blue)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(appSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSearchingAppStore)
            }
            .padding(.horizontal, 12)
            .frame(height: 42)
            .background(AppleTheme.cardSurface)
            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .stroke(AppleTheme.cardBorder, lineWidth: 0.8)
            )

            if !appSearchResults.isEmpty {
                VStack(spacing: 8) {
                    ForEach(appSearchResults) { hit in
                        let found = hit.record
                        let alreadyAdded = isQuickAppSelected(found)
                        HStack(spacing: 10) {
                            AppIconThumbnailView(iconUrl: found.iconUrl, size: 38)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(found.appName)
                                    .font(.system(size: 13.5, weight: .semibold))
                                    .foregroundColor(AppleTheme.textPrimary)
                                    .lineLimit(1)
                                if let dev = hit.developerName, !dev.isEmpty {
                                    Text(dev)
                                        .font(.system(size: 11))
                                        .foregroundColor(AppleTheme.textSecondary)
                                        .lineLimit(1)
                                }
                            }
                            Spacer()
                            Button(action: {
                                var tagged = found
                                tagged.detectionSource = "Aggiunta da ricerca"
                                onAddSearchApp(tagged)
                            }) {
                                HStack(spacing: 4) {
                                    if alreadyAdded {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 11, weight: .bold))
                                    }
                                    Text(alreadyAdded ? "Selezionata" : "Seleziona")
                                        .font(.system(size: 12, weight: .bold))
                                }
                                .foregroundColor(alreadyAdded ? AppleTheme.green : AppleTheme.textPrimary)
                                .padding(.horizontal, 11)
                                .padding(.vertical, 6)
                                .background(alreadyAdded ? AppleTheme.green.opacity(0.12) : AppleTheme.inputSurface)
                                .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                            .disabled(alreadyAdded)
                        }
                    }
                }
                .padding(.top, 2)
            }
        }
        .padding(12)
        .background(AppleTheme.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
    }

    // MARK: - Tendina 8: Chat WhatsApp

    @ViewBuilder
    private var whatsAppDropdownContent: some View {
        HStack(spacing: 8) {
            Image(systemName: "qrcode")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(AppleTheme.green)
            Text("Passaggio guidato gratuito tramite Codice QR")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(AppleTheme.textPrimary)
        }
        Text(isCrossOs
            ? "Trasferisce cronologia chat, foto, video e messaggi vocali direttamente dentro WhatsApp verso Android senza resettare il telefono."
            : "Trasferisce tutta la cronologia chat, allegati e vocali direttamente da iPhone a iPhone dentro WhatsApp senza occupare spazio iCloud.")
            .font(.system(size: 12))
            .foregroundColor(AppleTheme.textSecondary)
    }

    // MARK: - Helpers UI & Ricerca

    @ViewBuilder
    private func permissionDeniedInlineView(message: String, buttonTitle: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.shield.fill")
                    .foregroundColor(AppleTheme.orange)
                Text(message)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundColor(AppleTheme.textPrimary)
            }
            AppleSecondaryButton(
                title: buttonTitle,
                icon: "gearshape.fill",
                tint: AppleTheme.orange
            ) {
                iOSPermissionsHelper.openDirectSwitchSettings()
            }
        }
    }

    private func isQuickAppSelected(_ app: InstalledAppRecord) -> Bool {
        let pkgLower = app.packageName.lowercased()
        if selectedBundleIdsSet.contains(pkgLower) { return true }
        if let sid = app.appStoreId, selectedStoreIdsSet.contains(sid) { return true }
        return false
    }

    private func triggerInlineAppStoreSearch() {
        let q = appSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        isSearchingAppStore = true
        Task {
            let found = await iOSAppStoreCatalogResolver.searchAppStoreDetailed(query: q, limit: 12)
            isSearchingAppStore = false
            appSearchResults = found
        }
    }

    private func formattedSyncTimestamp(_ date: Date?) -> String {
        Self.syncDateTimeFormatter.string(from: date ?? Date())
    }

    private func badgeForCount(_ count: Int?, unit: String) -> String? {
        guard let c = count, c > 0 else { return nil }
        return "\(c) \(unit)"
    }

    private func badgeForPhotos(count: Int?, liveCount: Int?, bytes: Int64?) -> String? {
        guard let c = count, c > 0 else { return nil }
        let livePart = (liveCount ?? 0) > 0 ? " (\(liveCount!) Live)" : ""
        if let b = bytes, b > 0 {
            return "\(c) foto\(livePart) • \(DirectSwitchUIHelpers.formatBytes(b))"
        }
        return "\(c) foto\(livePart)"
    }

    private func badgeForMedia(count: Int?, bytes: Int64?, unit: String) -> String? {
        guard let c = count, c > 0 else { return nil }
        if let b = bytes, b > 0 {
            return "\(c) \(unit) • \(DirectSwitchUIHelpers.formatBytes(b))"
        }
        return "\(c) \(unit)"
    }
}

// MARK: - Scanner fotocamera nativo iOS per codici QR DirectSwitch

final class ScannerHostViewController: UIViewController {
    var session: AVCaptureSession?
    var previewLayer: AVCaptureVideoPreviewLayer?

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stopSession()
    }

    func stopSession() {
        guard let activeSession = session, activeSession.isRunning else { return }
        DispatchQueue.global(qos: .utility).async {
            activeSession.stopRunning()
        }
    }
}

struct QrCameraScannerView: UIViewControllerRepresentable {
    var onCodeScanned: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onCodeScanned: onCodeScanned)
    }

    func makeUIViewController(context: Context) -> ScannerHostViewController {
        let vc = ScannerHostViewController()
        vc.view.backgroundColor = .black
        let session = AVCaptureSession()
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            return vc
        }
        session.addInput(input)
        let output = AVCaptureMetadataOutput()
        if session.canAddOutput(output) {
            session.addOutput(output)
            output.setMetadataObjectsDelegate(context.coordinator, queue: DispatchQueue.main)
            if output.availableMetadataObjectTypes.contains(.qr) {
                output.metadataObjectTypes = [.qr]
            }
        }
        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspectFill
        previewLayer.frame = vc.view.bounds
        vc.view.layer.addSublayer(previewLayer)
        vc.session = session
        vc.previewLayer = previewLayer
        context.coordinator.session = session

        DispatchQueue.global(qos: .userInitiated).async {
            session.startRunning()
        }
        return vc
    }

    func updateUIViewController(_ uiViewController: ScannerHostViewController, context: Context) {
        uiViewController.previewLayer?.frame = uiViewController.view.bounds
    }

    static func dismantleUIViewController(_ uiViewController: ScannerHostViewController, coordinator: Coordinator) {
        uiViewController.stopSession()
    }

    final class Coordinator: NSObject, AVCaptureMetadataOutputObjectsDelegate {
        let onCodeScanned: (String) -> Void
        weak var session: AVCaptureSession?
        private var didScan = false

        init(onCodeScanned: @escaping (String) -> Void) {
            self.onCodeScanned = onCodeScanned
        }

        func metadataOutput(
            _ output: AVCaptureMetadataOutput,
            didOutput metadataObjects: [AVMetadataObject],
            from connection: AVCaptureConnection
        ) {
            guard !didScan,
                  let readable = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
                  let stringValue = readable.stringValue else { return }
            didScan = true
            let activeSession = session
            DispatchQueue.global(qos: .utility).async {
                activeSession?.stopRunning()
            }
            onCodeScanned(stringValue)
        }
    }
}

// MARK: - Scanner QR dedicato per aprire direttamente «Trasferisci la cronologia chat» di WhatsApp senza passare dalla Fotocamera iOS

struct WhatsAppMigrationQrScannerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var scannerSessionToken: Int = 0
    @State private var feedbackMessage: String? = nil

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                HStack(spacing: 8) {
                    AppleSettingsIcon(systemName: "qrcode.viewfinder", color: AppleTheme.green)
                    Text("Inquadra QR di WhatsApp")
                        .font(.system(size: 19, weight: .bold))
                        .foregroundColor(AppleTheme.textPrimary)
                }
                Spacer()
                Button("Chiudi") {
                    dismiss()
                }
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(AppleTheme.blue)
            }
            .padding(.top, 6)

            Text("Inquadra il codice QR mostrato da WhatsApp sul nuovo telefono: DirectSwitch aprirà direttamente la schermata «Trasferisci la cronologia chat» dentro WhatsApp Personale, saltando la Fotocamera di iPhone e il bottone giallo.")
                .font(.system(size: 13))
                .foregroundColor(AppleTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            ZStack {
                QrCameraScannerView { rawCode in
                    DirectSwitchTransportViewModel.openWhatsAppMigrationQrPayload(rawCode) { opened, errNote in
                        if opened {
                            dismiss()
                        } else {
                            feedbackMessage = errNote ?? "Codice QR non valido: inquadra il QR mostrato dentro WhatsApp sul nuovo telefono."
                            scannerSessionToken += 1
                        }
                    }
                }
                .id(scannerSessionToken)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(AppleTheme.green, style: StrokeStyle(lineWidth: 3, dash: [18, 10]))
                    .frame(width: 225, height: 225)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 310)
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(AppleTheme.cardBorder, lineWidth: 1)
            )

            if let msg = feedbackMessage, !msg.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(AppleTheme.orange)
                    Text(msg)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(AppleTheme.orange)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AppleTheme.orange.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            Spacer(minLength: 0)
        }
        .padding(20)
        .background(AppleTheme.backgroundGradient.ignoresSafeArea())
        .presentationDetents([.height(540), .large])
        .presentationDragIndicator(.visible)
    }
}
