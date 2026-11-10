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
    case quickContactsPortal
}

struct DirectSwitchMainView: View {
    @StateObject private var transport = DirectSwitchTransportViewModel()

    @State private var activeStep: DirectSwitchWizardStep = .home
    @State private var isReceiverMode: Bool = false

    // Stato accoppiamento Ricevente / Mittente
    @State private var receiverQrPayload: QrPairingPayload? = nil
    @State private var pairedTargetPayload: QrPairingPayload? = nil
    @State private var selectedBeacon: DiscoveryBeaconPayload? = nil
    @State private var pinCodeInput: String = ""
    @State private var manualCodeInput: String = ""
    @State private var showCameraScanner: Bool = false
    @State private var isPairingBusy: Bool = false
    @State private var pairingErrorNote: String? = nil

    // Categorie di trasferimento (stile Android Switch / CloudSave)
    @State private var includeContacts: Bool = true
    @State private var includePhotos: Bool = true
    @State private var includeVideos: Bool = true
    @State private var includeCalendars: Bool = true
    @State private var includeDocuments: Bool = true
    @State private var includeWhatsApp: Bool = true

    // File e archivi WhatsApp allegati
    @State private var showDocumentImporter: Bool = false
    @State private var pickedDocuments: [(ManifestItem, URL)] = []
    @State private var sharedVaultToast: String? = nil

    // Scansione locale e StoreKit Pass Cross-OS
    @State private var scanSummary: iOSLocalDeviceScanSummary? = nil
    @State private var isScanningDevice: Bool = false
    @State private var isProUnlocked: Bool = iOSLicenseStore.isLocalProUnlocked
    @State private var showProSheet: Bool = false
    @State private var showAndroidCableSheet: Bool = false
    @State private var billingNote: String? = nil

