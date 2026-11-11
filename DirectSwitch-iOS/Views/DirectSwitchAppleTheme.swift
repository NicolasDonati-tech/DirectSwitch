//
//  DirectSwitchAppleTheme.swift
//  DirectSwitch-iOS
//
//  Created by Nicolas Donati.
//  Copyright © 2026 Nicolas Donati. Tutti i diritti riservati.
//

import SwiftUI
import CoreImage.CIFilterBuiltins
import UIKit

// MARK: - Tema grafico Apple HIG (Base Perla + Colori Neutri ed Eleganti, Zero Viola)

enum AppleTheme {
    static let canvasTop = Color(red: 0.878, green: 0.906, blue: 0.945)      // #E0E7F1
    static let canvasMid = Color(red: 0.914, green: 0.933, blue: 0.965)      // #E9EEF6
    static let canvasBottom = Color(red: 0.855, green: 0.886, blue: 0.933)   // #DAE2EE

    static let headerBg = Color(red: 0.898, green: 0.922, blue: 0.957).opacity(0.95)
    static let cardSurface = Color(red: 0.973, green: 0.980, blue: 0.992)    // #F8FAFD Perla morbido
    static let cardSelected = Color(red: 0.918, green: 0.949, blue: 0.996)   // #EAF2FE
    static let inputSurface = Color(red: 0.918, green: 0.937, blue: 0.965)   // #EAEFF6
    static let cardBorder = Color(red: 0.812, green: 0.847, blue: 0.898)     // #CFD8E5
    static let hairline = Color(red: 0.780, green: 0.816, blue: 0.871)       // #C7D0DE

    static let blue = Color(red: 0.000, green: 0.478, blue: 1.000)           // Apple #007AFF
    static let teal = Color(red: 0.000, green: 0.541, blue: 0.659)           // Ocean Teal #008AA8
    static let green = Color(red: 0.204, green: 0.780, blue: 0.349)          // Apple #34C759
    static let orange = Color(red: 1.000, green: 0.584, blue: 0.000)         // Apple #FF9500
    static let red = Color(red: 1.000, green: 0.231, blue: 0.188)            // Apple #FF3B30
    static let slate = Color(red: 0.216, green: 0.255, blue: 0.318)          // Grigio Ardesia Neutro #374151
    static let charcoal = Color(red: 0.110, green: 0.118, blue: 0.137)       // Grafite Scuro Neutro #1C1E23

    // Palette dedicata per il badge "Premium Direct" (Oro/Ambra stile funzionalità Premium)
    static let premiumGold = Color(red: 0.780, green: 0.451, blue: 0.020)    // #C77305
    static let premiumAmber = Color(red: 0.945, green: 0.588, blue: 0.039)   // #F1960A
    static let premiumSurface = Color(red: 1.000, green: 0.965, blue: 0.863) // #FFF6DC
    static let premiumBorder = Color(red: 0.922, green: 0.659, blue: 0.145)  // #EBA825

    // Alias neutro al posto del vecchio indaco/viola
    static let indigo = slate

    static let textPrimary = Color(red: 0.110, green: 0.110, blue: 0.118)    // #1C1C1E
    static let textSecondary = Color(red: 0.388, green: 0.388, blue: 0.400)  // #636366
    static let textTertiary = Color(red: 0.557, green: 0.557, blue: 0.576)   // #8E8E93

