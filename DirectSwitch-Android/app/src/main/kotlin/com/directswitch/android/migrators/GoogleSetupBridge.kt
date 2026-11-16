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
import android.net.Uri
import android.provider.Settings
import com.directswitch.android.DirectSwitchLog

/**
 * Motore di sblocco e richiamo per "Configura dispositivo" / "Android Switch" nativo di Google
 * e per il collegamento diretto di WhatsApp su telefoni già configurati (senza errore post-setup).
 */
object GoogleSetupBridge {

    data class BridgeAvailability(
        val hasGooglePlayServicesD2d: Boolean,
        val hasAndroidSwitchRestoreTool: Boolean,
        val hasSamsungSmartSwitch: Boolean,
        val isUsbCableDeviceAttached: Boolean,
        val attachedUsbProductName: String?,
        val isAlreadyConfiguredPostSetup: Boolean
    )

    /**
     * Restituisce `true` se lo smartphone Android ha già completato la configurazione iniziale (`USER_SETUP_COMPLETE == 1`).
     * Quando è `true`, Google blocca il trasferimento di WhatsApp dentro `Android Switch` (`com.google.android.apps.restore`)
     * mostrando l'errore "Android Switch non può essere utilizzata dopo la configurazione su questo dispositivo":
     * in questo stato DirectSwitch guida l'utente al trasferimento diretto della cronologia chat
     * tramite Codice QR sullo stesso numero di telefono dentro WhatsApp (senza dispositivo complementare e senza formattare il telefono).
     */
    fun isDeviceAlreadySetup(context: Context): Boolean {
        return try {
            Settings.Secure.getInt(context.contentResolver, "user_setup_complete", 1) == 1
        } catch (_: Throwable) {
            true
        }
    }

    fun isWhatsAppInstalled(context: Context): Boolean {
        val pm = context.packageManager
        return isPackageInstalled(pm, "com.whatsapp") || isPackageInstalled(pm, "com.whatsapp.w4b")
    }

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
            attachedUsbProductName = firstUsb?.productName ?: firstUsb?.manufacturerName,
            isAlreadyConfiguredPostSetup = isDeviceAlreadySetup(context)
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

