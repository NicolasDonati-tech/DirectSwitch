//
//  DirectSwitchBackgroundKeepAlive.swift
//  DirectSwitch-iOS
//
//  Created by Nicolas Donati.
//  Copyright © 2026 Nicolas Donati. Tutti i diritti riservati.
//

import Foundation
import UIKit
import BackgroundTasks
import UserNotifications

/// Gestore del processo di esecuzione in background e anti-standby per i trasferimenti iOS:
/// 1) Mantiene lo schermo sveglio (`isIdleTimerDisabled = true`) sia su Invia che su Ricevi.
/// 2) Acquisisce e rinnova `UIBackgroundTaskIdentifier` (`beginBackgroundTask`) per mantenere attivi i socket
///    TCP/HTTP locali quando l'utente passa temporaneamente in Impostazioni, WhatsApp o risponde a una chiamata.
/// 3) Registra `BGProcessingTaskRequest` (`com.directswitch.ios.transfer.keepalive`) su `BGTaskScheduler`.
/// 4) Invia un avviso immediato locale se iOS sta per congelare i socket in background, e notifica il completamento.
@MainActor
final class iOSBackgroundTransferKeepAlive: NSObject {
    static let shared = iOSBackgroundTransferKeepAlive()
    static let bgTaskIdentifier = "com.directswitch.ios.transfer.keepalive"

    private var didRegisterScheduler = false
    private var isSessionActive = false
    private var activeRoleLabel = ""
    private var currentPercent: Int = 0
    private var currentDetail: String = ""
    private var didSendExpiryWarningInCurrentBackgroundSpan = false

    private var bgTaskId: UIBackgroundTaskIdentifier = .invalid
    private var backgroundWatchdogTask: Task<Void, Never>? = nil
    private var observersInstalled = false

    var onReturnToForegroundWhileActive: (() -> Void)?

    private override init() {
        super.init()
    }

    /// Da invocare una sola volta all'avvio dell'app (`DirectSwitchApp.init()`).
    nonisolated func registerBackgroundTasks() {
        Task { @MainActor in
            self.registerOnMainIfNeeded()
        }
    }

    private func registerOnMainIfNeeded() {
        guard !didRegisterScheduler else { return }
        didRegisterScheduler = true

        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.bgTaskIdentifier,
            using: nil
        ) { task in
            guard let processingTask = task as? BGProcessingTask else {
                task.setTaskCompleted(success: true)
                return
            }
            processingTask.expirationHandler = {
                processingTask.setTaskCompleted(success: false)
            }
            Task { @MainActor in
                if !iOSBackgroundTransferKeepAlive.shared.isSessionActive {
                    processingTask.setTaskCompleted(success: true)
                } else {
                    // Mantiene viva la finestra di rete concessa da BGTaskScheduler
                    try? await Task.sleep(nanoseconds: 15_000_000_000)
                    processingTask.setTaskCompleted(success: true)
                }
            }
        }