    static var backgroundGradient: LinearGradient {
        LinearGradient(
            colors: [canvasTop, canvasMid, canvasBottom],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

// MARK: - Emblema DirectSwitch identico al 100% all'icona AppIcon-1024.png

struct DirectSwitchAppleEmblem: View {
    var size: CGFloat = 86

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.235, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.071, green: 0.518, blue: 1.000), // #1284FF
                            Color(red: 0.000, green: 0.345, blue: 0.839), // #0058D6
                            Color(red: 0.000, green: 0.541, blue: 0.659)  // #008AA8
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: size, height: size)
                .shadow(color: AppleTheme.blue.opacity(0.22), radius: 10, x: 0, y: 5)

            Canvas { context, canvasSize in
                let w = canvasSize.width
                let h = canvasSize.height

                // 1. Telefono posteriore glassmorphic (in alto a destra, identico a AppIcon-1024.png)
                let backRect = CGRect(x: w * 0.439, y: h * 0.151, width: w * 0.312, height: h * 0.478)
                let backPath = RoundedRectangle(cornerRadius: w * 0.073, style: .continuous).path(in: backRect)
                context.fill(backPath, with: .color(Color.white.opacity(0.37)))
                context.stroke(backPath, with: .color(Color.white.opacity(0.47)), lineWidth: max(1.0, w * 0.012))

                // 2. Telefono principale bianco-perla scolpito (in basso a sinistra)
                let frontRect = CGRect(x: w * 0.244, y: h * 0.244, width: w * 0.337, height: h * 0.518)
                let frontPath = RoundedRectangle(cornerRadius: w * 0.080, style: .continuous).path(in: frontRect)

                context.drawLayer { layer in
                    var sub = layer
                    sub.addFilter(
                        .shadow(
                            color: Color(red: 0.03, green: 0.09, blue: 0.23).opacity(0.28),
                            radius: w * 0.042,
                            x: 0,
                            y: h * 0.025
                        )
                    )
                    sub.fill(
                        frontPath,
                        with: .linearGradient(
                            Gradient(colors: [
                                Color.white,
                                Color(red: 0.910, green: 0.949, blue: 0.988)
                            ]),
                            startPoint: CGPoint(x: frontRect.midX, y: frontRect.minY),
                            endPoint: CGPoint(x: frontRect.midX, y: frontRect.maxY)
                        )
                    )
                }

                // 3. Tacca speaker superiore
                let pillRect = CGRect(x: w * 0.371, y: h * 0.282, width: w * 0.083, height: h * 0.0185)
                context.fill(
                    Capsule().path(in: pillRect),
                    with: .color(Color(red: 0.000, green: 0.384, blue: 0.839).opacity(0.26))
                )

                // 4. Doppia freccia orizzontale (Blu destra + Teal sinistra) identica a AppIcon-1024.png
                let strokeW = max(1.8, w * 0.0265)
                let style = StrokeStyle(lineWidth: strokeW, lineCap: .round, lineJoin: .round)

                var rightArrow = Path()
                rightArrow.move(to: CGPoint(x: w * 0.332, y: h * 0.466))
                rightArrow.addLine(to: CGPoint(x: w * 0.493, y: h * 0.466))
                rightArrow.move(to: CGPoint(x: w * 0.449, y: h * 0.422))
                rightArrow.addLine(to: CGPoint(x: w * 0.495, y: h * 0.466))
                rightArrow.addLine(to: CGPoint(x: w * 0.449, y: h * 0.510))
                context.stroke(rightArrow, with: .color(Color(red: 0.000, green: 0.439, blue: 0.941)), style: style)

                var leftArrow = Path()
                leftArrow.move(to: CGPoint(x: w * 0.493, y: h * 0.564))
                leftArrow.addLine(to: CGPoint(x: w * 0.332, y: h * 0.564))
                leftArrow.move(to: CGPoint(x: w * 0.376, y: h * 0.520))
                leftArrow.addLine(to: CGPoint(x: w * 0.330, y: h * 0.564))
                leftArrow.addLine(to: CGPoint(x: w * 0.376, y: h * 0.608))
                context.stroke(leftArrow, with: .color(Color(red: 0.000, green: 0.541, blue: 0.659)), style: style)
            }
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.235, style: .continuous))
        }
    }
}

struct AppleSettingsIcon: View {
    let systemName: String
    let color: Color
    var size: CGFloat = 30

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(color)
                .frame(width: size, height: size)
            Image(systemName: systemName)
                .font(.system(size: size * 0.46, weight: .semibold))
                .foregroundColor(.white)
        }
    }
}

struct AppleCardModifier: ViewModifier {
    var paddingValue: CGFloat = 16
    var isSelected: Bool = false

    func body(content: Content) -> some View {
        content
            .padding(paddingValue)
            .background(isSelected ? AppleTheme.cardSelected : AppleTheme.cardSurface)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(isSelected ? AppleTheme.blue.opacity(0.45) : AppleTheme.cardBorder, lineWidth: isSelected ? 1.1 : 0.8)
            )
            .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 3)
    }
}

extension View {
    func appleCard(padding: CGFloat = 16, selected: Bool = false) -> some View {
        modifier(AppleCardModifier(paddingValue: padding, isSelected: selected))
    }
}

// MARK: - Barra superiore Apple HIG (logo piccolo + DirectSwitch a sinistra nella Home, Premium Direct a destra)

