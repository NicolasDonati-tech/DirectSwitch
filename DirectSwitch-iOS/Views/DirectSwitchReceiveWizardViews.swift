//
//  DirectSwitchReceiveWizardViews.swift
//  DirectSwitch-iOS
//
//  Created by Nicolas Donati.
//  Copyright © 2026 Nicolas Donati. Tutti i diritti riservati.
//

import SwiftUI

// MARK: - Passo 1 Ricevente (identico a "Passa a iOS": codice monouso a 6 cifre + opzione QR)

struct ReceivePairingStepView: View {
    let qrPayload: QrPairingPayload
    let pairingPin: String
    let isLocalNetworkDenied: Bool
    let deniedPermissionsNote: String?
    let errorMessage: String?
    var authorizedDestinations: [String] = []
    var fallbackDestinationRoot: String? = nil
    var onAuthorizeDestinations: (() -> Void)? = nil
    var onChooseFallbackRoot: (() -> Void)? = nil
    var onClearDestinations: (() -> Void)? = nil
    var onOpenAppSettings: () -> Void
    var onCancel: () -> Void

    private enum DisplayMode: Int {
        case sixDigitCode = 0
        case qrCode = 1
    }

    @State private var displayMode: DisplayMode = .sixDigitCode

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                // Intestazione Ricevi con freccia verso sinistra (<-) e sottotitolo dentro ⓘ
                VStack(spacing: 12) {
                    AppleSettingsIcon(systemName: "arrow.left", color: AppleTheme.teal, size: 52)
                        .padding(.top, 12)

                    HStack(spacing: 6) {
                        Text(displayMode == .sixDigitCode ? "Codice di ricezione" : "QR di ricezione")
                            .font(.system(size: 23, weight: .bold))
                            .foregroundColor(AppleTheme.textPrimary)
                        InfoCircleButton(
                            title: "Come ricevere i dati",
                            message: "1. Tieni i due telefoni sotto la stessa rete Wi-Fi (o Hotspot).\n2. Sull'altro telefono apri DirectSwitch e tocca 'Invia'.\n3. Seleziona questo iPhone (\(qrPayload.receiverName)) e inserisci il codice a 6 cifre, oppure inquadra il codice QR.\n4. Se il collegamento non parte, verifica che la voce «Rete locale» sia attiva in Impostazioni → DirectSwitch."
                        )
                    }
                }

                if isLocalNetworkDenied {
                    LocalNetworkRedirectBanner(onOpenSettings: onOpenAppSettings)
                }

