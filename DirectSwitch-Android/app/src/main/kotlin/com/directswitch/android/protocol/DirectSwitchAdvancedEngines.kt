//
//  DirectSwitchAdvancedEngines.kt
//  DirectSwitch-Android
//
//  Created by Nicolas Donati.
//  Copyright © 2026 Nicolas Donati. Tutti i diritti riservati.
//

package com.directswitch.android.protocol

import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import java.io.BufferedOutputStream
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.io.OutputStream
import java.io.RandomAccessFile
import java.security.MessageDigest
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale
import java.util.TimeZone

// ============================================================================
// 1. TIMELINE & CODEC HEALER (Ricostruzione data reale da nome file + Codec + Motion Photo)
// ============================================================================

data class HealedTimelineResult(
    val epochMillis: Long,
    val wasHealedFromFilename: Boolean,
    val sourcePattern: String? = null
)

object MediaTimelineHealer {
    private const val MIN_VALID_YEAR = 2000
    private const val MAX_VALID_YEAR = 2035
    private const val ONE_DAY_MS = 86_400_000L

    private val whatsappNameRegex = Regex(
        """(?:IMG|VID|PTT|AUD|DOC)-(\d{4})(\d{2})(\d{2})-WA\d+""",
        RegexOption.IGNORE_CASE
    )
    private val whatsappLongRegex = Regex(
        """WhatsApp\s+(?:Image|Video|Audio)\s+(\d{4})-(\d{2})-(\d{2})\s+(?:at|alle)\s+(\d{1,2})\.(\d{2})\.(\d{2})""",
        RegexOption.IGNORE_CASE
    )
    private val ymdHmsCompactRegex = Regex(
        """(?:^|[_\-\s])(\d{4})(\d{2})(\d{2})[_\-T](\d{2})(\d{2})(\d{2})(?:\D|$)"""
    )
    private val ymdHmsDashedRegex = Regex(
        """(?:^|[_\-\s])(\d{4})[-.](\d{2})[-.](\d{2})[_\-\sT](\d{2})[-.:](\d{2})[-.:](\d{2})(?:\D|$)"""
    )
    private val ymdDashedOnlyRegex = Regex(
        """(?:^|[_\-\s])(\d{4})-(\d{2})-(\d{2})(?:\D|$)"""
    )
    private val unixMillisStemRegex = Regex("""^(1[0-9]{12})$""")
    private val unixSecondsStemRegex = Regex("""^(1[0-9]{9})$""")

    fun extractTimestampFromFilename(
        fileName: String,
        nowEpochMillis: Long = System.currentTimeMillis()
    ): Pair<Long, String>? {
        val base = File(fileName).name.trim()
        if (base.isEmpty()) return null
        val maxAllowed = nowEpochMillis + ONE_DAY_MS

        whatsappLongRegex.find(base)?.let { m ->
            val ts = buildUtcOrLocalMillis(
                year = m.groupValues[1].toInt(),
                month = m.groupValues[2].toInt(),
                day = m.groupValues[3].toInt(),
                hour = m.groupValues[4].toInt(),
                minute = m.groupValues[5].toInt(),
                second = m.groupValues[6].toInt()
            )
            if (ts != null && ts <= maxAllowed) return ts to "whatsapp_long"
        }

        whatsappNameRegex.find(base)?.let { m ->
            val ts = buildUtcOrLocalMillis(
                year = m.groupValues[1].toInt(),
                month = m.groupValues[2].toInt(),
                day = m.groupValues[3].toInt(),
                hour = 12,
                minute = 0,
                second = 0
            )
            if (ts != null && ts <= maxAllowed) return ts to "whatsapp_wa"
        }

        ymdHmsDashedRegex.find(base)?.let { m ->
            val ts = buildUtcOrLocalMillis(
                year = m.groupValues[1].toInt(),
                month = m.groupValues[2].toInt(),
                day = m.groupValues[3].toInt(),
                hour = m.groupValues[4].toInt(),
                minute = m.groupValues[5].toInt(),
                second = m.groupValues[6].toInt()
            )
            if (ts != null && ts <= maxAllowed) return ts to "ymd_hms_dashed"
        }

        ymdHmsCompactRegex.find(base)?.let { m ->
            val ts = buildUtcOrLocalMillis(
                year = m.groupValues[1].toInt(),
                month = m.groupValues[2].toInt(),
                day = m.groupValues[3].toInt(),
                hour = m.groupValues[4].toInt(),
                minute = m.groupValues[5].toInt(),
                second = m.groupValues[6].toInt()
            )
            if (ts != null && ts <= maxAllowed) return ts to "ymd_hms_compact"
        }

        ymdDashedOnlyRegex.find(base)?.let { m ->
            val ts = buildUtcOrLocalMillis(
                year = m.groupValues[1].toInt(),
                month = m.groupValues[2].toInt(),
                day = m.groupValues[3].toInt(),
                hour = 12,
                minute = 0,
                second = 0
            )
            if (ts != null && ts <= maxAllowed) return ts to "ymd_dashed"
        }

        val stem = base.substringBeforeLast('.', base)
        unixMillisStemRegex.find(stem)?.let { m ->
            val ts = m.groupValues[1].toLongOrNull()
            if (ts != null && isValidEpochMillis(ts, maxAllowed)) return ts to "unix_ms"
        }
        unixSecondsStemRegex.find(stem)?.let { m ->
            val sec = m.groupValues[1].toLongOrNull()
            val ts = sec?.times(1000L)
            if (ts != null && isValidEpochMillis(ts, maxAllowed)) return ts to "unix_sec"
        }

        return null
    }

    /**
     * Determina la data di scatto migliore:
     * - Se `reportedEpochMillis <= 0` usa quella estratta dal nome file.
     * - Se `reportedEpochMillis` è sospettosamente recente (entro 24h da ora, tipico di copie WhatsApp/Download)
     *   e il nome file codifica una data valida più vecchia di almeno 48h, ripristina la data reale dal nome file.
     */
    fun resolveBestCaptureEpochMillis(
        fileName: String,
        reportedEpochMillis: Long,
        nowEpochMillis: Long = System.currentTimeMillis()
    ): HealedTimelineResult {
        val fromName = extractTimestampFromFilename(fileName, nowEpochMillis)
        if (reportedEpochMillis <= 0L) {
            return if (fromName != null) {
                HealedTimelineResult(fromName.first, wasHealedFromFilename = true, sourcePattern = fromName.second)
            } else {
                HealedTimelineResult(0L, wasHealedFromFilename = false)
            }
        }
        if (fromName != null) {
            val looksLikeCopyDate = kotlin.math.abs(nowEpochMillis - reportedEpochMillis) <= ONE_DAY_MS
            val filenameIsSignificantlyOlder = fromName.first < reportedEpochMillis - (2L * ONE_DAY_MS)
            if (looksLikeCopyDate && filenameIsSignificantlyOlder) {
                return HealedTimelineResult(fromName.first, wasHealedFromFilename = true, sourcePattern = fromName.second)
            }
        }
        return HealedTimelineResult(reportedEpochMillis, wasHealedFromFilename = false)
    }

    fun formatExifDateTime(epochMillis: Long): String {
        val sdf = SimpleDateFormat("yyyy:MM:dd HH:mm:ss", Locale.US)
        sdf.timeZone = TimeZone.getDefault()
        return sdf.format(Date(epochMillis))
    }