    private var topBarTitle: String {
        switch activeStep {
        case .home:
            return "DirectSwitch"
        case .receiveWaitCode:
            return "Ricevi dati"
        case .sendConnect:
            return "Collega telefono"
        case .sendSelectCategories:
            return "Cosa copiare"
        case .transferProgress:
            return transport.isCompleted ? "Completato" : "Copia dei dati"
        case .quickContactsPortal:
            return "Rubrica rapida"
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
                                onStartSend: startSendWizard,
                                onOpenAndroidCableGuide: { showAndroidCableSheet = true },
                                onStartQuickContactsPortal: startQuickContactsPortal
                            )

                        case .receiveWaitCode:
                            if let qr = receiverQrPayload {
                                ReceivePairingStepView(
                                    qrPayload: qr,
                                    pairingPin: transport.activePairingPin,
                                    errorMessage: transport.errorMessage,
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
                                discoveredBeacons: transport.discoveredBeacons,
                                selectedBeacon: $selectedBeacon,
                                pinInput: $pinCodeInput,
                                showCameraScanner: $showCameraScanner,
                                manualCodeInput: $manualCodeInput,
                                isPairingBusy: isPairingBusy,
                                errorNote: pairingErrorNote,
                                onConfirmPin: confirmPinPairing,
                                onScannedQrCode: handleScannedQrString,
                                onApplyManualCode: { handleScannedQrString(manualCodeInput) }
                            )

                        case .sendSelectCategories:
                            if let paired = pairedTargetPayload {
                                SendCategoriesStepView(
                                    pairedPayload: paired,
                                    scanSummary: scanSummary,
                                    isScanningDevice: isScanningDevice,
                                    isLocalProUnlocked: isProUnlocked,
                                    pickedDocuments: pickedDocuments,
                                    includeContacts: $includeContacts,
                                    includePhotos: $includePhotos,
                                    includeVideos: $includeVideos,
                                    includeCalendars: $includeCalendars,
                                    includeDocuments: $includeDocuments,
                                    includeWhatsApp: $includeWhatsApp,
                                    onScanExactCounts: scanExactDeviceCounts,
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
                                onFinish: finishAndReturnHome
                            )

                        case .quickContactsPortal:
                            if let url = transport.bootstrapPortalUrl {
                                QuickContactsPortalView(
                                    portalUrl: url,
                                    onClose: finishAndReturnHome
                                )
                            }
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
        }
        .onChange(of: transport.isSessionConnected) { connected in
            if connected && activeStep == .receiveWaitCode {
                withAnimation(.easeInOut(duration: 0.25)) {
                    activeStep = .transferProgress
                }
            }
        }
        .onOpenURL { incomingURL in
            handleIncomingURL(incomingURL)
        }
        .fileImporter(
            isPresented: $showDocumentImporter,
            allowedContentTypes: [.item],
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result {
                let imported = iOSDocumentsSandboxBridge.importPickedDocumentURLs(urls)
                pickedDocuments.append(contentsOf: imported)
                refreshAuthorizedSummary()
            }
        }
        .sheet(isPresented: $showProSheet) {
            DirectSwitchProPassSheet(
                isProUnlocked: $isProUnlocked,
                billingNote: $billingNote,
                onClose: { showProSheet = false }
            )
        }
        .sheet(isPresented: $showAndroidCableSheet) {
            AndroidCableGuideSheet(onClose: { showAndroidCableSheet = false })
        }
    }

    // MARK: - Azioni di navigazione e flusso guidato

    private func startReceiveWizard() {
        isReceiverMode = true
        pairingErrorNote = nil
        receiverQrPayload = transport.startReceiverServer()
        withAnimation(.easeInOut(duration: 0.22)) {
            activeStep = .receiveWaitCode
        }
    }

    private func startSendWizard() {
        isReceiverMode = false
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

    private func startQuickContactsPortal() {
        Task {
            if await transport.startBootstrapPortalSession() != nil {
                withAnimation(.easeInOut(duration: 0.22)) {
                    activeStep = .quickContactsPortal
                }
            }
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
        Task {
            await transport.executeSenderTransfer(
                qrPayload: paired,
                includeContacts: includeContacts,
                includePhotos: includePhotos,
                includeVideos: includeVideos,
                includeCalendars: includeCalendars,
                includeDocuments: includeDocuments,
                includeWhatsAppVault: includeWhatsApp,
                pickedDocuments: docsSnapshot
            )
            if transport.isCompleted {
                pickedDocuments.removeAll()
                refreshAuthorizedSummary()
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
                    startSendWizard()
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
        case .receiveWaitCode, .quickContactsPortal:
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
        transport.resetSession()
        withAnimation(.easeInOut(duration: 0.22)) {
            activeStep = .home
        }
    }
}

// MARK: - Schermata Home pulita (stile "Passa a iOS" + "CloudSave")

private struct DirectSwitchHomeView: View {
    var onStartReceive: () -> Void
    var onStartSend: () -> Void
    var onOpenAndroidCableGuide: () -> Void
    var onStartQuickContactsPortal: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                // Hero centrale pulito (identico all'impostazione di CloudSave)
                VStack(spacing: 10) {
                    DirectSwitchAppleEmblem(size: 64)
                        .padding(.top, 14)

                    HStack(spacing: 4) {
                        Text("DirectSwitch")
                            .font(.system(size: 26, weight: .bold))
                            .foregroundColor(AppleTheme.textPrimary)
                        InfoCircleButton(
                            title: "Come funziona DirectSwitch",
                            message: "DirectSwitch copia rubrica, foto con album, video originali, calendari, file e chat WhatsApp direttamente tra due telefoni già configurati, senza formattare l'iPhone e senza passare dal cloud."
                        )
                    }

                    Text("Copia i tuoi dati senza formattare")
                        .font(.system(size: 15))
                        .foregroundColor(AppleTheme.textSecondary)
                }
                .padding(.bottom, 4)

                // Card 1: Questo è il Nuovo iPhone (Ricevi)
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 10) {
                        AppleSettingsIcon(systemName: "arrow.down.to.line.compact", color: AppleTheme.blue)
                        Text("Questo è il **Nuovo** iPhone")
                            .font(.system(size: 16, weight: .regular))
                            .foregroundColor(AppleTheme.textPrimary)
                        Spacer()
                        InfoCircleButton(
                            title: "Ricevi su questo iPhone",
                            message: "Mostra un codice monouso a 6 cifre (come 'Passa a iOS') o un codice QR per ricevere i dati dal tuo vecchio iPhone o Android senza cancellare nulla di ciò che hai già sul telefono."
                        )
                    }

                    ApplePrimaryButton(
                        title: "Ricevi su questo iPhone",
                        icon: "arrow.down.circle.fill",
                        color: AppleTheme.blue,
                        action: onStartReceive
                    )
                }
                .appleCard()

                // Card 2: Questo è il Vecchio iPhone (Invia)
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 10) {
                        AppleSettingsIcon(systemName: "arrow.up.right.square.fill", color: AppleTheme.indigo)
                        Text("Questo è il **Vecchio** iPhone")
                            .font(.system(size: 16, weight: .regular))
                            .foregroundColor(AppleTheme.textPrimary)
                        Spacer()
                        InfoCircleButton(
                            title: "Invia al nuovo telefono",
                            message: "• Tocca 'Invia al nuovo telefono' per copiare in Wi-Fi diretto verso un nuovo iPhone o Android con DirectSwitch.\n• Tocca 'Passa ad Android con cavo' se vuoi usare il cavo USB-C e l'app ufficiale Google.\n• Tocca 'Solo Rubrica via QR' per passare subito i contatti a qualsiasi telefono senza installare app."
                        )
                    }

                    ApplePrimaryButton(
                        title: "Invia al nuovo telefono",
                        icon: "arrow.up.circle.fill",
                        color: AppleTheme.charcoal,
                        action: onStartSend
                    )

                    GoogleStyleActionButton(
                        title: "Passa ad Android con cavo",
                        action: onOpenAndroidCableGuide
                    )

                    Button(action: onStartQuickContactsPortal) {
                        HStack(spacing: 6) {
                            Image(systemName: "qrcode")
                                .font(.system(size: 13, weight: .semibold))
                            Text("Solo Rubrica via QR (senza app)")
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .foregroundColor(AppleTheme.blue)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 2)
                    }
                    .buttonStyle(.plain)
                }
                .appleCard()
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 28)
        }
    }
}

