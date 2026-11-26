package com.directswitch.android.protocol

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.ImageDecoder
import android.os.BatteryManager
import android.os.Build
import android.os.PowerManager
import android.provider.MediaStore
import androidx.core.content.ContextCompat
import androidx.exifinterface.media.ExifInterface
import kotlinx.serialization.Serializable
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.io.InputStream
import java.security.MessageDigest
import java.util.Locale

fun openMediaOriginalInputStream(context: Context, uri: android.net.Uri): InputStream? {
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q &&
        ContextCompat.checkSelfPermission(context, Manifest.permission.ACCESS_MEDIA_LOCATION) == PackageManager.PERMISSION_GRANTED
    ) {
        runCatching {
            val origUri = MediaStore.setRequireOriginal(uri)
            context.contentResolver.openInputStream(origUri)
        }.getOrNull()?.let { return it }
    }
    return context.contentResolver.openInputStream(uri)
}

// MARK: - 1. Guardia Termica Adattiva (Android)

enum class ThermalGuardState {
    NORMAL,
    WARM_THROTTLE,
    CRITICAL_COOLDOWN
}

data class ThermalReading(
    val tempCelsius: Double?,
    val thermalStatusLevel: Int
)

object ThermalGuardCore {
    /**
     * Valuta lo stato termico in base a `PowerManager.THERMAL_STATUS_*` (3 = SEVERE, 4+ = CRITICAL)
     * e alla temperatura batteria (`>= 44.0°C` -> raffreddamento, `>= 40.0°C` -> riduzione flussi).
     */
    fun evaluate(reading: ThermalReading): ThermalGuardState {
        val t = reading.tempCelsius
        val level = reading.thermalStatusLevel
        if (level >= 3 || (t != null && t >= 44.0)) {
            return ThermalGuardState.CRITICAL_COOLDOWN
        }
        if (level >= 2 || (t != null && t >= 40.0)) {
            return ThermalGuardState.WARM_THROTTLE
        }
        return ThermalGuardState.NORMAL
    }
}

object AndroidThermalMonitor {
    fun read(context: Context): ThermalReading {
        val status = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val pm = context.getSystemService(Context.POWER_SERVICE) as? PowerManager
            pm?.currentThermalStatus ?: 0
        } else {
            0
        }
        val batteryIntent = runCatching {
            context.registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
        }.getOrNull()
        val tenths = batteryIntent?.getIntExtra(BatteryManager.EXTRA_TEMPERATURE, -1) ?: -1
        val celsius = if (tenths > 0) tenths / 10.0 else null
        return ThermalReading(tempCelsius = celsius, thermalStatusLevel = status)
    }
}

// MARK: - 2. Smart Clean Pre-Migrazione (Merge Contatti E.164 + Dedup SHA-256 + Filtro Screenshot)

@Serializable
data class SmartCleanOptions(
    val mergeDuplicateContacts: Boolean = true,
    val skipExactDuplicatePhotosSha256: Boolean = false,
    val skipOldScreenshotsOlderThanMonths: Int = 0
)

data class SmartCleanMediaResult<T>(
    val kept: List<T>,
    val skippedDuplicatesCount: Int,
    val skippedOldScreenshotsCount: Int,
    val savedBytes: Long
)

object SmartCleanPreTransferEngine {

    fun normalizePhoneE164(raw: String, defaultCountryPrefix: String = "+39"): String {
        val trimmed = raw.trim()
        if (trimmed.isEmpty()) return ""
        val digits = trimmed.filter { it.isDigit() }
        if (digits.length < 5) return digits
        if (trimmed.startsWith("+")) return "+$digits"
        if (trimmed.startsWith("00") && digits.length > 4) return "+${digits.drop(2)}"
        if (defaultCountryPrefix == "+39" && digits.length in 9..10 && (digits.startsWith("3") || digits.startsWith("0"))) {
            return "+39$digits"
        }
        return "+$digits"
    }

