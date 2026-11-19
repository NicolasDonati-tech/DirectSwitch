//
//  DirectSwitchKeepAliveService.kt
//  DirectSwitch-Android
//
//  Created by Nicolas Donati.
//  Copyright © 2026 Nicolas Donati. Tutti i diritti riservati.
//

package com.directswitch.android.transport

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.net.wifi.WifiManager
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat
import androidx.core.content.ContextCompat
import com.directswitch.android.DirectSwitchLog
import com.directswitch.android.MainActivity
import com.directswitch.android.R

/**
 * Foreground Service `dataSync` con `WifiLock` a bassa latenza e `PARTIAL_WAKE_LOCK`:
 * impedisce ad Android 12–16 di sospendere la radio Wi-Fi 5GHz o chiudere i socket TCP
 * durante il trasferimento di decine di GB se lo schermo si spegne o arriva una telefonata.
 */
class DirectSwitchKeepAliveService : Service() {

    companion object {
        private const val CHANNEL_ID = "directswitch_transfer_keepalive"
        private const val NOTIFICATION_ID = 49443
        private const val EXTRA_STATUS = "extra_status"
        private const val EXTRA_PERCENT = "extra_percent"
        private const val EXTRA_SUBTEXT = "extra_subtext"
        private const val MAX_LOCK_MS = 3L * 60L * 60L * 1000L

        @Volatile
        private var lastProgressNotifMs: Long = 0L

        fun start(context: Context, statusText: String) {
            runCatching {
                val appCtx = context.applicationContext
                val intent = Intent(appCtx, DirectSwitchKeepAliveService::class.java).apply {
                    putExtra(EXTRA_STATUS, statusText)
                    putExtra(EXTRA_PERCENT, -1)
                }
                ContextCompat.startForegroundService(appCtx, intent)
            }.onFailure { t ->
                DirectSwitchLog.warn("Avvio KeepAliveService non disponibile", t)
            }
        }

        /** Aggiorna la barra di avanzamento live nella notifica di sistema / schermata di blocco (rate-limited ~700ms). */
        fun updateProgress(
            context: Context,
            percent: Int,
            statusText: String,
            etaSubText: String? = null,
            force: Boolean = false
        ) {
            val now = System.currentTimeMillis()
            if (!force && percent < 100 && now - lastProgressNotifMs < 700L) return
            lastProgressNotifMs = now
            runCatching {
                val appCtx = context.applicationContext
                val nm = appCtx.getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager ?: return
                val openAppIntent = PendingIntent.getActivity(
                    appCtx,
                    0,
                    Intent(appCtx, MainActivity::class.java).apply {
                        addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
                    },
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )
                val safePct = percent.coerceIn(0, 100)
                val title = if (safePct >= 100) {
                    "DirectSwitch • Completato (100%)"
                } else {
                    "DirectSwitch • $safePct% trasferito"
                }
                val builder = NotificationCompat.Builder(appCtx, CHANNEL_ID)
                    .setSmallIcon(R.mipmap.ic_launcher)
                    .setContentTitle(title)
                    .setContentText(statusText)
                    .setOngoing(safePct < 100)
                    .setOnlyAlertOnce(true)
                    .setPriority(NotificationCompat.PRIORITY_LOW)
                    .setProgress(100, safePct, false)
                    .setContentIntent(openAppIntent)
                if (!etaSubText.isNullOrBlank()) {
                    builder.setSubText(etaSubText)
                }
                nm.notify(NOTIFICATION_ID, builder.build())
            }
        }

        fun stop(context: Context) {
            runCatching {
                val appCtx = context.applicationContext
                appCtx.stopService(Intent(appCtx, DirectSwitchKeepAliveService::class.java))
            }.onFailure { t ->
                DirectSwitchLog.warn("Arresto KeepAliveService fallito", t)
            }
        }
    }

    private var wakeLock: PowerManager.WakeLock? = null
    private var wifiLock: WifiManager.WifiLock? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        ensureChannel()
        acquireLocks()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val status = intent?.getStringExtra(EXTRA_STATUS)
            ?: "Trasferimento diretto cifrato attivo sulla rete locale"
        val openAppIntent = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java).apply {
                addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle("DirectSwitch Attivo")
            .setContentText(status)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setContentIntent(openAppIntent)
            .build()

        runCatching {
            val fgType = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC
            } else {
                0
            }
            ServiceCompat.startForeground(this, NOTIFICATION_ID, notification, fgType)
        }.onFailure { t ->
            DirectSwitchLog.warn("startForeground fallito", t)
            stopSelf()
        }

        return START_NOT_STICKY
    }

    override fun onDestroy() {
        releaseLocks()
        super.onDestroy()
    }

    private fun ensureChannel() {
        val mgr = getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager ?: return
        val channel = NotificationChannel(
            CHANNEL_ID,
            "Trasferimento Dati DirectSwitch",
            NotificationManager.IMPORTANCE_LOW
        ).apply {
            description = "Mantiene attiva la connessione Wi-Fi ad alta velocità durante il passaggio dati"
            setShowBadge(false)
        }
        mgr.createNotificationChannel(channel)
    }

    private fun acquireLocks() {
        runCatching {
            val pm = applicationContext.getSystemService(Context.POWER_SERVICE) as? PowerManager
            if (pm != null && wakeLock == null) {
                wakeLock = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "DirectSwitch:TransferWakeLock").apply {
                    setReferenceCounted(false)
                    acquire(MAX_LOCK_MS)
                }
            }
        }.onFailure { DirectSwitchLog.warn("Acquisizione WakeLock fallita", it) }

        runCatching {
            val wm = applicationContext.getSystemService(Context.WIFI_SERVICE) as? WifiManager
            if (wm != null && wifiLock == null) {
                @Suppress("DEPRECATION")
                val mode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    WifiManager.WIFI_MODE_FULL_LOW_LATENCY
                } else {
                    WifiManager.WIFI_MODE_FULL_HIGH_PERF
                }
                wifiLock = wm.createWifiLock(mode, "DirectSwitch:TransferWifiLock").apply {
                    setReferenceCounted(false)
                    acquire()
                }
            }
        }.onFailure { DirectSwitchLog.warn("Acquisizione WifiLock fallita", it) }
    }

    private fun releaseLocks() {
        runCatching {
            if (wifiLock?.isHeld == true) wifiLock?.release()
        }
        wifiLock = null

        runCatching {
            if (wakeLock?.isHeld == true) wakeLock?.release()
        }
        wakeLock = null
    }
}