        installLifecycleObserversIfNeeded()
    }

    func requestNotificationPermissionIfNeeded() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            if settings.authorizationStatus == .notDetermined {
                UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
            }
        }
    }

    func beginActiveSession(roleLabel: String) {
        installLifecycleObserversIfNeeded()
        isSessionActive = true
        activeRoleLabel = roleLabel
        currentPercent = 0
        currentDetail = roleLabel
        didSendExpiryWarningInCurrentBackgroundSpan = false

        UIApplication.shared.isIdleTimerDisabled = true
        acquireOrRenewBackgroundTask()
        requestNotificationPermissionIfNeeded()
    }

    func updateProgress(percent: Int, detail: String) {
        currentPercent = max(0, min(100, percent))
        if !detail.isEmpty {
            currentDetail = detail
        }
    }

    func endActiveSession(completed: Bool, completionSummary: String? = nil) {
        let wasActive = isSessionActive
        isSessionActive = false
        backgroundWatchdogTask?.cancel()
        backgroundWatchdogTask = nil

        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.bgTaskIdentifier)
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ["ds_bg_keepalive_warn"])

        if completed && wasActive && UIApplication.shared.applicationState != .active {
            postLocalNotification(
                id: "ds_bg_transfer_done",
                title: "Trasferimento DirectSwitch completato",
                body: completionSummary ?? "Tutti i dati selezionati sono pronti su questo iPhone."
            )
        }

        releaseBackgroundTask()
        UIApplication.shared.isIdleTimerDisabled = false
    }

    // MARK: - Gestione ciclo di vita iOS Foreground / Background

    private func installLifecycleObserversIfNeeded() {
        guard !observersInstalled else { return }
        observersInstalled = true

        NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleDidEnterBackground()
            }
        }

        NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleWillEnterForeground()
            }
        }
    }

    private func handleDidEnterBackground() {
        guard isSessionActive else { return }
        didSendExpiryWarningInCurrentBackgroundSpan = false
        acquireOrRenewBackgroundTask()
        scheduleBackgroundProcessingRequest()
        startBackgroundRemainingWatchdog()
    }

    private func handleWillEnterForeground() {
        backgroundWatchdogTask?.cancel()
        backgroundWatchdogTask = nil
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ["ds_bg_keepalive_warn"])

        guard isSessionActive else { return }
        UIApplication.shared.isIdleTimerDisabled = true
        acquireOrRenewBackgroundTask()
        onReturnToForegroundWhileActive?()
    }

    private func acquireOrRenewBackgroundTask() {
        let previous = bgTaskId
        let newId = UIApplication.shared.beginBackgroundTask(withName: "DirectSwitchActiveTransfer") { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if self.isSessionActive && !self.didSendExpiryWarningInCurrentBackgroundSpan {
                    self.didSendExpiryWarningInCurrentBackgroundSpan = true
                    self.postLocalNotification(
                        id: "ds_bg_keepalive_warn",
                        title: "Copia DirectSwitch in pausa in background (\(self.currentPercent)%)",
                        body: "Tocca per riaprire DirectSwitch: il trasferimento riprenderà subito da dove era rimasto."
                    )
                }
                self.releaseBackgroundTask()
            }
        }
        bgTaskId = newId
        if previous != .invalid && previous != newId {
            UIApplication.shared.endBackgroundTask(previous)
        }
    }

    private func releaseBackgroundTask() {
        guard bgTaskId != .invalid else { return }
        let idToEnd = bgTaskId
        bgTaskId = .invalid
        UIApplication.shared.endBackgroundTask(idToEnd)
    }

    private func scheduleBackgroundProcessingRequest() {
        let req = BGProcessingTaskRequest(identifier: Self.bgTaskIdentifier)
        req.requiresNetworkConnectivity = true
        req.requiresExternalPower = false
        try? BGTaskScheduler.shared.submit(req)
    }

    private func startBackgroundRemainingWatchdog() {
        backgroundWatchdogTask?.cancel()
        backgroundWatchdogTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                guard let self, !Task.isCancelled, self.isSessionActive else { break }
                guard UIApplication.shared.applicationState == .background else { break }

                let remaining = UIApplication.shared.backgroundTimeRemaining
                // Se iOS concede una finestra limitata e restano meno di 14 secondi, avvisa subito l'utente
                if remaining < 14.0 && remaining > 0.0 && !self.didSendExpiryWarningInCurrentBackgroundSpan {
                    self.didSendExpiryWarningInCurrentBackgroundSpan = true
                    self.postLocalNotification(
                        id: "ds_bg_keepalive_warn",
                        title: "Mantieni attivo il trasferimento (\(self.currentPercent)%)",
                        body: "Tocca qui per tornare in DirectSwitch ed evitare che iOS sospenda la rete Wi-Fi in background."
                    )
                    break
                }
            }
        }
    }

    private func postLocalNotification(id: String, title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        if #available(iOS 15.0, *) {
            content.interruptionLevel = .timeSensitive
        }
        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
