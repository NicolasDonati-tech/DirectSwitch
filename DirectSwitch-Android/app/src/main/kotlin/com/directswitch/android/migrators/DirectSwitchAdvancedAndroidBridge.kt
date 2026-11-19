//
//  DirectSwitchAdvancedAndroidBridge.kt
//  DirectSwitch-Android
//
//  Created by Nicolas Donati.
//  Copyright © 2026 Nicolas Donati. Tutti i diritti riservati.
//

package com.directswitch.android.migrators

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
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
import android.provider.ContactsContract
import android.provider.Settings
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import androidx.exifinterface.media.ExifInterface
import com.directswitch.android.DirectSwitchLog
import com.directswitch.android.protocol.CrossOsCodecCompatibilityHelper
import com.directswitch.android.protocol.DirectSwitchJson
import com.directswitch.android.protocol.DirectSwitchMotionPhotoCodec
import com.directswitch.android.protocol.DirectSwitchOverflowHandoffManifest
import com.directswitch.android.protocol.DirectSwitchOverflowItemRecord
import com.directswitch.android.protocol.MediaTimelineHealer
import com.directswitch.android.protocol.OverflowSplitPlan
import kotlinx.serialization.encodeToString
import java.io.File
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
            context.contentResolver.openInputStream(sourceUri)?.use { inp ->
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
            encoder = MediaCodec.createEncoderByType(MediaFormat.MIMETYPE_AUDIO_AAC)
            encoder.configure(encFormat, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
            encoder.start()

            muxer = MediaMuxer(destM4a.absolutePath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
            var muxTrackIdx = -1

            val decInfo = MediaCodec.BufferInfo()
            val encInfo = MediaCodec.BufferInfo()
            var extractorDone = false
            var decoderDone = false
            var encoderDone = false
            val deadlineMs = System.currentTimeMillis() + 30_000L

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
                            while (offset < pcmCopy.size) {
                                val encInIdx = encoder.dequeueInputBuffer(TIMEOUT_US)
                                if (encInIdx >= 0) {
                                    val encBuf = encoder.getInputBuffer(encInIdx) ?: break
                                    encBuf.clear()
                                    val toWrite = minOf(encBuf.remaining(), pcmCopy.size - offset)
                                    encBuf.put(pcmCopy, offset, toWrite)
                                    encoder.queueInputBuffer(encInIdx, 0, toWrite, decInfo.presentationTimeUs, 0)
                                    offset += toWrite
                                }
                            }
                        }
                        decoder.releaseOutputBuffer(decOutIdx, false)
                        if (isEos) {
                            decoderDone = true
                            val encInIdx = encoder.dequeueInputBuffer(TIMEOUT_US * 5)
                            if (encInIdx >= 0) {
                                encoder.queueInputBuffer(encInIdx, 0, 0, decInfo.presentationTimeUs, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                            }
                        }
                    }
                }

                val encOutIdx = encoder.dequeueOutputBuffer(encInfo, TIMEOUT_US)
                when {
                    encOutIdx == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                        if (!muxerStarted) {
                            muxTrackIdx = muxer.addTrack(encoder.outputFormat)
                            muxer.start()
                            muxerStarted = true
                        }
                    }
                    encOutIdx >= 0 -> {
                        val encoded = encoder.getOutputBuffer(encOutIdx)
                        if (encoded != null && encInfo.size > 0 && muxerStarted &&
                            (encInfo.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG) == 0
                        ) {
                            encoded.position(encInfo.offset)
                            encoded.limit(encInfo.offset + encInfo.size)
                            muxer.writeSampleData(muxTrackIdx, encoded, encInfo)
                        }
                        encoder.releaseOutputBuffer(encOutIdx, false)
                        if ((encInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0) {
                            encoderDone = true
                        }
                    }
                }
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
 * - Inviando una Motion Photo Android verso iOS: separa still + MP4 così iOS li ricompone in Apple Live Photo nativa.
 */
object AndroidLiveMotionBridge {
    data class ExtractedAndroidMotionPhoto(
        val stillFile: File,
        val videoMp4File: File,
        val stillExtension: String
    )

    fun tryExtractAndroidMotionPhoto(
        context: Context,
        sourceUri: Uri,
        fileName: String,
        sizeBytes: Long
    ): ExtractedAndroidMotionPhoto? {
        val ext = File(fileName).extension.lowercase(Locale.ROOT)
        if (ext !in setOf("jpg", "jpeg", "heic", "heif")) return null
        if (sizeBytes < 4096L || sizeBytes > 120L * 1024L * 1024L) return null

        val tempSrc = File(context.cacheDir, "mp_probe_${System.nanoTime()}.$ext")
        val outStill = File(context.cacheDir, "mp_still_${System.nanoTime()}.$ext")
        val outVideo = File(context.cacheDir, "mp_clip_${System.nanoTime()}.mp4")
        return try {
            context.contentResolver.openInputStream(sourceUri)?.use { inp ->
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
        val bmp: Bitmap = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            runCatching { ImageDecoder.decodeBitmap(ImageDecoder.createSource(src)) }.getOrNull()
        } else {
            null
        } ?: BitmapFactory.decodeFile(src.absolutePath) ?: return false

        FileOutputStream(dstJpeg).use { fos ->
            if (!bmp.compress(Bitmap.CompressFormat.JPEG, 94, fos)) return false
        }
        bmp.recycle()
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
                    info.flags = extractor.sampleFlags
                    muxer.writeSampleData(dstTrack, buf, info)
                }
                extractor.advance()
            }
            dstMp4.exists() && dstMp4.length() > 1024L
        } catch (_: Throwable) {
            dstMp4.delete()
            false
        } finally {
            runCatching { extractor.release() }
            runCatching { if (started) muxer?.stop(); muxer?.release() }
        }
    }
}

