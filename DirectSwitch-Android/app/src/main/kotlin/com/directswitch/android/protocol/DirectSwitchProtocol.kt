//
//  DirectSwitchProtocol.kt
//  DirectSwitch-Android
//
//  Created by Nicolas Donati.
//  Copyright © 2026 Nicolas Donati. Tutti i diritti riservati.
//

package com.directswitch.android.protocol

import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.InputStream
import java.io.OutputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.security.MessageDigest
import java.security.SecureRandom
import java.util.Locale
import javax.crypto.Cipher
import javax.crypto.Mac
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.SecretKeySpec

@Serializable
enum class DevicePlatform {
    ANDROID,
    IOS
}

@Serializable
enum class SessionLicenseTier {
    /** Android <-> Android oppure iPhone <-> iPhone: 100% gratuito e illimitato */
    INTRA_OS_FREE,
    /** Android <-> iPhone senza Pass Pro attivo: Rubrica completa gratis + anteprima primi 25 media */
    CROSS_OS_PREVIEW,
    /** Android <-> iPhone con Pass Pro attivo su almeno UNO dei due telefoni (Single-Side Unlock) */
    CROSS_OS_PRO_UNLOCKED
}

@Serializable
enum class TransferCategory {
    CONTACTS,
    PHOTOS,
    VIDEOS,
    CALENDARS,
    DOCUMENTS,
    SMS_HISTORY,
    WHATSAPP_VAULT
}

/**
 * Payload completo codificato esclusivamente nel QR Code visivo (o scambiato via PIN autenticato).
 * Contiene il segreto `sessionKeyHex` a 256 bit e non deve MAI essere trasmesso in broadcast UDP in chiaro.
 */
@Serializable
data class QrPairingPayload(
    val proto: String = "DSWITCH_V1",
    val sessionId: String,
    val receiverName: String,
    val receiverPlatform: DevicePlatform,
    val ips: List<String>,
    val port: Int,
    val sessionKeyHex: String,
    val wifiSsid: String? = null,
    val wifiPass: String? = null,
    val receiverHasPro: Boolean = false
) {
    fun toCompactJson(): String = DirectSwitchJson.instance.encodeToString(this)

    fun toPublicBeacon(): DiscoveryBeaconPayload = DiscoveryBeaconPayload(
        sessionId = sessionId,
        receiverName = receiverName,
        receiverPlatform = receiverPlatform,
        ips = ips,
        port = port,
        receiverHasPro = receiverHasPro
    )

    companion object {
        fun fromJson(raw: String): QrPairingPayload {
            return DirectSwitchJson.instance.decodeFromString(raw.trim())
        }
    }
}

/**
 * Annuncio UDP pubblico per l'auto-discovery sulla rete locale: espone SOLO metadati non sensibili
 * (nessuna chiave crittografica `sessionKeyHex` e nessuna password Wi-Fi).
 */
@Serializable
data class DiscoveryBeaconPayload(
    val proto: String = "DSWITCH_BEACON_V1",
    val sessionId: String,
    val receiverName: String,
    val receiverPlatform: DevicePlatform,
    val ips: List<String>,
    val port: Int,
    val receiverHasPro: Boolean = false
) {
    fun toCompactJson(): String = DirectSwitchJson.instance.encodeToString(this)

    companion object {
        fun fromJson(raw: String): DiscoveryBeaconPayload {
            val trimmed = raw.trim()
            val decoded = DirectSwitchJson.instance.decodeFromString<DiscoveryBeaconPayload>(trimmed)
            require(decoded.proto == "DSWITCH_BEACON_V1" && decoded.sessionId.isNotBlank()) {
                "Beacon DirectSwitch non valido"
            }
            return decoded
        }
    }
}

/** Richiesta di accoppiamento tramite PIN a 6 cifre letto sullo schermo del ricevente (`/v1/pair-pin`). */
@Serializable
data class PinPairingRequest(
    val sessionId: String,
    val senderName: String
)

@Serializable
data class HandshakeRequest(
    val sessionId: String,
    val senderName: String,
    val senderPlatform: DevicePlatform,
    val senderHasPro: Boolean,
    val senderHasCloudSavePro: Boolean = false,
    val totalEstimatedBytes: Long = 0L
)

@Serializable
data class HandshakeResponse(
    val accepted: Boolean,
    val receiverName: String,
    val receiverPlatform: DevicePlatform,
    val freeStorageBytes: Long,
    val licenseTier: SessionLicenseTier,
    val hasEnoughSpace: Boolean,
    val statusMessage: String
)