        return false to "Modulo Google Play Services D2D non trovato su questo dispositivo: usa 'Invia' nella schermata principale."
    }

    /**
     * SCENARIO 2 (NUOVO ANDROID GIÀ CONFIGURATO — SOLO CONTATTI/APP DI SISTEMA, NON WHATSAPP):
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
                return true to "Modulo Google 'Copia dati' avviato (Nota: per WhatsApp a telefono già configurato usa invece il pulsante diretto WhatsApp in DirectSwitch)."
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
            return false to "Wizard diretto bloccato dalla ROM: usa 'Ricevi' nella Home di DirectSwitch."
        } catch (_: Throwable) {
        }

        return false to "Il produttore blocca il wizard Google post-setup: usa 'Ricevi' nella Home di DirectSwitch."
    }

    /**
     * SCENARIO 3 (DA IPHONE -> A QUESTO ANDROID):
     * Se il telefono Android è GIÀ CONFIGURATO (`isDeviceAlreadySetup == true`), Google blocca WhatsApp dentro
     * `Android Switch` ("non può essere utilizzata dopo la configurazione su questo dispositivo").
     * Pertanto su telefoni già configurati NON lanciamo `Android Switch` per WhatsApp, ma apriamo direttamente
     * WhatsApp ufficiale per verificare il numero associato e mostrare il Codice QR di importazione (senza formattare Android).
     */
    fun launchIphoneToAndroidGoogleRestore(
        context: Context,
        preferWirelessQr: Boolean = false
    ): Pair<Boolean, String> {
        if (isDeviceAlreadySetup(context)) {
            val (openedWa, _) = launchWhatsAppOrPlayStore(context)
            return if (openedWa) {
                true to "WhatsApp aperto su questo Android: verifica lo stesso numero di telefono associato all'iPhone fino alla schermata del Codice QR di trasferimento, poi inquadralo dall'iPhone (Impostazioni → Chat → Trasferisci chat su Android)."
            } else {
                false to "Installa WhatsApp dal Play Store, aprilo e verifica lo stesso numero di telefono fino alla schermata del Codice QR per importare le chat dall'iPhone."
            }
        }

        val pm = context.packageManager
        val capabilities = inspectDeviceCapabilities(context)
        val candidates = mutableListOf<Intent>()

        fun Intent.applyIosExtras(): Intent = apply {
            putExtra("source_device_type", "ios")
            putExtra("is_ios_migration", true)
            if (preferWirelessQr) {
                putExtra("transport_type", "WIFI")
                putExtra("wireless_migration", true)
                putExtra("cableless", true)
            }
        }

        candidates.add(
            Intent().apply {
                component = ComponentName(
                    "com.google.android.apps.restore",
                    "com.google.android.apps.restore.anya.AnytimeRestoreActivity"
                )
            }.applyIosExtras()
        )
        pm.getLaunchIntentForPackage("com.google.android.apps.restore")?.let { launchIntent ->
            candidates.add(launchIntent.applyIosExtras())
        }
        candidates.add(
            Intent("com.google.android.apps.restore.ACTION_START_RESTORE").apply {
                setPackage("com.google.android.apps.restore")
            }.applyIosExtras()
        )
        pm.getLaunchIntentForPackage("com.sec.android.easyMover")?.let { candidates.add(it) }

        val hint = if (capabilities.isUsbCableDeviceAttached) {
            "Cavo USB rilevato (${capabilities.attachedUsbProductName ?: "iPhone"}): premi 'Autorizza' sull'iPhone."
        } else {
            "Segui le istruzioni a schermo fino al codice QR."
        }

        for (intent in candidates) {
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            try {
                context.startActivity(intent)
                return true to "Modulo Android Switch avviato! $hint"
            } catch (t: Throwable) {
                DirectSwitchLog.warn("Avvio flusso iPhone-Android fallito", t)
            }
        }

        return launchWhatsAppOrPlayStore(context)
    }

    /**
     * Apre direttamente WhatsApp (o WhatsApp Business) su Android — oppure il Google Play Store se non è ancora installato.
     */
    fun launchWhatsAppOrPlayStore(context: Context): Pair<Boolean, String> {
        val pm = context.packageManager
        for (pkg in listOf("com.whatsapp", "com.whatsapp.w4b")) {
            val launch = pm.getLaunchIntentForPackage(pkg)
            if (launch != null) {
                launch.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                try {
                    context.startActivity(launch)
                    return true to "WhatsApp avviato: verifica lo stesso numero di telefono dell'iPhone finché WhatsApp mostra il Codice QR «Trasferisci cronologia chat», quindi inquadralo dal vecchio iPhone."
                } catch (t: Throwable) {
                    DirectSwitchLog.warn("Avvio WhatsApp fallito", t)
                }
            }
        }
        val storeCandidates = listOf(
            Intent(Intent.ACTION_VIEW, Uri.parse("market://details?id=com.whatsapp")),
            Intent(Intent.ACTION_VIEW, Uri.parse("https://play.google.com/store/apps/details?id=com.whatsapp"))
        )
        for (storeIntent in storeCandidates) {
            storeIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            try {
                context.startActivity(storeIntent)
                return true to "Apertura Google Play Store per installare WhatsApp..."
            } catch (_: Throwable) {
            }
        }
        return false to "Impossibile aprire WhatsApp o Google Play Store su questo dispositivo."
    }

    /**
     * Apre la schermata di sistema di WhatsApp ("Informazioni app") nel caso in cui l'utente avesse già effettuato
     * un accesso vuoto su Android e voglia far ricomparire la schermata iniziale con i 3 puntini `⋮`
     * ("Spazio di archiviazione → Cancella dati", che svuota solo WhatsApp senza toccare il telefono).
     */
    fun openWhatsAppAppInfoSettings(context: Context): Pair<Boolean, String> {
        val pm = context.packageManager
        val targetPkg = listOf("com.whatsapp", "com.whatsapp.w4b")
            .firstOrNull { isPackageInstalled(pm, it) }
            ?: return launchWhatsAppOrPlayStore(context)

        return try {
            val intent = Intent(
                Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                Uri.fromParts("package", targetPkg, null)
            ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            context.startActivity(intent)
            true to "Tocca «Spazio di archiviazione → Cancella dati» per riportare solo WhatsApp alla prima verifica del numero (senza formattare il telefono) e mostrare il Codice QR di importazione."
        } catch (t: Throwable) {
            DirectSwitchLog.warn("Apertura impostazioni WhatsApp fallita", t)
            false to "Impossibile aprire le impostazioni di WhatsApp."
        }
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
