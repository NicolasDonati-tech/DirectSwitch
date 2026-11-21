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
    @ObservedObject var l10n = DirectSwitchLocalizationStore.shared
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
                        Text(displayMode == .sixDigitCode ? l10n.tr("Codice di ricezione") : l10n.tr("QR di ricezione"))
                            .font(.system(size: 23, weight: .bold))
                            .foregroundColor(AppleTheme.textPrimary)
                        InfoCircleButton(
                            title: l10n.tr("Come ricevere i dati", en: "How to receive data", fr: "Comment recevoir des données"),
                            message: l10n.tr(
                                "1. Tieni i due telefoni sotto la stessa rete Wi-Fi (o Hotspot).\n2. Sull'altro telefono apri DirectSwitch e tocca 'Invia'.\n3. Seleziona questo iPhone (\(qrPayload.receiverName)) e inserisci il codice a 6 cifre, oppure inquadra il codice QR.\n4. Se il collegamento non parte, verifica che la voce «Rete locale» sia attiva in Impostazioni → DirectSwitch.",
                                en: "1. Keep both phones on the same Wi-Fi network (or Hotspot).\n2. On the other phone open DirectSwitch and tap 'Send'.\n3. Select this iPhone (\(qrPayload.receiverName)) and enter the 6-digit code, or scan the QR code.\n4. If it doesn't connect, check that 'Local Network' is enabled in Settings → DirectSwitch.",
                                fr: "1. Gardez les deux téléphones sur le même Wi-Fi (ou partage de connexion).\n2. Sur l'autre téléphone ouvrez DirectSwitch et touchez 'Envoyer'.\n3. Sélectionnez cet iPhone (\(qrPayload.receiverName)) et saisissez le code à 6 chiffres ou scannez le QR.\n4. Vérifiez que « Réseau local » est activé dans Réglages → DirectSwitch."
                            )
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
                            Text(l10n.tr("Abilita Foto e Contatti per salvare i dati", en: "Enable Photos & Contacts to save data", fr: "Activez Photos et Contacts pour enregistrer"))
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(AppleTheme.textPrimary)
                        }
                        Text(permWarning)
                            .font(.system(size: 13))
                            .foregroundColor(AppleTheme.textSecondary)
                        AppleSecondaryButton(
                            title: l10n.tr("Apri Impostazioni DirectSwitch", en: "Open DirectSwitch Settings", fr: "Ouvrir Réglages DirectSwitch"),
                            icon: "gearshape.fill",
                            tint: AppleTheme.orange,
                            action: onOpenAppSettings
                        )
                    }
                    .appleCard(padding: 14)
                }

                // Card principale perla con selettore Codice 6 cifre / QR
                VStack(spacing: 18) {
                    Picker(l10n.tr("Metodo collegamento", en: "Connection method", fr: "Méthode de connexion"), selection: $displayMode) {
                        Text(l10n.tr("Codice a 6 cifre")).tag(DisplayMode.sixDigitCode)
                        Text(l10n.tr("Codice QR")).tag(DisplayMode.qrCode)
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
                        Text(l10n.tr("In attesa di collegamento..."))
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(AppleTheme.textSecondary)
                    }

                    if !isLocalNetworkDenied {
                        Button(action: onOpenAppSettings) {
                            HStack(spacing: 6) {
                                Image(systemName: "gearshape")
                                    .font(.system(size: 12, weight: .semibold))
                                Text(l10n.tr("Non si avvia il trasferimento? Attiva «Rete locale»", en: "Transfer not starting? Enable 'Local Network'", fr: "Le transfert ne démarre pas ? Activez « Réseau local »"))
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
                            Text(l10n.tr("Posizioni di destinazione (fuori da DirectSwitch)", en: "Destination locations (outside DirectSwitch)", fr: "Emplacements de destination"))
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(AppleTheme.textPrimary)
                            Spacer()
                            InfoCircleButton(
                                title: l10n.tr("Salvataggio nelle posizioni originali", en: "Save to original locations", fr: "Enregistrement dans les emplacements d'origine"),
                                message: l10n.tr(
                                    "Per salvare file e cartelle direttamente nelle posizioni originali senza metterli tutti nella cartella DirectSwitch:\n\n1. Tocca «Seleziona posizione» qui sotto.\n2. Entra nella posizione desiderata (es. «Su iPhone» o «iCloud Drive»).\n3. Tocca semplicemente «Apri» in alto a destra.",
                                    en: "To save files and folders directly in their original locations:\n\n1. Tap 'Select location' below.\n2. Open the destination folder (e.g. On My iPhone or iCloud Drive).\n3. Tap 'Open' at the top right.",
                                    fr: "Pour enregistrer les fichiers dans leurs emplacements d'origine :\n\n1. Touchez « Sélectionner un emplacement » ci-dessous.\n2. Ouvrez le dossier souhaité (ex. Sur mon iPhone ou iCloud Drive).\n3. Touchez « Ouvrir » en haut à droite."
                                )
                            )
                        }

                        if authorizedDestinations.isEmpty && fallbackDestinationRoot == nil {
                            Text(l10n.tr("Seleziona la posizione dove salvare i file (es. «Su iPhone» o «iCloud Drive» → «Apri»). Senza selezione i file finiranno in File → Su iPhone → DirectSwitch.", en: "Select where to save files (e.g. On My iPhone or iCloud Drive → Open). Otherwise files go to Files → On My iPhone → DirectSwitch.", fr: "Choisissez où enregistrer les fichiers (ex. Sur mon iPhone ou iCloud Drive → Ouvrir). Sinon ils iront dans Fichiers → DirectSwitch."))
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
                                    Text(l10n.tr("…e altre \(authorizedDestinations.count - 4) posizioni selezionate", en: "…and \(authorizedDestinations.count - 4) more locations", fr: "…et \(authorizedDestinations.count - 4) autres emplacements"))
                                        .font(.system(size: 11))
                                        .foregroundColor(AppleTheme.textSecondary)
                                }
                                if let fb = fallbackDestinationRoot {
                                    HStack(spacing: 6) {
                                        Image(systemName: "folder.badge.plus")
                                            .font(.system(size: 11))
                                            .foregroundColor(AppleTheme.blue)
                                        Text("\(l10n.tr("Posizione base", en: "Base folder", fr: "Dossier de base")) → \(fb)")
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
                                title: authorizedDestinations.isEmpty ? l10n.tr("Seleziona posizione (Su iPhone / iCloud)") : l10n.tr("Aggiungi altra posizione (Su iPhone / iCloud)"),
                                icon: "folder.badge.plus",
                                tint: AppleTheme.blue,
                                action: onAuth
                            )
                        }

                        HStack(spacing: 12) {
                            if let onFb = onChooseFallbackRoot {
                                Button(action: onFb) {
                                    Text(fallbackDestinationRoot == nil ? l10n.tr("Posizione base per nuove cartelle", en: "Base folder for new folders", fr: "Dossier de base pour nouveaux dossiers") : l10n.tr("Cambia posizione base", en: "Change base folder", fr: "Changer le dossier de base"))
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundColor(AppleTheme.blue)
                                }
                                .buttonStyle(.plain)
                            }
                            Spacer()
                            if (!authorizedDestinations.isEmpty || fallbackDestinationRoot != nil),
                               let onClear = onClearDestinations {
                                Button(action: onClear) {
                                    Text(l10n.tr("Azzera"))
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
                    title: l10n.tr("Annulla"),
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
    @ObservedObject var l10n = DirectSwitchLocalizationStore.shared
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

                    Text(l10n.tr("Collegato!"))
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(AppleTheme.green)

                    Text(l10n.tr("Prosegui sull'altro telefono"))
                        .font(.system(size: 25, weight: .bold))
                        .foregroundColor(AppleTheme.textPrimary)
                        .multilineTextAlignment(.center)

                    Text(peerName.isEmpty
                         ? l10n.tr("Seleziona cosa vuoi trasferire sull'altro telefono e tocca «Copia le voci selezionate».", en: "Choose what to copy on the other phone and tap 'Copy selected items'.", fr: "Choisissez quoi transférer sur l'autre téléphone puis touchez « Copier les éléments sélectionnés ».")
                         : l10n.tr("Seleziona cosa trasferire su «\(peerName)» e tocca «Copia le voci selezionate». Il passaggio partirà in automatico anche qui.", en: "Select what to transfer on '\(peerName)' and tap 'Copy selected items'. Transfer will start automatically here too.", fr: "Sélectionnez quoi transférer sur « \(peerName) » et touchez « Copier ». Le transfert démarrera automatiquement ici aussi."))
                        .font(.system(size: 14.5))
                        .foregroundColor(AppleTheme.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 10)
                }

                VStack(spacing: 14) {
                    HStack(spacing: 12) {
                        AppleSettingsIcon(systemName: "arrow.left.arrow.right", color: AppleTheme.blue, size: 34)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(peerName.isEmpty ? l10n.tr("Canale sicuro pronto", en: "Secure channel ready", fr: "Canal sécurisé prêt") : l10n.tr("Connesso con \(peerName)", en: "Connected to \(peerName)", fr: "Connecté à \(peerName)"))
                                .font(.system(size: 15, weight: .bold))
                                .foregroundColor(AppleTheme.textPrimary)
                            Text(l10n.tr("In attesa che scegli le voci sull'altro telefono…"))
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
                            Text(l10n.tr("Cartella di salvataggio documenti", en: "Documents destination folder", fr: "Dossier de destination des documents"))
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(AppleTheme.textPrimary)
                            Spacer()
                        }

                        if authorizedDestinations.isEmpty && fallbackDestinationRoot == nil {
                            Text(l10n.tr("Opzionale: se trasferirai posizioni e cartelle, puoi scegliere ora dove salvarle (altrimenti andranno in File → Su iPhone → DirectSwitch).", en: "Optional: choose where to save transferred folders (otherwise Files → On My iPhone → DirectSwitch).", fr: "Facultatif : choisissez où enregistrer les dossiers (sinon Fichiers → DirectSwitch)."))
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
                                    Text("\(l10n.tr("Posizione base", en: "Base folder", fr: "Dossier de base")) → \(fb)")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundColor(AppleTheme.blue)
                                }
                            }
                        }

                        if let onAuth = onAuthorizeDestinations {
                            AppleSecondaryButton(
                                title: authorizedDestinations.isEmpty ? l10n.tr("Seleziona posizione (Su iPhone / iCloud)") : l10n.tr("Aggiungi altra posizione"),
                                icon: "folder.badge.plus",
                                tint: AppleTheme.blue,
                                action: onAuth
                            )
                        }

                        HStack {
                            if let onFb = onChooseFallbackRoot {
                                Button(action: onFb) {
                                    Text(fallbackDestinationRoot == nil ? l10n.tr("Posizione base per nuove cartelle", en: "Base folder for new folders", fr: "Dossier de base") : l10n.tr("Cambia posizione base", en: "Change base folder", fr: "Changer le dossier"))
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundColor(AppleTheme.blue)
                                }
                                .buttonStyle(.plain)
                            }
                            Spacer()
                            if (!authorizedDestinations.isEmpty || fallbackDestinationRoot != nil),
                               let onClear = onClearDestinations {
                                Button(action: onClear) {
                                    Text(l10n.tr("Azzera"))
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
                    title: l10n.tr("Annulla"),
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
    @ObservedObject var l10n = DirectSwitchLocalizationStore.shared
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

                    Text(isReceiverMode ? l10n.tr("Sto preparando la ricezione…") : l10n.tr("Sto preparando il trasferimento…"))
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(AppleTheme.textPrimary)
                        .multilineTextAlignment(.center)

                    Text(isReceiverMode
                         ? (transport.peerName.isEmpty
                            ? l10n.tr("Preparazione spazio di archiviazione e verifica elementi in arrivo...")
                            : l10n.tr("Preparazione della ricezione da \(transport.peerName) e verifica elementi già presenti...", en: "Preparing to receive from \(transport.peerName) and checking existing items...", fr: "Préparation de la réception depuis \(transport.peerName) et vérification des éléments existants..."))
                         : l10n.tr("Preparazione rapida e conteggio delle voci selezionate prima di partire dallo 0%."))
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
                                Text(transport.statusLabel.isEmpty ? l10n.tr("Preparazione in corso...") : l10n.tr(transport.statusLabel))
                                    .font(.system(size: 14.5, weight: .semibold))
                                    .foregroundColor(AppleTheme.textPrimary)
                                Text(l10n.tr("Tra pochi istanti inizierà la copia sincronizzata dallo 0%."))
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

                                    Text(l10n.tr(item.title))
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
                                            let locUnitPlural = l10n.tr(item.unitPlural)
                                            let locUnitSing = l10n.tr(item.unitSingular)
                                            Text(isDone
                                                 ? "\(item.targetCount) \(item.targetCount == 1 ? locUnitSing : locUnitPlural)"
                                                 : "\(currentVal) / \(item.targetCount) \(locUnitPlural)")
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
                    title: l10n.tr("Annulla"),
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
