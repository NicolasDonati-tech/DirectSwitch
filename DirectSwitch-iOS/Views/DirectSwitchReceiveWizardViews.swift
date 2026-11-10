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
    let errorMessage: String?
    var onCancel: () -> Void

    private enum DisplayMode: Int {
        case sixDigitCode = 0
        case qrCode = 1
    }

    @State private var displayMode: DisplayMode = .sixDigitCode

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                // Intestazione Passo pulita con pulsante ⓘ
                HStack {
                    Text("Passo 1 di 2")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(AppleTheme.blue)
                    Spacer()
                    InfoCircleButton(
                        title: "Come collegare i telefoni",
                        message: "1. Tieni i due telefoni sotto la stessa rete Wi-Fi (o Hotspot).\n2. Sul vecchio telefono apri DirectSwitch e tocca 'Invia al nuovo telefono'.\n3. Seleziona questo iPhone e inserisci il codice a 6 cifre, oppure usa 'Codice QR' per inquadrarlo con la fotocamera."
                    )
                }
                .padding(.top, 8)

                // Titolo chiaro in stile "Passa a iOS"
                VStack(spacing: 8) {
                    ZStack {
                        Circle()
                            .fill(AppleTheme.blue.opacity(0.12))
                            .frame(width: 58, height: 58)
                        Image(systemName: displayMode == .sixDigitCode ? "lock.iphone" : "qrcode")
                            .font(.system(size: 26, weight: .semibold))
                            .foregroundColor(AppleTheme.blue)
                    }

                    Text(displayMode == .sixDigitCode ? "Inserisci il codice monouso" : "Inquadra il codice QR")
                        .font(.system(size: 23, weight: .bold))
                        .foregroundColor(AppleTheme.textPrimary)
                        .multilineTextAlignment(.center)

                    Text("Apri DirectSwitch sul vecchio telefono e tocca **Invia al nuovo telefono**")
                        .font(.system(size: 14))
                        .foregroundColor(AppleTheme.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 12)
                }

                // Card principale perla con selettore Codice 6 cifre / QR
                VStack(spacing: 18) {
                    Picker("Metodo collegamento", selection: $displayMode) {
                        Text("Codice a 6 cifre").tag(DisplayMode.sixDigitCode)
                        Text("Codice QR").tag(DisplayMode.qrCode)
                    }
                    .pickerStyle(.segmented)

                    if displayMode == .sixDigitCode {
                        VStack(spacing: 14) {
                            PassaAiOSCodeBoxesView(code: pairingPin)
                                .padding(.vertical, 8)

                            Text("Visibile come **\(qrPayload.receiverName)**")
                                .font(.system(size: 13))
                                .foregroundColor(AppleTheme.textSecondary)
                        }
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

                            if !pairingPin.isEmpty {
                                Text("Codice: \(pairingPin)")
                                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                                    .foregroundColor(AppleTheme.blue)
                            }
                        }
                    }

                    Divider()

                    HStack(spacing: 10) {
                        ProgressView()
                            .tint(AppleTheme.blue)
                        Text("In attesa dell'altro telefono...")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(AppleTheme.textSecondary)
                    }
                    .padding(.bottom, 2)
                }
                .appleCard()

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

// MARK: - Portale Rubrica Rapida via QR (senza installare app sull'altro telefono)

struct QuickContactsPortalView: View {
    let portalUrl: String
    var onClose: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                HStack {
                    Text("Rubrica rapida")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(AppleTheme.blue)
                    Spacer()
                    InfoCircleButton(
                        title: "Rubrica senza installare l'app",
                        message: "Inquadra questo codice QR con la normale Fotocamera dell'altro telefono collegato alla stessa Wi-Fi: si aprirà una pagina sicura locale per salvare subito tutti i contatti (.vcf) senza internet né cloud."
                    )
                }
                .padding(.top, 8)

                VStack(spacing: 8) {
                    ZStack {
                        Circle()
                            .fill(AppleTheme.blue.opacity(0.12))
                            .frame(width: 58, height: 58)
                        Image(systemName: "person.crop.circle.badge.checkmark")
                            .font(.system(size: 26, weight: .semibold))
                            .foregroundColor(AppleTheme.blue)
                    }

                    Text("Inquadra con la Fotocamera")
                        .font(.system(size: 23, weight: .bold))
                        .foregroundColor(AppleTheme.textPrimary)

                    Text("Importa tutti i contatti sull'altro telefono in un tocco")
                        .font(.system(size: 14))
                        .foregroundColor(AppleTheme.textSecondary)
                        .multilineTextAlignment(.center)
                }

                VStack(spacing: 14) {
                    if let img = DirectSwitchUIHelpers.generateQrImage(from: portalUrl) {
                        Image(uiImage: img)
                            .interpolation(.none)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 215, height: 215)
                            .padding(14)
                            .background(Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .stroke(AppleTheme.cardBorder, lineWidth: 0.8)
                            )
                    }

                    HStack(spacing: 8) {
                        Image(systemName: "lock.shield.fill")
                            .font(.system(size: 13))
                            .foregroundColor(AppleTheme.green)
                        Text("Rete locale privata • Nessun cloud")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(AppleTheme.textSecondary)
                    }
                }
                .appleCard()

                ApplePrimaryButton(
                    title: "Chiudi",
                    color: AppleTheme.blue,
                    action: onClose
                )
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 28)
        }
    }
}
