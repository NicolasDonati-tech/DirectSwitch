//
//  DirectSwitchAppsTransferViews.swift
//  DirectSwitch-iOS
//
//  Created by Nicolas Donati.
//  Copyright © 2026 Nicolas Donati. Tutti i diritti riservati.
//

import AVFoundation
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

// MARK: - Anteprima Fotocamera Live 60fps per Lettura App dallo Schermo del Vecchio Telefono

private final class LiveAppCameraHostController: UIViewController {
    let previewLayer = AVCaptureVideoPreviewLayer()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        previewLayer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(previewLayer)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer.frame = view.bounds
    }
}

private struct LiveAppCameraPreviewView: UIViewControllerRepresentable {
    let session: AVCaptureSession

    func makeUIViewController(context: Context) -> LiveAppCameraHostController {
        let vc = LiveAppCameraHostController()
        vc.previewLayer.session = session
        return vc
    }

    func updateUIViewController(_ uiViewController: LiveAppCameraHostController, context: Context) {
        if uiViewController.previewLayer.session !== session {
            uiViewController.previewLayer.session = session
        }
        uiViewController.previewLayer.frame = uiViewController.view.bounds
    }
}

// MARK: - Scanner Fotocamera Live: Inquadra le Pagine Home del Vecchio Telefono (Zero Registrazione Schermo)

struct LiveCameraAppScannerSheet: View {
    @Environment(\.dismiss) private var dismiss
    let seedApps: [InstalledAppRecord]
    var senderPhoneLabel: String = ""
    var onLiveAppsUpdated: (([InstalledAppRecord]) -> Void)? = nil
    var onConfirmApps: ([InstalledAppRecord]) -> Void

    @StateObject private var scanner = LiveCameraAppScannerViewModel()
    @State private var didConfirmExplicitly: Bool = false

    private var subtitleText: String {
        if !senderPhoneLabel.isEmpty {
            return "Inquadra la schermata Home di \(senderPhoneLabel) e sfoglia con il dito le pagine delle sue App: vengono lette e aggiunte qui in tempo reale!"
        }
        return "Inquadra la schermata Home (o la Libreria App) del vecchio telefono e sfoglia le pagine con il dito: DirectSwitch legge tutte le app in tempo reale!"
    }