// MARK: - Schermata Avanzamento & Completamento (stile "Passa a iOS" / "Android Switch")

private struct DirectSwitchTransferProgressView: View {
    @ObservedObject var transport: DirectSwitchTransportViewModel
    let isReceiverMode: Bool
    let isProUnlocked: Bool
    var onOpenProSheet: () -> Void
    var onRetryIfFailed: () -> Void
    var onFinish: () -> Void

    private var progressFraction: Double {
        if transport.isCompleted { return 1.0 }
        if transport.totalBytesCount > 0 {
            return min(1.0, max(0.02, Double(transport.transferredBytesCount) / Double(transport.totalBytesCount)))
        }
        if transport.totalItems > 0 {
            return min(1.0, max(0.02, Double(transport.completedItems) / Double(transport.totalItems)))
        }
        return transport.isTransferring ? 0.08 : 0.0
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
                // Hero stato stile Passa a iOS
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
                        DirectSwitchAppleEmblem(size: 62)
                            .padding(.top, 14)

                        Text(isReceiverMode ? "Copia su questo iPhone..." : "Copia dei dati in corso...")
                            .font(.system(size: 23, weight: .bold))
                            .foregroundColor(AppleTheme.textPrimary)

                        Text("Tieni entrambi i telefoni vicini fino al termine")
                            .font(.system(size: 14))
                            .foregroundColor(AppleTheme.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                }

                // Barra di avanzamento Apple pulita
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

                // Riepilogo elementi copiati (stile Impostazioni Apple)
                VStack(spacing: 0) {
                    summaryRow(
                        icon: "person.crop.circle.fill",
                        color: AppleTheme.blue,
                        title: "Contatti uniti",
                        value: "\(transport.mergedContacts)"
                    )
                    Divider().padding(.leading, 56)
                    summaryRow(
                        icon: "photo.on.rectangle.angled",
                        color: AppleTheme.orange,
                        title: "Foto, Video e File",
                        value: transport.totalItems > 0 ? "\(transport.completedItems) / \(transport.totalItems)" : "\(transport.completedItems)"
                    )
                    Divider().padding(.leading, 56)
                    summaryRow(
                        icon: "calendar",
                        color: AppleTheme.indigo,
                        title: "Calendari importati",
                        value: "\(transport.importedCalendars)"
                    )

                    if transport.importedSms > 0 {
                        Divider().padding(.leading, 56)
                        summaryRow(
                            icon: "message.fill",
                            color: AppleTheme.green,
                            title: "Messaggi salvati",
                            value: "\(transport.importedSms)"
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
                }
                .appleCard(padding: 0)

                if isReceiverMode && transport.isCompleted && (transport.importedSms > 0 || transport.completedItems > 0) {
                    HStack(spacing: 10) {
                        Image(systemName: "folder.fill")
                            .foregroundColor(AppleTheme.blue)
                        Text("Documenti, chat WhatsApp e archivio SMS sono nell'app **File → Su iPhone → DirectSwitch**.")
                            .font(.system(size: 13))
                            .foregroundColor(AppleTheme.textSecondary)
                        Spacer()
                    }
                    .appleCard(padding: 14)
                }

                if transport.gatedPreviewCount > 0 && !isProUnlocked {
                    Button(action: onOpenProSheet) {
                        HStack(spacing: 10) {
                            AppleSettingsIcon(systemName: "lock.open.fill", color: AppleTheme.orange)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(transport.gatedPreviewCount) file oltre l'anteprima gratuita")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(AppleTheme.textPrimary)
                                Text("Tocca per sbloccare il Pass Cross-OS e copiarli tutti")
                                    .font(.system(size: 12))
                                    .foregroundColor(AppleTheme.textSecondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(AppleTheme.textTertiary)
                        }
                        .appleCard(padding: 14, selected: true)
                    }
                    .buttonStyle(.plain)
                }

                if let err = transport.errorMessage, !err.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(AppleTheme.red)
                            Text(err)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(AppleTheme.red)
                        }
                        if !isReceiverMode {
                            AppleSecondaryButton(
                                title: "Riprova copia",
                                icon: "arrow.clockwise",
                                tint: AppleTheme.blue,
                                action: onRetryIfFailed
                            )
                        }
                    }
                    .appleCard(padding: 14)
                }

                if transport.isCompleted || transport.errorMessage != nil {
                    ApplePrimaryButton(
                        title: transport.isCompleted ? "Fine" : "Torna alla Home",
                        icon: transport.isCompleted ? "checkmark" : nil,
                        color: AppleTheme.blue,
                        action: onFinish
                    )
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 28)
        }
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

// MARK: - Sheet Pass Cross-OS in stile CloudSave / Apple App Store

private struct DirectSwitchProPassSheet: View {
    @Binding var isProUnlocked: Bool
    @Binding var billingNote: String?
    var onClose: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Spacer()
                InfoCircleButton(
                    title: "Sblocco su un solo telefono",
                    message: "• Il passaggio tra due iPhone (iPhone ↔ iPhone) è sempre 100% gratuito e illimitato.\n• Per il passaggio Android ↔ iPhone, la Rubrica è gratuita e il Pass Una Tantum sblocca foto, video 4K, calendari, messaggi e file su entrambi i telefoni pagando su uno solo."
                )
            }

