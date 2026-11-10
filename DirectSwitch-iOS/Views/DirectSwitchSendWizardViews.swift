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

// MARK: - Passo 1 Mittente: Collega il nuovo telefono (Codice a 6 cifre stile "Passa a iOS" o QR)

struct SendConnectStepView: View {
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

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                HStack {
                    Text("Passo 1 di 3")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(AppleTheme.blue)
                    Spacer()
                    InfoCircleButton(
                        title: "Come collegare il nuovo telefono",
                        message: "Apri DirectSwitch sul nuovo iPhone o Android e tocca 'Ricevi'. Il nuovo telefono comparirà qui in automatico: toccalo e digita il codice a 6 cifre mostrato sul suo schermo, oppure premi 'Inquadra codice QR' (comodo anche per agganciare l'Hotspot 5GHz di Android senza Wi-Fi)."
                    )
                }
                .padding(.top, 8)

                VStack(spacing: 8) {
                    ZStack {
                        Circle()
                            .fill(AppleTheme.blue.opacity(0.12))
                            .frame(width: 58, height: 58)
                        Image(systemName: "iphone.radiowaves.left.and.right")
                            .font(.system(size: 25, weight: .semibold))
                            .foregroundColor(AppleTheme.blue)
                    }

                    Text("Collega il nuovo telefono")
                        .font(.system(size: 23, weight: .bold))
                        .foregroundColor(AppleTheme.textPrimary)

                    Text("Seleziona il telefono rilevato o inquadra il codice QR")
                        .font(.system(size: 14))
                        .foregroundColor(AppleTheme.textSecondary)
                        .multilineTextAlignment(.center)
                }

                // Card 1: Rilevamento automatico + Codice a 6 cifre (stile Passa a iOS)
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text("Telefoni vicini")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(AppleTheme.textPrimary)
                        Spacer()
                        if discoveredBeacons.isEmpty {
                            ProgressView()
                                .scaleEffect(0.85)
                                .tint(AppleTheme.blue)
                        } else {
                            Text("\(discoveredBeacons.count) trovato")
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
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Ricerca in corso sulla rete Wi-Fi...")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(AppleTheme.textPrimary)
                                Text("Assicurati che 'Ricevi' sia aperto sull'altro telefono")
                                    .font(.system(size: 12))
                                    .foregroundColor(AppleTheme.textSecondary)
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
                                            color: isSelected ? AppleTheme.blue : AppleTheme.indigo
                                        )
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(beacon.receiverName)
                                                .font(.system(size: 15, weight: .semibold))
                                                .foregroundColor(AppleTheme.textPrimary)
                                            Text(beacon.receiverPlatform == .IOS ? "iPhone pronto a ricevere" : "Android pronto a ricevere")
                                                .font(.system(size: 12))
                                                .foregroundColor(AppleTheme.textSecondary)
                                        }
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
                            Text("Inserisci il codice a 6 cifre mostrato su **\(activeBeacon.receiverName)**")
                                .font(.system(size: 14))
                                .foregroundColor(AppleTheme.textSecondary)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: .infinity)

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

                // Card 2: Fotocamera QR (ideale anche per Hotspot 5GHz Android)
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Oppure usa la fotocamera")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(AppleTheme.textPrimary)
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

