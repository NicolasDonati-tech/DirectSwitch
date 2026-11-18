//
//  DirectSwitchMainView.swift
//  DirectSwitch-iOS
//
//  Created by Nicolas Donati.
//  Copyright © 2026 Nicolas Donati. Tutti i diritti riservati.
//

import SwiftUI
import UniformTypeIdentifiers
import UIKit

private enum DirectSwitchWizardStep: Equatable {
    case home
    case receiveWaitCode
    case receiveConnected
    case sendConnect
    case sendSelectCategories
    case transferPreparing
    case transferProgress
}

@MainActor
private final class SerializedCategoryTaskQueue {
    private var pending: Task<Void, Never>?

    func enqueue(_ operation: @escaping @MainActor () async -> Void) {
        let previous = pending
        pending = Task { @MainActor in
            await previous?.value
            guard !Task.isCancelled else { return }
            await operation()
        }
    }

    func cancelAll() {
        pending?.cancel()
        pending = nil
    }
}

struct DirectSwitchMainView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var transport = DirectSwitchTransportViewModel()
    @StateObject private var appInstaller = iOSSequentialAppInstaller()

    @State private var activeStep: DirectSwitchWizardStep = .home
    @State private var isReceiverMode: Bool = false
    @State private var sendTargetDestination: SendTargetDestination = .newIPhone

    // Stato accoppiamento Ricevente / Mittente
    @State private var receiverQrPayload: QrPairingPayload? = nil
    @State private var receiverDeniedSummary: String? = nil
    @State private var pairedTargetPayload: QrPairingPayload? = nil
    @State private var selectedBeacon: DiscoveryBeaconPayload? = nil
    @State private var pinCodeInput: String = ""
    @State private var manualCodeInput: String = ""
    @State private var showCameraScanner: Bool = false
    @State private var isPairingBusy: Bool = false
    @State private var pairingErrorNote: String? = nil

    // Categorie di trasferimento (tutto da spuntare all'avvio)
    @State private var includeContacts: Bool = false
    @State private var includePhotos: Bool = false
    @State private var includeVideos: Bool = false
    @State private var includeCalendars: Bool = false
    @State private var includeReminders: Bool = false
    @State private var includeDocuments: Bool = false
    @State private var includeApps: Bool = false
    @State private var includeWhatsApp: Bool = false

    @State private var calendarsUpToTodayOnly: Bool = false
    @State private var remindersUpToTodayOnly: Bool = false
    @State private var contactsPreload: ContactsPreloadState = ContactsPreloadState()
    @State private var photosPreload: PhotosPreloadState = PhotosPreloadState()
    @State private var videosPreload: VideosPreloadState = VideosPreloadState()
    @State private var calendarsSync: DateSyncPreloadState = DateSyncPreloadState()
    @State private var remindersSync: DateSyncPreloadState = DateSyncPreloadState()
    @State private var categoryTaskQueue = SerializedCategoryTaskQueue()

    // Catalogo App rilevate su questo iPhone (schemi verificati + Foto/Album + Categorie estese)
    @State private var senderAppsCatalog: [InstalledAppRecord] = []
    @State private var verifiedLocalAppsCount: Int = 0
    @State private var photoDetectedAppsCount: Int = 0
    @State private var deselectedSenderAppIds: Set<String> = []
    @State private var isLoadingAppsCatalog: Bool = false
    @State private var categoryIconOverrides: [String: String] = [:]
    @State private var appImportStatusNote: String? = nil

    private var selectedSenderApps: [InstalledAppRecord] {
        senderAppsCatalog.filter { !deselectedSenderAppIds.contains($0.id) }
    }

    private var selectedSenderBundleIdsSet: Set<String> {
        Set(selectedSenderApps.map { $0.packageName.lowercased() })
    }

    private var selectedSenderStoreIdsSet: Set<Int> {
        Set(selectedSenderApps.compactMap(\.appStoreId))
    }

    // File e archivi WhatsApp allegati + pre-controllo posizioni su iPhone
    @State private var isLoadingDocumentPositions: Bool = false
    @State private var pickedDocuments: [(ManifestItem, URL)] = []
    @State private var documentPrecheckReport: iOSDocumentsPrecheckReport? = nil
    @State private var pendingTransferPrecheckAlert: iOSDocumentsPrecheckReport? = nil
    @State private var sharedVaultToast: String? = nil
    @State private var receiverAuthorizedDestinations: [String] = iOSDocumentsSandboxBridge.receiverDestinationsSummary().destinations
    @State private var receiverFallbackRootLabel: String? = iOSDocumentsSandboxBridge.receiverDestinationsSummary().fallbackRoot

    // Scansione locale e stato trasferimento
    @State private var scanSummary: iOSLocalDeviceScanSummary? = nil

    private var isDedicatedWhatsAppScreenActive: Bool {
        guard activeStep == .transferProgress, transport.errorMessage == nil else { return false }
        let scope = transport.activeTransferScope
        if scope.isWhatsAppOnly {
            return true
        }
        return !scope.hasAnyStandardDataCategory && transport.isCompleted && transport.pendingNativeWhatsAppMigration
    }

    private var topBarTitle: String {
        switch activeStep {
        case .home:
            return "DirectSwitch"
        case .receiveWaitCode:
            return "Ricevi"
        case .receiveConnected:
            return "Collegato"
        case .sendConnect:
            return "Invia"
        case .sendSelectCategories:
            return "Cosa inviare"
        case .transferPreparing:
            return "Preparazione"
        case .transferProgress:
            if isDedicatedWhatsAppScreenActive {
                return "Chat WhatsApp"
            }
            if isReceiverMode && transport.isCompleted && transport.activeTransferScope.isAppsOnly {
                return "App pronte"
            }
            return transport.isCompleted ? "Completato" : "Copia dati"
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppleTheme.backgroundGradient
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    AppleTopNavigationBar(
                        title: topBarTitle,
                        showBackButton: activeStep != .home,
                        onBack: handleBackNavigation
                    )

                    if let toast = sharedVaultToast, activeStep != .transferProgress {
                        HStack(spacing: 10) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(AppleTheme.green)
                            Text(toast)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(AppleTheme.textPrimary)
                                .lineLimit(2)
                            Spacer()
                            Button(action: { sharedVaultToast = nil }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(AppleTheme.textTertiary)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(AppleTheme.cardSurface)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(AppleTheme.cardBorder, lineWidth: 0.8)
                        )
                        .padding(.horizontal, 16)
                        .padding(.top, 10)
                    }

                    Group {
                        switch activeStep {
                        case .home:
                            DirectSwitchHomeView(
                                onStartReceive: startReceiveWizard,
                                onStartSendToIPhone: { startSendWizard(destination: .newIPhone) },
                                onStartSendToAndroid: { startSendWizard(destination: .newAndroid) }
                            )

                        case .receiveWaitCode:
                            if let qr = receiverQrPayload {
                                ReceivePairingStepView(
                                    qrPayload: qr,
                                    pairingPin: transport.activePairingPin,
                                    isLocalNetworkDenied: transport.isLocalNetworkDenied,
                                    deniedPermissionsNote: receiverDeniedSummary,
                                    errorMessage: transport.errorMessage,
                                    authorizedDestinations: receiverAuthorizedDestinations,
                                    fallbackDestinationRoot: receiverFallbackRootLabel,
                                    onAuthorizeDestinations: {
                                        presentDocumentPicker(mode: .receiverDestinations)
                                    },
                                    onChooseFallbackRoot: {
                                        presentDocumentPicker(mode: .receiverFallbackRoot)
                                    },
                                    onClearDestinations: {
                                        iOSDocumentsSandboxBridge.clearReceiverDestinations()
                                        receiverAuthorizedDestinations = []
                                        receiverFallbackRootLabel = nil
                                    },
                                    onOpenAppSettings: {
                                        DirectSwitchTransportViewModel.openAppSettings()
                                    },
                                    onCancel: {
                                        finishAndReturnHome()
                                    }
                                )
                            }

                        case .receiveConnected:
                            ReceiveConnectedStepView(
                                peerName: transport.peerName,
                                authorizedDestinations: receiverAuthorizedDestinations,
                                fallbackDestinationRoot: receiverFallbackRootLabel,
                                onAuthorizeDestinations: {
                                    presentDocumentPicker(mode: .receiverDestinations)
                                },
                                onChooseFallbackRoot: {
                                    presentDocumentPicker(mode: .receiverFallbackRoot)
                                },
                                onClearDestinations: {
                                    iOSDocumentsSandboxBridge.clearReceiverDestinations()
                                    receiverAuthorizedDestinations = []
                                    receiverFallbackRootLabel = nil
                                },
                                onCancel: {
                                    finishAndReturnHome()
                                }
                            )

                        case .sendConnect:
                            SendConnectStepView(
                                targetDestination: sendTargetDestination,
                                discoveredBeacons: transport.discoveredBeacons,
                                selectedBeacon: $selectedBeacon,
                                pinInput: $pinCodeInput,
                                showCameraScanner: $showCameraScanner,
                                manualCodeInput: $manualCodeInput,
                                isPairingBusy: isPairingBusy,
                                isLocalNetworkDenied: transport.isLocalNetworkDenied,
                                needsLocalNetworkRedirect: transport.needsLocalNetworkRedirect,
                                errorNote: pairingErrorNote,
                                onConfirmPin: confirmPinPairing,
                                onScannedQrCode: handleScannedQrString,
                                onApplyManualCode: { handleScannedQrString(manualCodeInput) },
                                onOpenAppSettings: {
                                    DirectSwitchTransportViewModel.openAppSettings()
                                }
                            )

                        case .sendSelectCategories:
                            if let paired = pairedTargetPayload {
                                SendCategoriesStepView(
                                    pairedPayload: paired,
                                    scanSummary: scanSummary,
                                    isLocalProUnlocked: true,
                                    pickedDocuments: pickedDocuments,
                                    documentPrecheck: documentPrecheckReport,
                                    isLoadingPositions: isLoadingDocumentPositions,
                                    contactsPreload: contactsPreload,
                                    photosPreload: photosPreload,
                                    videosPreload: videosPreload,
                                    calendarsSync: calendarsSync,
                                    remindersSync: remindersSync,
                                    senderAppsCatalog: senderAppsCatalog,
                                    deselectedSenderAppIds: deselectedSenderAppIds,
                                    verifiedLocalAppsCount: verifiedLocalAppsCount,
                                    photoDetectedAppsCount: photoDetectedAppsCount,
                                    selectedBundleIdsSet: selectedSenderBundleIdsSet,
                                    selectedStoreIdsSet: selectedSenderStoreIdsSet,
                                    categoryIconOverrides: categoryIconOverrides,
                                    isLoadingAppsCatalog: isLoadingAppsCatalog,
                                    appImportStatusNote: appImportStatusNote,
                                    includeContacts: $includeContacts,
                                    includePhotos: $includePhotos,
                                    includeVideos: $includeVideos,
                                    includeCalendars: $includeCalendars,
                                    calendarsUpToTodayOnly: $calendarsUpToTodayOnly,
                                    includeReminders: $includeReminders,
                                    remindersUpToTodayOnly: $remindersUpToTodayOnly,
                                    includeDocuments: $includeDocuments,
                                    includeApps: $includeApps,
                                    includeWhatsApp: $includeWhatsApp,
                                    onPreloadContacts: { enqueuePreloadContacts() },
                                    onPreloadPhotos: { enqueuePreloadPhotos() },
                                    onPreloadVideos: { enqueuePreloadVideos() },
                                    onRefreshCalendars: { enqueueRefreshCalendars() },
                                    onRefreshReminders: { enqueueRefreshReminders() },
                                    onToggleCatalogApp: { app in toggleCatalogAppSelection(app) },
                                    onToggleCategoryAllApps: { category, allSelected in
                                        toggleCategoryAllApps(category, currentlyAllSelected: allSelected)
                                    },
                                    onToggleCategorySingleApp: { app, selected in
                                        toggleCategorySingleApp(app, isCurrentlySelected: selected)
                                    },
                                    onAddSearchApp: { app in addAppsToSenderCatalog([app]) },
                                    onRescanAutomaticApps: {
                                        refreshSenderAppsCatalog()
                                        preloadCategoryIcons()
                                    },
                                    onRequestPhotoScanForApps: { requestPhotoLibraryAndRescanApps() },
                                    onResetAppsToDetectedOnly: resetSenderAppsToVerifiedOnly,
                                    onAddFolders: { presentDocumentPicker(mode: .positions) },
                                    onTogglePositionSelection: { locId, selected in
                                        iOSDocumentsSandboxBridge.setPositionSelected(locationId: locId, isSelected: selected)
                                        refreshAuthorizedSummary()
                                    },
                                    onRemovePosition: { locId in
                                        iOSDocumentsSandboxBridge.removeAuthorizedPosition(locationId: locId)
                                        refreshAuthorizedSummary()
                                    },
                                    onRefreshDocumentCheck: { refreshAuthorizedSummary() },
                                    onClearStagedFiles: {
                                        pickedDocuments.removeAll()
                                        iOSDocumentsSandboxBridge.clearAllPickedDocumentsAndBookmarks()
                                        refreshAuthorizedSummary()
                                    },
                                    onOpenProSheet: {},
                                    onChangePairedDevice: {
                                        if let oldPaired = pairedTargetPayload {
                                            Task { await transport.sendPairReset(qrPayload: oldPaired) }
                                        }
                                        pairedTargetPayload = nil
                                        pinCodeInput = ""
                                        pairingErrorNote = nil
                                        transport.startUdpAutoDiscovery()
                                        withAnimation(.easeInOut(duration: 0.2)) {
                                            activeStep = .sendConnect
                                        }
                                    },
                                    onStartCopy: launchSenderTransfer
                                )
                            }

                        case .transferPreparing:
                            TransferPreparationStepView(
                                transport: transport,
                                isReceiverMode: isReceiverMode,
                                onCancel: {
                                    finishAndReturnHome()
                                }
                            )

                        case .transferProgress:
                            DirectSwitchTransferProgressView(
                                transport: transport,
                                appInstaller: appInstaller,
                                isReceiverMode: isReceiverMode,
                                isProUnlocked: true,
                                canSendAnotherCategory: !isReceiverMode && pairedTargetPayload != nil,
                                onOpenProSheet: {},
                                onRetryIfFailed: {
                                    if !isReceiverMode, let paired = pairedTargetPayload {
                                        launchSenderTransferWithPayload(paired, isResume: transport.canResumeInterruptedTransfer)
                                    } else {
                                        handleBackNavigation()
                                    }
                                },
                                onReconnectNewCode: {
                                    pairedTargetPayload = nil
                                    selectedBeacon = nil
                                    pinCodeInput = ""
                                    manualCodeInput = ""
                                    pairingErrorNote = nil
                                    transport.errorMessage = nil
                                    transport.needsLocalNetworkRedirect = false
                                    transport.startUdpAutoDiscovery()
                                    withAnimation(.easeInOut(duration: 0.22)) {
                                        activeStep = .sendConnect
                                    }
                                },
                                onTransferAnotherCategory: returnToCategorySelectionForAnotherTransfer,
                                onFinish: finishAndReturnHome
                            )
                        }
                    }
                }
            }
            .overlay(alignment: .bottom) {
                if appInstaller.showsFloatingBottomBar {
                    FastOverlayFloatingControlBar(installer: appInstaller)
                        .padding(.horizontal, 12)
                        .padding(.bottom, appInstaller.overlaySafeBottomPadding + 8)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.2), value: appInstaller.showsFloatingBottomBar)
            .navigationBarHidden(true)
        }
        .preferredColorScheme(.light)
        .task {
            refreshAuthorizedSummary()
            refreshSenderAppsCatalog()
        }
        .onChange(of: transport.sessionStage) { stage in
            if isReceiverMode {
                switch stage {
                case .waitingPairing:
                    if activeStep == .receiveConnected {
                        withAnimation(.easeInOut(duration: 0.22)) {
                            activeStep = .receiveWaitCode
                        }
                    }
                case .pairedWaitingSelection:
                    if activeStep == .receiveWaitCode || activeStep == .transferProgress {
                        appInstaller.reset()
                        withAnimation(.easeInOut(duration: 0.24)) {
                            activeStep = .receiveConnected
                        }
                    }
                case .preparing:
                    if activeStep == .receiveWaitCode || activeStep == .receiveConnected {
                        appInstaller.reset()
                        withAnimation(.easeInOut(duration: 0.24)) {
                            activeStep = .transferPreparing
                        }
                    }
                case .transferring, .completed:
                    if activeStep == .receiveWaitCode || activeStep == .receiveConnected || activeStep == .transferPreparing {
                        appInstaller.reset()
                        withAnimation(.easeInOut(duration: 0.25)) {
                            activeStep = .transferProgress
                        }
                    }
                }
            } else {
                if (stage == .transferring || stage == .completed) && activeStep == .transferPreparing {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        activeStep = .transferProgress
                    }
                }
            }
        }
        .onChange(of: includeContacts) { enabled in
            if enabled {
                enqueuePreloadContacts()
            }
        }
        .onChange(of: includePhotos) { enabled in
            if enabled {
                enqueuePreloadPhotos()
            }
        }
        .onChange(of: includeVideos) { enabled in
            if enabled {
                enqueuePreloadVideos()
            }
        }
        .onChange(of: includeCalendars) { enabled in
            if enabled {
                enqueueRefreshCalendars()
            }
        }
        .onChange(of: includeReminders) { enabled in
            if enabled {
                enqueueRefreshReminders()
            }
        }
        .onChange(of: includeDocuments) { enabled in
            if enabled {
                refreshAuthorizedSummary()
            }
        }
        .onChange(of: includeApps) { enabled in
            if enabled {
                deselectedSenderAppIds.removeAll()
                refreshSenderAppsCatalog()
                preloadCategoryIcons()
            }
        }
        .onChange(of: scenePhase) { newPhase in
            if newPhase == .active {
                refreshAuthorizedSummary()
                if includeApps {
                    refreshSenderAppsCatalog()
                }
                appInstaller.handleSceneBecameActive()
                receiverDeniedSummary = iOSPermissionsHelper.receiverDeniedSummaryText()
                if activeStep == .sendConnect {
                    transport.startUdpAutoDiscovery()
                }
            }
        }
        .onOpenURL { incomingURL in
            handleIncomingURL(incomingURL)
        }
        .alert(
            "Controllo posizioni sul telefono",
            isPresented: Binding(
                get: { pendingTransferPrecheckAlert != nil },
                set: { if !$0 { pendingTransferPrecheckAlert = nil } }
            ),
            presenting: pendingTransferPrecheckAlert
        ) { report in
            Button("Seleziona posizione") {
                pendingTransferPrecheckAlert = nil
                presentDocumentPicker(mode: .positions)
            }
            if report.totalFiles > 0 {
                Button("Continua comunque") {
                    let paired = pairedTargetPayload
                    pendingTransferPrecheckAlert = nil
                    if let paired {
                        launchSenderTransferWithPayload(paired, isResume: false)
                    }
                }
            } else if includeContacts || includePhotos || includeVideos || includeCalendars || includeReminders || includeApps || includeWhatsApp {
                Button("Invia escludendo Documenti") {
                    includeDocuments = false
                    let paired = pairedTargetPayload
                    pendingTransferPrecheckAlert = nil
                    if let paired {
                        launchSenderTransferWithPayload(paired, isResume: false)
                    }
                }
            }
            Button("Annulla", role: .cancel) {
                pendingTransferPrecheckAlert = nil
            }
        } message: { report in
            Text(precheckAlertMessage(for: report))
        }
        .onChange(of: transport.photoMetadataDiscoveredApps) { clues in
            guard !clues.isEmpty else { return }
            mergeDetectedAppsIntoCatalog(clues)
        }
    }

    // MARK: - Azioni di navigazione e flusso guidato

    private func startReceiveWizard() {
        isReceiverMode = true
        pairingErrorNote = nil
        receiverQrPayload = transport.startReceiverServer()
        receiverDeniedSummary = iOSPermissionsHelper.receiverDeniedSummaryText()
        let destSummary = iOSDocumentsSandboxBridge.receiverDestinationsSummary()
        receiverAuthorizedDestinations = destSummary.destinations
        receiverFallbackRootLabel = destSummary.fallbackRoot
        withAnimation(.easeInOut(duration: 0.22)) {
            activeStep = .receiveWaitCode
        }
        Task {
            await iOSPermissionsHelper.requestAllTransferPermissions()
            receiverDeniedSummary = iOSPermissionsHelper.receiverDeniedSummaryText()
            refreshAuthorizedSummary()
        }
    }

    private func startSendWizard(destination: SendTargetDestination) {
        isReceiverMode = false
        sendTargetDestination = destination
        pairedTargetPayload = nil
        selectedBeacon = nil
        pinCodeInput = ""
        manualCodeInput = ""
        showCameraScanner = false
        pairingErrorNote = nil
        resetCategorySelectionsAndPreloads()
        transport.startUdpAutoDiscovery()
        withAnimation(.easeInOut(duration: 0.22)) {
            activeStep = .sendConnect
        }
    }

    private func confirmPinPairing() {
        guard let beacon = selectedBeacon else { return }
        let clean = pinCodeInput.filter { $0.isNumber }
        guard clean.count == 6, !isPairingBusy else { return }
        isPairingBusy = true
        pairingErrorNote = nil
        Task {
            do {
                let paired = try await transport.pairWithBeaconUsingPin(beacon: beacon, pin: clean)
                isPairingBusy = false
                transport.stopUdpAutoDiscovery()
                pairedTargetPayload = paired
                withAnimation(.easeInOut(duration: 0.22)) {
                    activeStep = .sendSelectCategories
                }
            } catch {
                isPairingBusy = false
                pairingErrorNote = error.localizedDescription
            }
        }
    }

    private func handleScannedQrString(_ raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do {
            let parsed = try QrPairingPayload.fromJson(trimmed)
            showCameraScanner = false
            pairingErrorNote = nil
            transport.stopUdpAutoDiscovery()
            pairedTargetPayload = parsed
            withAnimation(.easeInOut(duration: 0.22)) {
                activeStep = .sendSelectCategories
            }
            Task {
                await transport.sendPairAck(qrPayload: parsed)
            }
        } catch {
            pairingErrorNote = "Codice QR non riconosciuto. Assicurati di inquadrare il QR mostrato da DirectSwitch sul nuovo telefono."
        }
    }

    private func presentDocumentPicker(mode: iOSDocumentPickerMode) {
        iOSNativeDocumentPickerPresenter.shared.present(
            mode: mode,
            onPickedURLs: { urls in
                guard !urls.isEmpty else { return }
                switch mode {
                case .receiverDestinations:
                    Task {
                        let summary = await Task.detached(priority: .userInitiated) {
                            _ = iOSDocumentsSandboxBridge.authorizeReceiverDestinationBookmarks(urls)
                            return iOSDocumentsSandboxBridge.receiverDestinationsSummary()
                        }.value
                        receiverAuthorizedDestinations = summary.destinations
                        receiverFallbackRootLabel = summary.fallbackRoot
                    }
                case .receiverFallbackRoot:
                    Task {
                        let summary = await Task.detached(priority: .userInitiated) {
                            _ = iOSDocumentsSandboxBridge.setReceiverFallbackRootBookmark(urls)
                            return iOSDocumentsSandboxBridge.receiverDestinationsSummary()
                        }.value
                        receiverAuthorizedDestinations = summary.destinations
                        receiverFallbackRootLabel = summary.fallbackRoot
                    }
                case .positions, .folders:
                    isLoadingDocumentPositions = true
                    let currentStaged = pickedDocuments.map(\.0)
                    let includeLiveBytes = pairedTargetPayload?.receiverPlatform == .IOS
                    Task {
                        let (summary, precheck) = await Task.detached(priority: .userInitiated) {
                            _ = iOSDocumentsSandboxBridge.authorizePositionBookmarks(urls)
                            let sum = iOSDeviceDataAnalyzer.scanAuthorizedSummary(
                                stagedItems: currentStaged,
                                includePairedLiveVideoBytes: includeLiveBytes
                            )
                            let pre = iOSDocumentsSandboxBridge.inspectPreTransferDocuments(
                                stagedItems: currentStaged,
                                includeWhatsAppVault: false
                            )
                            return (sum, pre)
                        }.value
                        scanSummary = summary
                        documentPrecheckReport = precheck
                        isLoadingDocumentPositions = false
                        if let lastAdded = precheck.locationSummaries.last {
                            sharedVaultToast = "Posizione «\(lastAdded.locationName)» caricata (\(lastAdded.fileCount) file)"
                        }
                    }
                case .files:
                    isLoadingDocumentPositions = true
                    let existingStaged = pickedDocuments.map(\.0)
                    let includeLiveBytes = pairedTargetPayload?.receiverPlatform == .IOS
                    Task {
                        let (imported, summary, precheck) = await Task.detached(priority: .userInitiated) {
                            let imp = iOSDocumentsSandboxBridge.importPickedDocumentURLs(urls)
                            let allStaged = existingStaged + imp.map(\.0)
                            let sum = iOSDeviceDataAnalyzer.scanAuthorizedSummary(
                                stagedItems: allStaged,
                                includePairedLiveVideoBytes: includeLiveBytes
                            )
                            let pre = iOSDocumentsSandboxBridge.inspectPreTransferDocuments(
                                stagedItems: allStaged,
                                includeWhatsAppVault: false
                            )
                            return (imp, sum, pre)
                        }.value
                        pickedDocuments.append(contentsOf: imported)
                        scanSummary = summary
                        documentPrecheckReport = precheck
                        isLoadingDocumentPositions = false
                    }
                }
            }
        )
    }

    private func precheckAlertMessage(for report: iOSDocumentsPrecheckReport) -> String {
        let selectedCount = report.locationSummaries.filter(\.isSelected).count
        if !report.locationSummaries.isEmpty && selectedCount == 0 {
            return "Nessuna posizione è selezionata con la spunta. Seleziona almeno una posizione da trasferire nell'elenco oppure aggiungine un'altra."
        }
        if report.totalFiles == 0 && report.unreadableFilesCount == 0 {
            return "Nessun file trovato nelle posizioni selezionate. Tocca «Seleziona posizione», entra nella posizione da trasferire (es. Su iPhone o iCloud Drive) e premi «Apri» in alto a destra."
        }
        if report.totalFiles == 0 && report.unreadableFilesCount > 0 {
            return "Trovati \(report.unreadableFilesCount) file non ancora scaricati o non leggibili (es. su iCloud Drive). Scaricali nell'app File prima di copiare la posizione."
        }
        if report.unreadableFilesCount > 0 {
            return "Pronti \(report.totalFiles) file in \(max(1, selectedCount)) posizioni selezionate (\(report.folderSummaries.count) cartelle), ma \(report.unreadableFilesCount) file risultano illeggibili o solo su iCloud e verrebbero saltati."
        }
        return "Controllo completato: \(max(1, selectedCount)) posizioni selezionate (\(report.totalFiles) file in \(report.folderSummaries.count) cartelle) pronte."
    }

    private func launchSenderTransfer() {
        guard let paired = pairedTargetPayload else { return }
        if includeDocuments {
            let staged = pickedDocuments.map(\.0)
            let precheck = iOSDocumentsSandboxBridge.inspectPreTransferDocuments(
                stagedItems: staged,
                includeWhatsAppVault: false
            )
            documentPrecheckReport = precheck
            if precheck.totalFiles == 0 || precheck.unreadableFilesCount > 0 {
                pendingTransferPrecheckAlert = precheck
                return
            }
        }
        launchSenderTransferWithPayload(paired, isResume: false)
    }

    private func launchSenderTransferWithPayload(_ paired: QrPairingPayload, isResume: Bool) {
        sharedVaultToast = nil
        isReceiverMode = false
        let currentScope = ActiveTransferScope(
            contacts: includeContacts,
            photos: includePhotos,
            videos: includeVideos,
            calendars: includeCalendars,
            reminders: includeReminders,
            documents: includeDocuments,
            apps: includeApps,
            whatsApp: includeWhatsApp
        )
        if !isResume {
            appInstaller.reset()
            transport.prepareForFreshTransfer(
                sessionId: paired.sessionId,
                scope: currentScope,
                receiverName: paired.receiverName,
                receiverPlatform: paired.receiverPlatform
            )
        }
        withAnimation(.easeInOut(duration: 0.22)) {
            activeStep = (!isResume && !currentScope.isWhatsAppOnly) ? .transferPreparing : .transferProgress
        }
        let docsSnapshot = pickedDocuments
        let appsSnapshot: [InstalledAppRecord] = includeApps
            ? selectedSenderApps.filter {
                paired.receiverPlatform != .ANDROID || !iOSInstalledAppsScanner.isGoogleAppPreinstalledOnAndroid($0)
            }
            : []
        let calCutoff = calendarsUpToTodayOnly
        let remCutoff = remindersUpToTodayOnly
        Task {
            await transport.executeSenderTransfer(
                qrPayload: paired,
                includeContacts: includeContacts,
                includePhotos: includePhotos,
                includeVideos: includeVideos,
                includeCalendars: includeCalendars,
                calendarsUpToTodayOnly: calCutoff,
                includeReminders: includeReminders,
                remindersUpToTodayOnly: remCutoff,
                includeDocuments: includeDocuments,
                includeApps: includeApps,
                includeWhatsAppVault: includeWhatsApp,
                installedApps: appsSnapshot,
                pickedDocuments: docsSnapshot,
                isResume: isResume
            )
            if transport.isCompleted && transport.failedItemsCount == 0 {
                pickedDocuments.removeAll()
                refreshAuthorizedSummary()
            }
        }
    }

    private func returnToCategorySelectionForAnotherTransfer() {
        guard let paired = pairedTargetPayload else {
            finishAndReturnHome()
            return
        }
        appInstaller.reset()
        transport.errorMessage = nil
        transport.isCompleted = false
        transport.pendingNativeWhatsAppMigration = false
        transport.visualStepProgress = 0.0
        transport.sessionStage = .pairedWaitingSelection
        withAnimation(.easeInOut(duration: 0.22)) {
            activeStep = .sendSelectCategories
        }
        Task {
            await transport.sendPairAck(qrPayload: paired)
        }
    }

    private func resetCategorySelectionsAndPreloads() {
        categoryTaskQueue.cancelAll()
        includeContacts = false
        includePhotos = false
        includeVideos = false
        includeCalendars = false
        includeReminders = false
        includeDocuments = false
        includeApps = false
        includeWhatsApp = false
        calendarsUpToTodayOnly = false
        remindersUpToTodayOnly = false
        contactsPreload = ContactsPreloadState()
        photosPreload = PhotosPreloadState()
        videosPreload = VideosPreloadState()
        calendarsSync = DateSyncPreloadState()
        remindersSync = DateSyncPreloadState()
        appImportStatusNote = nil
    }

    private func enqueuePreloadContacts() {
        contactsPreload.isLoading = true
        contactsPreload.isCompleted = false
        categoryTaskQueue.enqueue {
            contactsPreload.isLoading = true
            contactsPreload.isCompleted = false
            _ = await iOSContactsSmartMerger.requestAccessIfNeeded()
            refreshAuthorizedSummary()
            let total = await iOSContactsSmartMerger.preloadContactsCountWithProgress { loaded, tot in
                Task { @MainActor in
                    // Ignora aggiornamenti tardivi arrivati dopo il completamento (evita tendina bloccata su "Precaricamento")
                    guard contactsPreload.isLoading else { return }
                    contactsPreload = ContactsPreloadState(
                        loadedCount: loaded,
                        totalCount: tot,
                        isLoading: true,
                        isCompleted: false
                    )
                }
            }
            contactsPreload = ContactsPreloadState(
                loadedCount: total,
                totalCount: total,
                isLoading: false,
                isCompleted: true
            )
            refreshAuthorizedSummary()
        }
    }

    private func enqueuePreloadPhotos() {
        photosPreload.isLoading = true
        photosPreload.isCompleted = false
        categoryTaskQueue.enqueue {
            photosPreload.isLoading = true
            photosPreload.isCompleted = false
            _ = await iOSPhotoKitMigrator.requestAccessIfNeeded()
            refreshAuthorizedSummary()
            let includeLiveBytes = pairedTargetPayload?.receiverPlatform == .IOS
            let res = await iOSPhotoKitMigrator.preloadMediaStatsWithProgress(
                for: .image,
                includePairedLiveVideoBytes: includeLiveBytes
            ) { loaded, tot, live, albums, iCloudCount, bytes in
                Task { @MainActor in
                    guard photosPreload.isLoading else { return }
                    photosPreload = PhotosPreloadState(
                        loadedCount: loaded,
                        totalCount: tot,
                        livePhotosCount: live,
                        albumsCount: albums,
                        iCloudCount: iCloudCount,
                        estimatedBytes: bytes,
                        isLoading: true,
                        isCompleted: false
                    )
                }
            }
            photosPreload = PhotosPreloadState(
                loadedCount: res.total,
                totalCount: res.total,
                livePhotosCount: res.liveCount,
                albumsCount: res.albumsCount,
                iCloudCount: res.iCloudCount,
                estimatedBytes: res.estimatedBytes,
                isLoading: false,
                isCompleted: true
            )
            refreshAuthorizedSummary()
            if includeApps {
                refreshSenderAppsCatalog()
            }
        }
    }

    private func enqueuePreloadVideos() {
        videosPreload.isLoading = true
        videosPreload.isCompleted = false
        categoryTaskQueue.enqueue {
            videosPreload.isLoading = true
            videosPreload.isCompleted = false
            _ = await iOSPhotoKitMigrator.requestAccessIfNeeded()
            refreshAuthorizedSummary()
            let res = await iOSPhotoKitMigrator.preloadMediaStatsWithProgress(for: .video) { loaded, tot, _, _, iCloudCount, bytes in
                Task { @MainActor in
                    guard videosPreload.isLoading else { return }
                    videosPreload = VideosPreloadState(
                        loadedCount: loaded,
                        totalCount: tot,
                        iCloudCount: iCloudCount,
                        estimatedBytes: bytes,
                        isLoading: true,
                        isCompleted: false
                    )
                }
            }
            videosPreload = VideosPreloadState(
                loadedCount: res.total,
                totalCount: res.total,
                iCloudCount: res.iCloudCount,
                estimatedBytes: res.estimatedBytes,
                isLoading: false,
                isCompleted: true
            )
            refreshAuthorizedSummary()
        }
    }

    private func enqueueRefreshCalendars() {
        calendarsSync.isLoading = true
        categoryTaskQueue.enqueue {
            _ = await iOSCalendarMigrator.requestAccessIfNeeded()
            let now = Date()
            let (allCount, upToTodayCount) = await Task.detached(priority: .userInitiated) {
                (
                    iOSCalendarMigrator.readEvents(upToDate: nil).count,
                    iOSCalendarMigrator.readEvents(upToDate: now).count
                )
            }.value
            calendarsSync = DateSyncPreloadState(
                totalAllCount: allCount,
                totalUpToTodayCount: upToTodayCount,
                lastUpdatedAt: Date(),
                isLoading: false
            )
            refreshAuthorizedSummary()
        }
    }

    private func enqueueRefreshReminders() {
        remindersSync.isLoading = true
        categoryTaskQueue.enqueue {
            _ = await iOSRemindersMigrator.requestAccessIfNeeded()
            let now = Date()
            let allList = await iOSRemindersMigrator.readReminders(upToDate: nil)
            let upToTodayList = await iOSRemindersMigrator.readReminders(upToDate: now)
            remindersSync = DateSyncPreloadState(
                totalAllCount: allList.count,
                totalUpToTodayCount: upToTodayList.count,
                lastUpdatedAt: Date(),
                isLoading: false
            )
            let staged = pickedDocuments.map(\.0)
            let remCount = allList.count
            let includeLiveBytes = pairedTargetPayload?.receiverPlatform == .IOS
            let (summary, precheck) = await Task.detached(priority: .utility) {
                (
                    iOSDeviceDataAnalyzer.scanAuthorizedSummary(
                        stagedItems: staged,
                        knownRemindersCount: remCount,
                        includePairedLiveVideoBytes: includeLiveBytes
                    ),
                    iOSDocumentsSandboxBridge.inspectPreTransferDocuments(stagedItems: staged, includeWhatsAppVault: false)
                )
            }.value
            scanSummary = summary
            documentPrecheckReport = precheck
        }
    }

    private func requestPhotoLibraryAndRescanApps() {
        categoryTaskQueue.enqueue {
            _ = await iOSPhotoKitMigrator.requestAccessIfNeeded()
            refreshAuthorizedSummary()
            refreshSenderAppsCatalog()
        }
    }

    private func preloadCategoryIcons() {
        let isAndroid = pairedTargetPayload?.receiverPlatform == .ANDROID
        let categories = iOSInstalledAppsScanner.curatedCategories.filter {
            !isAndroid || !$0.isGoogleAndroidPreinstalledCategory
        }
        Task {
            let icons = await iOSAppStoreCatalogResolver.fetchIconsForCategories(categories)
            if !icons.isEmpty {
                categoryIconOverrides.merge(icons) { _, new in new }
            }
        }
    }

    private func refreshSenderAppsCatalog() {
        isLoadingAppsCatalog = true
        let quickProbes = iOSInstalledAppsScanner.scanLocallyInstalledProbesOnly()
        verifiedLocalAppsCount = quickProbes.count
        let initialDetected = iOSInstalledAppsScanner.scanLocallyInstalledApps()
        mergeDetectedAppsIntoCatalog(initialDetected)

        Task {
            let fullScan = await iOSInstalledAppsScanner.detectAllAppsInstantAsync()
            verifiedLocalAppsCount = fullScan.verifiedProbesCount
            photoDetectedAppsCount = fullScan.photoDiscoveredCount
            mergeDetectedAppsIntoCatalog(fullScan.apps)

            let snapshot = senderAppsCatalog
            let enriched = await iOSAppStoreCatalogResolver.enrichAppsWithStoreMetadata(snapshot)
            if !enriched.isEmpty {
                self.senderAppsCatalog = enriched
            }
            isLoadingAppsCatalog = false
        }
    }

    private func mergeDetectedAppsIntoCatalog(_ incoming: [InstalledAppRecord]) {
        guard !incoming.isEmpty else { return }
        if senderAppsCatalog.isEmpty {
            senderAppsCatalog = incoming
        } else {
            var merged = senderAppsCatalog
            for app in incoming {
                if let idx = merged.firstIndex(where: {
                    $0.packageName.caseInsensitiveCompare(app.packageName) == .orderedSame
                        || ($0.appStoreId != nil && $0.appStoreId == app.appStoreId)
                }) {
                    // Preserva etichetta sorgente più dettagliata se presente
                    if merged[idx].detectionSource == nil, let src = app.detectionSource {
                        merged[idx].detectionSource = src
                    }
                    if merged[idx].iconUrl == nil, let icon = app.iconUrl {
                        merged[idx].iconUrl = icon
                    }
                } else {
                    merged.append(app)
                }
            }
            senderAppsCatalog = merged
        }
        photoDetectedAppsCount = senderAppsCatalog.filter {
            ($0.detectionSource ?? "").hasPrefix("da ")
        }.count
    }

    private func matchingCatalogApp(for target: InstalledAppRecord) -> InstalledAppRecord? {
        senderAppsCatalog.first {
            $0.packageName.caseInsensitiveCompare(target.packageName) == .orderedSame
                || ($0.appStoreId != nil && $0.appStoreId == target.appStoreId)
        }
    }

    private func toggleCatalogAppSelection(_ app: InstalledAppRecord) {
        if deselectedSenderAppIds.contains(app.id) {
            deselectedSenderAppIds.remove(app.id)
        } else {
            deselectedSenderAppIds.insert(app.id)
        }
    }

    private func toggleCategorySingleApp(_ item: InstalledAppRecord, isCurrentlySelected: Bool) {
        if isCurrentlySelected {
            if let existing = matchingCatalogApp(for: item) {
                deselectedSenderAppIds.insert(existing.id)
            }
            appImportStatusNote = nil
        } else {
            addAppsToSenderCatalog([item])
        }
    }

    private func toggleCategoryAllApps(_ category: AppQuickCategory, currentlyAllSelected: Bool) {
        if currentlyAllSelected {
            for item in category.apps {
                if let existing = matchingCatalogApp(for: item) {
                    deselectedSenderAppIds.insert(existing.id)
                }
            }
            appImportStatusNote = nil
        } else {
            addAppsToSenderCatalog(category.apps)
            appImportStatusNote = "Categoria «\(category.title)» selezionata (\(category.apps.count) app)."
        }
    }

    private func addAppsToSenderCatalog(_ incomingApps: [InstalledAppRecord]) {
        var newlyAdded: [InstalledAppRecord] = []
        for item in incomingApps {
            if let existing = matchingCatalogApp(for: item) {
                deselectedSenderAppIds.remove(existing.id)
            } else {
                var seeded = item
                if seeded.iconUrl == nil, let icon = categoryIconOverrides[item.packageName.lowercased()] {
                    seeded.iconUrl = icon
                }
                senderAppsCatalog.append(seeded)
                deselectedSenderAppIds.remove(seeded.id)
                newlyAdded.append(seeded)
            }
        }
        guard !newlyAdded.isEmpty else { return }
        iOSInstalledAppsScanner.appendCustomApps(newlyAdded)
        Task {
            let enriched = await iOSAppStoreCatalogResolver.enrichAppsWithStoreMetadata(newlyAdded)
            mergeDetectedAppsIntoCatalog(enriched)
        }
    }

    private func resetSenderAppsToVerifiedOnly() {
        iOSInstalledAppsScanner.clearSavedCustomApps()
        deselectedSenderAppIds.removeAll()
        appImportStatusNote = nil
        senderAppsCatalog = []
        photoDetectedAppsCount = 0
        refreshSenderAppsCatalog()
    }

    private func refreshAuthorizedSummary() {
        let staged = pickedDocuments.map(\.0)
        let includeLiveBytes = pairedTargetPayload?.receiverPlatform == .IOS
        Task {
            let (summary, precheck) = await Task.detached(priority: .utility) {
                (
                    iOSDeviceDataAnalyzer.scanAuthorizedSummary(
                        stagedItems: staged,
                        includePairedLiveVideoBytes: includeLiveBytes
                    ),
                    iOSDocumentsSandboxBridge.inspectPreTransferDocuments(stagedItems: staged, includeWhatsAppVault: false)
                )
            }.value
            scanSummary = summary
            documentPrecheckReport = precheck
        }
    }

    private func handleIncomingURL(_ incomingURL: URL) {
        if incomingURL.isFileURL {
            if let imported = iOSDocumentsSandboxBridge.importIncomingOpenURL(incomingURL) {
                pickedDocuments.append(imported)
                sharedVaultToast = "'\(imported.0.fileName)' pronto per la copia"
                refreshAuthorizedSummary()
                if activeStep == .home {
                    startSendWizard(destination: .newIPhone)
                }
            }
            return
        }
        if let comps = URLComponents(url: incomingURL, resolvingAgainstBaseURL: false),
           let qrParam = comps.queryItems?.first(where: { $0.name == "qr" })?.value,
           !qrParam.isEmpty {
            isReceiverMode = false
            handleScannedQrString(qrParam)
        }
    }

    private func handleBackNavigation() {
        switch activeStep {
        case .home:
            break
        case .receiveWaitCode, .receiveConnected, .transferPreparing:
            finishAndReturnHome()
        case .sendConnect:
            showCameraScanner = false
            transport.stopUdpAutoDiscovery()
            withAnimation(.easeInOut(duration: 0.2)) {
                activeStep = .home
            }
        case .sendSelectCategories:
            if let oldPaired = pairedTargetPayload {
                Task { await transport.sendPairReset(qrPayload: oldPaired) }
            }
            pairedTargetPayload = nil
            pinCodeInput = ""
            pairingErrorNote = nil
            transport.startUdpAutoDiscovery()
            withAnimation(.easeInOut(duration: 0.2)) {
                activeStep = .sendConnect
            }
        case .transferProgress:
            if !isReceiverMode && pairedTargetPayload != nil && !transport.isTransferring {
                returnToCategorySelectionForAnotherTransfer()
            } else {
                finishAndReturnHome()
            }
        }
    }

    private func finishAndReturnHome() {
        showCameraScanner = false
        receiverQrPayload = nil
        pairedTargetPayload = nil
        selectedBeacon = nil
        pinCodeInput = ""
        pairingErrorNote = nil
        resetCategorySelectionsAndPreloads()
        appInstaller.reset()
        transport.resetSession()
        withAnimation(.easeInOut(duration: 0.22)) {
            activeStep = .home
        }
    }
}

