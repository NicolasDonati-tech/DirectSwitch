//
//  DirectSwitchMainView.swift
//  DirectSwitch-iOS
//
//  Created by Nicolas Donati.
//  Copyright © 2026 Nicolas Donati. Tutti i diritti riservati.
//

import SwiftUI
import AVFoundation
import CoreImage.CIFilterBuiltins
import UniformTypeIdentifiers
import UIKit

struct DirectSwitchMainView: View {
    @StateObject private var transport = DirectSwitchTransportViewModel()
    @State private var activeQr: QrPairingPayload? = nil
    @State private var showSenderSheet: Bool = false
    @State private var showCameraScanner: Bool = false
    @State private var showDocumentImporter: Bool = false
    @State private var senderQrInput: String = ""
    @State private var selectedBeaconForPin: DiscoveryBeaconPayload? = nil
    @State private var pinCodeInput: String = ""
    @State private var senderValidationNote: String? = nil
    @State private var sharedVaultBanner: String? = nil
    @State private var pickedDocuments: [(ManifestItem, URL)] = []
    @State private var scanSummary: iOSLocalDeviceScanSummary? = nil
    @State private var isScanningDevice: Bool = false
    @State private var includeContacts: Bool = true
    @State private var includePhotos: Bool = true
    @State private var includeVideos: Bool = true
    @State private var includeCalendars: Bool = true
    @State private var isProUnlocked: Bool = iOSLicenseStore.isLocalProUnlocked
    @State private var showProSheet: Bool = false
    @State private var billingNote: String? = nil

