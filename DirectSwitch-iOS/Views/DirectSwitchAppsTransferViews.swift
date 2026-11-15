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
        let phoneRef = senderPhoneLabel.isEmpty ? "il vecchio telefono" : senderPhoneLabel
        return "Per non saltare le app dentro le cartelle: su \(phoneRef) scorri fino all'ultima pagina a destra («Libreria app»), tira verso il basso per aprire l'elenco alfabetico A–Z e scorri piano davanti alla fotocamera!"
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
                                    Text("Scorri l'elenco A–Z in Libreria App (o le pagine Home)")
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

                    // Striscia live delle app rilevate (rimovibili con un tocco su x o azzerabili)
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("App registrate (\(scanner.discoveredApps.count))")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(AppleTheme.textPrimary)
                            Spacer()
                            if scanner.newlyScannedCount > 0 {
                                Text("+\(scanner.newlyScannedCount) lette")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(AppleTheme.green)
                                Button("Azzera") {
                                    scanner.resetToSeedApps()
                                }
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(AppleTheme.orange)
                                .buttonStyle(.plain)
                                .padding(.leading, 4)
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

                                Text("Senza attivare alcuna registrazione schermo: tocca il pulsante qui sotto per aprire la fotocamera su **\(targetPhoneLabel)**, poi su questo telefono vai all'ultima pagina a destra (**Libreria app**), scorri verso il basso per aprire l'**elenco A–Z** (così includi anche tutte le app nelle cartelle!) e scorri piano fino a Z.")
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
                                    Text(canUsePairedNewIPhoneCamera ? "Alternativa su questo iPhone" : "Cattura completa senza impostazioni")
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundColor(AppleTheme.teal)
                                    Text("Screenshot all'elenco A–Z in Libreria App")
                                        .font(.system(size: 17, weight: .bold))
                                        .foregroundColor(AppleTheme.textPrimary)
                                }
                            }

                            guideStepRow(
                                number: "1",
                                title: "Apri l'elenco alfabetico A–Z in Libreria App",
                                detail: "Vai sulla Home, scorri fino all'ultima pagina a destra («Libreria app») e tira con un dito verso il basso: vedrai il 100% delle tue app dalla A alla Z (incluse quelle chiuse nelle cartelle!)."
                            )
                            Divider()
                            guideStepRow(
                                number: "2",
                                title: "Fai uno screenshot mentre scorri dalla A alla Z",
                                detail: "Premi «Tasto Laterale + Volume Su» sulle schermate dell'elenco A–Z (oppure sulle pagine della Home)."
                            )
                            Divider()
                            guideStepRow(
                                number: "3",
                                title: "Riapri DirectSwitch: lettura automatica!",
                                detail: "Appena torni qui, DirectSwitch legge con precisione solo le app realmente presenti e ti permette di eliminare gli screenshot dal Rullino con 1 tocco."
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
    var onResetAllCustomApps: (() -> Void)? = nil

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
                            HStack(spacing: 10) {
                                Text("Passo 2: App selezionate (\(selectedCount)/\(appsCatalog.count))")
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundColor(AppleTheme.textPrimary)
                                Spacer()
                                Button(action: resetToVerifiedInstalledOnly) {
                                    HStack(spacing: 3) {
                                        Image(systemName: "arrow.counterclockwise")
                                            .font(.system(size: 11, weight: .bold))
                                        Text("Rileva da zero")
                                            .font(.system(size: 12, weight: .semibold))
                                    }
                                    .foregroundColor(AppleTheme.orange)
                                }
                                .buttonStyle(.plain)

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
        let verified = iOSInstalledAppsScanner.filterFalsePositiveProbesOnSender(discovered)
        var newlyAdded = 0
        for app in verified {
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
        if !verified.isEmpty {
            iOSInstalledAppsScanner.appendCustomApps(verified)
        }
        isScanningScreenshots = false
        if newlyAdded > 0 {
            ocrStatusNote = "Estratti \(generatedFramesCount) screenshot automatici: aggiunte \(newlyAdded) nuove app (totale \(appsCatalog.count))!"
        } else if !verified.isEmpty {
            ocrStatusNote = "Analizzati \(generatedFramesCount) fotogrammi: tutte le app trovate sono già selezionate."
        } else {
            ocrStatusNote = "Analizzati \(generatedFramesCount) fotogrammi: nessuna nuova app rilevata."
        }
    }

    private func resetToVerifiedInstalledOnly() {
        iOSInstalledAppsScanner.clearSavedCustomApps()
        deselectedAppIds.removeAll()
        onResetAllCustomApps?()
        let base = iOSInstalledAppsScanner.scanLocallyInstalledApps()
        appsCatalog = base
        searchResults = []
        ocrStatusNote = "Elenco ripristinato alle sole app verificate localmente (\(base.count)). Ora puoi ripetere la scansione dalla Libreria app A–Z."
        Task {
            let enriched = await iOSAppStoreCatalogResolver.enrichAppsWithStoreMetadata(base)
            if !enriched.isEmpty {
                appsCatalog = enriched
            }
        }
    }
}

// MARK: - Card Ricevente: Istruzioni TeamViewer Style + Installazione In-App in Basso (`SKOverlay` / StoreKit)

fileprivate enum ReceiverAppGuideKind: Identifiable {
    case faceIdPasscode
    case mediaPurchasesPassword

    var id: String {
        switch self {
        case .faceIdPasscode: return "faceid"
        case .mediaPurchasesPassword: return "media"
        }
    }
}

struct ReceiverAppsAutoInstallCard: View {
    private enum AppleAccountMode: String {
        case differentAppleId
        case sameAppleId
    }

    let incomingApps: [InstalledAppRecord]
    @ObservedObject var installer: iOSSequentialAppInstaller
    var onAppsScannedOnReceiver: (([InstalledAppRecord]) -> Void)? = nil

    @AppStorage("directswitch_zero_faceid_setup_done_v2") private var persistedSetupConfirmed: Bool = false
    @State private var accountMode: AppleAccountMode = .differentAppleId
    @State private var step1FaceIdChecked: Bool = false
    @State private var step2MediaPasswordChecked: Bool = false
    @State private var showSetupChecklist: Bool = true
    @State private var activeGuideSheet: ReceiverAppGuideKind? = nil
    @State private var showFullList: Bool = false
    @State private var showMissingCatalogList: Bool = false
    @State private var showLiveAppCameraScanner: Bool = false

    private var queueableApps: [InstalledAppRecord] {
        installer.queueableApps
    }

    private var missingApps: [InstalledAppRecord] {
        installer.missingCatalogApps
    }

    private var visibleApps: [InstalledAppRecord] {
        showFullList ? queueableApps : Array(queueableApps.prefix(10))
    }

    private var alreadyCount: Int {
        installer.alreadyInstalledIds.count
    }

    private var pendingCount: Int {
        installer.pendingInstallableCount
    }

    private var downloadingCount: Int {
        installer.activeDownloadingIds.count
    }

    private var bothPermissionsChecked: Bool {
        step1FaceIdChecked && step2MediaPasswordChecked
    }

    private var isAppsLauncherUnlocked: Bool {
        accountMode == .sameAppleId || (persistedSetupConfirmed && !showSetupChecklist)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            headerSection

            accountModeSelectionSection

            if accountMode == .sameAppleId {
                sameAppleIdSection
            } else {
                teamViewerPermissionsSetupCard
            }

            if installer.apps.isEmpty {
                emptyAppsActions
            } else if !isAppsLauncherUnlocked {
                lockedPreviewBanner
            } else {
                activeInstallerSection

                if let note = installer.installerStatusNote, !note.isEmpty {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "info.circle.fill")
                            .font(.system(size: 13))
                            .foregroundColor(AppleTheme.orange)
                            .padding(.top, 1)
                        Text(note)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(AppleTheme.textSecondary)
                    }
                    .padding(10)
                    .background(AppleTheme.orange.opacity(0.09))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }

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

                if !missingApps.isEmpty {
                    missingCatalogAppsSection
                }
            }
        }
        .appleCard(padding: 15)
        .sheet(isPresented: $showLiveAppCameraScanner) {
            LiveCameraAppScannerSheet(
                seedApps: installer.apps,
                onConfirmApps: { scanned in
                    installer.appendAdditionalApps(scanned)
                    onAppsScannedOnReceiver?(installer.apps)
                }
            )
        }
        .sheet(item: $activeGuideSheet) { kind in
            ApplePermissionStepGuideSheet(
                kind: kind,
                isAlreadyChecked: kind == .faceIdPasscode ? step1FaceIdChecked : step2MediaPasswordChecked,
                onConfirmStepDone: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        if kind == .faceIdPasscode {
                            step1FaceIdChecked = true
                        } else {
                            step2MediaPasswordChecked = true
                        }
                    }
                }
            )
        }
        .onAppear {
            if persistedSetupConfirmed {
                step1FaceIdChecked = true
                step2MediaPasswordChecked = true
                showSetupChecklist = false
            } else {
                showSetupChecklist = true
            }
            installer.configure(with: incomingApps)
        }
        .onChange(of: incomingApps) { updated in
            installer.configure(with: updated)
        }
    }

    // MARK: - Intestazione chiara

    private var headerSection: some View {
        HStack(spacing: 10) {
            AppleSettingsIcon(systemName: "square.grid.2x2.fill", color: AppleTheme.blue)
            VStack(alignment: .leading, spacing: 3) {
                Text(installer.apps.isEmpty
                     ? "App ricevute — Pronte da scaricare"
                     : "App ricevute pronte da scaricare (\(installer.apps.count))")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(AppleTheme.textPrimary)

                if !installer.apps.isEmpty {
                    let subtitle = downloadingCount > 0
                        ? "\(pendingCount) in coda • \(downloadingCount) in download • \(alreadyCount) installate"
                        : "\(pendingCount) pronte su App Store • \(alreadyCount) già presenti"
                    Text(subtitle)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(AppleTheme.textSecondary)
                }
            }
            Spacer()
            InfoCircleButton(
                title: "Come funziona il download delle App",
                message: "• Le app NON vengono scaricate automaticamente in blocco da sole: iOS richiede il tocco sul tasto «Ottieni» per sicurezza Apple.\n\n• Se hai un NUOVO / ALTRO ID Apple, completa e spunta in blu i 2 passaggi iniziali, tocca «Fatto • Chiudi» e poi avvia la barra in basso: le app restano visibili in basso mentre si scaricano una dietro l'altra senza mai uscire nell'App Store.\n\n• Premi «Interrompi» in qualsiasi momento per fermare la coda."
            )
        }
    }

    // MARK: - Scelta ID Apple con descrizioni esplicite (soprattutto Nuovo ID Apple)

    private var accountModeSelectionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Quale ID Apple è attivo su questo nuovo iPhone?")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(AppleTheme.textPrimary)

            VStack(spacing: 8) {
                appleAccountOptionCard(
                    title: "Altro Apple ID / Nuovo Apple ID",
                    badge: "Richiede i 2 passaggi",
                    subtitle: "Hai configurato questo iPhone con un nuovo Apple Account diverso dal vecchio telefono: le app gratuite vanno associate e scaricate su questo account seguendo i 2 passaggi qui sotto.",
                    icon: "person.crop.circle.badge.plus",
                    mode: .differentAppleId
                )

                appleAccountOptionCard(
                    title: "Stesso Apple ID del vecchio iPhone",
                    badge: "Storico già collegato",
                    subtitle: "Usi lo stesso Apple Account di prima: tutte le tue app sono già nello storico «Acquistate» su App Store (Profilo in alto a destra → App → Non su questo iPhone).",
                    icon: "icloud.and.arrow.down",
                    mode: .sameAppleId
                )
            }
        }
    }

    private func appleAccountOptionCard(
        title: String,
        badge: String,
        subtitle: String,
        icon: String,
        mode: AppleAccountMode
    ) -> some View {
        let isSelected = accountMode == mode
        return Button(action: {
            withAnimation(.easeInOut(duration: 0.18)) {
                accountMode = mode
                if mode == .differentAppleId && !persistedSetupConfirmed {
                    showSetupChecklist = true
                }
            }
        }) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundColor(isSelected ? AppleTheme.blue : AppleTheme.textTertiary)
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Image(systemName: icon)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(isSelected ? AppleTheme.blue : AppleTheme.textSecondary)
                        Text(title)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(AppleTheme.textPrimary)
                        Spacer()
                        Text(badge)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(isSelected ? AppleTheme.blue : AppleTheme.textSecondary)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(isSelected ? AppleTheme.blue.opacity(0.12) : AppleTheme.inputSurface)
                            .clipShape(Capsule())
                    }

                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundColor(AppleTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }
            }
            .padding(11)
            .background(isSelected ? AppleTheme.cardSelected : AppleTheme.inputSurface.opacity(0.55))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(isSelected ? AppleTheme.blue.opacity(0.55) : AppleTheme.cardBorder, lineWidth: isSelected ? 1.3 : 0.8)
            )
        }
        .buttonStyle(.plain)
    }

    private var sameAppleIdSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Con lo stesso ID Apple puoi aprire App Store sulla scheda **«Non su questo iPhone»** e toccare la nuvola ☁️ accanto alle app mancanti, oppure avviare la barra qui sotto.")
                .font(.system(size: 12.5))
                .foregroundColor(AppleTheme.textSecondary)

            AppleSecondaryButton(
                title: "Apri App Store → Profilo → App → Non su questo iPhone",
                icon: "icloud.and.arrow.down.fill",
                tint: AppleTheme.teal
            ) {
                iOSPermissionsHelper.openAppStorePurchasedSection()
            }
        }
        .padding(12)
        .background(AppleTheme.teal.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .stroke(AppleTheme.teal.opacity(0.32), lineWidth: 1.0)
        )
    }

    // MARK: - Checklist Stile TeamViewer Mac (2 spunte blu + conferma automatica prima di «Fatto»)

    @ViewBuilder
    private var teamViewerPermissionsSetupCard: some View {
        if persistedSetupConfirmed && !showSetupChecklist {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(AppleTheme.blue)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Istruzioni confermate (2/2 spunte attive)")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(AppleTheme.textPrimary)
                    Text("Face ID App Store disattivato • Password download gratuiti: Non richiedere mai")
                        .font(.system(size: 11))
                        .foregroundColor(AppleTheme.textSecondary)
                }
                Spacer()
                Button("Rivedi") {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        showSetupChecklist = true
                    }
                }
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(AppleTheme.blue)
                .buttonStyle(.plain)
            }
            .padding(12)
            .background(AppleTheme.blue.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .stroke(AppleTheme.blue.opacity(0.35), lineWidth: 1.0)
            )
        } else {
            let checkedCount = (step1FaceIdChecked ? 1 : 0) + (step2MediaPasswordChecked ? 1 : 0)

            VStack(alignment: .leading, spacing: 11) {
                HStack(spacing: 8) {
                    Image(systemName: bothPermissionsChecked ? "checkmark.shield.fill" : "checklist.checked")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(bothPermissionsChecked ? AppleTheme.blue : AppleTheme.orange)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Passo obbligatorio prima di scaricare le App")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(AppleTheme.textPrimary)
                        Text("Spunta entrambe le voci in blu, poi premi «Fatto • Chiudi» per caricare le app")
                            .font(.system(size: 11.5))
                            .foregroundColor(AppleTheme.textSecondary)
                    }
                    Spacer()
                    Text("\(checkedCount)/2")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundColor(bothPermissionsChecked ? .white : AppleTheme.orange)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(bothPermissionsChecked ? AppleTheme.blue : AppleTheme.orange.opacity(0.14))
                        .clipShape(Capsule())
                }

                // Riga 1 (TeamViewer-style): Face ID / Touch ID e codice
                teamViewerPermissionRow(
                    number: 1,
                    title: "Face ID / Touch ID e codice",
                    summary: "Apri **Impostazioni** (icona grigia sulla Home) → **Face ID e codice** (o **Touch ID e codice**) → **DISATTIVA** «iTunes Store e App Store».",
                    buttonTitle: "Istruzioni Face ID / Touch ID",
                    buttonIcon: "faceid",
                    isChecked: step1FaceIdChecked,
                    onToggleCheck: {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            step1FaceIdChecked.toggle()
                        }
                    },
                    onOpenInstructions: {
                        activeGuideSheet = .faceIdPasscode
                    }
                )

                // Riga 2 (TeamViewer-style): File multimediali e acquisti -> Non richiedere mai
                teamViewerPermissionRow(
                    number: 2,
                    title: "Password File multimediali e acquisti",
                    summary: "Sempre in **Impostazioni** → tocca il **tuo Nome (Apple Account)** in alto → **File multimediali e acquisti → Impostazioni password** → sotto «Download gratuiti» scegli **«Non richiedere mai»** *(appare solo dopo il punto 1)*.",
                    buttonTitle: "Istruzioni File multimediali e acquisti",
                    buttonIcon: "key.fill",
                    isChecked: step2MediaPasswordChecked,
                    onToggleCheck: {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            step2MediaPasswordChecked.toggle()
                        }
                    },
                    onOpenInstructions: {
                        activeGuideSheet = .mediaPurchasesPassword
                    }
                )

                // Conferma automatica quando entrambe le spunte sono blu!
                if bothPermissionsChecked {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(AppleTheme.blue)
                        Text("Confermato automaticamente: entrambe le spunte sono attive in blu! Ora puoi premere «Fatto • Chiudi».")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(AppleTheme.blue)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AppleTheme.blue.opacity(0.11))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }

                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        persistedSetupConfirmed = true
                        showSetupChecklist = false
                    }
                }) {
                    HStack(spacing: 7) {
                        Image(systemName: bothPermissionsChecked ? "checkmark.circle.fill" : "lock.fill")
                            .font(.system(size: 14, weight: .bold))
                        Text(bothPermissionsChecked
                             ? "Fatto • Chiudi e carica le \(queueableApps.count) app"
                             : "Spunta entrambi i passaggi in blu per sbloccare «Fatto»")
                            .font(.system(size: 13.5, weight: .bold))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(bothPermissionsChecked ? AppleTheme.blue : AppleTheme.textTertiary.opacity(0.55))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(!bothPermissionsChecked)
            }
            .padding(13)
            .background(bothPermissionsChecked ? AppleTheme.blue.opacity(0.06) : AppleTheme.orange.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke((bothPermissionsChecked ? AppleTheme.blue : AppleTheme.orange).opacity(0.45), lineWidth: 1.2)
            )
        }
    }

    private func teamViewerPermissionRow(
        number: Int,
        title: String,
        summary: String,
        buttonTitle: String,
        buttonIcon: String,
        isChecked: Bool,
        onToggleCheck: @escaping () -> Void,
        onOpenInstructions: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 10) {
                Button(action: onToggleCheck) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(isChecked ? AppleTheme.blue : Color.white)
                            .frame(width: 24, height: 24)
                            .overlay(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .stroke(isChecked ? AppleTheme.blue : AppleTheme.textTertiary, lineWidth: 1.6)
                            )
                        if isChecked {
                            Image(systemName: "checkmark")
                                .font(.system(size: 13, weight: .heavy))
                                .foregroundColor(.white)
                        }
                    }
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 1) {
                    Text("\(number). \(title)")
                        .font(.system(size: 13.5, weight: .bold))
                        .foregroundColor(AppleTheme.textPrimary)
                    Text(isChecked ? "Spunta blu attiva" : "Tocca il riquadro a sinistra quando hai fatto")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(isChecked ? AppleTheme.blue : AppleTheme.orange)
                }

                Spacer()

                Button(action: onToggleCheck) {
                    Text(isChecked ? "Attivato ✓" : "In attesa")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(isChecked ? .white : AppleTheme.orange)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(isChecked ? AppleTheme.blue : AppleTheme.orange.opacity(0.14))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }

            Text(.init(summary))
                .font(.system(size: 12))
                .foregroundColor(AppleTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Button(action: onOpenInstructions) {
                    HStack(spacing: 5) {
                        Image(systemName: buttonIcon)
                            .font(.system(size: 12, weight: .bold))
                        Text(buttonTitle)
                            .font(.system(size: 12, weight: .bold))
                            .lineLimit(1)
                    }
                    .foregroundColor(AppleTheme.blue)
                    .padding(.horizontal, 11)
                    .frame(height: 34)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .stroke(AppleTheme.blue.opacity(0.32), lineWidth: 0.9)
                    )
                }
                .buttonStyle(.plain)

                if !isChecked {
                    Button(action: onToggleCheck) {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .bold))
                            Text("Conferma spunta blu")
                                .font(.system(size: 12, weight: .bold))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 11)
                        .frame(height: 34)
                        .background(AppleTheme.blue)
                        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(11)
        .background(Color.white.opacity(0.92))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(isChecked ? AppleTheme.blue.opacity(0.65) : AppleTheme.cardBorder, lineWidth: isChecked ? 1.4 : 0.8)
        )
    }

    private var lockedPreviewBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "lock.circle.fill")
                .font(.system(size: 22))
                .foregroundColor(AppleTheme.textTertiary)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(queueableApps.count) App pronte in attesa di conferma")
                    .font(.system(size: 13.5, weight: .bold))
                    .foregroundColor(AppleTheme.textSecondary)
                Text("Completa i 2 passaggi sopra (spunta blu 1 e 2) e premi «Fatto • Chiudi» per caricare le app senza errori.")
                    .font(.system(size: 11.5))
                    .foregroundColor(AppleTheme.textSecondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppleTheme.inputSurface.opacity(0.75))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var emptyAppsActions: some View {
        VStack(spacing: 8) {
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
        }
    }

    // MARK: - Pannello Coda Attiva + Avvio Download In-App

    @ViewBuilder
    private var activeInstallerSection: some View {
        if installer.isRunningSequence {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    if let active = installer.currentActiveApp {
                        AppIconThumbnailView(iconUrl: active.iconUrl, size: 36)
                    } else {
                        ProgressView().tint(AppleTheme.blue)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(installer.isWaitingInlineNextConfirmation
                             ? "In attesa — App \(installer.currentQueuePosition) di \(installer.totalQueueCount)"
                             : "Download in coda: App \(installer.currentQueuePosition) di \(installer.totalQueueCount)")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(AppleTheme.blue)
                        Text(installer.currentActiveApp?.appName ?? "Preparazione...")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(AppleTheme.textPrimary)
                            .lineLimit(1)
                    }

                    Spacer()

                    Button(action: {
                        installer.stopSequence()
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "stop.circle.fill")
                                .font(.system(size: 12, weight: .bold))
                            Text("Interrompi")
                                .font(.system(size: 12, weight: .bold))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 7)
                        .background(AppleTheme.red)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }

                Text(installer.isWaitingInlineNextConfirmation
                     ? "Premi «Scarica prossima →» nella barra in basso per aprire la scheda successiva, oppure «Interrompi» per fermare tutto."
                     : "Usa il mini-banner Apple e i comandi nella barra in basso (puoi interrompere o saltare in qualunque momento senza mai uscire in App Store).")
                    .font(.system(size: 11.5))
                    .foregroundColor(AppleTheme.textSecondary)
            }
            .padding(12)
            .background(AppleTheme.cardSelected)
            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .stroke(AppleTheme.blue.opacity(0.45), lineWidth: 1.1)
            )
        } else if pendingCount > 0 {
            VStack(alignment: .leading, spacing: 7) {
                ApplePrimaryButton(
                    title: "Carica e scarica tutte le \(pendingCount) App in basso",
                    icon: "arrow.down.app.fill",
                    color: AppleTheme.blue
                ) {
                    installer.startAutomaticSequence()
                }
                Text("Le app compaiono una dopo l'altra nella barra in basso con lo stato di scaricamento in tempo reale (nessuna apertura incontrollata dell'App Store e tasto «Interrompi» sempre visibile).")
                    .font(.system(size: 11))
                    .foregroundColor(AppleTheme.textSecondary)
            }
        } else {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundColor(AppleTheme.green)
                Text(queueableApps.isEmpty
                     ? "Nessuna app con scheda App Store pronta in elenco."
                     : "Tutte le app selezionate sono state avviate o sono già installate!")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(AppleTheme.green)
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Elenco App Scaricabili in-App

    private var appsChecklistSection: some View {
        VStack(spacing: 8) {
            VStack(spacing: 0) {
                ForEach(Array(visibleApps.enumerated()), id: \.element.id) { index, app in
                    let isAlready = installer.alreadyInstalledIds.contains(app.id)
                    let isDownloading = installer.activeDownloadingIds.contains(app.id)
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

                        VStack(alignment: .leading, spacing: 2) {
                            Text(app.appName)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(AppleTheme.textPrimary)
                                .lineLimit(1)
                            if isDownloading && !isAlready {
                                Text("In download su questo iPhone...")
                                    .font(.system(size: 10.5, weight: .semibold))
                                    .foregroundColor(AppleTheme.blue)
                            }
                        }

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
                                    Image(systemName: isDownloading ? "arrow.down.circle.fill" : (isDone ? "checkmark.circle.fill" : "icloud.and.arrow.down"))
                                        .font(.system(size: 12, weight: .semibold))
                                    Text(isDownloading ? "In download" : (isDone ? "Avviata" : "Ottieni"))
                                        .font(.system(size: 12, weight: .bold))
                                }
                                .foregroundColor(isDownloading ? AppleTheme.blue : (isDone ? AppleTheme.teal : AppleTheme.blue))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(isDownloading ? AppleTheme.blue.opacity(0.12) : (isDone ? AppleTheme.teal.opacity(0.12) : AppleTheme.cardSelected))
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

            if queueableApps.count > 10 {
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showFullList.toggle()
                    }
                }) {
                    HStack(spacing: 4) {
                        Text(showFullList ? "Mostra meno" : "Mostra tutte le \(queueableApps.count) app")
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

    // MARK: - App non presenti nel catalogo IT (mai aperte in automatico!)

    private var missingCatalogAppsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: {
                withAnimation(.easeInOut(duration: 0.18)) {
                    showMissingCatalogList.toggle()
                }
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "questionmark.app.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(AppleTheme.textSecondary)
                    Text("Non trovate nel catalogo App Store IT (\(missingApps.count))")
                        .font(.system(size: 12.5, weight: .bold))
                        .foregroundColor(AppleTheme.textSecondary)
                    Spacer()
                    Image(systemName: showMissingCatalogList ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(AppleTheme.textTertiary)
                }
            }
            .buttonStyle(.plain)

            Text("Escluse dalla sequenza automatica: non aprono mai l'App Store esterno da sole.")
                .font(.system(size: 11))
                .foregroundColor(AppleTheme.textTertiary)

            if showMissingCatalogList {
                VStack(spacing: 6) {
                    ForEach(missingApps) { app in
                        HStack(spacing: 10) {
                            AppIconThumbnailView(iconUrl: app.iconUrl, size: 30)
                            Text(app.appName)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(AppleTheme.textPrimary)
                                .lineLimit(1)
                            Spacer()
                            Button("Cerca") {
                                iOSPermissionsHelper.searchAppOnAppStore(appName: app.appName)
                            }
                            .font(.system(size: 11.5, weight: .bold))
                            .foregroundColor(AppleTheme.blue)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(AppleTheme.cardSelected)
                            .clipShape(Capsule())
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.top, 4)
            }
        }
        .padding(11)
        .background(AppleTheme.inputSurface.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - Sheet Istruzioni Dedicate per Passo 1 (Face ID) e Passo 2 (Non richiedere mai)

private struct ApplePermissionStepGuideSheet: View {
    @Environment(\.dismiss) private var dismiss
    let kind: ReceiverAppGuideKind
    let isAlreadyChecked: Bool
    let onConfirmStepDone: () -> Void

    private var navTitle: String {
        switch kind {
        case .faceIdPasscode:
            return "1. Face ID / Touch ID e codice"
        case .mediaPurchasesPassword:
            return "2. Password File multimediali"
        }
    }

    var body: some View {
        NavigationView {
            ZStack {
                AppleTheme.backgroundGradient.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 10) {
                                AppleSettingsIcon(
                                    systemName: kind == .faceIdPasscode ? "faceid" : "key.fill",
                                    color: AppleTheme.blue
                                )
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(navTitle)
                                        .font(.system(size: 17, weight: .bold))
                                        .foregroundColor(AppleTheme.textPrimary)
                                    Text("Percorso dentro l'app Impostazioni di iPhone")
                                        .font(.system(size: 12))
                                        .foregroundColor(AppleTheme.textSecondary)
                                }
                            }

                            Text("Apple iOS non consente alle app di aprire direttamente questa schermata di sistema: torna sulla Home e apri l'icona grigia **Impostazioni** di iPhone.")
                                .font(.system(size: 12.5))
                                .foregroundColor(AppleTheme.textSecondary)
                        }
                        .appleCard(padding: 14, selected: true)

                        VStack(alignment: .leading, spacing: 12) {
                            if kind == .faceIdPasscode {
                                stepRow(1, "Apri l'app **Impostazioni** (ingranaggio grigio sulla Home).")
                                Divider()
                                stepRow(2, "Scorri fino a **Face ID e codice** *(oppure Touch ID e codice su iPhone con tasto Home)* e inserisci il codice dell'iPhone.")
                                Divider()
                                stepRow(3, "**Spegni l'interruttore «iTunes Store e App Store»** (deve diventare grigio/spento). Questo sblocca anche l'opzione «Non richiedere mai» del punto 2.")
                            } else {
                                stepRow(1, "Apri l'app **Impostazioni** e tocca il **tuo Nome (Apple Account)** in cima alla pagina.")
                                Divider()
                                stepRow(2, "Tocca **File multimediali e acquisti** → **Impostazioni password**.\n*(Se «Impostazioni password» non compare, devi prima spegnere «iTunes Store e App Store» nel punto 1).*")
                                Divider()
                                stepRow(3, "Sotto la sezione **Download gratuiti**, disattiva «Richiedi password» oppure seleziona **«Non richiedere mai»**.")
                            }
                        }
                        .appleCard(padding: 15)

                        Button(action: {
                            onConfirmStepDone()
                            dismiss()
                        }) {
                            HStack(spacing: 8) {
                                Image(systemName: isAlreadyChecked ? "checkmark.circle.fill" : "checkmark.square.fill")
                                    .font(.system(size: 15, weight: .bold))
                                Text(isAlreadyChecked
                                     ? "Passaggio già confermato • Chiudi"
                                     : (kind == .faceIdPasscode
                                        ? "Fatto: ho disattivato Face ID per App Store ✓"
                                        : "Fatto: ho scelto «Non richiedere mai» ✓"))
                                    .font(.system(size: 14, weight: .bold))
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 46)
                            .background(isAlreadyChecked ? AppleTheme.green : AppleTheme.blue)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(16)
                }
            }
            .navigationTitle(navTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Chiudi") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.light)
    }

    private func stepRow(_ index: Int, _ markdownText: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(index)")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .frame(width: 24, height: 24)
                .background(AppleTheme.blue)
                .clipShape(Circle())
            Text(.init(markdownText))
                .font(.system(size: 13.5))
                .foregroundColor(AppleTheme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Barra Inferiore Fissa di Avanzamento e Controllo Download (`SKOverlay` / StoreKit in-app + Interrompi immediato)

struct FastOverlayFloatingControlBar: View {
    @ObservedObject var installer: iOSSequentialAppInstaller

    private var doneOrDownloadingCount: Int {
        installer.dockTrackedApps.filter {
            installer.alreadyInstalledIds.contains($0.id) || installer.activeDownloadingIds.contains($0.id) || installer.completedIds.contains($0.id)
        }.count
    }

    private var progressFraction: Double {
        guard installer.totalQueueCount > 0 else { return 0 }
        return min(1.0, max(0.05, Double(installer.currentQueuePosition) / Double(installer.totalQueueCount)))
    }

    private var dockPreviewApps: [InstalledAppRecord] {
        // Mostra per prime l'app attiva, quelle in scaricamento e le più recenti già installate
        var ordered: [InstalledAppRecord] = []
        if let active = installer.currentActiveApp {
            ordered.append(active)
        }
        for app in installer.apps.reversed() where app.id != installer.currentActiveApp?.id {
            if installer.activeDownloadingIds.contains(app.id) || installer.alreadyInstalledIds.contains(app.id) {
                ordered.append(app)
            }
        }
        return Array(ordered.prefix(10))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            // Riga alta: app attuale + contatore + tasto rosso INTERROMPI sempre accessibile
            HStack(spacing: 10) {
                if let active = installer.currentActiveApp {
                    AppIconThumbnailView(iconUrl: active.iconUrl, size: 34)
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(installer.isSingleOverlaySession
                             ? "Download App"
                             : "App \(installer.currentQueuePosition) di \(installer.totalQueueCount)")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(AppleTheme.blue)

                        if !installer.activeDownloadingIds.isEmpty {
                            Text("• \(installer.activeDownloadingIds.count) in download")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(AppleTheme.teal)
                        }

                        if !installer.alreadyInstalledIds.isEmpty {
                            Text("• \(installer.alreadyInstalledIds.count) installate")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(AppleTheme.green)
                        }

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
                    HStack(spacing: 4) {
                        Image(systemName: "stop.circle.fill")
                            .font(.system(size: 12, weight: .bold))
                        Text("Interrompi")
                            .font(.system(size: 12, weight: .bold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(AppleTheme.red)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }

            // Barra di avanzamento coda
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

            // Striscia live delle app in scaricamento una per una / installate
            if !dockPreviewApps.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(dockPreviewApps) { item in
                            let isInstalled = installer.alreadyInstalledIds.contains(item.id)
                            let isDownloading = installer.activeDownloadingIds.contains(item.id)
                            let isCurrent = installer.currentActiveApp?.id == item.id

                            HStack(spacing: 5) {
                                AppIconThumbnailView(iconUrl: item.iconUrl, size: 20)
                                Text(item.appName)
                                    .font(.system(size: 10.5, weight: .semibold))
                                    .foregroundColor(AppleTheme.textPrimary)
                                    .lineLimit(1)
                                    .frame(maxWidth: 74, alignment: .leading)
                                if isInstalled {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundColor(AppleTheme.green)
                                } else if isDownloading {
                                    ProgressView()
                                        .scaleEffect(0.55)
                                        .tint(AppleTheme.blue)
                                } else if isCurrent {
                                    Image(systemName: "arrow.down.circle")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundColor(AppleTheme.orange)
                                }
                            }
                            .padding(.horizontal, 7)
                            .padding(.vertical, 4)
                            .background(isInstalled ? AppleTheme.green.opacity(0.10) : (isCurrent ? AppleTheme.blue.opacity(0.10) : AppleTheme.inputSurface))
                            .clipShape(Capsule())
                        }
                    }
                }
            }

            Text(installer.isWaitingInlineNextConfirmation
                 ? "Tocca «Apri prossima app» per continuare oppure «Interrompi» per chiudere senza aprire altre schede."
                 : "1. Tocca «Ottieni» nel banner Apple sotto  •  2. Premi «Prossima →» per accodare la successiva (iOS richiede il tocco per sicurezza)")
                .font(.system(size: 10.5))
                .foregroundColor(AppleTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

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

                if !installer.isWaitingInlineNextConfirmation && !installer.isOverlayVisible && !installer.isLoadingInlineCard {
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

                if installer.isWaitingInlineNextConfirmation {
                    Button(action: {
                        installer.resumePausedInlineNextApp()
                    }) {
                        HStack(spacing: 6) {
                            Text("Apri \(installer.currentActiveApp?.appName ?? "prossima")")
                                .font(.system(size: 13, weight: .bold))
                                .lineLimit(1)
                            Image(systemName: "arrow.right.circle.fill")
                                .font(.system(size: 14, weight: .bold))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .background(AppleTheme.blue)
                        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                    }
                    .buttonStyle(.plain)
                } else {
                    Button(action: {
                        installer.confirmCurrentAndAdvance()
                    }) {
                        HStack(spacing: 6) {
                            Text(installer.isSingleOverlaySession ? "Fatto • Chiudi" : "Prossima App →")
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