@Serializable
data class ContactTransferRecord(
    val id: String,
    val displayName: String,
    val phones: List<String>,
    val emails: List<String> = emptyList(),
    val organization: String? = null,
    val note: String? = null
)

@Serializable
data class CalendarEventRecord(
    val id: String,
    val title: String,
    val description: String? = null,
    val location: String? = null,
    val startEpochMillis: Long,
    val endEpochMillis: Long,
    val allDay: Boolean = false,
    val rrule: String? = null
)

@Serializable
data class SmsTransferRecord(
    val id: String,
    val address: String,
    val body: String,
    val dateEpochMillis: Long,
    /** 1 = Inbox (ricevuto), 2 = Sent (inviato) */
    val messageType: Int = 1
)

@Serializable
data class ManifestItem(
    val id: String,
    val category: TransferCategory,
    val fileName: String,
    val relativeAlbumOrFolder: String = "",
    val sizeBytes: Long,
    val capturedEpochMillis: Long = 0L,
    val dedupKey: String,
    val mimeType: String = "application/octet-stream"
)

@Serializable
data class TransferManifest(
    val sessionId: String,
    val senderPlatform: DevicePlatform,
    val items: List<ManifestItem>,
    val contactsPayload: List<ContactTransferRecord> = emptyList(),
    val calendarsPayload: List<CalendarEventRecord> = emptyList(),
    val smsPayload: List<SmsTransferRecord> = emptyList()
)

@Serializable
data class ManifestResponse(
    val acceptedItemIds: List<String>,
    val skippedDuplicateCount: Int,
    val contactsMergedCount: Int,
    val contactsSkippedDuplicates: Int,
    val calendarsImportedCount: Int,
    val smsImportedCount: Int = 0,
    val gatedByCrossOsPreviewCount: Int = 0
)

@Serializable
data class TransferCompletionReport(
    val sessionId: String,
    val licenseTier: SessionLicenseTier,
    val transferredFilesCount: Int,
    val transferredBytes: Long,
    val mergedContactsCount: Int,
    val importedCalendarsCount: Int,
    val importedSmsCount: Int = 0,
    val skippedDuplicatesCount: Int,
    val elapsedMillis: Long
)

object DirectSwitchJson {
    val instance: Json = Json {
        ignoreUnknownKeys = true
        encodeDefaults = true
    }
}

/**
 * Valutatore della policy di licenza Intra-OS (sempre gratuito) e Cross-OS (Single-Side Unlock).
 */
object LicensePolicyEvaluator {
    const val CROSS_OS_PREVIEW_MEDIA_LIMIT = 25

    /**
     * In modalità `CROSS_OS_PREVIEW` passano gratuitamente l'intera Rubrica Contatti e i primi 25 media;
     * le categorie estese (Calendari, SMS, Documenti illimitati) richiedono `INTRA_OS_FREE` o `CROSS_OS_PRO_UNLOCKED`.
     */
    fun allowsFullCategories(tier: SessionLicenseTier): Boolean =
        tier != SessionLicenseTier.CROSS_OS_PREVIEW

    /** Alias mantenuto per compatibilità con i chiamanti e i test esistenti. */
    fun allowsCalendars(tier: SessionLicenseTier): Boolean = allowsFullCategories(tier)

    fun resolveTier(
        senderPlatform: DevicePlatform,
        receiverPlatform: DevicePlatform,
        senderHasPro: Boolean,
        receiverHasPro: Boolean,
        senderHasCloudSavePro: Boolean = false,
        receiverHasCloudSavePro: Boolean = false
    ): SessionLicenseTier {
        if (senderPlatform == receiverPlatform) {
            return SessionLicenseTier.INTRA_OS_FREE
        }
        val anySidePro = senderHasPro || receiverHasPro || senderHasCloudSavePro || receiverHasCloudSavePro
        return if (anySidePro) {
            SessionLicenseTier.CROSS_OS_PRO_UNLOCKED
        } else {
            SessionLicenseTier.CROSS_OS_PREVIEW
        }
    }

    fun filterItemsForTier(
        items: List<ManifestItem>,
        tier: SessionLicenseTier
    ): Pair<List<ManifestItem>, Int> {
        if (tier == SessionLicenseTier.INTRA_OS_FREE || tier == SessionLicenseTier.CROSS_OS_PRO_UNLOCKED) {
            return items to 0
        }
        val allowed = mutableListOf<ManifestItem>()
        var previewMediaUsed = 0
        var gatedCount = 0
        for (item in items) {
            if (item.category == TransferCategory.CONTACTS) {
                allowed.add(item)
            } else if (
                (item.category == TransferCategory.PHOTOS || item.category == TransferCategory.VIDEOS) &&
                previewMediaUsed < CROSS_OS_PREVIEW_MEDIA_LIMIT
            ) {
                allowed.add(item)
                previewMediaUsed++
            } else {
                gatedCount++
            }
        }
        return allowed to gatedCount
    }
}

