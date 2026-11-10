//
//  GoogleSetupBridge.kt
//  DirectSwitch-Android
//
//  Created by Nicolas Donati.
//  Copyright © 2026 Nicolas Donati. Tutti i diritti riservati.
//

package com.directswitch.android.migrators

import android.app.SearchManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.hardware.usb.UsbManager
import android.provider.Settings
import com.directswitch.android.DirectSwitchLog

/**
 * Motore di sblocco e richiamo per "Configura dispositivo" / "Android Switch" nativo di Google
 * (`com.google.android.gms.smartdevice.d2d` e `com.google.android.apps.restore`).
 */
object GoogleSetupBridge {

    data class BridgeAvailability(
        val hasGooglePlayServicesD2d: Boolean,
        val hasAndroidSwitchRestoreTool: Boolean,
        val hasSamsungSmartSwitch: Boolean,
        val isUsbCableDeviceAttached: Boolean,
        val attachedUsbProductName: String?
    )

    fun inspectDeviceCapabilities(context: Context): BridgeAvailability {
        val pm = context.packageManager
        val hasGms = isPackageInstalled(pm, "com.google.android.gms")
        val hasRestore = isPackageInstalled(pm, "com.google.android.apps.restore")
        val hasSamsung = isPackageInstalled(pm, "com.sec.android.easyMover")

        val usbManager = context.getSystemService(Context.USB_SERVICE) as? UsbManager
        val usbDevices = runCatching { usbManager?.deviceList?.values?.toList().orEmpty() }.getOrDefault(emptyList())
        val firstUsb = usbDevices.firstOrNull()

        return BridgeAvailability(
            hasGooglePlayServicesD2d = hasGms,
            hasAndroidSwitchRestoreTool = hasRestore,
            hasSamsungSmartSwitch = hasSamsung,
            isUsbCableDeviceAttached = usbDevices.isNotEmpty(),
            attachedUsbProductName = firstUsb?.productName ?: firstUsb?.manufacturerName
        )
    }

    /**
     * SCENARIO 1 (VECCHIO ANDROID -> NUOVO ANDROID):
     * Apre sul VECCHIO telefono il trasmettitore nativo di Google Play Services ("Configura dispositivo").
     */
    fun launchOldPhoneGoogleNearbySetup(context: Context): Pair<Boolean, String> {
        val directCandidates = listOf(
            Intent().apply {
                component = ComponentName(
                    "com.google.android.gms",
                    "com.google.android.gms.smartdevice.d2d.ui.SourceDirectTransferActivity"
                )
            },
            Intent().apply {
                component = ComponentName(
                    "com.google.android.gms",
                    "com.google.android.gms.smartdevice.d2d.QuickStartSourceActivity"
                )
            },
            Intent("com.google.android.gms.smartdevice.d2d.SOURCE_DIRECT_TRANSFER").apply {
                setPackage("com.google.android.gms")
            },
            Intent("com.google.android.gms.accountsettings.VIEW_SETTINGS_0P").apply {
                setPackage("com.google.android.gms")
                putExtra("extra.screenId", 412)
            }
        )

        for (intent in directCandidates) {
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            try {
                context.startActivity(intent)
                return true to "Trasmettitore 'Configura dispositivo' di Google avviato."
            } catch (t: Throwable) {
                DirectSwitchLog.warn("Avvio Configura (trasmettitore) fallito", t)
            }
        }

        val settingsFallbacks = listOf(
            Intent("com.android.settings.action.SETTINGS_SEARCH").apply {
                putExtra(SearchManager.QUERY, "Configura dispositivo")
            },
            Intent(Settings.ACTION_SETTINGS)
        )
        for (fallback in settingsFallbacks) {
            fallback.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            try {
                context.startActivity(fallback)
                return false to "Apertura diretta bloccata dal produttore: nelle Impostazioni aperte tocca 'Google → Configura e ripristina'."
            } catch (t: Throwable) {
                DirectSwitchLog.warn("Fallback impostazioni Configura fallito", t)
            }
        }

        return false to "Modulo Google Play Services D2D non trovato su questo dispositivo: usa 'Invia con DirectSwitch' qui sotto."
    }

