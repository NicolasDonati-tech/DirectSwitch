//
//  DirectSwitchAdvancedAndroidBridge.kt
//  DirectSwitch-Android
//
//  Created by Nicolas Donati.
//  Copyright © 2026 Nicolas Donati. Tutti i diritti riservati.
//

package com.directswitch.android.migrators

import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.ImageDecoder
import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMuxer
import android.net.Uri
import android.os.BatteryManager
import android.os.Build
import androidx.exifinterface.media.ExifInterface
import com.directswitch.android.DirectSwitchLog
import com.directswitch.android.protocol.CrossOsCodecCompatibilityHelper
import com.directswitch.android.protocol.DirectSwitchMotionPhotoCodec
import com.directswitch.android.protocol.MediaTimelineHealer
import com.directswitch.android.protocol.SharedBitmapDecodeGate
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.nio.ByteBuffer
import java.util.Locale

data class BatterySnapshot(
    val percent: Int,
    val isCharging: Boolean,
    val recommendsAutoTriage: Boolean
)

object AndroidBatteryTriageMonitor {
    fun readSnapshot(context: Context): BatterySnapshot {
        return runCatching {
            val intent = context.registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
            val level = intent?.getIntExtra(BatteryManager.EXTRA_LEVEL, -1) ?: -1
            val scale = intent?.getIntExtra(BatteryManager.EXTRA_SCALE, 100) ?: 100
            val status = intent?.getIntExtra(BatteryManager.EXTRA_STATUS, -1) ?: -1
            val pct = if (level >= 0 && scale > 0) ((level * 100) / scale).coerceIn(0, 100) else 100
            val charging = status == BatteryManager.BATTERY_STATUS_CHARGING ||
                status == BatteryManager.BATTERY_STATUS_FULL
            BatterySnapshot(
                percent = pct,
                isCharging = charging,
                recommendsAutoTriage = com.directswitch.android.protocol.BatteryTriagePlanner.shouldAutoActivate(pct, charging)
            )
        }.getOrElse {
            BatterySnapshot(percent = 100, isCharging = true, recommendsAutoTriage = false)
        }
    }
}

object AndroidTimelineExifInjector {
    private val exifSupportedExts = setOf("jpg", "jpeg", "png", "webp", "heic", "heif")

    /**
     * Inietta `DateTimeOriginal` / `DateTimeDigitized` / `DateTime` (e GPS opzionale) se assenti o ricostruiti
     * dal nome file, preservando così l'ordine cronologico reale nella Galleria.
     */
    fun injectCaptureMetadataIfNeeded(
        mediaFile: File,
        fileName: String,
        targetEpochMillis: Long,
        forceOverwriteDate: Boolean = false,
        latitude: Double? = null,
        longitude: Double? = null
    ): Boolean {
        if (targetEpochMillis <= 0L || !mediaFile.exists() || !mediaFile.isFile) return false
        val ext = File(fileName).extension.lowercase(Locale.ROOT)
        if (ext !in exifSupportedExts) return false
        return runCatching {
            val exif = ExifInterface(mediaFile.absolutePath)
            var dirty = false
            val existingOrig = exif.getAttribute(ExifInterface.TAG_DATETIME_ORIGINAL)?.trim().orEmpty()
            if (forceOverwriteDate || existingOrig.isEmpty()) {
                val formatted = MediaTimelineHealer.formatExifDateTime(targetEpochMillis)
                exif.setAttribute(ExifInterface.TAG_DATETIME_ORIGINAL, formatted)
                exif.setAttribute(ExifInterface.TAG_DATETIME_DIGITIZED, formatted)
                exif.setAttribute(ExifInterface.TAG_DATETIME, formatted)
                dirty = true
            }
            if (latitude != null && longitude != null && (latitude != 0.0 || longitude != 0.0)) {
                val existingLatLong = exif.latLong
                if (existingLatLong == null) {
                    exif.setLatLong(latitude, longitude)
                    dirty = true
                }
            }
            if (dirty) {
                exif.saveAttributes()
            }
            dirty
        }.getOrDefault(false)
    }
}