// MARK: - Schermata Home pulita (solo Invia sopra e Ricevi sotto, sottotitoli dentro ⓘ)

private struct DirectSwitchHomeView: View {
    var onStartReceive: () -> Void
    var onStartSendToIPhone: () -> Void
    var onStartSendToAndroid: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                // Hero centrale con icona ingrandita (88pt) e sottotitolo racchiuso nel pulsante ⓘ
                VStack(spacing: 12) {
                    DirectSwitchAppleEmblem(size: 88)
                        .padding(.top, 22)
                        .padding(.bottom, 4)

                    HStack(spacing: 6) {
                        Text("DirectSwitch")
                            .font(.system(size: 29, weight: .bold))
                            .foregroundColor(AppleTheme.textPrimary)
                        InfoCircleButton(
                            title: "DirectSwitch",
                            message: "Copia i tuoi dati senza formattare: trasferisce rubrica, foto con album, video originali, calendari, file e chat WhatsApp direttamente tra due telefoni già configurati, senza passare dal cloud."
                        )
                    }
                }
                .padding(.bottom, 10)

                // Sezione 1 (SOPRA): Invia (freccia verso destra ->, sottotitolo dentro ⓘ, pulsante unico "Invia")
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        AppleSettingsIcon(systemName: "arrow.right", color: AppleTheme.blue)
                        Text("Invia")
                            .font(.system(size: 19, weight: .bold))
                            .foregroundColor(AppleTheme.textPrimary)
                        Spacer()
                        InfoCircleButton(
                            title: "Invia",
                            message: "Invia i dati da questo telefono direttamente senza cavo all'altro telefono (iPhone o Android) dove hai aperto 'Ricevi', tutto gratuito e senza formattare."
                        )
                    }

                    ApplePrimaryButton(
                        title: "Invia",
                        icon: "arrow.right",
                        color: AppleTheme.blue,
                        action: onStartSendToIPhone
                    )
                }
                .appleCard()

                // Sezione 2 (SOTTO): Ricevi (SOLTANTO la freccia verso sinistra <-, sottotitolo dentro ⓘ)
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        AppleSettingsIcon(systemName: "arrow.left", color: AppleTheme.teal)
                        Text("Ricevi")
                            .font(.system(size: 19, weight: .bold))
                            .foregroundColor(AppleTheme.textPrimary)
                        Spacer()
                        InfoCircleButton(
                            title: "Ricevi",
                            message: "Mostra il codice monouso a 6 cifre (come 'Passa a iOS') o il codice QR per ricevere i dati dal tuo altro iPhone o Android senza cancellare nulla."
                        )
                    }

                    ApplePrimaryButton(
                        title: "Ricevi",
                        icon: "arrow.left",
                        color: AppleTheme.teal,
                        action: onStartReceive
                    )
                }
                .appleCard()
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 30)
        }
    }
}