    var body: some View {
        NavigationView {
            ZStack {
                AppleTheme.backgroundGradient
                    .ignoresSafeArea()

                VStack(spacing: 14) {
                    Text(subtitleText)
                        .font(.system(size: 13))
                        .foregroundColor(AppleTheme.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    ZStack {
                        if scanner.isCameraPermissionDenied {
                            VStack(spacing: 12) {
                                Image(systemName: "camera.fill")
                                    .font(.system(size: 34))
                                    .foregroundColor(AppleTheme.orange)
                                Text("Permesso Fotocamera necessario")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundColor(.white)
                                Text("Attiva la voce «Fotocamera» per inquadrare le icone sullo schermo del vecchio telefono.")
                                    .font(.system(size: 13))
                                    .foregroundColor(.white.opacity(0.82))
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 18)
                                Button(action: {
                                    iOSPermissionsHelper.openDirectSwitchSettings()
                                }) {
                                    Text("Abilita Fotocamera")
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 18)
                                        .padding(.vertical, 10)
                                        .background(AppleTheme.blue)
                                        .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(Color.black)
                        } else {
                            LiveAppCameraPreviewView(session: scanner.captureSession)

                            // Cornice guida schermo telefono
                            RoundedRectangle(cornerRadius: 24, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.85), style: StrokeStyle(lineWidth: 2.5, dash: [16, 10]))
                                .padding(.horizontal, 28)
                                .padding(.vertical, 20)

                            VStack {
                                HStack(spacing: 7) {
                                    Circle()
                                        .fill(AppleTheme.green)
                                        .frame(width: 8, height: 8)
                                    Text("Lettura live attiva • \(scanner.discoveredApps.count) app")
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundColor(.white)
                                    if scanner.pendingLookupsCount > 0 {
                                        ProgressView()
                                            .scaleEffect(0.72)
                                            .tint(.white)
                                    }
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.black.opacity(0.66))
                                .clipShape(Capsule())
                                .padding(.top, 10)

                                Spacer()

                                if let lastAdded = scanner.latestDetectedAppName {
                                    HStack(spacing: 6) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.system(size: 13, weight: .bold))
                                            .foregroundColor(AppleTheme.green)
                                        Text("+ \(lastAdded)")
                                            .font(.system(size: 13, weight: .bold))
                                            .foregroundColor(.white)
                                            .lineLimit(1)
                                    }
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 7)
                                    .background(Color.black.opacity(0.75))
                                    .clipShape(Capsule())
                                    .padding(.bottom, 12)
                                } else {
                                    Text("Sfoglia le pagine Home sul vecchio telefono")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(Color.black.opacity(0.60))
                                        .clipShape(Capsule())
                                        .padding(.bottom, 12)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 320)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(AppleTheme.blue.opacity(0.45), lineWidth: 1.3)
                    )

                    // Striscia live delle app rilevate (rimovibili con un tocco su x)
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("App registrate (\(scanner.discoveredApps.count))")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(AppleTheme.textPrimary)
                            Spacer()
                            if scanner.newlyScannedCount > 0 {
                                Text("+\(scanner.newlyScannedCount) dallo schermo")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(AppleTheme.green)
                            }
                        }

                        if scanner.discoveredApps.isEmpty {
                            Text("Punta la fotocamera sulle icone delle app del vecchio telefono: appariranno qui in automatico.")
                                .font(.system(size: 12))
                                .foregroundColor(AppleTheme.textSecondary)
                                .padding(.vertical, 4)
                        } else {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(scanner.discoveredApps.reversed()) { app in
                                        HStack(spacing: 6) {
                                            AppIconThumbnailView(iconUrl: app.iconUrl, size: 26)
                                            Text(app.appName)
                                                .font(.system(size: 12, weight: .semibold))
                                                .foregroundColor(AppleTheme.textPrimary)
                                                .lineLimit(1)
                                            Button(action: {
                                                scanner.removeApp(app)
                                            }) {
                                                Image(systemName: "xmark.circle.fill")
                                                    .font(.system(size: 14))
                                                    .foregroundColor(AppleTheme.textTertiary)
                                            }
                                            .buttonStyle(.plain)
                                        }
                                        .padding(.leading, 6)
                                        .padding(.trailing, 8)
                                        .padding(.vertical, 5)
                                        .background(Color.white)
                                        .clipShape(Capsule())
                                        .overlay(
                                            Capsule()
                                                .stroke(AppleTheme.cardBorder, lineWidth: 0.8)
                                        )
                                    }
                                }
                            }
                        }
                    }
                    .appleCard(padding: 12)

                    Spacer(minLength: 0)

                    ApplePrimaryButton(
                        title: scanner.discoveredApps.isEmpty
                            ? "Chiudi scanner"
                            : "Conferma \(scanner.discoveredApps.count) App rilevate",
                        icon: "checkmark.circle.fill",
                        color: AppleTheme.green
                    ) {
                        didConfirmExplicitly = true
                        let finalApps = scanner.discoveredApps
                        scanner.stopScanning()
                        onConfirmApps(finalApps)
                        dismiss()
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .navigationTitle("Scanner App Live")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Chiudi") {
                        didConfirmExplicitly = true
                        let finalApps = scanner.discoveredApps
                        scanner.stopScanning()
                        if scanner.newlyScannedCount > 0 {
                            onConfirmApps(finalApps)
                        }
                        dismiss()
                    }
                }
            }
        }
        .preferredColorScheme(.light)
        .onAppear {
            scanner.onLiveAppsChanged = { updated in
                onLiveAppsUpdated?(updated)
            }
            scanner.bootstrap(seedApps: seedApps)
            scanner.startScanning()
        }
        .onDisappear {
            scanner.stopScanning()
            if !didConfirmExplicitly && scanner.newlyScannedCount > 0 {
                onConfirmApps(scanner.discoveredApps)
            }
        }
    }
}