            DirectSwitchAppleEmblem(size: 56)

            VStack(spacing: 6) {
                Text("Pass Android ↔ iPhone")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(AppleTheme.textPrimary)
                Text("Sblocca copia illimitata su entrambi i telefoni")
                    .font(.system(size: 14))
                    .foregroundColor(AppleTheme.textSecondary)
            }

            VStack(alignment: .leading, spacing: 10) {
                featureLine(icon: "checkmark.circle.fill", text: "iPhone ↔ iPhone sempre 100% gratuito")
                featureLine(icon: "photo.stack.fill", text: "Foto HEIC/JPG e Video 4K originali con Album")
                featureLine(icon: "person.2.fill", text: "Un solo acquisto vale per entrambi i telefoni")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .appleCard(padding: 14)

            if let note = billingNote, !note.isEmpty {
                Text(note)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(AppleTheme.blue)
                    .multilineTextAlignment(.center)
            }

            ApplePrimaryButton(
                title: isProUnlocked ? "Pass già attivo" : "Sblocca Pass Una Tantum (9,99 €)",
                icon: isProUnlocked ? "checkmark.seal.fill" : "lock.open.fill",
                color: isProUnlocked ? AppleTheme.green : AppleTheme.blue,
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

            HStack(spacing: 18) {
                Button("Ripristina acquisti") {
                    Task {
                        let restored = await iOSLicenseStore.restoreStoreKitEntitlements()
                        isProUnlocked = restored
                        billingNote = restored ? "Acquisto ripristinato!" : "Nessun acquisto precedente trovato."
                    }
                }
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(AppleTheme.blue)
                .buttonStyle(.plain)

                Text("•")
                    .foregroundColor(AppleTheme.textTertiary)

                Button("Chiudi", action: onClose)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(AppleTheme.textSecondary)
                    .buttonStyle(.plain)
            }
            .padding(.top, 2)
        }
        .padding(20)
        .background(AppleTheme.backgroundGradient.ignoresSafeArea())
        .presentationDetents([.height(470), .large])
        .presentationDragIndicator(.visible)
        .preferredColorScheme(.light)
    }