/**
 * Converte al volo file audio non supportati nativamente da iOS (`.opus`, `.ogg`, `.amr`, `.3gp`) in `.m4a` AAC-LC
 * tramite `MediaExtractor` + `MediaCodec` + `MediaMuxer` senza dipendenze esterne.
 */
object AndroidAudioCodecHealer {
    private const val TIMEOUT_US = 10_000L
    private const val MAX_TRANSCODE_SOURCE_BYTES = 40L * 1024L * 1024L

    fun transcodeAudioToM4aIfNeeded(
        context: Context,
        sourceUri: Uri,
        fileName: String,
        mimeType: String,
        sizeBytes: Long
    ): File? {
        if (!CrossOsCodecCompatibilityHelper.needsAudioTranscodeForIos(fileName, mimeType)) return null
        if (sizeBytes <= 0L || sizeBytes > MAX_TRANSCODE_SOURCE_BYTES) return null

        val tempSrc = File(context.cacheDir, "aud_src_${System.nanoTime()}.${File(fileName).extension.ifBlank { "bin" }}")
        val tempOut = File(context.cacheDir, "aud_healed_${System.nanoTime()}.m4a")
        return try {
            com.directswitch.android.protocol.openMediaOriginalInputStream(context, sourceUri)?.use { inp ->
                tempSrc.outputStream().use { out -> inp.copyTo(out) }
            } ?: return null
            if (!tempSrc.exists() || tempSrc.length() <= 0L) return null
            val ok = transcodeFileToAacM4a(tempSrc, tempOut)
            if (ok && tempOut.exists() && tempOut.length() > 128L) {
                tempOut
            } else {
                tempOut.delete()
                null
            }
        } catch (t: Throwable) {
            DirectSwitchLog.warn("Transcodifica audio compatibile iOS saltata per $fileName", t)
            tempOut.delete()
            null
        } finally {
            tempSrc.delete()
        }
    }

