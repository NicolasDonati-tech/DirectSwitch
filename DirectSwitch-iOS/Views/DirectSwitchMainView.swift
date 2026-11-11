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

    // Catalogo App rilevate sull'iPhone che invia
    @State private var senderAppsCatalog: [InstalledAppRecord] = []
    @State private var deselectedSenderAppIds: Set<String> = []
    @State private var showSenderAppsSheet: Bool = false

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
                                    includeContacts: $includeContacts,
                                    includePhotos: $includePhotos,
                                    includeVideos: $includeVideos,
                                    includeCalendars: $includeCalendars,
                                    includeReminders: $includeReminders,
                                    includeDocuments: $includeDocuments,
                                    includeApps: $includeApps,
                                    includeWhatsApp: $includeWhatsApp,
                                    onScanExactCounts: scanExactDeviceCounts,
                                    onManageApps: { showSenderAppsSheet = true },
                                    onAddFilesOrWhatsApp: { showDocumentImporter = true },
                                    onClearStagedFiles: {
                                        pickedDocuments.removeAll()
                                        iOSDocumentsSandboxBridge.clearStagedVault()
                                        refreshAuthorizedSummary()
                                    },
                                    onOpenProSheet: { showProSheet = true },
                                    onChangePairedDevice: {
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
                                onOpenProSheet: { showProSheet = true },
                                onRetryIfFailed: {
                                    if !isReceiverMode, let paired = pairedTargetPayload {
                                        launchSenderTransferWithPayload(paired)
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
                                onFinish: finishAndReturnHome
                            )
                        }
                    }
                }
            }
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
                withAnimation(.easeInOut(duration: 0.25)) {
                    activeStep = .transferProgress
                }
            }
        }
        .onChange(of: scenePhase) { newPhase in
            if newPhase == .active {
                refreshAuthorizedSummary()
                refreshSenderAppsCatalog()
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
                deselectedAppIds: $deselectedSenderAppIds
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
        launchSenderTransferWithPayload(paired)
    }

    private func launchSenderTransferWithPayload(_ paired: QrPairingPayload) {
        sharedVaultToast = nil
        isReceiverMode = false
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
                includeWhatsAppVault: includeWhatsApp,
                installedApps: appsSnapshot,
                pickedDocuments: docsSnapshot
            )
            if transport.isCompleted && transport.failedItemsCount == 0 {
                pickedDocuments.removeAll()
                refreshAuthorizedSummary()
            }
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
            pairedTargetPayload = nil
            pinCodeInput = ""
            pairingErrorNote = nil
            transport.startUdpAutoDiscovery()
            withAnimation(.easeInOut(duration: 0.2)) {
                activeStep = .sendConnect
            }
        case .transferProgress:
            finishAndReturnHome()
        }
    }

    private func finishAndReturnHome() {
        showCameraScanner = false
        receiverQrPayload = nil
        pairedTargetPayload = nil
        selectedBeacon = nil
        pinCodeInput = ""
        pairingErrorNote = nil
        appInstaller.stopSequence()
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
    var onOpenProSheet: () -> Void
    var onRetryIfFailed: () -> Void
    var onReconnectNewCode: () -> Void
    var onFinish: () -> Void

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
        return 0.0
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
                             ? "I tuoi dati sono pronti su questo iPhone"
                             : "Tutti i dati selezionati sono stati copiati su \(transport.peerName.isEmpty ? "il nuovo telefono" : transport.peerName)")
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
                            Text(isReceiverMode ? "Copia su questo iPhone..." : "Copia dei dati in corso...")
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

                VStack(spacing: 0) {
                    summaryRow(
                        icon: "person.crop.circle.fill",
                        color: AppleTheme.blue,
                        title: "Contatti uniti",
                        value: contactsSummaryValue
                    )
                    Divider().padding(.leading, 56)
                    summaryRow(
                        icon: "photo.on.rectangle.angled",
                        color: AppleTheme.orange,
                        title: "Foto, Video e File",
                        value: transport.totalItems > 0 ? "\(transport.completedItems) / \(transport.totalItems)" : "\(transport.completedItems)"
                    )

                    if transport.savedLivePhotos > 0 {
                        Divider().padding(.leading, 56)
                        summaryRow(
                            icon: "livephoto",
                            color: AppleTheme.orange,
                            title: "Live Photos animate",
                            value: "\(transport.savedLivePhotos)"
                        )
                    }

                    Divider().padding(.leading, 56)
                    summaryRow(
                        icon: "calendar",
                        color: AppleTheme.slate,
                        title: "Calendari importati",
                        value: "\(transport.importedCalendars)"
                    )

                    if transport.importedReminders > 0 || isReceiverMode {
                        Divider().padding(.leading, 56)
                        summaryRow(
                            icon: "checklist",
                            color: AppleTheme.blue,
                            title: "Promemoria importati",
                            value: "\(transport.importedReminders)"
                        )
                    }

                    if transport.importedSms > 0 {
                        Divider().padding(.leading, 56)
                        summaryRow(
                            icon: "message.fill",
                            color: AppleTheme.green,
                            title: "Messaggi salvati",
                            value: "\(transport.importedSms)"
                        )
                    }

                    if isReceiverMode && !transport.receivedInstalledApps.isEmpty {
                        Divider().padding(.leading, 56)
                        summaryRow(
                            icon: "square.grid.2x2.fill",
                            color: AppleTheme.blue,
                            title: "App trasferite",
                            value: "\(transport.receivedInstalledApps.count)"
                        )
                    }

                    if transport.skippedDuplicates > 0 {
                        Divider().padding(.leading, 56)
                        summaryRow(
                            icon: "sparkles",
                            color: AppleTheme.teal,
                            title: "Doppioni già presenti ignorati",
                            value: "\(transport.skippedDuplicates)"
                        )
                    }

                    if transport.failedItemsCount > 0 {
                        Divider().padding(.leading, 56)
                        summaryRow(
                            icon: "icloud.slash",
                            color: AppleTheme.orange,
                            title: "Foto iCloud non scaricate / illeggibili",
                            value: "\(transport.failedItemsCount)"
                        )
                    }
                }
                .appleCard(padding: 0)

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

                if transport.isCompleted && transport.pendingNativeWhatsAppMigration {
                    whatsAppWirelessMigrationCard
                }

                if isReceiverMode && transport.isCompleted && transport.receivedPasswordsCsvCount > 0 {
                    passwordsCsvImportHelperCard
                }

                if isReceiverMode && transport.isCompleted {
                    ReceiverAppsAutoInstallCard(
                        incomingApps: transport.receivedInstalledApps,
                        installer: appInstaller
                    )
                }

                if isReceiverMode && transport.isCompleted && (transport.importedSms > 0 || transport.completedItems > 0) {
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
                    ApplePrimaryButton(
                        title: "Fine",
                        icon: "checkmark",
                        color: AppleTheme.blue,
                        action: onFinish
                    )
                } else if transport.errorMessage != nil {
                    AppleSecondaryButton(
                        title: "Torna alla Home",
                        icon: "house",
                        tint: AppleTheme.slate,
                        action: onFinish
                    )
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 28)
        }
    }

    @ViewBuilder
    private var whatsAppWirelessMigrationCard: some View {
        let isToAndroid = !isReceiverMode && transport.peerPlatform == .ANDROID
        let isFromAndroid = isReceiverMode && transport.peerPlatform == .ANDROID
        let isPersonalInstalled = iOSInstalledAppsScanner.isPersonalWhatsAppInstalled()
        let isBusinessAlsoInstalled = iOSInstalledAppsScanner.isWhatsAppBusinessInstalled()

        let cardTitle: String = {
            if isToAndroid { return "Chat WhatsApp → Android" }
            if !isReceiverMode { return "Chat WhatsApp → Altro iPhone" }
            if isFromAndroid { return "Importa Chat WhatsApp" }
            return "Ricevi Chat WhatsApp senza iCloud"
        }()

        let stepsList: [String] = {
            if isToAndroid {
                return [
                    "Sul telefono Android prosegui nella schermata aperta fino al codice QR.",
                    "Tocca «Apri WhatsApp Personale» qui sotto.",
                    "Dentro WhatsApp vai in Impostazioni ⚙️ → Chat → Trasferisci chat su Android → Inizia per aprire la fotocamera interna di WhatsApp e inquadrare il QR."
                ]
            }
            if !isReceiverMode {
                return [
                    "Sull'altro iPhone apri WhatsApp Personale, verifica il numero SMS e tocca Continua su «Trasferisci la cronologia chat da iPhone» per mostrare il QR.",
                    "Su questo iPhone tocca «Apri WhatsApp Personale» qui sotto.",
                    "Dentro WhatsApp vai in Impostazioni ⚙️ → Chat → Trasferisci chat su iPhone → Inizia per aprire lo scanner interno di WhatsApp e inquadrare il QR."
                ]
            }
            if isFromAndroid {
                return [
                    "Tocca il pulsante verde qui sotto per aprire (o scaricare) WhatsApp Personale.",
                    "Inserisci il tuo numero di telefono e segui la procedura guidata per importare le chat."
                ]
            }
            return [
                "Tocca il pulsante verde qui sotto per aprire (o scaricare da App Store) WhatsApp Personale.",
                "Inserisci il tuo numero e il codice SMS: quando appare «Trasferisci la cronologia chat da iPhone», tocca Continua (NON toccare «Salta») per mostrare il codice QR.",
                "Dal vecchio iPhone apri WhatsApp Personale → Impostazioni ⚙️ → Chat → Trasferisci chat su iPhone → Inizia e inquadra il QR mostrato qui!"
            ]
        }()

        let buttonTitle: String = isPersonalInstalled
            ? "Apri WhatsApp Personale"
            : "Scarica WhatsApp Personale"

        let buttonIcon: String = isPersonalInstalled
            ? "bubble.left.and.bubble.right.fill"
            : "arrow.down.app.fill"

        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                AppleSettingsIcon(systemName: "bubble.left.and.bubble.right.fill", color: AppleTheme.green)
                Text(cardTitle)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(AppleTheme.textPrimary)
                Spacer()
                InfoCircleButton(
                    title: "Perché lo scanner QR si apre dentro WhatsApp",
                    message: "Per motivi di sicurezza Meta non permette ad alcuna app esterna di avviare direttamente la fotocamera di migrazione di WhatsApp.\n\n• Il pulsante qui sotto apre sempre il tuo WhatsApp Personale (mai WhatsApp Business per errore).\n• Una volta dentro WhatsApp sul vecchio telefono, bastano 2 tocchi: Impostazioni ⚙️ (in basso a destra) → Chat → Trasferisci chat su iPhone (o Android) → Inizia per aprire lo scanner QR integrato!"
                )
            }

            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(stepsList.enumerated()), id: \.offset) { idx, stepText in
                    HStack(alignment: .top, spacing: 8) {
                        Text("\(idx + 1)")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .frame(width: 19, height: 19)
                            .background(AppleTheme.green)
                            .clipShape(Circle())
                            .padding(.top, 1)

                        Text(stepText)
                            .font(.system(size: 13))
                            .foregroundColor(AppleTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            ApplePrimaryButton(
                title: buttonTitle,
                icon: buttonIcon,
                color: AppleTheme.green
            ) {
                DirectSwitchTransportViewModel.openPersonalWhatsAppOrStore()
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
        .padding(14)
        .background(AppleTheme.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(AppleTheme.green.opacity(0.48), lineWidth: 1.2)
        )
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