// MARK: - Schermata Avanzamento & Completamento (stile "Passa a iOS" / "Passa a Android")

private struct DirectSwitchTransferProgressView: View {
    @ObservedObject var transport: DirectSwitchTransportViewModel
    @ObservedObject var appInstaller: iOSSequentialAppInstaller
    let isReceiverMode: Bool
    let isProUnlocked: Bool
    let canSendAnotherCategory: Bool
    var onOpenProSheet: () -> Void
    var onRetryIfFailed: () -> Void
    var onReconnectNewCode: () -> Void
    var onTransferAnotherCategory: () -> Void
    var onFinish: () -> Void

    @State private var showWhatsAppQrScanner: Bool = false

    private struct ScopedSummaryItem: Identifiable {
        let id: String
        let icon: String
        let color: Color
        let title: String
        let value: String
    }

    private var scope: ActiveTransferScope {
        transport.activeTransferScope
    }

    /// Quando il passaggio riguarda solo WhatsApp (oppure quando termina la copia delle altre voci e serve il passaggio chat di WhatsApp),
    /// l'intera schermata cambia e mostra ESCLUSIVAMENTE la guida/scanner dedicata a WhatsApp senza 100% fuorvianti o voci non selezionate.
    private var isStandaloneWhatsAppScreen: Bool {
        guard transport.errorMessage == nil else { return false }
        // Da Android -> iPhone DirectSwitch esegue la copia speculare diretta lasciando fuori WhatsApp
        if isReceiverMode && transport.peerPlatform == .ANDROID {
            return false
        }
        if scope.isWhatsAppOnly {
            return true
        }
        return !scope.hasAnyStandardDataCategory && transport.isCompleted && transport.pendingNativeWhatsAppMigration
    }