struct AppleTopNavigationBar: View {
    let title: String
    let showBackButton: Bool
    let isProUnlocked: Bool
    let onBack: () -> Void
    let onTapPassBadge: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                if showBackButton {
                    Button(action: onBack) {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 16, weight: .semibold))
                            Text("Indietro")
                                .font(.system(size: 16, weight: .regular))
                        }
                        .foregroundColor(AppleTheme.blue)
                    }
                    .buttonStyle(.plain)
                    .fixedSize()
                } else {
                    HStack(spacing: 8) {
                        DirectSwitchAppleEmblem(size: 26)
                        Text("DirectSwitch")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundColor(AppleTheme.textPrimary)
                    }
                    .fixedSize()
                }

                Spacer(minLength: 4)

                if showBackButton {
                    Text(title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(AppleTheme.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)

                    Spacer(minLength: 4)
                }

                Button(action: onTapPassBadge) {
                    HStack(spacing: 5) {
                        Image(systemName: "crown.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(AppleTheme.premiumAmber)
                        Text(isProUnlocked ? "Premium Attivo" : "Premium Direct")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(AppleTheme.premiumGold)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(AppleTheme.premiumSurface)
                    .clipShape(Capsule())
                    .overlay(
                        Capsule()
                            .stroke(AppleTheme.premiumBorder.opacity(0.65), lineWidth: 1.0)
                    )
                    .shadow(color: AppleTheme.premiumAmber.opacity(0.14), radius: 4, x: 0, y: 2)
                }
                .buttonStyle(.plain)
                .fixedSize()
            }
            .padding(.horizontal, 16)
            .frame(height: 50)
            .background(AppleTheme.headerBg)

            Rectangle()
                .fill(AppleTheme.hairline)
                .frame(height: 0.6)
        }
    }
}

// MARK: - Pulsante ⓘ informativo

struct InfoCircleButton: View {
    let title: String
    let message: String
    @State private var isPresented: Bool = false

    var body: some View {
        Button(action: { isPresented = true }) {
            Image(systemName: "info.circle")
                .font(.system(size: 17, weight: .medium))
                .foregroundColor(AppleTheme.blue)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $isPresented) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    Image(systemName: "info.circle.fill")
                        .font(.system(size: 22))
                        .foregroundColor(AppleTheme.blue)
                    Text(title)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(AppleTheme.textPrimary)
                    Spacer()
                }
                .padding(.top, 8)

                Text(message)
                    .font(.system(size: 15))
                    .foregroundColor(AppleTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 8)

                Button(action: { isPresented = false }) {
                    Text("Chiudi")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(AppleTheme.blue)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            .padding(20)
            .background(AppleTheme.backgroundGradient.ignoresSafeArea())
            .presentationDetents([.height(290), .medium])
            .presentationDragIndicator(.visible)
            .preferredColorScheme(.light)
        }
    }
}

// MARK: - Pulsanti Apple HIG

struct ApplePrimaryButton: View {
    let title: String
    var icon: String? = nil
    var color: Color = AppleTheme.blue
    var isDisabled: Bool = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let iconName = icon {
                    Image(systemName: iconName)
                        .font(.system(size: 15, weight: .semibold))
                }
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(isDisabled ? color.opacity(0.50) : color)
            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
    }
}

struct AppleNeutralOutlinedButton: View {
    let title: String
    var icon: String = "arrow.left.arrow.right"
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(AppleTheme.slate)
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(AppleTheme.textPrimary)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(AppleTheme.inputSurface)
            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .stroke(AppleTheme.cardBorder, lineWidth: 1.0)
            )
        }
        .buttonStyle(.plain)
    }
}

struct AppleSecondaryButton: View {
    let title: String
    var icon: String? = nil
    var tint: Color = AppleTheme.blue
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let iconName = icon {
                    Image(systemName: iconName)
                        .font(.system(size: 15, weight: .semibold))
                }
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
            }
            .foregroundColor(tint)
            .frame(maxWidth: .infinity)
            .frame(height: 45)
            .background(AppleTheme.inputSurface)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Riga categoria pulita in stile Impostazioni Apple / Passa a iOS (sottotitolo dentro ⓘ)

struct CleanCategoryToggleRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    var countBadge: String? = nil
    var infoMessage: String = ""
    @Binding var isOn: Bool

    private var fullInfoText: String {
        if let badge = countBadge, !badge.isEmpty {
            return infoMessage.isEmpty ? "Rilevati sul dispositivo: \(badge)." : "\(infoMessage)\n\nStato attuale: \(badge)."
        }
        return infoMessage.isEmpty ? "Seleziona se includere \(title.lowercased()) nel trasferimento." : infoMessage
    }

    var body: some View {
        HStack(spacing: 12) {
            AppleSettingsIcon(systemName: icon, color: iconColor)

            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(AppleTheme.textPrimary)

            InfoCircleButton(
                title: title,
                message: fullInfoText
            )

            Spacer()

            Toggle("", isOn: $isOn)
                .labelsHidden()
                .tint(AppleTheme.green)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}

// MARK: - Caselle codice a 6 cifre in stile "Passa a iOS" / "Passa a Android"

struct PassaAiOSCodeBoxesView: View {
    let code: String

    private var digits: [String] {
        let chars = Array(code.filter { $0.isNumber }.prefix(6))
        return (0..<6).map { idx in
            idx < chars.count ? String(chars[idx]) : "•"
        }
    }

    var body: some View {
        HStack(spacing: 7) {
            ForEach(0..<6, id: \.self) { idx in
                Text(digits[idx])
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundColor(AppleTheme.textPrimary)
                    .frame(width: 44, height: 56)
                    .background(AppleTheme.inputSurface)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(AppleTheme.cardBorder, lineWidth: 0.9)
                    )

                if idx == 2 {
                    Spacer()
                        .frame(width: 6)
                }
            }
        }
    }
}

