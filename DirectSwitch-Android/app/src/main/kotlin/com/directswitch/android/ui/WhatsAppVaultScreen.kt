//
//  WhatsAppVaultScreen.kt
//  DirectSwitch-Android
//
//  Created by Nicolas Donati.
//  Copyright © 2026 Nicolas Donati. Tutti i diritti riservati.
//

package com.directswitch.android.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Chat
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.QrCode2
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.directswitch.android.migrators.GoogleSetupBridge
import com.directswitch.android.protocol.DevicePlatform
import com.directswitch.android.protocol.DirectSwitchL10n
import com.directswitch.android.ui.theme.AppleSettingsIcon
import com.directswitch.android.ui.theme.DirectSwitchCard
import com.directswitch.android.ui.theme.DirectSwitchPrimaryButton
import com.directswitch.android.ui.theme.DirectSwitchTheme
import com.directswitch.android.ui.theme.InfoCircleButton

/**
 * Scheda gratuita dedicata al trasferimento nativo della cronologia chat WhatsApp dentro
 * il flusso guidato di trasferimento dati (nessuna card in Home, nessun dispositivo complementare).
 */
@Composable
fun WhatsAppNativeTransferCard(
    isReceiver: Boolean,
    peerPlatform: DevicePlatform?
) {
    val context = LocalContext.current
    var statusMessage by remember { mutableStateOf<String?>(null) }
    var statusOk by remember { mutableStateOf(true) }

    val isIphoneToThisAndroid = isReceiver && peerPlatform == DevicePlatform.IOS
    val isThisAndroidToIphone = !isReceiver && peerPlatform == DevicePlatform.IOS

    val headerTitle = when {
        isIphoneToThisAndroid -> DirectSwitchL10n.tr("Trasferisci cronologia WhatsApp da iPhone", en = "Transfer WhatsApp chat history from iPhone", fr = "Transférer l'historique WhatsApp depuis iPhone")
        isThisAndroidToIphone -> DirectSwitchL10n.tr("Trasferisci cronologia WhatsApp su iPhone", en = "Transfer WhatsApp chat history to iPhone", fr = "Transférer l'historique WhatsApp vers iPhone")
        else -> DirectSwitchL10n.tr("Trasferisci cronologia WhatsApp via QR", en = "Transfer WhatsApp chat history via QR", fr = "Transférer l'historique WhatsApp par QR")
    }

    val headerSubtitle = when {
        isIphoneToThisAndroid -> DirectSwitchL10n.tr(
            "Gratuito dentro WhatsApp: una sola scansione QR, senza Android Switch",
            en = "Free inside WhatsApp: single QR scan, no Android Switch required",
            fr = "Gratuit dans WhatsApp : un seul scan QR, sans Android Switch"
        )
        isThisAndroidToIphone -> DirectSwitchL10n.tr(
            "Gratuito dentro WhatsApp: trasferimento diretto via QR senza Passa a iOS e senza formattare",
            en = "Free inside WhatsApp: direct QR transfer without Move to iOS or factory reset",
            fr = "Gratuit dans WhatsApp : transfert QR direct sans réinitialisation"
        )
        else -> DirectSwitchL10n.tr(
            "Passaggio gratuito della cronologia WhatsApp via Codice QR sullo stesso numero.",
            en = "Free WhatsApp chat transfer via QR Code on the same phone number.",
            fr = "Transfert gratuit de l'historique WhatsApp par Code QR sur le même numéro."
        )
    }

    val steps: List<Pair<String, String>> = when {
        isIphoneToThisAndroid -> listOf(
            "1" to DirectSwitchL10n.tr(
                "Su questo Android tocca «Apri WhatsApp (Numero + QR)», verifica lo stesso numero e arriva al Codice QR. Prima di inquadrare: se vedi i 3 pallini (⋮) in alto a destra, tocca subito ⋮ → «Mostra QR per iPhone» così eviti pop-up e riavvii del QR.",
                en = "On this Android tap 'Open WhatsApp (Number + QR)', verify the same number until the QR Code appears. If you see the ⋮ menu at top right, tap ⋮ → 'Show QR for iPhone'.",
                fr = "Sur cet Android touchez « Ouvrir WhatsApp », vérifiez le même numéro jusqu'au Code QR (si ⋮ apparaît en haut à droite, choisissez « Afficher QR pour iPhone »)."
            ),
            "2" to DirectSwitchL10n.tr(
                "Sul vecchio iPhone apri direttamente WhatsApp (senza usare lo scanner di DirectSwitch) → Impostazioni → Chat → Trasferisci chat su Android → Inizia e inquadra il QR una sola volta.",
                en = "On your old iPhone open WhatsApp → Settings → Chats → Move Chats to Android → Start and scan the QR once.",
                fr = "Sur l'ancien iPhone ouvrez WhatsApp → Réglages → Discussions → Transférer vers Android → Démarrer et scannez le QR."
            )
        )
        isThisAndroidToIphone -> listOf(
            "1" to DirectSwitchL10n.tr(
                "Sul nuovo iPhone apri WhatsApp e verifica lo stesso numero fino al Codice QR (anche su iPhone già configurato, senza usare Passa a iOS e senza formattare).",
                en = "On your new iPhone open WhatsApp and verify the same number until the QR Code appears (no reset needed).",
                fr = "Sur le nouvel iPhone ouvrez WhatsApp et vérifiez le même numéro jusqu'au Code QR (sans réinitialiser)."
            ),
            "2" to DirectSwitchL10n.tr(
                "Su questo Android tocca «Apri WhatsApp» qui sotto → Impostazioni → Chat → Trasferisci chat → Inizia e inquadra il Codice QR sul nuovo iPhone.",
                en = "On this Android tap 'Open WhatsApp' below → Settings → Chats → Transfer chats → Start and scan the QR on the new iPhone.",
                fr = "Sur cet Android touchez « Ouvrir WhatsApp » ci-dessous → Paramètres → Discussions → Transférer → Démarrer et scannez le QR."
            )
        )
        else -> listOf(
            "1" to DirectSwitchL10n.tr(
                "Sul vecchio Android apri WhatsApp → Impostazioni → Chat → Trasferisci chat → Inizia.",
                en = "On the old Android open WhatsApp → Settings → Chats → Transfer chats → Start.",
                fr = "Sur l'ancien Android ouvrez WhatsApp → Paramètres → Discussions → Transférer → Démarrer."
            ),
            "2" to DirectSwitchL10n.tr(
                "Su questo telefono verifica lo stesso numero in WhatsApp fino al Codice QR e inquadralo una sola volta.",
                en = "On this phone verify the same number in WhatsApp until the QR Code appears and scan it once.",
                fr = "Sur ce téléphone vérifiez le même numéro dans WhatsApp jusqu'au Code QR et scannez-le."
            )
        )
    }

    val primaryButtonTitle = when {
        isIphoneToThisAndroid -> DirectSwitchL10n.tr("Apri WhatsApp (Numero + QR)", en = "Open WhatsApp (Number + QR)", fr = "Ouvrir WhatsApp (Numéro + QR)")
        isThisAndroidToIphone -> DirectSwitchL10n.tr("Apri WhatsApp (Trasferisci chat)", en = "Open WhatsApp (Transfer chats)", fr = "Ouvrir WhatsApp (Transférer)")
        else -> DirectSwitchL10n.tr("Apri WhatsApp su questo Android", en = "Open WhatsApp on this Android", fr = "Ouvrir WhatsApp sur cet Android")
    }

    DirectSwitchCard(
        modifier = Modifier
            .fillMaxWidth()
            .border(1.dp, DirectSwitchTheme.green.copy(alpha = 0.42f), RoundedCornerShape(18.dp))
    ) {
        Column(
            modifier = Modifier.padding(18.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                AppleSettingsIcon(
                    icon = Icons.AutoMirrored.Filled.Chat,
                    color = DirectSwitchTheme.green
                )
                Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    Text(
                        text = headerTitle,
                        fontSize = 17.sp,
                        fontWeight = FontWeight.Bold,
                        color = DirectSwitchTheme.textPrimary
                    )
                    Text(
                        text = headerSubtitle,
                        fontSize = 13.sp,
                        color = DirectSwitchTheme.textSecondary
                    )
                }
            }

            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(12.dp))
                    .background(DirectSwitchTheme.inputSurface)
                    .padding(12.dp),
                verticalArrangement = Arrangement.spacedBy(9.dp)
            ) {
                steps.forEach { (num, text) ->
                    WhatsAppNumberedStepRow(stepNumber = num, text = text)
                }
            }

            DirectSwitchPrimaryButton(
                text = primaryButtonTitle,
                icon = Icons.Filled.QrCode2,
                containerColor = DirectSwitchTheme.green,
                onClick = {
                    val (ok, msg) = GoogleSetupBridge.launchWhatsAppOrPlayStore(context)
                    statusOk = ok
                    statusMessage = msg
                }
            )

            if (isIphoneToThisAndroid || isReceiver) {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .clip(RoundedCornerShape(12.dp))
                        .background(DirectSwitchTheme.inputSurface)
                        .clickable {
                            val (ok, msg) = GoogleSetupBridge.openWhatsAppAppInfoSettings(context)
                            statusOk = ok
                            statusMessage = msg
                        }
                        .padding(horizontal = 12.dp, vertical = 10.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    Icon(
                        imageVector = Icons.Filled.Refresh,
                        contentDescription = null,
                        tint = DirectSwitchTheme.blue,
                        modifier = Modifier.size(18.dp)
                    )
                    Text(
                        text = "WhatsApp già aperto senza schermata QR? Reimposta solo WhatsApp",
                        fontSize = 12.sp,
                        fontWeight = FontWeight.SemiBold,
                        color = DirectSwitchTheme.blue,
                        modifier = Modifier.weight(1f)
                    )
                    InfoCircleButton(
                        title = "Perché potrei dover reimpostare solo WhatsApp?",
                        message = "WhatsApp su Android mostra il Codice QR per importare le chat solo durante la prima verifica del numero su una installazione pulita. Se avevi già attivato WhatsApp vuoto su questo Android, «Spazio di archiviazione → Cancella dati» azzera solo WhatsApp (senza toccare il telefono o altri file) e ti permette di verificare subito il numero mostrando il QR."
                    )
                }
            } else if (isThisAndroidToIphone) {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .clip(RoundedCornerShape(12.dp))
                        .background(DirectSwitchTheme.inputSurface)
                        .padding(horizontal = 12.dp, vertical = 10.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    Icon(
                        imageVector = Icons.Filled.Refresh,
                        contentDescription = null,
                        tint = DirectSwitchTheme.blue,
                        modifier = Modifier.size(18.dp)
                    )
                    Text(
                        text = "WhatsApp su iPhone già aperto senza QR? Elimina e riscarica solo WhatsApp su iPhone",
                        fontSize = 12.sp,
                        fontWeight = FontWeight.SemiBold,
                        color = DirectSwitchTheme.blue,
                        modifier = Modifier.weight(1f)
                    )
                    InfoCircleButton(
                        title = "Perché potrei dover reimpostare solo WhatsApp su iPhone?",
                        message = "WhatsApp su iPhone mostra il Codice QR per ricevere le chat durante la verifica iniziale del numero. Se sul nuovo iPhone avevi già aperto WhatsApp vuoto saltando il QR, disinstalla e reinstalla solo WhatsApp da App Store (senza resettare l'iPhone) per far riapparire il QR."
                    )
                }
            }

            if (!statusMessage.isNullOrBlank()) {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .clip(RoundedCornerShape(10.dp))
                        .background(
                            if (statusOk) DirectSwitchTheme.green.copy(alpha = 0.12f)
                            else DirectSwitchTheme.orange.copy(alpha = 0.14f)
                        )
                        .padding(10.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    Icon(
                        imageVector = Icons.Filled.CheckCircle,
                        contentDescription = null,
                        tint = if (statusOk) DirectSwitchTheme.green else DirectSwitchTheme.orange,
                        modifier = Modifier.size(16.dp)
                    )
                    Text(
                        text = statusMessage!!,
                        fontSize = 12.sp,
                        color = DirectSwitchTheme.textPrimary,
                        modifier = Modifier.weight(1f)
                    )
                }
            }
        }
    }
}

@Composable
private fun WhatsAppNumberedStepRow(
    stepNumber: String,
    text: String
) {
    Row(
        horizontalArrangement = Arrangement.spacedBy(10.dp),
        verticalAlignment = Alignment.Top
    ) {
        Box(
            modifier = Modifier
                .size(22.dp)
                .clip(CircleShape)
                .background(DirectSwitchTheme.green.copy(alpha = 0.16f)),
            contentAlignment = Alignment.Center
        ) {
            Text(
                text = stepNumber,
                fontSize = 12.sp,
                fontWeight = FontWeight.Bold,
                color = DirectSwitchTheme.green
            )
        }
        Text(
            text = text,
            fontSize = 13.sp,
            color = DirectSwitchTheme.textPrimary,
            modifier = Modifier.weight(1f)
        )
    }
}