    private var isReceiverAppsPhase: Bool {
        isReceiverMode && transport.isCompleted && scope.apps
    }

    private var isReceiverAppsOnlyPhase: Bool {
        isReceiverAppsPhase && scope.isAppsOnly
    }

    private var queueableAppIdsSet: Set<String> {
        Set(appInstaller.queueableApps.map(\.id))
    }

    private var handledQueueableAppsCount: Int {
        let handled = appInstaller.alreadyInstalledIds
            .union(appInstaller.activeDownloadingIds)
            .union(appInstaller.completedIds)
        return handled.intersection(queueableAppIdsSet).count
    }

    private var progressFraction: Double {
        if isReceiverAppsOnlyPhase {
            let total = appInstaller.queueableApps.count
            guard total > 0 else { return 0.0 }
            return min(1.0, max(0.0, Double(handledQueueableAppsCount) / Double(total)))
        }
        if transport.isCompleted { return 1.0 }
        if transport.totalBytesCount > 0 && transport.transferredBytesCount > 0 {
            return min(1.0, max(0.01, Double(transport.transferredBytesCount) / Double(transport.totalBytesCount)))
        }
        if transport.totalItems > 0 {
            let processed = transport.completedItems + transport.failedItemsCount
            guard processed > 0 else { return 0.0 }
            return min(1.0, max(0.01, Double(processed) / Double(transport.totalItems)))
        }
        return min(0.99, max(0.0, transport.visualStepProgress))
    }

