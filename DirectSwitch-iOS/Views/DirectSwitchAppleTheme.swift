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

// MARK: - Tema grafico Apple HIG (Base Perla / Grafite Dark Mode Nativa, Zero Viola)

enum AppleTheme {
    private static func dynamic(light: UIColor, dark: UIColor) -> Color {
        Color(UIColor { traits in
            traits.userInterfaceStyle == .dark ? dark : light
        })
    }

    static let canvasTop = dynamic(
        light: UIColor(red: 0.878, green: 0.906, blue: 0.945, alpha: 1),
        dark: UIColor(red: 0.055, green: 0.075, blue: 0.110, alpha: 1)
    )
    static let canvasMid = dynamic(
        light: UIColor(red: 0.914, green: 0.933, blue: 0.965, alpha: 1),
        dark: UIColor(red: 0.075, green: 0.102, blue: 0.149, alpha: 1)
    )
    static let canvasBottom = dynamic(
        light: UIColor(red: 0.855, green: 0.886, blue: 0.933, alpha: 1),
        dark: UIColor(red: 0.043, green: 0.059, blue: 0.090, alpha: 1)
    )

    static let headerBg = dynamic(
        light: UIColor(red: 0.898, green: 0.922, blue: 0.957, alpha: 0.95),
        dark: UIColor(red: 0.067, green: 0.090, blue: 0.133, alpha: 0.95)
    )
    static let cardSurface = dynamic(
        light: UIColor(red: 0.973, green: 0.980, blue: 0.992, alpha: 1),
        dark: UIColor(red: 0.110, green: 0.145, blue: 0.204, alpha: 1)
    )
    static let cardSelected = dynamic(
        light: UIColor(red: 0.918, green: 0.949, blue: 0.996, alpha: 1),
        dark: UIColor(red: 0.118, green: 0.196, blue: 0.306, alpha: 1)
    )
    static let inputSurface = dynamic(
        light: UIColor(red: 0.918, green: 0.937, blue: 0.965, alpha: 1),
        dark: UIColor(red: 0.149, green: 0.192, blue: 0.263, alpha: 1)
    )
    static let cardBorder = dynamic(
        light: UIColor(red: 0.812, green: 0.847, blue: 0.898, alpha: 1),
        dark: UIColor(red: 0.212, green: 0.267, blue: 0.353, alpha: 1)
    )
    static let hairline = dynamic(
        light: UIColor(red: 0.780, green: 0.816, blue: 0.871, alpha: 1),
        dark: UIColor(red: 0.204, green: 0.255, blue: 0.337, alpha: 1)
    )

    static let blue = dynamic(
        light: UIColor(red: 0.000, green: 0.478, blue: 1.000, alpha: 1),
        dark: UIColor(red: 0.239, green: 0.612, blue: 1.000, alpha: 1)
    )
    static let teal = dynamic(
        light: UIColor(red: 0.000, green: 0.541, blue: 0.659, alpha: 1),
        dark: UIColor(red: 0.180, green: 0.761, blue: 0.859, alpha: 1)
    )
    static let green = dynamic(
        light: UIColor(red: 0.204, green: 0.780, blue: 0.349, alpha: 1),
        dark: UIColor(red: 0.251, green: 0.835, blue: 0.420, alpha: 1)
    )
    static let orange = dynamic(
        light: UIColor(red: 1.000, green: 0.584, blue: 0.000, alpha: 1),
        dark: UIColor(red: 1.000, green: 0.667, blue: 0.157, alpha: 1)
    )
    static let red = dynamic(
        light: UIColor(red: 1.000, green: 0.231, blue: 0.188, alpha: 1),
        dark: UIColor(red: 1.000, green: 0.369, blue: 0.337, alpha: 1)
    )
    static let slate = dynamic(
        light: UIColor(red: 0.216, green: 0.255, blue: 0.318, alpha: 1),
        dark: UIColor(red: 0.580, green: 0.639, blue: 0.722, alpha: 1)
    )
    static let charcoal = dynamic(
        light: UIColor(red: 0.110, green: 0.118, blue: 0.137, alpha: 1),
        dark: UIColor(red: 0.941, green: 0.957, blue: 0.980, alpha: 1)
    )