object AndroidDecommissionScanner {
    fun countLocalOrSimOnlyContacts(context: Context): Int {
        if (ContextCompat.checkSelfPermission(context, Manifest.permission.READ_CONTACTS) != PackageManager.PERMISSION_GRANTED) {
            return 0
        }
        var count = 0
        val projection = arrayOf(
            ContactsContract.RawContacts._ID,
            ContactsContract.RawContacts.ACCOUNT_TYPE,
            ContactsContract.RawContacts.DELETED
        )
        runCatching {
            context.contentResolver.query(
                ContactsContract.RawContacts.CONTENT_URI,
                projection,
                "${ContactsContract.RawContacts.DELETED} = 0",
                null,
                null
            )?.use { cursor ->
                val typeIdx = cursor.getColumnIndex(ContactsContract.RawContacts.ACCOUNT_TYPE)
                while (cursor.moveToNext()) {
                    val accType = if (typeIdx >= 0) cursor.getString(typeIdx)?.trim().orEmpty().lowercase(Locale.ROOT) else ""
                    val isLocalOrSim = accType.isEmpty() ||
                        accType.contains("sim") ||
                        accType.contains("phone") ||
                        accType.contains("local") ||
                        accType.contains("device") ||
                        accType.contains("tablet")
                    if (isLocalOrSim) count++
                }
            }
        }
        return count
    }

    fun openDeviceResetSettings(context: Context) {
        val candidates = listOf(
            Intent("android.settings.PRIVACY_SETTINGS"),
            Intent(Settings.ACTION_SETTINGS)
        )
        for (intent in candidates) {
            val ok = runCatching {
                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                context.startActivity(intent)
                true
            }.getOrDefault(false)
            if (ok) return
        }
    }
}

object AndroidCloudSaveOverflowBridge {
    private const val CLOUDSAVE_PACKAGE = "com.cloudsave.android"