    private let tealPrimary = Color(red: 0.0, green: 0.56, blue: 0.48)
    private let blueAccent = Color(red: 0.0, green: 0.48, blue: 1.0)

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.87, green: 0.92, blue: 0.94),
                        Color(red: 0.91, green: 0.94, blue: 0.96),
                        Color(red: 0.84, green: 0.89, blue: 0.93)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 16) {
                        headerCard

                        if let banner = sharedVaultBanner {
                            vaultImportBanner(text: banner)
                        }

                        deviceStorageSummaryCard

                        if let qr = activeQr {
                            receiverQrCard(qr: qr)
                        } else if let portalUrl = transport.bootstrapPortalUrl {
                            bootstrapPortalQrCard(url: portalUrl)
                        } else {
                            roleCards
                        }

                        pricingTierCard
                    }
                    .padding(18)
                }
            }
            .task {
                isProUnlocked = await iOSLicenseStore.restoreStoreKitEntitlements()
                let staged = pickedDocuments.map(\.0)
                scanSummary = await Task.detached(priority: .utility) {
                    iOSDeviceDataAnalyzer.scanAuthorizedSummary(stagedItems: staged)
                }.value
            }
            .onOpenURL { incomingURL in
                handleIncomingURL(incomingURL)
            }
            .sheet(isPresented: $showProSheet) {
                proUnlockSheet
            }
            .sheet(isPresented: $showSenderSheet, onDismiss: {
                showCameraScanner = false
                transport.stopUdpAutoDiscovery()
            }) {
                senderTransferSheet
            }
        }
    }

    private func handleIncomingURL(_ incomingURL: URL) {
        if incomingURL.isFileURL {
            if let imported = iOSDocumentsSandboxBridge.importIncomingOpenURL(incomingURL) {
                pickedDocuments.append(imported)
                sharedVaultBanner = "Aggiunto '\(imported.0.fileName)' al Vault DirectSwitch e pronto per l'invio cifrato!"
                scanSummary = iOSDeviceDataAnalyzer.scanAuthorizedSummary(stagedItems: pickedDocuments.map(\.0))
                transport.startUdpAutoDiscovery()
                showSenderSheet = true
            }
            return
        }
        if let comps = URLComponents(url: incomingURL, resolvingAgainstBaseURL: false),
           let qrParam = comps.queryItems?.first(where: { $0.name == "qr" })?.value,
           !qrParam.isEmpty {
            senderQrInput = qrParam
            senderValidationNote = "Codice sessione acquisito dal collegamento rapido."
            transport.startUdpAutoDiscovery()
            showSenderSheet = true
        }
    }

    private var headerCard: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("DirectSwitch")
                    .font(.system(size: 24, weight: .bold))
                Text("Trasferimento diretto senza formattare l'iPhone")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }
            Spacer()
            Button(action: { showProSheet = true }) {
                Text(isProUnlocked ? "PRO ATTIVO" : "Android Bridge")
                    .font(.system(size: 11, weight: .bold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background((isProUnlocked ? tealPrimary : .orange).opacity(0.16))
                    .foregroundColor(isProUnlocked ? tealPrimary : .orange)
                    .clipShape(Capsule())
            }
        }
    }

    private func vaultImportBanner(text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.seal.fill")
                .foregroundColor(tealPrimary)
            Text(text)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.primary)
            Spacer()
            Button(action: { sharedVaultBanner = nil }) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.secondary)
            }
        }
        .padding(12)
        .background(Color.white.opacity(0.95))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var deviceStorageSummaryCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Stato Memoria & Dati iPhone", systemImage: "internaldrive")
                    .font(.system(size: 14, weight: .bold))
                Spacer()
                if let summary = scanSummary, summary.totalStorageBytes > 0 {
                    Text("\(formatBytes(summary.freeStorageBytes)) liberi su \(formatBytes(summary.totalStorageBytes))")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(tealPrimary)
                }
            }

            if let summary = scanSummary, summary.totalStorageBytes > 0 {
                let used = max(0, summary.totalStorageBytes - summary.freeStorageBytes)
                ProgressView(value: Double(used), total: Double(max(1, summary.totalStorageBytes)))
                    .tint(blueAccent)

                if summary.hasFullPermissions || summary.contactsCount > 0 || summary.photosCount > 0 || !pickedDocuments.isEmpty {
                    Text("Contatti: \(summary.contactsCount) • Foto: \(summary.photosCount) • Video: \(summary.videosCount) • Calendari: \(summary.calendarEventsCount) • Vault: \(pickedDocuments.count)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                }
            }

            if !(scanSummary?.hasFullPermissions ?? false) {
                Button(action: {
                    isScanningDevice = true
                    let staged = pickedDocuments.map(\.0)
                    Task {
                        scanSummary = await iOSDeviceDataAnalyzer.requestPermissionsAndScanAll(stagedItems: staged)
                        isScanningDevice = false
                    }
                }) {
                    Text(isScanningDevice ? "Analisi contenuti in corso..." : "Analizza Contenuti di Questo iPhone (Contatti, Foto, Video)")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(tealPrimary.opacity(0.12))
                        .foregroundColor(tealPrimary)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .disabled(isScanningDevice)
            }
        }
        .padding(14)
        .background(Color.white.opacity(0.93))
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    private var roleCards: some View {
        VStack(spacing: 14) {
            // Card 1: Passaggio iPhone -> Android con Configura / Android Switch Nativo di Google
            VStack(alignment: .leading, spacing: 10) {
                Label("Passa a un Nuovo Android (Configura Google)", systemImage: "cable.connector.horizontal")
                    .font(.system(size: 16, weight: .bold))
                Text("Se il tuo nuovo telefono è un Android già configurato, apri DirectSwitch sull'Android e premi '3. Da iPhone → a Questo Android': potrai collegare il cavo USB-C/Lightning o usare Android Switch ufficiale.")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)

                Button(action: {
                    if let url = URL(string: "https://apps.apple.com/app/switch-to-android/id1611395432") {
                        UIApplication.shared.open(url)
                    }
                }) {
                    Text("Apri 'Android Switch' di Google su iPhone (Opzionale)")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(blueAccent.opacity(0.12))
                        .foregroundColor(blueAccent)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
            .padding(16)
            .background(Color.white.opacity(0.94))
            .clipShape(RoundedRectangle(cornerRadius: 18))

            // Card 2: Nuovo iPhone (Ricevi da Android o iPhone)
            VStack(alignment: .leading, spacing: 10) {
                Label("Questo è il Nuovo iPhone (Ricevi)", systemImage: "qrcode")
                    .font(.system(size: 17, weight: .bold))
                Text("Mostra il codice QR e il PIN a 6 cifre per ricevere Contatti (Smart Merge senza doppioni), Foto HEIC/JPG, Video 4K, Album, SMS, Documenti e Calendari dal vecchio Android o iPhone già configurato.")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)

                Button(action: {
                    activeQr = transport.startReceiverServer()
                }) {
                    Text("Ricevi Dati su Questo iPhone")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(blueAccent)
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
            }
            .padding(16)
            .background(Color.white.opacity(0.92))
            .clipShape(RoundedRectangle(cornerRadius: 18))

            // Card 3: Vecchio iPhone (Invia con Motore Diretto DirectSwitch + Portale Rubrica QR)
            VStack(alignment: .leading, spacing: 10) {
                Label("Questo è il Vecchio iPhone (Invia Diretto)", systemImage: "arrow.up.doc.fill")
                    .font(.system(size: 17, weight: .bold))
                Text("Invia Contatti, Foto con Album reali, Video 4K, Calendari, Documenti e Chat WhatsApp (.zip anche da 'Esporta chat → DirectSwitch') in Wi-Fi locale senza passare da iCloud.")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)

                Button(action: {
                    senderValidationNote = nil
                    selectedBeaconForPin = nil
                    pinCodeInput = ""
                    transport.startUdpAutoDiscovery()
                    showSenderSheet = true
                }) {
                    Text("Invia Dati da Questo iPhone")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(tealPrimary)
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }

                Button(action: {
                    Task {
                        _ = await transport.startBootstrapPortalSession()
                    }
                }) {
                    Label("Portale QR Rapido Rubrica (.vcf senza App)", systemImage: "person.crop.circle.badge.checkmark")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(tealPrimary.opacity(0.12))
                        .foregroundColor(tealPrimary)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
            .padding(16)
            .background(Color.white.opacity(0.92))
            .clipShape(RoundedRectangle(cornerRadius: 18))

            liveSessionStatusCard
        }
    }

    private var liveSessionStatusCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Stato Sessione", systemImage: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                if transport.isCompleted {
                    Text("COMPLETATO")
                        .font(.system(size: 10, weight: .heavy))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(tealPrimary.opacity(0.16))
                        .foregroundColor(tealPrimary)
                        .clipShape(Capsule())
                }
            }

            Text(transport.statusLabel)
                .font(.system(size: 13))
                .foregroundColor(.secondary)

            if transport.totalItems > 0 {
                ProgressView(
                    value: Double(min(transport.completedItems, transport.totalItems)),
                    total: Double(max(1, transport.totalItems))
                )
                .tint(tealPrimary)
            }

            if transport.totalItems > 0 || transport.mergedContacts > 0 || transport.importedSms > 0 || transport.skippedDuplicates > 0 {
                Text(String(format: "Velocità: %.1f MB/s • File: %d/%d (%@) • Contatti: %d • Duplicati evitati: %d",
                            transport.speedMegabytesPerSec,
                            transport.completedItems,
                            transport.totalItems,
                            formatBytes(transport.transferredBytesCount),
                            transport.mergedContacts,
                            transport.skippedDuplicates))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(tealPrimary)
            }

            if transport.importedSms > 0 || (transport.isCompleted && transport.completedItems > 0) {
                Text("Documenti, Archivi WhatsApp e SMS sono consultabili nell'app File → Su iPhone → DirectSwitch.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            if let err = transport.errorMessage {
                Text(err)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.red)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.white.opacity(0.92))
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    private func receiverQrCard(qr: QrPairingPayload) -> some View {
        VStack(spacing: 12) {
            Text("Inquadra dal Vecchio Android o iPhone")
                .font(.system(size: 17, weight: .bold))

            if let img = generateQrImage(from: qr.toCompactJson()) {
                Image(uiImage: img)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 220, height: 220)
                    .padding(12)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            }

            if !transport.activePairingPin.isEmpty {
                VStack(spacing: 2) {
                    Text("PIN Auto-Discovery (senza fotocamera)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)
                    Text(transport.activePairingPin)
                        .font(.system(size: 24, weight: .heavy, design: .monospaced))
                        .kerning(4)
                        .foregroundColor(blueAccent)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 8)
                .background(blueAccent.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            Text(transport.statusLabel)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(tealPrimary)
                .multilineTextAlignment(.center)

            if transport.totalItems > 0 {
                ProgressView(
                    value: Double(min(transport.completedItems, transport.totalItems)),
                    total: Double(max(1, transport.totalItems))
                )
                .tint(tealPrimary)
            }

            if transport.totalItems > 0 || transport.mergedContacts > 0 || transport.importedSms > 0 {
                Text("Contatti uniti: \(transport.mergedContacts) • Calendari: \(transport.importedCalendars) • SMS: \(transport.importedSms) • File: \(transport.completedItems)/\(transport.totalItems) (\(formatBytes(transport.transferredBytesCount)))")
                    .font(.system(size: 13))
                    .multilineTextAlignment(.center)
            }

            if let err = transport.errorMessage {
                Text(err)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
            }

            Button("Chiudi Sessione QR") {
                transport.stopReceiverServer()
                activeQr = nil
            }
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(blueAccent)
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .background(Color.white.opacity(0.95))
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    private func bootstrapPortalQrCard(url: String) -> some View {
        VStack(spacing: 12) {
            Text("Portale Rubrica Rapida (.vcf)")
                .font(.system(size: 17, weight: .bold))
            Text("Inquadra questo QR con la fotocamera del nuovo telefono connesso alla stessa Wi-Fi per importare subito l'intera Rubrica.")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            if let img = generateQrImage(from: url) {
                Image(uiImage: img)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 210, height: 210)
                    .padding(12)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            }

            Text(url)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Button("Chiudi Portale Rubrica") {
                transport.stopReceiverServer()
            }
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(blueAccent)
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .background(Color.white.opacity(0.95))
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    private var senderTransferSheet: some View {
        ScrollView {
            VStack(spacing: 14) {
                Text("Invia Dati al Nuovo Telefono")
                    .font(.system(size: 20, weight: .bold))

                if !transport.discoveredBeacons.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Dispositivo Rilevato Automaticamente in Wi-Fi:")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(tealPrimary)
                        ForEach(transport.discoveredBeacons, id: \.sessionId) { found in
                            Button(action: {
                                selectedBeaconForPin = found
                                senderValidationNote = nil
                                showCameraScanner = false
                            }) {
                                Text("Collega a \(found.receiverName) (\(found.receiverPlatform.rawValue)) con PIN")
                                    .font(.system(size: 14, weight: .semibold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .background(tealPrimary)
                                    .foregroundColor(.white)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                        }
                    }
                }

                if let beacon = selectedBeaconForPin {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Inserisci il PIN a 6 cifre mostrato su \(beacon.receiverName):")
                            .font(.system(size: 13, weight: .semibold))
                        HStack(spacing: 8) {
                            TextField("PIN 6 cifre", text: $pinCodeInput)
                                .keyboardType(.numberPad)
                                .textFieldStyle(.roundedBorder)
                            Button("Conferma PIN") {
                                Task {
                                    do {
                                        let paired = try await transport.pairWithBeaconUsingPin(beacon: beacon, pin: pinCodeInput)
                                        senderQrInput = paired.toCompactJson()
                                        selectedBeaconForPin = nil
                                        senderValidationNote = "Accoppiato in modo sicuro con \(paired.receiverName)!"
                                    } catch {
                                        senderValidationNote = error.localizedDescription
                                    }
                                }
                            }
                            .font(.system(size: 13, weight: .bold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(blueAccent)
                            .foregroundColor(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                    }
                    .padding(12)
                    .background(blueAccent.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                Button(action: { showCameraScanner.toggle() }) {
                    Label(showCameraScanner ? "Chiudi Fotocamera QR" : "Inquadra QR con la Fotocamera", systemImage: "camera.viewfinder")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(blueAccent.opacity(0.14))
                        .foregroundColor(blueAccent)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                if showCameraScanner {
                    QrCameraScannerView { scannedCode in
                        senderQrInput = scannedCode
                        senderValidationNote = "Codice QR acquisito correttamente."
                        showCameraScanner = false
                    }
                    .frame(height: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }

                TextField("Oppure incolla codice QR del ricevente", text: $senderQrInput)
                    .textFieldStyle(.roundedBorder)

                if let note = senderValidationNote {
                    Text(note)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(senderQrInput.isEmpty ? .red : tealPrimary)
                }

                Toggle("Rubrica Contatti (Smart Merge)", isOn: $includeContacts)
                Toggle("Foto & Album Utente (HEIC/EXIF + GPS)", isOn: $includePhotos)
                Toggle("Video HD / 4K Originali", isOn: $includeVideos)
                Toggle("Calendari ed Eventi", isOn: $includeCalendars)

                Button(action: { showDocumentImporter = true }) {
                    Label(
                        pickedDocuments.isEmpty
                            ? "Aggiungi Documenti o Archivio WhatsApp (.zip)"
                            : "File nel Vault pronti all'invio: \(pickedDocuments.count) (Tocca per aggiungere)",
                        systemImage: "folder.badge.plus"
                    )
                    .font(.system(size: 13, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(tealPrimary.opacity(0.12))
                    .foregroundColor(tealPrimary)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                if !pickedDocuments.isEmpty {
                    HStack {
                        Text(pickedDocuments.map { $0.0.fileName }.joined(separator: ", "))
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                        Spacer()
                        Button("Svuota") {
                            pickedDocuments.removeAll()
                            iOSDocumentsSandboxBridge.clearStagedVault()
                        }
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.red)
                    }
                }

                Button(action: {
                    guard let qr = try? QrPairingPayload.fromJson(senderQrInput) else {
                        senderValidationNote = "Inquadra prima il codice QR del nuovo telefono oppure inserisci il PIN Auto-Discovery."
                        return
                    }
                    let docsSnapshot = pickedDocuments
                    pickedDocuments.removeAll()
                    sharedVaultBanner = nil
                    showSenderSheet = false
                    Task {
                        await transport.executeSenderTransfer(
                            qrPayload: qr,
                            includeContacts: includeContacts,
                            includePhotos: includePhotos,
                            includeVideos: includeVideos,
                            includeCalendars: includeCalendars,
                            pickedDocuments: docsSnapshot
                        )
                    }
                }) {
                    Text("Avvia Trasferimento Cifrato")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(tealPrimary)
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                Button("Chiudi") { showSenderSheet = false }
            }
            .padding(22)
        }
        .fileImporter(
            isPresented: $showDocumentImporter,
            allowedContentTypes: [.item],
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result {
                let imported = iOSDocumentsSandboxBridge.importPickedDocumentURLs(urls)
                pickedDocuments.append(contentsOf: imported)
                scanSummary = iOSDeviceDataAnalyzer.scanAuthorizedSummary(stagedItems: pickedDocuments.map(\.0))
            }
        }
        .presentationDetents([.large])
    }

    private var pricingTierCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("iPhone ↔ iPhone: 100% Gratuito Illimitato")
                .font(.system(size: 14, weight: .bold))
            Text("Il ponte Android ↔ iPhone include la Rubrica gratuita e si sblocca su UN SOLO telefono (Single-Side Unlock) o con abbonamento CloudSave Pro verificato.")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.white.opacity(0.9))
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    private var proUnlockSheet: some View {
        VStack(spacing: 16) {
            Text("DirectSwitch Pass Cross-OS")
                .font(.system(size: 20, weight: .bold))
            Text("Sblocca il trasferimento illimitato Android ↔ iPhone (Foto HEIC/JPG, Video 4K, Album, Calendari, SMS e File). Paghi su un solo telefono e vale per entrambi.")
                .font(.system(size: 14))
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)

            if let note = billingNote {
                Text(note)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(tealPrimary)
                    .multilineTextAlignment(.center)
            }

            Button(action: {
                Task {
                    let (ok, msg) = await iOSLicenseStore.purchaseCrossOsPass()
                    billingNote = msg
                    if ok {
                        isProUnlocked = true
                        showProSheet = false
                    }
                }
            }) {
                Text(isProUnlocked ? "Pass Già Attivo" : "Acquista Pass Cross-OS Una Tantum (9,99 €)")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(tealPrimary)
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }

            Button("Ripristina Acquisti App Store") {
                Task {
                    let restored = await iOSLicenseStore.restoreStoreKitEntitlements()
                    isProUnlocked = restored
                    billingNote = restored ? "Acquisto App Store ripristinato!" : "Nessun acquisto precedente trovato."
                }
            }
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(blueAccent)

            Button("Chiudi") { showProSheet = false }
        }
        .padding(24)
        .presentationDetents([.medium])
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: max(0, bytes))
    }

    private func generateQrImage(from string: String) -> UIImage? {
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

/// ViewController dedicato per la scansione QR che adatta dinamicamente `previewLayer.frame`
/// e rilascia l'`AVCaptureSession` alla chiusura dello scanner.
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

/// Scanner fotocamera nativo iOS (`AVCaptureSession` + `AVCaptureMetadataOutput`) per codici QR DirectSwitch.
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
        var session: AVCaptureSession?
        private var didEmit = false

        init(onCodeScanned: @escaping (String) -> Void) {
            self.onCodeScanned = onCodeScanned
        }

        func metadataOutput(
            _ output: AVCaptureMetadataOutput,
            didOutput metadataObjects: [AVMetadataObject],
            from connection: AVCaptureConnection
        ) {
            guard !didEmit,
                  let readable = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
                  let val = readable.stringValue else { return }
            didEmit = true
            if let activeSession = session, activeSession.isRunning {
                DispatchQueue.global(qos: .utility).async {
                    activeSession.stopRunning()
                }
            }
            onCodeScanned(val)
        }
    }
}