    private fun isValidEpochMillis(ts: Long, maxAllowed: Long): Boolean {
        val min2000 = 946_684_800_000L
        return ts in min2000..maxAllowed
    }

    private fun buildUtcOrLocalMillis(
        year: Int,
        month: Int,
        day: Int,
        hour: Int,
        minute: Int,
        second: Int
    ): Long? {
        if (year !in MIN_VALID_YEAR..MAX_VALID_YEAR) return null
        if (month !in 1..12 || day !in 1..31) return null
        if (hour !in 0..23 || minute !in 0..59 || second !in 0..59) return null
        val cal = Calendar.getInstance()
        cal.isLenient = false
        return runCatching {
            cal.set(year, month - 1, day, hour, minute, second)
            cal.set(Calendar.MILLISECOND, 0)
            cal.timeInMillis
        }.getOrNull()
    }
}

object CrossOsCodecCompatibilityHelper {
    private val iosHostileAudioExts = setOf("opus", "ogg", "oga", "amr", "3gp", "3gpp", "wma", "webm", "mka")

    fun needsAudioTranscodeForIos(fileName: String, mimeType: String = ""): Boolean {
        val ext = File(fileName).extension.lowercase(Locale.ROOT)
        if (ext in iosHostileAudioExts) return true
        val m = mimeType.lowercase(Locale.ROOT)
        return m.contains("opus") || m.contains("ogg") || m.contains("amr") || m.contains("x-ms-wma")
    }

    fun healedM4aFileName(originalName: String): String {
        val clean = File(originalName).name.ifBlank { "audio_memo" }
        val dot = clean.lastIndexOf('.')
        val stem = if (dot > 0) clean.substring(0, dot) else clean
        return "$stem.m4a"
    }
}

data class ParsedDirectSwitchMotionPhoto(
    val stillLength: Long,
    val stillExtension: String,
    val videoStartOffset: Long,
    val videoLength: Long,
    val presentationTimestampUs: Long,
    val detectionSource: String
)

/**
 * Codec streaming puro-JVM per la conversione bidirezionale Motion Photo (Android) <-> Live Photo (iOS)
 * durante i trasferimenti diretti DirectSwitch (Google XMP 1.0, Pixel MicroVideo, Samsung MotionPhoto_Data).
 */
object DirectSwitchMotionPhotoCodec {
    private const val STREAM_BUFFER_BYTES = 64 * 1024
    private const val TAIL_SCAN_WINDOW_BYTES = 256 * 1024
    private val XMP_APP1_HEADER = "http://ns.adobe.com/xap/1.0/\u0000".toByteArray(Charsets.US_ASCII)
    private val EXT_XMP_APP1_HEADER = "http://ns.adobe.com/xmp/extension/\u0000".toByteArray(Charsets.US_ASCII)
    private val SAMSUNG_MARKER = "MotionPhoto_Data".toByteArray(Charsets.US_ASCII)
    private val FTYP_BYTES = "ftyp".toByteArray(Charsets.US_ASCII)

    fun looksLikeMotionPhotoCandidateQuick(file: File): Boolean {
        if (!file.exists() || !file.isFile) return false
        val len = file.length()
        if (len < 4096L || len > 120L * 1024L * 1024L) return false
        return runCatching {
            RandomAccessFile(file, "r").use { raf ->
                val headSize = minOf(len, 256L * 1024L).toInt()
                val head = ByteArray(headSize)
                raf.readFully(head)
                val headStr = String(head, Charsets.ISO_8859_1)
                if (headStr.contains("MotionPhoto") || headStr.contains("MicroVideo")) {
                    return@use true
                }
                if (head.size >= 2 && head[0] == 0xFF.toByte() && head[1] == 0xD8.toByte()) {
                    val scanStart = (len - 20L * 1024L * 1024L).coerceAtLeast(256L)
                    return@use findBytesInRafWindow(raf, scanStart, len, SAMSUNG_MARKER) >= 0L
                }
                false
            }
        }.getOrDefault(false)
    }

    fun parseMotionPhotoFile(
        srcFile: File,
        outStillFile: File,
        outVideoFile: File
    ): ParsedDirectSwitchMotionPhoto? {
        if (!srcFile.exists() || !srcFile.isFile) return null
        val fileLen = srcFile.length()
        if (fileLen < 4096L || fileLen > 120L * 1024L * 1024L) return null

        return runCatching {
            RandomAccessFile(srcFile, "r").use { raf ->
                val headerScanLen = minOf(fileLen, 512L * 1024L).toInt()
                val head = ByteArray(headerScanLen)
                raf.readFully(head)

                val isJpeg = head[0] == 0xFF.toByte() && head[1] == 0xD8.toByte()
                val isHeic = isHeicHeader(head)
                if (!isJpeg && !isHeic) return@use null

                val xmpStr = String(head, 0, headerScanLen, Charsets.ISO_8859_1)
                val ptsUs = (extractLongAttr(xmpStr, "MotionPhotoPresentationTimestampUs")
                    ?: extractLongAttr(xmpStr, "MicroVideoPresentationTimestampUs")
                    ?: 0L).coerceAtLeast(0L)
                val stillExt = if (isHeic) "heic" else "jpg"

                val hasMotionFlag = Regex("""\b(?:G?Camera:)?MotionPhoto\s*=\s*["']1["']""")
                    .containsMatchIn(xmpStr) ||
                    Regex("""<(?:G?Camera:)?MotionPhoto>\s*1\s*</(?:G?Camera:)?MotionPhoto>""")
                        .containsMatchIn(xmpStr)
                if (hasMotionFlag) {
                    val dirMatch = extractContainerMotionPhotoLengthLong(xmpStr)
                    if (dirMatch != null) {
                        val (videoLen, padding) = dirMatch
                        if (videoLen in 1024L until (fileLen - 128L)) {
                            val candidateOffset = fileLen - videoLen - padding
                            val mp4Start = findFtypBoxNearInRaf(raf, fileLen, candidateOffset)
                            if (mp4Start != null && mp4Start > 128L && mp4Start + 1024L <= fileLen) {
                                val stillEnd = candidateOffset.coerceIn(128L, mp4Start)
                                copyRafRangeToFile(raf, 0L, stillEnd, outStillFile)
                                copyRafRangeToFile(raf, mp4Start, fileLen - mp4Start, outVideoFile)
                                return@use ParsedDirectSwitchMotionPhoto(
                                    stillLength = stillEnd,
                                    stillExtension = stillExt,
                                    videoStartOffset = mp4Start,
                                    videoLength = fileLen - mp4Start,
                                    presentationTimestampUs = ptsUs,
                                    detectionSource = "xmp_container"
                                )
                            }
                        }
                    }
                }

                val hasMicroFlag = Regex("""\b(?:G?Camera:)?MicroVideo\s*=\s*["']1["']""")
                    .containsMatchIn(xmpStr)
                if (hasMicroFlag) {
                    val offsetLen = extractLongAttr(xmpStr, "MicroVideoOffset")
                    if (offsetLen != null && offsetLen in 1024L until (fileLen - 128L)) {
                        val candidateOffset = fileLen - offsetLen
                        val mp4Start = findFtypBoxNearInRaf(raf, fileLen, candidateOffset)
                        if (mp4Start != null && mp4Start > 128L && mp4Start + 1024L <= fileLen) {
                            copyRafRangeToFile(raf, 0L, mp4Start, outStillFile)
                            copyRafRangeToFile(raf, mp4Start, fileLen - mp4Start, outVideoFile)
                            return@use ParsedDirectSwitchMotionPhoto(
                                stillLength = mp4Start,
                                stillExtension = stillExt,
                                videoStartOffset = mp4Start,
                                videoLength = fileLen - mp4Start,
                                presentationTimestampUs = ptsUs,
                                detectionSource = "xmp_microvideo"
                            )
                        }
                    }
                }

                if (isJpeg) {
                    val scanStart = (fileLen - 20L * 1024L * 1024L).coerceAtLeast(256L)
                    val markerPos = findBytesInRafWindow(raf, scanStart, fileLen, SAMSUNG_MARKER)
                    if (markerPos in 256L until (fileLen - 1024L)) {
                        val searchMp4From = markerPos + SAMSUNG_MARKER.size
                        val probeLen = minOf(64L, fileLen - searchMp4From).toInt()
                        if (probeLen >= 16) {
                            val probe = ByteArray(probeLen)
                            raf.seek(searchMp4From)
                            raf.readFully(probe)
                            val relMp4 = findFtypBoxInRange(probe, 0, probeLen)
                            if (relMp4 != null) {
                                val mp4Start = searchMp4From + relMp4.toLong()
                                if (mp4Start + 1024L <= fileLen) {
                                    val stillEnd = findJpegEoiJustBeforeInRaf(raf, markerPos) ?: markerPos
                                    copyRafRangeToFile(raf, 0L, stillEnd, outStillFile)
                                    copyRafRangeToFile(raf, mp4Start, fileLen - mp4Start, outVideoFile)
                                    return@use ParsedDirectSwitchMotionPhoto(
                                        stillLength = stillEnd,
                                        stillExtension = "jpg",
                                        videoStartOffset = mp4Start,
                                        videoLength = fileLen - mp4Start,
                                        presentationTimestampUs = 0L,
                                        detectionSource = "samsung_marker"
                                    )
                                }
                            }
                        }
                    }
                }
                null
            }
        }.getOrNull()
    }

