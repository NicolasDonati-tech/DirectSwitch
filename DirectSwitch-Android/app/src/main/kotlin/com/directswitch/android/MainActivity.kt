//
//  MainActivity.kt
//  DirectSwitch-Android
//
//  Created by Nicolas Donati.
//  Copyright © 2026 Nicolas Donati. Tutti i diritti riservati.
//

package com.directswitch.android

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.view.WindowManager
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.lifecycleScope
import com.directswitch.android.migrators.DocumentsAndWhatsAppScanner
import com.directswitch.android.ui.DirectSwitchMainScreen
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

class MainActivity : ComponentActivity() {

    private var sharedImportBanner by mutableStateOf<String?>(null)
    private var sharedImportVersion by mutableIntStateOf(0)

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Mantiene lo schermo sveglio durante i trasferimenti ad alta velocità per evitare drop del Wi-Fi
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        enableEdgeToEdge()
        handleIncomingShareIntent(intent)
        setContent {
            DirectSwitchMainScreen(
                externalVaultNote = sharedImportBanner,
                externalVaultTrigger = sharedImportVersion
            )
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleIncomingShareIntent(intent)
    }

    private fun handleIncomingShareIntent(incoming: Intent?) {
        if (incoming == null) return
        val action = incoming.action ?: return
        if (action != Intent.ACTION_SEND && action != Intent.ACTION_SEND_MULTIPLE) return

        val uris = mutableListOf<Uri>()
        if (action == Intent.ACTION_SEND) {
            val single = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                incoming.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
            } else {
                @Suppress("DEPRECATION")
                incoming.getParcelableExtra(Intent.EXTRA_STREAM)
            }
            if (single != null) uris.add(single)
        } else {
            val multi = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                incoming.getParcelableArrayListExtra(Intent.EXTRA_STREAM, Uri::class.java)
            } else {
                @Suppress("DEPRECATION")
                incoming.getParcelableArrayListExtra(Intent.EXTRA_STREAM)
            }
            if (!multi.isNullOrEmpty()) uris.addAll(multi)
        }

        val clip = incoming.clipData
        if (uris.isEmpty() && clip != null) {
            for (i in 0 until clip.itemCount) {
                clip.getItemAt(i)?.uri?.let { uris.add(it) }
            }
        }
        if (uris.isEmpty()) return

        lifecycleScope.launch {
            val added = withContext(Dispatchers.IO) {
                DocumentsAndWhatsAppScanner.importSharedUrisIntoVault(applicationContext, uris.distinct())
            }
            if (added > 0) {
                sharedImportBanner = "$added file/chat WhatsApp aggiunti al Vault DirectSwitch e pronti al trasferimento!"
                sharedImportVersion++
            }
        }
    }
}