    static let premiumGold = Color(red: 0.780, green: 0.451, blue: 0.020)
    static let premiumAmber = Color(red: 0.945, green: 0.588, blue: 0.039)
    static let premiumSurface = dynamic(
        light: UIColor(red: 1.000, green: 0.965, blue: 0.863, alpha: 1),
        dark: UIColor(red: 0.235, green: 0.180, blue: 0.075, alpha: 1)
    )
    static let premiumBorder = Color(red: 0.922, green: 0.659, blue: 0.145)

    static let indigo = slate

    static let textPrimary = dynamic(
        light: UIColor(red: 0.110, green: 0.110, blue: 0.118, alpha: 1),
        dark: UIColor(red: 0.957, green: 0.969, blue: 0.984, alpha: 1)
    )
    static let textSecondary = dynamic(
        light: UIColor(red: 0.388, green: 0.388, blue: 0.400, alpha: 1),
        dark: UIColor(red: 0.690, green: 0.733, blue: 0.796, alpha: 1)
    )
    static let textTertiary = dynamic(
        light: UIColor(red: 0.557, green: 0.557, blue: 0.576, alpha: 1),
        dark: UIColor(red: 0.514, green: 0.561, blue: 0.631, alpha: 1)
    )

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
                            Color(red: 0.063, green: 0.447, blue: 0.863), // #1072DC
                            Color(red: 0.004, green: 0.306, blue: 0.737), // #014EBC
                            Color(red: 0.000, green: 0.475, blue: 0.576)  // #007993
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

// MARK: - Barra superiore Apple HIG (pulita, senza badge a pagamento)

struct AppleTopNavigationBar: View {
    let title: String
    let showBackButton: Bool
    var isProUnlocked: Bool = true
    let onBack: () -> Void
    var onTapPassBadge: (() -> Void)? = nil
    @ObservedObject var l10n = DirectSwitchLocalizationStore.shared

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                HStack(spacing: 8) {
                    if showBackButton {
                        Button(action: onBack) {
                            HStack(spacing: 4) {
                                Image(systemName: "chevron.left")
                                    .font(.system(size: 16, weight: .semibold))
                                Text(l10n.tr("Indietro"))
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
                }

                if showBackButton {
                    Text(title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(AppleTheme.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                        .padding(.horizontal, 86)
                }
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
    @ObservedObject var l10n = DirectSwitchLocalizationStore.shared

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
                    Text(l10n.tr(title))
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(AppleTheme.textPrimary)
                    Spacer()
                }
                .padding(.top, 8)

                Text(l10n.tr(message))
                    .font(.system(size: 15))
                    .foregroundColor(AppleTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 8)

                Button(action: { isPresented = false }) {
                    Text(l10n.tr("Chiudi"))
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
        }
    }
}

// MARK: - Pulsanti Apple HIG

private struct ApplePressScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.985 : 1.0)
            .brightness(configuration.isPressed ? -0.05 : 0.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct ApplePrimaryButton: View {
    let title: String
    var icon: String? = nil
    var color: Color = AppleTheme.blue
    var isDisabled: Bool = false
    var isLoading: Bool = false
    var loadingTitle: String? = nil
    var action: () -> Void

    var body: some View {
        Button {
            guard !isDisabled && !isLoading else { return }
            action()
        } label: {
            HStack(spacing: 9) {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(0.9)
                    Text(loadingTitle ?? title)
                        .font(.system(size: 16, weight: .semibold))
                } else {
                    if let iconName = icon {
                        Image(systemName: iconName)
                            .font(.system(size: 15, weight: .semibold))
                    }
                    Text(title)
                        .font(.system(size: 16, weight: .semibold))
                }
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(isLoading ? color : (isDisabled ? color.opacity(0.42) : color))
            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        }
        .buttonStyle(ApplePressScaleButtonStyle())
        .disabled(isDisabled || isLoading)
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
    var premiumBadge: Bool = false
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
        TransferDisplayFormatting.formatBytes(bytes)
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