    fun buildMotionPhotoJpegToFile(
        stillJpegFile: File,
        mp4File: File,
        presentationTimestampUs: Long = 0L,
        outMotionJpegFile: File
    ) {
        require(stillJpegFile.exists() && stillJpegFile.length() >= 4L) {
            "Fotogramma JPEG statico non valido."
        }
        val mp4Length = mp4File.length()
        require(mp4File.exists() && mp4Length >= 32L) {
            "Clip video MP4 non valida."
        }
        val xmpPacket = buildXmpMotionPhotoPacket(mp4Length, presentationTimestampUs)
        val segPayloadLen = XMP_APP1_HEADER.size + xmpPacket.size
        val segTotalFieldLen = 2 + segPayloadLen
        require(segTotalFieldLen <= 0xFFFF) { "Segmento XMP oltre 64 KB." }

        outMotionJpegFile.parentFile?.mkdirs()
        RandomAccessFile(stillJpegFile, "r").use { stillRaf ->
            val stillLen = stillRaf.length()
            val b0 = stillRaf.read()
            val b1 = stillRaf.read()
            require(b0 == 0xFF && b1 == 0xD8) { "Fotogramma statico non è JPEG." }

            BufferedOutputStream(FileOutputStream(outMotionJpegFile), STREAM_BUFFER_BYTES).use { out ->
                out.write(0xFF)
                out.write(0xD8)
                out.write(0xFF)
                out.write(0xE1)
                out.write((segTotalFieldLen ushr 8) and 0xFF)
                out.write(segTotalFieldLen and 0xFF)
                out.write(XMP_APP1_HEADER)
                out.write(xmpPacket)
                streamStillWithoutXmpAfterSoi(stillRaf, stillLen, out)
                FileInputStream(mp4File).use { mp4In ->
                    mp4In.copyTo(out, STREAM_BUFFER_BYTES)
                }
                out.flush()
            }
        }
    }

    private fun buildXmpMotionPhotoPacket(mp4Length: Long, presentationTimestampUs: Long): ByteArray {
        val safePts = presentationTimestampUs.coerceAtLeast(0L)
        return """<?xpacket begin="﻿" id="W5M0MpCehiHzreSzNTczkc9d"?>
<x:xmpmeta xmlns:x="adobe:ns:meta/">
 <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
  <rdf:Description rdf:about=""
    xmlns:GCamera="http://ns.google.com/photos/1.0/camera/"
    xmlns:Container="http://ns.google.com/photos/1.0/container/"
    xmlns:Item="http://ns.google.com/photos/1.0/container/item/"
    GCamera:MotionPhoto="1"
    GCamera:MotionPhotoVersion="1"
    GCamera:MotionPhotoPresentationTimestampUs="$safePts">
   <Container:Directory>
    <rdf:Seq>
     <rdf:li rdf:parseType="Resource">
      <Container:Item
        Item:Mime="image/jpeg"
        Item:Semantic="Primary"
        Item:Length="0"
        Item:Padding="0"/>
     </rdf:li>
     <rdf:li rdf:parseType="Resource">
      <Container:Item
        Item:Mime="video/mp4"
        Item:Semantic="MotionPhoto"
        Item:Length="$mp4Length"
        Item:Padding="0"/>
     </rdf:li>
    </rdf:Seq>
   </Container:Directory>
  </rdf:Description>
 </rdf:RDF>
</x:xmpmeta>
<?xpacket end="w"?>""".toByteArray(Charsets.UTF_8)
    }

    private fun streamStillWithoutXmpAfterSoi(raf: RandomAccessFile, stillLen: Long, out: OutputStream) {
        val copyBuf = ByteArray(STREAM_BUFFER_BYTES)
        val probeHeader = ByteArray(maxOf(XMP_APP1_HEADER.size, EXT_XMP_APP1_HEADER.size))
        var pos = 2L
        while (pos + 1L < stillLen) {
            raf.seek(pos)
            if (raf.read() != 0xFF) {
                copyRafRangeToStream(raf, pos, stillLen - pos, out, copyBuf)
                return
            }
            var markerPos = pos + 1L
            var marker = raf.read()
            while (marker == 0xFF && markerPos + 1L < stillLen) {
                markerPos++
                marker = raf.read()
            }
            if (marker < 0 || marker == 0xFF) break
            if (marker == 0x00 || marker == 0x01 || marker in 0xD0..0xD9) {
                copyRafRangeToStream(raf, pos, (markerPos + 1L) - pos, out, copyBuf)
                pos = markerPos + 1L
                if (marker == 0xD9) return
                continue
            }
            if (marker == 0xDA || markerPos + 2L >= stillLen) {
                copyRafRangeToStream(raf, pos, stillLen - pos, out, copyBuf)
                return
            }
            raf.seek(markerPos + 1L)
            val lenHi = raf.read()
            val lenLo = raf.read()
            if (lenHi < 0 || lenLo < 0) {
                copyRafRangeToStream(raf, pos, stillLen - pos, out, copyBuf)
                return
            }
            val segLen = ((lenHi and 0xFF) shl 8) or (lenLo and 0xFF)
            val segEnd = (markerPos + 1L + segLen.toLong()).coerceAtMost(stillLen)
            val payloadStart = markerPos + 3L
            var isXmp = false
            if (marker == 0xE1 && segEnd > payloadStart) {
                val avail = minOf(probeHeader.size.toLong(), segEnd - payloadStart).toInt()
                raf.seek(payloadStart)
                raf.readFully(probeHeader, 0, avail)
                isXmp = (avail >= XMP_APP1_HEADER.size && startsWithBytes(probeHeader, 0, XMP_APP1_HEADER)) ||
                    (avail >= EXT_XMP_APP1_HEADER.size && startsWithBytes(probeHeader, 0, EXT_XMP_APP1_HEADER))
            }
            if (!isXmp) {
                copyRafRangeToStream(raf, pos, segEnd - pos, out, copyBuf)
            }
            pos = segEnd
        }
    }