    /**
     * Unisce contatti duplicati sul dispositivo sorgente prima dell'invio (senza toccare la rubrica originale):
     * due contatti vengono fusi se condividono almeno un numero normalizzato E.164 (o nome + email identici).
     */
    fun mergeDuplicateContacts(contacts: List<ContactTransferRecord>): Pair<List<ContactTransferRecord>, Int> {
        if (contacts.size <= 1) return contacts to 0

        val n = contacts.size
        val parent = IntArray(n) { it }
        fun find(x: Int): Int {
            var cur = x
            while (parent[cur] != cur) {
                parent[cur] = parent[parent[cur]]
                cur = parent[cur]
            }
            return cur
        }
        fun union(a: Int, b: Int) {
            val ra = find(a)
            val rb = find(b)
            if (ra != rb) parent[rb] = ra
        }

        val phoneOwner = HashMap<String, Int>()
        val nameEmailOwner = HashMap<String, Int>()
        for (i in contacts.indices) {
            val c = contacts[i]
            val normPhones = (c.phones + c.labeledPhones.orEmpty().map { it.value })
                .map { normalizePhoneE164(it) }
                .filter { it.length >= 7 }
            for (p in normPhones) {
                val prev = phoneOwner.putIfAbsent(p, i)
                if (prev != null) union(prev, i)
            }
            val normName = c.displayName.trim().lowercase(Locale.ROOT)
            val normEmails = (c.emails + c.labeledEmails.orEmpty().map { it.value })
                .map { it.trim().lowercase(Locale.ROOT) }
                .filter { it.isNotEmpty() }
            if (normName.isNotEmpty() && normEmails.isNotEmpty()) {
                for (em in normEmails) {
                    val key = "$normName|$em"
                    val prev = nameEmailOwner.putIfAbsent(key, i)
                    if (prev != null) union(prev, i)
                }
            }
        }

        val groups = LinkedHashMap<Int, MutableList<ContactTransferRecord>>()
        for (i in contacts.indices) {
            groups.getOrPut(find(i)) { mutableListOf() }.add(contacts[i])
        }

        var mergedDuplicates = 0
        val mergedList = groups.values.map { group ->
            if (group.size == 1) return@map group.first()
            mergedDuplicates += (group.size - 1)
            val first = group.first()
            val allPhones = LinkedHashMap<String, String>()
            val allEmails = LinkedHashSet<String>()
            val allLabeledPhones = LinkedHashMap<String, LabeledValueRecord>()
            val allLabeledEmails = LinkedHashMap<String, LabeledValueRecord>()
            val allUrls = LinkedHashSet<String>()
            val allAddresses = LinkedHashMap<String, PostalAddressTransferRecord>()
            val allNotes = LinkedHashSet<String>()

            for (c in group) {
                c.phones.forEach { p ->
                    val k = normalizePhoneE164(p).ifBlank { p.trim() }
                    if (k.isNotEmpty()) allPhones.putIfAbsent(k, p.trim())
                }
                c.labeledPhones.orEmpty().forEach { lp ->
                    val k = normalizePhoneE164(lp.value).ifBlank { lp.value.trim() }
                    if (k.isNotEmpty()) allLabeledPhones.putIfAbsent(k, lp)
                }
                c.emails.map { it.trim() }.filter { it.isNotEmpty() }.forEach { allEmails.add(it) }
                c.labeledEmails.orEmpty().forEach { le ->
                    val k = le.value.trim().lowercase(Locale.ROOT)
                    if (k.isNotEmpty()) allLabeledEmails.putIfAbsent(k, le)
                }
                c.urls.orEmpty().map { it.trim() }.filter { it.isNotEmpty() }.forEach { allUrls.add(it) }
                c.postalAddresses.orEmpty().forEach { pa ->
                    val k = "${pa.street}|${pa.city}|${pa.postalCode}".lowercase(Locale.ROOT)
                    allAddresses.putIfAbsent(k, pa)
                }
                c.note?.trim()?.takeIf { it.isNotEmpty() }?.let { allNotes.add(it) }
            }

            first.copy(
                displayName = group.maxByOrNull { it.displayName.length }?.displayName ?: first.displayName,
                phones = allPhones.values.toList(),
                emails = allEmails.toList(),
                organization = group.firstNotNullOfOrNull { it.organization?.takeIf(String::isNotBlank) },
                note = allNotes.joinToString("\n").ifBlank { null },
                givenName = group.firstNotNullOfOrNull { it.givenName?.takeIf(String::isNotBlank) },
                familyName = group.firstNotNullOfOrNull { it.familyName?.takeIf(String::isNotBlank) },
                nickname = group.firstNotNullOfOrNull { it.nickname?.takeIf(String::isNotBlank) },
                jobTitle = group.firstNotNullOfOrNull { it.jobTitle?.takeIf(String::isNotBlank) },
                birthdayYear = group.firstNotNullOfOrNull { it.birthdayYear },
                birthdayMonth = group.firstNotNullOfOrNull { it.birthdayMonth },
                birthdayDay = group.firstNotNullOfOrNull { it.birthdayDay },
                labeledPhones = allLabeledPhones.values.toList().ifEmpty { null },
                labeledEmails = allLabeledEmails.values.toList().ifEmpty { null },
                urls = allUrls.toList().ifEmpty { null },
                postalAddresses = allAddresses.values.toList().ifEmpty { null },
                avatarJpegBase64 = group.firstNotNullOfOrNull { it.avatarJpegBase64?.takeIf(String::isNotBlank) }
            )
        }
        return mergedList to mergedDuplicates
    }