    private func formattedCountWithAlreadyPresent(imported: Int, alreadyPresent: Int) -> String {
        if imported == 0 && alreadyPresent > 0 {
            return "0 (\(alreadyPresent) già presenti)"
        }
        if alreadyPresent > 0 {
            return "\(imported) (+\(alreadyPresent) già presenti)"
        }
        return "\(imported)"
    }

    private var contactsSummaryValue: String {
        formattedCountWithAlreadyPresent(
            imported: transport.mergedContacts,
            alreadyPresent: transport.contactsAlreadyPresentCount
        )
    }

    private var percentageInt: Int {
        let completedFlag = isReceiverAppsOnlyPhase
            ? (!appInstaller.queueableApps.isEmpty && handledQueueableAppsCount >= appInstaller.queueableApps.count)
            : transport.isCompleted
        return TransferDisplayFormatting.percentageInt(fraction: progressFraction, isCompleted: completedFlag)
    }

    private var mediaRowTitle: String {
        if scope.photos && !scope.videos && !scope.documents { return "Foto trasferite" }
        if scope.videos && !scope.photos && !scope.documents { return "Video trasferiti" }
        if scope.documents && !scope.photos && !scope.videos { return "Documenti e File" }
        if scope.photos && scope.videos && !scope.documents { return "Foto e Video" }
        return "Foto, Video e File"
    }