    private fun copyRafRangeToFile(raf: RandomAccessFile, startOffset: Long, length: Long, destFile: File) {
        destFile.parentFile?.mkdirs()
        val buf = ByteArray(STREAM_BUFFER_BYTES)
        BufferedOutputStream(FileOutputStream(destFile), STREAM_BUFFER_BYTES).use { out ->
            copyRafRangeToStream(raf, startOffset, length, out, buf)
            out.flush()
        }
    }

    private fun copyRafRangeToStream(
        raf: RandomAccessFile,
        startOffset: Long,
        length: Long,
        out: OutputStream,
        buf: ByteArray
    ) {
        if (length <= 0L) return
        raf.seek(startOffset)
        var remaining = length
        while (remaining > 0L) {
            val chunk = minOf(remaining, buf.size.toLong()).toInt()
            val read = raf.read(buf, 0, chunk)
            if (read <= 0) break
            out.write(buf, 0, read)
            remaining -= read.toLong()
        }
    }

    private fun findFtypBoxNearInRaf(raf: RandomAccessFile, fileLen: Long, expectedStart: Long): Long? {
        val winStart = (expectedStart - 24L).coerceAtLeast(8L)
        val winEnd = (expectedStart + 40L).coerceAtMost(fileLen)
        val winLen = (winEnd - winStart).toInt()
        if (winLen < 12) return null
        val win = ByteArray(winLen)
        raf.seek(winStart)
        raf.readFully(win)
        val rel = findFtypBoxInRange(win, 0, winLen) ?: return null
        return winStart + rel.toLong()
    }

    private fun findJpegEoiJustBeforeInRaf(raf: RandomAccessFile, beforePos: Long): Long? {
        val minSearch = (beforePos - 256L).coerceAtLeast(2L)
        val winLen = (beforePos - minSearch).toInt()
        if (winLen < 2) return null
        val win = ByteArray(winLen)
        raf.seek(minSearch)
        raf.readFully(win)
        for (i in (winLen - 2) downTo 0) {
            if (win[i] == 0xFF.toByte() && win[i + 1] == 0xD9.toByte()) {
                return minSearch + i.toLong() + 2L
            }
        }
        return null
    }

    private fun findBytesInRafWindow(raf: RandomAccessFile, fromOffset: Long, toOffset: Long, needle: ByteArray): Long {
        if (needle.isEmpty() || toOffset - fromOffset < needle.size.toLong()) return -1L
        val window = ByteArray(TAIL_SCAN_WINDOW_BYTES)
        val overlap = (needle.size - 1).coerceAtLeast(0)
        var pos = fromOffset.coerceAtLeast(0L)
        while (pos < toOffset) {
            val toRead = minOf(window.size.toLong(), toOffset - pos).toInt()
            if (toRead < needle.size) break
            raf.seek(pos)
            raf.readFully(window, 0, toRead)
            val idx = indexOfBytesInLimit(window, toRead, needle, 0)
            if (idx >= 0) return pos + idx.toLong()
            if (pos + toRead.toLong() >= toOffset) break
            pos += (toRead - overlap).toLong()
        }
        return -1L
    }

    private fun extractLongAttr(xmp: String, attrLocalName: String): Long? {
        val attrMatch = Regex("""\b(?:G?Camera:)?$attrLocalName\s*=\s*["'](-?\d+)["']""").find(xmp)
        if (attrMatch != null) return attrMatch.groupValues[1].toLongOrNull()
        val elemMatch = Regex("""<(?:G?Camera:)?$attrLocalName>\s*(-?\d+)\s*</(?:G?Camera:)?$attrLocalName>""").find(xmp)
        return elemMatch?.groupValues?.get(1)?.toLongOrNull()
    }

    private fun extractContainerMotionPhotoLengthLong(xmp: String): Pair<Long, Long>? {
        val itemRegex = Regex("""<(?:Container:)?Item\b([^>]*)/>""", setOf(RegexOption.DOT_MATCHES_ALL))
        for (m in itemRegex.findAll(xmp)) {
            val attrs = m.groupValues[1]
            if (Regex("""\bItem:Semantic\s*=\s*["']MotionPhoto["']""").containsMatchIn(attrs)) {
                val len = Regex("""\bItem:Length\s*=\s*["'](\d+)["']""").find(attrs)?.groupValues?.get(1)?.toLongOrNull()
                val pad = Regex("""\bItem:Padding\s*=\s*["'](\d+)["']""").find(attrs)?.groupValues?.get(1)?.toLongOrNull() ?: 0L
                if (len != null && len > 0L) return len to pad
            }
        }
        return null
    }

    private fun isHeicHeader(bytes: ByteArray): Boolean {
        if (bytes.size < 12) return false
        if (!startsWithBytes(bytes, 4, FTYP_BYTES)) return false
        val brand = String(bytes, 8, 4, Charsets.US_ASCII).lowercase(Locale.US)
        return brand in setOf("heic", "heix", "hevc", "hevx", "mif1", "msf1")
    }

    private fun findFtypBoxInRange(bytes: ByteArray, from: Int, to: Int): Int? {
        val safeEnd = minOf(to, bytes.size) - 4
        var i = maxOf(from, 4)
        while (i <= safeEnd) {
            if (startsWithBytes(bytes, i, FTYP_BYTES)) return i - 4
            i++
        }
        return null
    }

    private fun startsWithBytes(haystack: ByteArray, offset: Int, needle: ByteArray): Boolean {
        if (offset < 0 || offset + needle.size > haystack.size) return false
        for (i in needle.indices) {
            if (haystack[offset + i] != needle[i]) return false
        }
        return true
    }

    private fun indexOfBytesInLimit(haystack: ByteArray, limit: Int, needle: ByteArray, fromIndex: Int): Int {
        if (needle.isEmpty() || fromIndex >= limit) return -1
        val maxStart = limit - needle.size
        outer@ for (i in maxOf(0, fromIndex)..maxStart) {
            for (j in needle.indices) {
                if (haystack[i + j] != needle[j]) continue@outer
            }
            return i
        }
        return -1
    }
}

// ============================================================================
// 2. TRIAGE BATTERIA CRITICA + RECUPERO DELTA 14–30 GIORNI
// ============================================================================

object BatteryTriagePlanner {
    const val CRITICAL_BATTERY_PERCENT = 15
    private const val SMALL_VIDEO_THRESHOLD_BYTES = 50L * 1024L * 1024L