object PhoneNormalizer {
    /**
     * Normalizza un numero telefonico per lo Smart Merge anti-duplicati.
     * Confronta le ultime 9-10 cifre significative così "+39 333 123 4567" e "3331234567" coincidono.
     */
    fun normalizeKey(rawPhone: String): String {
        val digitsOnly = buildString {
            for (ch in rawPhone) {
                if (ch.isDigit()) append(ch)
            }
        }
        if (digitsOnly.length >= 9) {
            return digitsOnly.takeLast(10)
        }
        return digitsOnly
    }
}

/**
 * Motore crittografico CSGCM1 100% compatibile byte-per-byte tra Android (javax.crypto) e iOS (Apple CryptoKit).
 * Supporta blocchi streaming da 4 MiB per trasferire video 4K da decine di GB senza mai saturare la RAM.
 */
object DirectSwitchCrypto {
    const val CHUNK_SIZE_BYTES = 4 * 1024 * 1024 // 4 MiB
    private const val PIN_STRETCH_ROUNDS = 60_000
    private const val GCM_NONCE_BYTES = 12
    private const val GCM_TAG_BITS = 128
    private const val GCM_TAG_BYTES = 16
    private val MAGIC_CSGCM1 = "CSGCM1".toByteArray(Charsets.US_ASCII)
    private val secureRandom = SecureRandom()

    fun generateSessionKeyHex(): String = toHexLower(randomBytes(32))

    /** Genera un PIN numerico casuale a 6 cifre per l'accoppiamento da Auto-Discovery senza QR. */
    fun generatePairingPin(): String =
        String.format(Locale.US, "%06d", secureRandom.nextInt(1_000_000))

    fun randomBytes(count: Int): ByteArray {
        val out = ByteArray(count)
        secureRandom.nextBytes(out)
        return out
    }

    fun sha256(data: ByteArray): ByteArray =
        MessageDigest.getInstance("SHA-256").digest(data)

    fun hmacSha256Hex(keyBytes: ByteArray, message: String): String {
        val mac = Mac.getInstance("HmacSHA256")
        mac.init(SecretKeySpec(keyBytes, "HmacSHA256"))
        return toHexLower(mac.doFinal(message.toByteArray(Charsets.UTF_8)))
    }

    /** Confronto in tempo costante per token di autenticazione HTTP. */
    fun constantTimeEquals(a: String, b: String): Boolean =
        MessageDigest.isEqual(a.toByteArray(Charsets.UTF_8), b.toByteArray(Charsets.UTF_8))

    /**
     * RFC 5869 HKDF-SHA256 generico (Extract + Expand multi-blocco), identico a
     * `HKDF<SHA256>.deriveKey` di Apple CryptoKit. Verificato con i vettori ufficiali RFC 5869.
     */
    fun hkdfSha256(ikm: ByteArray, salt: ByteArray, info: ByteArray, length: Int): ByteArray {
        require(length in 1..(255 * 32)) { "Lunghezza HKDF non valida" }
        val extractMac = Mac.getInstance("HmacSHA256")
        extractMac.init(SecretKeySpec(if (salt.isEmpty()) ByteArray(32) else salt, "HmacSHA256"))
        val prk = extractMac.doFinal(ikm)

        val out = ByteArrayOutputStream(length)
        var previous = ByteArray(0)
        var counter = 1
        while (out.size() < length) {
            val expandMac = Mac.getInstance("HmacSHA256")
            expandMac.init(SecretKeySpec(prk, "HmacSHA256"))
            expandMac.update(previous)
            expandMac.update(info)
            expandMac.update(counter.toByte())
            previous = expandMac.doFinal()
            out.write(previous)
            counter++
        }
        return out.toByteArray().copyOf(length)
    }

    /**
     * Deriva la chiave AES-256 operativa di sessione dalla chiave casuale a 256 bit contenuta nel QR Code.
     */
    fun deriveSessionAesKey(sessionKeyHex: String): ByteArray {
        val ikm = fromHex(sessionKeyHex)
        require(ikm.size == 32) { "La chiave di sessione deve essere di 256 bit" }
        return hkdfSha256(
            ikm = ikm,
            salt = "DirectSwitch-Salt-2026".toByteArray(Charsets.UTF_8),
            info = "DirectSwitch-CSGCM1-v1".toByteArray(Charsets.UTF_8),
            length = 32
        )
    }

