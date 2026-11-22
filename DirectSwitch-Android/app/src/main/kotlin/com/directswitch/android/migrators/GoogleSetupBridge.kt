//
//  GoogleSetupBridge.kt
//  DirectSwitch-Android
//
//  Created by Nicolas Donati.
//  Copyright © 2026 Nicolas Donati. Tutti i diritti riservati.
//

package com.directswitch.android.migrators

import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.provider.Settings
import com.directswitch.android.DirectSwitchLog

/**
 * Helper diretto per il lancio guidato di WhatsApp nativo su dispositivi già configurati
 * (senza passare da Android Switch né formattare il telefono).
 */
object GoogleSetupBridge {

    fun isWhatsAppInstalled(context: Context): Boolean {
        val pm = context.packageManager
        return isPackageInstalled(pm, "com.whatsapp") || isPackageInstalled(pm, "com.whatsapp.w4b")
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
                    return true to "WhatsApp avviato: segui il passaggio guidato via Codice QR «Trasferisci cronologia chat»."
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
     * un accesso vuoto su Android e voglia far ricomparire la schermata iniziale di importazione via QR
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
