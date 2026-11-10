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

// MARK: - Tema grafico Apple HIG (identità visiva condivisa con CloudSave)

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
    static let green = Color(red: 0.204, green: 0.780, blue: 0.349)          // Apple #34C759
    static let orange = Color(red: 1.000, green: 0.584, blue: 0.000)         // Apple #FF9500
    static let red = Color(red: 1.000, green: 0.231, blue: 0.188)            // Apple #FF3B30
    static let indigo = Color(red: 0.345, green: 0.337, blue: 0.839)         // Apple #5856D6
    static let teal = Color(red: 0.188, green: 0.690, blue: 0.780)           // Apple #30B0C7
    static let charcoal = Color(red: 0.110, green: 0.110, blue: 0.118)       // Apple #1C1C1E

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

// MARK: - Emblema scolpito DirectSwitch in stile Apple / Passa a iOS / CloudSave

struct DirectSwitchAppleEmblem: View {
    var size: CGFloat = 56

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.169, green: 0.651, blue: 1.000),
                            Color(red: 0.000, green: 0.400, blue: 0.961),
                            Color(red: 0.071, green: 0.169, blue: 0.533)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: size, height: size)
                .shadow(color: AppleTheme.blue.opacity(0.24), radius: 8, x: 0, y: 4)

            Canvas { context, canvasSize in
                let w = canvasSize.width
                let h = canvasSize.height

                // Telefono posteriore glassmorphic (in alto a destra)
                var backLayer = context
                backLayer.opacity = 0.38
                let backPhone = RoundedRectangle(cornerRadius: w * 0.09, style: .continuous)
                    .path(in: CGRect(x: w * 0.44, y: h * 0.16, width: w * 0.34, height: h * 0.52))
                backLayer.fill(backPhone, with: .color(.white))

                // Telefono principale scolpito bianco-perla (in basso a sinistra)
                context.drawLayer { layer in
                    var sub = layer
                    sub.addFilter(
                        .shadow(
                            color: Color(red: 0.02, green: 0.07, blue: 0.27).opacity(0.28),
                            radius: w * 0.045,
                            x: 0,
                            y: h * 0.028
                        )
                    )
                    let frontRect = CGRect(x: w * 0.22, y: h * 0.30, width: w * 0.36, height: h * 0.54)
                    let frontPath = RoundedRectangle(cornerRadius: w * 0.095, style: .continuous).path(in: frontRect)
                    sub.fill(
                        frontPath,
                        with: .linearGradient(
                            Gradient(colors: [
                                Color.white,
                                Color(red: 0.902, green: 0.945, blue: 1.000)
                            ]),
                            startPoint: CGPoint(x: w * 0.40, y: h * 0.30),
                            endPoint: CGPoint(x: w * 0.40, y: h * 0.84)
                        )
                    )
                }

                // Tacca altoparlante sottile sul telefono frontale
                let notchRect = CGRect(x: w * 0.35, y: h * 0.345, width: w * 0.10, height: h * 0.022)
                context.fill(
                    Capsule().path(in: notchRect),
                    with: .color(Color(red: 0.000, green: 0.400, blue: 0.961).opacity(0.32))
                )
            }
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.24, style: .continuous))

            // Frecce bidirezionali Apple Blue al centro dello schermo frontale (identiche all'AppIcon)
            Image(systemName: "arrow.left.arrow.right")
                .font(.system(size: size * 0.21, weight: .bold))
                .foregroundColor(AppleTheme.blue)
                .offset(x: -size * 0.10, y: size * 0.09)
        }
    }
}

struct GoogleGlyphIcon: View {
    var size: CGFloat = 19

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.white)
                .frame(width: size + 4, height: size + 4)
            Text("G")
                .font(.system(size: size * 0.82, weight: .bold, design: .rounded))
                .foregroundStyle(
                    LinearGradient(
                        colors: [
                            Color(red: 0.26, green: 0.52, blue: 0.96),
                            Color(red: 0.20, green: 0.66, blue: 0.33)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
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
                .font(.system(size: size * 0.47, weight: .semibold))
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

// MARK: - Barra superiore Apple HIG (identica a CloudSave)

struct AppleTopNavigationBar: View {
    let title: String
    let showBackButton: Bool
    let isProUnlocked: Bool
    let onBack: () -> Void
    let onTapPassBadge: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Text(title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(AppleTheme.textPrimary)
                    .lineLimit(1)

                HStack {
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
                    } else {
                        DirectSwitchAppleEmblem(size: 28)
                    }

                    Spacer()

                    Button(action: onTapPassBadge) {
                        HStack(spacing: 4) {
                            Image(systemName: isProUnlocked ? "checkmark.seal.fill" : "arrow.triangle.2.circlepath")
                                .font(.system(size: 11, weight: .semibold))
                            Text(isProUnlocked ? "Pro" : "Cross-OS")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .foregroundColor(isProUnlocked ? AppleTheme.green : AppleTheme.blue)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background((isProUnlocked ? AppleTheme.green : AppleTheme.blue).opacity(0.12))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
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

// MARK: - Pulsante ⓘ informativo (mantiene le schermate pulite senza muri di testo)

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
                        .font(.system(size: 16, weight: .semibold))
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

struct GoogleStyleActionButton: View {
    let title: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                GoogleGlyphIcon(size: 18)
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(AppleTheme.textPrimary)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 46)
            .background(AppleTheme.cardSurface)
            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .stroke(AppleTheme.cardBorder, lineWidth: 1.1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Riga categoria pulita in stile Impostazioni Apple / Android Switch / CloudSave

struct CleanCategoryToggleRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    var countBadge: String? = nil
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 14) {
            AppleSettingsIcon(systemName: icon, color: iconColor)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(AppleTheme.textPrimary)
                if let badge = countBadge, !badge.isEmpty {
                    Text(badge)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(AppleTheme.textSecondary)
                }
            }

            Spacer()

            Toggle("", isOn: $isOn)
                .labelsHidden()
                .tint(AppleTheme.green)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}

// MARK: - Caselle codice a 6 cifre in stile "Passa a iOS" (Display & Input)

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
            // Campo numerico invisibile ma pienamente accessibile che guida la tastiera numerica iOS
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

// MARK: - Utilità grafiche condivise (QR & Byte Formatter)

enum DirectSwitchUIHelpers {
    static func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: max(0, bytes))
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