    /**
     * Deriva una chiave AES-256 dal PIN visivo a 6 cifre e dal `sessionId` con key-stretching HMAC-SHA256
     * (60.000 iterazioni), identica byte-per-byte a `DirectSwitchCrypto.derivePinSymmetricKey` su iOS.
     */
    fun derivePinAesKey(sessionId: String, pin: String): ByteArray {
        val cleanPin = pin.filter { it.isDigit() }
        require(cleanPin.length == 6 && sessionId.isNotBlank()) { "PIN a 6 cifre non valido" }
        val saltBytes = "DirectSwitch-PIN-Salt-2026:$sessionId".toByteArray(Charsets.UTF_8)
        var acc = hkdfSha256(
            ikm = cleanPin.toByteArray(Charsets.UTF_8),
            salt = saltBytes,
            info = "DirectSwitch-PIN-v1".toByteArray(Charsets.UTF_8),
            length = 32
        )
        val mac = Mac.getInstance("HmacSHA256")
        mac.init(SecretKeySpec(saltBytes, "HmacSHA256"))
        repeat(PIN_STRETCH_ROUNDS) {
            acc = mac.doFinal(acc)
        }
        return acc
    }

    /**
     * Busta cifrata per i messaggi di controllo JSON (handshake, manifesto, report, PIN pairing).
     */
    fun sealJsonEnvelope(json: String, aesKey32: ByteArray): ByteArray =
        encryptBytesCsgcm1(json.toByteArray(Charsets.UTF_8), aesKey32)

    fun openJsonEnvelope(envelope: ByteArray, aesKey32: ByteArray): String =
        decryptBytesCsgcm1(envelope, aesKey32).toString(Charsets.UTF_8)