                if let permWarning = deniedPermissionsNote, !permWarning.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            Image(systemName: "photo.badge.exclamationmark.fill")
                                .foregroundColor(AppleTheme.orange)
                            Text("Abilita Foto e Contatti per salvare i dati")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(AppleTheme.textPrimary)
                        }
                        Text(permWarning)
                            .font(.system(size: 13))
                            .foregroundColor(AppleTheme.textSecondary)
                        AppleSecondaryButton(
                            title: "Apri Impostazioni DirectSwitch",
                            icon: "gearshape.fill",
                            tint: AppleTheme.orange,
                            action: onOpenAppSettings
                        )
                    }
                    .appleCard(padding: 14)
                }

                // Card principale perla con selettore Codice 6 cifre / QR
                VStack(spacing: 18) {
                    Picker("Metodo collegamento", selection: $displayMode) {
                        Text("Codice a 6 cifre").tag(DisplayMode.sixDigitCode)
                        Text("Codice QR").tag(DisplayMode.qrCode)
                    }
                    .pickerStyle(.segmented)

                    if displayMode == .sixDigitCode {
                        PassaAiOSCodeBoxesView(code: pairingPin)
                            .padding(.vertical, 8)
                    } else {
                        VStack(spacing: 12) {
                            if let qrImg = DirectSwitchUIHelpers.generateQrImage(from: qrPayload.toCompactJson()) {
                                Image(uiImage: qrImg)
                                    .interpolation(.none)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 210, height: 210)
                                    .padding(12)
                                    .background(Color.white)
                                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                                            .stroke(AppleTheme.cardBorder, lineWidth: 0.8)
                                    )
                            }
                        }
                    }

                    Divider()

                    HStack(spacing: 10) {
                        ProgressView()
                            .tint(AppleTheme.teal)
                        Text("In attesa di collegamento...")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(AppleTheme.textSecondary)
                    }

                    if !isLocalNetworkDenied {
                        Button(action: onOpenAppSettings) {
                            HStack(spacing: 6) {
                                Image(systemName: "gearshape")
                                    .font(.system(size: 12, weight: .semibold))
                                Text("Non si avvia il trasferimento? Attiva «Rete locale»")
                                    .font(.system(size: 12, weight: .semibold))
                            }
                            .foregroundColor(AppleTheme.blue)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .appleCard()

                if onAuthorizeDestinations != nil || onChooseFallbackRoot != nil {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 10) {
                            Image(systemName: authorizedDestinations.isEmpty && fallbackDestinationRoot == nil ? "folder.badge.questionmark" : "folder.fill.badge.checkmark")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(authorizedDestinations.isEmpty && fallbackDestinationRoot == nil ? AppleTheme.orange : AppleTheme.green)
                            Text("Posizioni di destinazione (fuori da DirectSwitch)")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(AppleTheme.textPrimary)
                            Spacer()
                            InfoCircleButton(
                                title: "Salvataggio nelle posizioni originali",
                                message: "Per salvare file e cartelle direttamente nelle posizioni originali senza metterli tutti nella cartella DirectSwitch:\n\n1. Tocca «Seleziona posizione» qui sotto.\n2. Entra nella posizione desiderata (es. «Su iPhone» o «iCloud Drive»).\n3. Tocca semplicemente «Apri» in alto a destra."
                            )
                        }

                        if authorizedDestinations.isEmpty && fallbackDestinationRoot == nil {
                            Text("Seleziona la posizione dove salvare i file (es. «Su iPhone» o «iCloud Drive» → «Apri»). Senza selezione i file finiranno in File → Su iPhone → DirectSwitch.")
                                .font(.system(size: 12))
                                .foregroundColor(AppleTheme.orange)
                                .fixedSize(horizontal: false, vertical: true)
                        } else {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(Array(authorizedDestinations.prefix(4)), id: \.self) { label in
                                    HStack(spacing: 6) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.system(size: 11))
                                            .foregroundColor(AppleTheme.green)
                                        Text(label)
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundColor(AppleTheme.textPrimary)
                                            .lineLimit(1)
                                            .truncationMode(.middle)
                                    }
                                }
                                if authorizedDestinations.count > 4 {
                                    Text("…e altre \(authorizedDestinations.count - 4) posizioni selezionate")
                                        .font(.system(size: 11))
                                        .foregroundColor(AppleTheme.textSecondary)
                                }
                                if let fb = fallbackDestinationRoot {
                                    HStack(spacing: 6) {
                                        Image(systemName: "folder.badge.plus")
                                            .font(.system(size: 11))
                                            .foregroundColor(AppleTheme.blue)
                                        Text("Posizione base → \(fb)")
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundColor(AppleTheme.blue)
                                            .lineLimit(1)
                                            .truncationMode(.middle)
                                    }
                                }
                            }
                        }

                        if let onAuth = onAuthorizeDestinations {
                            AppleSecondaryButton(
                                title: authorizedDestinations.isEmpty ? "Seleziona posizione (Su iPhone / iCloud)" : "Aggiungi altra posizione (Su iPhone / iCloud)",
                                icon: "folder.badge.plus",
                                tint: AppleTheme.blue,
                                action: onAuth
                            )
                        }

                        HStack(spacing: 12) {
                            if let onFb = onChooseFallbackRoot {
                                Button(action: onFb) {
                                    Text(fallbackDestinationRoot == nil ? "Posizione base per nuove cartelle" : "Cambia posizione base")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundColor(AppleTheme.blue)
                                }
                                .buttonStyle(.plain)
                            }
                            Spacer()
                            if (!authorizedDestinations.isEmpty || fallbackDestinationRoot != nil),
                               let onClear = onClearDestinations {
                                Button(action: onClear) {
                                    Text("Azzera")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundColor(AppleTheme.red)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .appleCard(padding: 14)
                }

                if let err = errorMessage, !err.isEmpty {
                    HStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(AppleTheme.red)
                        Text(err)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(AppleTheme.red)
                        Spacer()
                    }
                    .appleCard(padding: 14)
                }

                AppleSecondaryButton(
                    title: "Annulla",
                    icon: "xmark",
                    tint: AppleTheme.textSecondary,
                    action: onCancel
                )
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 28)
        }
    }
}

// MARK: - Passo 2 Ricevente (Collegato -> "Prosegui sull'altro telefono" stile Passa a iOS)

