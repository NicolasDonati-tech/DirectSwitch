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
    var preScannedAppsCount: Int = 0
    var onOpenLiveAppScanner: (() -> Void)? = nil
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
                        Text("In attesa dell'altro telefono...")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(AppleTheme.textSecondary)
                    }

                    HStack(spacing: 6) {
                        Image(systemName: "bolt.shield.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(AppleTheme.teal)
                        Text("Anti-Standby e Keep-Alive Background attivi")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(AppleTheme.teal)
                        InfoCircleButton(
                            title: "Esecuzione in Background attiva",
                            message: "DirectSwitch mantiene lo schermo sveglio e protegge il canale di rete locale anche se passi temporaneamente in Impostazioni o rispondi a una chiamata."
                        )
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(AppleTheme.teal.opacity(0.09))
                    .clipShape(Capsule())

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

                if let openScanner = onOpenLiveAppScanner {
                    Button(action: openScanner) {
                        HStack(spacing: 11) {
                            AppleSettingsIcon(
                                systemName: preScannedAppsCount > 0 ? "checkmark.seal.fill" : "camera.viewfinder",
                                color: preScannedAppsCount > 0 ? AppleTheme.green : AppleTheme.blue,
                                size: 34
                            )
                            VStack(alignment: .leading, spacing: 2) {
                                Text(preScannedAppsCount > 0
                                     ? "App già lette dal vecchio telefono (\(preScannedAppsCount))"
                                     : "Scansiona le App inquadrando il vecchio telefono")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(AppleTheme.textPrimary)
                                    .lineLimit(1)
                                Text(preScannedAppsCount > 0
                                     ? "Tocca se vuoi inquadrare altre pagine della schermata Home"
                                     : "Opzionale: inquadra le pagine Home per 5 sec senza registrazione schermo")
                                    .font(.system(size: 12))
                                    .foregroundColor(AppleTheme.textSecondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(AppleTheme.textTertiary)
                        }
                        .appleCard(padding: 13)
                    }
                    .buttonStyle(.plain)
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