struct PassaAiOSPinInputView: View {
    @Binding var pin: String
    @FocusState private var isFocused: Bool
    var onComplete: (() -> Void)? = nil

    private var digits: [String] {
        let chars = Array(pin.filter { $0.isNumber }.prefix(6))
        return (0..<6).map { idx in
            idx < chars.count ? String(chars[idx]) : ""
        }
    }

    var body: some View {
        ZStack {
            TextField("", text: $pin)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .focused($isFocused)
                .opacity(0.01)
                .frame(width: 1, height: 1)
                .onChange(of: pin) { newVal in
                    let filtered = String(newVal.filter { $0.isNumber }.prefix(6))
                    if filtered != newVal {
                        pin = filtered
                    }
                    if filtered.count == 6 {
                        onComplete?()
                    }
                }

            HStack(spacing: 7) {
                ForEach(0..<6, id: \.self) { idx in
                    let currentCount = pin.filter { $0.isNumber }.count
                    let isActiveSlot = isFocused && (idx == currentCount || (currentCount == 6 && idx == 5))

                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(digits[idx].isEmpty ? AppleTheme.inputSurface : AppleTheme.cardSelected)
                            .frame(width: 44, height: 56)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(isActiveSlot ? AppleTheme.blue : AppleTheme.cardBorder, lineWidth: isActiveSlot ? 1.8 : 0.9)
                            )

                        if digits[idx].isEmpty && isActiveSlot {
                            RoundedRectangle(cornerRadius: 1)
                                .fill(AppleTheme.blue)
                                .frame(width: 2, height: 22)
                        } else {
                            Text(digits[idx])
                                .font(.system(size: 25, weight: .bold, design: .rounded))
                                .foregroundColor(AppleTheme.textPrimary)
                        }
                    }

                    if idx == 2 {
                        Spacer()
                            .frame(width: 6)
                    }
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                isFocused = true
            }
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                isFocused = true
            }
        }
    }
}

// MARK: - Avviso + Redirect diretto alla voce «Rete locale» di DirectSwitch nelle Impostazioni iOS

struct LocalNetworkRedirectBanner: View {
    var detailMessage: String? = nil
    var onOpenSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 10) {
                AppleSettingsIcon(systemName: "wifi.exclamationmark", color: AppleTheme.orange, size: 32)
                Text("Abilita «Rete locale» per avviare")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(AppleTheme.textPrimary)
                Spacer()
                InfoCircleButton(
                    title: "Perché serve «Rete locale»",
                    message: "Su iPhone, Apple blocca il collegamento diretto Wi-Fi / Hotspot tra due telefoni se l'interruttore «Rete locale» è spento.\n\n1. Tocca il pulsante arancione qui sotto: si aprirà direttamente la pagina di DirectSwitch in Impostazioni.\n2. Attiva l'interruttore verde alla voce «Rete locale» (su entrambi gli iPhone).\n3. Torna in DirectSwitch: il trasferimento partirà subito."
                )
            }

            Text(
                detailMessage
                    ?? "Se il trasferimento non si avvia, DirectSwitch non è abilitata per le reti locali. Tocca qui sotto per aprire direttamente la scheda di DirectSwitch in Impostazioni e attivare la voce «Rete locale»."
            )
            .font(.system(size: 13, weight: .medium))
            .foregroundColor(AppleTheme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)

            ApplePrimaryButton(
                title: "Attiva «Rete locale» in Impostazioni",
                icon: "gearshape.fill",
                color: AppleTheme.orange,
                action: onOpenSettings
            )
        }
        .padding(14)
        .background(AppleTheme.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(AppleTheme.orange.opacity(0.65), lineWidth: 1.2)
        )
    }
}

// MARK: - Utilità grafiche condivise (QR & Byte Formatter)

enum DirectSwitchUIHelpers {
    static func formatBytes(_ bytes: Int64) -> String {
        guard bytes > 0 else { return "0 MB" }
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    static func generateQrImage(from string: String) -> UIImage? {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"
        guard let outputImage = filter.outputImage else { return nil }
        let scaled = outputImage.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}
