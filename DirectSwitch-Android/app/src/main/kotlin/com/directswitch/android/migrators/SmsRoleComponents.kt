//
//  SmsRoleComponents.kt
//  DirectSwitch-Android
//
//  Created by Nicolas Donati.
//  Copyright © 2026 Nicolas Donati. Tutti i diritti riservati.
//

package com.directswitch.android.migrators

import android.app.Service
import android.content.BroadcastReceiver
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.os.IBinder
import android.provider.Telephony
import com.directswitch.android.DirectSwitchLog

/**
 * Componenti richiesti da Android (`RoleManager.ROLE_SMS`) affinché DirectSwitch possa
 * assumere temporaneamente il ruolo di app SMS predefinita durante il ripristino diretto
 * degli SMS nel database di sistema (`Telephony.Sms.CONTENT_URI`).
 *
 * Sicurezza anti-perdita: se un SMS reale sulla rete cellulare arriva proprio nei secondi in cui
 * DirectSwitch detiene `ROLE_SMS`, [DirectSwitchSmsDeliverReceiver] lo salva subito in `Telephony.Sms.Inbox`
 * così il messaggio compare regolarmente non appena l'utente ripristina l'app Messaggi predefinita.
 */
class DirectSwitchSmsDeliverReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context?, intent: Intent?) {
        if (context == null || intent == null) return
        if (intent.action != Telephony.Sms.Intents.SMS_DELIVER_ACTION) return
        if (!SmsSystemScanner.isDefaultSmsApp(context)) return

        try {
            val parts = Telephony.Sms.Intents.getMessagesFromIntent(intent)
            if (parts.isNullOrEmpty()) return
            val sender = parts.firstOrNull()?.displayOriginatingAddress.orEmpty()
            val timestamp = parts.firstOrNull()?.timestampMillis ?: System.currentTimeMillis()
            val fullBody = buildString {
                for (msg in parts) {
                    append(msg.displayMessageBody.orEmpty())
                }
            }
            if (sender.isEmpty() && fullBody.isEmpty()) return

            val values = ContentValues().apply {
                put(Telephony.Sms.ADDRESS, sender)
                put(Telephony.Sms.BODY, fullBody)
                put(Telephony.Sms.DATE, timestamp)
                put(Telephony.Sms.TYPE, Telephony.Sms.MESSAGE_TYPE_INBOX)
                put(Telephony.Sms.READ, 0)
                put(Telephony.Sms.SEEN, 0)
            }
            context.contentResolver.insert(Telephony.Sms.Inbox.CONTENT_URI, values)
        } catch (t: Throwable) {
            DirectSwitchLog.warn("Salvataggio SMS in arrivo durante ROLE_SMS fallito", t)
        }
    }
}

class DirectSwitchMmsWapPushReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context?, intent: Intent?) {
        // Ricevitore WAP Push richiesto dal contratto ROLE_SMS di Android
    }
}

class DirectSwitchHeadlessSmsSendService : Service() {
    override fun onBind(intent: Intent?): IBinder? = null
}