    private val screenshotTokens = listOf(
        "screenshot",
        "screen_shot",
        "screen shot",
        "screencapture",
        "screen_capture",
        "screen capture",
        "schermata",
        "schermate",
        "capture d'écran",
        "capture d\u2019écran",
        "captures d'écran",
        "captures d\u2019écran",
        "capture d'ecran",
        "captures d'ecran",
        "capture_d_ecran"
    )

    fun looksLikeScreenshotNameOrAlbum(fileName: String, albumOrFolder: String): Boolean {
        val lowFile = fileName.lowercase(Locale.ROOT)
        val lowAlbum = albumOrFolder.lowercase(Locale.ROOT)
        return screenshotTokens.any { token -> lowFile.contains(token) || lowAlbum.contains(token) }
    }

    fun isOldScreenshot(
        fileName: String,
        albumOrFolder: String,
        capturedEpochMillis: Long,
        nowMillis: Long,
        olderThanMonths: Int,
        isScreenshotFlag: Boolean = false
    ): Boolean {
        if (olderThanMonths <= 0 || capturedEpochMillis <= 0L) return false
        val isShot = isScreenshotFlag || looksLikeScreenshotNameOrAlbum(fileName, albumOrFolder)
        if (!isShot) return false
        val thresholdMs = olderThanMonths.toLong() * 30L * 86_400_000L
        return (nowMillis - capturedEpochMillis) > thresholdMs
    }

    fun <T> filterMediaSmartClean(
        entries: List<T>,
        options: SmartCleanOptions,
        nowMillis: Long = System.currentTimeMillis(),
        itemOf: (T) -> ManifestItem,
        sha256Of: (T) -> String?
    ): SmartCleanMediaResult<T> {
        if (!options.skipExactDuplicatePhotosSha256 && options.skipOldScreenshotsOlderThanMonths <= 0) {
            return SmartCleanMediaResult(entries, 0, 0, 0L)
        }
        val photoSizeCounts = if (options.skipExactDuplicatePhotosSha256) {
            val counts = HashMap<Long, Int>()
            for (entry in entries) {
                val item = itemOf(entry)
                if (item.category == TransferCategory.PHOTOS && item.sizeBytes > 0L) {
                    counts[item.sizeBytes] = (counts[item.sizeBytes] ?: 0) + 1
                }
            }
            counts
        } else {
            emptyMap()
        }
        val kept = ArrayList<T>(entries.size)
        val seenHashes = HashSet<String>()
        var skippedDups = 0
        var skippedShots = 0
        var savedBytes = 0L

        for (entry in entries) {
            val item = itemOf(entry)
            if (options.skipOldScreenshotsOlderThanMonths > 0 &&
                (item.category == TransferCategory.PHOTOS || item.category == TransferCategory.VIDEOS) &&
                isOldScreenshot(
                    fileName = item.fileName,
                    albumOrFolder = item.relativeAlbumOrFolder,
                    capturedEpochMillis = item.capturedEpochMillis,
                    nowMillis = nowMillis,
                    olderThanMonths = options.skipOldScreenshotsOlderThanMonths,
                    isScreenshotFlag = item.isScreenshot == true
                )
            ) {
                skippedShots++
                savedBytes += item.sizeBytes
                continue
            }

            if (options.skipExactDuplicatePhotosSha256 &&
                item.category == TransferCategory.PHOTOS &&
                (item.sizeBytes <= 0L || (photoSizeCounts[item.sizeBytes] ?: 0) > 1)
            ) {
                val h = sha256Of(entry)
                if (!h.isNullOrBlank() && !seenHashes.add(h)) {
                    skippedDups++
                    savedBytes += item.sizeBytes
                    continue
                }
            }
            kept.add(entry)
        }
        return SmartCleanMediaResult(kept, skippedDups, skippedShots, savedBytes)
    }