    /**
     * SCENARIO 2 (NUOVO ANDROID GIÀ CONFIGURATO):
     * Riapre sul NUOVO telefono Android già avviato il ricevitore nativo "Android Switch / Copia dati".
     */
    fun launchNewPhonePostSetupRestore(context: Context): Pair<Boolean, String> {
        val pm = context.packageManager
        val candidates = mutableListOf<Intent>()

        pm.getLaunchIntentForPackage("com.google.android.apps.restore")?.let { candidates.add(it) }
        candidates.add(
            Intent().apply {
                component = ComponentName(
                    "com.google.android.apps.restore",
                    "com.google.android.apps.restore.anya.AnytimeRestoreActivity"
                )
            }
        )
        candidates.add(
            Intent().apply {
                component = ComponentName(
                    "com.google.android.gms",
                    "com.google.android.gms.smartdevice.d2d.ui.TargetDirectTransferActivity"
                )
            }
        )
        candidates.add(
            Intent("com.google.android.apps.restore.ACTION_START_RESTORE").apply {
                setPackage("com.google.android.apps.restore")
            }
        )
        candidates.add(
            Intent("com.google.android.setupwizard.DEFERRED_SUW").apply {
                setPackage("com.google.android.setupwizard")
            }
        )
        pm.getLaunchIntentForPackage("com.sec.android.easyMover")?.let { candidates.add(it) }

        for (intent in candidates) {
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            try {
                context.startActivity(intent)
                return true to "Ricevitore nativo 'Configura / Android Switch' avviato sul telefono già configurato."
            } catch (t: Throwable) {
                DirectSwitchLog.warn("Avvio Configura (ricevitore) fallito", t)
            }
        }

        try {
            val searchIntent = Intent("com.android.settings.action.SETTINGS_SEARCH").apply {
                putExtra(SearchManager.QUERY, "Copia dati")
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            context.startActivity(searchIntent)
            return false to "Wizard diretto bloccato dalla ROM: seleziona 'Copia dati / Android Switch' nella ricerca aperta, oppure usa 'Ricevi con DirectSwitch'."
        } catch (_: Throwable) {
        }

        return false to "Il produttore blocca il wizard Google post-setup: usa il trasferimento diretto DirectSwitch qui sotto."
    }

    /**
     * SCENARIO 3 (DA IPHONE -> A QUESTO ANDROID TRAMITE CONFIGURA NATIVO GOOGLE):
     * Apre il flusso nativo di Google "Android Switch" per importare da iPhone ad Android.
     */
    fun launchIphoneToAndroidGoogleRestore(context: Context): Pair<Boolean, String> {
        val pm = context.packageManager
        val capabilities = inspectDeviceCapabilities(context)
        val candidates = mutableListOf<Intent>()

        candidates.add(
            Intent().apply {
                component = ComponentName(
                    "com.google.android.apps.restore",
                    "com.google.android.apps.restore.anya.AnytimeRestoreActivity"
                )
                putExtra("source_device_type", "ios")
                putExtra("is_ios_migration", true)
            }
        )
        pm.getLaunchIntentForPackage("com.google.android.apps.restore")?.let { launchIntent ->
            launchIntent.putExtra("source_device_type", "ios")
            candidates.add(launchIntent)
        }
        candidates.add(
            Intent("com.google.android.apps.restore.ACTION_START_RESTORE").apply {
                setPackage("com.google.android.apps.restore")
                putExtra("source_device_type", "ios")
            }
        )
        candidates.add(
            Intent("com.google.android.setupwizard.DEFERRED_SUW").apply {
                setPackage("com.google.android.setupwizard")
                putExtra("source_device_type", "ios")
            }
        )
        pm.getLaunchIntentForPackage("com.sec.android.easyMover")?.let { candidates.add(it) }

        val cableHint = if (capabilities.isUsbCableDeviceAttached) {
            "Cavo USB rilevato (${capabilities.attachedUsbProductName ?: "iPhone"}): premi 'Autorizza' sull'iPhone."
        } else {
            "Puoi collegare l'iPhone via cavo USB-C/Lightning oppure scegliere la modalità wireless con QR."
        }

        for (intent in candidates) {
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            try {
                context.startActivity(intent)
                return true to "Flusso Google 'iPhone → Android' avviato! $cableHint"
            } catch (t: Throwable) {
                DirectSwitchLog.warn("Avvio flusso iPhone-Android fallito", t)
            }
        }
        return false to "Android Switch nativo non accessibile su questa ROM: usa 'Ricevi con DirectSwitch' qui sotto."
    }

    private fun isPackageInstalled(pm: PackageManager, pkg: String): Boolean {
        return try {
            pm.getPackageInfo(pkg, 0)
            true
        } catch (_: PackageManager.NameNotFoundException) {
            false
        }
    }
}