struct ReceiveConnectedStepView: View {
    let peerName: String
    var authorizedDestinations: [String] = []
    var fallbackDestinationRoot: String? = nil
    var onAuthorizeDestinations: (() -> Void)? = nil
    var onChooseFallbackRoot: (() -> Void)? = nil
    var onClearDestinations: (() -> Void)? = nil
    var onCancel: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                VStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(AppleTheme.green.opacity(0.16))
                            .frame(width: 72, height: 72)
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 38, weight: .semibold))
                            .foregroundColor(AppleTheme.green)
                    }
                    .padding(.top, 22)

                    Text("Collegato!")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(AppleTheme.green)

                    Text("Prosegui sull'altro telefono")
                        .font(.system(size: 25, weight: .bold))
                        .foregroundColor(AppleTheme.textPrimary)
                        .multilineTextAlignment(.center)

                    Text(peerName.isEmpty
                         ? "Seleziona cosa vuoi trasferire sull'altro telefono e tocca «Copia le voci selezionate»."
                         : "Seleziona cosa trasferire su «\(peerName)» e tocca «Copia le voci selezionate». Il passaggio partirà in automatico anche qui.")
                        .font(.system(size: 14.5))
                        .foregroundColor(AppleTheme.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 10)
                }

                VStack(spacing: 14) {
                    HStack(spacing: 12) {
                        AppleSettingsIcon(systemName: "arrow.left.arrow.right", color: AppleTheme.blue, size: 34)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(peerName.isEmpty ? "Canale sicuro pronto" : "Connesso con \(peerName)")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundColor(AppleTheme.textPrimary)
                            Text("In attesa che scegli le voci sull'altro telefono…")
                                .font(.system(size: 13))
                                .foregroundColor(AppleTheme.textSecondary)
                        }
                        Spacer()
                        ProgressView()
                            .tint(AppleTheme.blue)
                    }
                }
                .appleCard(padding: 16, selected: true)

                if onAuthorizeDestinations != nil || onChooseFallbackRoot != nil {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            Image(systemName: authorizedDestinations.isEmpty && fallbackDestinationRoot == nil ? "folder.badge.questionmark" : "folder.fill.badge.checkmark")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(authorizedDestinations.isEmpty && fallbackDestinationRoot == nil ? AppleTheme.orange : AppleTheme.green)
                            Text("Cartella di salvataggio documenti")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(AppleTheme.textPrimary)
                            Spacer()
                        }

                        if authorizedDestinations.isEmpty && fallbackDestinationRoot == nil {
                            Text("Opzionale: se trasferirai posizioni e cartelle, puoi scegliere ora dove salvarle (altrimenti andranno in File → Su iPhone → DirectSwitch).")
                                .font(.system(size: 12))
                                .foregroundColor(AppleTheme.textSecondary)
                        } else {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(Array(authorizedDestinations.prefix(4)), id: \.self) { label in
                                    HStack(spacing: 6) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.system(size: 11))
                                            .foregroundColor(AppleTheme.green)
                                        Text(label)
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundColor(AppleTheme.textPrimary)
                                            .lineLimit(1)
                                    }
                                }
                                if let fb = fallbackDestinationRoot {
                                    Text("Posizione base → \(fb)")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundColor(AppleTheme.blue)
                                }
                            }
                        }

                        if let onAuth = onAuthorizeDestinations {
                            AppleSecondaryButton(
                                title: authorizedDestinations.isEmpty ? "Seleziona posizione (Su iPhone / iCloud)" : "Aggiungi altra posizione",
                                icon: "folder.badge.plus",
                                tint: AppleTheme.blue,
                                action: onAuth
                            )
                        }

                        HStack {
                            if let onFb = onChooseFallbackRoot {
                                Button(action: onFb) {
                                    Text(fallbackDestinationRoot == nil ? "Posizione base per nuove cartelle" : "Cambia posizione base")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundColor(AppleTheme.blue)
                                }
                                .buttonStyle(.plain)
                            }
                            Spacer()
                            if (!authorizedDestinations.isEmpty || fallbackDestinationRoot != nil),
                               let onClear = onClearDestinations {
                                Button(action: onClear) {
                                    Text("Azzera")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundColor(AppleTheme.red)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .appleCard(padding: 14)
                }

                AppleSecondaryButton(
                    title: "Annulla",
                    icon: "xmark",
                    tint: AppleTheme.textSecondary,
                    action: onCancel
                )
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 28)
        }
    }
}

// MARK: - Schermata 2: Preparazione simultanea ("Sto preparando la ricezione..." / "Sto preparando il trasferimento...")

struct TransferPreparationStepView: View {
    @ObservedObject var transport: DirectSwitchTransportViewModel
    let isReceiverMode: Bool
    var onCancel: () -> Void

    @State private var displayedCounts: [String: Int] = [:]
    @State private var didTriggerFinishCallback: Bool = false

    private let ticker = Timer.publish(every: 0.025, on: .main, in: .common).autoconnect()