    fun encryptBlock(plain: ByteArray, aesKey32: ByteArray): ByteArray {
        val nonce = randomBytes(GCM_NONCE_BYTES)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, SecretKeySpec(aesKey32, "AES"), GCMParameterSpec(GCM_TAG_BITS, nonce))
        val encryptedWithTag = cipher.doFinal(plain)
        val out = ByteArray(nonce.size + encryptedWithTag.size)
        System.arraycopy(nonce, 0, out, 0, nonce.size)
        System.arraycopy(encryptedWithTag, 0, out, nonce.size, encryptedWithTag.size)
        return out
    }

    fun decryptBlock(packet: ByteArray, aesKey32: ByteArray): ByteArray {
        require(packet.size >= GCM_NONCE_BYTES + GCM_TAG_BYTES) { "Pacchetto GCM troppo corto" }
        val nonce = packet.copyOfRange(0, GCM_NONCE_BYTES)
        val cipherWithTag = packet.copyOfRange(GCM_NONCE_BYTES, packet.size)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE, SecretKeySpec(aesKey32, "AES"), GCMParameterSpec(GCM_TAG_BITS, nonce))
        return cipher.doFinal(cipherWithTag)
    }

    /**
     * Cifra uno stream di lunghezza arbitraria in formato multi-blocco CSGCM1 (4 MiB per blocco).
     * Anche un input vuoto (0 byte) emette sempre almeno 1 blocco GCM autenticato (nonce + tag),
     * impedendo la falsificazione di buste vuote senza la chiave.
     */
    fun encryptStreamCsgcm1(input: InputStream, output: OutputStream, aesKey32: ByteArray): Pair<Long, String> {
        output.write(MAGIC_CSGCM1)
        val digest = MessageDigest.getInstance("SHA-256")
        val buffer = ByteArray(CHUNK_SIZE_BYTES)
        var totalPlainBytes = 0L
        var wroteAtLeastOneBlock = false

        while (true) {
            val read = readChunkFully(input, buffer)
            if (read <= 0) break
            totalPlainBytes += read
            digest.update(buffer, 0, read)
            val slice = if (read == buffer.size) buffer else buffer.copyOf(read)
            val encryptedPacket = encryptBlock(slice, aesKey32)
            val lenHeader = ByteBuffer.allocate(4).order(ByteOrder.BIG_ENDIAN).putInt(encryptedPacket.size).array()
            output.write(lenHeader)
            output.write(encryptedPacket)
            wroteAtLeastOneBlock = true
        }

        if (!wroteAtLeastOneBlock) {
            val emptyAuthenticatedPacket = encryptBlock(ByteArray(0), aesKey32)
            val lenHeader = ByteBuffer.allocate(4).order(ByteOrder.BIG_ENDIAN).putInt(emptyAuthenticatedPacket.size).array()
            output.write(lenHeader)
            output.write(emptyAuthenticatedPacket)
        }

        output.flush()
        return totalPlainBytes to toHexLower(digest.digest())
    }

    /**
     * Decifra uno stream CSGCM1 verificando l'autenticità GCM di ogni singolo blocco (almeno 1 obbligatorio)
     * e restituendo l'hash SHA-256 esatto del contenuto in chiaro.
     */
    fun decryptStreamCsgcm1(input: InputStream, output: OutputStream, aesKey32: ByteArray): Pair<Long, String> {
        val magicBuf = ByteArray(MAGIC_CSGCM1.size)
        val magicRead = readExact(input, magicBuf)
        require(magicRead == MAGIC_CSGCM1.size && magicBuf.contentEquals(MAGIC_CSGCM1)) {
            "Header CSGCM1 non valido"
        }
        val digest = MessageDigest.getInstance("SHA-256")
        val lenBuf = ByteArray(4)
        var totalPlainBytes = 0L
        var blockCount = 0

        while (true) {
            val headerRead = readExactOrEof(input, lenBuf)
            if (headerRead == 0) break
            require(headerRead == 4) { "Header lunghezza blocco CSGCM1 troncato" }
            val packetLen = ByteBuffer.wrap(lenBuf).order(ByteOrder.BIG_ENDIAN).int
            require(packetLen in (GCM_NONCE_BYTES + GCM_TAG_BYTES)..(CHUNK_SIZE_BYTES + 1024)) {
                "Lunghezza blocco CSGCM1 fuori range: $packetLen"
            }
            val packet = ByteArray(packetLen)
            val bodyRead = readExact(input, packet)
            require(bodyRead == packetLen) { "Corpo blocco CSGCM1 troncato" }

            val plain = decryptBlock(packet, aesKey32)
            digest.update(plain)
            if (plain.isNotEmpty()) {
                output.write(plain)
                totalPlainBytes += plain.size
            }
            blockCount++
        }
        require(blockCount >= 1) { "Stream CSGCM1 privo di blocchi autenticati GCM" }
        output.flush()
        return totalPlainBytes to toHexLower(digest.digest())
    }

    fun encryptBytesCsgcm1(plain: ByteArray, aesKey32: ByteArray): ByteArray {
        val out = ByteArrayOutputStream()
        encryptStreamCsgcm1(ByteArrayInputStream(plain), out, aesKey32)
        return out.toByteArray()
    }

    fun decryptBytesCsgcm1(encrypted: ByteArray, aesKey32: ByteArray): ByteArray {
        val out = ByteArrayOutputStream()
        decryptStreamCsgcm1(ByteArrayInputStream(encrypted), out, aesKey32)
        return out.toByteArray()
    }

    fun toHexLower(bytes: ByteArray): String {
        val sb = StringBuilder(bytes.size * 2)
        for (b in bytes) {
            sb.append(String.format(Locale.US, "%02x", b.toInt() and 0xFF))
        }
        return sb.toString()
    }

    fun fromHex(hex: String): ByteArray {
        val clean = hex.trim()
        require(clean.length % 2 == 0) { "Stringa esadecimale di lunghezza dispari" }
        val out = ByteArray(clean.length / 2)
        for (i in out.indices) {
            val idx = i * 2
            val hi = Character.digit(clean[idx], 16)
            val lo = Character.digit(clean[idx + 1], 16)
            require(hi >= 0 && lo >= 0) { "Carattere esadecimale non valido" }
            out[i] = ((hi shl 4) or lo).toByte()
        }
        return out
    }

    private fun readChunkFully(input: InputStream, buffer: ByteArray): Int {
        var total = 0
        while (total < buffer.size) {
            val r = input.read(buffer, total, buffer.size - total)
            if (r < 0) break
            total += r
        }
        return total
    }

    private fun readExact(input: InputStream, buffer: ByteArray): Int {
        var total = 0
        while (total < buffer.size) {
            val r = input.read(buffer, total, buffer.size - total)
            if (r < 0) break
            total += r
        }
        return total
    }

    private fun readExactOrEof(input: InputStream, buffer: ByteArray): Int {
        val first = input.read(buffer, 0, 1)
        if (first < 0) return 0
        var total = 1
        while (total < buffer.size) {
            val r = input.read(buffer, total, buffer.size - total)
            if (r < 0) break
            total += r
        }
        return total
    }
}