// MARK: - Passo 2 Mittente: Scegli cosa copiare (stile "Android Switch" + "CloudSave")

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
                // Riga Passo + Seleziona tutto (identica a CloudSave UnifiedCategoriesStepView)
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

                // Dispositivo collegato (card compatta perla)
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(AppleTheme.green.opacity(0.15))
                                .frame(width: 38, height: 38)
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundColor(AppleTheme.green)
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Collegato a \(pairedPayload.receiverName)")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(AppleTheme.textPrimary)
                            Text(!isCrossOs
                                 ? "Passaggio iPhone ↔ iPhone • 100% Gratuito"
                                 : (isSessionFullUnlocked
                                    ? "Pass Cross-OS attivo • Copia completa"
                                    : "Modalità anteprima • Rubrica + 25 foto/video"))
                                .font(.system(size: 12))
                                .foregroundColor(isSessionFullUnlocked ? AppleTheme.green : AppleTheme.orange)
                        }

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
                                Image(systemName: "lock.open.fill")
                                    .font(.system(size: 12, weight: .semibold))
                                Text("Sblocca copia illimitata verso Android")
                                    .font(.system(size: 13, weight: .semibold))
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 11, weight: .semibold))
                            }
                            .foregroundColor(AppleTheme.blue)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 9)
                            .background(AppleTheme.blue.opacity(0.10))
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .appleCard(padding: 14, selected: true)

                // Titolo sezione
                HStack {
                    Text("Scegli cosa copiare")
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

                // Lista pulita in stile Impostazioni Apple / Android Switch
                VStack(spacing: 0) {
                    CleanCategoryToggleRow(
                        icon: "person.crop.circle.fill",
                        iconColor: AppleTheme.blue,
                        title: "Rubrica contatti",
                        countBadge: badgeForCount(scanSummary?.contactsCount, unit: "contatti"),
                        isOn: $includeContacts
                    )

                    Divider().padding(.leading, 58)

                    CleanCategoryToggleRow(
                        icon: "photo.fill",
                        iconColor: AppleTheme.orange,
                        title: "Foto e Album",
                        countBadge: badgeForMedia(count: scanSummary?.photosCount, bytes: scanSummary?.photosBytes, unit: "foto"),
                        isOn: $includePhotos
                    )

                    Divider().padding(.leading, 58)

                    CleanCategoryToggleRow(
                        icon: "video.fill",
                        iconColor: AppleTheme.red,
                        title: "Video originali",
                        countBadge: badgeForMedia(count: scanSummary?.videosCount, bytes: scanSummary?.videosBytes, unit: "video"),
                        isOn: $includeVideos
                    )

                    Divider().padding(.leading, 58)

                    CleanCategoryToggleRow(
                        icon: "calendar",
                        iconColor: AppleTheme.indigo,
                        title: "Calendari",
                        countBadge: badgeForCount(scanSummary?.calendarEventsCount, unit: "eventi"),
                        isOn: $includeCalendars
                    )

                    Divider().padding(.leading, 58)

                    CleanCategoryToggleRow(
                        icon: "doc.fill",
                        iconColor: AppleTheme.teal,
                        title: "Documenti e File",
                        countBadge: docsCount > 0 ? "\(docsCount) file selezionati" : "Da app File",
                        isOn: $includeDocuments
                    )

                    Divider().padding(.leading, 58)

                    CleanCategoryToggleRow(
                        icon: "bubble.left.and.bubble.right.fill",
                        iconColor: AppleTheme.green,
                        title: "Chat WhatsApp",
                        countBadge: whatsAppCount > 0 ? "\(whatsAppCount) archivi .zip pronti" : "Esporta chat (.zip)",
                        isOn: $includeWhatsApp
                    )
                }
                .appleCard(padding: 0)

                // Aggiunta file o chat WhatsApp (.zip) pulita con ⓘ
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("File e chat WhatsApp da allegare")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(AppleTheme.textPrimary)
                        Spacer()
                        InfoCircleButton(
                            title: "Come allegare File e WhatsApp su iPhone",
                            message: "• Per i Documenti: tocca 'Scegli da File' per allegare PDF, cartelle o archivi presenti sull'iPhone.\n• Per WhatsApp: in WhatsApp apri una chat → Esporta chat → scegli 'DirectSwitch' (oppure salvala in File e selezionala qui)."
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

                // Pulsante principale di avvio copia
                ApplePrimaryButton(
                    title: "Copia i dati",
                    icon: "arrow.right.circle.fill",
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