// MARK: - Sheet Guidata Passo 1: Registrazione Semplice di Tutte le App (Zero Redirect alle Impostazioni)

struct AutoAppScrollCaptureGuideSheet: View {
    @Environment(\.dismiss) private var dismiss
    var canUsePairedNewIPhoneCamera: Bool = false
    var pairedNewIPhoneName: String = ""
    var onOpenScannerOnNewIPhone: (() -> Void)? = nil
    var onArmHomeScreenshotsCapture: () -> Void

    private var targetPhoneLabel: String {
        pairedNewIPhoneName.isEmpty ? "il nuovo iPhone" : pairedNewIPhoneName
    }

    var body: some View {
        NavigationView {
            ZStack {
                AppleTheme.backgroundGradient
                    .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if canUsePairedNewIPhoneCamera, let triggerRemote = onOpenScannerOnNewIPhone {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack(spacing: 10) {
                                    AppleSettingsIcon(systemName: "camera.viewfinder", color: AppleTheme.blue)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Metodo consigliato (5 secondi)")
                                            .font(.system(size: 12, weight: .bold))
                                            .foregroundColor(AppleTheme.blue)
                                        Text("Inquadra la Home col nuovo iPhone")
                                            .font(.system(size: 17, weight: .bold))
                                            .foregroundColor(AppleTheme.textPrimary)
                                    }
                                }

                                Text("Senza attivare alcuna registrazione schermo: tocca il pulsante qui sotto per aprire automaticamente la fotocamera su **\(targetPhoneLabel)**, poi vai sulla schermata Home di questo telefono e sfoglia le pagine delle tue app!")
                                    .font(.system(size: 13))
                                    .foregroundColor(AppleTheme.textSecondary)

                                ApplePrimaryButton(
                                    title: "Apri Fotocamera su \(targetPhoneLabel)",
                                    icon: "camera.viewfinder",
                                    color: AppleTheme.blue
                                ) {
                                    triggerRemote()
                                    dismiss()
                                }
                            }
                            .appleCard(padding: 15, selected: true)
                        }

                        VStack(alignment: .leading, spacing: 14) {
                            HStack(spacing: 10) {
                                AppleSettingsIcon(systemName: "rectangle.stack.fill", color: AppleTheme.teal)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(canUsePairedNewIPhoneCamera ? "Alternativa su questo iPhone" : "Cattura rapida senza impostazioni")
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundColor(AppleTheme.teal)
                                    Text("Screenshot rapidi alle pagine Home")
                                        .font(.system(size: 17, weight: .bold))
                                        .foregroundColor(AppleTheme.textPrimary)
                                }
                            }

                            guideStepRow(
                                number: "1",
                                title: "Vai sulla schermata Home di questo iPhone",
                                detail: "Tocca il pulsante qui sotto e scorri dal basso verso l'alto per uscire sulla tua schermata Home con le icone delle app."
                            )
                            Divider()
                            guideStepRow(
                                number: "2",
                                title: "Fai uno screenshot a ogni pagina delle tue App",
                                detail: "Premi «Tasto Laterale + Volume Su» sulle 2–4 pagine della tua Home (oppure nella «Libreria app» in fondo a destra)."
                            )
                            Divider()
                            guideStepRow(
                                number: "3",
                                title: "Riapri DirectSwitch: lettura automatica!",
                                detail: "Appena torni qui, DirectSwitch legge da sola tutte le app dagli screenshot appena fatti e ti permette di cancellarli dal Rullino con 1 tocco."
                            )

                            if canUsePairedNewIPhoneCamera {
                                AppleSecondaryButton(
                                    title: "Pronto: vado sulla Home a fare gli screenshot",
                                    icon: "iphone.and.arrow.forward",
                                    tint: AppleTheme.teal
                                ) {
                                    onArmHomeScreenshotsCapture()
                                    dismiss()
                                }
                            } else {
                                ApplePrimaryButton(
                                    title: "Pronto: vado sulla Home a fare gli screenshot",
                                    icon: "iphone.and.arrow.forward",
                                    color: AppleTheme.blue
                                ) {
                                    onArmHomeScreenshotsCapture()
                                    dismiss()
                                }
                            }
                        }
                        .appleCard(padding: 16)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                }
            }
            .navigationTitle("Registra tutte le App")
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
                .background(AppleTheme.teal)
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
    var canScanWithPairedIPhone: Bool = false
    var pairedIPhoneName: String = ""
    var onTriggerPairedIPhoneScanner: (() -> Void)? = nil
    var onStartGuidedAutoCapture: (() -> Void)? = nil

    @State private var searchQuery: String = ""
    @State private var searchResults: [InstalledAppRecord] = []
    @State private var isSearching: Bool = false
    @State private var screenshotPickerItems: [PhotosPickerItem] = []
    @State private var isScanningScreenshots: Bool = false
    @State private var ocrStatusNote: String? = nil
    @State private var temporaryCapturedAssetIds: [String] = []
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
                        // PASSO 1: Registrazione semplice di tutte le App installate (Fotocamera Live sul nuovo iPhone oppure Screenshot Home)
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 10) {
                                AppleSettingsIcon(
                                    systemName: canScanWithPairedIPhone ? "camera.viewfinder" : "rectangle.stack.fill",
                                    color: AppleTheme.blue
                                )
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Passo 1: Registra tutte le App installate")
                                        .font(.system(size: 15, weight: .bold))
                                        .foregroundColor(AppleTheme.textPrimary)
                                    Text(canScanWithPairedIPhone
                                         ? "Inquadra la Home col nuovo iPhone (5 sec) o usa screenshot Home"
                                         : "Fai uno screenshot alle pagine della tua Home: lettura automatica!")
                                        .font(.system(size: 12))
                                        .foregroundColor(AppleTheme.textSecondary)
                                }
                                Spacer()
                                InfoCircleButton(
                                    title: "Come registrare il 100% delle App",
                                    message: canScanWithPairedIPhone
                                        ? "• Metodo consigliato (zero impostazioni e zero registrazione schermo): tocca «Inquadra tutte le App col Nuovo iPhone». La fotocamera si aprirà da sola sul nuovo telefono e ti basterà sfogliare le pagine della tua schermata Home davanti all'obiettivo!\n\n• In alternativa: fai 2–3 screenshot alle pagine della tua Home (Tasto Laterale + Volume Su) e tocca «Estrai da Foto»."
                                        : "Non serve attivare alcuna registrazione schermo:\n\n1. Vai sulla schermata Home di questo iPhone.\n2. Premi «Tasto Laterale + Volume Su» sulle 2–4 pagine delle tue App.\n3. Torna qui o tocca «Estrai da Foto»: DirectSwitch legge e seleziona tutte le tue app con le icone ufficiali!"
                                )
                            }

                            if canScanWithPairedIPhone, let triggerRemote = onTriggerPairedIPhoneScanner {
                                Button(action: {
                                    dismiss()
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                                        triggerRemote()
                                    }
                                }) {
                                    HStack(spacing: 8) {
                                        Image(systemName: "camera.viewfinder")
                                            .font(.system(size: 15, weight: .bold))
                                        Text(pairedIPhoneName.isEmpty
                                             ? "Inquadra tutte le App col Nuovo iPhone"
                                             : "Inquadra le App con \(pairedIPhoneName)")
                                            .font(.system(size: 14, weight: .bold))
                                            .lineLimit(1)
                                    }
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 44)
                                    .background(AppleTheme.blue)
                                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                }
                                .buttonStyle(.plain)
                                .disabled(isScanningScreenshots)
                            } else {
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
                                        Image(systemName: "iphone.and.arrow.forward")
                                            .font(.system(size: 15, weight: .bold))
                                        Text("Cattura da screenshot delle pagine Home")
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
                            }

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
                                        Text(isScanningScreenshots ? "Lettura..." : "Estrai da Foto recenti")
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
                                    matching: .any(of: [.images, .videos])
                                ) {
                                    HStack(spacing: 5) {
                                        Image(systemName: "photo.on.rectangle.angled")
                                            .font(.system(size: 12, weight: .semibold))
                                        Text("Scegli screenshot")
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

                            if !temporaryCapturedAssetIds.isEmpty {
                                Button(action: {
                                    let ids = temporaryCapturedAssetIds
                                    Task {
                                        if await iOSInstalledAppsScanner.deleteTemporaryCapturedAssets(localIdentifiers: ids) {
                                            temporaryCapturedAssetIds.removeAll()
                                        }
                                    }
                                }) {
                                    HStack(spacing: 5) {
                                        Image(systemName: "trash")
                                            .font(.system(size: 11, weight: .bold))
                                        Text("Elimina cattura temporanea dal Rullino")
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
            AutoAppScrollCaptureGuideSheet(
                canUsePairedNewIPhoneCamera: canScanWithPairedIPhone,
                pairedNewIPhoneName: pairedIPhoneName,
                onOpenScannerOnNewIPhone: onTriggerPairedIPhoneScanner,
                onArmHomeScreenshotsCapture: {
                    onStartGuidedAutoCapture?()
                }
            )
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
            temporaryCapturedAssetIds = result.allTemporaryAssetIdentifiers
            guard result.generatedScreenshotsCount > 0 else {
                isScanningScreenshots = false
                ocrStatusNote = "Nessuno screenshot recente delle pagine Home trovato (oppure permesso Foto disattivato)."
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
    var onAppsScannedOnReceiver: (([InstalledAppRecord]) -> Void)? = nil
    @AppStorage("directswitch_zero_faceid_setup_done_v1") private var zeroFaceIdSetupDone: Bool = false
    @State private var accountMode: AppleAccountMode = .differentAppleId
    @State private var showZeroFaceIdSteps: Bool = true
    @State private var showFullList: Bool = false
    @State private var showLiveAppCameraScanner: Bool = false

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
                    title: "Inquadra le App sul vecchio telefono (5 sec)",
                    icon: "camera.viewfinder",
                    color: AppleTheme.blue
                ) {
                    showLiveAppCameraScanner = true
                }

                AppleSecondaryButton(
                    title: "Carica elenco App principali in coda",
                    icon: "square.stack.3d.down.right.fill",
                    tint: AppleTheme.teal
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

                Button(action: {
                    showLiveAppCameraScanner = true
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "camera.viewfinder")
                            .font(.system(size: 13, weight: .bold))
                        Text("Manca qualche app? Inquadra la Home del vecchio telefono")
                            .font(.system(size: 12, weight: .bold))
                            .lineLimit(1)
                    }
                    .foregroundColor(AppleTheme.teal)
                    .frame(maxWidth: .infinity)
                    .frame(height: 36)
                    .background(AppleTheme.teal.opacity(0.10))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)

                appsChecklistSection
            }
        }
        .appleCard(padding: 14)
        .sheet(isPresented: $showLiveAppCameraScanner) {
            LiveCameraAppScannerSheet(
                seedApps: installer.apps,
                onConfirmApps: { scanned in
                    installer.appendAdditionalApps(scanned)
                    onAppsScannedOnReceiver?(installer.apps)
                }
            )
        }
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