    private var visibleSummaryRows: [ScopedSummaryItem] {
        var rows: [ScopedSummaryItem] = []

        if scope.contacts {
            rows.append(
                ScopedSummaryItem(
                    id: "contacts",
                    icon: "person.crop.circle.fill",
                    color: AppleTheme.blue,
                    title: "Rubrica contatti",
                    value: contactsSummaryValue
                )
            )
        }

        if scope.photos || scope.videos || scope.documents || (scope.whatsApp && transport.totalItems > 0) {
            rows.append(
                ScopedSummaryItem(
                    id: "media_docs",
                    icon: scope.documents && !scope.photos && !scope.videos ? "doc.fill" : "photo.on.rectangle.angled",
                    color: scope.documents && !scope.photos && !scope.videos ? AppleTheme.teal : AppleTheme.orange,
                    title: mediaRowTitle,
                    value: transport.totalItems > 0 ? "\(transport.completedItems) / \(transport.totalItems)" : "\(transport.completedItems)"
                )
            )
        }

        if scope.photos && transport.savedLivePhotos > 0 {
            rows.append(
                ScopedSummaryItem(
                    id: "live_photos",
                    icon: "livephoto",
                    color: AppleTheme.orange,
                    title: "Live Photos animate",
                    value: "\(transport.savedLivePhotos)"
                )
            )
        }

        if scope.calendars {
            rows.append(
                ScopedSummaryItem(
                    id: "calendars",
                    icon: "calendar",
                    color: AppleTheme.slate,
                    title: "Calendari importati",
                    value: formattedCountWithAlreadyPresent(
                        imported: transport.importedCalendars,
                        alreadyPresent: transport.calendarsAlreadyPresentCount
                    )
                )
            )
        }

        if scope.reminders {
            rows.append(
                ScopedSummaryItem(
                    id: "reminders",
                    icon: "checklist",
                    color: AppleTheme.blue,
                    title: "Promemoria importati",
                    value: formattedCountWithAlreadyPresent(
                        imported: transport.importedReminders,
                        alreadyPresent: transport.remindersAlreadyPresentCount
                    )
                )
            )
        }

        if transport.importedSms > 0 {
            rows.append(
                ScopedSummaryItem(
                    id: "sms",
                    icon: "message.fill",
                    color: AppleTheme.green,
                    title: "Messaggi salvati",
                    value: "\(transport.importedSms)"
                )
            )
        }

        if scope.apps {
            let countVal = isReceiverMode ? transport.receivedInstalledApps.count : transport.sentInstalledAppsCount
            rows.append(
                ScopedSummaryItem(
                    id: "apps",
                    icon: "square.grid.2x2.fill",
                    color: AppleTheme.blue,
                    title: isReceiverMode ? "Elenco App ricevute" : "App inviate al nuovo telefono",
                    value: isReceiverMode ? "\(countVal) pronte al download" : "\(countVal)"
                )
            )
        }

        if transport.skippedDuplicates > 0 {
            rows.append(
                ScopedSummaryItem(
                    id: "duplicates",
                    icon: "sparkles",
                    color: AppleTheme.teal,
                    title: "Doppioni già presenti ignorati",
                    value: "\(transport.skippedDuplicates)"
                )
            )
        }

        if transport.failedItemsCount > 0 {
            rows.append(
                ScopedSummaryItem(
                    id: "failed",
                    icon: "icloud.slash",
                    color: AppleTheme.orange,
                    title: "Elementi non scaricabili da iCloud / illeggibili",
                    value: "\(transport.failedItemsCount)"
                )
            )
        }

        return rows
    }

    private var remainingTimeLabel: String? {
        guard !isReceiverAppsOnlyPhase, !isReceiverAppsPhase, !transport.isCompleted else {
            return nil
        }
        return transport.etaLabel
    }

    var body: some View {
        Group {
            if isStandaloneWhatsAppScreen {
                whatsAppDedicatedScreen
            } else {
                standardDataTransferScreen
            }
        }
        .sheet(isPresented: $showWhatsAppQrScanner) {
            WhatsAppMigrationQrScannerSheet()
        }
    }

    // MARK: - Schermata ESCLUSIVA per il passaggio delle Chat WhatsApp (senza 100% fuorvianti o altre voci)

