//
//  DirectSwitchAutoDiscovery.kt
//  DirectSwitch-Android
//
//  Created by Nicolas Donati.
//  Copyright © 2026 Nicolas Donati. Tutti i diritti riservati.
//

package com.directswitch.android.transport

import android.content.Context
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import com.directswitch.android.DirectSwitchLog
import com.directswitch.android.protocol.DiscoveryBeaconPayload
import com.directswitch.android.protocol.QrPairingPayload
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.InetAddress
import java.net.InetSocketAddress
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Motore di Scoperta Automatica del Dispositivo Nuovo nelle Vicinanze.
 *
 * Sicurezza: il beacon UDP (porta 49444) trasmette ESCLUSIVAMENTE [DiscoveryBeaconPayload]
 * (nome modello, piattaforma, IP privati e porta TCP). La chiave `sessionKeyHex` a 256 bit e la
 * password dell'Hotspot NON viaggiano mai sul canale broadcast: chi si collega tramite Auto-Discovery
 * deve confermare il PIN a 6 cifre mostrato sullo schermo del ricevente (`/v1/pair-pin`) oppure inquadrare il QR.
 */
class DirectSwitchAutoDiscovery(private val context: Context) {

    companion object {
        const val DISCOVERY_UDP_PORT = 49444
        const val SERVICE_TYPE = "_directswitch._tcp."
    }

    private val executor = Executors.newCachedThreadPool()
    private val broadcasting = AtomicBoolean(false)
    private val listening = AtomicBoolean(false)

    private var udpListenerSocket: DatagramSocket? = null
    private var registrationListener: NsdManager.RegistrationListener? = null
    @Volatile
    private var activeAdvertisingSessionId: String = ""

    private val discoveredMap = ConcurrentHashMap<String, DiscoveryBeaconPayload>()
    private val lastSeenMillisMap = ConcurrentHashMap<String, Long>()
    private val _discoveredDevices = MutableStateFlow<List<DiscoveryBeaconPayload>>(emptyList())
    val discoveredDevices: StateFlow<List<DiscoveryBeaconPayload>> = _discoveredDevices

    /**
     * Avviato dal Telefono Ricevente (Nuovo): annuncia solo il [DiscoveryBeaconPayload] pubblico.
     */
    fun startAdvertisingReceiver(payload: QrPairingPayload) {
        stopAdvertising()
        broadcasting.set(true)
        activeAdvertisingSessionId = payload.sessionId
        val publicBeacon = payload.toPublicBeacon()

        // 1. Registrazione mDNS / Bonjour (_directswitch._tcp.)
        try {
            val nsdManager = context.getSystemService(Context.NSD_SERVICE) as? NsdManager
            if (nsdManager != null) {
                val serviceInfo = NsdServiceInfo().apply {
                    serviceName = "DirectSwitch_${publicBeacon.receiverName.take(18)}"
                    serviceType = SERVICE_TYPE
                    port = publicBeacon.port
                }
                val regListener = object : NsdManager.RegistrationListener {
                    override fun onServiceRegistered(info: NsdServiceInfo?) {}
                    override fun onRegistrationFailed(info: NsdServiceInfo?, errorCode: Int) {}
                    override fun onServiceUnregistered(info: NsdServiceInfo?) {}
                    override fun onUnregistrationFailed(info: NsdServiceInfo?, errorCode: Int) {}
                }
                registrationListener = regListener
                nsdManager.registerService(serviceInfo, NsdManager.PROTOCOL_DNS_SD, regListener)
            }
        } catch (t: Throwable) {
            DirectSwitchLog.warn("Registrazione NSD fallita", t)
        }

        // 2. Beacon UDP periodico privo di chiavi segrete
        executor.execute {
            val jsonBytes = publicBeacon.toCompactJson().toByteArray(Charsets.UTF_8)
            DatagramSocket().use { sock ->
                sock.broadcast = true
                while (broadcasting.get()) {
                    try {
                        val bcastAddr = InetAddress.getByName("255.255.255.255")
                        sock.send(DatagramPacket(jsonBytes, jsonBytes.size, bcastAddr, DISCOVERY_UDP_PORT))

                        for (ip in publicBeacon.ips) {
                            val parts = ip.split(".")
                            if (parts.size == 4 && LocalNetworkAddresses.isLocalNetworkIpv4(ip)) {
                                val subnetBcast = InetAddress.getByName("${parts[0]}.${parts[1]}.${parts[2]}.255")
                                sock.send(DatagramPacket(jsonBytes, jsonBytes.size, subnetBcast, DISCOVERY_UDP_PORT))
                            }
                        }
                    } catch (t: Throwable) {
                        DirectSwitchLog.warn("Invio broadcast discovery fallito", t)
                    }
                    try {
                        Thread.sleep(1500)
                    } catch (_: InterruptedException) {
                        break
                    }
                }
            }
        }
    }