    fun shouldAutoActivate(batteryPercent: Int, isCharging: Boolean): Boolean =
        batteryPercent in 1..CRITICAL_BATTERY_PERCENT && !isCharging

    fun priorityBucket(item: ManifestItem): Int {
        if (item.relativeAlbumOrFolder.equals("Password_e_Accessi", ignoreCase = true) ||
            (item.category == TransferCategory.DOCUMENTS && item.fileName.endsWith(".csv", ignoreCase = true))
        ) {
            return 0
        }
        return when (item.category) {
            TransferCategory.DOCUMENTS, TransferCategory.WHATSAPP_VAULT -> 1
            TransferCategory.AUDIO -> 2
            TransferCategory.PHOTOS -> if (item.isFavorite == true) 3 else 4
            TransferCategory.VIDEOS -> if (item.sizeBytes <= SMALL_VIDEO_THRESHOLD_BYTES) 5 else 6
            else -> 1
        }
    }

    /**
     * Ordina i file massimizzando la sopravvivenza dei dati insostituibili quando la batteria è critica:
     * Password CSV -> Documenti/WhatsApp (più leggeri prima) -> Audio -> Foto Preferite -> Foto recenti -> Video leggeri -> Video 4K pesanti.
     */
    fun <T> sortByTriagePriority(entries: List<T>, itemSelector: (T) -> ManifestItem): List<T> {
        return entries.sortedWith(
            compareBy<T> { priorityBucket(itemSelector(it)) }
                .thenBy { entry ->
                    val item = itemSelector(entry)
                    val bucket = priorityBucket(item)
                    if (bucket <= 1) item.sizeBytes else -item.capturedEpochMillis
                }
                .thenBy { itemSelector(it).sizeBytes }
        )
    }
}

@Serializable
data class CompletedMigrationRecord(
    val sessionId: String,
    val peerName: String,
    val peerPlatform: DevicePlatform,
    val completedAtEpochMillis: Long,
    val transferredFilesCount: Int,
    val transferredBytes: Long,
    val transferredDedupKeys: List<String> = emptyList(),
    val lastScope: ActiveTransferScope = ActiveTransferScope()
) {
    fun daysSinceCompleted(nowEpochMillis: Long = System.currentTimeMillis()): Int {
        val diff = (nowEpochMillis - completedAtEpochMillis).coerceAtLeast(0L)
        return (diff / 86_400_000L).toInt()
    }
}

object CompletedMigrationStore {
    private const val FILE_NAME = "completed_migration_delta_v1.json"
    private const val RETENTION_MS = 30L * 24L * 60L * 60L * 1000L
    private const val MAX_STORED_KEYS = 25_000

    fun defaultFile(filesDir: File): File = File(filesDir, FILE_NAME)

    fun save(file: File, record: CompletedMigrationRecord) {
        val trimmed = if (record.transferredDedupKeys.size > MAX_STORED_KEYS) {
            record.copy(transferredDedupKeys = record.transferredDedupKeys.takeLast(MAX_STORED_KEYS))
        } else {
            record
        }
        runCatching {
            file.parentFile?.mkdirs()
            val tmp = File(file.parentFile, "${file.name}.tmp")
            tmp.writeText(DirectSwitchJson.instance.encodeToString(trimmed), Charsets.UTF_8)
            if (!tmp.renameTo(file)) {
                tmp.copyTo(file, overwrite = true)
                tmp.delete()
            }
        }
    }

    fun load(file: File, nowEpochMillis: Long = System.currentTimeMillis()): CompletedMigrationRecord? {
        if (!file.exists()) return null
        val parsed = runCatching {
            DirectSwitchJson.instance.decodeFromString<CompletedMigrationRecord>(file.readText(Charsets.UTF_8))
        }.getOrNull() ?: return null
        if (nowEpochMillis - parsed.completedAtEpochMillis > RETENTION_MS) {
            clear(file)
            return null
        }
        return parsed
    }

    fun clear(file: File) {
        runCatching { if (file.exists()) file.delete() }
    }

    /**
     * Filtra solo gli elementi nuovi o modificati dopo l'ultima migrazione completata (con tolleranza di 5 minuti
     * e anti-duplicazione deterministica tramite `transferredDedupKeys`).
     */
    fun <T> filterDeltaEntries(
        entries: List<T>,
        record: CompletedMigrationRecord,
        itemSelector: (T) -> ManifestItem
    ): List<T> {
        val seenKeys = record.transferredDedupKeys.toHashSet()
        val cutoff = (record.completedAtEpochMillis - 5L * 60L * 1000L).coerceAtLeast(0L)
        return entries.filter { entry ->
            val item = itemSelector(entry)
            if (item.dedupKey in seenKeys) return@filter false
            if (item.capturedEpochMillis > 0L) {
                item.capturedEpochMillis >= cutoff
            } else {
                true
            }
        }
    }

    fun filterDeltaSms(list: List<SmsTransferRecord>, record: CompletedMigrationRecord): List<SmsTransferRecord> {
        val cutoff = (record.completedAtEpochMillis - 5L * 60L * 1000L).coerceAtLeast(0L)
        return list.filter { it.dateEpochMillis >= cutoff }
    }

    fun filterDeltaCallLogs(list: List<CallLogTransferRecord>, record: CompletedMigrationRecord): List<CallLogTransferRecord> {
        val cutoff = (record.completedAtEpochMillis - 5L * 60L * 1000L).coerceAtLeast(0L)
        return list.filter { it.dateEpochMillis >= cutoff }
    }

    fun filterDeltaCalendars(list: List<CalendarEventRecord>, record: CompletedMigrationRecord): List<CalendarEventRecord> {
        val cutoff = (record.completedAtEpochMillis - 5L * 60L * 1000L).coerceAtLeast(0L)
        return list.filter { it.endEpochMillis >= cutoff || it.startEpochMillis >= cutoff }
    }
}

// ============================================================================
// 3. AUDIT ANTI-LOCKOUT DINAMICO (Banche/SPID/2FA/SIM) + CERTIFICATO PRONTO PER RESET
// ============================================================================

@Serializable
enum class SensitiveAppRiskKind(val displayLabel: String) {
    SPID_IDENTITY("SPID / Identità Digitale"),
    TWO_FACTOR_AUTH("Authenticator / 2FA"),
    BANKING_PAYMENTS("Banca / Pagamenti"),
    CRYPTO_WALLET("Wallet Crypto"),
    ESIM_CARRIER("eSIM / Operatore")
}

@Serializable
data class SensitiveAppAuditItem(
    val canonicalId: String,
    val appName: String,
    val riskKind: SensitiveAppRiskKind,
    val isPresentOnReceiver: Boolean,
    val guidance: String
)

enum class DecommissionReadinessLevel {
    BLOCKED_RED,
    CAUTION_AMBER,
    READY_FOR_RESET_GREEN
}

data class DecommissionAuditReport(
    val sessionId: String,
    val peerName: String,
    val peerPlatform: DevicePlatform,
    val checkedWithLiveReceiver: Boolean,
    val missingCriticalApps: List<SensitiveAppAuditItem>,
    val verifiedCriticalApps: List<SensitiveAppAuditItem>,
    val localOnlyContactsCount: Int,
    val contactsWereMigrated: Boolean,
    val icloudPhantomMediaCount: Int,
    val unresolvedSkippedItemsCount: Int,
    val readinessLevel: DecommissionReadinessLevel,
    val completedFilesCount: Int,
    val transferredBytes: Long,
    val certificateSha256: String,
    val generatedAtEpochMillis: Long
)