    private func featureLine(icon: String, text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(AppleTheme.blue)
            Text(text)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(AppleTheme.textPrimary)
        }
    }
}

// MARK: - Sheet compatto per Passaggio iPhone → Android con cavo / Android Switch

private struct AndroidCableGuideSheet: View {
    var onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                GoogleGlyphIcon(size: 22)
                Text("Passa ad Android con cavo")
                    .font(.system(size: 19, weight: .bold))
                    .foregroundColor(AppleTheme.textPrimary)
                Spacer()
            }
            .padding(.top, 6)

            VStack(alignment: .leading, spacing: 10) {
                Text("1. Sul nuovo Android apri **DirectSwitch** e scegli **Copia con cavo Google**.")
                Text("2. Collega iPhone e Android con il cavo USB-C / Lightning (oppure apri **Android Switch** qui sotto per la modalità senza cavo).")
            }
            .font(.system(size: 14))
            .foregroundColor(AppleTheme.textSecondary)
            .appleCard(padding: 14)

            ApplePrimaryButton(
                title: "Apri Android Switch su App Store",
                icon: "arrow.up.forward.app.fill",
                color: AppleTheme.blue
            ) {
                if let url = URL(string: "https://apps.apple.com/app/switch-to-android/id1611395432") {
                    UIApplication.shared.open(url)
                }
            }

            AppleSecondaryButton(
                title: "Chiudi",
                tint: AppleTheme.textSecondary,
                action: onClose
            )
        }
        .padding(20)
        .background(AppleTheme.backgroundGradient.ignoresSafeArea())
        .presentationDetents([.height(330), .medium])
        .presentationDragIndicator(.visible)
        .preferredColorScheme(.light)
    }
}
