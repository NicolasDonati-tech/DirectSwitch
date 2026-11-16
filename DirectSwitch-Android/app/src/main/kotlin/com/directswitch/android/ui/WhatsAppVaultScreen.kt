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
        isIphoneToThisAndroid -> "Trasferisci cronologia WhatsApp da iPhone"
        isThisAndroidToIphone -> "Trasferisci cronologia WhatsApp su iPhone"
        else -> "Trasferisci cronologia WhatsApp via QR"
    }

    val headerSubtitle = when {
        isIphoneToThisAndroid ->
            "Gratuito dentro WhatsApp: una sola scansione QR, senza Android Switch."
        isThisAndroidToIphone ->
            "Passaggio diretto della cronologia chat WhatsApp sul nuovo iPhone."
        else ->
            "Passaggio gratuito della cronologia WhatsApp via Codice QR sullo stesso numero."
    }

    val steps: List<Pair<String, String>> = when {
        isIphoneToThisAndroid -> listOf(
            "1" to "Su questo Android tocca «Apri WhatsApp (Numero + QR)», verifica lo stesso numero e arriva al Codice QR. Prima di inquadrare: se vedi i 3 pallini (⋮) in alto a destra, tocca subito ⋮ → «Mostra QR per iPhone» così eviti pop-up e riavvii del QR.",
            "2" to "Sul vecchio iPhone apri direttamente WhatsApp (senza usare lo scanner di DirectSwitch) → Impostazioni → Chat → Trasferisci chat su Android → Inizia e inquadra il QR una sola volta."
        )
        isThisAndroidToIphone -> listOf(
            "1" to "Su questo Android apri WhatsApp → Impostazioni → Chat → Trasferisci chat.",
            "2" to "Sul nuovo iPhone conferma con «Passa a iOS» / WhatsApp usando lo stesso numero di telefono."
        )
        else -> listOf(
            "1" to "Sul vecchio Android apri WhatsApp → Impostazioni → Chat → Trasferisci chat → Inizia.",
            "2" to "Su questo telefono verifica lo stesso numero in WhatsApp fino al Codice QR e inquadralo una sola volta."
        )
    }

    val primaryButtonTitle = when {
        isIphoneToThisAndroid -> "Apri WhatsApp (Numero + QR)"
        isThisAndroidToIphone -> "Apri WhatsApp (Impostazioni Chat)"
        else -> "Apri WhatsApp su questo Android"
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
                        message = "WhatsApp su Android mostra il Codice QR per importare le chat dall'iPhone solo durante la prima verifica del numero su una installazione pulita. Se avevi già attivato WhatsApp vuoto su questo Android, «Spazio di archiviazione → Cancella dati» azzera solo WhatsApp (senza toccare il telefono o altri file) e ti permette di verificare subito il numero mostrando il QR."
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