object SensitiveAppRiskClassifier {
    private data class KnownSensitiveAppRule(
        val canonicalId: String,
        val displayName: String,
        val riskKind: SensitiveAppRiskKind,
        val identifiers: Set<String>,
        val nameKeywords: Set<String>,
        val guidance: String
    )

    private val rules: List<KnownSensitiveAppRule> = listOf(
        // SPID & Identità Digitale
        KnownSensitiveAppRule(
            "posteid", "PosteID", SensitiveAppRiskKind.SPID_IDENTITY,
            setOf("posteitaliane.posteapp.appposteid", "it.poste.postebuy2", "posteid"),
            setOf("posteid"),
            "Attiva PosteID sul nuovo telefono prima di rimuoverlo dal vecchio (eviti il blocco SPID)."
        ),
        KnownSensitiveAppRule(
            "cieid", "CieID", SensitiveAppRiskKind.SPID_IDENTITY,
            setOf("it.ipzs.cieid", "it.ipzs.cieID", "cieid"),
            setOf("cieid", "cie id"),
            "Registra la tua Carta d'Identità Elettronica (CIE) sul nuovo telefono con PIN e NFC."
        ),
        KnownSensitiveAppRule(
            "app_io", "IO — Servizi Pubblici", SensitiveAppRiskKind.SPID_IDENTITY,
            setOf("it.pagopa.io.app", "it.pagopa.app.io", "ioit"),
            setOf("app io"),
            "Accedi ad App IO sul nuovo telefono con SPID o CIE."
        ),
        KnownSensitiveAppRule(
            "aruba_otp", "Aruba OTP / PEC", SensitiveAppRiskKind.SPID_IDENTITY,
            setOf("it.aruba.otp", "it.aruba.pec.mobile", "it.aruba.mobilepec"),
            setOf("aruba otp", "aruba pec"),
            "Trasferisci il token Aruba OTP finché il vecchio dispositivo genera ancora codici."
        ),
        KnownSensitiveAppRule(
            "lepida_id", "LepidaID", SensitiveAppRiskKind.SPID_IDENTITY,
            setOf("it.lepida.lepidaid"),
            setOf("lepidaid"),
            "Riassocia LepidaID sul nuovo telefono prima del reset."
        ),
        KnownSensitiveAppRule(
            "sielte_id", "MySielteID", SensitiveAppRiskKind.SPID_IDENTITY,
            setOf("it.sielte.mysielteid"),
            setOf("sielteid", "mysielteid"),
            "Trasferisci l'app SielteID prima di disattivare il vecchio telefono."
        ),
        KnownSensitiveAppRule(
            "infocert_id", "InfoCert ID", SensitiveAppRiskKind.SPID_IDENTITY,
            setOf("it.infocert.myinfocert"),
            setOf("infocert"),
            "Configura InfoCert ID sul nuovo dispositivo usando il vecchio per autorizzarlo."
        ),
        // 2FA & Password Manager
        KnownSensitiveAppRule(
            "google_auth", "Google Authenticator", SensitiveAppRiskKind.TWO_FACTOR_AUTH,
            setOf("com.google.android.apps.authenticator2", "com.google.Authenticator", "googleauthenticator"),
            setOf("google authenticator"),
            "Esporta i codici 2FA tramite QR (Menu → Trasferisci account) prima di formattare!"
        ),
        KnownSensitiveAppRule(
            "ms_auth", "Microsoft Authenticator", SensitiveAppRiskKind.TWO_FACTOR_AUTH,
            setOf("com.azure.authenticator", "com.microsoft.azureauthenticator"),
            setOf("microsoft authenticator"),
            "Verifica il Backup Cloud o trasferisci gli account aziendali/personali sul nuovo telefono."
        ),
        KnownSensitiveAppRule(
            "authy", "Twilio Authy", SensitiveAppRiskKind.TWO_FACTOR_AUTH,
            setOf("com.authy.authy"),
            setOf("authy"),
            "Abilita Multi-Device su Authy e verifica i token sul nuovo smartphone."
        ),
        KnownSensitiveAppRule(
            "twofas", "2FAS Auth", SensitiveAppRiskKind.TWO_FACTOR_AUTH,
            setOf("com.twofasapp"),
            setOf("2fas"),
            "Esporta il backup cifrato di 2FAS e importalo sul nuovo telefono."
        ),
        KnownSensitiveAppRule(
            "aegis", "Aegis Authenticator", SensitiveAppRiskKind.TWO_FACTOR_AUTH,
            setOf("com.beemdevelopment.aegis"),
            setOf("aegis"),
            "Esporta il vault cifrato di Aegis prima di formattare il vecchio telefono."
        ),
        KnownSensitiveAppRule(
            "bitwarden", "Bitwarden / 1Password", SensitiveAppRiskKind.TWO_FACTOR_AUTH,
            setOf("com.x8bit.bitwarden", "com.agilebits.onepassword", "com.onepassword.android", "ch.protonpass.android"),
            setOf("bitwarden", "1password", "proton pass"),
            "Verifica l'accesso al gestore password sul nuovo telefono prima di chiudere il vecchio."
        ),
        // Banche & Pagamenti
        KnownSensitiveAppRule(
            "intesa", "Intesa Sanpaolo Mobile", SensitiveAppRiskKind.BANKING_PAYMENTS,
            setOf("com.latuabancaperandroid", "com.intesasanpaolo.mobile"),
            setOf("intesa sanpaolo", "isybank"),
            "Attiva O-Key Smart sul nuovo telefono autorizzandolo dal vecchio dispositivo."
        ),
        KnownSensitiveAppRule(
            "unicredit", "UniCredit Mobile Banking", SensitiveAppRiskKind.BANKING_PAYMENTS,
            setOf("com.unicredit", "it.unicredit.mobile"),
            setOf("unicredit", "buddybank"),
            "Attiva Mobile Token sul nuovo smartphone finché il vecchio è operativo."
        ),
        KnownSensitiveAppRule(
            "fineco", "Fineco", SensitiveAppRiskKind.BANKING_PAYMENTS,
            setOf("com.fineco.it", "it.fineco.mobile"),
            setOf("fineco"),
            "Trasferisci Mobile Code Fineco sul nuovo telefono prima del reset."
        ),
        KnownSensitiveAppRule(
            "postepay", "PostePay / BancoPosta", SensitiveAppRiskKind.BANKING_PAYMENTS,
            setOf("posteitaliane.posteapp.apppostepay", "posteitaliane.posteapp.appbpol", "it.poste.postepay", "it.poste.bancoposta"),
            setOf("postepay", "bancoposta"),
            "Autorizza PostePay/BancoPosta sul nuovo dispositivo prima di resettare il vecchio."
        ),
        KnownSensitiveAppRule(
            "revolut", "Revolut", SensitiveAppRiskKind.BANKING_PAYMENTS,
            setOf("com.revolut.revolut", "revolut"),
            setOf("revolut"),
            "Accedi a Revolut sul nuovo telefono e conferma il dispositivo."
        ),
        KnownSensitiveAppRule(
            "satispay", "Satispay", SensitiveAppRiskKind.BANKING_PAYMENTS,
            setOf("com.satispay.customer", "satispay"),
            setOf("satispay"),
            "Attiva Satispay sul nuovo telefono confermando il codice di sicurezza."
        ),
        KnownSensitiveAppRule(
            "paypal", "PayPal", SensitiveAppRiskKind.BANKING_PAYMENTS,
            setOf("com.paypal.android.p2pmobile", "com.yourcompany.PPClient", "paypal"),
            setOf("paypal"),
            "Accedi a PayPal sul nuovo telefono per spostare le notifiche di conferma."
        ),
        KnownSensitiveAppRule(
            "bper_bpm_ing_bbva", "Home Banking (BPER/BPM/ING/BBVA/N26/Hype)", SensitiveAppRiskKind.BANKING_PAYMENTS,
            setOf(
                "it.bper.smart", "it.bancobpm.youapp", "com.ing.mobile", "it.ingdirect.app",
                "com.bbva.bbvacontigo", "de.number26.android", "it.hype.app", "it.nexi.nexipay",
                "it.mediolanum.android", "it.credem.mobile", "it.illimity.bank", "it.bnl.mobile"
            ),
            setOf("bper", "youapp", "banco bpm", "ing", "bbva", "n26", "hype", "nexi", "mediolanum", "illimity", "credem", "bnl", "widiba", "sella", "mediobanca", "mps", "credit agricole"),
            "Attiva il token bancario sul nuovo telefono prima di formattare il vecchio."
        ),
        // Crypto & eSIM
        KnownSensitiveAppRule(
            "crypto_wallet", "Wallet Crypto (MetaMask/Trust/Coinbase/Ledger)", SensitiveAppRiskKind.CRYPTO_WALLET,
            setOf("io.metamask", "com.wallet.crypto.trustapp", "com.coinbase.android", "com.binance.dev", "com.ledger.live"),
            setOf("metamask", "trust wallet", "coinbase", "binance", "ledger"),
            "Verifica la seed phrase offline e il login del wallet sul nuovo dispositivo!"
        ),
        KnownSensitiveAppRule(
            "esim_carrier", "Operatore / eSIM", SensitiveAppRiskKind.ESIM_CARRIER,
            setOf("it.telecomitalia.mytim", "it.vodafone.my190", "it.windtre.app", "it.iliad.android", "it.fastweb.myfastweb", "com.mobillium.airalo"),
            setOf("mytim", "myvodafone", "windtre", "very mobile", "ho. mobile", "airalo"),
            "Se usi una eSIM, ricorda di trasferirla o scaricare il nuovo QR prima di resettare il telefono."
        )
    )