    fun computeContentUriSha256(context: Context, uri: android.net.Uri): String? {
        return runCatching {
            val md = MessageDigest.getInstance("SHA-256")
            val buf = ByteArray(65536)
            openMediaOriginalInputStream(context, uri)?.use { stream ->
                while (true) {
                    val n = stream.read(buf)
                    if (n <= 0) break
                    md.update(buf, 0, n)
                }
            } ?: return null
            md.digest().joinToString("") { "%02x".format(it) }
        }.getOrNull()
    }
}

// MARK: - 3. Verifica Integrità Post-Migrazione & Diff

object ReconciliationDiffCore {
    fun evaluate(
        sentItemIds: List<String>,
        expectedHashesById: Map<String, String>,
        committedHashesById: Map<String, String>
    ): ReconcileManifestResponse {
        val committed = ArrayList<String>()
        val missing = ArrayList<String>()
        val mismatch = ArrayList<String>()
        for (id in sentItemIds) {
            val rxHash = committedHashesById[id]
            if (rxHash == null) {
                missing.add(id)
            } else {
                val exp = expectedHashesById[id]
                if (!exp.isNullOrBlank() && !exp.equals(rxHash, ignoreCase = true)) {
                    mismatch.add(id)
                } else {
                    committed.add(id)
                }
            }
        }
        return ReconcileManifestResponse(
            committedIds = committed,
            missingIds = missing,
            hashMismatchIds = mismatch,
            totalVerified = committed.size
        )
    }
}

// MARK: - 4. Rilevamento AP Client Isolation + Fallback Hotspot Guidato

data class NetworkDiagnosticVerdict(
    val likelyApClientIsolation: Boolean,
    val subnetMismatch: Boolean,
    val title: String,
    val description: String,
    val guidanceSteps: List<String>
)