    @ViewBuilder
    private var whatsAppDedicatedScreen: some View {
        let isToAndroid = !isReceiverMode && transport.peerPlatform == .ANDROID
        let isFromAndroid = isReceiverMode && transport.peerPlatform == .ANDROID

        let screenTitle: String = {
            if isToAndroid { return "Passaggio Chat su Android" }
            if !isReceiverMode { return "Passaggio Chat da questo iPhone" }
            if isFromAndroid { return "Importa Chat WhatsApp" }
            return "Passaggio Chat su questo iPhone"
        }()

        let screenSubtitle: String = {
            if isToAndroid {
                return "Gratuito dentro WhatsApp: una sola scansione QR, senza Android Switch"
            }
            if !isReceiverMode && !isToAndroid {
                return "Inquadra il QR di WhatsApp del nuovo iPhone senza passare dalla Fotocamera di sistema"
            }
            if isFromAndroid {
                return "Gratuito dentro WhatsApp: trasferimento diretto via QR anche su iPhone già configurato"
            }
            if isReceiverMode && !isFromAndroid {
                return "Verifica il numero qui: il vecchio iPhone si scollegherà da solo e apparirà il codice QR"
            }
            return "Trasferimento diretto della cronologia chat senza cloud"
        }()

        ScrollView {
            VStack(spacing: 18) {
                VStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(AppleTheme.green.opacity(0.16))
                            .frame(width: 72, height: 72)
                        Image(systemName: (!isReceiverMode && !isToAndroid) ? "qrcode.viewfinder" : "bubble.left.and.bubble.right.fill")
                            .font(.system(size: 34, weight: .semibold))
                            .foregroundColor(AppleTheme.green)
                    }
                    .padding(.top, 16)

                    Text(screenTitle)
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(AppleTheme.textPrimary)
                        .multilineTextAlignment(.center)

                    Text(screenSubtitle)
                        .font(.system(size: 14))
                        .foregroundColor(AppleTheme.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 12)
                }

                whatsAppNativeTransferCard(embeddedInSummary: false)

                if canSendAnotherCategory {
                    AppleSecondaryButton(
                        title: "Trasferisci un'altra voce a questo telefono",
                        icon: "arrow.uturn.backward.circle.fill",
                        tint: AppleTheme.blue,
                        action: onTransferAnotherCategory
                    )
                }

                AppleSecondaryButton(
                    title: "Fine",
                    icon: "checkmark",
                    tint: AppleTheme.slate,
                    action: onFinish
                )
            }
            .padding(.horizontal, 16)
            .padding(.bottom, appInstaller.showsFloatingBottomBar ? (appInstaller.overlaySafeBottomPadding + 165) : 28)
        }
    }

    @ViewBuilder
    private func whatsAppNativeTransferCard(embeddedInSummary: Bool) -> some View {
        let isToAndroid = !isReceiverMode && transport.peerPlatform == .ANDROID
        let isFromAndroid = isReceiverMode && transport.peerPlatform == .ANDROID
        let isPersonalInstalled = iOSInstalledAppsScanner.isPersonalWhatsAppInstalled()
        let isBusinessAlsoInstalled = iOSInstalledAppsScanner.isWhatsAppBusinessInstalled()

        let cardTitle: String = {
            if !embeddedInSummary { return "Come procedere adesso" }
            if isToAndroid { return "Trasferisci cronologia WhatsApp su Android" }
            if isFromAndroid { return "Importa Chat WhatsApp" }
            return "Trasferisci cronologia WhatsApp via QR"
        }()

        let stepsList: [String] = {
            if isToAndroid {
                return [
                    "Sul nuovo Android apri WhatsApp e verifica lo stesso numero fino al Codice QR. Se vedi i 3 pallini (⋮) in alto a destra, tocca subito ⋮ → «Mostra QR per iPhone» prima di inquadrare (eviti pop-up e riavvii).",
                    "Su questo iPhone tocca «Apri WhatsApp» qui sotto → Impostazioni ⚙️ → Chat → Trasferisci chat su Android → Inizia e inquadra il QR una sola volta dentro WhatsApp."
                ]
            }
            if !isReceiverMode {
                return [
                    "Sul nuovo iPhone apri WhatsApp Personale, inserisci il numero e il codice di conferma SMS: questo vecchio iPhone verrà disconnesso subito in automatico e sul nuovo apparirà il codice QR del trasferimento chat.",
                    "Senza aprire la Fotocamera di iPhone e senza premere il bottone giallo, tocca direttamente qui sotto «Inquadra QR di WhatsApp e avvia passaggio»: DirectSwitch leggerà il QR e aprirà subito «Trasferisci la cronologia chat su iPhone» su questo telefono!"
                ]
            }
            if isFromAndroid {
                return [
                    "Tocca il pulsante verde qui sotto per aprire (o scaricare da App Store) WhatsApp Personale su questo iPhone.",
                    "Inserisci il tuo numero e il codice SMS fino alla schermata del Codice QR (funziona anche su iPhone già configurato, senza usare Passa a iOS).",
                    "Sul vecchio Android apri WhatsApp → Impostazioni → Chat → Trasferisci chat → Inizia e inquadra il Codice QR mostrato qui."
                ]
            }
            return [
                "Tocca il pulsante verde qui sotto per aprire (o scaricare da App Store) WhatsApp Personale su questo nuovo iPhone.",
                "Inserisci il numero e il codice SMS: WhatsApp scollegherà subito il vecchio iPhone (non c'è bisogno di riaprire nulla qui) e ti chiederà di iniziare il trasferimento mostrando il codice QR su questo schermo.",
                "Lascia il codice QR visibile qui e sul vecchio iPhone tocca «Inquadra QR di WhatsApp e avvia passaggio» direttamente dentro DirectSwitch!"
            ]
        }()

        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                AppleSettingsIcon(systemName: "bubble.left.and.bubble.right.fill", color: AppleTheme.green)
                VStack(alignment: .leading, spacing: 2) {
                    Text(cardTitle)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(AppleTheme.textPrimary)
                    if embeddedInSummary {
                        Text(isToAndroid
                            ? "Gratuito dentro WhatsApp: una sola scansione QR, senza Android Switch"
                            : "Passaggio gratuito della cronologia chat via Codice QR")
                            .font(.system(size: 12))
                            .foregroundColor(AppleTheme.textSecondary)
                    }
                }
                Spacer()
                InfoCircleButton(
                    title: isToAndroid
                        ? "Come evitare la doppia scansione su Android"
                        : (isFromAndroid
                            ? "Trasferimento chat Android → iPhone senza Passa a iOS"
                            : "Come funziona dopo la disconnessione del vecchio iPhone"),
                    message: isToAndroid
                        ? "Da iPhone a Android fa tutto WhatsApp gratis con una sola scansione dentro WhatsApp stesso (non serve aprire lo scanner QR di DirectSwitch né Android Switch).\n\nSe sullo schermo QR di Android vedi i 3 pallini (⋮) in alto a destra, seleziona subito «Mostra QR per iPhone» prima di scansionare: in questo modo il QR non va riavviato e WhatsApp lo legge al primo colpo."
                        : (isFromAndroid
                            ? "WhatsApp trasferisce gratuitamente tutta la cronologia chat direttamente tramite Codice QR in Wi-Fi locale anche su iPhone già configurati, senza formattare e senza usare Passa a iOS."
                            : "Quando inserisci numero e SMS sul nuovo iPhone, WhatsApp disconnette subito il vecchio telefono (quindi sul vecchio non puoi più entrare in Impostazioni → Chat).\n\nIl codice QR mostrato sul nuovo iPhone contiene il link diretto di sblocco della schermata «Trasferisci la cronologia chat»: inquadrandolo con il pulsante qui sotto dentro DirectSwitch salti completamente la Fotocamera di iPhone e il bottone giallo!")
                )
            }

            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(stepsList.enumerated()), id: \.offset) { idx, stepText in
                    HStack(alignment: .top, spacing: 10) {
                        Text("\(idx + 1)")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .frame(width: 22, height: 22)
                            .background(AppleTheme.green)
                            .clipShape(Circle())
                            .padding(.top, 1)

                        Text(stepText)
                            .font(.system(size: 14))
                            .foregroundColor(AppleTheme.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            if !isReceiverMode {
                if isToAndroid {
                    ApplePrimaryButton(
                        title: isPersonalInstalled
                            ? "Apri WhatsApp (Trasferisci chat su Android)"
                            : "Scarica WhatsApp Personale",
                        icon: isPersonalInstalled ? "bubble.left.and.bubble.right.fill" : "arrow.down.app.fill",
                        color: AppleTheme.green
                    ) {
                        DirectSwitchTransportViewModel.openPersonalWhatsAppOrStore()
                    }
                } else {
                    // Vecchio iPhone -> Nuovo iPhone: Scanner diretto del QR WhatsApp
                    ApplePrimaryButton(
                        title: "Inquadra QR di WhatsApp e avvia passaggio",
                        icon: "qrcode.viewfinder",
                        color: AppleTheme.green
                    ) {
                        showWhatsAppQrScanner = true
                    }

                    AppleSecondaryButton(
                        title: isPersonalInstalled
                            ? "Oppure apri WhatsApp Personale"
                            : "Scarica WhatsApp Personale",
                        icon: isPersonalInstalled ? "bubble.left.and.bubble.right.fill" : "arrow.down.app.fill",
                        tint: AppleTheme.green
                    ) {
                        DirectSwitchTransportViewModel.openPersonalWhatsAppOrStore()
                    }
                }
            } else {
                // Nuovo iPhone (Ricevente): Apre direttamente WhatsApp Personale per inserire numero + codice SMS e mostrare il QR
                ApplePrimaryButton(
                    title: isPersonalInstalled
                        ? "Apri WhatsApp Personale"
                        : "Scarica WhatsApp Personale",
                    icon: isPersonalInstalled ? "bubble.left.and.bubble.right.fill" : "arrow.down.app.fill",
                    color: AppleTheme.green
                ) {
                    DirectSwitchTransportViewModel.openPersonalWhatsAppOrStore()
                }
            }

            if isToAndroid || isReceiverMode {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.clockwise.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(AppleTheme.blue)
                    Text(isToAndroid
                        ? "WhatsApp su Android già aperto senza QR? Usa «Reimposta solo WhatsApp» su Android"
                        : "WhatsApp già aperto senza schermata QR? Reinstalla solo WhatsApp")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(AppleTheme.blue)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 4)
                    InfoCircleButton(
                        title: "Perché potrei dover reimpostare solo WhatsApp?",
                        message: isToAndroid
                            ? "WhatsApp su Android mostra il Codice QR per importare le chat dall'iPhone solo durante la prima verifica del numero su una installazione pulita. Se avevi già attivato WhatsApp vuoto sul nuovo Android, tocca «Reimposta solo WhatsApp» in DirectSwitch su Android (Spazio di archiviazione → Cancella dati) per azzerare solo WhatsApp senza toccare il telefono e far riapparire il QR."
                            : "Su iPhone WhatsApp mostra il Codice QR per importare le chat subito dopo il codice SMS su una installazione pulita. Se avevi già completato l'accesso vuoto su questo iPhone saltando il QR, elimina e riscarica solo l'app WhatsApp da App Store (senza toccare il resto dell'iPhone) e reinserisci il numero per far riapparire il QR."
                    )
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(AppleTheme.inputSurface)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            if isBusinessAlsoInstalled {
                Button(action: {
                    DirectSwitchTransportViewModel.openWhatsAppBusiness()
                }) {
                    HStack(spacing: 5) {
                        Image(systemName: "briefcase.fill")
                            .font(.system(size: 11, weight: .semibold))
                        Text("Devi trasferire invece l'account aziendale? Apri WhatsApp Business")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundColor(AppleTheme.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 2)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .background(AppleTheme.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(AppleTheme.green.opacity(0.48), lineWidth: 1.2)
        )
    }

    // MARK: - Schermata Avanzamento Dati Selezionati (sempre da 0% -> 100%, mostra SOLO le voci scelte in questo trasferimento)

    private var standardDataTransferScreen: some View {
        ScrollView {
            VStack(spacing: 18) {
                VStack(spacing: 10) {
                    if transport.isCompleted {
                        if isReceiverAppsOnlyPhase {
                            let allAppsHandled = !appInstaller.queueableApps.isEmpty && handledQueueableAppsCount >= appInstaller.queueableApps.count
                            ZStack {
                                Circle()
                                    .fill((allAppsHandled ? AppleTheme.green : AppleTheme.blue).opacity(0.16))
                                    .frame(width: 68, height: 68)
                                Image(systemName: allAppsHandled ? "checkmark.circle.fill" : "arrow.down.app.fill")
                                    .font(.system(size: 36, weight: .semibold))
                                    .foregroundColor(allAppsHandled ? AppleTheme.green : AppleTheme.blue)
                            }
                            .padding(.top, 14)

                            Text(allAppsHandled ? "Tutte le App avviate su iPhone" : "App ricevute — Pronte da scaricare")
                                .font(.system(size: 22, weight: .bold))
                                .foregroundColor(AppleTheme.textPrimary)
                                .multilineTextAlignment(.center)

                            Text("Hai ricevuto l'elenco di \(transport.receivedInstalledApps.count) app dal vecchio telefono. Segui i 2 passaggi qui sotto e tocca «Fatto» per sbloccare il download.")
                                .font(.system(size: 13.5))
                                .foregroundColor(AppleTheme.textSecondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 12)
                        } else if isReceiverAppsPhase {
                            ZStack {
                                Circle()
                                    .fill(AppleTheme.green.opacity(0.16))
                                    .frame(width: 68, height: 68)
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 40, weight: .semibold))
                                    .foregroundColor(AppleTheme.green)
                            }
                            .padding(.top, 14)

                            Text("Dati salvati • App pronte da scaricare")
                                .font(.system(size: 22, weight: .bold))
                                .foregroundColor(AppleTheme.textPrimary)
                                .multilineTextAlignment(.center)

                            Text("Le altre voci selezionate sono state copiate su questo iPhone. Completa la guida qui sotto per scaricare le \(transport.receivedInstalledApps.count) app ricevute.")
                                .font(.system(size: 13.5))
                                .foregroundColor(AppleTheme.textSecondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 12)
                        } else {
                            ZStack {
                                Circle()
                                    .fill(AppleTheme.green.opacity(0.16))
                                    .frame(width: 68, height: 68)
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 40, weight: .semibold))
                                    .foregroundColor(AppleTheme.green)
                            }
                            .padding(.top, 14)

                            Text("Trasferimento completato")
                                .font(.system(size: 24, weight: .bold))
                                .foregroundColor(AppleTheme.textPrimary)

                            Text(isReceiverMode
                                 ? "Le voci selezionate sono pronte su questo iPhone"
                                 : "Le voci selezionate sono state copiate su \(transport.peerName.isEmpty ? "il nuovo telefono" : transport.peerName)")
                                .font(.system(size: 14))
                                .foregroundColor(AppleTheme.textSecondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 12)
                        }
                    } else {
                        DirectSwitchAppleEmblem(size: 68)
                            .padding(.top, 14)

                        if transport.errorMessage != nil {
                            Text("Trasferimento in pausa (\(percentageInt)%)")
                                .font(.system(size: 23, weight: .bold))
                                .foregroundColor(AppleTheme.textPrimary)

                            Text("I file già copiati sono al sicuro e non verranno duplicati")
                                .font(.system(size: 14))
                                .foregroundColor(AppleTheme.textSecondary)
                                .multilineTextAlignment(.center)
                        } else {
                            Text(isReceiverMode ? "Copia su questo iPhone..." : "Copia delle voci selezionate...")
                                .font(.system(size: 23, weight: .bold))
                                .foregroundColor(AppleTheme.textPrimary)

                            Text("Tieni entrambi i telefoni vicini fino al termine")
                                .font(.system(size: 14))
                                .foregroundColor(AppleTheme.textSecondary)
                                .multilineTextAlignment(.center)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    let isBarCompleteGreen = isReceiverAppsOnlyPhase
                        ? (!appInstaller.queueableApps.isEmpty && handledQueueableAppsCount >= appInstaller.queueableApps.count)
                        : transport.isCompleted

                    HStack(alignment: .firstTextBaseline) {
                        if isReceiverAppsOnlyPhase && appInstaller.queueableApps.isEmpty {
                            Text("Elenco ricevuto")
                                .font(.system(size: 24, weight: .bold, design: .rounded))
                                .foregroundColor(AppleTheme.blue)
                        } else {
                            Text("\(percentageInt)%")
                                .font(.system(size: 32, weight: .bold, design: .rounded))
                                .foregroundColor(isBarCompleteGreen ? AppleTheme.green : (isReceiverAppsOnlyPhase ? AppleTheme.blue : AppleTheme.textPrimary))
                        }

                        Spacer()

                        if isReceiverAppsOnlyPhase {
                            Text(appInstaller.isRunningSequence
                                 ? "Download in coda"
                                 : (isBarCompleteGreen ? "App avviate ✓" : "Pronte da scaricare"))
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(isBarCompleteGreen ? AppleTheme.green : AppleTheme.blue)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background((isBarCompleteGreen ? AppleTheme.green : AppleTheme.blue).opacity(0.10))
                                .clipShape(Capsule())
                        } else if isReceiverAppsPhase {
                            Text("Dati copiati • \(handledQueueableAppsCount)/\(appInstaller.queueableApps.count) app")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(AppleTheme.blue)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(AppleTheme.blue.opacity(0.10))
                                .clipShape(Capsule())
                        } else if transport.speedMegabytesPerSec > 0.05 && !transport.isCompleted {
                            Text(String(format: "%.1f MB/s", transport.speedMegabytesPerSec))
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(AppleTheme.blue)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(AppleTheme.blue.opacity(0.10))
                                .clipShape(Capsule())
                        }
                    }

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(AppleTheme.inputSurface)
                                .frame(height: 10)

                            Capsule()
                                .fill(isBarCompleteGreen ? AppleTheme.green : AppleTheme.blue)
                                .frame(width: max(12, geo.size.width * progressFraction), height: 10)
                                .animation(.easeInOut(duration: 0.25), value: progressFraction)
                        }
                    }
                    .frame(height: 10)

                    HStack {
                        if isReceiverAppsOnlyPhase {
                            Text(appInstaller.queueableApps.isEmpty
                                 ? "\(transport.receivedInstalledApps.count) app ricevute in elenco (senza scheda App Store diretta)"
                                 : "\(handledQueueableAppsCount) / \(appInstaller.queueableApps.count) app avviate o installate (\(transport.receivedInstalledApps.count) ricevute)")
                                .font(.system(size: 13))
                                .foregroundColor(AppleTheme.textSecondary)
                                .lineLimit(2)
                        } else {
                            Text(transport.currentItemName.isEmpty ? transport.statusLabel : transport.currentItemName)
                                .font(.system(size: 13))
                                .foregroundColor(AppleTheme.textSecondary)
                                .lineLimit(1)

                            Spacer()

                            if transport.totalBytesCount > 0 {
                                Text("\(DirectSwitchUIHelpers.formatBytes(transport.transferredBytesCount)) / \(DirectSwitchUIHelpers.formatBytes(transport.totalBytesCount))")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(AppleTheme.textSecondary)
                            }
                        }
                    }

                    if let eta = remainingTimeLabel {
                        HStack(spacing: 6) {
                            Image(systemName: "clock.fill")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(AppleTheme.blue)
                            Text(eta)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(AppleTheme.blue)
                        }
                        .padding(.top, 2)
                    }
                }
                .appleCard()

                // Mostra ESCLUSIVAMENTE le categorie selezionate per QUESTO trasferimento
                if !visibleSummaryRows.isEmpty {
                    VStack(spacing: 0) {
                        ForEach(Array(visibleSummaryRows.enumerated()), id: \.element.id) { index, row in
                            summaryRow(
                                icon: row.icon,
                                color: row.color,
                                title: row.title,
                                value: row.value
                            )
                            if index < visibleSummaryRows.count - 1 {
                                Divider().padding(.leading, 56)
                            }
                        }
                    }
                    .appleCard(padding: 0)
                }

                if !isReceiverMode && transport.isCompleted && transport.canResumeInterruptedTransfer && transport.failedItemsCount > 0 {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.clockwise.circle.fill")
                                .foregroundColor(AppleTheme.blue)
                            Text("Completa i \(transport.failedItemsCount) file rimasti in sospeso")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(AppleTheme.textPrimary)
                        }
                        Text("I file già copiati non verranno duplicati: tocca qui per riprendere subito da dove era rimasto.")
                            .font(.system(size: 13))
                            .foregroundColor(AppleTheme.textSecondary)
                        AppleSecondaryButton(
                            title: "Riprendi trasferimento da dove era rimasto",
                            icon: "play.fill",
                            tint: AppleTheme.blue,
                            action: onRetryIfFailed
                        )
                    }
                    .appleCard(padding: 14)
                }

                if isReceiverMode && transport.isCompleted && scope.documents && transport.receivedPasswordsCsvCount > 0 {
                    passwordsCsvImportHelperCard
                }

                // Mostra il catalogo di installazione automatica App SOLO se in questo trasferimento è stata selezionata «App scaricate»
                if isReceiverMode && transport.isCompleted && scope.apps {
                    ReceiverAppsAutoInstallCard(
                        incomingApps: transport.receivedInstalledApps,
                        installer: appInstaller,
                        onAppsScannedOnReceiver: { scanned in
                            transport.updateReceiverScannedApps(scanned, replaceExisting: false, completed: true)
                        }
                    )
                }

                if isReceiverMode && transport.isCompleted && ((scope.documents && transport.completedItems > 0) || !transport.receivedDocumentFolders.isEmpty || transport.importedSms > 0) {
                    receivedDocumentFoldersCard
                }

                if transport.isCompleted && transport.pendingNativeWhatsAppMigration {
                    whatsAppNativeTransferCard(embeddedInSummary: true)
                }

                if transport.needsLocalNetworkRedirect || transport.isLocalNetworkDenied {
                    VStack(spacing: 10) {
                        LocalNetworkRedirectBanner(
                            detailMessage: transport.errorMessage
                        ) {
                            DirectSwitchTransportViewModel.openAppSettings()
                        }
                        if !isReceiverMode {
                            ApplePrimaryButton(
                                title: transport.canResumeInterruptedTransfer
                                    ? "Riprendi trasferimento da dove era rimasto"
                                    : "Riprova copia",
                                icon: "arrow.clockwise",
                                color: AppleTheme.blue,
                                action: onRetryIfFailed
                            )
                            if transport.canResumeInterruptedTransfer {
                                AppleSecondaryButton(
                                    title: "Ricollega con nuovo codice / QR (salta già copiati)",
                                    icon: "qrcode",
                                    tint: AppleTheme.teal,
                                    action: onReconnectNewCode
                                )
                            }
                        }
                    }
                } else if let err = transport.errorMessage, !err.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(AppleTheme.red)
                            Text(err)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(AppleTheme.red)
                        }
                        if err.contains("Impostazioni") {
                            AppleSecondaryButton(
                                title: "Apri Impostazioni DirectSwitch",
                                icon: "gearshape.fill",
                                tint: AppleTheme.orange
                            ) {
                                DirectSwitchTransportViewModel.openAppSettings()
                            }
                        }
                        if !isReceiverMode {
                            ApplePrimaryButton(
                                title: transport.canResumeInterruptedTransfer
                                    ? "Riprendi trasferimento da dove era rimasto"
                                    : "Riprova copia",
                                icon: "arrow.clockwise",
                                color: AppleTheme.blue,
                                action: onRetryIfFailed
                            )
                            if transport.canResumeInterruptedTransfer {
                                AppleSecondaryButton(
                                    title: "Ricollega con nuovo codice / QR (salta già copiati)",
                                    icon: "qrcode",
                                    tint: AppleTheme.teal,
                                    action: onReconnectNewCode
                                )
                            }
                        }
                    }
                    .appleCard(padding: 14)
                }

                if transport.isCompleted {
                    if canSendAnotherCategory {
                        AppleSecondaryButton(
                            title: "Trasferisci un'altra voce a questo telefono",
                            icon: "arrow.uturn.backward.circle.fill",
                            tint: AppleTheme.blue,
                            action: onTransferAnotherCategory
                        )
                    }
                    ApplePrimaryButton(
                        title: "Fine",
                        icon: "checkmark",
                        color: AppleTheme.blue,
                        action: onFinish
                    )
                } else if transport.errorMessage != nil {
                    if canSendAnotherCategory {
                        AppleSecondaryButton(
                            title: "Torna alla scelta delle voci",
                            icon: "arrow.uturn.backward",
                            tint: AppleTheme.blue,
                            action: onTransferAnotherCategory
                        )
                    }
                    AppleSecondaryButton(
                        title: "Torna alla Home",
                        icon: "house",
                        tint: AppleTheme.slate,
                        action: onFinish
                    )
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, appInstaller.showsFloatingBottomBar ? (appInstaller.overlaySafeBottomPadding + 165) : 28)
        }
    }

    private var passwordsCsvImportHelperCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                AppleSettingsIcon(systemName: "key.fill", color: AppleTheme.orange)
                Text("Password ricevute (\(transport.receivedPasswordsCsvCount) file .csv)")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(AppleTheme.textPrimary)
                Spacer()
                InfoCircleButton(
                    title: "Importare le Password senza iCloud",
                    message: "1. Tocca il pulsante qui sotto per aprire Impostazioni.\n2. Vai in App → Password (oppure Safari → Importa) e seleziona il file .csv salvato in «Password_Esportate» (vedi il riepilogo cartelle qui sotto).\n3. Tutte le password verranno salvate nel Portachiavi locale con Face ID senza attivare iCloud!"
                )
            }

            AppleSecondaryButton(
                title: "Importa Password in Impostazioni",
                icon: "key.horizontal.fill",
                tint: AppleTheme.orange
            ) {
                DirectSwitchTransportViewModel.openAppSettings()
            }
        }
        .appleCard(padding: 14)
    }

    private var receivedDocumentFoldersCard: some View {
        let sortedFolders = transport.receivedDocumentFolders.sorted { $0.key < $1.key }
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "folder.fill")
                    .foregroundColor(AppleTheme.blue)
                Text("Posizioni e cartelle ricreate su questo iPhone:")
                    .font(.system(size: 13))
                    .foregroundColor(AppleTheme.textSecondary)
                Spacer()
            }

            if !sortedFolders.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(sortedFolders.prefix(12)), id: \.key) { entry in
                        HStack(spacing: 8) {
                            Image(systemName: "folder.badge.plus")
                                .font(.system(size: 12))
                                .foregroundColor(AppleTheme.blue)
                            Text(entry.key)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(AppleTheme.textPrimary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            Text("\(entry.value) file")
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundColor(AppleTheme.textSecondary)
                        }
                        .padding(.vertical, 5)
                        .padding(.horizontal, 10)
                        .background(AppleTheme.inputSurface)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    if sortedFolders.count > 12 {
                        Text("…e altre \(sortedFolders.count - 12) cartelle nelle rispettive posizioni di destinazione")
                            .font(.system(size: 12))
                            .foregroundColor(AppleTheme.textSecondary)
                    }
                }
            }
        }
        .appleCard(padding: 14)
    }

    private func summaryRow(icon: String, color: Color, title: String, value: String) -> some View {
        HStack(spacing: 12) {
            AppleSettingsIcon(systemName: icon, color: color)
            Text(title)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(AppleTheme.textPrimary)
            Spacer()
            Text(value)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundColor(AppleTheme.textSecondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }
}
