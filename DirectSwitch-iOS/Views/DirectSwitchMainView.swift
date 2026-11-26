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
    @ObservedObject var l10n = DirectSwitchLocalizationStore.shared

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
    @State private var includeAudio: Bool = false
    @State private var includeApps: Bool = false
    @State private var includeWhatsApp: Bool = false

    @State private var calendarsUpToTodayOnly: Bool = false
    @State private var remindersUpToTodayOnly: Bool = false
    @State private var mediaFilters: MediaTransferFilterOptions = MediaTransferFilterOptions()
    @State private var activeDeltaBaseline: CompletedMigrationRecord? = nil
    @State private var forceBatteryTriage: Bool = false
    @State private var smartCleanOptions: SmartCleanOptions = SmartCleanOptions()
    @State private var convertHeicToJpeg: Bool = false
    @State private var availablePhotoAlbums: [String] = []
    @State private var pickedAudioFiles: [(ManifestItem, URL)] = []
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
    @State private var isLaunchingTransfer: Bool = false
    @State private var showPositionsImporter: Bool = false
    @State private var showFilesImporter: Bool = false
    @State private var showAudioNotesImporter: Bool = false
    @State private var showPasswordCsvImporter: Bool = false
    @State private var showReceiverDestImporter: Bool = false
    @State private var showReceiverFallbackImporter: Bool = false
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
            return l10n.text("nav_receive", fallbackItalian: "Ricevi")
        case .receiveConnected:
            return l10n.text("nav_connected", fallbackItalian: "Collegato")
        case .sendConnect:
            return l10n.text("nav_connect", fallbackItalian: "Invia")
        case .sendSelectCategories:
            return l10n.text("nav_select", fallbackItalian: "Cosa inviare")
        case .transferPreparing:
            return l10n.text("nav_preparing", fallbackItalian: "Preparazione")
        case .transferProgress:
            if isDedicatedWhatsAppScreenActive {
                return l10n.tr("Chat WhatsApp")
            }
            if isReceiverMode && transport.isCompleted && transport.activeTransferScope.isAppsOnly {
                return l10n.text("nav_apps_ready", fallbackItalian: "App pronte")
            }
            return transport.isCompleted
                ? l10n.text("nav_done", fallbackItalian: "Completato")
                : l10n.text("nav_copying", fallbackItalian: "Copia dati")
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
                                resumableCheckpoint: transport.resumableCheckpoint,
                                onResumeCheckpoint: { cp in resumeSavedCheckpoint(cp) },
                                onDismissCheckpoint: { transport.dismissResumableCheckpoint() },
                                completedDeltaRecord: transport.completedDeltaRecord,
                                onStartDeltaSync: { rec in
                                    startSendWizard(destination: rec.peerPlatform == .IOS ? .newIPhone : .newAndroid)
                                    activeDeltaBaseline = rec
                                    includeContacts = rec.lastScope.contacts
                                    includePhotos = rec.lastScope.photos
                                    includeVideos = rec.lastScope.videos
                                    includeCalendars = rec.lastScope.calendars
                                    includeReminders = rec.lastScope.reminders
                                    includeDocuments = rec.lastScope.documents
                                    includeAudio = rec.lastScope.audio
                                    includeApps = false
                                    includeWhatsApp = false
                                },
                                onDismissDelta: {
                                    activeDeltaBaseline = nil
                                    transport.dismissCompletedDeltaRecord()
                                },
                                onStartReceive: startReceiveWizard,
                                onStartSendToIPhone: {
                                    activeDeltaBaseline = nil
                                    startSendWizard(destination: .newIPhone)
                                }
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
                                networkDiagnostic: transport.networkDiagnostic,
                                onConfirmPin: confirmPinPairing,
                                onScannedQrCode: handleScannedQrString,
                                onApplyManualCode: { handleScannedQrString(manualCodeInput) },
                                onOpenAppSettings: {
                                    DirectSwitchTransportViewModel.openAppSettings()
                                },
                                onRetryNetwork: {
                                    transport.startUdpAutoDiscovery()
                                    if selectedBeacon != nil && pinCodeInput.filter(\.isNumber).count == 6 {
                                        confirmPinPairing()
                                    }
                                }
                            )

                        case .sendSelectCategories:
                            if let paired = pairedTargetPayload {
                                SendCategoriesStepView(
                                    pairedPayload: paired,
                                    scanSummary: scanSummary,
                                    isLocalProUnlocked: true,
                                    pickedDocuments: pickedDocuments,
                                    pickedAudioFiles: pickedAudioFiles,
                                    availablePhotoAlbums: availablePhotoAlbums,
                                    documentPrecheck: documentPrecheckReport,
                                    isLoadingPositions: isLoadingDocumentPositions,
                                    isLaunchingTransfer: isLaunchingTransfer,
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
                                    includeAudio: $includeAudio,
                                    includeApps: $includeApps,
                                    includeWhatsApp: $includeWhatsApp,
                                    mediaFilters: $mediaFilters,
                                    activeDeltaBaseline: activeDeltaBaseline,
                                    forceBatteryTriage: $forceBatteryTriage,
                                    smartCleanOptions: $smartCleanOptions,
                                    convertHeicToJpeg: $convertHeicToJpeg,
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
                                    onPickAudioOrNotes: { presentDocumentPicker(mode: .audioOrNotes) },
                                    onClearAudioFiles: { pickedAudioFiles.removeAll() },
                                    onPickPasswordCsv: { presentDocumentPicker(mode: .passwordCsv) },
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
                                onRetrySkippedOnly: { ids in
                                    if !isReceiverMode, let paired = pairedTargetPayload, !ids.isEmpty {
                                        launchSenderTransferWithPayload(paired, isResume: false, onlyRetryItemIds: Set(ids))
                                    }
                                },
                                onApplySpaceRelief: { action in
                                    applySpaceReliefAndRestart(action)
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
        .background {
            // Selettori File nativi SwiftUI isolati per tipo: elimina completamente il bug UIKit "schermata bianca" su iOS 17/18/26!
            ZStack {
                Color.clear.fileImporter(
                    isPresented: $showPositionsImporter,
                    allowedContentTypes: [.folder],
                    allowsMultipleSelection: false
                ) { result in
                    handleFileImporterResult(result, mode: .positions)
                }
                Color.clear.fileImporter(
                    isPresented: $showFilesImporter,
                    allowedContentTypes: [.item],
                    allowsMultipleSelection: true
                ) { result in
                    handleFileImporterResult(result, mode: .files)
                }
                Color.clear.fileImporter(
                    isPresented: $showAudioNotesImporter,
                    allowedContentTypes: [.audio, .plainText, .pdf, .item],
                    allowsMultipleSelection: true
                ) { result in
                    handleFileImporterResult(result, mode: .audioOrNotes)
                }
                Color.clear.fileImporter(
                    isPresented: $showPasswordCsvImporter,
                    allowedContentTypes: [.commaSeparatedText, .plainText],
                    allowsMultipleSelection: false
                ) { result in
                    handleFileImporterResult(result, mode: .passwordCsv)
                }
                Color.clear.fileImporter(
                    isPresented: $showReceiverDestImporter,
                    allowedContentTypes: [.folder],
                    allowsMultipleSelection: false
                ) { result in
                    handleFileImporterResult(result, mode: .receiverDestinations)
                }
                Color.clear.fileImporter(
                    isPresented: $showReceiverFallbackImporter,
                    allowedContentTypes: [.folder],
                    allowsMultipleSelection: false
                ) { result in
                    handleFileImporterResult(result, mode: .receiverFallbackRoot)
                }
            }
            .allowsHitTesting(false)
        }
        .onChange(of: mediaFilters.includeICloudOnlyMedia) { _ in
            if includePhotos { enqueuePreloadPhotos() }
            if includeVideos { enqueuePreloadVideos() }
            refreshAuthorizedSummary()
        }
        .alert(
            l10n.tr("Controllo posizioni sul telefono"),
            isPresented: Binding(
                get: { pendingTransferPrecheckAlert != nil },
                set: { if !$0 { pendingTransferPrecheckAlert = nil } }
            ),
            presenting: pendingTransferPrecheckAlert
        ) { report in
            Button(l10n.tr("Seleziona posizione")) {
                pendingTransferPrecheckAlert = nil
                presentDocumentPicker(mode: .positions)
            }
            if report.totalFiles > 0 {
                Button(l10n.tr("Continua comunque")) {
                    let paired = pairedTargetPayload
                    pendingTransferPrecheckAlert = nil
                    if let paired {
                        launchSenderTransferWithPayload(paired, isResume: false)
                    }
                }
            } else if includeContacts || includePhotos || includeVideos || includeCalendars || includeReminders || includeAudio || includeApps || includeWhatsApp {
                Button(l10n.tr("Invia escludendo Documenti")) {
                    includeDocuments = false
                    let paired = pairedTargetPayload
                    pendingTransferPrecheckAlert = nil
                    if let paired {
                        launchSenderTransferWithPayload(paired, isResume: false)
                    }
                }
            }
            Button(l10n.tr("Annulla"), role: .cancel) {
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
        // Resetta eventuali flag stale prima di presentare il selettore nativo SwiftUI `.fileImporter`
        showPositionsImporter = false
        showFilesImporter = false
        showAudioNotesImporter = false
        showPasswordCsvImporter = false
        showReceiverDestImporter = false
        showReceiverFallbackImporter = false

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            switch mode {
            case .positions, .folders:
                self.showPositionsImporter = true
            case .files:
                self.showFilesImporter = true
            case .audioOrNotes:
                self.showAudioNotesImporter = true
            case .passwordCsv:
                self.showPasswordCsvImporter = true
            case .receiverDestinations:
                self.showReceiverDestImporter = true
            case .receiverFallbackRoot:
                self.showReceiverFallbackImporter = true
            }
        }
    }

    private func handleFileImporterResult(_ result: Result<[URL], Error>, mode: iOSDocumentPickerMode) {
        switch result {
        case .success(let urls):
            handlePickedDocumentURLs(urls, mode: mode)
        case .failure:
            isLoadingDocumentPositions = false
        }
    }

    private func handlePickedDocumentURLs(_ urls: [URL], mode: iOSDocumentPickerMode) {
        guard !urls.isEmpty else { return }
        let allowCloud = mediaFilters.includeICloudOnlyMedia
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
            Task {
                let (summary, precheck) = await Task.detached(priority: .userInitiated) {
                    _ = iOSDocumentsSandboxBridge.authorizePositionBookmarks(urls)
                    let sum = iOSDeviceDataAnalyzer.scanAuthorizedSummary(
                        stagedItems: currentStaged,
                        includePairedLiveVideoBytes: true,
                        allowCloudOnly: allowCloud
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
                    sharedVaultToast = l10n.tr(
                        "Posizione «\(lastAdded.locationName)» caricata (\(lastAdded.fileCount) file idonei)",
                        en: "Location \"\(lastAdded.locationName)\" ready (\(lastAdded.fileCount) eligible files)",
                        fr: "Emplacement « \(lastAdded.locationName) » prêt (\(lastAdded.fileCount) fichiers prêts)"
                    )
                }
            }
        case .files:
            isLoadingDocumentPositions = true
            let existingStaged = pickedDocuments.map(\.0)
            Task {
                let (imported, summary, precheck) = await Task.detached(priority: .userInitiated) {
                    let imp = iOSDocumentsSandboxBridge.importPickedDocumentURLs(urls)
                    let allStaged = existingStaged + imp.map(\.0)
                    let sum = iOSDeviceDataAnalyzer.scanAuthorizedSummary(
                        stagedItems: allStaged,
                        includePairedLiveVideoBytes: true,
                        allowCloudOnly: allowCloud
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
        case .audioOrNotes:
            Task {
                let imported = await Task.detached(priority: .userInitiated) {
                    iOSAudioAndCallLogMigrator.importPickedAudioOrNoteURLs(urls)
                }.value
                if !imported.isEmpty {
                    pickedAudioFiles.append(contentsOf: imported)
                    includeAudio = true
                    sharedVaultToast = l10n.tr(
                        "\(imported.count) file audio/note pronti per la copia",
                        en: "\(imported.count) audio/note files ready to copy",
                        fr: "\(imported.count) fichiers audio/notes prêts à copier"
                    )
                }
            }
        case .passwordCsv:
            isLoadingDocumentPositions = true
            let existingStaged = pickedDocuments.map(\.0)
            Task {
                let (imported, summary, precheck) = await Task.detached(priority: .userInitiated) {
                    let imp = iOSDocumentsSandboxBridge.importPickedDocumentURLs(urls)
                    let allStaged = existingStaged + imp.map(\.0)
                    let sum = iOSDeviceDataAnalyzer.scanAuthorizedSummary(
                        stagedItems: allStaged,
                        includePairedLiveVideoBytes: true,
                        allowCloudOnly: allowCloud
                    )
                    let pre = iOSDocumentsSandboxBridge.inspectPreTransferDocuments(
                        stagedItems: allStaged,
                        includeWhatsAppVault: false
                    )
                    return (imp, sum, pre)
                }.value
                if !imported.isEmpty {
                    pickedDocuments.append(contentsOf: imported)
                    includeDocuments = true
                    sharedVaultToast = l10n.tr(
                        "CSV Password pronto (verrà sovrascritto a zeri a fine trasferimento)",
                        en: "Password CSV ready (securely zero-wiped after transfer)",
                        fr: "CSV Mots de passe prêt (effacé par écrasement après le transfert)"
                    )
                }
                scanSummary = summary
                documentPrecheckReport = precheck
                isLoadingDocumentPositions = false
            }
        }
    }

    private func precheckAlertMessage(for report: iOSDocumentsPrecheckReport) -> String {
        let selectedCount = report.locationSummaries.filter(\.isSelected).count
        if !report.locationSummaries.isEmpty && selectedCount == 0 {
            return l10n.tr(
                "Nessuna posizione è selezionata con la spunta. Seleziona almeno una posizione da trasferire nell'elenco oppure aggiungine un'altra.",
                en: "No location is checked. Select at least one location in the list or add another one.",
                fr: "Aucun emplacement n'est coché. Sélectionnez-en au moins un ou ajoutez-en un autre."
            )
        }
        if report.totalFiles == 0 && report.unreadableFilesCount == 0 {
            return l10n.tr(
                "Nessun file idoneo trovato nelle posizioni selezionate. Tocca «Seleziona posizione», entra nella posizione da trasferire (es. Su iPhone o iCloud Drive) e premi «Apri» in alto a destra.",
                en: "No eligible files found in selected locations. Tap 'Select location', open the folder (e.g. On My iPhone or iCloud Drive) and tap 'Open' at the top right.",
                fr: "Aucun fichier prêt dans les emplacements sélectionnés. Touchez « Sélectionner un emplacement », ouvrez le dossier et touchez « Ouvrir » en haut à droite."
            )
        }
        if report.totalFiles == 0 && report.unreadableFilesCount > 0 {
            return l10n.tr(
                "Trovati \(report.unreadableFilesCount) file solo su iCloud e non scaricati localmente. Scaricali nell'app File prima di copiarli.",
                en: "Found \(report.unreadableFilesCount) iCloud-only files not downloaded locally. Download them in the Files app first.",
                fr: "\(report.unreadableFilesCount) fichiers uniquement sur iCloud non téléchargés. Téléchargez-les d'abord dans Fichiers."
            )
        }
        return l10n.tr(
            "Controllo completato: \(report.totalFiles) file idonei al trasferimento in \(max(1, selectedCount)) posizioni selezionate.",
            en: "Check complete: \(report.totalFiles) eligible files ready in \(max(1, selectedCount)) selected locations.",
            fr: "Vérification terminée : \(report.totalFiles) fichiers prêts dans \(max(1, selectedCount)) emplacements."
        )
    }

    private func launchSenderTransfer() {
        guard let paired = pairedTargetPayload, !isLaunchingTransfer else { return }
        if includeDocuments {
            isLaunchingTransfer = true
            let staged = pickedDocuments.map(\.0)
            Task {
                let precheck = await Task.detached(priority: .userInitiated) {
                    iOSDocumentsSandboxBridge.inspectPreTransferDocuments(
                        stagedItems: staged,
                        includeWhatsAppVault: false
                    )
                }.value
                documentPrecheckReport = precheck
                isLaunchingTransfer = false
                // Blocca con avviso SOLO se non ci sono file idonei trasferibili (i file solo-iCloud vengono già esclusi a priori)
                if precheck.totalFiles == 0 {
                    pendingTransferPrecheckAlert = precheck
                    return
                }
                launchSenderTransferWithPayload(paired, isResume: false)
            }
            return
        }
        isLaunchingTransfer = true
        DispatchQueue.main.async {
            self.launchSenderTransferWithPayload(paired, isResume: false)
            self.isLaunchingTransfer = false
        }
    }

    private func resumeSavedCheckpoint(_ checkpoint: TransferCheckpointRecord) {
        guard let parsed = try? QrPairingPayload.fromJson(checkpoint.qrPayloadJson) else {
            transport.dismissResumableCheckpoint()
            return
        }
        pairedTargetPayload = parsed
        includeContacts = checkpoint.scope.contacts
        includePhotos = checkpoint.scope.photos
        includeVideos = checkpoint.scope.videos
        includeCalendars = checkpoint.scope.calendars
        includeReminders = checkpoint.scope.reminders
        includeDocuments = checkpoint.scope.documents
        includeAudio = checkpoint.scope.audio
        includeApps = checkpoint.scope.apps
        includeWhatsApp = checkpoint.scope.whatsApp
        mediaFilters = checkpoint.filterOptions
        transport.restoreCheckpointIntoMemory(checkpoint)
        launchSenderTransferWithPayload(parsed, isResume: true)
    }

    private func applySpaceReliefAndRestart(_ action: SpaceReliefActionKind) {
        guard let paired = pairedTargetPayload else { return }
        switch action {
        case .compactVideosHevc1080p:
            mediaFilters.compactVideo1080pHevc = true
        case .excludeHeavyVideos300Mb:
            mediaFilters.maxVideoBytes = SpaceReliefPlanner.heavyVideoThresholdBytes
        case .lastYearMediaOnly:
            mediaFilters.photosLastYearOnly = true
            mediaFilters.videosLastYearOnly = true
        }
        launchSenderTransferWithPayload(paired, isResume: false)
    }

    private func launchSenderTransferWithPayload(
        _ paired: QrPairingPayload,
        isResume: Bool,
        onlyRetryItemIds: Set<String>? = nil
    ) {
        sharedVaultToast = nil
        isReceiverMode = false
        let isTargetedRetry = !(onlyRetryItemIds?.isEmpty ?? true)
        let currentScope = ActiveTransferScope(
            contacts: isTargetedRetry ? false : includeContacts,
            photos: includePhotos,
            videos: includeVideos,
            calendars: isTargetedRetry ? false : includeCalendars,
            reminders: isTargetedRetry ? false : includeReminders,
            documents: includeDocuments,
            audio: includeAudio,
            apps: isTargetedRetry ? false : includeApps,
            whatsApp: isTargetedRetry ? false : includeWhatsApp
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
            activeStep = (!isResume && !isTargetedRetry && !currentScope.isWhatsAppOnly) ? .transferPreparing : .transferProgress
        }
        let docsSnapshot = pickedDocuments
        let audioSnapshot = pickedAudioFiles
        let filtersSnapshot = mediaFilters
        let appsSnapshot: [InstalledAppRecord] = (includeApps && !isTargetedRetry)
            ? selectedSenderApps.filter {
                paired.receiverPlatform != .ANDROID || !iOSInstalledAppsScanner.isGoogleAppPreinstalledOnAndroid($0)
            }
            : []
        let calCutoff = calendarsUpToTodayOnly
        let remCutoff = remindersUpToTodayOnly
        let deltaSnap = activeDeltaBaseline
        let triageSnap = forceBatteryTriage
        let smartCleanSnap = smartCleanOptions
        let heicSnap = convertHeicToJpeg
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
                includeAudio: includeAudio,
                includeApps: includeApps,
                includeWhatsAppVault: includeWhatsApp,
                installedApps: appsSnapshot,
                pickedDocuments: docsSnapshot,
                pickedAudioFiles: audioSnapshot,
                mediaFilters: filtersSnapshot,
                onlyRetryItemIds: onlyRetryItemIds,
                isResume: isResume,
                deltaBaseline: deltaSnap,
                forceBatteryTriage: triageSnap,
                smartCleanOptions: smartCleanSnap,
                convertHeicToJpeg: heicSnap
            )
            if transport.isCompleted && transport.failedItemsCount == 0 && transport.reconciliationMissingIds.isEmpty {
                pickedDocuments.removeAll()
                pickedAudioFiles.removeAll()
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
        includeAudio = false
        includeApps = false
        includeWhatsApp = false
        calendarsUpToTodayOnly = false
        remindersUpToTodayOnly = false
        mediaFilters = MediaTransferFilterOptions()
        pickedAudioFiles.removeAll()
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
        let allowCloud = mediaFilters.includeICloudOnlyMedia
        categoryTaskQueue.enqueue {
            photosPreload.isLoading = true
            photosPreload.isCompleted = false
            _ = await iOSPhotoKitMigrator.requestAccessIfNeeded()
            refreshAuthorizedSummary()
            let res = await iOSPhotoKitMigrator.preloadMediaStatsWithProgress(
                for: .image,
                includePairedLiveVideoBytes: true,
                allowCloudOnly: allowCloud
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
            availablePhotoAlbums = await Task.detached(priority: .utility) {
                iOSPhotoFilterHelper.fetchUserAlbumTitles()
            }.value
            refreshAuthorizedSummary()
            if includeApps {
                refreshSenderAppsCatalog()
            }
        }
    }

    private func enqueuePreloadVideos() {
        videosPreload.isLoading = true
        videosPreload.isCompleted = false
        let allowCloud = mediaFilters.includeICloudOnlyMedia
        categoryTaskQueue.enqueue {
            videosPreload.isLoading = true
            videosPreload.isCompleted = false
            _ = await iOSPhotoKitMigrator.requestAccessIfNeeded()
            refreshAuthorizedSummary()
            let res = await iOSPhotoKitMigrator.preloadMediaStatsWithProgress(
                for: .video,
                includePairedLiveVideoBytes: false,
                allowCloudOnly: allowCloud
            ) { loaded, tot, _, _, iCloudCount, bytes in
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
            let allowCloud = mediaFilters.includeICloudOnlyMedia
            let (summary, precheck) = await Task.detached(priority: .utility) {
                (
                    iOSDeviceDataAnalyzer.scanAuthorizedSummary(
                        stagedItems: staged,
                        knownRemindersCount: remCount,
                        includePairedLiveVideoBytes: true,
                        allowCloudOnly: allowCloud
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
        let allowCloud = mediaFilters.includeICloudOnlyMedia
        Task {
            let (summary, precheck) = await Task.detached(priority: .utility) {
                (
                    iOSDeviceDataAnalyzer.scanAuthorizedSummary(
                        stagedItems: staged,
                        includePairedLiveVideoBytes: true,
                        allowCloudOnly: allowCloud
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
    @ObservedObject var l10n = DirectSwitchLocalizationStore.shared
    let resumableCheckpoint: TransferCheckpointRecord?
    var onResumeCheckpoint: (TransferCheckpointRecord) -> Void
    var onDismissCheckpoint: () -> Void
    let completedDeltaRecord: CompletedMigrationRecord?
    var onStartDeltaSync: (CompletedMigrationRecord) -> Void
    var onDismissDelta: () -> Void
    var onStartReceive: () -> Void
    var onStartSendToIPhone: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                HStack {
                    Spacer()
                    LanguageSelectorPill()
                }
                .padding(.top, 8)

                // Hero centrale con icona ingrandita (88pt) e sottotitolo racchiuso nel pulsante ⓘ
                VStack(spacing: 12) {
                    DirectSwitchAppleEmblem(size: 88)
                        .padding(.top, 4)
                        .padding(.bottom, 4)

                    HStack(spacing: 6) {
                        Text("DirectSwitch")
                            .font(.system(size: 29, weight: .bold))
                            .foregroundColor(AppleTheme.textPrimary)
                        InfoCircleButton(
                            title: "DirectSwitch",
                            message: l10n.tr(
                                "Copia i tuoi dati senza formattare: trasferisce rubrica, foto con album, video originali, calendari, audio, file e chat WhatsApp direttamente tra due telefoni già configurati, via Wi-Fi locale o Wi-Fi P2P senza passare dal cloud.",
                                en: "Copy your data without resetting: transfers contacts, photos with albums, original videos, calendars, audio, files, and WhatsApp chats directly between two configured phones via local Wi-Fi or P2P Wi-Fi without cloud.",
                                fr: "Copiez vos données sans réinitialiser : transfère contacts, photos avec albums, vidéos originales, calendriers, audio, fichiers et discussions WhatsApp directement entre deux téléphones configurés, en Wi-Fi local ou P2P sans passer par le cloud."
                            )
                        )
                    }
                }
                .padding(.bottom, 6)

                if let cp = resumableCheckpoint {
                    ResumableCheckpointCard(
                        checkpoint: cp,
                        onResume: { onResumeCheckpoint(cp) },
                        onDismiss: onDismissCheckpoint
                    )
                } else if let deltaRec = completedDeltaRecord {
                    DeltaCatchUpCard(
                        record: deltaRec,
                        onStartDeltaSync: { onStartDeltaSync(deltaRec) },
                        onDismiss: onDismissDelta
                    )
                }

                // Sezione 1 (SOPRA): Invia (freccia verso destra ->, sottotitolo dentro ⓘ, pulsante unico "Invia")
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        AppleSettingsIcon(systemName: "arrow.right", color: AppleTheme.blue)
                        Text(l10n.tr("Invia"))
                            .font(.system(size: 19, weight: .bold))
                            .foregroundColor(AppleTheme.textPrimary)
                        Spacer()
                        InfoCircleButton(
                            title: "Invia",
                            message: "Invia i dati da questo telefono direttamente senza cavo all'altro telefono (iPhone o Android) dove hai aperto 'Ricevi', tutto gratuito e senza formattare."
                        )
                    }

                    ApplePrimaryButton(
                        title: l10n.tr("Invia"),
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
                        Text(l10n.tr("Ricevi"))
                            .font(.system(size: 19, weight: .bold))
                            .foregroundColor(AppleTheme.textPrimary)
                        Spacer()
                        InfoCircleButton(
                            title: "Ricevi",
                            message: "Mostra il codice monouso a 6 cifre (come 'Passa a iOS') o il codice QR per ricevere i dati dal tuo altro iPhone o Android senza cancellare nulla."
                        )
                    }

                    ApplePrimaryButton(
                        title: l10n.tr("Ricevi"),
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
    @ObservedObject var l10n = DirectSwitchLocalizationStore.shared
    let isReceiverMode: Bool
    let isProUnlocked: Bool
    let canSendAnotherCategory: Bool
    var onOpenProSheet: () -> Void
    var onRetryIfFailed: () -> Void
    var onRetrySkippedOnly: ([String]) -> Void
    var onApplySpaceRelief: (SpaceReliefActionKind) -> Void
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
        let alreadyWord = l10n.tr("già presenti", en: "already present", fr: "déjà présents")
        if imported == 0 && alreadyPresent > 0 {
            return "0 (\(alreadyPresent) \(alreadyWord))"
        }
        if alreadyPresent > 0 {
            return "\(imported) (+\(alreadyPresent) \(alreadyWord))"
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

        if scope.photos || scope.videos || scope.documents || scope.audio || (scope.whatsApp && transport.totalItems > 0) {
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
                    title: isReceiverMode
                        ? l10n.tr(
                            "Messaggi salvati (in File)",
                            en: "Messages saved (in Files)",
                            fr: "Messages enregistrés (dans Fichiers)"
                        )
                        : "Messaggi salvati",
                    value: "\(transport.importedSms)"
                )
            )
        }

        if transport.importedCallLogs > 0 {
            rows.append(
                ScopedSummaryItem(
                    id: "call_logs",
                    icon: "phone.fill",
                    color: AppleTheme.teal,
                    title: isReceiverMode
                        ? l10n.tr(
                            "Cronologia chiamate (in File)",
                            en: "Call history (in Files)",
                            fr: "Historique d'appels (dans Fichiers)"
                        )
                        : "Cronologia chiamate salvata",
                    value: "\(transport.importedCallLogs)"
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
        return l10n.translateEta(transport.etaLabel)
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

                            Text(l10n.tr("Trasferimento completato"))
                                .font(.system(size: 24, weight: .bold))
                                .foregroundColor(AppleTheme.textPrimary)

                            Text(isReceiverMode
                                 ? l10n.tr("Le voci selezionate sono pronte su questo iPhone")
                                 : l10n.tr(
                                     "Le voci selezionate sono state copiate su \(transport.peerName.isEmpty ? "il nuovo telefono" : transport.peerName)",
                                     en: "Selected items were copied to \(transport.peerName.isEmpty ? "the new phone" : transport.peerName)",
                                     fr: "Les éléments sélectionnés ont été copiés sur \(transport.peerName.isEmpty ? "le nouveau téléphone" : transport.peerName)"
                                 ))
                                .font(.system(size: 14))
                                .foregroundColor(AppleTheme.textSecondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 12)
                        }
                    } else {
                        DirectSwitchAppleEmblem(size: 68)
                            .padding(.top, 14)

                        if transport.errorMessage != nil {
                            Text(l10n.tr("Trasferimento in pausa (\(percentageInt)%)", en: "Transfer paused (\(percentageInt)%)", fr: "Transfert en pause (\(percentageInt)%)"))
                                .font(.system(size: 23, weight: .bold))
                                .foregroundColor(AppleTheme.textPrimary)

                            Text(l10n.tr("I file già copiati sono al sicuro e non verranno duplicati"))
                                .font(.system(size: 14))
                                .foregroundColor(AppleTheme.textSecondary)
                                .multilineTextAlignment(.center)
                        } else {
                            Text(isReceiverMode ? l10n.tr("Copia su questo iPhone...") : l10n.tr("Copia delle voci selezionate..."))
                                .font(.system(size: 23, weight: .bold))
                                .foregroundColor(AppleTheme.textPrimary)

                            Text(l10n.tr("Tieni entrambi i telefoni vicini fino al termine"))
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

                    HStack(spacing: 8) {
                        ConnectionMediumPill(medium: transport.connectionMedium)
                        if transport.batteryTriageActive {
                            BatteryTriageActivePill()
                        }
                        if transport.thermalGuardState != .normal {
                            ThermalGuardBannerPill(
                                state: transport.thermalGuardState,
                                bannerText: transport.thermalBanner
                            )
                        }
                        Spacer()
                    }
                    .padding(.top, 2)
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

                if !isReceiverMode, let offer = transport.spaceReliefOffer {
                    SpaceReliefAssistantCard(offer: offer) { action in
                        onApplySpaceRelief(action)
                    }
                }

                if !transport.skippedItems.isEmpty {
                    SkippedItemsReportCard(
                        items: transport.skippedItems,
                        canRetry: !isReceiverMode && !transport.isTransferring,
                        onRetrySkippedOnly: {
                            onRetrySkippedOnly(transport.skippedItems.map(\.id))
                        }
                    )
                } else if !isReceiverMode && transport.isCompleted && transport.canResumeInterruptedTransfer && transport.failedItemsCount > 0 {
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
                                title: l10n.tr("Apri Impostazioni DirectSwitch"),
                                icon: "gearshape.fill",
                                tint: AppleTheme.orange
                            ) {
                                DirectSwitchTransportViewModel.openAppSettings()
                            }
                        }
                        if !isReceiverMode {
                            ApplePrimaryButton(
                                title: transport.canResumeInterruptedTransfer
                                    ? l10n.tr("Riprendi trasferimento da dove era rimasto")
                                    : l10n.tr("Riprova copia"),
                                icon: "arrow.clockwise",
                                color: AppleTheme.blue,
                                action: onRetryIfFailed
                            )
                            if transport.canResumeInterruptedTransfer {
                                AppleSecondaryButton(
                                    title: l10n.tr("Ricollega con nuovo codice / QR (salta già copiati)"),
                                    icon: "qrcode",
                                    tint: AppleTheme.teal,
                                    action: onReconnectNewCode
                                )
                            }
                        }
                    }
                    .appleCard(padding: 14)
                }

                if !isReceiverMode, transport.errorMessage != nil, let diag = transport.networkDiagnostic {
                    NetworkIsolationHotspotCard(verdict: diag, showRetryButton: false, onRetry: onRetryIfFailed)
                }

                if transport.isCompleted {
                    if !isReceiverMode &&
                        (transport.reconciliationVerifiedCount > 0 ||
                            !transport.reconciliationMissingIds.isEmpty ||
                            transport.heicConvertedCount > 0 ||
                            transport.smartCleanMergedContactsCount > 0 ||
                            transport.smartCleanSkippedDuplicatesCount > 0 ||
                            transport.smartCleanSkippedScreenshotsCount > 0) {
                        PostTransferReconciliationCard(
                            verifiedCount: transport.reconciliationVerifiedCount,
                            missingIds: transport.reconciliationMissingIds,
                            failedCount: transport.failedItemsCount,
                            heicConvertedCount: transport.heicConvertedCount,
                            smartCleanMergedContacts: transport.smartCleanMergedContactsCount,
                            smartCleanSkippedDuplicates: transport.smartCleanSkippedDuplicatesCount,
                            smartCleanSkippedScreenshots: transport.smartCleanSkippedScreenshotsCount,
                            onRepairMissing: { missingIds in
                                onRetrySkippedOnly(missingIds)
                            }
                        )
                    }

                    if canSendAnotherCategory {
                        AppleSecondaryButton(
                            title: l10n.tr("Trasferisci un'altra voce a questo telefono"),
                            icon: "arrow.uturn.backward.circle.fill",
                            tint: AppleTheme.blue,
                            action: onTransferAnotherCategory
                        )
                    }
                    ApplePrimaryButton(
                        title: l10n.tr("Fine"),
                        icon: "checkmark",
                        color: AppleTheme.blue,
                        action: onFinish
                    )
                } else if transport.errorMessage != nil {
                    if canSendAnotherCategory {
                        AppleSecondaryButton(
                            title: l10n.tr("Torna alla scelta delle voci"),
                            icon: "arrow.uturn.backward",
                            tint: AppleTheme.blue,
                            action: onTransferAnotherCategory
                        )
                    }
                    AppleSecondaryButton(
                        title: l10n.tr("Torna alla Home"),
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
            Text(l10n.tr(title))
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