    fun stopAdvertising() {
        broadcasting.set(false)
        activeAdvertisingSessionId = ""
        try {
            val nsdManager = context.getSystemService(Context.NSD_SERVICE) as? NsdManager
            registrationListener?.let { nsdManager?.unregisterService(it) }
        } catch (t: Throwable) {
            DirectSwitchLog.warn("Deregistrazione NSD fallita", t)
        } finally {
            registrationListener = null
        }
    }

    /**
     * Avviato dal Telefono Vecchio (Mittente): ascolta i beacon pubblici dei dispositivi riceventi
     * sulla rete locale e aggiorna [discoveredDevices].
     */
    fun startScanningForNewDevices() {
        if (listening.getAndSet(true)) return
        discoveredMap.clear()
        lastSeenMillisMap.clear()
        _discoveredDevices.value = emptyList()

        // Thread di pulizia dei beacon inattivi (> 8,5 secondi)
        executor.execute {
            while (listening.get()) {
                try {
                    Thread.sleep(2500)
                } catch (_: InterruptedException) {
                    break
                }
                if (!listening.get()) break
                val cutoff = System.currentTimeMillis() - 8_500L
                var changed = false
                for ((sid, seenAt) in lastSeenMillisMap.entries) {
                    if (seenAt < cutoff) {
                        lastSeenMillisMap.remove(sid)
                        if (discoveredMap.remove(sid) != null) {
                            changed = true
                        }
                    }
                }
                if (changed) {
                    _discoveredDevices.value = discoveredMap.values.toList()
                }
            }
        }

        executor.execute {
            try {
                val sock = DatagramSocket(null).apply {
                    reuseAddress = true
                    bind(InetSocketAddress(DISCOVERY_UDP_PORT))
                }
                udpListenerSocket = sock
                val buf = ByteArray(8192)
                while (listening.get()) {
                    val packet = DatagramPacket(buf, buf.size)
                    sock.receive(packet)
                    val senderIp = packet.address?.hostAddress
                    if (senderIp != null && !LocalNetworkAddresses.isLocalNetworkIpv4(senderIp)) {
                        continue
                    }
                    val raw = String(packet.data, 0, packet.length, Charsets.UTF_8)
                    runCatching { DiscoveryBeaconPayload.fromJson(raw) }.onSuccess { beacon ->
                        val localIps = beacon.ips.filter { LocalNetworkAddresses.isLocalNetworkIpv4(it) }
                        val enrichedIps = if (!senderIp.isNullOrBlank() && senderIp !in localIps) {
                            listOf(senderIp) + localIps
                        } else {
                            localIps
                        }
                        if (enrichedIps.isNotEmpty()) {
                            val myLocalIps = LocalNetworkAddresses.listPrivateIpv4Addresses().toSet()
                            val isSelfSession = activeAdvertisingSessionId.isNotEmpty() &&
                                beacon.sessionId == activeAdvertisingSessionId
                            val isSelfIp = myLocalIps.isNotEmpty() && enrichedIps.toSet().all { it in myLocalIps }
                            if (!isSelfSession && !isSelfIp) {
                                val updated = beacon.copy(ips = enrichedIps)
                                // Rimuove eventuali vecchi sessionId dello stesso telefono fisico (stesso IP)
                                val staleSameDeviceIds = discoveredMap.values
                                    .filter { it.sessionId != updated.sessionId && it.representsSameDevice(updated) }
                                    .map { it.sessionId }
                                for (oldId in staleSameDeviceIds) {
                                    discoveredMap.remove(oldId)
                                    lastSeenMillisMap.remove(oldId)
                                }
                                discoveredMap[updated.sessionId] = updated
                                lastSeenMillisMap[updated.sessionId] = System.currentTimeMillis()
                                _discoveredDevices.value = discoveredMap.values.toList()
                            }
                        }
                    }
                }
            } catch (t: Throwable) {
                if (listening.get()) {
                    DirectSwitchLog.warn("Ascolto discovery UDP interrotto", t)
                }
            }
        }
    }

    fun stopScanning() {
        listening.set(false)
        try {
            udpListenerSocket?.close()
        } catch (t: Throwable) {
            DirectSwitchLog.warn("Chiusura socket UDP fallita", t)
        } finally {
            udpListenerSocket = null
        }
    }
}