    fun isCloudSaveInstalled(context: Context): Boolean {
        return runCatching {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                context.packageManager.getPackageInfo(CLOUDSAVE_PACKAGE, PackageManager.PackageInfoFlags.of(0))
            } else {
                @Suppress("DEPRECATION")
                context.packageManager.getPackageInfo(CLOUDSAVE_PACKAGE, 0)
            }
            true
        }.getOrDefault(false)
    }

    data class LaunchOutcome(
        val launchedCloudSave: Boolean,
        val manifestFile: File,
        val overflowCount: Int,
        val overflowBytes: Long,
        val message: String
    )

    fun stageAndLaunchOverflowToCloudSave(
        context: Context,
        targetDeviceName: String,
        allEntries: List<LocalMediaEntry>,
        plan: OverflowSplitPlan
    ): LaunchOutcome {
        val overflowIds = plan.overflowItems.map { it.id }.toHashSet()
        val overflowEntries = allEntries.filter { it.manifestItem.id in overflowIds }
        val records = overflowEntries.map { e ->
            DirectSwitchOverflowItemRecord(
                id = e.manifestItem.id,
                category = e.manifestItem.category,
                fileName = e.manifestItem.fileName,
                album = e.manifestItem.relativeAlbumOrFolder,
                sizeBytes = e.manifestItem.sizeBytes,
                capturedEpochMillis = e.manifestItem.capturedEpochMillis,
                contentUri = e.contentUri.toString()
            )
        }
        val manifest = DirectSwitchOverflowHandoffManifest(
            version = 1,
            createdAtEpochMillis = System.currentTimeMillis(),
            sourceDeviceName = "${Build.MANUFACTURER} ${Build.MODEL}".trim(),
            targetDeviceName = targetDeviceName,
            cutoffEpochMillis = plan.cutoffEpochMillis,
            maxVideoBytes = plan.maxVideoBytes,
            totalOverflowCount = records.size,
            totalOverflowBytes = plan.overflowTotalBytes,
            items = records
        )

        val dir = File(context.cacheDir, "overflow_bridge").apply { mkdirs() }
        val manifestFile = File(dir, "directswitch_overflow_handoff.json")
        manifestFile.writeText(DirectSwitchJson.instance.encodeToString(manifest), Charsets.UTF_8)

        if (!isCloudSaveInstalled(context)) {
            return LaunchOutcome(
                launchedCloudSave = false,
                manifestFile = manifestFile,
                overflowCount = records.size,
                overflowBytes = plan.overflowTotalBytes,
                message = "Installa CloudSave per parcheggiare cifrati i ${records.size} file eccedenti."
            )
        }

        val contentUri = runCatching {
            FileProvider.getUriForFile(context, "${context.packageName}.fileprovider", manifestFile)
        }.getOrNull()

        if (contentUri != null) {
            runCatching {
                context.grantUriPermission(CLOUDSAVE_PACKAGE, contentUri, Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
        }

        val deepLink = Uri.Builder()
            .scheme("com.cloudsave.android")
            .authority("overflow-bridge")
            .appendQueryParameter("count", records.size.toString())
            .appendQueryParameter("bytes", plan.overflowTotalBytes.toString())
            .appendQueryParameter("cutoffMs", plan.cutoffEpochMillis.toString())
            .appendQueryParameter("maxVideoBytes", plan.maxVideoBytes.toString())
            .appendQueryParameter("receiver", targetDeviceName)
            .apply {
                if (contentUri != null) {
                    appendQueryParameter("manifestUri", contentUri.toString())
                }
            }
            .build()

        val launched = runCatching {
            val intent = Intent(Intent.ACTION_VIEW, deepLink).apply {
                setPackage(CLOUDSAVE_PACKAGE)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
            context.startActivity(intent)
            true
        }.getOrDefault(false)

        return LaunchOutcome(
            launchedCloudSave = launched,
            manifestFile = manifestFile,
            overflowCount = records.size,
            overflowBytes = plan.overflowTotalBytes,
            message = if (launched) {
                "CloudSave aperto con ${records.size} file pronti per l'archiviazione cifrata!"
            } else {
                "Manifest Overflow pronto (${records.size} file): apri CloudSave per completarne il salvataggio."
            }
        )
    }
}