    fun classifyApp(app: InstalledAppRecord): Pair<String, SensitiveAppRiskKind>? {
        val pkgLower = app.packageName.trim().lowercase(Locale.ROOT)
        val schemeLower = app.urlScheme?.trim()?.lowercase(Locale.ROOT).orEmpty()
        val nameLower = app.appName.trim().lowercase(Locale.ROOT)

        for (rule in rules) {
            if (pkgLower in rule.identifiers || (schemeLower.isNotEmpty() && schemeLower in rule.identifiers)) {
                return rule.canonicalId to rule.riskKind
            }
            if (rule.nameKeywords.any { kw -> nameLower.contains(kw) }) {
                return rule.canonicalId to rule.riskKind
            }
        }
        return null
    }

    fun guidanceForCanonical(canonicalId: String, fallbackKind: SensitiveAppRiskKind): String {
        return rules.firstOrNull { it.canonicalId == canonicalId }?.guidance ?: when (fallbackKind) {
            SensitiveAppRiskKind.SPID_IDENTITY -> "Attiva l'identità digitale sul nuovo telefono prima del reset."
            SensitiveAppRiskKind.TWO_FACTOR_AUTH -> "Trasferisci tutti i codici 2FA prima di formattare il vecchio telefono."
            SensitiveAppRiskKind.BANKING_PAYMENTS -> "Attiva il token bancario sul nuovo dispositivo finché hai il vecchio acceso."
            SensitiveAppRiskKind.CRYPTO_WALLET -> "Verifica la frase di recupero del wallet prima di cancellare il dispositivo."
            SensitiveAppRiskKind.ESIM_CARRIER -> "Verifica il trasferimento della eSIM prima del ripristino di fabbrica."
        }
    }

    fun resolveCanonicalKeys(appIds: List<String>, appNames: List<String> = emptyList()): Set<String> {
        val out = HashSet<String>()
        for (rawId in appIds) {
            val low = rawId.trim().lowercase(Locale.ROOT)
            if (low.isEmpty()) continue
            out.add(low)
            for (rule in rules) {
                if (low in rule.identifiers || rule.identifiers.any { it.lowercase(Locale.ROOT) == low }) {
                    out.add(rule.canonicalId)
                }
            }
        }
        for (rawName in appNames) {
            val low = rawName.trim().lowercase(Locale.ROOT)
            if (low.isEmpty()) continue
            for (rule in rules) {
                if (rule.nameKeywords.any { low.contains(it) }) {
                    out.add(rule.canonicalId)
                }
            }
        }
        return out
    }
}

object DecommissionReadinessEvaluator {
    fun evaluate(
        sessionId: String,
        peerName: String,
        peerPlatform: DevicePlatform,
        senderInstalledApps: List<InstalledAppRecord>,
        receiverInstalledAppIds: List<String>?,
        receiverInstalledAppNames: List<String> = emptyList(),
        localOnlyContactsCount: Int,
        contactsWereMigrated: Boolean,
        icloudPhantomMediaCount: Int = 0,
        unresolvedSkippedItemsCount: Int = 0,
        completedFilesCount: Int = 0,
        transferredBytes: Long = 0L,
        acknowledgedAppIds: Set<String> = emptySet(),
        nowEpochMillis: Long = System.currentTimeMillis()
    ): DecommissionAuditReport {
        val hasLiveReceiverList = receiverInstalledAppIds != null
        val receiverCanonical = SensitiveAppRiskClassifier.resolveCanonicalKeys(
            appIds = receiverInstalledAppIds.orEmpty(),
            appNames = receiverInstalledAppNames
        )

        val missing = mutableListOf<SensitiveAppAuditItem>()
        val verified = mutableListOf<SensitiveAppAuditItem>()
        val seenCanonical = HashSet<String>()

        for (app in senderInstalledApps) {
            val classified = SensitiveAppRiskClassifier.classifyApp(app) ?: continue
            val (canonical, kind) = classified
            val uniqueKey = "$canonical:${app.packageName.lowercase(Locale.ROOT)}"
            if (!seenCanonical.add(canonical) && kind != SensitiveAppRiskKind.BANKING_PAYMENTS) continue
            if (!seenCanonical.add(uniqueKey)) continue

            val onReceiver = hasLiveReceiverList && (
                canonical in receiverCanonical ||
                    app.packageName.lowercase(Locale.ROOT) in receiverCanonical
                )
            val isVerifiedOrAck = onReceiver || canonical in acknowledgedAppIds
            val item = SensitiveAppAuditItem(
                canonicalId = canonical,
                appName = app.appName,
                riskKind = kind,
                isPresentOnReceiver = isVerifiedOrAck,
                guidance = SensitiveAppRiskClassifier.guidanceForCanonical(canonical, kind)
            )
            if (isVerifiedOrAck) verified.add(item) else missing.add(item)
        }

        val hasUnmigratedLocalContacts = localOnlyContactsCount > 0 && !contactsWereMigrated
        val level = when {
            missing.isNotEmpty() -> DecommissionReadinessLevel.BLOCKED_RED
            hasUnmigratedLocalContacts || icloudPhantomMediaCount > 0 || unresolvedSkippedItemsCount > 0 ->
                DecommissionReadinessLevel.CAUTION_AMBER
            else -> DecommissionReadinessLevel.READY_FOR_RESET_GREEN
        }

        val digestInput = listOf(
            sessionId,
            peerName,
            peerPlatform.name,
            completedFilesCount.toString(),
            transferredBytes.toString(),
            missing.size.toString(),
            verified.size.toString(),
            localOnlyContactsCount.toString(),
            icloudPhantomMediaCount.toString(),
            level.name,
            (nowEpochMillis / 1000L).toString()
        ).joinToString("|")
        val certHash = DirectSwitchCrypto.toHexLower(
            MessageDigest.getInstance("SHA-256").digest(digestInput.toByteArray(Charsets.UTF_8))
        )

        return DecommissionAuditReport(
            sessionId = sessionId,
            peerName = peerName,
            peerPlatform = peerPlatform,
            checkedWithLiveReceiver = hasLiveReceiverList,
            missingCriticalApps = missing,
            verifiedCriticalApps = verified,
            localOnlyContactsCount = localOnlyContactsCount,
            contactsWereMigrated = contactsWereMigrated,
            icloudPhantomMediaCount = icloudPhantomMediaCount,
            unresolvedSkippedItemsCount = unresolvedSkippedItemsCount,
            readinessLevel = level,
            completedFilesCount = completedFilesCount,
            transferredBytes = transferredBytes,
            certificateSha256 = certHash,
            generatedAtEpochMillis = nowEpochMillis
        )
    }

