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
        .preferredColorScheme(.light)
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
    @Binding var includeReminders: Bool
    @Binding var includeDocuments: Bool
    @Binding var includeWhatsApp: Bool

    var onScanExactCounts: () -> Void
    var onAddFilesOrWhatsApp: () -> Void
    var onClearStagedFiles: () -> Void
    var onOpenProSheet: () -> Void
    var onChangePairedDevice: () -> Void
    var onStartCopy: () -> Void

    @State private var didAutoRequestPermissions: Bool = false

    private var hasAnyPermissionDenied: Bool {
        guard let s = scanSummary else { return false }
        return s.contactsDenied || s.photosDenied || s.calendarsDenied || s.remindersDenied
    }

    private var allSelected: Bool {
        includeContacts && includePhotos && includeVideos && includeCalendars && includeReminders && includeDocuments && includeWhatsApp
    }

    private var anySelected: Bool {
        includeContacts || includePhotos || includeVideos || includeCalendars || includeReminders || includeDocuments || includeWhatsApp
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
                        includeReminders = target
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

                if hasAnyPermissionDenied {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.shield.fill")
                                .foregroundColor(AppleTheme.orange)
                            Text("Alcuni permessi sono disattivati su questo iPhone")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(AppleTheme.textPrimary)
                        }
                        Text("Per caricare tutti i Contatti, le Foto/Video e i Calendari senza blocchi, attiva tutti i permessi nella pagina di DirectSwitch in Impostazioni.")
                            .font(.system(size: 13))
                            .foregroundColor(AppleTheme.textSecondary)
                        AppleSecondaryButton(
                            title: "Abilita Contatti e Foto in Impostazioni",
                            icon: "gearshape.fill",
                            tint: AppleTheme.orange
                        ) {
                            iOSPermissionsHelper.openDirectSwitchSettings()
                        }
                    }
                    .appleCard(padding: 14)
                }

                // Lista pulita con sottotitoli racchiusi in ⓘ
                VStack(spacing: 0) {
                    CleanCategoryToggleRow(
                        icon: "person.crop.circle.fill",
                        iconColor: AppleTheme.blue,
                        title: "Rubrica contatti",
                        countBadge: badgeForCount(scanSummary?.contactsCount, unit: "contatti"),
                        infoMessage: "Trasferisce tutti i contatti completi di foto profilo, compleanni, indirizzi di casa/lavoro, azienda, siti web ed etichette dei numeri unendo eventuali duplicati.",
                        isOn: $includeContacts
                    )

                    Divider().padding(.leading, 58)

                    CleanCategoryToggleRow(
                        icon: "photo.fill",
                        iconColor: AppleTheme.orange,
                        title: "Foto, Live Photos e Album",
                        countBadge: badgeForPhotos(
                            count: scanSummary?.photosCount,
                            liveCount: scanSummary?.livePhotosCount,
                            bytes: scanSummary?.photosBytes
                        ),
                        infoMessage: "Copia tutte le foto nella qualità originale HEIC/RAW preservando Live Photos animate (.HEIC + .MOV), Preferiti (❤️), data di scatto, posizione GPS e Album utente.",
                        isOn: $includePhotos
                    )

                    Divider().padding(.leading, 58)

                    CleanCategoryToggleRow(
                        icon: "video.fill",
                        iconColor: AppleTheme.red,
                        title: "Video originali",
                        countBadge: badgeForMedia(count: scanSummary?.videosCount, bytes: scanSummary?.videosBytes, unit: "video"),
                        infoMessage: "Copia tutti i video in risoluzione originale (inclusi 4K 60fps e Slow-Motion) in streaming su disco senza compressione.",
                        isOn: $includeVideos
                    )

                    Divider().padding(.leading, 58)

                    CleanCategoryToggleRow(
                        icon: "calendar",
                        iconColor: AppleTheme.slate,
                        title: "Calendari",
                        countBadge: badgeForCount(scanSummary?.calendarEventsCount, unit: "eventi"),
                        infoMessage: "Importa lo storico completo degli appuntamenti (-10/+10 anni) con ricorrenze annuali/settimanali e avvisi.",
                        isOn: $includeCalendars
                    )

                    Divider().padding(.leading, 58)

                    CleanCategoryToggleRow(
                        icon: "checklist",
                        iconColor: AppleTheme.blue,
                        title: "Promemoria",
                        countBadge: badgeForCount(scanSummary?.remindersCount, unit: "promemoria"),
                        infoMessage: "Trasferisce le tue liste di Promemoria Apple con scadenze, note, priorità e stato di completamento senza usare iCloud.",
                        isOn: $includeReminders
                    )

                    Divider().padding(.leading, 58)

                    CleanCategoryToggleRow(
                        icon: "doc.fill",
                        iconColor: AppleTheme.teal,
                        title: "Documenti, Cartelle e Password",
                        countBadge: docsCount > 0 ? "\(docsCount) file pronti" : "File e Cartelle",
                        infoMessage: "Trasferisce documenti, PDF, Memo Vocali salvati in File, intere cartelle «Su iPhone» (mantenendo tutte le sottocartelle) e file Password .csv esportati.",
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
                            ? "Al termine della copia, DirectSwitch apre automaticamente il modulo Android Switch senza cavo sul telefono Android per mostrare il codice QR: su questo iPhone ti basterà aprire WhatsApp → Impostazioni → Chat → Trasferisci chat su Android e inquadrare il QR."
                            : "Al termine della copia, DirectSwitch ti guida passo-passo a trasferire il 100% di chat, foto e vocali sul nuovo iPhone via Wi-Fi diretto senza usare 1 MB di iCloud.",
                        isOn: $includeWhatsApp
                    )
                }
                .appleCard(padding: 0)

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Cartelle «Su iPhone», File o Password .csv")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(AppleTheme.textPrimary)
                        Spacer()
                        InfoCircleButton(
                            title: "Cartelle «Su iPhone» e Password senza iCloud",
                            message: "• Puoi selezionare singoli file oppure INTERE CARTELLE da «Su iPhone» nell'app File (inclusi Memo Vocali salvati in File e PDF): DirectSwitch ricrea automaticamente tutte le sottocartelle sul nuovo iPhone.\n\n• Vuoi passare anche le Password salvate senza Portachiavi iCloud? Apri Impostazioni → App → Password (o Safari) → Esporta password (.csv), salva il file e allegalo qui: sul nuovo iPhone comparirà il tasto rapido per reimportarle tutte!"
                        )
                    }

                    AppleSecondaryButton(
                        title: pickedDocuments.isEmpty
                            ? "Scegli file, cartelle «Su iPhone» o Password .csv"
                            : "Aggiungi altri file o cartelle (\(pickedDocuments.count) pronti)",
                        icon: "folder.badge.plus",
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

                // Card informativa pulita: App, Account Mail, Password e Background
                HStack(spacing: 12) {
                    AppleSettingsIcon(systemName: "square.grid.2x2.fill", color: AppleTheme.slate)
                    Text("App, Mail, Password e Background")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(AppleTheme.textPrimary)
                    Spacer()
                    InfoCircleButton(
                        title: "Passaggio completo senza iCloud",
                        message: "• App senza iCloud: al termine della copia, sul nuovo iPhone trovi il pulsante diretto ad App Store («App → Non su questo iPhone») che elenca gratuitamente il 100% delle tue app legate all'ID Apple (0 GB su iCloud) più i pulsanti rapidi 1-tap per le app principali.\n\n• Account Mail e Password: sul nuovo iPhone trovi i collegamenti rapidi 1-tap per Gmail, Outlook, Yahoo e Apple Mail, e il supporto all'importazione del file Password (.csv).\n\n• Esecuzione in Background e Resume: DirectSwitch mantiene attivo il trasferimento anche se passi brevemente a un'altra app o ricevi una chiamata, avvisandoti con una notifica se iOS sta per mettere in pausa il Wi-Fi e riprendendo esattamente dal file interrotto!"
                    )
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
        .onAppear {
            if !didAutoRequestPermissions && !(scanSummary?.hasFullPermissions ?? false) {
                didAutoRequestPermissions = true
                onScanExactCounts()
            }
        }
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
