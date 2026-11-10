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
    let errorNote: String?

    var onConfirmPin: () -> Void
    var onScannedQrCode: (String) -> Void
    var onApplyManualCode: () -> Void

    @State private var showManualField: Bool = false

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
                            message: "Sull'altro telefono (iPhone o Android) apri DirectSwitch e tocca 'Ricevi'. Comparirà qui in automatico: toccalo e inserisci il codice a 6 cifre, oppure inquadra il codice QR."
                        )
                    }
                }

                // Card 1: Rilevamento automatico + Codice a 6 cifre (stile Passa a iOS / Passa a Android, sottotitoli dentro ⓘ)
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 6) {
                        Text("Dispositivi rilevati")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(AppleTheme.textPrimary)
                        InfoCircleButton(
                            title: "Rilevamento automatico",
                            message: "Assicurati che sull'altro telefono sia aperta la schermata 'Ricevi' di DirectSwitch sulla stessa rete Wi-Fi o Hotspot."
                        )
                        Spacer()
                        if discoveredBeacons.isEmpty {
                            ProgressView()
                                .scaleEffect(0.85)
                                .tint(AppleTheme.blue)
                        } else {
                            Text("\(discoveredBeacons.count) pronto")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(AppleTheme.green)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(AppleTheme.green.opacity(0.12))
                                .clipShape(Capsule())
                        }
                    }

                    if discoveredBeacons.isEmpty {
                        HStack(spacing: 12) {
                            AppleSettingsIcon(systemName: "wifi", color: AppleTheme.blue)
                            Text("Ricerca dell'altro telefono...")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundColor(AppleTheme.textPrimary)
                            Spacer()
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
                .onChange(of: discoveredBeacons.count) { _ in
                    if selectedBeacon == nil, let first = discoveredBeacons.first {
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

                if let err = errorNote, !err.isEmpty {
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
        .onAppear {
            if selectedBeacon == nil, let first = discoveredBeacons.first {
                selectedBeacon = first
            }
        }
    }
}

// MARK: - Passo 2 Mittente: Scegli cosa copiare (stile "Passa a Android" + "CloudSave")

struct SendCategoriesStepView: View {
    let pairedPayload: QrPairingPayload
    let scanSummary: iOSLocalDeviceScanSummary?
    let isScanningDevice: Bool
    let isLocalProUnlocked: Bool
    let pickedDocuments: [(ManifestItem, URL)]

    @Binding var includeContacts: Bool
    @Binding var includePhotos: Bool
    @Binding var includeVideos: Bool
    @Binding var includeCalendars: Bool
    @Binding var includeDocuments: Bool
    @Binding var includeWhatsApp: Bool

    var onScanExactCounts: () -> Void
    var onAddFilesOrWhatsApp: () -> Void
    var onClearStagedFiles: () -> Void
    var onOpenProSheet: () -> Void
    var onChangePairedDevice: () -> Void
    var onStartCopy: () -> Void

    private var allSelected: Bool {
        includeContacts && includePhotos && includeVideos && includeCalendars && includeDocuments && includeWhatsApp
    }

    private var anySelected: Bool {
        includeContacts || includePhotos || includeVideos || includeCalendars || includeDocuments || includeWhatsApp
    }

    private var isCrossOs: Bool {
        pairedPayload.receiverPlatform == .ANDROID
    }

    private var isSessionFullUnlocked: Bool {
        !isCrossOs || isLocalProUnlocked || pairedPayload.receiverHasPro
    }

    private var docsCount: Int {
        pickedDocuments.filter { $0.0.category == .DOCUMENTS }.count
    }

    private var whatsAppCount: Int {
        pickedDocuments.filter { $0.0.category == .WHATSAPP_VAULT }.count
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                HStack {
                    Text("Passo 2 di 3")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(AppleTheme.blue)
                    Spacer()
                    Button(action: {
                        let target = !allSelected
                        includeContacts = target
                        includePhotos = target
                        includeVideos = target
                        includeCalendars = target
                        includeDocuments = target
                        includeWhatsApp = target
                    }) {
                        Text(allSelected ? "Deseleziona" : "Seleziona tutto")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(AppleTheme.blue)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 8)

                // Dispositivo collegato (sottotitolo dentro ⓘ)
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
                                ? "Collegamento diretto attivo e pronto al trasferimento completo dei dati selezionati."
                                : (isSessionFullUnlocked
                                   ? "Premium Direct attivo: trasferimento completo iPhone ↔ Android sbloccato senza limiti."
                                   : "Con Premium Direct sblocchi il trasferimento illimitato di foto originali, video 4K, album, calendari e file verso Android senza formattare.")
                        )

                        Spacer()

                        Button(action: onChangePairedDevice) {
                            Text("Cambia")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(AppleTheme.blue)
                        }
                        .buttonStyle(.plain)
                    }

                    if isCrossOs && !isSessionFullUnlocked {
                        Button(action: onOpenProSheet) {
                            HStack(spacing: 6) {
                                Image(systemName: "crown.fill")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(AppleTheme.premiumAmber)
                                Text("Sblocca trasferimento completo iPhone ↔ Android")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundColor(AppleTheme.premiumGold)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(AppleTheme.premiumGold)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 9)
                            .background(AppleTheme.premiumSurface)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(AppleTheme.premiumBorder.opacity(0.6), lineWidth: 1.0)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .appleCard(padding: 14, selected: true)

                HStack {
                    Text("Cosa inviare")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(AppleTheme.textPrimary)
                    Spacer()
                    if !(scanSummary?.hasFullPermissions ?? false) {
                        Button(action: onScanExactCounts) {
                            Text(isScanningDevice ? "Calcolo..." : "Calcola dimensioni")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(AppleTheme.blue)
                        }
                        .buttonStyle(.plain)
                        .disabled(isScanningDevice)
                    }
                }

                // Lista pulita con sottotitoli racchiusi in ⓘ
                VStack(spacing: 0) {
                    CleanCategoryToggleRow(
                        icon: "person.crop.circle.fill",
                        iconColor: AppleTheme.blue,
                        title: "Rubrica contatti",
                        countBadge: badgeForCount(scanSummary?.contactsCount, unit: "contatti"),
                        infoMessage: "Trasferisce tutti i contatti con numeri di telefono, email e note unendo eventuali duplicati.",
                        isOn: $includeContacts
                    )

                    Divider().padding(.leading, 58)

                    CleanCategoryToggleRow(
                        icon: "photo.fill",
                        iconColor: AppleTheme.orange,
                        title: "Foto e Album",
                        countBadge: badgeForMedia(count: scanSummary?.photosCount, bytes: scanSummary?.photosBytes, unit: "foto"),
                        infoMessage: "Copia tutte le foto nella qualità originale preservando data di scatto, posizione GPS e album.",
                        isOn: $includePhotos
                    )

                    Divider().padding(.leading, 58)

                    CleanCategoryToggleRow(
                        icon: "video.fill",
                        iconColor: AppleTheme.red,
                        title: "Video originali",
                        countBadge: badgeForMedia(count: scanSummary?.videosCount, bytes: scanSummary?.videosBytes, unit: "video"),
                        infoMessage: "Copia tutti i video in risoluzione originale (inclusi 4K 60fps) senza compressione.",
                        isOn: $includeVideos
                    )

                    Divider().padding(.leading, 58)

                    CleanCategoryToggleRow(
                        icon: "calendar",
                        iconColor: AppleTheme.slate,
                        title: "Calendari",
                        countBadge: badgeForCount(scanSummary?.calendarEventsCount, unit: "eventi"),
                        infoMessage: "Importa tutti gli appuntamenti, promemoria ed eventi del calendario.",
                        isOn: $includeCalendars
                    )

                    Divider().padding(.leading, 58)

                    CleanCategoryToggleRow(
                        icon: "doc.fill",
                        iconColor: AppleTheme.teal,
                        title: "Documenti e File",
                        countBadge: docsCount > 0 ? "\(docsCount) file selezionati" : "Da app File",
                        infoMessage: "Trasferisce i documenti, PDF e cartelle selezionati dall'app File di iPhone.",
                        isOn: $includeDocuments
                    )

                    Divider().padding(.leading, 58)

                    CleanCategoryToggleRow(
                        icon: "bubble.left.and.bubble.right.fill",
                        iconColor: AppleTheme.green,
                        title: "Chat WhatsApp",
                        countBadge: whatsAppCount > 0
                            ? "Cronologia QR + \(whatsAppCount) .zip"
                            : (isCrossOs ? "Senza cavo via QR (Android Switch)" : "Cronologia diretta via QR"),
                        infoMessage: isCrossOs
                            ? "Al termine della copia, DirectSwitch apre automaticamente il modulo Android Switch senza cavo sul telefono Android per mostrare il codice QR: su questo iPhone ti basterà aprire WhatsApp → Impostazioni → Chat → Trasferisci chat su Android e inquadrare il QR. Eventuali archivi .zip allegati vengono trasferiti insieme ai file."
                            : "Al termine della copia, DirectSwitch ti guida a trasferire l'intera cronologia chat sul nuovo iPhone senza usare spazio iCloud: sul nuovo iPhone inserisci il tuo numero in WhatsApp e inquadra il codice QR da questo iPhone (Impostazioni → Chat → Trasferisci chat su iPhone).",
                        isOn: $includeWhatsApp
                    )
                }
                .appleCard(padding: 0)

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Documenti o archivi extra da allegare")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(AppleTheme.textPrimary)
                        Spacer()
                        InfoCircleButton(
                            title: "Documenti e archivi opzionali",
                            message: "• L'intera cronologia chat di WhatsApp viene trasferita senza cavo tramite codice QR al termine della copia.\n• Qui puoi inoltre allegare PDF, cartelle dall'app File o singoli archivi .zip esportati."
                        )
                    }

                    AppleSecondaryButton(
                        title: pickedDocuments.isEmpty
                            ? "Scegli da File o allega .zip WhatsApp"
                            : "Aggiungi altri file (\(pickedDocuments.count) pronti)",
                        icon: "plus.circle.fill",
                        tint: AppleTheme.blue,
                        action: onAddFilesOrWhatsApp
                    )

                    if !pickedDocuments.isEmpty {
                        HStack {
                            Text(pickedDocuments.map { $0.0.fileName }.joined(separator: ", "))
                                .font(.system(size: 12))
                                .foregroundColor(AppleTheme.textSecondary)
                                .lineLimit(1)
                            Spacer()
                            Button("Rimuovi", action: onClearStagedFiles)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(AppleTheme.red)
                                .buttonStyle(.plain)
                        }
                    }
                }
                .appleCard(padding: 14)

                ApplePrimaryButton(
                    title: "Copia i dati",
                    icon: "arrow.right",
                    color: AppleTheme.blue,
                    isDisabled: !anySelected,
                    action: onStartCopy
                )
                .padding(.top, 4)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 28)
        }
    }

    private func badgeForCount(_ count: Int?, unit: String) -> String? {
        guard let c = count, c > 0 else { return nil }
        return "\(c) \(unit)"
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