    fun buildResetCertificateText(report: DecommissionAuditReport, senderDeviceName: String): String {
        val df = SimpleDateFormat("dd/MM/yyyy HH:mm", Locale.ITALY)
        val statusText = when (report.readinessLevel) {
            DecommissionReadinessLevel.READY_FOR_RESET_GREEN -> "PRONTO PER RESET / PERMUTA ✓"
            DecommissionReadinessLevel.CAUTION_AMBER -> "ATTENZIONE — VERIFICA ELEMENTI SECONDARI"
            DecommissionReadinessLevel.BLOCKED_RED -> "NON FORMATTARE — APP CRITICHE MANCANTI"
        }
        return buildString {
            appendLine("DirectSwitch — Certificato Audit Pre-Reset")
            appendLine("Stato: $statusText")
            appendLine("Data: ${df.format(Date(report.generatedAtEpochMillis))}")
            appendLine("Vecchio dispositivo: $senderDeviceName")
            appendLine("Nuovo dispositivo: ${report.peerName} (${report.peerPlatform.name})")
            appendLine("----------------------------------------")
            appendLine("File migrati: ${report.completedFilesCount} (${TransferDisplayFormatting.formatBytes(report.transferredBytes)})")
            appendLine("App critiche verificate sul nuovo telefono: ${report.verifiedCriticalApps.size}")
            appendLine("App critiche ancora mancanti: ${report.missingCriticalApps.size}")
            if (report.missingCriticalApps.isNotEmpty()) {
                report.missingCriticalApps.forEach { app ->
                    appendLine("  [!] ${app.appName} (${app.riskKind.displayLabel})")
                }
            }
            if (report.localOnlyContactsCount > 0) {
                appendLine("Contatti solo-SIM / locali rilevati: ${report.localOnlyContactsCount} (${if (report.contactsWereMigrated) "migrati ✓" else "NON ancora migrati"})")
            }
            if (report.icloudPhantomMediaCount > 0) {
                appendLine("Media solo-cloud (non scaricati offline): ${report.icloudPhantomMediaCount}")
            }
            appendLine("Elementi saltati non risolti: ${report.unresolvedSkippedItemsCount}")
            appendLine("----------------------------------------")
            append("Impronta SHA-256 Audit: ${report.certificateSha256.take(24).uppercase(Locale.US)}")
        }
    }
}

// ============================================================================
// 5. OVERFLOW BRIDGE DIRECTSWITCH -> CLOUDSAVE
// ============================================================================

@Serializable
data class DirectSwitchOverflowItemRecord(
    val id: String,
    val category: TransferCategory,
    val fileName: String,
    val album: String = "",
    val sizeBytes: Long,
    val capturedEpochMillis: Long = 0L,
    val contentUri: String = ""
)

@Serializable
data class DirectSwitchOverflowHandoffManifest(
    val version: Int = 1,
    val createdAtEpochMillis: Long,
    val sourceDeviceName: String,
    val targetDeviceName: String,
    val cutoffEpochMillis: Long,
    val maxVideoBytes: Long = 0L,
    val totalOverflowCount: Int,
    val totalOverflowBytes: Long,
    val items: List<DirectSwitchOverflowItemRecord>
)

data class OverflowSplitPlan(
    val directItems: List<ManifestItem>,
    val overflowItems: List<ManifestItem>,
    val cutoffEpochMillis: Long,
    val maxVideoBytes: Long,
    val directTotalBytes: Long,
    val overflowTotalBytes: Long,
    val fitsAvailableSpace: Boolean
)

object OverflowBridgePlanner {
    fun buildSplitPlan(
        availableFreeBytes: Long,
        items: List<ManifestItem>,
        nowEpochMillis: Long = System.currentTimeMillis()
    ): OverflowSplitPlan {
        val usableFree = (availableFreeBytes - SpaceReliefPlanner.safetyMarginBytes()).coerceAtLeast(0L)
        val oneYearCutoff = nowEpochMillis - 365L * 86_400_000L

        val olderMedia = items.filter {
            (it.category == TransferCategory.PHOTOS || it.category == TransferCategory.VIDEOS) &&
                it.capturedEpochMillis > 0L && it.capturedEpochMillis < oneYearCutoff
        }
        val (overflow, cutoff, maxVid) = if (olderMedia.isNotEmpty()) {
            Triple(olderMedia, oneYearCutoff, 0L)
        } else {
            val heavy = items.filter {
                it.category == TransferCategory.VIDEOS && it.sizeBytes > SpaceReliefPlanner.HEAVY_VIDEO_THRESHOLD_BYTES
            }
            Triple(heavy, 0L, SpaceReliefPlanner.HEAVY_VIDEO_THRESHOLD_BYTES)
        }

        val overflowIds = overflow.map { it.id }.toHashSet()
        val direct = items.filterNot { it.id in overflowIds }
        val directBytes = direct.sumOf { it.sizeBytes.coerceAtLeast(0L) }
        val overflowBytes = overflow.sumOf { it.sizeBytes.coerceAtLeast(0L) }
        return OverflowSplitPlan(
            directItems = direct,
            overflowItems = overflow,
            cutoffEpochMillis = cutoff,
            maxVideoBytes = maxVid,
            directTotalBytes = directBytes,
            overflowTotalBytes = overflowBytes,
            fitsAvailableSpace = directBytes <= usableFree
        )
    }

    private fun SpaceReliefPlanner.safetyMarginBytes(): Long = 250L * 1024L * 1024L
}