object NetworkIsolationDiagnostics {
    fun analyzePairingFailure(
        localIp: String?,
        targetIps: List<String>,
        isWifiConnected: Boolean,
        errorMessage: String,
        language: DirectSwitchLanguage = DirectSwitchL10n.activeLanguage
    ): NetworkDiagnosticVerdict {
        val localParts = localIp?.split(".")
        val targetPartsList = targetIps.map { it.split(".") }.filter { it.size == 4 }
        val same24Subnet = localParts != null && localParts.size == 4 && targetPartsList.any { tp ->
            tp[0] == localParts[0] && tp[1] == localParts[1] && tp[2] == localParts[2]
        }
        val subnetDiffers = localParts != null && localParts.size == 4 && targetPartsList.isNotEmpty() && !same24Subnet
        val errLow = errorMessage.lowercase(Locale.ROOT)
        val isTimeoutOrBlocked = errLow.contains("timeout") || errLow.contains("timed out") ||
            errLow.contains("refused") || errLow.contains("raggiungere") ||
            errLow.contains("unreachable") || errLow.contains("route") ||
            errLow.contains("impossibile") || errLow.contains("collegarsi") ||
            errLow.contains("non si avvia") || errLow.contains("connessione")

        if (isWifiConnected && same24Subnet && isTimeoutOrBlocked) {
            val subnetLabel = "${localParts[0]}.${localParts[1]}.${localParts[2]}.x"
            return NetworkDiagnosticVerdict(
                likelyApClientIsolation = true,
                subnetMismatch = false,
                title = DirectSwitchL10n.tr(
                    "Router Wi-Fi con AP Client Isolation rilevato",
                    en = "Wi-Fi router with AP Client Isolation detected",
                    fr = "Routeur Wi-Fi avec isolation client AP détecté",
                    lang = language
                ),
                description = DirectSwitchL10n.tr(
                    "Entrambi i telefoni sono sulla stessa rete ($subnetLabel) ma il router blocca la comunicazione diretta tra dispositivi.",
                    en = "Both phones are on the same network ($subnetLabel), but the router blocks direct device-to-device traffic.",
                    fr = "Les deux téléphones sont sur le même réseau ($subnetLabel), mais le routeur bloque la communication directe.",
                    lang = language
                ),
                guidanceSteps = listOf(
                    DirectSwitchL10n.tr(
                        "1. Sul telefono ricevente attiva l'Hotspot Personale (non consuma Giga perché i dati viaggiano in locale).",
                        en = "1. Turn on Personal Hotspot on the receiving phone (uses 0 mobile data; transfer stays local).",
                        fr = "1. Activez le Partage de connexion sur le téléphone récepteur (ne consomme aucune donnée mobile).",
                        lang = language
                    ),
                    DirectSwitchL10n.tr(
                        "2. Collega questo telefono al Wi-Fi dell'Hotspot.",
                        en = "2. Connect this phone to the Hotspot Wi-Fi.",
                        fr = "2. Connectez ce téléphone au Wi-Fi du partage de connexion.",
                        lang = language
                    ),
                    DirectSwitchL10n.tr(
                        "3. Tocca Riprova o inquadra di nuovo il QR: la velocità salirà al massimo.",
                        en = "3. Tap Retry or scan the QR again for maximum speed.",
                        fr = "3. Touchez Réessayer ou scannez à nouveau le QR pour une vitesse maximale.",
                        lang = language
                    )
                )
            )
        }
        if (subnetDiffers) {
            val peerIp = targetIps.firstOrNull().orEmpty()
            return NetworkDiagnosticVerdict(
                likelyApClientIsolation = false,
                subnetMismatch = true,
                title = DirectSwitchL10n.tr(
                    "I due telefoni sono su reti Wi-Fi diverse",
                    en = "Both phones are on different Wi-Fi networks",
                    fr = "Les deux téléphones sont sur des réseaux Wi-Fi différents",
                    lang = language
                ),
                description = DirectSwitchL10n.tr(
                    "Questo telefono è su rete diversa da quella del ricevente ($peerIp).",
                    en = "This phone is on a different subnet from the receiver ($peerIp).",
                    fr = "Ce téléphone est sur un sous-réseau différent du récepteur ($peerIp).",
                    lang = language
                ),
                guidanceSteps = listOf(
                    DirectSwitchL10n.tr(
                        "1. Collega entrambi i telefoni allo stesso Wi-Fi, oppure",
                        en = "1. Connect both phones to the same Wi-Fi network, or",
                        fr = "1. Connectez les deux téléphones au même Wi-Fi, ou",
                        lang = language
                    ),
                    DirectSwitchL10n.tr(
                        "2. Collega questo telefono direttamente all'Hotspot del telefono nuovo.",
                        en = "2. Connect this phone directly to the new phone's Personal Hotspot.",
                        fr = "2. Connectez ce téléphone directement au partage de connexion du nouveau téléphone.",
                        lang = language
                    )
                )
            )
        }
        return NetworkDiagnosticVerdict(
            likelyApClientIsolation = false,
            subnetMismatch = false,
            title = DirectSwitchL10n.tr(
                "Connessione diretta non riuscita",
                en = "Direct connection failed",
                fr = "Échec de la connexion directe",
                lang = language
            ),
            description = DirectSwitchL10n.tr(
                "Controlla che DirectSwitch sia aperto in primo piano sul telefono ricevente e disattiva eventuali VPN.",
                en = "Make sure DirectSwitch is open in the foreground on the receiving phone and turn off any VPN.",
                fr = "Vérifiez que DirectSwitch est ouvert au premier plan sur le récepteur et désactivez tout VPN.",
                lang = language
            ),
            guidanceSteps = listOf(
                DirectSwitchL10n.tr(
                    "1. Disattiva temporaneamente eventuali VPN su entrambi i telefoni.",
                    en = "1. Temporarily disable any VPN on both phones.",
                    fr = "1. Désactivez temporairement tout VPN sur les deux téléphones.",
                    lang = language
                ),
                DirectSwitchL10n.tr(
                    "2. In alternativa usa l'Hotspot Personale diretto tra i due dispositivi.",
                    en = "2. Alternatively, connect directly via Personal Hotspot between both devices.",
                    fr = "2. Sinon, utilisez le Partage de connexion direct entre les deux appareils.",
                    lang = language
                )
            )
        )
    }
}

