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
                            message: "1. Tieni i due telefoni sotto la stessa rete Wi-Fi (o Hotspot).\n2. Sull'altro telefono apri DirectSwitch e tocca 'Invia'.\n3. Seleziona questo iPhone (\(qrPayload.receiverName)) e inserisci il codice a 6 cifre, oppure inquadra il codice QR."
                        )
                    }
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