    private func colorForItem(_ id: String) -> Color {
        switch id {
        case "contacts", "reminders", "apps": return AppleTheme.blue
        case "photos": return AppleTheme.orange
        case "videos": return AppleTheme.red
        case "documents": return AppleTheme.teal
        default: return AppleTheme.slate
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                VStack(spacing: 12) {
                    DirectSwitchAppleEmblem(size: 72)
                        .padding(.top, 22)

                    ProgressView()
                        .scaleEffect(1.15)
                        .tint(AppleTheme.blue)
                        .padding(.top, 4)

                    Text(isReceiverMode ? "Sto preparando la ricezione…" : "Sto preparando il trasferimento…")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(AppleTheme.textPrimary)
                        .multilineTextAlignment(.center)

                    Text(isReceiverMode
                         ? (transport.peerName.isEmpty
                            ? "Preparazione spazio di archiviazione e verifica elementi in arrivo..."
                            : "Preparazione della ricezione da \(transport.peerName) e verifica elementi già presenti...")
                         : "Preparazione rapida e conteggio delle voci selezionate prima di partire dallo 0%.")
                        .font(.system(size: 14))
                        .foregroundColor(AppleTheme.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 12)
                }

                if isReceiverMode {
                    VStack(spacing: 12) {
                        HStack(spacing: 12) {
                            AppleSettingsIcon(systemName: "arrow.down.circle.fill", color: AppleTheme.teal)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(transport.statusLabel.isEmpty ? "Preparazione in corso..." : transport.statusLabel)
                                    .font(.system(size: 14.5, weight: .semibold))
                                    .foregroundColor(AppleTheme.textPrimary)
                                Text("Tra pochi istanti inizierà la copia sincronizzata dallo 0%.")
                                    .font(.system(size: 12.5))
                                    .foregroundColor(AppleTheme.textSecondary)
                            }
                            Spacer()
                        }
                    }
                    .appleCard(padding: 16)
                } else if !transport.preparationItems.isEmpty {
                    VStack(spacing: 14) {
                        ForEach(transport.preparationItems) { item in
                            let currentVal = displayedCounts[item.id] ?? 0
                            let isDone = item.isReady && currentVal >= item.targetCount
                            let target = max(1, item.targetCount)

                            VStack(alignment: .leading, spacing: 7) {
                                HStack(spacing: 10) {
                                    AppleSettingsIcon(systemName: item.icon, color: colorForItem(item.id), size: 28)

                                    Text(item.title)
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundColor(AppleTheme.textPrimary)

                                    Spacer()

                                    if !item.isReady && item.targetCount == 0 {
                                        ProgressView()
                                            .scaleEffect(0.75)
                                            .tint(AppleTheme.blue)
                                    } else {
                                        HStack(spacing: 5) {
                                            if isDone {
                                                Image(systemName: "checkmark.circle.fill")
                                                    .font(.system(size: 14, weight: .semibold))
                                                    .foregroundColor(AppleTheme.green)
                                            }
                                            Text(isDone
                                                 ? item.formattedCount(item.targetCount)
                                                 : "\(currentVal) / \(item.targetCount) \(item.unitPlural)")
                                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                                .foregroundColor(isDone ? AppleTheme.green : AppleTheme.blue)
                                        }
                                    }
                                }

                                GeometryReader { geo in
                                    let ratio: Double = {
                                        if isDone { return 1.0 }
                                        guard item.targetCount > 0 else { return 0.12 }
                                        return min(1.0, max(0.05, Double(currentVal) / Double(target)))
                                    }()
                                    ZStack(alignment: .leading) {
                                        Capsule()
                                            .fill(AppleTheme.inputSurface)
                                            .frame(height: 6)
                                        Capsule()
                                            .fill(isDone ? AppleTheme.green : AppleTheme.blue)
                                            .frame(width: max(8, geo.size.width * ratio), height: 6)
                                    }
                                }
                                .frame(height: 6)
                            }
                        }
                    }
                    .appleCard(padding: 15)
                }

                AppleSecondaryButton(
                    title: "Annulla",
                    icon: "xmark",
                    tint: AppleTheme.textSecondary,
                    action: onCancel
                )
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 28)
        }
        .onReceive(ticker) { _ in
            guard !isReceiverMode else { return }
            var allFinished = transport.arePreparationItemsReady && !transport.preparationItems.isEmpty
            for item in transport.preparationItems {
                let current = displayedCounts[item.id] ?? 0
                if item.targetCount > current {
                    let remaining = item.targetCount - current
                    let step = max(1, (item.targetCount + 15) / 16)
                    displayedCounts[item.id] = current + min(step, remaining)
                }
                let updated = displayedCounts[item.id] ?? 0
                if !item.isReady || updated < item.targetCount {
                    allFinished = false
                }
            }
            if allFinished && !didTriggerFinishCallback {
                didTriggerFinishCallback = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) {
                    transport.markPreparationAnimationCompleted()
                }
            }
        }
        .onAppear {
            displayedCounts = [:]
            didTriggerFinishCallback = false
        }
    }
}
