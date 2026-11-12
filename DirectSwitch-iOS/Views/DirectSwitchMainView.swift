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
    case sendConnect
    case sendSelectCategories
    case transferProgress
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

    // Categorie di trasferimento (stile Passa a iOS / Passa a Android)
    @State private var includeContacts: Bool = true
    @State private var includePhotos: Bool = true
    @State private var includeVideos: Bool = true
    @State private var includeCalendars: Bool = true
    @State private var includeReminders: Bool = true
    @State private var includeDocuments: Bool = true
    @State private var includeApps: Bool = true
    @State private var includeWhatsApp: Bool = true

    // Catalogo App rilevate sull'iPhone che invia + Passo 1 Fotocamera Live / Screenshot Home
    @State private var senderAppsCatalog: [InstalledAppRecord] = []
    @State private var deselectedSenderAppIds: Set<String> = []
    @State private var showSenderAppsSheet: Bool = false
    @State private var showAutoAppCaptureGuideSheet: Bool = false
    @State private var isRemoteAppScannerActiveOnPeer: Bool = false
    @State private var isStartingRemoteAppScanner: Bool = false
    @State private var remoteScannerPollTask: Task<Void, Never>? = nil
    @State private var isAwaitingAutoAppCapture: Bool = false
    @State private var autoCaptureArmedAt: Date? = nil
    @State private var isExtractingAutoAppScreenshots: Bool = false
    @State private var hasCompletedAutoAppCapture: Bool = !iOSInstalledAppsScanner.loadSavedCustomApps().isEmpty
    @State private var autoAppCaptureStatusNote: String? = nil
    @State private var lastTemporaryCapturedAssetIds: [String] = []

    private var selectedSenderApps: [InstalledAppRecord] {
        senderAppsCatalog.filter { !deselectedSenderAppIds.contains($0.id) }
    }

    // File e archivi WhatsApp allegati
    @State private var showDocumentImporter: Bool = false
    @State private var pickedDocuments: [(ManifestItem, URL)] = []
    @State private var sharedVaultToast: String? = nil

    // Scansione locale e StoreKit Pass iPhone <-> Android
    @State private var scanSummary: iOSLocalDeviceScanSummary? = nil
    @State private var isScanningDevice: Bool = false
    @State private var isProUnlocked: Bool = iOSLicenseStore.isLocalProUnlocked
    @State private var showProSheet: Bool = false
    @State private var billingNote: String? = nil

    private var isDedicatedWhatsAppScreenActive: Bool {
        guard activeStep == .transferProgress, transport.errorMessage == nil else { return false }
        if transport.activeTransferScope.isWhatsAppOnly && transport.totalItems == 0 {
            return true
        }
        return transport.isCompleted && transport.pendingNativeWhatsAppMigration
    }

    private var topBarTitle: String {
        switch activeStep {
        case .home:
            return "DirectSwitch"
        case .receiveWaitCode:
            return "Ricevi"
        case .sendConnect:
            return "Invia"
        case .sendSelectCategories:
            return "Cosa inviare"
        case .transferProgress:
            if isDedicatedWhatsAppScreenActive {
                return "Chat WhatsApp"
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
                        isProUnlocked: isProUnlocked,
                        onBack: handleBackNavigation,
                        onTapPassBadge: { showProSheet = true }
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
                                    preScannedAppsCount: transport.remoteScannedApps.count,
                                    onOpenLiveAppScanner: {
                                        transport.showRemoteAppScannerOnReceiver = true
                                    },
                                    onOpenAppSettings: {
                                        DirectSwitchTransportViewModel.openAppSettings()
                                    },
                                    onCancel: {
                                        transport.resetSession()
                                        receiverQrPayload = nil
                                        withAnimation(.easeInOut(duration: 0.2)) {
                                            activeStep = .home
                                        }
                                    }
                                )
                            }

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
                                    isScanningDevice: isScanningDevice,
                                    isLocalProUnlocked: isProUnlocked,
                                    pickedDocuments: pickedDocuments,
                                    selectedAppsCount: selectedSenderApps.count,
                                    totalDetectedAppsCount: senderAppsCatalog.count,
                                    selectedAppsPreview: selectedSenderApps,
                                    isRemoteAppScannerActiveOnPeer: isRemoteAppScannerActiveOnPeer,
                                    isStartingRemoteAppScanner: isStartingRemoteAppScanner,
                                    isAwaitingAutoAppCapture: isAwaitingAutoAppCapture,
                                    isExtractingAutoAppScreenshots: isExtractingAutoAppScreenshots,
                                    hasCompletedAutoAppCapture: hasCompletedAutoAppCapture,
                                    autoAppCaptureStatusNote: autoAppCaptureStatusNote,
                                    canDeleteTempAutoRecording: !lastTemporaryCapturedAssetIds.isEmpty,
                                    includeContacts: $includeContacts,
                                    includePhotos: $includePhotos,
                                    includeVideos: $includeVideos,
                                    includeCalendars: $includeCalendars,
                                    includeReminders: $includeReminders,
                                    includeDocuments: $includeDocuments,
                                    includeApps: $includeApps,
                                    includeWhatsApp: $includeWhatsApp,
                                    onScanExactCounts: scanExactDeviceCounts,
                                    onStartRemoteCameraAppScan: startRemoteScannerOnPairedIPhone,
                                    onRefreshRemoteCameraAppScanNow: {
                                        refreshRemoteScannerOnce()
                                    },
                                    onStartAutoAppCapture: armAndPresentAutoAppCapture,
                                    onExtractRecentAutoCaptureNow: {
                                        runAutomaticAppScreenshotExtraction(fromForegroundReturn: false)
                                    },
                                    onDeleteTempAutoRecording: deleteTemporaryAutoRecording,
                                    onManageApps: { showSenderAppsSheet = true },
                                    onAddFilesOrWhatsApp: { showDocumentImporter = true },
                                    onClearStagedFiles: {
                                        pickedDocuments.removeAll()
                                        iOSDocumentsSandboxBridge.clearStagedVault()
                                        refreshAuthorizedSummary()
                                    },
                                    onOpenProSheet: { showProSheet = true },
                                    onChangePairedDevice: {
                                        stopRemoteScannerPolling()
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

                        case .transferProgress:
                            DirectSwitchTransferProgressView(
                                transport: transport,
                                appInstaller: appInstaller,
                                isReceiverMode: isReceiverMode,
                                isProUnlocked: isProUnlocked,
                                canSendAnotherCategory: !isReceiverMode && pairedTargetPayload != nil,
                                onOpenProSheet: { showProSheet = true },
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
            isProUnlocked = await iOSLicenseStore.restoreStoreKitEntitlements()
            refreshAuthorizedSummary()
            refreshSenderAppsCatalog()
        }
        .onChange(of: transport.isSessionConnected) { connected in
            if connected && activeStep == .receiveWaitCode {
                appInstaller.reset()
                withAnimation(.easeInOut(duration: 0.25)) {
                    activeStep = .transferProgress
                }
            }
        }
        .onChange(of: includeApps) { enabled in
            if enabled {
                deselectedSenderAppIds.removeAll()
                refreshSenderAppsCatalog()
            }
        }
        .onChange(of: scenePhase) { newPhase in
            if newPhase == .active {
                refreshAuthorizedSummary()
                refreshSenderAppsCatalog()
                appInstaller.handleSceneBecameActive()
                if isRemoteAppScannerActiveOnPeer {
                    refreshRemoteScannerOnce()
                }
                if isAwaitingAutoAppCapture && !isExtractingAutoAppScreenshots {
                    runAutomaticAppScreenshotExtraction(fromForegroundReturn: true)
                }
                receiverDeniedSummary = iOSPermissionsHelper.receiverDeniedSummaryText()
                if activeStep == .sendConnect {
                    transport.startUdpAutoDiscovery()
                }
            }
        }
        .onOpenURL { incomingURL in
            handleIncomingURL(incomingURL)
        }
        .fileImporter(
            isPresented: $showDocumentImporter,
            allowedContentTypes: [.item, .folder],
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result {
                let imported = iOSDocumentsSandboxBridge.importPickedDocumentURLs(urls)
                pickedDocuments.append(contentsOf: imported)
                refreshAuthorizedSummary()
            }
        }
        .sheet(isPresented: $showSenderAppsSheet) {
            SenderAppsSelectionSheet(
                appsCatalog: $senderAppsCatalog,
                deselectedAppIds: $deselectedSenderAppIds,
                canScanWithPairedIPhone: pairedTargetPayload?.receiverPlatform == .IOS,
                pairedIPhoneName: pairedTargetPayload?.receiverName ?? "",
                onTriggerPairedIPhoneScanner: startRemoteScannerOnPairedIPhone,
                onStartGuidedAutoCapture: armAndPresentAutoAppCapture
            )
        }
        .sheet(isPresented: $showAutoAppCaptureGuideSheet) {
            AutoAppScrollCaptureGuideSheet(
                canUsePairedNewIPhoneCamera: pairedTargetPayload?.receiverPlatform == .IOS,
                pairedNewIPhoneName: pairedTargetPayload?.receiverName ?? "",
                onOpenScannerOnNewIPhone: startRemoteScannerOnPairedIPhone,
                onArmHomeScreenshotsCapture: armLocalHomeScreenshotsCapture
            )
        }
        .sheet(isPresented: $transport.showRemoteAppScannerOnReceiver) {
            LiveCameraAppScannerSheet(
                seedApps: transport.remoteScannedApps,
                senderPhoneLabel: transport.remoteScannerPeerName,
                onLiveAppsUpdated: { liveApps in
                    transport.updateReceiverScannedApps(liveApps, replaceExisting: true, completed: false)
                },
                onConfirmApps: { confirmedApps in
                    transport.updateReceiverScannedApps(confirmedApps, replaceExisting: true, completed: true)
                }
            )
        }
        .sheet(isPresented: $showProSheet) {
            DirectSwitchProPassSheet(
                isProUnlocked: $isProUnlocked,
                billingNote: $billingNote,
                onClose: { showProSheet = false }
            )
        }
    }

    // MARK: - Azioni di navigazione e flusso guidato

    private func startReceiveWizard() {
        isReceiverMode = true
        pairingErrorNote = nil
        receiverQrPayload = transport.startReceiverServer()
        receiverDeniedSummary = iOSPermissionsHelper.receiverDeniedSummaryText()
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
        } catch {
            pairingErrorNote = "Codice QR non riconosciuto. Assicurati di inquadrare il QR mostrato da DirectSwitch sul nuovo telefono."
        }
    }

    private func launchSenderTransfer() {
        guard let paired = pairedTargetPayload else { return }
        launchSenderTransferWithPayload(paired, isResume: false)
    }

    private func launchSenderTransferWithPayload(_ paired: QrPairingPayload, isResume: Bool) {
        stopRemoteScannerPolling()
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
            activeStep = .transferProgress
        }
        let docsSnapshot = pickedDocuments
        let appsSnapshot = includeApps ? selectedSenderApps : []
        Task {
            await transport.executeSenderTransfer(
                qrPayload: paired,
                includeContacts: includeContacts,
                includePhotos: includePhotos,
                includeVideos: includeVideos,
                includeCalendars: includeCalendars,
                includeReminders: includeReminders,
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
        guard pairedTargetPayload != nil else {
            finishAndReturnHome()
            return
        }
        appInstaller.reset()
        transport.errorMessage = nil
        transport.isCompleted = false
        transport.pendingNativeWhatsAppMigration = false
        transport.visualStepProgress = 0.0
        withAnimation(.easeInOut(duration: 0.22)) {
            activeStep = .sendSelectCategories
        }
    }

    private func refreshSenderAppsCatalog() {
        let detected = iOSInstalledAppsScanner.scanLocallyInstalledApps()
        if senderAppsCatalog.isEmpty {
            senderAppsCatalog = detected
        } else {
            var merged = senderAppsCatalog
            for app in detected {
                let exists = merged.contains {
                    $0.packageName.caseInsensitiveCompare(app.packageName) == .orderedSame
                        || ($0.appStoreId != nil && $0.appStoreId == app.appStoreId)
                }
                if !exists {
                    merged.append(app)
                }
            }
            senderAppsCatalog = merged
        }
        let snapshot = senderAppsCatalog
        Task {
            let enriched = await iOSAppStoreCatalogResolver.enrichAppsWithStoreMetadata(snapshot)
            if !enriched.isEmpty {
                self.senderAppsCatalog = enriched
            }
        }
    }

    private func armLocalHomeScreenshotsCapture() {
        stopRemoteScannerPolling()
        autoCaptureArmedAt = Date()
        isAwaitingAutoAppCapture = true
        autoAppCaptureStatusNote = nil
    }

    private func armAndPresentAutoAppCapture() {
        armLocalHomeScreenshotsCapture()
        showAutoAppCaptureGuideSheet = true
    }

    private func startRemoteScannerOnPairedIPhone() {
        guard let paired = pairedTargetPayload,
              paired.receiverPlatform == .IOS,
              !isStartingRemoteAppScanner else { return }

        stopRemoteScannerPolling()
        isAwaitingAutoAppCapture = false
        isStartingRemoteAppScanner = true
        autoAppCaptureStatusNote = nil

        let seedSnapshot = senderAppsCatalog
        Task {
            do {
                let status = try await transport.requestRemoteAppScannerStart(
                    pairedPayload: paired,
                    seedApps: seedSnapshot
                )
                isStartingRemoteAppScanner = false
                isRemoteAppScannerActiveOnPeer = status.isScannerOpen
                mergeIncomingRemoteScannedApps(
                    status.discoveredApps,
                    peerName: paired.receiverName,
                    scannerClosed: !status.isScannerOpen || status.isCompleted
                )
                if status.isScannerOpen && !status.isCompleted {
                    beginRemoteScannerPollingLoop(for: paired)
                }
            } catch {
                isStartingRemoteAppScanner = false
                isRemoteAppScannerActiveOnPeer = false
                autoAppCaptureStatusNote = "⚠ \(error.localizedDescription)"
            }
        }
    }

    private func beginRemoteScannerPollingLoop(for paired: QrPairingPayload) {
        remoteScannerPollTask?.cancel()
        remoteScannerPollTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_200_000_000)
                if Task.isCancelled { break }
                do {
                    let status = try await transport.pollRemoteAppScannerStatus(pairedPayload: paired)
                    let closed = !status.isScannerOpen || status.isCompleted
                    mergeIncomingRemoteScannedApps(
                        status.discoveredApps,
                        peerName: paired.receiverName,
                        scannerClosed: closed
                    )
                    if closed {
                        isRemoteAppScannerActiveOnPeer = false
                        break
                    }
                } catch {
                    // Continua in silenzio anche se questo iPhone è passato sulla schermata Home per qualche secondo
                }
            }
        }
    }

    private func refreshRemoteScannerOnce() {
        guard let paired = pairedTargetPayload, paired.receiverPlatform == .IOS else { return }
        Task {
            if let status = try? await transport.pollRemoteAppScannerStatus(pairedPayload: paired) {
                let closed = !status.isScannerOpen || status.isCompleted
                mergeIncomingRemoteScannedApps(
                    status.discoveredApps,
                    peerName: paired.receiverName,
                    scannerClosed: closed
                )
                if closed {
                    stopRemoteScannerPolling()
                }
            }
        }
    }

    private func stopRemoteScannerPolling() {
        remoteScannerPollTask?.cancel()
        remoteScannerPollTask = nil
        isRemoteAppScannerActiveOnPeer = false
        isStartingRemoteAppScanner = false
    }

    private func mergeIncomingRemoteScannedApps(
        _ incoming: [InstalledAppRecord],
        peerName: String,
        scannerClosed: Bool
    ) {
        guard !incoming.isEmpty else { return }
        var newlyAdded = 0
        for app in incoming {
            let exists = senderAppsCatalog.contains {
                $0.packageName.caseInsensitiveCompare(app.packageName) == .orderedSame
                    || ($0.appStoreId != nil && $0.appStoreId == app.appStoreId)
            }
            if !exists {
                senderAppsCatalog.append(app)
                newlyAdded += 1
            }
            deselectedSenderAppIds.remove(app.id)
        }

        if newlyAdded > 0 {
            iOSInstalledAppsScanner.appendCustomApps(incoming)
            hasCompletedAutoAppCapture = true
            autoAppCaptureStatusNote = "✓ \(senderAppsCatalog.count) App selezionate in tempo reale con \(peerName)!"
        } else if scannerClosed && !senderAppsCatalog.isEmpty {
            hasCompletedAutoAppCapture = true
            autoAppCaptureStatusNote = "✓ Scansione completata su \(peerName): \(senderAppsCatalog.count) App pronte!"
        }
    }

    private func runAutomaticAppScreenshotExtraction(fromForegroundReturn: Bool) {
        guard !isExtractingAutoAppScreenshots else { return }
        isExtractingAutoAppScreenshots = true
        autoAppCaptureStatusNote = nil
        let armedSince = fromForegroundReturn ? autoCaptureArmedAt : nil

        Task {
            var result = await iOSInstalledAppsScanner.extractAutomaticScreenshotsAndRecognizeApps(since: armedSince)

            if fromForegroundReturn && result.generatedScreenshotsCount == 0 {
                try? await Task.sleep(nanoseconds: 1_200_000_000)
                result = await iOSInstalledAppsScanner.extractAutomaticScreenshotsAndRecognizeApps(since: armedSince)
            }

            isExtractingAutoAppScreenshots = false

            guard result.generatedScreenshotsCount > 0 else {
                if !fromForegroundReturn {
                    autoAppCaptureStatusNote = "⚠ Nessuno screenshot recente delle pagine Home trovato. Vai sulla Home, fai uno screenshot alle pagine delle tue App e riprova!"
                }
                return
            }

            isAwaitingAutoAppCapture = false
            lastTemporaryCapturedAssetIds = result.allTemporaryAssetIdentifiers

            var newlyAdded = 0
            for app in result.discoveredApps {
                let exists = senderAppsCatalog.contains {
                    $0.packageName.caseInsensitiveCompare(app.packageName) == .orderedSame
                        || ($0.appStoreId != nil && $0.appStoreId == app.appStoreId)
                }
                if !exists {
                    senderAppsCatalog.append(app)
                    newlyAdded += 1
                }
                deselectedSenderAppIds.remove(app.id)
            }

            if !result.discoveredApps.isEmpty {
                iOSInstalledAppsScanner.appendCustomApps(result.discoveredApps)
                hasCompletedAutoAppCapture = true
            }

            if newlyAdded > 0 {
                autoAppCaptureStatusNote = "✓ Letti \(result.generatedScreenshotsCount) screenshot Home: +\(newlyAdded) app aggiunte (\(senderAppsCatalog.count) selezionate)!"
            } else if !result.discoveredApps.isEmpty {
                hasCompletedAutoAppCapture = true
                autoAppCaptureStatusNote = "✓ Analizzati \(result.generatedScreenshotsCount) screenshot Home: tutte le \(senderAppsCatalog.count) app sono selezionate!"
            } else {
                autoAppCaptureStatusNote = "⚠ Analizzati \(result.generatedScreenshotsCount) screenshot: nessuna nuova app rilevata."
            }
        }
    }

    private func deleteTemporaryAutoRecording() {
        let ids = lastTemporaryCapturedAssetIds
        guard !ids.isEmpty else { return }
        Task {
            if await iOSInstalledAppsScanner.deleteTemporaryCapturedAssets(localIdentifiers: ids) {
                lastTemporaryCapturedAssetIds.removeAll()
            }
        }
    }

    private func scanExactDeviceCounts() {
        isScanningDevice = true
        let staged = pickedDocuments.map(\.0)
        Task {
            scanSummary = await iOSDeviceDataAnalyzer.requestPermissionsAndScanAll(stagedItems: staged)
            isScanningDevice = false
        }
    }

    private func refreshAuthorizedSummary() {
        let staged = pickedDocuments.map(\.0)
        Task {
            let summary = await Task.detached(priority: .utility) {
                iOSDeviceDataAnalyzer.scanAuthorizedSummary(stagedItems: staged)
            }.value
            scanSummary = summary
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
        case .receiveWaitCode:
            finishAndReturnHome()
        case .sendConnect:
            showCameraScanner = false
            transport.stopUdpAutoDiscovery()
            withAnimation(.easeInOut(duration: 0.2)) {
                activeStep = .home
            }
        case .sendSelectCategories:
            stopRemoteScannerPolling()
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
        stopRemoteScannerPolling()
        showCameraScanner = false
        receiverQrPayload = nil
        pairedTargetPayload = nil
        selectedBeacon = nil
        pinCodeInput = ""
        pairingErrorNote = nil
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
                            message: "Invia i dati da questo telefono direttamente senza cavo all'altro telefono dove hai aperto 'Ricevi'. Con Premium Direct trasferisci tutto anche tra iPhone e Android già configurati, senza formattare."
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
        if scope.isWhatsAppOnly && transport.totalItems == 0 {
            return true
        }
        return transport.isCompleted && transport.pendingNativeWhatsAppMigration
    }

    private var progressFraction: Double {
        if transport.isCompleted { return 1.0 }
        if transport.totalBytesCount > 0 {
            guard transport.transferredBytesCount > 0 else { return 0.0 }
            return min(1.0, max(0.01, Double(transport.transferredBytesCount) / Double(transport.totalBytesCount)))
        }
        if transport.totalItems > 0 {
            guard transport.completedItems > 0 else { return 0.0 }
            return min(1.0, max(0.01, Double(transport.completedItems) / Double(transport.totalItems)))
        }
        return min(0.99, max(0.0, transport.visualStepProgress))
    }

    private var contactsSummaryValue: String {
        if transport.mergedContacts == 0 && transport.contactsAlreadyPresentCount > 0 {
            return "0 (\(transport.contactsAlreadyPresentCount) già presenti)"
        }
        return "\(transport.mergedContacts)"
    }

    private var percentageInt: Int {
        Int((progressFraction * 100.0).rounded())
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
                    value: "\(transport.importedCalendars)"
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
                    value: "\(transport.importedReminders)"
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
                    title: isReceiverMode ? "App ricevute" : "App inviate al nuovo telefono",
                    value: "\(countVal)"
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
                    title: "Foto iCloud non scaricate / illeggibili",
                    value: "\(transport.failedItemsCount)"
                )
            )
        }

        return rows
    }

    private var remainingTimeLabel: String? {
        guard !transport.isCompleted,
              transport.speedMegabytesPerSec > 0.15,
              transport.totalBytesCount > transport.transferredBytesCount else {
            return nil
        }
        let remMB = Double(transport.totalBytesCount - transport.transferredBytesCount) / (1024.0 * 1024.0)
        let remSec = Int((remMB / transport.speedMegabytesPerSec).rounded())
        if remSec < 60 {
            return "Meno di un minuto rimanente"
        }
        let mins = max(1, remSec / 60)
        return "Circa \(mins) min rimanenti"
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
        let isPersonalInstalled = iOSInstalledAppsScanner.isPersonalWhatsAppInstalled()
        let isBusinessAlsoInstalled = iOSInstalledAppsScanner.isWhatsAppBusinessInstalled()

        let screenTitle: String = {
            if isToAndroid { return "Passaggio Chat su Android" }
            if !isReceiverMode { return "Passaggio Chat da questo iPhone" }
            if isFromAndroid { return "Importa Chat WhatsApp" }
            return "Passaggio Chat su questo iPhone"
        }()

        let screenSubtitle: String = {
            if !isReceiverMode && !isToAndroid {
                return "Inquadra il QR di WhatsApp del nuovo iPhone senza passare dalla Fotocamera di sistema"
            }
            if isReceiverMode && !isFromAndroid {
                return "Verifica il numero qui: il vecchio iPhone si scollegherà da solo e apparirà il codice QR"
            }
            return "Trasferimento diretto della cronologia chat senza cloud"
        }()

        let stepsList: [String] = {
            if isToAndroid {
                return [
                    "Sul telefono Android prosegui nella schermata aperta fino a visualizzare il codice QR.",
                    "Su questo iPhone tocca «Inquadra QR di WhatsApp» qui sotto (oppure apri WhatsApp Personale → Impostazioni ⚙️ → Chat → Trasferisci chat su Android) per avviare il passaggio."
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
                    "Tocca il pulsante verde qui sotto per aprire (o scaricare) WhatsApp Personale.",
                    "Inserisci il tuo numero e il codice SMS per completare l'importazione delle chat."
                ]
            }
            return [
                "Tocca il pulsante verde qui sotto per aprire (o scaricare da App Store) WhatsApp Personale su questo nuovo iPhone.",
                "Inserisci il numero e il codice SMS: WhatsApp scollegherà subito il vecchio iPhone (non c'è bisogno di riaprire nulla qui) e ti chiederà di iniziare il trasferimento mostrando il codice QR su questo schermo.",
                "Lascia il codice QR visibile qui e sul vecchio iPhone tocca «Inquadra QR di WhatsApp e avvia passaggio» direttamente dentro DirectSwitch!"
            ]
        }()

        ScrollView {
            VStack(spacing: 18) {
                if scope.hasAnyStandardDataCategory && transport.isCompleted {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(AppleTheme.green)
                        Text("Altre voci selezionate già copiate • Ora passa le Chat WhatsApp")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(AppleTheme.green)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(AppleTheme.green.opacity(0.12))
                    .clipShape(Capsule())
                    .padding(.top, 8)
                }

                VStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(AppleTheme.green.opacity(0.16))
                            .frame(width: 72, height: 72)
                        Image(systemName: !isReceiverMode ? "qrcode.viewfinder" : "bubble.left.and.bubble.right.fill")
                            .font(.system(size: 34, weight: .semibold))
                            .foregroundColor(AppleTheme.green)
                    }
                    .padding(.top, scope.hasAnyStandardDataCategory ? 4 : 16)

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

                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 10) {
                        AppleSettingsIcon(systemName: "bubble.left.and.bubble.right.fill", color: AppleTheme.green)
                        Text("Come procedere adesso")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(AppleTheme.textPrimary)
                        Spacer()
                        InfoCircleButton(
                            title: "Come funziona dopo la disconnessione del vecchio iPhone",
                            message: "Quando inserisci numero e SMS sul nuovo iPhone, WhatsApp disconnette subito il vecchio telefono (quindi sul vecchio non puoi più entrare in Impostazioni → Chat).\n\nIl codice QR mostrato sul nuovo iPhone contiene il link diretto di sblocco della schermata «Trasferisci la cronologia chat»: inquadrandolo con il pulsante qui sotto dentro DirectSwitch salti completamente la Fotocamera di iPhone e il bottone giallo!"
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
                        // Vecchio iPhone (Mittente): Scanner diretto del QR WhatsApp che salta la Fotocamera di iPhone e il bottone giallo
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

    // MARK: - Schermata Avanzamento Dati Selezionati (sempre da 0% -> 100%, mostra SOLO le voci scelte in questo trasferimento)

    private var standardDataTransferScreen: some View {
        ScrollView {
            VStack(spacing: 18) {
                VStack(spacing: 10) {
                    if transport.isCompleted {
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

                        if transport.isBackgroundKeepAliveActive {
                            HStack(spacing: 6) {
                                Image(systemName: "bolt.shield.fill")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(AppleTheme.teal)
                                Text("Protezione Background e Anti-Standby attiva")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(AppleTheme.teal)
                                InfoCircleButton(
                                    title: "Esecuzione in Background e Resume",
                                    message: "DirectSwitch mantiene lo schermo acceso e tiene vivo il trasferimento in background se passi brevemente a un'altra app o ricevi una chiamata.\n\nSe iOS dovesse sospendere il Wi-Fi dopo diversi minuti in background, riceverai una notifica e potrai riprendere esattamente dal file interrotto senza rifare il QR."
                                )
                            }
                            .padding(.horizontal, 11)
                            .padding(.vertical, 6)
                            .background(AppleTheme.teal.opacity(0.10))
                            .clipShape(Capsule())
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("\(percentageInt)%")
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                            .foregroundColor(transport.isCompleted ? AppleTheme.green : AppleTheme.textPrimary)

                        Spacer()

                        if transport.speedMegabytesPerSec > 0.05 && !transport.isCompleted {
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
                                .fill(transport.isCompleted ? AppleTheme.green : AppleTheme.blue)
                                .frame(width: max(12, geo.size.width * progressFraction), height: 10)
                                .animation(.easeInOut(duration: 0.25), value: progressFraction)
                        }
                    }
                    .frame(height: 10)

                    HStack {
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

                    if let eta = remainingTimeLabel {
                        Text(eta)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(AppleTheme.blue)
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

                if isReceiverMode && transport.isCompleted && ((scope.documents && transport.completedItems > 0) || transport.importedSms > 0) {
                    HStack(spacing: 10) {
                        Image(systemName: "folder.fill")
                            .foregroundColor(AppleTheme.blue)
                        Text("Documenti, cartelle «Su iPhone» e file ricevuti sono in **File → Su iPhone → DirectSwitch → DirectSwitch_Documenti**.")
                            .font(.system(size: 13))
                            .foregroundColor(AppleTheme.textSecondary)
                        Spacer()
                    }
                    .appleCard(padding: 14)
                }

                if transport.gatedPreviewCount > 0 && !isProUnlocked {
                    Button(action: onOpenProSheet) {
                        HStack(spacing: 10) {
                            AppleSettingsIcon(systemName: "crown.fill", color: AppleTheme.premiumAmber)
                            Text("Sblocca i restanti \(transport.gatedPreviewCount) file con Premium Direct")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(AppleTheme.premiumGold)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(AppleTheme.premiumGold)
                        }
                        .padding(14)
                        .background(AppleTheme.premiumSurface)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(AppleTheme.premiumBorder.opacity(0.65), lineWidth: 1.0)
                        )
                    }
                    .buttonStyle(.plain)
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
                    message: "1. Tocca il pulsante qui sotto per aprire Impostazioni.\n2. Vai in App → Password (oppure Safari → Importa) e seleziona il file .csv salvato in «Su iPhone → DirectSwitch → DirectSwitch_Documenti → Password_Esportate».\n3. Tutte le password verranno salvate nel Portachiavi locale con Face ID senza attivare iCloud!"
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

// MARK: - Sheet Premium Direct (Passaggio completo iPhone <-> Android senza formattare)

private struct DirectSwitchProPassSheet: View {
    @Binding var isProUnlocked: Bool
    @Binding var billingNote: String?
    var onClose: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            // Pill superiore che chiarisce subito iPhone <-> Android
            HStack(spacing: 5) {
                Image(systemName: "crown.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(AppleTheme.premiumAmber)
                Text("PASSAGGIO DIRETTO iPHONE ↔ ANDROID")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(0.4)
                    .foregroundColor(AppleTheme.premiumGold)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(AppleTheme.premiumSurface)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(AppleTheme.premiumBorder.opacity(0.65), lineWidth: 1.0)
            )
            .padding(.top, 6)

            DirectSwitchAppleEmblem(size: 64)

            VStack(spacing: 5) {
                HStack(spacing: 6) {
                    Text("Premium Direct")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(AppleTheme.textPrimary)
                    InfoCircleButton(
                        title: "Perché scegliere Premium Direct",
                        message: "Le app tradizionali ti costringono a formattare il telefono ai dati di fabbrica o a comprare costosi abbonamenti Cloud mensili per spostare i tuoi GB tra iPhone e Android.\n\nCon Premium Direct sposti tutto in Wi-Fi o Hotspot 5GHz diretto tra telefoni già configurati, alla massima velocità e senza perdere nessun dato già presente."
                    )
                }

                Text("Trasferisci tutto tra iPhone e Android senza resettare")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(AppleTheme.premiumGold)
                    .multilineTextAlignment(.center)
            }

            VStack(alignment: .leading, spacing: 11) {
                featureLine(
                    icon: "bolt.fill",
                    color: AppleTheme.premiumAmber,
                    text: "Da iPhone ad Android (e viceversa) senza cavi"
                )
                featureLine(
                    icon: "iphone",
                    color: AppleTheme.blue,
                    text: "Zero formattazione: funziona su telefoni già in uso"
                )
                featureLine(
                    icon: "photo.stack.fill",
                    color: AppleTheme.orange,
                    text: "Foto originali, Video 4K, Contatti e Chat WhatsApp"
                )
                featureLine(
                    icon: "checkmark.seal.fill",
                    color: AppleTheme.teal,
                    text: "Un solo acquisto sblocca entrambi i telefoni"
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .appleCard(padding: 14)

            Text("Pagamento unico • Nessun abbonamento mensile")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(AppleTheme.textSecondary)

            if let note = billingNote, !note.isEmpty {
                Text(note)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(AppleTheme.blue)
                    .multilineTextAlignment(.center)
            }

            ApplePrimaryButton(
                title: isProUnlocked ? "Premium Direct Attivo" : "Sblocca Premium Direct — 9,99 €",
                icon: isProUnlocked ? "checkmark.seal.fill" : "crown.fill",
                color: isProUnlocked ? AppleTheme.green : AppleTheme.premiumGold,
                isDisabled: isProUnlocked
            ) {
                Task {
                    let (ok, msg) = await iOSLicenseStore.purchaseCrossOsPass()
                    billingNote = msg
                    if ok {
                        isProUnlocked = true
                        onClose()
                    }
                }
            }

            HStack(spacing: 14) {
                Button("Ripristina acquisti") {
                    Task {
                        let restored = await iOSLicenseStore.restoreStoreKitEntitlements()
                        isProUnlocked = restored
                        billingNote = restored ? "Premium Direct attivo!" : "Nessun acquisto precedente trovato."
                    }
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(AppleTheme.blue)
                .buttonStyle(.plain)

                if isProUnlocked {
                    Text("•")
                        .foregroundColor(AppleTheme.textTertiary)

                    Button("Blocca (Test)") {
                        iOSLicenseStore.isLocalProUnlocked = false
                        isProUnlocked = false
                        billingNote = "Modalità Anteprima attivata (rubrica + 25 foto) per test."
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(AppleTheme.orange)
                    .buttonStyle(.plain)
                }

                Text("•")
                    .foregroundColor(AppleTheme.textTertiary)

                Button("Chiudi", action: onClose)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(AppleTheme.textSecondary)
                    .buttonStyle(.plain)
            }
            .padding(.top, 2)
        }
        .padding(20)
        .background(AppleTheme.backgroundGradient.ignoresSafeArea())
        .presentationDetents([.height(540), .large])
        .presentationDragIndicator(.visible)
        .preferredColorScheme(.light)
    }

    private func featureLine(icon: String, color: Color, text: String) -> some View {
        HStack(spacing: 11) {
            AppleSettingsIcon(systemName: icon, color: color, size: 28)
            Text(text)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(AppleTheme.textPrimary)
        }
    }
}