// MARK: - 5. Compatibilità Media HEIC -> JPEG preservando EXIF (lock anti-OOM 1 bitmap alla volta)

object SharedBitmapDecodeGate {
    val lock = Any()
}

object AndroidHeicCompatibilityConverter {
    private val heicExts = setOf("heic", "heif")

    fun isHeicPhoto(fileName: String, mimeType: String): Boolean {
        val ext = File(fileName).extension.lowercase(Locale.ROOT)
        return ext in heicExts || mimeType.contains("heic", ignoreCase = true) || mimeType.contains("heif", ignoreCase = true)
    }

    fun convertHeicToJpegPreservingExif(
        context: Context,
        sourceUri: android.net.Uri,
        destJpegFile: File
    ): Boolean {
        val srcTemp = File(context.cacheDir, "heic_src_${System.nanoTime()}.heic")
        return try {
            openMediaOriginalInputStream(context, sourceUri)?.use { inp ->
                FileOutputStream(srcTemp).use { out -> inp.copyTo(out) }
            } ?: return false
            convertHeicFileToJpegPreservingExif(srcTemp, destJpegFile)
        } finally {
            runCatching { srcTemp.delete() }
        }
    }

    fun convertHeicFileToJpegPreservingExif(srcFile: File, destJpegFile: File): Boolean {
        return runCatching {
            val compressedOk = synchronized(SharedBitmapDecodeGate.lock) {
                val bmp: Bitmap = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                    ImageDecoder.decodeBitmap(ImageDecoder.createSource(srcFile)) { decoder, _, _ ->
                        decoder.allocator = ImageDecoder.ALLOCATOR_SOFTWARE
                    }
                } else {
                    BitmapFactory.decodeFile(srcFile.absolutePath) ?: return false
                }
                try {
                    FileOutputStream(destJpegFile).use { fos ->
                        bmp.compress(Bitmap.CompressFormat.JPEG, 92, fos)
                    }
                } finally {
                    bmp.recycle()
                }
            }
            if (!compressedOk) return false

            val srcExif = ExifInterface(srcFile.absolutePath)
            val dstExif = ExifInterface(destJpegFile.absolutePath)
            val tagsToPreserve = buildList {
                add(ExifInterface.TAG_DATETIME_ORIGINAL)
                add(ExifInterface.TAG_DATETIME_DIGITIZED)
                add(ExifInterface.TAG_DATETIME)
                add(ExifInterface.TAG_MAKE)
                add(ExifInterface.TAG_MODEL)
                if (Build.VERSION.SDK_INT < Build.VERSION_CODES.P) {
                    add(ExifInterface.TAG_ORIENTATION)
                }
            }
            for (tag in tagsToPreserve) {
                srcExif.getAttribute(tag)?.let { dstExif.setAttribute(tag, it) }
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                dstExif.setAttribute(ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_NORMAL.toString())
            }
            srcExif.latLong?.let { ll -> dstExif.setLatLong(ll[0], ll[1]) }
            dstExif.saveAttributes()
            destJpegFile.exists() && destJpegFile.length() > 0L
        }.getOrDefault(false)
    }
}