    private fun transcodeFileToAacM4a(srcFile: File, destM4a: File): Boolean {
        val extractor = MediaExtractor()
        var decoder: MediaCodec? = null
        var encoder: MediaCodec? = null
        var muxer: MediaMuxer? = null
        var muxerStarted = false
        try {
            extractor.setDataSource(srcFile.absolutePath)
            var audioTrack = -1
            var inputFormat: MediaFormat? = null
            for (i in 0 until extractor.trackCount) {
                val fmt = extractor.getTrackFormat(i)
                val mime = fmt.getString(MediaFormat.KEY_MIME).orEmpty()
                if (mime.startsWith("audio/")) {
                    audioTrack = i
                    inputFormat = fmt
                    break
                }
            }
            if (audioTrack < 0 || inputFormat == null) return false
            val inMime = inputFormat.getString(MediaFormat.KEY_MIME) ?: return false
            extractor.selectTrack(audioTrack)

            val sampleRate = runCatching { inputFormat.getInteger(MediaFormat.KEY_SAMPLE_RATE) }.getOrDefault(44100).coerceIn(8000, 48000)
            val channelCount = runCatching { inputFormat.getInteger(MediaFormat.KEY_CHANNEL_COUNT) }.getOrDefault(1).coerceIn(1, 2)

            decoder = MediaCodec.createDecoderByType(inMime)
            decoder.configure(inputFormat, null, null, 0)
            decoder.start()

            val encFormat = MediaFormat.createAudioFormat(MediaFormat.MIMETYPE_AUDIO_AAC, sampleRate, channelCount).apply {
                setInteger(MediaFormat.KEY_AAC_PROFILE, MediaCodecInfo.CodecProfileLevel.AACObjectLC)
                setInteger(MediaFormat.KEY_BIT_RATE, if (channelCount > 1) 128_000 else 96_000)
                setInteger(MediaFormat.KEY_MAX_INPUT_SIZE, 16 * 1024)
            }
            val aacEncoder = MediaCodec.createEncoderByType(MediaFormat.MIMETYPE_AUDIO_AAC)
            encoder = aacEncoder
            aacEncoder.configure(encFormat, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
            aacEncoder.start()

            val mp4Muxer = MediaMuxer(destM4a.absolutePath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
            muxer = mp4Muxer
            var muxTrackIdx = -1

            val decInfo = MediaCodec.BufferInfo()
            val encInfo = MediaCodec.BufferInfo()
            var extractorDone = false
            var decoderDone = false
            var encoderDone = false
            val deadlineMs = System.currentTimeMillis() + 30_000L

            fun drainEncoderOutput(initialTimeoutUs: Long) {
                var timeoutUs = initialTimeoutUs
                while (!encoderDone && System.currentTimeMillis() < deadlineMs) {
                    val encOutIdx = aacEncoder.dequeueOutputBuffer(encInfo, timeoutUs)
                    timeoutUs = 0L
                    when {
                        encOutIdx == MediaCodec.INFO_TRY_AGAIN_LATER -> break
                        encOutIdx == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                            if (!muxerStarted) {
                                muxTrackIdx = mp4Muxer.addTrack(aacEncoder.outputFormat)
                                mp4Muxer.start()
                                muxerStarted = true
                            }
                        }
                        encOutIdx >= 0 -> {
                            val encoded = aacEncoder.getOutputBuffer(encOutIdx)
                            if (encoded != null && encInfo.size > 0 && muxerStarted &&
                                (encInfo.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG) == 0
                            ) {
                                encoded.position(encInfo.offset)
                                encoded.limit(encInfo.offset + encInfo.size)
                                mp4Muxer.writeSampleData(muxTrackIdx, encoded, encInfo)
                            }
                            aacEncoder.releaseOutputBuffer(encOutIdx, false)
                            if ((encInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0) {
                                encoderDone = true
                                break
                            }
                        }
                    }
                }
            }

            while (!encoderDone && System.currentTimeMillis() < deadlineMs) {
                if (!extractorDone) {
                    val inIdx = decoder.dequeueInputBuffer(TIMEOUT_US)
                    if (inIdx >= 0) {
                        val buf = decoder.getInputBuffer(inIdx)
                        if (buf != null) {
                            val read = extractor.readSampleData(buf, 0)
                            if (read < 0) {
                                decoder.queueInputBuffer(inIdx, 0, 0, 0L, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                                extractorDone = true
                            } else {
                                decoder.queueInputBuffer(inIdx, 0, read, extractor.sampleTime.coerceAtLeast(0L), 0)
                                extractor.advance()
                            }
                        }
                    }
                }

                if (!decoderDone) {
                    val decOutIdx = decoder.dequeueOutputBuffer(decInfo, TIMEOUT_US)
                    if (decOutIdx >= 0) {
                        val pcmBuf = decoder.getOutputBuffer(decOutIdx)
                        val isEos = (decInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0
                        if (pcmBuf != null && decInfo.size > 0) {
                            pcmBuf.position(decInfo.offset)
                            pcmBuf.limit(decInfo.offset + decInfo.size)
                            val pcmCopy = ByteArray(decInfo.size)
                            pcmBuf.get(pcmCopy)
                            var offset = 0
                            while (offset < pcmCopy.size && !encoderDone && System.currentTimeMillis() < deadlineMs) {
                                val encInIdx = aacEncoder.dequeueInputBuffer(TIMEOUT_US)
                                if (encInIdx >= 0) {
                                    val encBuf = aacEncoder.getInputBuffer(encInIdx) ?: break
                                    encBuf.clear()
                                    val toWrite = minOf(encBuf.remaining(), pcmCopy.size - offset)
                                    encBuf.put(pcmCopy, offset, toWrite)
                                    aacEncoder.queueInputBuffer(encInIdx, 0, toWrite, decInfo.presentationTimeUs, 0)
                                    offset += toWrite
                                }
                                // Drena sempre l'output dell'encoder per evitare deadlock quando il buffer AAC si riempie
                                drainEncoderOutput(0L)
                            }
                        }
                        decoder.releaseOutputBuffer(decOutIdx, false)
                        if (isEos) {
                            decoderDone = true
                            var eosQueued = false
                            while (!eosQueued && !encoderDone && System.currentTimeMillis() < deadlineMs) {
                                val encInIdx = aacEncoder.dequeueInputBuffer(TIMEOUT_US)
                                if (encInIdx >= 0) {
                                    aacEncoder.queueInputBuffer(
                                        encInIdx,
                                        0,
                                        0,
                                        decInfo.presentationTimeUs,
                                        MediaCodec.BUFFER_FLAG_END_OF_STREAM
                                    )
                                    eosQueued = true
                                } else {
                                    drainEncoderOutput(TIMEOUT_US)
                                }
                            }
                        }
                    }
                }

                drainEncoderOutput(TIMEOUT_US)
            }
            return muxerStarted && encoderDone
        } finally {
            runCatching { extractor.release() }
            runCatching { decoder?.stop(); decoder?.release() }
            runCatching { encoder?.stop(); encoder?.release() }
            runCatching { if (muxerStarted) muxer?.stop(); muxer?.release() }
        }
    }
}

/**
 * Ponte Android per Live Photo (iOS) <-> Motion Photo (Android) su DirectSwitch:
 * - Ricevendo still + clip `.mov` da iOS: converte lo still in JPEG se HEIC, rimuxa `.mov` -> `.mp4`
 *   e assembla una Motion Photo JPEG nativa Google Foto / Samsung Galleria.
 * - Inviando una Motion Photo Android verso iOS: esegue prima un probe a zero scritture su disco
 *   (header 256 KB + coda 64 KB via FileChannel) e copia in cache solo le vere Motion Photo.
 */
object AndroidLiveMotionBridge {
    data class ExtractedAndroidMotionPhoto(
        val stillFile: File,
        val videoMp4File: File,
        val stillExtension: String
    )

    private fun isLikelyMotionPhotoUri(context: Context, sourceUri: Uri, reportedSizeBytes: Long): Boolean {
        val pfdResult = runCatching {
            context.contentResolver.openFileDescriptor(sourceUri, "r")?.use { pfd ->
                FileInputStream(pfd.fileDescriptor).use { fis ->
                    val channel = fis.channel
                    val fileSize = runCatching { channel.size() }.getOrDefault(reportedSizeBytes)
                    if (fileSize < 4096L || fileSize > 120L * 1024L * 1024L) return@use false

                    val headLen = minOf(fileSize, 256L * 1024L).toInt()
                    val headBuf = ByteBuffer.allocate(headLen)
                    var headRead = 0
                    while (headRead < headLen) {
                        val n = channel.read(headBuf)
                        if (n <= 0) break
                        headRead += n
                    }
                    val headBytes = headBuf.array()
                    if (DirectSwitchMotionPhotoCodec.looksLikeMotionPhotoHeaderBytes(headBytes, headRead)) {
                        return@use true
                    }

                    // Samsung Motion Photo salva il trailer SEFT/MotionPhoto_Data negli ultimi 64 KB del JPEG
                    val isJpeg = headRead >= 2 && headBytes[0] == 0xFF.toByte() && headBytes[1] == 0xD8.toByte()
                    if (isJpeg && fileSize > headLen.toLong()) {
                        val tailLen = minOf(fileSize, 64L * 1024L).toInt()
                        val tailStart = (fileSize - tailLen.toLong()).coerceAtLeast(0L)
                        val tailBuf = ByteBuffer.allocate(tailLen)
                        var tailRead = 0
                        var pos = tailStart
                        while (tailRead < tailLen) {
                            val n = channel.read(tailBuf, pos)
                            if (n <= 0) break
                            tailRead += n
                            pos += n.toLong()
                        }
                        if (DirectSwitchMotionPhotoCodec.looksLikeMotionPhotoTailBytes(tailBuf.array(), tailRead)) {
                            return@use true
                        }
                    }
                    false
                }
            }
        }.getOrNull()

        if (pfdResult != null) return pfdResult

        // Fallback streaming senza FileDescriptor seekable: legge solo i primi 256 KB
        return runCatching {
            context.contentResolver.openInputStream(sourceUri)?.use { inp ->
                val head = ByteArray(256 * 1024)
                var total = 0
                while (total < head.size) {
                    val n = inp.read(head, total, head.size - total)
                    if (n <= 0) break
                    total += n
                }
                DirectSwitchMotionPhotoCodec.looksLikeMotionPhotoHeaderBytes(head, total)
            } ?: false
        }.getOrDefault(false)
    }

    fun tryExtractAndroidMotionPhoto(
        context: Context,
        sourceUri: Uri,
        fileName: String,
        sizeBytes: Long
    ): ExtractedAndroidMotionPhoto? {
        val ext = File(fileName).extension.lowercase(Locale.ROOT)
        if (ext !in setOf("jpg", "jpeg", "heic", "heif")) return null
        if (sizeBytes < 4096L || sizeBytes > 120L * 1024L * 1024L) return null

        // Probe leggero a ZERO scritture su flash: evita di copiare ogni foto statica in cacheDir!
        if (!isLikelyMotionPhotoUri(context, sourceUri, sizeBytes)) return null

        val tempSrc = File(context.cacheDir, "mp_probe_${System.nanoTime()}.$ext")
        val outStill = File(context.cacheDir, "mp_still_${System.nanoTime()}.$ext")
        val outVideo = File(context.cacheDir, "mp_clip_${System.nanoTime()}.mp4")
        return try {
            com.directswitch.android.protocol.openMediaOriginalInputStream(context, sourceUri)?.use { inp ->
                tempSrc.outputStream().use { out -> inp.copyTo(out) }
            } ?: return null
            if (!DirectSwitchMotionPhotoCodec.looksLikeMotionPhotoCandidateQuick(tempSrc)) return null
            val parsed = DirectSwitchMotionPhotoCodec.parseMotionPhotoFile(tempSrc, outStill, outVideo)
            if (parsed != null && outStill.exists() && outStill.length() > 128L && outVideo.exists() && outVideo.length() > 1024L) {
                ExtractedAndroidMotionPhoto(outStill, outVideo, parsed.stillExtension)
            } else {
                outStill.delete()
                outVideo.delete()
                null
            }
        } catch (_: Throwable) {
            outStill.delete()
            outVideo.delete()
            null
        } finally {
            tempSrc.delete()
        }
    }

    fun assembleIncomingIosLivePhotoToMotionJpeg(
        context: Context,
        stillFile: File,
        stillFileName: String,
        liveVideoFile: File,
        outMotionJpegFile: File
    ): Boolean {
        val tempJpeg = File(context.cacheDir, "live_still_conv_${System.nanoTime()}.jpg")
        val tempMp4 = File(context.cacheDir, "live_clip_conv_${System.nanoTime()}.mp4")
        return try {
            val jpegSource = if (isJpegFile(stillFile)) {
                stillFile
            } else {
                if (!convertImageToJpegWithExif(stillFile, tempJpeg)) return false
                tempJpeg
            }
            val mp4Source = if (remuxVideoToMp4(liveVideoFile, tempMp4)) {
                tempMp4
            } else if (File(liveVideoFile.name).extension.equals("mp4", ignoreCase = true)) {
                liveVideoFile
            } else {
                return false
            }
            DirectSwitchMotionPhotoCodec.buildMotionPhotoJpegToFile(
                stillJpegFile = jpegSource,
                mp4File = mp4Source,
                presentationTimestampUs = 0L,
                outMotionJpegFile = outMotionJpegFile
            )
            outMotionJpegFile.exists() && outMotionJpegFile.length() > jpegSource.length()
        } catch (t: Throwable) {
            DirectSwitchLog.warn("Assemblaggio Motion Photo fallito per $stillFileName", t)
            outMotionJpegFile.delete()
            false
        } finally {
            tempJpeg.delete()
            tempMp4.delete()
        }
    }

    private fun isJpegFile(file: File): Boolean = runCatching {
        file.inputStream().use { inp ->
            val b0 = inp.read()
            val b1 = inp.read()
            b0 == 0xFF && b1 == 0xD8
        }
    }.getOrDefault(false)

    private fun convertImageToJpegWithExif(src: File, dstJpeg: File): Boolean {
        val compressedOk = synchronized(SharedBitmapDecodeGate.lock) {
            val bmp: Bitmap = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                runCatching {
                    ImageDecoder.decodeBitmap(ImageDecoder.createSource(src)) { decoder, _, _ ->
                        decoder.allocator = ImageDecoder.ALLOCATOR_SOFTWARE
                    }
                }.getOrNull()
            } else {
                null
            } ?: BitmapFactory.decodeFile(src.absolutePath) ?: return false

            try {
                FileOutputStream(dstJpeg).use { fos ->
                    bmp.compress(Bitmap.CompressFormat.JPEG, 94, fos)
                }
            } finally {
                bmp.recycle()
            }
        }
        if (!compressedOk) return false

        runCatching {
            val srcExif = ExifInterface(src.absolutePath)
            val dstExif = ExifInterface(dstJpeg.absolutePath)
            listOf(
                ExifInterface.TAG_DATETIME_ORIGINAL,
                ExifInterface.TAG_DATETIME_DIGITIZED,
                ExifInterface.TAG_DATETIME,
                ExifInterface.TAG_MAKE,
                ExifInterface.TAG_MODEL,
                ExifInterface.TAG_GPS_LATITUDE,
                ExifInterface.TAG_GPS_LATITUDE_REF,
                ExifInterface.TAG_GPS_LONGITUDE,
                ExifInterface.TAG_GPS_LONGITUDE_REF
            ).forEach { tag ->
                srcExif.getAttribute(tag)?.let { dstExif.setAttribute(tag, it) }
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                dstExif.setAttribute(ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_NORMAL.toString())
            }
            dstExif.saveAttributes()
        }
        return dstJpeg.exists() && dstJpeg.length() > 128L
    }

    private fun remuxVideoToMp4(srcVideo: File, dstMp4: File): Boolean {
        val extractor = MediaExtractor()
        var muxer: MediaMuxer? = null
        var started = false
        return try {
            extractor.setDataSource(srcVideo.absolutePath)
            muxer = MediaMuxer(dstMp4.absolutePath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
            val trackMap = HashMap<Int, Int>()
            for (i in 0 until extractor.trackCount) {
                val fmt = extractor.getTrackFormat(i)
                val mime = fmt.getString(MediaFormat.KEY_MIME).orEmpty()
                if (mime.startsWith("video/") || mime.startsWith("audio/")) {
                    val outIdx = runCatching { muxer.addTrack(fmt) }.getOrNull()
                    if (outIdx != null) {
                        trackMap[i] = outIdx
                        extractor.selectTrack(i)
                    }
                }
            }
            if (trackMap.isEmpty()) return false
            muxer.start()
            started = true

            val buf = ByteBuffer.allocate(1024 * 1024)
            val info = MediaCodec.BufferInfo()
            while (true) {
                val srcTrack = extractor.sampleTrackIndex
                if (srcTrack < 0) break
                val dstTrack = trackMap[srcTrack]
                val read = extractor.readSampleData(buf, 0)
                if (read < 0) break
                if (dstTrack != null) {
                    info.offset = 0
                    info.size = read
                    info.presentationTimeUs = extractor.sampleTime.coerceAtLeast(0L)
                    val sampleFlags = extractor.sampleFlags
                    var bufferFlags = 0
                    if ((sampleFlags and MediaExtractor.SAMPLE_FLAG_SYNC) != 0) {
                        bufferFlags = bufferFlags or MediaCodec.BUFFER_FLAG_KEY_FRAME
                    }
                    if ((sampleFlags and MediaExtractor.SAMPLE_FLAG_PARTIAL_FRAME) != 0) {
                        bufferFlags = bufferFlags or MediaCodec.BUFFER_FLAG_PARTIAL_FRAME
                    }
                    info.flags = bufferFlags
                    muxer.writeSampleData(dstTrack, buf, info)
                }
                extractor.advance()
            }
            started = false
            muxer.stop()
            dstMp4.exists() && dstMp4.length() > 1024L
        } catch (_: Throwable) {
            dstMp4.delete()
            false
        } finally {
            runCatching { extractor.release() }
            runCatching { if (started) muxer?.stop() }
            runCatching { muxer?.release() }
        }
    }
}
