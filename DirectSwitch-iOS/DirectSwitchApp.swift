//
//  DirectSwitchApp.swift
//  DirectSwitch-iOS
//
//  Created by Nicolas Donati.
//  Copyright © 2026 Nicolas Donati. Tutti i diritti riservati.
//

import SwiftUI

@main
struct DirectSwitchApp: App {
    init() {
        iOSBackgroundTransferKeepAlive.shared.registerBackgroundTasks()
    }

    var body: some Scene {
        WindowGroup {
            DirectSwitchMainView()
        }
    }
}
