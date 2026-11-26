//
//  DirectSwitchMainScreen.kt
//  DirectSwitch-Android
//
//  Created by Nicolas Donati.
//  Copyright © 2026 Nicolas Donati. Tutti i diritti riservati.
//

package com.directswitch.android.ui

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import android.view.ViewGroup
import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.camera.core.CameraSelector
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.ImageProxy
import androidx.camera.core.Preview
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.view.PreviewView
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.ArrowForward
import androidx.compose.material.icons.automirrored.filled.Chat
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.Apps
import androidx.compose.material.icons.filled.AudioFile
import androidx.compose.material.icons.filled.CalendarMonth
import androidx.compose.material.icons.filled.Call
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Checklist
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Contacts
import androidx.compose.material.icons.filled.Description
import androidx.compose.material.icons.filled.Email
import androidx.compose.material.icons.filled.Folder
import androidx.compose.material.icons.filled.Image
import androidx.compose.material.icons.filled.PhoneAndroid
import androidx.compose.material.icons.filled.PhoneIphone
import androidx.compose.material.icons.filled.QrCode2
import androidx.compose.material.icons.filled.QrCodeScanner
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Schedule
import androidx.compose.material.icons.filled.Sms
import androidx.compose.material.icons.filled.SwapHoriz
import androidx.compose.material.icons.filled.Videocam
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material.icons.filled.Wifi
import androidx.compose.material.icons.filled.WifiTethering
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.core.content.ContextCompat
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import com.directswitch.android.DirectSwitchLog
import com.directswitch.android.migrators.AndroidBatteryTriageMonitor
import com.directswitch.android.migrators.AndroidMediaFilterHelper
import com.directswitch.android.migrators.AudioAndMemoMigrator
import com.directswitch.android.migrators.BatterySnapshot
import com.directswitch.android.migrators.CalendarMigrator
import com.directswitch.android.migrators.CallLogMigrator
import com.directswitch.android.migrators.ContactsPreloadState
import com.directswitch.android.migrators.ContactsSmartMerger
import com.directswitch.android.migrators.DateSyncPreloadState
import com.directswitch.android.migrators.DeviceDataAnalyzer
import com.directswitch.android.migrators.DocumentPrecheckReport
import com.directswitch.android.migrators.DocumentsAndWhatsAppScanner
import com.directswitch.android.migrators.InstalledAppCategoryGroup
import com.directswitch.android.migrators.InstalledAppsScanner
import com.directswitch.android.migrators.LocalDeviceScanSummary
import com.directswitch.android.migrators.MediaExifScannerAndImporter
import com.directswitch.android.migrators.PhotosPreloadState
import com.directswitch.android.migrators.SmsSystemScanner
import com.directswitch.android.migrators.VideosPreloadState
import com.directswitch.android.protocol.CompletedMigrationRecord
import com.directswitch.android.protocol.CompletedMigrationStore
import com.directswitch.android.protocol.DevicePlatform
import com.directswitch.android.protocol.DirectSwitchL10n
import com.directswitch.android.protocol.DirectSwitchLanguage
import com.directswitch.android.protocol.DiscoveryBeaconPayload
import com.directswitch.android.protocol.InstalledAppRecord
import com.directswitch.android.protocol.MediaTransferFilterOptions
import com.directswitch.android.protocol.NetworkDiagnosticVerdict
import com.directswitch.android.protocol.QrPairingPayload
import com.directswitch.android.protocol.SmartCleanOptions
import com.directswitch.android.protocol.SpaceReliefActionKind
import com.directswitch.android.protocol.SpaceReliefPlanner
import com.directswitch.android.protocol.ThermalGuardState
import com.directswitch.android.protocol.TransferCheckpointRecord
import com.directswitch.android.protocol.TransferCheckpointStore
import com.directswitch.android.protocol.TransferDisplayFormatting
import com.directswitch.android.protocol.TransferPreparationItem
import com.directswitch.android.protocol.TransferSessionStage
import com.directswitch.android.transport.DirectSwitchAutoDiscovery
import com.directswitch.android.transport.DirectSwitchTransferClient
import com.directswitch.android.transport.DirectSwitchTransferServer
import com.directswitch.android.transport.LiveTransferProgress
import com.directswitch.android.transport.LocalNetworkAddresses
import com.directswitch.android.transport.LocalOnlyHotspotController
import com.directswitch.android.ui.theme.AppleSettingsIcon
import com.directswitch.android.ui.theme.AppleTopNavigationBar
import com.directswitch.android.ui.theme.CleanCategoryToggleRow
import com.directswitch.android.ui.theme.DirectSwitchAppleEmblem
import com.directswitch.android.ui.theme.DirectSwitchCard
import com.directswitch.android.ui.theme.DirectSwitchNeutralOutlinedButton
import com.directswitch.android.ui.theme.DirectSwitchPrimaryButton
import com.directswitch.android.ui.theme.DirectSwitchSecondaryButton
import com.directswitch.android.ui.theme.DirectSwitchTheme
import com.directswitch.android.ui.theme.InfoCircleButton
import com.directswitch.android.ui.theme.PassaAiOSCodeBoxes
import com.directswitch.android.ui.theme.QrBitmapGenerator
import com.google.zxing.BarcodeFormat
import com.google.zxing.BinaryBitmap
import com.google.zxing.DecodeHintType
import com.google.zxing.PlanarYUVLuminanceSource
import com.google.zxing.ReaderException
import com.google.zxing.common.HybridBinarizer
import com.google.zxing.qrcode.QRCodeReader
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File
import java.util.Locale
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

private enum class WizardStep {
    HOME,
    RECEIVER_WAIT_CODE,
    RECEIVER_CONNECTED,
    SENDER_CONNECT,
    SENDER_SELECT_CATEGORIES,
    TRANSFER_PREPARING,
    TRANSFER_PROGRESS
}

private data class CategorySelectionState(
    val contacts: Boolean = false,
    val photos: Boolean = false,
    val videos: Boolean = false,
    val calendars: Boolean = false,
    val sms: Boolean = false,
    val callLogs: Boolean = false,
    val audio: Boolean = false,
    val documents: Boolean = false,
    val whatsAppVault: Boolean = false,
    val installedApps: Boolean = false
)

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun DirectSwitchMainScreen(
    externalVaultNote: String? = null,
    externalVaultTrigger: Int = 0
) {
    DirectSwitchTheme.isDarkMode = isSystemInDarkTheme()
    val context = LocalContext.current
    val scope = rememberCoroutineScope()

    LaunchedEffect(Unit) {
        DirectSwitchL10n.init(context)
    }
    val currentLanguage = DirectSwitchL10n.activeLanguage
    var isLaunchingTransfer by remember { mutableStateOf(false) }
    var resumableCheckpoint by remember { mutableStateOf(TransferCheckpointStore.load(context)) }
    var completedDeltaRecord by remember {
        mutableStateOf(CompletedMigrationStore.load(CompletedMigrationStore.defaultFile(context.filesDir)))
    }
    var activeDeltaBaseline by remember { mutableStateOf<CompletedMigrationRecord?>(null) }
    var forceBatteryTriage by remember { mutableStateOf(false) }
    var step by remember { mutableStateOf(WizardStep.HOME) }
    var scanSummary by remember { mutableStateOf<LocalDeviceScanSummary?>(null) }

    val server = remember { DirectSwitchTransferServer(context) }
    val client = remember { DirectSwitchTransferClient(context) }
    val hotspotController = remember { LocalOnlyHotspotController(context) }
    val autoDiscovery = remember { DirectSwitchAutoDiscovery(context) }
    val discoveredDevices by autoDiscovery.discoveredDevices.collectAsState()
    val activePairingPin by server.activePairingPin.collectAsState()
    val serverProgress by server.progress.collectAsState()
    val clientProgress by client.progress.collectAsState()
    val clientNetworkDiagnostic by client.networkDiagnostic.collectAsState()

    var smartCleanOptions by remember { mutableStateOf(SmartCleanOptions()) }
    var convertHeicToJpeg by remember { mutableStateOf(false) }

    var activeQrPayload by remember { mutableStateOf<QrPairingPayload?>(null) }
    var useOffline5GhzHotspot by remember { mutableStateOf(false) }
    var hotspotStatusNote by remember { mutableStateOf<String?>(null) }

    var selectedBeaconForPin by remember { mutableStateOf<DiscoveryBeaconPayload?>(null) }
    var pinInput by remember { mutableStateOf("") }
    var pinErrorNote by remember { mutableStateOf<String?>(null) }
    var isPinPairingBusy by remember { mutableStateOf(false) }

    var pairedTargetPayload by remember { mutableStateOf<QrPairingPayload?>(null) }
    var manualQrInput by remember { mutableStateOf("") }
    var showCameraScanner by remember { mutableStateOf(false) }

    var vaultStatusNote by remember { mutableStateOf<String?>(null) }
    var pendingDocPrecheckReport by remember { mutableStateOf<DocumentPrecheckReport?>(null) }

    var categories by remember { mutableStateOf(CategorySelectionState()) }
    var calendarsUpToTodayOnly by remember { mutableStateOf(false) }
    var smsUpToTodayOnly by remember { mutableStateOf(false) }
    var mediaFilters by remember { mutableStateOf(MediaTransferFilterOptions()) }
    var availablePhotoAlbums by remember { mutableStateOf<List<String>>(emptyList()) }
    var contactsPreload by remember { mutableStateOf(ContactsPreloadState()) }
    var photosPreload by remember { mutableStateOf(PhotosPreloadState()) }
    var videosPreload by remember { mutableStateOf(VideosPreloadState()) }
    var calendarsSync by remember { mutableStateOf(DateSyncPreloadState()) }
    var smsSync by remember { mutableStateOf(DateSyncPreloadState()) }
    var audioFilesCount by remember { mutableIntStateOf(0) }
    var isLoadingAudio by remember { mutableStateOf(false) }
    var callLogsCount by remember { mutableIntStateOf(0) }
    var isLoadingCallLogs by remember { mutableStateOf(false) }
    var detectedAppsCatalog by remember { mutableStateOf<List<InstalledAppRecord>>(emptyList()) }
    var groupedAppCategories by remember { mutableStateOf<List<InstalledAppCategoryGroup>>(emptyList()) }
    var deselectedAppPackages by remember { mutableStateOf<Set<String>>(emptySet()) }
    var extraSelectedCuratedApps by remember { mutableStateOf<List<InstalledAppRecord>>(emptyList()) }
    var stagedPasswordCsvFiles by remember { mutableStateOf<List<File>>(emptyList()) }
    var isLoadingAppsCatalog by remember { mutableStateOf(false) }
    var isReceiverFlow by remember { mutableStateOf(false) }

    var pendingPermissionContinuation by remember { mutableStateOf<(() -> Unit)?>(null) }
    var didRequestMediaLocationUpgrade by remember { mutableStateOf(false) }

    val permissionsLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestMultiplePermissions()
    ) {
        scope.launch {
            scanSummary = withContext(Dispatchers.IO) { DeviceDataAnalyzer.scanSummary(context) }
            val next = pendingPermissionContinuation
            pendingPermissionContinuation = null
            next?.invoke()
        }
    }

    val folderTreePickerLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.OpenDocumentTree()
    ) { treeUri ->
        if (treeUri != null) {
            scope.launch {
                val ok = withContext(Dispatchers.IO) {
                    DocumentsAndWhatsAppScanner.savePickedFolderTree(context, treeUri)
                }
                scanSummary = withContext(Dispatchers.IO) { DeviceDataAnalyzer.scanSummary(context) }
                vaultStatusNote = if (ok) {
                    "Cartella autorizzata: tutte le sottocartelle verranno mantenute intatte."
                } else {
                    "Impossibile leggere la cartella selezionata."
                }
            }
        }
    }

    val passwordCsvPickerLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.OpenDocument()
    ) { uri ->
        if (uri != null) {
            scope.launch {
                val staged = withContext(Dispatchers.IO) {
                    runCatching {
                        val dest = File(context.cacheDir, "ds_pwd_${System.currentTimeMillis()}.csv")
                        context.contentResolver.openInputStream(uri)?.use { inp ->
                            dest.outputStream().use { out -> inp.copyTo(out) }
                        }
                        if (dest.exists() && dest.length() > 0L) dest else null
                    }.getOrNull()
                }
                if (staged != null) {
                    stagedPasswordCsvFiles = stagedPasswordCsvFiles + staged
                    categories = categories.copy(documents = true)
                    vaultStatusNote = "File CSV Password pronto (sarà sovrascritto a zeri a fine trasferimento)."
                }
            }
        }
    }

    val currentLifecycleOwner = LocalLifecycleOwner.current
    DisposableEffect(currentLifecycleOwner, step) {
        val observer = LifecycleEventObserver { _, event ->
            if (event == Lifecycle.Event.ON_RESUME && step == WizardStep.SENDER_SELECT_CATEGORIES) {
                scope.launch {
                    scanSummary = withContext(Dispatchers.IO) { DeviceDataAnalyzer.scanSummary(context) }
                }
            }
        }
        currentLifecycleOwner.lifecycle.addObserver(observer)
        onDispose { currentLifecycleOwner.lifecycle.removeObserver(observer) }
    }

    fun buildSenderEntryPermissions(): List<String> {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            listOf(
                Manifest.permission.NEARBY_WIFI_DEVICES,
                Manifest.permission.POST_NOTIFICATIONS
            )
        } else {
            listOf(
                Manifest.permission.ACCESS_FINE_LOCATION,
                Manifest.permission.ACCESS_COARSE_LOCATION
            )
        }
    }

    fun buildReceiverEntryPermissions(): List<String> {
        val perms = mutableListOf(
            Manifest.permission.READ_CONTACTS,
            Manifest.permission.WRITE_CONTACTS,
            Manifest.permission.READ_CALENDAR,
            Manifest.permission.WRITE_CALENDAR
        )
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            perms.add(Manifest.permission.NEARBY_WIFI_DEVICES)
            perms.add(Manifest.permission.POST_NOTIFICATIONS)
        } else {
            perms.add(Manifest.permission.ACCESS_FINE_LOCATION)
            perms.add(Manifest.permission.ACCESS_COARSE_LOCATION)
            if (Build.VERSION.SDK_INT <= Build.VERSION_CODES.Q) {
                perms.add(Manifest.permission.WRITE_EXTERNAL_STORAGE)
            }
        }
        return perms
    }

    fun requestEntryPermissionsThen(perms: List<String>, actionAfter: (() -> Unit)? = null) {
        val missing = perms.filter { perm ->
            ContextCompat.checkSelfPermission(context, perm) != PackageManager.PERMISSION_GRANTED
        }
        if (missing.isEmpty()) {
            scope.launch {
                scanSummary = withContext(Dispatchers.IO) { DeviceDataAnalyzer.scanSummary(context) }
                actionAfter?.invoke()
            }
        } else {
            pendingPermissionContinuation = actionAfter
            permissionsLauncher.launch(missing.toTypedArray())
        }
    }

    fun requestSpecificPermissionsThen(perms: List<String>, actionAfter: (() -> Unit)? = null) {
        val missing = perms.filter { perm ->
            ContextCompat.checkSelfPermission(context, perm) != PackageManager.PERMISSION_GRANTED
        }
        if (missing.isEmpty()) {
            actionAfter?.invoke()
        } else {
            pendingPermissionContinuation = actionAfter
            permissionsLauncher.launch(missing.toTypedArray())
        }
    }

    fun startContactsPreload() {
        if (!ContactsSmartMerger.hasReadPermission(context)) return
        contactsPreload = ContactsPreloadState(isLoading = true)
        scope.launch {
            val total = ContactsSmartMerger.preloadContactsCountWithProgress(context) { loaded, tot ->
                contactsPreload = ContactsPreloadState(loadedCount = loaded, totalCount = tot, isLoading = true, isCompleted = false)
            }
            contactsPreload = ContactsPreloadState(loadedCount = total, totalCount = total, isLoading = false, isCompleted = true)
        }
    }

    fun startPhotosPreload() {
        if (!MediaExifScannerAndImporter.hasPhotoPermission(context)) return
        photosPreload = PhotosPreloadState(isLoading = true)
        scope.launch {
            val (total, albums, bytes) = MediaExifScannerAndImporter.preloadMediaStatsWithProgress(context, isVideo = false) { loaded, tot, alb, b ->
                photosPreload = PhotosPreloadState(loadedCount = loaded, totalCount = tot, albumsCount = alb, estimatedBytes = b, isLoading = true, isCompleted = false)
            }
            photosPreload = PhotosPreloadState(loadedCount = total, totalCount = total, albumsCount = albums, estimatedBytes = bytes, isLoading = false, isCompleted = true)
            availablePhotoAlbums = withContext(Dispatchers.IO) { AndroidMediaFilterHelper.listPhotoAlbumNames(context) }
        }
    }

    fun startVideosPreload() {
        if (!MediaExifScannerAndImporter.hasVideoPermission(context)) return
        videosPreload = VideosPreloadState(isLoading = true)
        scope.launch {
            val (total, _, bytes) = MediaExifScannerAndImporter.preloadMediaStatsWithProgress(context, isVideo = true) { loaded, tot, _, b ->
                videosPreload = VideosPreloadState(loadedCount = loaded, totalCount = tot, estimatedBytes = b, isLoading = true, isCompleted = false)
            }
            videosPreload = VideosPreloadState(loadedCount = total, totalCount = total, estimatedBytes = bytes, isLoading = false, isCompleted = true)
        }
    }

    fun refreshCalendarsSync() {
        if (!CalendarMigrator.hasReadPermission(context)) return
        calendarsSync = calendarsSync.copy(isLoading = true)
        scope.launch {
            val (allCount, upToTodayCount) = withContext(Dispatchers.IO) {
                val cutoff = CalendarMigrator.endOfDayMillis()
                CalendarMigrator.readEvents(context, null).size to
                    CalendarMigrator.readEvents(context, cutoff).size
            }
            calendarsSync = DateSyncPreloadState(
                totalAllCount = allCount,
                totalUpToTodayCount = upToTodayCount,
                lastUpdatedEpochMillis = System.currentTimeMillis(),
                isLoading = false
            )
        }
    }

    fun refreshSmsSync() {
        if (!SmsSystemScanner.hasReadPermission(context)) return
        smsSync = smsSync.copy(isLoading = true)
        scope.launch {
            val (allCount, upToTodayCount) = withContext(Dispatchers.IO) {
                val cutoff = CalendarMigrator.endOfDayMillis()
                SmsSystemScanner.countSms(context, null) to
                    SmsSystemScanner.countSms(context, cutoff)
            }
            smsSync = DateSyncPreloadState(
                totalAllCount = allCount,
                totalUpToTodayCount = upToTodayCount,
                lastUpdatedEpochMillis = System.currentTimeMillis(),
                isLoading = false
            )
        }
    }

    fun refreshAudioSync() {
        if (!AudioAndMemoMigrator.hasReadPermission(context)) return
        isLoadingAudio = true
        scope.launch {
            audioFilesCount = withContext(Dispatchers.IO) { AudioAndMemoMigrator.scanAudioAndVoiceMemos(context).size }
            isLoadingAudio = false
        }
    }

    fun refreshCallLogsSync() {
        if (!CallLogMigrator.hasReadPermission(context)) return
        isLoadingCallLogs = true
        scope.launch {
            callLogsCount = withContext(Dispatchers.IO) { CallLogMigrator.readCallLogs(context).size }
            isLoadingCallLogs = false
        }
    }

    fun loadInstalledAppsCatalog() {
        isLoadingAppsCatalog = true
        scope.launch {
            val (scanned, groups) = withContext(Dispatchers.IO) {
                val list = InstalledAppsScanner.scanUserInstalledApps(context)
                val cats = InstalledAppsScanner.groupInstalledAppsByCategory(context, list)
                list to cats
            }
            detectedAppsCatalog = scanned
            groupedAppCategories = groups
            isLoadingAppsCatalog = false
        }
    }

    fun updateCategoriesAndTriggerPreloads(next: CategorySelectionState) {
        val prev = categories
        categories = next
        // Raccoglie TUTTI i permessi mancanti in un'unica richiesta di sistema: Android ne mostra una sola alla volta,
        // quindi più richieste parallele (es. "Seleziona tutto") farebbero perdere i precaricamenti delle altre voci.
        val missingPerms = LinkedHashSet<String>()
        val pendingActions = mutableListOf<() -> Unit>()
        fun schedule(granted: Boolean, perms: List<String>, action: () -> Unit) {
            if (granted) action() else {
                missingPerms.addAll(perms)
                pendingActions.add(action)
            }
        }
        if (!prev.contacts && next.contacts) {
            schedule(
                ContactsSmartMerger.hasReadPermission(context),
                listOf(Manifest.permission.READ_CONTACTS, Manifest.permission.WRITE_CONTACTS)
            ) { startContactsPreload() }
        }
        val shouldAskMediaLocUpgrade = !MediaExifScannerAndImporter.hasMediaLocationPermission(context) && !didRequestMediaLocationUpgrade
        if (!prev.photos && next.photos) {
            val photoPerms = buildList {
                when {
                    Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE -> {
                        add(Manifest.permission.READ_MEDIA_IMAGES)
                        add(Manifest.permission.READ_MEDIA_VISUAL_USER_SELECTED)
                    }
                    Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU ->
                        add(Manifest.permission.READ_MEDIA_IMAGES)
                    else ->
                        add(Manifest.permission.READ_EXTERNAL_STORAGE)
                }
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    add(Manifest.permission.ACCESS_MEDIA_LOCATION)
                }
            }
            if (!MediaExifScannerAndImporter.hasPhotoPermission(context)) {
                schedule(false, photoPerms) { startPhotosPreload() }
            } else if (shouldAskMediaLocUpgrade) {
                schedule(false, listOf(Manifest.permission.ACCESS_MEDIA_LOCATION)) { startPhotosPreload() }
            } else {
                startPhotosPreload()
            }
        }
        if (!prev.videos && next.videos) {
            val videoPerms = buildList {
                when {
                    Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE -> {
                        add(Manifest.permission.READ_MEDIA_VIDEO)
                        add(Manifest.permission.READ_MEDIA_VISUAL_USER_SELECTED)
                    }
                    Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU ->
                        add(Manifest.permission.READ_MEDIA_VIDEO)
                    else ->
                        add(Manifest.permission.READ_EXTERNAL_STORAGE)
                }
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    add(Manifest.permission.ACCESS_MEDIA_LOCATION)
                }
            }
            if (!MediaExifScannerAndImporter.hasVideoPermission(context)) {
                schedule(false, videoPerms) { startVideosPreload() }
            } else if (shouldAskMediaLocUpgrade) {
                schedule(false, listOf(Manifest.permission.ACCESS_MEDIA_LOCATION)) { startVideosPreload() }
            } else {
                startVideosPreload()
            }
        }
        if (shouldAskMediaLocUpgrade && ((!prev.photos && next.photos) || (!prev.videos && next.videos))) {
            didRequestMediaLocationUpgrade = true
        }
        if (!prev.calendars && next.calendars) {
            schedule(
                CalendarMigrator.hasReadPermission(context),
                listOf(Manifest.permission.READ_CALENDAR, Manifest.permission.WRITE_CALENDAR)
            ) { refreshCalendarsSync() }
        }
        if (!prev.sms && next.sms) {
            schedule(SmsSystemScanner.hasReadPermission(context), listOf(Manifest.permission.READ_SMS)) { refreshSmsSync() }
        }
        if (!prev.audio && next.audio) {
            schedule(AudioAndMemoMigrator.hasReadPermission(context), listOf(AudioAndMemoMigrator.requiredReadPermission())) { refreshAudioSync() }
        }
        if (!prev.callLogs && next.callLogs) {
            schedule(CallLogMigrator.hasReadPermission(context), listOf(Manifest.permission.READ_CALL_LOG)) { refreshCallLogsSync() }
        }
        if (missingPerms.isNotEmpty()) {
            requestSpecificPermissionsThen(missingPerms.toList()) {
                // Ogni azione verifica di nuovo il proprio permesso e non fa nulla se l'utente lo ha negato
                pendingActions.forEach { it() }
            }
        }
        if (!prev.documents && next.documents) {
            scope.launch {
                scanSummary = withContext(Dispatchers.IO) { DeviceDataAnalyzer.scanSummary(context) }
            }
        }
        if (!prev.installedApps && next.installedApps) {
            deselectedAppPackages = emptySet()
            loadInstalledAppsCatalog()
        }
    }

    fun resetCategorySelectionsAndPreloads() {
        categories = CategorySelectionState()
        calendarsUpToTodayOnly = false
        smsUpToTodayOnly = false
        mediaFilters = MediaTransferFilterOptions()
        contactsPreload = ContactsPreloadState()
        photosPreload = PhotosPreloadState()
        videosPreload = VideosPreloadState()
        calendarsSync = DateSyncPreloadState()
        smsSync = DateSyncPreloadState()
        audioFilesCount = 0
        callLogsCount = 0
        deselectedAppPackages = emptySet()
        extraSelectedCuratedApps = emptyList()
        stagedPasswordCsvFiles = emptyList()
    }

    fun resetAndGoHome() {
        isLaunchingTransfer = false
        showCameraScanner = false
        autoDiscovery.stopAdvertising()
        autoDiscovery.stopScanning()
        server.stop()
        server.resetProgress()
        client.resetProgress()
        hotspotController.stopHotspot()
        useOffline5GhzHotspot = false
        hotspotStatusNote = null
        activeQrPayload = null
        pairedTargetPayload = null
        selectedBeaconForPin = null
        pinInput = ""
        pinErrorNote = null
        resetCategorySelectionsAndPreloads()
        step = WizardStep.HOME
    }

    fun handleBack() {
        when (step) {
            WizardStep.HOME -> Unit
            WizardStep.RECEIVER_WAIT_CODE,
            WizardStep.RECEIVER_CONNECTED,
            WizardStep.TRANSFER_PREPARING,
            WizardStep.TRANSFER_PROGRESS -> resetAndGoHome()
            WizardStep.SENDER_CONNECT -> {
                showCameraScanner = false
                autoDiscovery.stopScanning()
                step = WizardStep.HOME
            }
            WizardStep.SENDER_SELECT_CATEGORIES -> {
                val previousTarget = pairedTargetPayload
                if (previousTarget != null) {
                    scope.launch { client.sendPairReset(previousTarget) }
                }
                pairedTargetPayload = null
                pinInput = ""
                pinErrorNote = null
                autoDiscovery.startScanningForNewDevices()
                step = WizardStep.SENDER_CONNECT
            }
        }
    }

    BackHandler(enabled = step != WizardStep.HOME) {
        handleBack()
    }

    LaunchedEffect(Unit) {
        scanSummary = withContext(Dispatchers.IO) { DeviceDataAnalyzer.scanSummary(context) }
    }

    LaunchedEffect(externalVaultTrigger) {
        if (externalVaultTrigger > 0 && !externalVaultNote.isNullOrBlank()) {
            vaultStatusNote = externalVaultNote
            scanSummary = withContext(Dispatchers.IO) { DeviceDataAnalyzer.scanSummary(context) }
            if (step == WizardStep.HOME) {
                isReceiverFlow = false
                autoDiscovery.startScanningForNewDevices()
                step = WizardStep.SENDER_CONNECT
            }
        }
    }

    LaunchedEffect(serverProgress.sessionStage, serverProgress.errorMessage, isReceiverFlow, step) {
        if (!isReceiverFlow && step != WizardStep.RECEIVER_WAIT_CODE && step != WizardStep.RECEIVER_CONNECTED) {
            return@LaunchedEffect
        }
        when (serverProgress.sessionStage) {
            TransferSessionStage.WAITING_PAIRING -> {
                if (step == WizardStep.RECEIVER_CONNECTED) {
                    step = WizardStep.RECEIVER_WAIT_CODE
                }
            }
            TransferSessionStage.PAIRED_WAITING_SELECTION -> {
                if (step == WizardStep.RECEIVER_WAIT_CODE) {
                    isReceiverFlow = true
                    step = WizardStep.RECEIVER_CONNECTED
                }
            }
            TransferSessionStage.PREPARING -> {
                if (step == WizardStep.RECEIVER_WAIT_CODE || step == WizardStep.RECEIVER_CONNECTED) {
                    isReceiverFlow = true
                    step = WizardStep.TRANSFER_PREPARING
                }
            }
            TransferSessionStage.TRANSFERRING, TransferSessionStage.COMPLETED -> {
                if (step == WizardStep.RECEIVER_WAIT_CODE ||
                    step == WizardStep.RECEIVER_CONNECTED ||
                    step == WizardStep.TRANSFER_PREPARING
                ) {
                    isReceiverFlow = true
                    step = WizardStep.TRANSFER_PROGRESS
                }
            }
        }
        if (serverProgress.errorMessage != null && step == WizardStep.TRANSFER_PREPARING && isReceiverFlow) {
            step = WizardStep.TRANSFER_PROGRESS
        }
    }

    LaunchedEffect(clientProgress.sessionStage, clientProgress.errorMessage, isReceiverFlow, step) {
        if (isReceiverFlow) return@LaunchedEffect
        when (clientProgress.sessionStage) {
            TransferSessionStage.PREPARING -> {
                if (step == WizardStep.SENDER_SELECT_CATEGORIES) {
                    step = WizardStep.TRANSFER_PREPARING
                }
            }
            TransferSessionStage.TRANSFERRING, TransferSessionStage.COMPLETED -> {
                if (step == WizardStep.TRANSFER_PREPARING) {
                    step = WizardStep.TRANSFER_PROGRESS
                }
            }
            else -> Unit
        }
        if (clientProgress.errorMessage != null && step == WizardStep.TRANSFER_PREPARING) {
            step = WizardStep.TRANSFER_PROGRESS
        }
    }

    DisposableEffect(Unit) {
        onDispose {
            autoDiscovery.stopAdvertising()
            autoDiscovery.stopScanning()
            server.stop()
            hotspotController.stopHotspot()
        }
    }

    fun launchSenderTransfer(
        targetPayload: QrPairingPayload,
        onlyRetryItemIds: Set<String>? = null,
        resumeCheckpoint: TransferCheckpointRecord? = null
    ) {
        isLaunchingTransfer = false
        pendingDocPrecheckReport = null
        isReceiverFlow = false
        vaultStatusNote = null
        val selectedDetected = if (categories.installedApps && detectedAppsCatalog.isNotEmpty()) {
            detectedAppsCatalog.filter { it.packageName !in deselectedAppPackages }
        } else {
            emptyList()
        }
        val mergedApps = (selectedDetected + extraSelectedCuratedApps).distinctBy { it.packageName }
        val appsOverride = if (categories.installedApps && mergedApps.isNotEmpty()) mergedApps else null
        val isWhatsAppOnly = onlyRetryItemIds == null &&
            resumeCheckpoint == null &&
            targetPayload.receiverPlatform != DevicePlatform.IOS &&
            categories.whatsAppVault &&
            !categories.contacts && !categories.photos && !categories.videos &&
            !categories.calendars && !categories.sms && !categories.audio &&
            !categories.callLogs && !categories.documents &&
            !categories.installedApps
        val skipPrep = isWhatsAppOnly || resumeCheckpoint != null || !onlyRetryItemIds.isNullOrEmpty()
        step = if (skipPrep) WizardStep.TRANSFER_PROGRESS else WizardStep.TRANSFER_PREPARING
        val pwdFilesSnapshot = stagedPasswordCsvFiles
        val deltaSnapshot = activeDeltaBaseline
        val triageSnapshot = forceBatteryTriage
        val smartCleanSnapshot = smartCleanOptions
        val heicCompatSnapshot = convertHeicToJpeg
        scope.launch {
            client.executeTransfer(
                qrPayload = targetPayload,
                includeContacts = categories.contacts,
                includePhotos = categories.photos,
                includeVideos = categories.videos,
                includeCalendars = categories.calendars,
                calendarsUpToTodayOnly = calendarsUpToTodayOnly,
                includeSms = categories.sms,
                smsUpToTodayOnly = smsUpToTodayOnly,
                includeDocuments = categories.documents,
                includeWhatsAppVault = if (targetPayload.receiverPlatform == DevicePlatform.IOS) false else categories.whatsAppVault,
                includeInstalledApps = categories.installedApps,
                installedAppsOverride = appsOverride,
                includeAudio = categories.audio,
                includeCallLogs = categories.callLogs,
                mediaFilters = mediaFilters,
                onlyRetryItemIds = onlyRetryItemIds,
                resumeCheckpoint = resumeCheckpoint,
                stagedPasswordCsvFiles = pwdFilesSnapshot,
                deltaBaseline = deltaSnapshot,
                forceBatteryTriage = triageSnapshot,
                smartCleanOptions = smartCleanSnapshot,
                convertHeicToJpeg = heicCompatSnapshot
            )
            val finalProg = client.progress.value
            if (finalProg.isCompleted && finalProg.failedItemsCount == 0 && finalProg.reconciliationMissingIds.isEmpty()) {
                stagedPasswordCsvFiles = emptyList()
            }
            resumableCheckpoint = TransferCheckpointStore.load(context)
            completedDeltaRecord = CompletedMigrationStore.load(CompletedMigrationStore.defaultFile(context.filesDir))
        }
    }

    fun resumeSavedCheckpoint(cp: TransferCheckpointRecord) {
        val parsed = runCatching { QrPairingPayload.fromJson(cp.qrPayloadJson) }.getOrNull()
        if (parsed == null) {
            TransferCheckpointStore.clear(context)
            resumableCheckpoint = null
            return
        }
        pairedTargetPayload = parsed
        categories = CategorySelectionState(
            contacts = cp.scope.contacts,
            photos = cp.scope.photos,
            videos = cp.scope.videos,
            calendars = cp.scope.calendars,
            sms = true,
            callLogs = cp.scope.callLogs,
            audio = cp.scope.audio,
            documents = cp.scope.documents,
            whatsAppVault = cp.scope.whatsApp,
            installedApps = cp.scope.apps
        )
        mediaFilters = cp.filterOptions
        launchSenderTransfer(parsed, resumeCheckpoint = cp)
    }

    fun applySpaceReliefAndRestart(action: SpaceReliefActionKind) {
        val target = pairedTargetPayload ?: return
        when (action) {
            SpaceReliefActionKind.EXCLUDE_HEAVY_VIDEOS_300MB -> {
                mediaFilters = mediaFilters.copy(maxVideoBytes = SpaceReliefPlanner.HEAVY_VIDEO_THRESHOLD_BYTES)
            }
            SpaceReliefActionKind.LAST_YEAR_MEDIA_ONLY -> {
                mediaFilters = mediaFilters.copy(photosLastYearOnly = true, videosLastYearOnly = true)
            }
            SpaceReliefActionKind.EXCLUDE_ALL_VIDEOS -> {
                categories = categories.copy(videos = false)
            }
        }
        launchSenderTransfer(target)
    }

    val topTitle = when (step) {
        WizardStep.HOME -> "DirectSwitch"
        WizardStep.RECEIVER_WAIT_CODE -> DirectSwitchL10n.tr("Ricevi dati")
        WizardStep.RECEIVER_CONNECTED -> DirectSwitchL10n.tr("Collegato")
        WizardStep.SENDER_CONNECT -> DirectSwitchL10n.tr("Collega telefono")
        WizardStep.SENDER_SELECT_CATEGORIES -> DirectSwitchL10n.tr("Cosa copiare")
        WizardStep.TRANSFER_PREPARING -> DirectSwitchL10n.tr("Preparazione")
        WizardStep.TRANSFER_PROGRESS -> {
            val done = if (isReceiverFlow) serverProgress.isCompleted else clientProgress.isCompleted
            if (done) DirectSwitchL10n.tr("Completato")
            else DirectSwitchL10n.tr("Copia dati")
        }
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(DirectSwitchTheme.backgroundBrush)
            .navigationBarsPadding()
    ) {
        AppleTopNavigationBar(
            title = topTitle,
            showBackButton = step != WizardStep.HOME,
            onBack = { handleBack() }
        )

        Column(
            modifier = Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 16.dp, vertical = 14.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp)
        ) {
            if (!vaultStatusNote.isNullOrBlank() && step != WizardStep.TRANSFER_PROGRESS) {
                DirectSwitchCard(padding = 12.dp, spacing = 6.dp) {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.SpaceBetween
                    ) {
                        Row(
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(8.dp),
                            modifier = Modifier.weight(1f)
                        ) {
                            Icon(Icons.Filled.CheckCircle, contentDescription = null, tint = DirectSwitchTheme.green)
                            Text(vaultStatusNote ?: "", fontSize = 13.sp, color = DirectSwitchTheme.textPrimary)
                        }
                        Icon(
                            imageVector = Icons.Filled.Close,
                            contentDescription = "Chiudi",
                            tint = DirectSwitchTheme.textMuted,
                            modifier = Modifier
                                .size(18.dp)
                                .clickable { vaultStatusNote = null }
                        )
                    }
                }
            }

            when (step) {
                WizardStep.HOME -> {
                    AndroidHomeView(
                        currentLanguage = currentLanguage,
                        onSelectLanguage = { lang ->
                            DirectSwitchL10n.setLanguage(context, lang)
                        },
                        resumableCheckpoint = resumableCheckpoint,
                        onResumeCheckpoint = { cp -> resumeSavedCheckpoint(cp) },
                        onDismissCheckpoint = {
                            TransferCheckpointStore.clear(context)
                            resumableCheckpoint = null
                        },
                        completedDeltaRecord = completedDeltaRecord,
                        onStartDeltaSync = { rec ->
                            requestEntryPermissionsThen(buildSenderEntryPermissions()) {
                                isReceiverFlow = false
                                pairedTargetPayload = null
                                selectedBeaconForPin = null
                                pinInput = ""
                                pinErrorNote = null
                                activeDeltaBaseline = rec
                                resetCategorySelectionsAndPreloads()
                                updateCategoriesAndTriggerPreloads(
                                    CategorySelectionState(
                                        contacts = rec.lastScope.contacts,
                                        photos = rec.lastScope.photos,
                                        videos = rec.lastScope.videos,
                                        calendars = rec.lastScope.calendars,
                                        sms = false,
                                        callLogs = rec.lastScope.callLogs,
                                        audio = rec.lastScope.audio,
                                        documents = rec.lastScope.documents,
                                        whatsAppVault = false,
                                        installedApps = false
                                    )
                                )
                                autoDiscovery.startScanningForNewDevices()
                                step = WizardStep.SENDER_CONNECT
                            }
                        },
                        onDismissDelta = {
                            CompletedMigrationStore.clear(CompletedMigrationStore.defaultFile(context.filesDir))
                            completedDeltaRecord = null
                            activeDeltaBaseline = null
                        },
                        onStartReceive = {
                            requestEntryPermissionsThen(buildReceiverEntryPermissions()) {
                                isReceiverFlow = true
                                val payload = server.startReceiverSession()
                                activeQrPayload = payload
                                autoDiscovery.startAdvertisingReceiver(payload)
                                step = WizardStep.RECEIVER_WAIT_CODE
                            }
                        },
                        onStartSend = {
                            requestEntryPermissionsThen(buildSenderEntryPermissions()) {
                                isReceiverFlow = false
                                activeDeltaBaseline = null
                                pairedTargetPayload = null
                                selectedBeaconForPin = null
                                pinInput = ""
                                pinErrorNote = null
                                resetCategorySelectionsAndPreloads()
                                autoDiscovery.startScanningForNewDevices()
                                step = WizardStep.SENDER_CONNECT
                            }
                        }
                    )
                }

                WizardStep.RECEIVER_WAIT_CODE -> {
                    ReceiverPairingWizardView(
                        qrPayload = activeQrPayload,
                        pairingPin = activePairingPin,
                        useHotspot = useOffline5GhzHotspot,
                        hotspotNote = hotspotStatusNote,
                        onToggleHotspot = { enabled ->
                            useOffline5GhzHotspot = enabled
                            if (enabled) {
                                hotspotController.startHotspot { ssid, pass, err ->
                                    if (err != null) {
                                        useOffline5GhzHotspot = false
                                        hotspotStatusNote = err
                                    } else {
                                        hotspotStatusNote = "Rete 5GHz pronta: $ssid"
                                    }
                                    val payload = server.startReceiverSession(ssid, pass)
                                    activeQrPayload = payload
                                    autoDiscovery.startAdvertisingReceiver(payload)
                                }
                            } else {
                                hotspotController.stopHotspot()
                                hotspotStatusNote = null
                                val payload = server.startReceiverSession()
                                activeQrPayload = payload
                                autoDiscovery.startAdvertisingReceiver(payload)
                            }
                        },
                        onCancel = { resetAndGoHome() }
                    )
                }

                WizardStep.RECEIVER_CONNECTED -> {
                    ReceiverConnectedWizardView(
                        peerDeviceName = serverProgress.peerDeviceName,
                        onCancel = { resetAndGoHome() }
                    )
                }

                WizardStep.SENDER_CONNECT -> {
                    SenderConnectWizardView(
                        discoveredDevices = discoveredDevices,
                        selectedBeacon = selectedBeaconForPin,
                        pinInput = pinInput,
                        isPinPairingBusy = isPinPairingBusy,
                        errorNote = pinErrorNote,
                        networkDiagnostic = clientNetworkDiagnostic,
                        showCameraScanner = showCameraScanner,
                        manualQrInput = manualQrInput,
                        onSelectBeacon = { beacon ->
                            selectedBeaconForPin = beacon
                            pinErrorNote = null
                            showCameraScanner = false
                        },
                        onPinChange = { raw ->
                            val clean = raw.filter { it.isDigit() }.take(6)
                            pinInput = clean
                            pinErrorNote = null
                        },
                        onConfirmPin = {
                            val beacon = selectedBeaconForPin ?: return@SenderConnectWizardView
                            if (pinInput.length != 6 || isPinPairingBusy) return@SenderConnectWizardView
                            isPinPairingBusy = true
                            pinErrorNote = null
                            scope.launch {
                                val res = client.pairWithBeaconUsingPin(beacon, pinInput)
                                isPinPairingBusy = false
                                res.onSuccess { paired ->
                                    autoDiscovery.stopScanning()
                                    pairedTargetPayload = paired
                                    scope.launch { client.sendPairAck(paired) }
                                    step = WizardStep.SENDER_SELECT_CATEGORIES
                                }.onFailure { err ->
                                    pinErrorNote = err.localizedMessage ?: "Codice errato o scaduto."
                                }
                            }
                        },
                        onToggleCamera = {
                            if (showCameraScanner) {
                                showCameraScanner = false
                            } else {
                                requestSpecificPermissionsThen(listOf(Manifest.permission.CAMERA)) {
                                    if (ContextCompat.checkSelfPermission(context, Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED) {
                                        showCameraScanner = true
                                    } else {
                                        pinErrorNote = DirectSwitchL10n.tr(
                                            "Permesso Fotocamera necessario per inquadrare il codice QR.",
                                            en = "Camera permission is required to scan the QR code.",
                                            fr = "L'autorisation Appareil photo est requise pour scanner le code QR."
                                        )
                                    }
                                }
                            }
                        },
                        onQrScanned = { raw ->
                            runCatching { QrPairingPayload.fromJson(raw) }
                                .onSuccess { paired ->
                                    showCameraScanner = false
                                    autoDiscovery.stopScanning()
                                    pinErrorNote = null
                                    pairedTargetPayload = paired
                                    scope.launch { client.sendPairAck(paired) }
                                    step = WizardStep.SENDER_SELECT_CATEGORIES
                                }
                                .onFailure {
                                    pinErrorNote = "Codice QR non riconosciuto."
                                }
                        },
                        onManualInputChange = {
                            manualQrInput = it
                            pinErrorNote = null
                        },
                        onApplyManualCode = {
                            runCatching { QrPairingPayload.fromJson(manualQrInput) }
                                .onSuccess { paired ->
                                    autoDiscovery.stopScanning()
                                    pinErrorNote = null
                                    pairedTargetPayload = paired
                                    scope.launch { client.sendPairAck(paired) }
                                    step = WizardStep.SENDER_SELECT_CATEGORIES
                                }
                                .onFailure {
                                    pinErrorNote = "Codice manuale non valido."
                                }
                        },
                        onRetryNetwork = {
                            pinErrorNote = null
                            autoDiscovery.startScanningForNewDevices()
                            val beacon = selectedBeaconForPin
                            if (beacon != null && pinInput.length == 6 && !isPinPairingBusy) {
                                isPinPairingBusy = true
                                scope.launch {
                                    val res = client.pairWithBeaconUsingPin(beacon, pinInput)
                                    isPinPairingBusy = false
                                    res.onSuccess { paired ->
                                        autoDiscovery.stopScanning()
                                        pairedTargetPayload = paired
                                        scope.launch { client.sendPairAck(paired) }
                                        step = WizardStep.SENDER_SELECT_CATEGORIES
                                    }.onFailure { err ->
                                        pinErrorNote = err.localizedMessage ?: "Codice errato o scaduto."
                                    }
                                }
                            }
                        }
                    )
                }

                WizardStep.SENDER_SELECT_CATEGORIES -> {
                    val target = pairedTargetPayload
                    if (target != null) {
                        SenderCategoriesWizardView(
                            pairedPayload = target,
                            summary = scanSummary,
                            categories = categories,
                            calendarsUpToTodayOnly = calendarsUpToTodayOnly,
                            smsUpToTodayOnly = smsUpToTodayOnly,
                            mediaFilters = mediaFilters,
                            availablePhotoAlbums = availablePhotoAlbums,
                            contactsPreload = contactsPreload,
                            photosPreload = photosPreload,
                            videosPreload = videosPreload,
                            calendarsSync = calendarsSync,
                            smsSync = smsSync,
                            audioFilesCount = audioFilesCount,
                            isLoadingAudio = isLoadingAudio,
                            callLogsCount = callLogsCount,
                            isLoadingCallLogs = isLoadingCallLogs,
                            stagedPasswordCsvCount = stagedPasswordCsvFiles.size,
                            detectedAppsCatalog = detectedAppsCatalog,
                            groupedAppCategories = groupedAppCategories,
                            deselectedAppPackages = deselectedAppPackages,
                            extraSelectedCuratedApps = extraSelectedCuratedApps,
                            isLoadingApps = isLoadingAppsCatalog,
                            vaultStatusNote = vaultStatusNote,
                            onUpdateCategories = { updateCategoriesAndTriggerPreloads(it) },
                            onToggleCalendarsUpToToday = { calendarsUpToTodayOnly = it },
                            onToggleSmsUpToToday = { smsUpToTodayOnly = it },
                            onFiltersChange = { mediaFilters = it },
                            onRequestContactsPermission = {
                                requestSpecificPermissionsThen(listOf(Manifest.permission.READ_CONTACTS, Manifest.permission.WRITE_CONTACTS)) { startContactsPreload() }
                            },
                            onRequestPhotosPermission = {
                                val photoPerms = buildList {
                                    when {
                                        Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE -> {
                                            add(Manifest.permission.READ_MEDIA_IMAGES)
                                            add(Manifest.permission.READ_MEDIA_VISUAL_USER_SELECTED)
                                        }
                                        Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU ->
                                            add(Manifest.permission.READ_MEDIA_IMAGES)
                                        else ->
                                            add(Manifest.permission.READ_EXTERNAL_STORAGE)
                                    }
                                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                                        add(Manifest.permission.ACCESS_MEDIA_LOCATION)
                                    }
                                }
                                requestSpecificPermissionsThen(photoPerms) { startPhotosPreload() }
                            },
                            onRequestVideosPermission = {
                                val videoPerms = buildList {
                                    when {
                                        Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE -> {
                                            add(Manifest.permission.READ_MEDIA_VIDEO)
                                            add(Manifest.permission.READ_MEDIA_VISUAL_USER_SELECTED)
                                        }
                                        Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU ->
                                            add(Manifest.permission.READ_MEDIA_VIDEO)
                                        else ->
                                            add(Manifest.permission.READ_EXTERNAL_STORAGE)
                                    }
                                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                                        add(Manifest.permission.ACCESS_MEDIA_LOCATION)
                                    }
                                }
                                requestSpecificPermissionsThen(videoPerms) { startVideosPreload() }
                            },
                            onRequestCalendarsPermission = {
                                requestSpecificPermissionsThen(listOf(Manifest.permission.READ_CALENDAR, Manifest.permission.WRITE_CALENDAR)) { refreshCalendarsSync() }
                            },
                            onRequestSmsPermission = {
                                requestSpecificPermissionsThen(listOf(Manifest.permission.READ_SMS)) { refreshSmsSync() }
                            },
                            onRequestAudioPermission = {
                                requestSpecificPermissionsThen(listOf(AudioAndMemoMigrator.requiredReadPermission())) { refreshAudioSync() }
                            },
                            onRequestCallLogsPermission = {
                                requestSpecificPermissionsThen(listOf(Manifest.permission.READ_CALL_LOG)) { refreshCallLogsSync() }
                            },
                            onReloadContacts = { startContactsPreload() },
                            onReloadPhotos = { startPhotosPreload() },
                            onReloadVideos = { startVideosPreload() },
                            onRefreshCalendars = { refreshCalendarsSync() },
                            onRefreshSms = { refreshSmsSync() },
                            onReloadAudio = { refreshAudioSync() },
                            onReloadCallLogs = { refreshCallLogsSync() },
                            onPickPasswordCsv = {
                                passwordCsvPickerLauncher.launch(arrayOf("text/csv", "text/comma-separated-values", "text/plain", "*/*"))
                            },
                            onToggleExtraCuratedApp = { extraApp ->
                                extraSelectedCuratedApps = if (extraSelectedCuratedApps.any { it.packageName == extraApp.packageName }) {
                                    extraSelectedCuratedApps.filterNot { it.packageName == extraApp.packageName }
                                } else {
                                    extraSelectedCuratedApps + extraApp
                                }
                            },
                            onToggleSingleApp = { app ->
                                deselectedAppPackages = if (app.packageName in deselectedAppPackages) {
                                    deselectedAppPackages - app.packageName
                                } else {
                                    deselectedAppPackages + app.packageName
                                }
                            },
                            onToggleAppCategoryAll = { group, currentlyAllSelected ->
                                val pkgs = group.apps.map { it.packageName }.toSet()
                                deselectedAppPackages = if (currentlyAllSelected) {
                                    deselectedAppPackages + pkgs
                                } else {
                                    deselectedAppPackages - pkgs
                                }
                            },
                            onToggleAllDetectedApps = { currentlyAllSelected ->
                                deselectedAppPackages = if (currentlyAllSelected) {
                                    detectedAppsCatalog.map { it.packageName }.toSet()
                                } else {
                                    emptySet()
                                }
                            },
                            onRefreshApps = { loadInstalledAppsCatalog() },
                            onPickFolderTree = { folderTreePickerLauncher.launch(null) },
                            onToggleLocationSelection = { locId, selected ->
                                scope.launch {
                                    withContext(Dispatchers.IO) {
                                        DocumentsAndWhatsAppScanner.setLocationSelected(context, locId, selected)
                                    }
                                    scanSummary = withContext(Dispatchers.IO) { DeviceDataAnalyzer.scanSummary(context) }
                                }
                            },
                            onRemoveSafLocation = { locId ->
                                scope.launch {
                                    withContext(Dispatchers.IO) {
                                        DocumentsAndWhatsAppScanner.removePersistedFolderTree(context, locId)
                                    }
                                    scanSummary = withContext(Dispatchers.IO) { DeviceDataAnalyzer.scanSummary(context) }
                                }
                            },
                            onRefreshDocumentCheck = {
                                scope.launch {
                                    scanSummary = withContext(Dispatchers.IO) { DeviceDataAnalyzer.scanSummary(context) }
                                }
                            },
                            onClearPickedDocuments = {
                                scope.launch {
                                    withContext(Dispatchers.IO) {
                                        DocumentsAndWhatsAppScanner.clearPickedDocumentsAndFolders(context)
                                    }
                                    vaultStatusNote = null
                                    scanSummary = withContext(Dispatchers.IO) { DeviceDataAnalyzer.scanSummary(context) }
                                }
                            },
                            onChangeDevice = {
                                val previousTarget = pairedTargetPayload
                                if (previousTarget != null) {
                                    scope.launch { client.sendPairReset(previousTarget) }
                                }
                                pairedTargetPayload = null
                                pinInput = ""
                                autoDiscovery.startScanningForNewDevices()
                                step = WizardStep.SENDER_CONNECT
                            },
                            activeDeltaBaseline = activeDeltaBaseline,
                            forceBatteryTriage = forceBatteryTriage,
                            smartCleanOptions = smartCleanOptions,
                            convertHeicToJpeg = convertHeicToJpeg,
                            isLaunchingTransfer = isLaunchingTransfer,
                            onToggleForceBatteryTriage = { forceBatteryTriage = it },
                            onSmartCleanChange = { smartCleanOptions = it },
                            onToggleConvertHeic = { convertHeicToJpeg = it },
                            onClearDeltaBaseline = { activeDeltaBaseline = null },
                            onStartTransfer = {
                                if (isLaunchingTransfer) return@SenderCategoriesWizardView
                                isLaunchingTransfer = true
                                if (categories.documents) {
                                    scope.launch {
                                        val precheck = withContext(Dispatchers.IO) {
                                            DocumentsAndWhatsAppScanner.inspectPreTransferDocuments(
                                                context = context,
                                                includeDocuments = true,
                                                includeWhatsAppVault = false
                                            )
                                        }
                                        val missingAllFiles =
                                            Build.VERSION.SDK_INT >= Build.VERSION_CODES.R && !precheck.hasAllFilesAccess
                                        if (missingAllFiles || precheck.totalFiles == 0) {
                                            isLaunchingTransfer = false
                                            pendingDocPrecheckReport = precheck
                                        } else {
                                            launchSenderTransfer(target)
                                        }
                                    }
                                } else {
                                    launchSenderTransfer(target)
                                }
                            }
                        )
                    }
                }

                WizardStep.TRANSFER_PREPARING -> {
                    TransferPreparationWizardView(
                        progress = if (isReceiverFlow) serverProgress else clientProgress,
                        isReceiver = isReceiverFlow,
                        onPreparationCompleted = { client.markPreparationAnimationCompleted() },
                        onCancel = { resetAndGoHome() }
                    )
                }

                WizardStep.TRANSFER_PROGRESS -> {
                    TransferProgressWizardView(
                        progress = if (isReceiverFlow) serverProgress else clientProgress,
                        isReceiver = isReceiverFlow,
                        networkDiagnostic = if (isReceiverFlow) null else clientNetworkDiagnostic,
                        onRetryNetwork = {
                            val target = pairedTargetPayload
                            if (!isReceiverFlow && target != null) {
                                val cp = TransferCheckpointStore.load(context)?.takeIf { it.sessionId == target.sessionId }
                                launchSenderTransfer(target, resumeCheckpoint = cp)
                            }
                        },
                        onApplySpaceRelief = { action -> applySpaceReliefAndRestart(action) },
                        onRetrySkippedOnly = { ids ->
                            val target = pairedTargetPayload
                            if (!isReceiverFlow && target != null && ids.isNotEmpty()) {
                                launchSenderTransfer(target, onlyRetryItemIds = ids.toSet())
                            }
                        },
                        onFinish = { resetAndGoHome() }
                    )
                }
            }
        }
    }

    val activePrecheck = pendingDocPrecheckReport
    val activePrecheckTarget = pairedTargetPayload
    if (activePrecheck != null && activePrecheckTarget != null) {
        val missingAllFiles = Build.VERSION.SDK_INT >= Build.VERSION_CODES.R && !activePrecheck.hasAllFilesAccess
        val selectedLocations = activePrecheck.locationSummaries.filter { it.isSelected }
        val accessibleLocations = selectedLocations.filter { it.isAccessible }
        val noneSelected = activePrecheck.locationSummaries.isNotEmpty() && selectedLocations.isEmpty()
        AlertDialog(
            onDismissRequest = { pendingDocPrecheckReport = null },
            containerColor = DirectSwitchTheme.cardSurface,
            title = {
                Text(
                    text = DirectSwitchL10n.tr("Controllo posizioni sul telefono", en = "Device storage locations check", fr = "Vérification des emplacements"),
                    fontWeight = FontWeight.Bold,
                    color = DirectSwitchTheme.textPrimary
                )
            },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text(
                        text = when {
                            noneSelected -> DirectSwitchL10n.tr(
                                "Nessuna posizione è selezionata con la spunta. Seleziona almeno una posizione da trasferire nell'elenco oppure aggiungine un'altra.",
                                en = "No storage location is checked. Check at least one location to copy or add another one.",
                                fr = "Aucun emplacement n'est coché. Cochez au moins un emplacement ou ajoutez-en un autre."
                            )
                            missingAllFiles -> DirectSwitchL10n.tr(
                                "Per leggere e copiare le posizioni intere del telefono (Memoria interna, Download, Documenti, Scheda SD) ricreandole identiche sul nuovo telefono, attiva «Accesso a tutti i file».",
                                en = "To read and copy full storage locations (Internal storage, Downloads, Documents, SD card) keeping folder structure intact, enable 'All files access'.",
                                fr = "Pour lire et copier les emplacements complets (Stockage interne, Téléchargements, Documents, SD), activez « Accès à tous les fichiers »."
                            )
                            activePrecheck.totalFiles == 0 -> DirectSwitchL10n.tr(
                                "Nessun documento o file rilevato nelle posizioni selezionate al momento. Puoi aggiungere un'altra posizione (es. SD, USB o Drive) oppure continuare comunque.",
                                en = "No files found in the selected locations yet. Add another location (SD, USB, Drive) or continue anyway.",
                                fr = "Aucun fichier trouvé dans les emplacements sélectionnés. Ajoutez un autre emplacement ou continuez."
                            )
                            else -> DirectSwitchL10n.tr(
                                "Pronte ${maxOf(1, accessibleLocations.size)} posizioni selezionate (${activePrecheck.totalFiles} file in ${activePrecheck.folderSummaries.size} cartelle).",
                                en = "${maxOf(1, accessibleLocations.size)} locations ready (${activePrecheck.totalFiles} files in ${activePrecheck.folderSummaries.size} folders).",
                                fr = "${maxOf(1, accessibleLocations.size)} emplacements prêts (${activePrecheck.totalFiles} fichiers dans ${activePrecheck.folderSummaries.size} dossiers)."
                            )
                        },
                        fontSize = 13.sp,
                        color = DirectSwitchTheme.textSecondary
                    )
                    if (activePrecheck.locationSummaries.isNotEmpty()) {
                        Text(
                            text = DirectSwitchL10n.tr("Posizioni: ", en = "Locations: ", fr = "Emplacements : ") +
                                activePrecheck.locationSummaries.joinToString(" • ") {
                                    val prefix = if (it.isSelected) "✓ " else "○ "
                                    if (it.isAccessible) "$prefix${it.locationName} (${it.fileCount} ${DirectSwitchL10n.tr("file", en = "files", fr = "fichiers")})"
                                    else "$prefix${it.locationName} (${DirectSwitchL10n.tr("accesso richiesto", en = "access required", fr = "accès requis")})"
                                },
                            fontSize = 12.sp,
                            fontWeight = FontWeight.Medium,
                            color = DirectSwitchTheme.teal
                        )
                    }
                }
            },
            confirmButton = {
                if (missingAllFiles) {
                    TextButton(
                        onClick = {
                            pendingDocPrecheckReport = null
                            DocumentsAndWhatsAppScanner.openAllFilesAccessSettings(context)
                        }
                    ) {
                        Text(DirectSwitchL10n.tr("Autorizza accesso completo", en = "Allow full access", fr = "Autoriser l'accès complet"), fontWeight = FontWeight.Bold, color = DirectSwitchTheme.blue)
                    }
                } else {
                    TextButton(
                        onClick = {
                            pendingDocPrecheckReport = null
                            folderTreePickerLauncher.launch(null)
                        }
                    ) {
                        Text(DirectSwitchL10n.tr("Autorizza posizione", en = "Authorize location", fr = "Autoriser l'emplacement"), fontWeight = FontWeight.Bold, color = DirectSwitchTheme.blue)
                    }
                }
            },
            dismissButton = {
                Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                    if (missingAllFiles) {
                        TextButton(
                            onClick = {
                                pendingDocPrecheckReport = null
                                folderTreePickerLauncher.launch(null)
                            }
                        ) {
                            Text(DirectSwitchL10n.tr("Autorizza posizione", en = "Authorize location", fr = "Autoriser l'emplacement"), color = DirectSwitchTheme.blue)
                        }
                    }
                    TextButton(
                        onClick = { launchSenderTransfer(activePrecheckTarget) }
                    ) {
                        Text(DirectSwitchL10n.tr("Continua lo stesso"), color = DirectSwitchTheme.textSecondary)
                    }
                }
            }
        )
    }
}

// MARK: - 1. Home pulita (solo Invia sopra e Ricevi sotto, sottotitoli dentro ⓘ)

@Composable
private fun AndroidHomeView(
    currentLanguage: DirectSwitchLanguage,
    onSelectLanguage: (DirectSwitchLanguage) -> Unit,
    resumableCheckpoint: TransferCheckpointRecord?,
    onResumeCheckpoint: (TransferCheckpointRecord) -> Unit,
    onDismissCheckpoint: () -> Unit,
    completedDeltaRecord: CompletedMigrationRecord?,
    onStartDeltaSync: (CompletedMigrationRecord) -> Unit,
    onDismissDelta: () -> Unit,
    onStartReceive: () -> Unit,
    onStartSend: () -> Unit
) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.End
    ) {
        LanguageSelectorChip(
            currentLanguage = currentLanguage,
            onSelectLanguage = onSelectLanguage
        )
    }

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(top = 6.dp, bottom = 10.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        DirectSwitchAppleEmblem(size = 88.dp)

        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(6.dp)
        ) {
            Text(
                text = "DirectSwitch",
                fontSize = 29.sp,
                fontWeight = FontWeight.Bold,
                color = DirectSwitchTheme.textPrimary
            )
            InfoCircleButton(
                title = "DirectSwitch",
                message = DirectSwitchL10n.tr(
                    "Copia i tuoi dati senza formattare: trasferisce rubrica, foto, video 4K, calendari, SMS, chiamate, audio, documenti e chat WhatsApp direttamente tra due telefoni già configurati, via Wi-Fi locale o Hotspot 5GHz senza passare dal cloud.",
                    en = "Copy your data without resetting: transfers contacts, photos, 4K videos, calendars, SMS, call logs, audio, documents and WhatsApp chats directly between two already set-up phones over local Wi-Fi or 5GHz Hotspot.",
                    fr = "Copiez vos données sans réinitialiser : contacts, photos, vidéos 4K, calendriers, SMS, appels, audio, documents et WhatsApp directement en Wi-Fi local ou partage 5 GHz."
                )
            )
        }
    }

    if (resumableCheckpoint != null) {
        ResumableCheckpointCard(
            checkpoint = resumableCheckpoint,
            onResume = { onResumeCheckpoint(resumableCheckpoint) },
            onDismiss = onDismissCheckpoint
        )
    } else if (completedDeltaRecord != null) {
        DeltaCatchUpCard(
            record = completedDeltaRecord,
            onStartDeltaSync = { onStartDeltaSync(completedDeltaRecord) },
            onDismiss = onDismissDelta
        )
    }

    // Sezione 1 (SOPRA): Invia (freccia verso destra ->, sottotitolo dentro ⓘ)
    DirectSwitchCard {
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.SpaceBetween
        ) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                AppleSettingsIcon(icon = Icons.AutoMirrored.Filled.ArrowForward, color = DirectSwitchTheme.blue)
                Text(
                    text = DirectSwitchL10n.tr("Invia"),
                    fontSize = 19.sp,
                    fontWeight = FontWeight.Bold,
                    color = DirectSwitchTheme.textPrimary
                )
            }
            InfoCircleButton(
                title = DirectSwitchL10n.tr("Invia"),
                message = DirectSwitchL10n.tr(
                    "Invia i dati da questo telefono direttamente senza cavo all'altro telefono (Android o iPhone) dove hai aperto 'Ricevi'.",
                    en = "Send data wirelessly from this phone directly to your other phone (Android or iPhone) where 'Receive' is open.",
                    fr = "Envoyez vos données sans fil vers votre autre téléphone (Android ou iPhone) où « Recevoir » est ouvert."
                )
            )
        }

        DirectSwitchPrimaryButton(
            text = DirectSwitchL10n.tr("Invia"),
            onClick = onStartSend,
            containerColor = DirectSwitchTheme.blue
        )
    }

    // Sezione 2 (SOTTO): Ricevi (SOLTANTO la freccia verso sinistra <-, sottotitolo dentro ⓘ)
    DirectSwitchCard {
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.SpaceBetween
        ) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                AppleSettingsIcon(icon = Icons.AutoMirrored.Filled.ArrowBack, color = DirectSwitchTheme.teal)
                Text(
                    text = DirectSwitchL10n.tr("Ricevi"),
                    fontSize = 19.sp,
                    fontWeight = FontWeight.Bold,
                    color = DirectSwitchTheme.textPrimary
                )
            }
            InfoCircleButton(
                title = DirectSwitchL10n.tr("Ricevi"),
                message = DirectSwitchL10n.tr(
                    "Mostra il codice monouso a 6 cifre (come 'Passa a iOS') o il codice QR per ricevere i dati dal tuo altro telefono senza cancellare nulla.",
                    en = "Show a 6-digit one-time code or QR code to receive data from your other phone without erasing anything.",
                    fr = "Affichez le code à 6 chiffres ou le code QR pour recevoir des données sans rien effacer."
                )
            )
        }

        DirectSwitchPrimaryButton(
            text = DirectSwitchL10n.tr("Ricevi"),
            onClick = onStartReceive,
            containerColor = DirectSwitchTheme.teal
        )
    }
}

// MARK: - 2A. Passo 1 Ricevente (stile "Passa a iOS": codice a 6 cifre + QR + Hotspot 5GHz)

@Composable
private fun ReceiverPairingWizardView(
    qrPayload: QrPairingPayload?,
    pairingPin: String,
    useHotspot: Boolean,
    hotspotNote: String?,
    onToggleHotspot: (Boolean) -> Unit,
    onCancel: () -> Unit
) {
    val context = LocalContext.current
    var selectedTab by remember { mutableIntStateOf(0) }
    var isDefaultSms by remember { mutableStateOf(SmsSystemScanner.isDefaultSmsApp(context)) }
    val smsRoleLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.StartActivityForResult()
    ) {
        isDefaultSms = SmsSystemScanner.isDefaultSmsApp(context)
    }

    Row(
        modifier = Modifier.fillMaxWidth(),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.SpaceBetween
    ) {
        Text(
            text = DirectSwitchL10n.tr("Passo 1 di 2", en = "Step 1 of 2", fr = "Étape 1 sur 2"),
            fontSize = 13.sp,
            fontWeight = FontWeight.SemiBold,
            color = DirectSwitchTheme.blue
        )
        InfoCircleButton(
            title = DirectSwitchL10n.tr("Come collegare i telefoni", en = "How to connect phones", fr = "Comment connecter les téléphones"),
            message = DirectSwitchL10n.tr(
                "Apri DirectSwitch sul vecchio telefono, tocca 'Invia al nuovo telefono' e digita il codice a 6 cifre mostrato qui sotto, oppure passa a 'Codice QR' per inquadrarlo (anche senza rete Wi-Fi attivando l'Hotspot 5GHz).",
                en = "Open DirectSwitch on the old phone, tap 'Send' and enter the 6-digit code shown below, or switch to 'QR Code' to scan it (even without Wi-Fi using 5GHz Hotspot).",
                fr = "Ouvrez DirectSwitch sur l'ancien téléphone, touchez « Envoyer » et saisissez le code à 6 chiffres ci-dessous, ou scannez le « Code QR »."
            )
        )
    }

    Column(
        modifier = Modifier.fillMaxWidth(),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(6.dp)
    ) {
        Text(
            text = if (selectedTab == 0) DirectSwitchL10n.tr("Inserisci il codice monouso", en = "Enter one-time code", fr = "Saisissez le code unique") else DirectSwitchL10n.tr("Inquadra il codice QR", en = "Scan QR code", fr = "Scannez le code QR"),
            fontSize = 22.sp,
            fontWeight = FontWeight.Bold,
            color = DirectSwitchTheme.textPrimary,
            textAlign = TextAlign.Center
        )
        Text(
            text = DirectSwitchL10n.tr("Apri DirectSwitch sul vecchio telefono e tocca Invia", en = "Open DirectSwitch on your old phone and tap Send", fr = "Ouvrez DirectSwitch sur l'ancien téléphone et touchez Envoyer"),
            fontSize = 14.sp,
            color = DirectSwitchTheme.textSecondary,
            textAlign = TextAlign.Center
        )
    }

    DirectSwitchCard {
        // Selettore segmentato in stile iOS
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .clip(RoundedCornerShape(10.dp))
                .background(DirectSwitchTheme.inputSurface)
                .padding(3.dp),
            horizontalArrangement = Arrangement.spacedBy(4.dp)
        ) {
            listOf(DirectSwitchL10n.tr("Codice a 6 cifre"), DirectSwitchL10n.tr("Codice QR")).forEachIndexed { idx, label ->
                val active = selectedTab == idx
                Box(
                    modifier = Modifier
                        .weight(1f)
                        .clip(RoundedCornerShape(8.dp))
                        .background(if (active) DirectSwitchTheme.cardSurface else Color.Transparent)
                        .clickable { selectedTab = idx }
                        .padding(vertical = 8.dp),
                    contentAlignment = Alignment.Center
                ) {
                    Text(
                        text = label,
                        fontSize = 13.sp,
                        fontWeight = if (active) FontWeight.SemiBold else FontWeight.Medium,
                        color = DirectSwitchTheme.textPrimary
                    )
                }
            }
        }

        if (selectedTab == 0) {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(vertical = 8.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(10.dp)
            ) {
                PassaAiOSCodeBoxes(code = pairingPin)
                if (qrPayload != null) {
                    Text(
                        text = DirectSwitchL10n.tr("Visibile come ${qrPayload.receiverName}", en = "Visible as ${qrPayload.receiverName}", fr = "Visible en tant que ${qrPayload.receiverName}"),
                        fontSize = 13.sp,
                        color = DirectSwitchTheme.textSecondary
                    )
                }
            }
        } else if (qrPayload != null) {
            val compactJson = remember(qrPayload) { qrPayload.toCompactJson() }
            val qrBitmap = remember(compactJson) { QrBitmapGenerator.generate(compactJson, 620) }
            Column(
                modifier = Modifier.fillMaxWidth(),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                if (qrBitmap != null) {
                    Image(
                        bitmap = qrBitmap.asImageBitmap(),
                        contentDescription = "QR DirectSwitch",
                        modifier = Modifier
                            .size(210.dp)
                            .clip(RoundedCornerShape(16.dp))
                            .background(Color.White)
                            .border(0.8.dp, DirectSwitchTheme.cardBorder, RoundedCornerShape(16.dp))
                            .padding(10.dp)
                    )
                }
                if (pairingPin.length == 6) {
                    Text(
                        text = DirectSwitchL10n.tr("Codice: $pairingPin", en = "Code: $pairingPin", fr = "Code : $pairingPin"),
                        fontSize = 14.sp,
                        fontWeight = FontWeight.SemiBold,
                        color = DirectSwitchTheme.blue
                    )
                }
            }
        }

        HorizontalDivider(color = DirectSwitchTheme.hairline)

        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.Center,
            verticalAlignment = Alignment.CenterVertically
        ) {
            CircularProgressIndicator(
                modifier = Modifier.size(18.dp),
                strokeWidth = 2.dp,
                color = DirectSwitchTheme.blue
            )
            Spacer(modifier = Modifier.size(10.dp))
            Text(
                text = DirectSwitchL10n.tr("In attesa di collegamento..."),
                fontSize = 14.sp,
                color = DirectSwitchTheme.textSecondary
            )
        }
    }

    // Opzioni rapide pulite (Hotspot 5GHz senza router + SMS)
    DirectSwitchCard(padding = 0.dp, spacing = 0.dp) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 14.dp, vertical = 11.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.SpaceBetween
        ) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(12.dp),
                modifier = Modifier.weight(1f)
            ) {
                AppleSettingsIcon(icon = Icons.Filled.WifiTethering, color = DirectSwitchTheme.teal)
                Column {
                    Text(DirectSwitchL10n.tr("Hotspot diretto 5GHz", en = "Direct 5GHz Hotspot", fr = "Point d'accès 5 GHz direct"), fontSize = 15.sp, fontWeight = FontWeight.Medium, color = DirectSwitchTheme.textPrimary)
                    Text(hotspotNote ?: DirectSwitchL10n.tr("Usa senza rete Wi-Fi di casa", en = "Use without a home Wi-Fi network", fr = "Utiliser sans Wi-Fi domestique"), fontSize = 12.sp, color = DirectSwitchTheme.textSecondary)
                }
            }
            Switch(
                checked = useHotspot,
                onCheckedChange = onToggleHotspot,
                colors = SwitchDefaults.colors(checkedThumbColor = Color.White, checkedTrackColor = DirectSwitchTheme.green)
            )
        }

        if (!isDefaultSms) {
            HorizontalDivider(modifier = Modifier.padding(start = 56.dp), color = DirectSwitchTheme.hairline)
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .clickable {
                        SmsSystemScanner.createDefaultSmsRoleIntent(context)?.let { smsRoleLauncher.launch(it) }
                    }
                    .padding(horizontal = 14.dp, vertical = 12.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.SpaceBetween
            ) {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(12.dp),
                    modifier = Modifier.weight(1f)
                ) {
                    AppleSettingsIcon(icon = Icons.Filled.Sms, color = DirectSwitchTheme.green)
                    Column {
                        Text(DirectSwitchL10n.tr("Salva SMS nell'app Messaggi", en = "Save SMS in Messages app", fr = "Enregistrer les SMS dans Messages"), fontSize = 15.sp, fontWeight = FontWeight.Medium, color = DirectSwitchTheme.textPrimary)
                        Text(DirectSwitchL10n.tr("Tocca per abilitare l'importazione nativa", en = "Tap to enable native SMS import", fr = "Touchez pour activer l'importation native"), fontSize = 12.sp, color = DirectSwitchTheme.blue)
                    }
                }
                Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, contentDescription = null, tint = DirectSwitchTheme.textMuted)
            }
        }
    }

    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
        val localContext = LocalContext.current
        val localLifecycle = LocalLifecycleOwner.current
        var hasAllFilesInReceiver by remember {
            mutableStateOf(DocumentsAndWhatsAppScanner.hasAllFilesAccess(localContext))
        }
        DisposableEffect(localLifecycle) {
            val observer = LifecycleEventObserver { _, event ->
                if (event == Lifecycle.Event.ON_RESUME) {
                    hasAllFilesInReceiver = DocumentsAndWhatsAppScanner.hasAllFilesAccess(localContext)
                }
            }
            localLifecycle.lifecycle.addObserver(observer)
            onDispose { localLifecycle.lifecycle.removeObserver(observer) }
        }
        if (!hasAllFilesInReceiver) {
            DirectSwitchCard(padding = 14.dp) {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .clickable {
                            DocumentsAndWhatsAppScanner.openAllFilesAccessSettings(localContext)
                        },
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.SpaceBetween
                ) {
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(12.dp),
                        modifier = Modifier.weight(1f)
                    ) {
                        AppleSettingsIcon(icon = Icons.Filled.Folder, color = DirectSwitchTheme.orange)
                        Column {
                            Text(
                                DirectSwitchL10n.tr("Ricrea posizioni e cartelle originali", en = "Restore original folders and locations", fr = "Recréer les dossiers d'origine"),
                                fontSize = 15.sp,
                                fontWeight = FontWeight.Medium,
                                color = DirectSwitchTheme.textPrimary
                            )
                            Text(
                                DirectSwitchL10n.tr("Autorizza «Accesso a tutti i file» per salvare intere posizioni nelle identiche cartelle di origine", en = "Allow 'All files access' to save locations into their exact original folders", fr = "Autorisez « Accès à tous les fichiers » pour conserver la structure des dossiers"),
                                fontSize = 12.sp,
                                color = DirectSwitchTheme.blue
                            )
                        }
                    }
                    Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, contentDescription = null, tint = DirectSwitchTheme.textMuted)
                }
            }
        }
    }

    DirectSwitchSecondaryButton(
        text = DirectSwitchL10n.tr("Annulla"),
        onClick = onCancel,
        tint = DirectSwitchTheme.textSecondary
    )
}

// MARK: - 2B. Passo 1 Mittente: Collega il nuovo telefono

@Composable
private fun SenderConnectWizardView(
    discoveredDevices: List<DiscoveryBeaconPayload>,
    selectedBeacon: DiscoveryBeaconPayload?,
    pinInput: String,
    isPinPairingBusy: Boolean,
    errorNote: String?,
    networkDiagnostic: NetworkDiagnosticVerdict?,
    showCameraScanner: Boolean,
    manualQrInput: String,
    onSelectBeacon: (DiscoveryBeaconPayload) -> Unit,
    onPinChange: (String) -> Unit,
    onConfirmPin: () -> Unit,
    onToggleCamera: () -> Unit,
    onQrScanned: (String) -> Unit,
    onManualInputChange: (String) -> Unit,
    onApplyManualCode: () -> Unit,
    onRetryNetwork: () -> Unit
) {
    var showManualInput by remember { mutableStateOf(false) }

    LaunchedEffect(discoveredDevices) {
        val current = selectedBeacon
        if (current == null) {
            if (discoveredDevices.isNotEmpty()) {
                onSelectBeacon(discoveredDevices.first())
            }
        } else {
            val updated = discoveredDevices.firstOrNull { it.representsSameDevice(current) }
            if (updated != null && updated.sessionId != current.sessionId) {
                onSelectBeacon(updated)
            }
        }
    }

    Row(
        modifier = Modifier.fillMaxWidth(),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.SpaceBetween
    ) {
        Text(DirectSwitchL10n.tr("Passo 1 di 3", en = "Step 1 of 3", fr = "Étape 1 sur 3"), fontSize = 13.sp, fontWeight = FontWeight.SemiBold, color = DirectSwitchTheme.blue)
        InfoCircleButton(
            title = DirectSwitchL10n.tr("Come collegare il nuovo telefono", en = "How to connect the new phone", fr = "Comment connecter le nouveau téléphone"),
            message = DirectSwitchL10n.tr(
                "Sul nuovo iPhone o Android apri DirectSwitch e tocca 'Ricevi'. Selezionalo qui sotto e inserisci il codice a 6 cifre, oppure usa 'Inquadra codice QR'.",
                en = "On the new iPhone or Android open DirectSwitch and tap 'Receive'. Select it below and enter the 6-digit code, or tap 'Scan QR code'.",
                fr = "Sur le nouveau téléphone ouvrez DirectSwitch et touchez « Recevoir ». Sélectionnez-le ci-dessous et saisissez le code à 6 chiffres ou scannez le QR."
            )
        )
    }

    Column(
        modifier = Modifier.fillMaxWidth(),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(4.dp)
    ) {
        Text(DirectSwitchL10n.tr("Collega il nuovo telefono", en = "Connect new phone", fr = "Connecter le nouveau téléphone"), fontSize = 22.sp, fontWeight = FontWeight.Bold, color = DirectSwitchTheme.textPrimary)
        Text(DirectSwitchL10n.tr("Seleziona il telefono rilevato o inquadra il codice QR", en = "Select the discovered phone or scan the QR code", fr = "Sélectionnez le téléphone détecté ou scannez le code QR"), fontSize = 14.sp, color = DirectSwitchTheme.textSecondary)
    }

    DirectSwitchCard {
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.SpaceBetween
        ) {
            Text(DirectSwitchL10n.tr("Telefoni vicini"), fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = DirectSwitchTheme.textPrimary)
            if (discoveredDevices.isEmpty()) {
                CircularProgressIndicator(modifier = Modifier.size(16.dp), strokeWidth = 2.dp, color = DirectSwitchTheme.blue)
            } else {
                val countLabel = if (discoveredDevices.size == 1) DirectSwitchL10n.tr("1 trovato", en = "1 found", fr = "1 trouvé") else DirectSwitchL10n.tr("${discoveredDevices.size} trovati", en = "${discoveredDevices.size} found", fr = "${discoveredDevices.size} trouvés")
                Text(countLabel, fontSize = 12.sp, fontWeight = FontWeight.SemiBold, color = DirectSwitchTheme.green)
            }
        }

        if (discoveredDevices.isEmpty()) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                AppleSettingsIcon(icon = Icons.Filled.Wifi, color = DirectSwitchTheme.blue)
                Column {
                    Text(DirectSwitchL10n.tr("Ricerca sulla rete Wi-Fi..."), fontSize = 14.sp, fontWeight = FontWeight.Medium, color = DirectSwitchTheme.textPrimary)
                    Text(DirectSwitchL10n.tr("Assicurati che 'Ricevi' sia aperto sull'altro telefono", en = "Make sure 'Receive' is open on the other phone", fr = "Assurez-vous que « Recevoir » est ouvert sur l'autre téléphone"), fontSize = 12.sp, color = DirectSwitchTheme.textSecondary)
                }
            }
        } else {
            for (beacon in discoveredDevices) {
                val isSelected = selectedBeacon?.sessionId == beacon.sessionId
                Surface(
                    onClick = { onSelectBeacon(beacon) },
                    shape = RoundedCornerShape(12.dp),
                    color = if (isSelected) DirectSwitchTheme.cardSelected else DirectSwitchTheme.inputSurface.copy(alpha = 0.7f),
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Row(
                        modifier = Modifier.padding(12.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.SpaceBetween
                    ) {
                        Row(
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(12.dp)
                        ) {
                            AppleSettingsIcon(
                                icon = if (beacon.receiverPlatform == DevicePlatform.IOS) Icons.Filled.PhoneIphone else Icons.Filled.PhoneAndroid,
                                color = if (isSelected) DirectSwitchTheme.blue else DirectSwitchTheme.indigo
                            )
                            Column {
                                Text(beacon.receiverName, fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = DirectSwitchTheme.textPrimary)
                                Text(
                                    if (beacon.receiverPlatform == DevicePlatform.IOS) DirectSwitchL10n.tr("iPhone pronto a ricevere") else DirectSwitchL10n.tr("Android pronto a ricevere"),
                                    fontSize = 12.sp,
                                    color = DirectSwitchTheme.textSecondary
                                )
                            }
                        }
                        Icon(
                            imageVector = if (isSelected) Icons.Filled.CheckCircle else Icons.AutoMirrored.Filled.KeyboardArrowRight,
                            contentDescription = null,
                            tint = if (isSelected) DirectSwitchTheme.blue else DirectSwitchTheme.textMuted
                        )
                    }
                }
            }
        }

        if (selectedBeacon != null) {
            HorizontalDivider(color = DirectSwitchTheme.hairline)
            Text(
                text = DirectSwitchL10n.tr("Inserisci il codice a 6 cifre mostrato su ${selectedBeacon.receiverName}", en = "Enter the 6-digit code shown on ${selectedBeacon.receiverName}", fr = "Saisissez le code à 6 chiffres affiché sur ${selectedBeacon.receiverName}"),
                fontSize = 13.sp,
                color = DirectSwitchTheme.textSecondary,
                modifier = Modifier.fillMaxWidth(),
                textAlign = TextAlign.Center
            )
            OutlinedTextField(
                value = pinInput,
                onValueChange = onPinChange,
                placeholder = { Text(DirectSwitchL10n.tr("Codice a 6 cifre")) },
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.NumberPassword),
                modifier = Modifier.fillMaxWidth(),
                singleLine = true,
                shape = RoundedCornerShape(12.dp)
            )
            DirectSwitchPrimaryButton(
                text = DirectSwitchL10n.tr("Continua"),
                onClick = onConfirmPin,
                enabled = pinInput.length == 6,
                isLoading = isPinPairingBusy,
                loadingText = DirectSwitchL10n.tr("Collegamento in corso...")
            )
        }
    }

    DirectSwitchCard {
        Text(DirectSwitchL10n.tr("Oppure usa la fotocamera"), fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = DirectSwitchTheme.textPrimary)
        DirectSwitchSecondaryButton(
            text = if (showCameraScanner) DirectSwitchL10n.tr("Chiudi fotocamera") else DirectSwitchL10n.tr("Inquadra codice QR"),
            onClick = onToggleCamera
        )
        if (showCameraScanner) {
            QrCameraPreviewBox(onQrScanned = onQrScanned)
        }
        TextButton(
            onClick = { showManualInput = !showManualInput },
            modifier = Modifier.fillMaxWidth()
        ) {
            Text(
                text = if (showManualInput) DirectSwitchL10n.tr("Nascondi inserimento manuale") else DirectSwitchL10n.tr("Incolla codice di collegamento"),
                fontSize = 13.sp,
                color = DirectSwitchTheme.textSecondary
            )
        }
        if (showManualInput) {
            OutlinedTextField(
                value = manualQrInput,
                onValueChange = onManualInputChange,
                placeholder = { Text(DirectSwitchL10n.tr("Incolla qui il codice")) },
                modifier = Modifier.fillMaxWidth(),
                singleLine = true,
                shape = RoundedCornerShape(12.dp)
            )
            if (manualQrInput.isNotBlank()) {
                DirectSwitchPrimaryButton(text = DirectSwitchL10n.tr("Collega"), onClick = onApplyManualCode)
            }
        }
    }

    if (!errorNote.isNullOrBlank()) {
        DirectSwitchCard(padding = 14.dp) {
            Text(errorNote, fontSize = 13.sp, fontWeight = FontWeight.Medium, color = DirectSwitchTheme.red)
        }
    }

    if (networkDiagnostic != null) {
        NetworkIsolationHotspotCard(
            verdict = networkDiagnostic,
            onRetryConnect = onRetryNetwork
        )
    }
}

// MARK: - 3B. Passo 2 Mittente: Scegli cosa copiare (tendine inline stile iPhone, tutto da spuntare)

@Composable
private fun SenderCategoriesWizardView(
    pairedPayload: QrPairingPayload,
    summary: LocalDeviceScanSummary?,
    categories: CategorySelectionState,
    calendarsUpToTodayOnly: Boolean,
    smsUpToTodayOnly: Boolean,
    mediaFilters: MediaTransferFilterOptions,
    availablePhotoAlbums: List<String>,
    contactsPreload: ContactsPreloadState,
    photosPreload: PhotosPreloadState,
    videosPreload: VideosPreloadState,
    calendarsSync: DateSyncPreloadState,
    smsSync: DateSyncPreloadState,
    audioFilesCount: Int,
    isLoadingAudio: Boolean,
    callLogsCount: Int,
    isLoadingCallLogs: Boolean,
    stagedPasswordCsvCount: Int,
    detectedAppsCatalog: List<InstalledAppRecord>,
    groupedAppCategories: List<InstalledAppCategoryGroup>,
    deselectedAppPackages: Set<String>,
    extraSelectedCuratedApps: List<InstalledAppRecord>,
    isLoadingApps: Boolean,
    vaultStatusNote: String?,
    onUpdateCategories: (CategorySelectionState) -> Unit,
    onToggleCalendarsUpToToday: (Boolean) -> Unit,
    onToggleSmsUpToToday: (Boolean) -> Unit,
    onFiltersChange: (MediaTransferFilterOptions) -> Unit,
    onRequestContactsPermission: () -> Unit,
    onRequestPhotosPermission: () -> Unit,
    onRequestVideosPermission: () -> Unit,
    onRequestCalendarsPermission: () -> Unit,
    onRequestSmsPermission: () -> Unit,
    onRequestAudioPermission: () -> Unit,
    onRequestCallLogsPermission: () -> Unit,
    onReloadContacts: () -> Unit,
    onReloadPhotos: () -> Unit,
    onReloadVideos: () -> Unit,
    onRefreshCalendars: () -> Unit,
    onRefreshSms: () -> Unit,
    onReloadAudio: () -> Unit,
    onReloadCallLogs: () -> Unit,
    onPickPasswordCsv: () -> Unit,
    onToggleExtraCuratedApp: (InstalledAppRecord) -> Unit,
    onToggleSingleApp: (InstalledAppRecord) -> Unit,
    onToggleAppCategoryAll: (InstalledAppCategoryGroup, Boolean) -> Unit,
    onToggleAllDetectedApps: (Boolean) -> Unit,
    onRefreshApps: () -> Unit,
    onPickFolderTree: () -> Unit,
    onToggleLocationSelection: (String, Boolean) -> Unit,
    onRemoveSafLocation: (String) -> Unit,
    onRefreshDocumentCheck: () -> Unit,
    onClearPickedDocuments: () -> Unit,
    onChangeDevice: () -> Unit,
    activeDeltaBaseline: CompletedMigrationRecord?,
    forceBatteryTriage: Boolean,
    smartCleanOptions: SmartCleanOptions,
    convertHeicToJpeg: Boolean,
    isLaunchingTransfer: Boolean = false,
    onToggleForceBatteryTriage: (Boolean) -> Unit,
    onSmartCleanChange: (SmartCleanOptions) -> Unit,
    onToggleConvertHeic: (Boolean) -> Unit,
    onClearDeltaBaseline: () -> Unit,
    onStartTransfer: () -> Unit
) {
    val wizardContext = LocalContext.current
    val isCrossOs = pairedPayload.receiverPlatform == DevicePlatform.IOS
    val allSelected = categories.contacts && categories.photos && categories.videos &&
        categories.calendars && categories.sms && categories.callLogs && categories.audio &&
        categories.documents && (isCrossOs || categories.whatsAppVault) && categories.installedApps
    val anySelected = categories.contacts || categories.photos || categories.videos ||
        categories.calendars || categories.sms || categories.callLogs || categories.audio ||
        categories.documents || (!isCrossOs && categories.whatsAppVault) || categories.installedApps

    Row(
        modifier = Modifier.fillMaxWidth(),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.SpaceBetween
    ) {
        Text(DirectSwitchL10n.tr("Passo 2 di 3", en = "Step 2 of 3", fr = "Étape 2 sur 3"), fontSize = 13.sp, fontWeight = FontWeight.SemiBold, color = DirectSwitchTheme.blue)
        Text(
            text = if (allSelected) DirectSwitchL10n.tr("Deseleziona tutto") else DirectSwitchL10n.tr("Seleziona tutto"),
            fontSize = 14.sp,
            fontWeight = FontWeight.SemiBold,
            color = DirectSwitchTheme.blue,
            modifier = Modifier.clickable {
                val next = !allSelected
                onUpdateCategories(
                    CategorySelectionState(
                        contacts = next,
                        photos = next,
                        videos = next,
                        calendars = next,
                        sms = next,
                        callLogs = next,
                        audio = next,
                        documents = next,
                        whatsAppVault = if (isCrossOs) false else next,
                        installedApps = next
                    )
                )
            }
        )
    }

    DirectSwitchCard(selected = true, padding = 14.dp, spacing = 10.dp) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.SpaceBetween
        ) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(10.dp),
                modifier = Modifier.weight(1f)
            ) {
                Icon(Icons.Filled.CheckCircle, contentDescription = null, tint = DirectSwitchTheme.green, modifier = Modifier.size(28.dp))
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(6.dp)
                ) {
                    Text(
                        DirectSwitchL10n.tr("Collegato a ${pairedPayload.receiverName}", en = "Connected to ${pairedPayload.receiverName}", fr = "Connecté à ${pairedPayload.receiverName}"),
                        fontSize = 15.sp,
                        fontWeight = FontWeight.SemiBold,
                        color = DirectSwitchTheme.textPrimary
                    )
                    InfoCircleButton(
                        title = DirectSwitchL10n.tr("Stato collegamento", en = "Connection status", fr = "État de la connexion"),
                        message = DirectSwitchL10n.tr("Collegamento diretto attivo e pronto al trasferimento completo dei dati selezionati senza resettare il telefono.", en = "Direct link active and ready to copy all selected data without resetting your phone.", fr = "Connexion directe active et prête à copier toutes les données sans réinitialiser.")
                    )
                }
            }
            Text(
                text = DirectSwitchL10n.tr("Cambia"),
                fontSize = 13.sp,
                fontWeight = FontWeight.SemiBold,
                color = DirectSwitchTheme.blue,
                modifier = Modifier.clickable(onClick = onChangeDevice)
            )
        }
    }

    Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
        Text(DirectSwitchL10n.tr("Cosa inviare", en = "What to send", fr = "Quoi envoyer"), fontSize = 20.sp, fontWeight = FontWeight.Bold, color = DirectSwitchTheme.textPrimary)
        Text(
            text = DirectSwitchL10n.tr("Spunta ogni voce per aprire la configurazione del passaggio al nuovo telefono.", en = "Check each item to configure what copies to the new phone.", fr = "Cochez chaque élément pour configurer le transfert vers le nouveau téléphone."),
            fontSize = 12.5.sp,
            color = DirectSwitchTheme.textSecondary
        )
    }

    val contactsTotal = maxOf(contactsPreload.totalCount, summary?.contactsCount ?: 0)
    val contactsLoaded = if (contactsPreload.isCompleted) contactsTotal else contactsPreload.loadedCount
    CategoryDropdownCard(
        icon = Icons.Filled.Contacts,
        iconColor = DirectSwitchTheme.blue,
        title = DirectSwitchL10n.tr("Rubrica contatti"),
        countBadge = if (contactsTotal > 0) "$contactsTotal ${DirectSwitchL10n.tr("contatti")}" else null,
        checked = categories.contacts,
        onCheckedChange = { onUpdateCategories(categories.copy(contacts = it)) }
    ) {
        ProgressivePreloadDropdownBody(
            hasPermission = ContactsSmartMerger.hasReadPermission(wizardContext),
            permissionTitle = DirectSwitchL10n.tr("Permesso Contatti richiesto per preparare la rubrica.", en = "Contacts permission required to prepare your address book.", fr = "Autorisation Contacts requise pour préparer le carnet d'adresses."),
            onRequestPermission = onRequestContactsPermission,
            isLoading = contactsPreload.isLoading,
            loadedCount = contactsLoaded,
            totalCount = contactsTotal,
            loadingLabel = DirectSwitchL10n.tr("Precaricamento rubrica: $contactsLoaded / ${maxOf(contactsLoaded, contactsTotal)} contatti", en = "Loading contacts: $contactsLoaded / ${maxOf(contactsLoaded, contactsTotal)}", fr = "Chargement contacts : $contactsLoaded / ${maxOf(contactsLoaded, contactsTotal)}"),
            readyLabel = DirectSwitchL10n.tr("$contactsTotal contatti idonei al trasferimento", en = "$contactsTotal contacts ready to transfer", fr = "$contactsTotal contacts prêts à transférer"),
            detailLabel = DirectSwitchL10n.tr("Include numeri con etichette, foto profilo, email, indirizzi e compleanni con unione duplicati.", en = "Includes phone labels, profile photos, emails, addresses and birthdays with duplicate merge.", fr = "Inclut numéros, photos, e-mails, adresses et anniversaires avec fusion des doublons."),
            accentColor = DirectSwitchTheme.blue,
            onReload = onReloadContacts
        )
    }

    val photosTotal = maxOf(photosPreload.totalCount, summary?.photosCount ?: 0)
    val photosLoaded = if (photosPreload.isCompleted) photosTotal else photosPreload.loadedCount
    val photosAlbums = maxOf(photosPreload.albumsCount, summary?.photoAlbumsCount ?: 0)
    val photosBytes = maxOf(photosPreload.estimatedBytes, summary?.photosBytes ?: 0L)
    CategoryDropdownCard(
        icon = Icons.Filled.Image,
        iconColor = DirectSwitchTheme.orange,
        title = DirectSwitchL10n.tr("Foto e Album"),
        countBadge = if (photosTotal > 0) "$photosTotal ${DirectSwitchL10n.tr("foto")} • ${formatMb(photosBytes)}" else null,
        checked = categories.photos,
        onCheckedChange = { onUpdateCategories(categories.copy(photos = it)) }
    ) {
        ProgressivePreloadDropdownBody(
            hasPermission = MediaExifScannerAndImporter.hasPhotoPermission(wizardContext),
            permissionTitle = DirectSwitchL10n.tr("Permesso Foto richiesto per preparare immagini e album.", en = "Photos permission required to prepare images and albums.", fr = "Autorisation Photos requise pour préparer les images et albums."),
            onRequestPermission = onRequestPhotosPermission,
            isLoading = photosPreload.isLoading,
            loadedCount = photosLoaded,
            totalCount = photosTotal,
            loadingLabel = DirectSwitchL10n.tr("Verifica foto idonee: $photosLoaded / ${maxOf(photosLoaded, photosTotal)}", en = "Checking eligible photos: $photosLoaded / ${maxOf(photosLoaded, photosTotal)}", fr = "Vérification des photos : $photosLoaded / ${maxOf(photosLoaded, photosTotal)}"),
            readyLabel = DirectSwitchL10n.tr("$photosTotal foto idonee al trasferimento", en = "$photosTotal eligible photos ready to transfer", fr = "$photosTotal photos prêtes au transfert"),
            detailLabel = DirectSwitchL10n.tr("$photosAlbums album rilevati • ${formatMb(photosBytes)} in qualità originale.", en = "$photosAlbums albums found • ${formatMb(photosBytes)} in original quality.", fr = "$photosAlbums albums détectés • ${formatMb(photosBytes)} en qualité d'origine."),
            accentColor = DirectSwitchTheme.orange,
            onReload = onReloadPhotos
        )
        if (MediaExifScannerAndImporter.hasPhotoPermission(wizardContext)) {
            PhotoFilterChipsBar(
                filters = mediaFilters,
                availableAlbums = availablePhotoAlbums,
                onFiltersChange = onFiltersChange
            )
        }
    }

    val videosTotal = maxOf(videosPreload.totalCount, summary?.videosCount ?: 0)
    val videosLoaded = if (videosPreload.isCompleted) videosTotal else videosPreload.loadedCount
    val videosBytes = maxOf(videosPreload.estimatedBytes, summary?.videosBytes ?: 0L)
    CategoryDropdownCard(
        icon = Icons.Filled.Videocam,
        iconColor = DirectSwitchTheme.red,
        title = DirectSwitchL10n.tr("Video originali"),
        countBadge = if (videosTotal > 0) "$videosTotal ${DirectSwitchL10n.tr("video")} • ${formatMb(videosBytes)}" else null,
        checked = categories.videos,
        onCheckedChange = { onUpdateCategories(categories.copy(videos = it)) }
    ) {
        ProgressivePreloadDropdownBody(
            hasPermission = MediaExifScannerAndImporter.hasVideoPermission(wizardContext),
            permissionTitle = DirectSwitchL10n.tr("Permesso Video richiesto per preparare i filmati originali.", en = "Videos permission required to prepare original clips.", fr = "Autorisation Vidéos requise pour préparer les vidéos."),
            onRequestPermission = onRequestVideosPermission,
            isLoading = videosPreload.isLoading,
            loadedCount = videosLoaded,
            totalCount = videosTotal,
            loadingLabel = DirectSwitchL10n.tr("Verifica video idonei: $videosLoaded / ${maxOf(videosLoaded, videosTotal)}", en = "Checking eligible videos: $videosLoaded / ${maxOf(videosLoaded, videosTotal)}", fr = "Vérification des vidéos : $videosLoaded / ${maxOf(videosLoaded, videosTotal)}"),
            readyLabel = DirectSwitchL10n.tr("$videosTotal video idonei al trasferimento", en = "$videosTotal eligible videos ready to transfer", fr = "$videosTotal vidéos prêtes au transfert"),
            detailLabel = DirectSwitchL10n.tr("Qualità 4K e Slow-Motion preservata • ${formatMb(videosBytes)}.", en = "4K & Slow-Motion quality preserved • ${formatMb(videosBytes)}.", fr = "Qualité 4K et Ralenti préservée • ${formatMb(videosBytes)}."),
            accentColor = DirectSwitchTheme.red,
            onReload = onReloadVideos
        )
        if (MediaExifScannerAndImporter.hasVideoPermission(wizardContext)) {
            VideoFilterChipsBar(
                filters = mediaFilters,
                onFiltersChange = onFiltersChange
            )
        }
    }

    val activeCalCount = if (calendarsUpToTodayOnly) {
        calendarsSync.totalUpToTodayCount
    } else {
        maxOf(calendarsSync.totalAllCount, summary?.calendarEventsCount ?: 0)
    }
    CategoryDropdownCard(
        icon = Icons.Filled.CalendarMonth,
        iconColor = DirectSwitchTheme.indigo,
        title = DirectSwitchL10n.tr("Calendari"),
        countBadge = if (activeCalCount > 0) "$activeCalCount ${DirectSwitchL10n.tr("eventi")}" else null,
        checked = categories.calendars,
        onCheckedChange = { onUpdateCategories(categories.copy(calendars = it)) }
    ) {
        DateSyncDropdownBody(
            hasPermission = CalendarMigrator.hasReadPermission(wizardContext),
            permissionTitle = DirectSwitchL10n.tr("Permesso Calendario richiesto per leggere gli eventi.", en = "Calendar permission required to read events.", fr = "Autorisation Calendrier requise pour lire les événements."),
            onRequestPermission = onRequestCalendarsPermission,
            isLoading = calendarsSync.isLoading,
            lastUpdatedEpochMillis = calendarsSync.lastUpdatedEpochMillis,
            activeCount = activeCalCount,
            unitLabel = "eventi",
            upToTodayOnly = calendarsUpToTodayOnly,
            onToggleUpToToday = onToggleCalendarsUpToToday,
            onRefresh = onRefreshCalendars
        )
    }

    val activeSmsCount = if (smsUpToTodayOnly) {
        smsSync.totalUpToTodayCount
    } else {
        maxOf(smsSync.totalAllCount, summary?.smsCount ?: 0)
    }
    CategoryDropdownCard(
        icon = Icons.Filled.Sms,
        iconColor = DirectSwitchTheme.green,
        title = DirectSwitchL10n.tr("Messaggi SMS"),
        countBadge = if (activeSmsCount > 0) "$activeSmsCount ${DirectSwitchL10n.tr("messaggi")}" else null,
        checked = categories.sms,
        onCheckedChange = { onUpdateCategories(categories.copy(sms = it)) }
    ) {
        DateSyncDropdownBody(
            hasPermission = SmsSystemScanner.hasReadPermission(wizardContext),
            permissionTitle = DirectSwitchL10n.tr("Permesso SMS richiesto per preparare i messaggi.", en = "SMS permission required to prepare messages.", fr = "Autorisation SMS requise pour préparer les messages."),
            onRequestPermission = onRequestSmsPermission,
            isLoading = smsSync.isLoading,
            lastUpdatedEpochMillis = smsSync.lastUpdatedEpochMillis,
            activeCount = activeSmsCount,
            unitLabel = "messaggi",
            upToTodayOnly = smsUpToTodayOnly,
            onToggleUpToToday = onToggleSmsUpToToday,
            onRefresh = onRefreshSms
        )
    }

    CategoryDropdownCard(
        icon = Icons.Filled.Call,
        iconColor = DirectSwitchTheme.teal,
        title = DirectSwitchL10n.tr("Cronologia Chiamate"),
        countBadge = if (callLogsCount > 0) "$callLogsCount ${DirectSwitchL10n.tr("chiamate", en = "calls", fr = "appels")}" else DirectSwitchL10n.tr("Registro + archivio", en = "Log + archive", fr = "Journal + archive"),
        checked = categories.callLogs,
        onCheckedChange = { onUpdateCategories(categories.copy(callLogs = it)) }
    ) {
        ProgressivePreloadDropdownBody(
            hasPermission = CallLogMigrator.hasReadPermission(wizardContext),
            permissionTitle = DirectSwitchL10n.tr("Permesso Registro Chiamate richiesto per esportare la cronologia.", en = "Call Log permission required to export history.", fr = "Autorisation Journal d'appels requise."),
            onRequestPermission = onRequestCallLogsPermission,
            isLoading = isLoadingCallLogs,
            loadedCount = callLogsCount,
            totalCount = callLogsCount,
            loadingLabel = DirectSwitchL10n.tr("Lettura registro chiamate...", en = "Reading call history...", fr = "Lecture du journal d'appels..."),
            readyLabel = DirectSwitchL10n.tr("$callLogsCount chiamate pronte", en = "$callLogsCount calls ready", fr = "$callLogsCount appels prêts"),
            detailLabel = if (isCrossOs) {
                DirectSwitchL10n.tr("Salvata su iPhone come archivio HTML/JSON leggibile in Cronologia_Chiamate.", en = "Saved on iPhone as readable HTML/JSON archive in Call_History.", fr = "Enregistré sur iPhone en archive HTML/JSON lisible.")
            } else {
                DirectSwitchL10n.tr("Importata nativamente nel registro chiamate Android + archivio di backup.", en = "Imported natively into Android call log + backup archive.", fr = "Importé nativement dans le journal d'appels Android + archive.")
            },
            accentColor = DirectSwitchTheme.teal,
            onReload = onReloadCallLogs
        )
    }

    CategoryDropdownCard(
        icon = Icons.Filled.AudioFile,
        iconColor = DirectSwitchTheme.blue,
        title = DirectSwitchL10n.tr("Audio e Memo Vocali"),
        countBadge = if (audioFilesCount > 0) "$audioFilesCount ${DirectSwitchL10n.tr("tracce", en = "tracks", fr = "pistes")}" else DirectSwitchL10n.tr("Registrazioni e MP3", en = "Recordings & MP3", fr = "Enregistrements et MP3"),
        checked = categories.audio,
        onCheckedChange = { onUpdateCategories(categories.copy(audio = it)) }
    ) {
        ProgressivePreloadDropdownBody(
            hasPermission = AudioAndMemoMigrator.hasReadPermission(wizardContext),
            permissionTitle = DirectSwitchL10n.tr("Permesso Audio richiesto per trovare Memo Vocali e tracce.", en = "Audio permission required to scan Voice Memos & tracks.", fr = "Autorisation Audio requise pour scanner vos enregistrements."),
            onRequestPermission = onRequestAudioPermission,
            isLoading = isLoadingAudio,
            loadedCount = audioFilesCount,
            totalCount = audioFilesCount,
            loadingLabel = DirectSwitchL10n.tr("Ricerca memo vocali e audio...", en = "Scanning voice memos and audio...", fr = "Recherche des mémos vocaux et audio..."),
            readyLabel = DirectSwitchL10n.tr("$audioFilesCount file audio/memo pronti", en = "$audioFilesCount audio/memo files ready", fr = "$audioFilesCount fichiers audio prêts"),
            detailLabel = DirectSwitchL10n.tr("Copia registrazioni vocali, .m4a, .mp3 e file audio nella cartella Musica / Audio_e_Memo.", en = "Copies voice recordings, .m4a, .mp3 and audio files to Music / Audio_e_Memo.", fr = "Copie enregistrements vocaux, .m4a, .mp3 dans Musique / Audio_e_Memo."),
            accentColor = DirectSwitchTheme.blue,
            onReload = onReloadAudio
        )
    }

    val locationSummaries = summary?.documentLocationSummaries.orEmpty()
    val hasAllFiles = summary?.hasAllFilesAccess ?: DocumentsAndWhatsAppScanner.hasAllFilesAccess(wizardContext)
    val hasPickedLocations = !vaultStatusNote.isNullOrBlank() ||
        remember(summary) { DocumentsAndWhatsAppScanner.getPersistedFolderTreeUris(wizardContext).isNotEmpty() }
    val docsBadge = summary?.let {
        if (it.documentsCount > 0) "${maxOf(1, it.documentFoldersCount)} ${DirectSwitchL10n.tr("cartelle", en = "folders", fr = "dossiers")} • ${it.documentsCount} ${DirectSwitchL10n.tr("file", en = "files", fr = "fichiers")}"
        else DirectSwitchL10n.tr("Memoria interna, Drive, SD", en = "Internal storage, Drive, SD", fr = "Stockage interne, Drive, SD")
    }
    CategoryDropdownCard(
        icon = Icons.Filled.Description,
        iconColor = DirectSwitchTheme.teal,
        title = DirectSwitchL10n.tr("Documenti e Posizioni File"),
        countBadge = docsBadge,
        checked = categories.documents,
        onCheckedChange = { onUpdateCategories(categories.copy(documents = it)) }
    ) {
        DocumentsPositionsDropdownBody(
            locationSummaries = locationSummaries,
            hasAllFiles = hasAllFiles,
            vaultStatusNote = vaultStatusNote,
            onToggleLocationSelection = onToggleLocationSelection,
            onRemoveSafLocation = onRemoveSafLocation,
            onRefreshDocumentCheck = onRefreshDocumentCheck,
            onPickFolderTree = onPickFolderTree,
            onClearPickedDocuments = onClearPickedDocuments,
            hasPickedLocations = hasPickedLocations
        )
        GuidedPasswordsCard(
            stagedCsvCount = stagedPasswordCsvCount,
            onPickPasswordCsv = onPickPasswordCsv
        )
    }

    if (!isCrossOs) {
        CategoryDropdownCard(
            icon = Icons.AutoMirrored.Filled.Chat,
            iconColor = DirectSwitchTheme.green,
            title = DirectSwitchL10n.tr("Chat WhatsApp"),
            countBadge = DirectSwitchL10n.tr("Gratuito • Codice QR"),
            checked = categories.whatsAppVault,
            onCheckedChange = { onUpdateCategories(categories.copy(whatsAppVault = it)) }
        ) {
            WhatsAppDropdownBody(isCrossOs = false)
        }
    }

    val effectiveAppsCatalog = detectedAppsCatalog
    val selectedExtraPackages = remember(extraSelectedCuratedApps) {
        extraSelectedCuratedApps.map { it.packageName }.toSet()
    }
    val selectedAppsCount = (if (effectiveAppsCatalog.isNotEmpty()) {
        effectiveAppsCatalog.count { it.packageName !in deselectedAppPackages }
    } else {
        summary?.installedAppsCount ?: 0
    }) + extraSelectedCuratedApps.size
    CategoryDropdownCard(
        icon = Icons.Filled.Apps,
        iconColor = DirectSwitchTheme.blue,
        title = DirectSwitchL10n.tr("App scaricate"),
        countBadge = if (selectedAppsCount > 0) DirectSwitchL10n.tr("$selectedAppsCount app pronte", en = "$selectedAppsCount apps ready", fr = "$selectedAppsCount apps prêtes") else null,
        checked = categories.installedApps,
        onCheckedChange = { onUpdateCategories(categories.copy(installedApps = it)) }
    ) {
        InstalledAppsDropdownBody(
            allApps = effectiveAppsCatalog,
            groupedCategories = groupedAppCategories,
            deselectedPackages = deselectedAppPackages,
            isLoadingApps = isLoadingApps,
            onToggleApp = onToggleSingleApp,
            onToggleCategoryAll = onToggleAppCategoryAll,
            onToggleAllDetected = onToggleAllDetectedApps,
            onRefreshApps = onRefreshApps,
            extraCuratedCategories = InstalledAppsScanner.curatedExtraAndroidCategories,
            selectedExtraPackages = selectedExtraPackages,
            onToggleExtraApp = onToggleExtraCuratedApp
        )
    }

    DirectSwitchCard(padding = 12.dp, spacing = 6.dp) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.SpaceBetween
        ) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(10.dp),
                modifier = Modifier.weight(1f)
            ) {
                AppleSettingsIcon(icon = Icons.Filled.Email, color = DirectSwitchTheme.slate, size = 26.dp)
                Text(
                    text = DirectSwitchL10n.tr("App, Account Mail e Impostazioni", en = "Apps, Mail Accounts & Settings", fr = "Apps, Comptes Mail et Réglages"),
                    fontSize = 14.sp,
                    fontWeight = FontWeight.SemiBold,
                    color = DirectSwitchTheme.textPrimary
                )
            }
            InfoCircleButton(
                title = DirectSwitchL10n.tr("Confronto con Passa a Android / Passa a iOS", en = "How it works vs Switch tools", fr = "Comment ça fonctionne"),
                message = DirectSwitchL10n.tr(
                    "• App installate: DirectSwitch trasferisce l'elenco completo delle tue app per riscaricarle con 1 tocco da App Store o Play Store sul telefono ricevente.\n• Account Mail (Gmail, iCloud, Outlook): per sicurezza Apple/Google le password non viaggiano mai in chiaro; a fine copia trovi il pulsante rapido per collegare il tuo account e riavere tutte le email.\n• Impostazioni di sistema: non vengono sovrascritte, così il telefono ricevente non viene né formattato né alterato.",
                    en = "• Installed apps: DirectSwitch transfers your full app list so you can reinstall with 1 tap from App Store or Play Store.\n• Mail accounts (Gmail, iCloud, Outlook): for security passwords never leave the device; a quick shortcut is shown at the end.\n• System settings: untouched, so your receiving phone is never erased.",
                    fr = "• Apps installées : DirectSwitch transfère la liste complète pour les réinstaller en 1 geste.\n• Comptes Mail : vos mots de passe ne quittent jamais l'appareil.\n• Réglages système : préservés sans jamais réinitialiser le téléphone."
                )
            )
        }
    }

    val batterySnap = remember(wizardContext) { AndroidBatteryTriageMonitor.readSnapshot(wizardContext) }
    if (activeDeltaBaseline != null) {
        DirectSwitchCard(padding = 12.dp, spacing = 6.dp) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.SpaceBetween
            ) {
                Column(modifier = Modifier.weight(1f)) {
                    Text(
                        text = DirectSwitchL10n.tr("Modalità Delta attiva (solo novità)", en = "Delta Mode active (new items only)", fr = "Mode Delta actif (nouveautés)"),
                        fontSize = 13.5.sp,
                        fontWeight = FontWeight.Bold,
                        color = DirectSwitchTheme.teal
                    )
                    Text(
                        text = DirectSwitchL10n.tr("Verranno inviati solo i nuovi elementi creati dopo l'ultima copia verso ${activeDeltaBaseline.peerName}.", en = "Only new items created since the last transfer to ${activeDeltaBaseline.peerName} will be sent.", fr = "Seuls les nouveaux éléments créés depuis la dernière copie vers ${activeDeltaBaseline.peerName} seront envoyés."),
                        fontSize = 11.5.sp,
                        color = DirectSwitchTheme.textSecondary
                    )
                }
                TextButton(onClick = onClearDeltaBaseline) {
                    Text(DirectSwitchL10n.tr("Copia tutto", en = "Copy all", fr = "Tout copier"), fontSize = 12.sp, fontWeight = FontWeight.Bold, color = DirectSwitchTheme.blue)
                }
            }
        }
    }

    if (batterySnap.recommendsAutoTriage || (!batterySnap.isCharging && batterySnap.percent <= 25) || forceBatteryTriage) {
        BatteryTriageToggleCard(
            battery = batterySnap,
            enabled = forceBatteryTriage,
            onToggle = onToggleForceBatteryTriage
        )
    }

    SmartCleanAndCompatCard(
        smartClean = smartCleanOptions,
        convertHeicToJpeg = convertHeicToJpeg,
        showHeicOption = categories.photos,
        onSmartCleanChange = onSmartCleanChange,
        onToggleConvertHeic = onToggleConvertHeic
    )

    val isOnlyWhatsAppSelected = !isCrossOs && categories.whatsAppVault &&
        !categories.contacts && !categories.photos && !categories.videos &&
        !categories.calendars && !categories.sms && !categories.callLogs &&
        !categories.audio && !categories.documents &&
        !categories.installedApps

    DirectSwitchPrimaryButton(
        text = if (isOnlyWhatsAppSelected) DirectSwitchL10n.tr("Vai al passaggio Chat WhatsApp") else DirectSwitchL10n.tr("Copia le voci selezionate"),
        onClick = onStartTransfer,
        enabled = anySelected,
        isLoading = isLaunchingTransfer,
        loadingText = DirectSwitchL10n.tr("Avvio preparazione...")
    )
}

// MARK: - 4. Avanzamento & Completamento (stile "Passa a iOS" / "Android Switch")

@Composable
private fun TransferProgressWizardView(
    progress: LiveTransferProgress,
    isReceiver: Boolean,
    networkDiagnostic: NetworkDiagnosticVerdict?,
    onRetryNetwork: () -> Unit,
    onApplySpaceRelief: (SpaceReliefActionKind) -> Unit,
    onRetrySkippedOnly: (List<String>) -> Unit,
    onFinish: () -> Unit
) {
    val context = LocalContext.current
    var stillDefaultSms by remember(progress.isCompleted, progress.errorMessage) {
        mutableStateOf(SmsSystemScanner.isDefaultSmsApp(context))
    }
    val restoreSmsLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.StartActivityForResult()
    ) {
        stillDefaultSms = SmsSystemScanner.isDefaultSmsApp(context)
    }

    val scope = progress.activeTransferScope
    val hasOtherItems = progress.totalItems > 0 ||
        progress.mergedContacts > 0 ||
        progress.importedCalendars > 0 ||
        progress.importedSms > 0 ||
        progress.receivedInstalledApps.isNotEmpty()
    val isStandaloneWhatsApp = progress.errorMessage == null && (
        scope.isWhatsAppOnly ||
            (progress.isCompleted && progress.pendingNativeWhatsAppMigration && !hasOtherItems)
        )

    if (isStandaloneWhatsApp) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(top = 8.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Box(
                modifier = Modifier
                    .size(66.dp)
                    .clip(CircleShape)
                    .background(DirectSwitchTheme.green.copy(alpha = 0.16f)),
                contentAlignment = Alignment.Center
            ) {
                Icon(
                    imageVector = Icons.AutoMirrored.Filled.Chat,
                    contentDescription = null,
                    tint = DirectSwitchTheme.green,
                    modifier = Modifier.size(34.dp)
                )
            }
            Text(
                text = DirectSwitchL10n.tr("Chat WhatsApp"),
                fontSize = 23.sp,
                fontWeight = FontWeight.Bold,
                color = DirectSwitchTheme.textPrimary
            )
            Text(
                text = DirectSwitchL10n.tr("Segui i passaggi qui sotto per caricare le chat dentro WhatsApp (gratuito)", en = "Follow the steps below to move chats inside WhatsApp (free)", fr = "Suivez les étapes ci-dessous pour transférer vos discussions dans WhatsApp (gratuit)"),
                fontSize = 14.sp,
                color = DirectSwitchTheme.textSecondary,
                textAlign = TextAlign.Center
            )
        }

        WhatsAppNativeTransferCard(
            isReceiver = isReceiver,
            peerPlatform = progress.peerPlatform
        )

        DirectSwitchPrimaryButton(
            text = DirectSwitchL10n.tr("Fine"),
            onClick = onFinish
        )
        return
    }

    val processedItems = progress.completedItems + progress.failedItemsCount
    val ratioDouble = when {
        progress.isCompleted -> 1.0
        progress.transferredBytes == 0L && processedItems == 0 -> 0.0
        progress.totalBytes > 0L && progress.transferredBytes > 0L ->
            (progress.transferredBytes.toDouble() / progress.totalBytes.toDouble()).coerceIn(0.01, 1.0)
        progress.totalItems > 0 -> (processedItems.toDouble() / progress.totalItems.toDouble()).coerceIn(0.01, 1.0)
        else -> 0.0
    }
    val ratio = ratioDouble.toFloat()
    val pct = TransferDisplayFormatting.percentageInt(ratioDouble, progress.isCompleted)

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(top = 8.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        if (progress.isCompleted) {
            Box(
                modifier = Modifier
                    .size(66.dp)
                    .clip(CircleShape)
                    .background(DirectSwitchTheme.green.copy(alpha = 0.16f)),
                contentAlignment = Alignment.Center
            ) {
                Icon(Icons.Filled.CheckCircle, contentDescription = null, tint = DirectSwitchTheme.green, modifier = Modifier.size(40.dp))
            }
            Text(DirectSwitchL10n.tr("Trasferimento completato"), fontSize = 23.sp, fontWeight = FontWeight.Bold, color = DirectSwitchTheme.textPrimary)
            Text(
                text = if (isReceiver) DirectSwitchL10n.tr("I tuoi dati sono pronti su questo telefono") else DirectSwitchL10n.tr("Tutti i dati selezionati sono stati copiati"),
                fontSize = 14.sp,
                color = DirectSwitchTheme.textSecondary,
                textAlign = TextAlign.Center
            )
        } else {
            DirectSwitchAppleEmblem(size = 60.dp)
            Text(
                text = if (isReceiver) DirectSwitchL10n.tr("Copia su questo telefono...") else DirectSwitchL10n.tr("Copia dei dati in corso..."),
                fontSize = 22.sp,
                fontWeight = FontWeight.Bold,
                color = DirectSwitchTheme.textPrimary
            )
            Text(DirectSwitchL10n.tr("Tieni entrambi i telefoni vicini fino al termine"), fontSize = 14.sp, color = DirectSwitchTheme.textSecondary)
        }
    }

    DirectSwitchCard {
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.Bottom,
            horizontalArrangement = Arrangement.SpaceBetween
        ) {
            Text(
                text = "$pct%",
                fontSize = 32.sp,
                fontWeight = FontWeight.Bold,
                color = if (progress.isCompleted) DirectSwitchTheme.green else DirectSwitchTheme.textPrimary
            )
            if (!progress.isCompleted && progress.speedMegabytesPerSec > 0.05) {
                Text(
                    text = String.format(Locale.ITALY, "%.1f MB/s", progress.speedMegabytesPerSec),
                    fontSize = 13.sp,
                    fontWeight = FontWeight.SemiBold,
                    color = DirectSwitchTheme.blue
                )
            }
        }

        LinearProgressIndicator(
            progress = { ratio },
            modifier = Modifier
                .fillMaxWidth()
                .height(10.dp)
                .clip(RoundedCornerShape(6.dp)),
            color = if (progress.isCompleted) DirectSwitchTheme.green else DirectSwitchTheme.blue,
            trackColor = DirectSwitchTheme.inputSurface
        )

        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween
        ) {
            Text(
                text = progress.currentFileName.ifEmpty { DirectSwitchL10n.tr(progress.phaseLabel) },
                fontSize = 13.sp,
                color = DirectSwitchTheme.textSecondary,
                maxLines = 1,
                modifier = Modifier.weight(1f)
            )
            if (progress.totalBytes > 0L) {
                Text(
                    text = "${formatMb(progress.transferredBytes)} / ${formatMb(progress.totalBytes)}",
                    fontSize = 12.sp,
                    color = DirectSwitchTheme.textSecondary
                )
            }
        }

        if (!progress.isCompleted && !progress.etaLabel.isNullOrBlank()) {
            Spacer(modifier = Modifier.height(2.dp))
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(10.dp))
                    .background(DirectSwitchTheme.blue.copy(alpha = 0.09f))
                    .padding(horizontal = 12.dp, vertical = 8.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                Icon(
                    imageVector = Icons.Filled.Schedule,
                    contentDescription = null,
                    tint = DirectSwitchTheme.blue,
                    modifier = Modifier.size(18.dp)
                )
                Text(
                    text = DirectSwitchL10n.translateEta(progress.etaLabel) ?: progress.etaLabel,
                    fontSize = 15.sp,
                    fontWeight = FontWeight.SemiBold,
                    color = DirectSwitchTheme.blue
                )
            }
        }

        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            ConnectionMediumPill(medium = progress.connectionMedium)
            if (progress.batteryTriageActive) {
                BatteryTriageActivePill()
            }
            if (progress.thermalGuardState != ThermalGuardState.NORMAL) {
                ThermalGuardBannerPill(
                    state = progress.thermalGuardState,
                    bannerText = progress.thermalBanner
                )
            }
        }
    }

    DirectSwitchCard(padding = 0.dp, spacing = 0.dp) {
        SummaryItemRow(
            Icons.Filled.Contacts,
            DirectSwitchTheme.blue,
            DirectSwitchL10n.tr("Contatti uniti"),
            formatImportedWithDuplicates(progress.mergedContacts, progress.contactsAlreadyPresent)
        )
        HorizontalDivider(modifier = Modifier.padding(start = 56.dp), color = DirectSwitchTheme.hairline)
        SummaryItemRow(
            Icons.Filled.Image,
            DirectSwitchTheme.orange,
            DirectSwitchL10n.tr("Foto, Video e File"),
            if (progress.totalItems > 0) "${progress.completedItems} / ${progress.totalItems}" else "${progress.completedItems}"
        )
        HorizontalDivider(modifier = Modifier.padding(start = 56.dp), color = DirectSwitchTheme.hairline)
        SummaryItemRow(
            Icons.Filled.CalendarMonth,
            DirectSwitchTheme.indigo,
            DirectSwitchL10n.tr("Calendari importati"),
            formatImportedWithDuplicates(progress.importedCalendars, progress.calendarsAlreadyPresent)
        )
        if (progress.activeTransferScope.reminders || progress.importedReminders > 0 || progress.remindersAlreadyPresent > 0) {
            HorizontalDivider(modifier = Modifier.padding(start = 56.dp), color = DirectSwitchTheme.hairline)
            SummaryItemRow(
                Icons.Filled.Checklist,
                DirectSwitchTheme.blue,
                DirectSwitchL10n.tr("Promemoria salvati"),
                formatImportedWithDuplicates(progress.importedReminders, progress.remindersAlreadyPresent)
            )
        }
        if (progress.importedSms > 0) {
            HorizontalDivider(modifier = Modifier.padding(start = 56.dp), color = DirectSwitchTheme.hairline)
            SummaryItemRow(Icons.Filled.Sms, DirectSwitchTheme.green, DirectSwitchL10n.tr("Messaggi salvati"), "${progress.importedSms}")
        }
        if (progress.importedCallLogs > 0) {
            HorizontalDivider(modifier = Modifier.padding(start = 56.dp), color = DirectSwitchTheme.hairline)
            SummaryItemRow(Icons.Filled.Call, DirectSwitchTheme.teal, DirectSwitchL10n.tr("Chiamate salvate"), "${progress.importedCallLogs}")
        }
        if (progress.healedTimelineCount > 0) {
            HorizontalDivider(modifier = Modifier.padding(start = 56.dp), color = DirectSwitchTheme.hairline)
            SummaryItemRow(Icons.Filled.Schedule, DirectSwitchTheme.blue, DirectSwitchL10n.tr("Date EXIF ricostruite"), "${progress.healedTimelineCount}")
        }
        if (progress.convertedLiveMotionCount > 0) {
            HorizontalDivider(modifier = Modifier.padding(start = 56.dp), color = DirectSwitchTheme.hairline)
            SummaryItemRow(Icons.Filled.Image, DirectSwitchTheme.teal, DirectSwitchL10n.tr("Live / Motion Photo preservate"), "${progress.convertedLiveMotionCount}")
        }
        if (progress.healedCodecCount > 0) {
            HorizontalDivider(modifier = Modifier.padding(start = 56.dp), color = DirectSwitchTheme.hairline)
            SummaryItemRow(Icons.Filled.AudioFile, DirectSwitchTheme.indigo, DirectSwitchL10n.tr("Audio convertiti compatibili iOS"), "${progress.healedCodecCount}")
        }
        if (progress.skippedDuplicates > 0) {
            HorizontalDivider(modifier = Modifier.padding(start = 56.dp), color = DirectSwitchTheme.hairline)
            SummaryItemRow(Icons.Filled.CheckCircle, DirectSwitchTheme.teal, DirectSwitchL10n.tr("Doppioni ignorati"), "${progress.skippedDuplicates}")
        }
        if (progress.failedItemsCount > 0) {
            HorizontalDivider(modifier = Modifier.padding(start = 56.dp), color = DirectSwitchTheme.hairline)
            SummaryItemRow(Icons.Filled.Warning, DirectSwitchTheme.orange, DirectSwitchL10n.tr("File non disponibili saltati"), "${progress.failedItemsCount}")
        }
    }

    if (isReceiver && progress.isCompleted && progress.receivedInstalledApps.isNotEmpty()) {
        ReceiverAppsMirrorCard(
            apps = progress.receivedInstalledApps,
            peerPlatform = progress.peerPlatform
        )
    }

    if (isReceiver && progress.isCompleted) {
        DirectSwitchCard {
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.SpaceBetween
            ) {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(10.dp),
                    modifier = Modifier.weight(1f)
                ) {
                    AppleSettingsIcon(icon = Icons.Filled.Email, color = DirectSwitchTheme.slate)
                    Text(
                        text = DirectSwitchL10n.tr("Account Mail e Cloud"),
                        fontSize = 15.sp,
                        fontWeight = FontWeight.Bold,
                        color = DirectSwitchTheme.textPrimary
                    )
                }
                InfoCircleButton(
                    title = DirectSwitchL10n.tr("Sincronizza Email e Account", en = "Sync Email & Accounts", fr = "Synchroniser e-mails et comptes"),
                    message = DirectSwitchL10n.tr("Come su Android Switch, per motivi di sicurezza le password delle caselle email non viaggiano tra dispositivi. Accedi qui al tuo account Google, iCloud o Outlook per sincronizzare istantaneamente tutte le email.", en = "For security, email passwords never leave the old device. Sign in to Google, iCloud or Outlook here to sync your email instantly.", fr = "Pour votre sécurité, les mots de passe ne quittent jamais l'appareil. Connectez-vous ici pour synchroniser vos e-mails.")
                )
            }
            DirectSwitchSecondaryButton(
                text = DirectSwitchL10n.tr("Aggiungi account Mail / Google", en = "Add Mail / Google account", fr = "Ajouter un compte Mail / Google"),
                onClick = { InstalledAppsScanner.openAddAccountSettings(context) }
            )
        }
    }

    if (isReceiver && progress.isCompleted && progress.receivedDocumentFolders.isNotEmpty()) {
        val sortedFolders = progress.receivedDocumentFolders.entries.sortedBy { it.key.lowercase() }
        val totalReceivedFiles = sortedFolders.sumOf { it.value }
        DirectSwitchCard(padding = 14.dp, spacing = 8.dp) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.SpaceBetween
            ) {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(10.dp),
                    modifier = Modifier.weight(1f)
                ) {
                    AppleSettingsIcon(icon = Icons.Filled.Folder, color = DirectSwitchTheme.teal)
                    Column {
                        Text(
                            text = DirectSwitchL10n.tr("Cartelle ricreate su questo telefono", en = "Folders restored on this phone", fr = "Dossiers recréés sur ce téléphone"),
                            fontSize = 15.sp,
                            fontWeight = FontWeight.Bold,
                            color = DirectSwitchTheme.textPrimary
                        )
                        Text(
                            text = DirectSwitchL10n.tr("$totalReceivedFiles file in ${sortedFolders.size} cartelle originali", en = "$totalReceivedFiles files in ${sortedFolders.size} original folders", fr = "$totalReceivedFiles fichiers dans ${sortedFolders.size} dossiers"),
                            fontSize = 12.sp,
                            color = DirectSwitchTheme.textSecondary
                        )
                    }
                }
            }
            Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                sortedFolders.take(8).forEach { (folderPath, count) ->
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween
                    ) {
                        Text(
                            text = "$folderPath/",
                            fontSize = 12.sp,
                            fontWeight = FontWeight.Medium,
                            color = DirectSwitchTheme.textPrimary,
                            modifier = Modifier.weight(1f)
                        )
                        Text(
                            text = "$count ${DirectSwitchL10n.tr("file", en = "files", fr = "fichiers")}",
                            fontSize = 12.sp,
                            color = DirectSwitchTheme.textSecondary
                        )
                    }
                }
                if (sortedFolders.size > 8) {
                    Text(
                        text = DirectSwitchL10n.tr("e altre ${sortedFolders.size - 8} cartelle salvate nella memoria del telefono.", en = "and ${sortedFolders.size - 8} more folders saved on device storage.", fr = "et ${sortedFolders.size - 8} autres dossiers enregistrés."),
                        fontSize = 12.sp,
                        fontWeight = FontWeight.SemiBold,
                        color = DirectSwitchTheme.teal
                    )
                }
            }
        }
    }

    if (progress.isCompleted && progress.pendingNativeWhatsAppMigration) {
        WhatsAppNativeTransferCard(
            isReceiver = isReceiver,
            peerPlatform = progress.peerPlatform
        )
    }

    val reliefOffer = progress.spaceReliefOffer
    if (!isReceiver && reliefOffer != null) {
        SpaceReliefAssistantCard(
            offer = reliefOffer,
            onSelectAction = onApplySpaceRelief
        )
    }

    if (progress.skippedItems.isNotEmpty()) {
        SkippedItemsReportCard(
            items = progress.skippedItems,
            canRetry = !isReceiver && (progress.isCompleted || progress.errorMessage != null),
            onRetrySkippedOnly = { onRetrySkippedOnly(progress.skippedItems.map { it.id }) }
        )
    }

    if (progress.errorMessage != null) {
        DirectSwitchCard(padding = 14.dp) {
            Text(progress.errorMessage, fontSize = 13.sp, fontWeight = FontWeight.Medium, color = DirectSwitchTheme.red)
            if (!isReceiver) {
                DirectSwitchPrimaryButton(
                    text = if (progress.completedItems > 0) {
                        DirectSwitchL10n.tr(
                            "Riprendi trasferimento da dove era rimasto",
                            en = "Resume transfer where it left off",
                            fr = "Reprendre le transfert là où il s'est arrêté"
                        )
                    } else {
                        DirectSwitchL10n.tr(
                            "Riprova copia",
                            en = "Retry copy",
                            fr = "Réessayer la copie"
                        )
                    },
                    onClick = onRetryNetwork
                )
            }
        }
        if (!isReceiver && networkDiagnostic != null) {
            NetworkIsolationHotspotCard(
                verdict = networkDiagnostic,
                onRetryConnect = onRetryNetwork,
                showRetryButton = false
            )
        }
    }

    if (!isReceiver && progress.isCompleted &&
        (progress.reconciliationVerifiedCount > 0 ||
            progress.reconciliationMissingIds.isNotEmpty() ||
            progress.heicConvertedCount > 0 ||
            progress.smartCleanMergedContactsCount > 0 ||
            progress.smartCleanSkippedDuplicatesCount > 0 ||
            progress.smartCleanSkippedScreenshotsCount > 0)
    ) {
        PostTransferReconciliationCard(
            verifiedCount = progress.reconciliationVerifiedCount,
            missingIds = progress.reconciliationMissingIds,
            failedCount = progress.failedItemsCount,
            heicConvertedCount = progress.heicConvertedCount,
            smartCleanMergedContacts = progress.smartCleanMergedContactsCount,
            smartCleanSkippedDuplicates = progress.smartCleanSkippedDuplicatesCount,
            smartCleanSkippedScreenshots = progress.smartCleanSkippedScreenshotsCount,
            onRepairMissing = { missingIds -> onRetrySkippedOnly(missingIds) }
        )
    }

    if (isReceiver && stillDefaultSms && (progress.isCompleted || progress.errorMessage != null)) {
        DirectSwitchCard(padding = 14.dp) {
            Text(DirectSwitchL10n.tr("Ripristina la tua app Messaggi predefinita", en = "Restore your default Messages app", fr = "Restaurer votre app Messages par défaut"), fontSize = 14.sp, fontWeight = FontWeight.SemiBold, color = DirectSwitchTheme.textPrimary)
            DirectSwitchSecondaryButton(
                text = DirectSwitchL10n.tr("Ripristina app Messaggi", en = "Restore Messages app", fr = "Restaurer l'app Messages"),
                onClick = {
                    runCatching { restoreSmsLauncher.launch(SmsSystemScanner.createRestorePreviousSmsAppIntent(context)) }
                }
            )
        }
    }

    if (progress.isCompleted || progress.errorMessage != null) {
        DirectSwitchPrimaryButton(
            text = if (progress.isCompleted) DirectSwitchL10n.tr("Fine") else DirectSwitchL10n.tr("Torna alla Home"),
            onClick = onFinish
        )
    }
}

private fun formatImportedWithDuplicates(imported: Int, alreadyPresent: Int): String {
    val already = DirectSwitchL10n.tr("già presenti", en = "already present", fr = "déjà présents")
    return when {
        imported == 0 && alreadyPresent > 0 -> "0 ($alreadyPresent $already)"
        alreadyPresent > 0 -> "$imported (+$alreadyPresent $already)"
        else -> "$imported"
    }
}

@Composable
private fun SummaryItemRow(icon: ImageVector, color: Color, title: String, value: String) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 14.dp, vertical = 11.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.SpaceBetween
    ) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            AppleSettingsIcon(icon = icon, color = color)
            Text(title, fontSize = 15.sp, fontWeight = FontWeight.Medium, color = DirectSwitchTheme.textPrimary)
        }
        Text(value, fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = DirectSwitchTheme.textSecondary)
    }
}

@Composable
private fun ReceiverAppsMirrorCard(
    apps: List<InstalledAppRecord>,
    peerPlatform: DevicePlatform?
) {
    val context = LocalContext.current
    val lifecycleOwner = LocalLifecycleOwner.current
    var refreshTick by remember { mutableIntStateOf(0) }
    var showAlreadyInstalled by remember { mutableStateOf(false) }

    DisposableEffect(lifecycleOwner) {
        val observer = LifecycleEventObserver { _, event ->
            if (event == Lifecycle.Event.ON_RESUME) {
                refreshTick++
            }
        }
        lifecycleOwner.lifecycle.addObserver(observer)
        onDispose { lifecycleOwner.lifecycle.removeObserver(observer) }
    }

    val snapshot = remember(refreshTick, apps.size) {
        InstalledAppsScanner.readInstalledAppsSnapshot(context)
    }
    val pendingApps = remember(apps, snapshot, peerPlatform) {
        apps.filter { !InstalledAppsScanner.isAppInstalled(snapshot, it, peerPlatform) }
    }
    val installedApps = remember(apps, snapshot, peerPlatform) {
        apps.filter { InstalledAppsScanner.isAppInstalled(snapshot, it, peerPlatform) }
    }

    DirectSwitchCard {
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.SpaceBetween
        ) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                modifier = Modifier.weight(1f)
            ) {
                AppleSettingsIcon(icon = Icons.Filled.Apps, color = DirectSwitchTheme.blue, size = 30.dp)
                Column {
                    Text(
                        text = if (pendingApps.isEmpty()) {
                            DirectSwitchL10n.tr("Tutte le app già installate (${installedApps.size})", en = "All apps already installed (${installedApps.size})", fr = "Toutes les apps déjà installées (${installedApps.size})")
                        } else {
                            DirectSwitchL10n.tr("App da installare (${pendingApps.size})", en = "Apps to install (${pendingApps.size})", fr = "Apps à installer (${pendingApps.size})")
                        },
                        fontSize = 15.sp,
                        fontWeight = FontWeight.Bold,
                        color = DirectSwitchTheme.textPrimary
                    )
                    Text(
                        text = when {
                            pendingApps.isEmpty() -> DirectSwitchL10n.tr("Nessuna app mancante: hai già tutte le ${apps.size} app sul telefono", en = "No missing apps: all ${apps.size} apps are already installed", fr = "Aucune app manquante : les ${apps.size} apps sont déjà installées")
                            installedApps.isNotEmpty() -> DirectSwitchL10n.tr("${installedApps.size} già presenti e nascoste automaticamente • aggiornamento al rientro", en = "${installedApps.size} already installed and hidden • refreshes on return", fr = "${installedApps.size} déjà installées et masquées • actualisation au retour")
                            else -> DirectSwitchL10n.tr("Tocca un'app per installarla dal Play Store (aggiornamento automatico al rientro)", en = "Tap an app to install from Play Store (refreshes on return)", fr = "Touchez une app pour l'installer depuis Play Store")
                        },
                        fontSize = 12.sp,
                        color = DirectSwitchTheme.textSecondary
                    )
                }
            }
            Surface(
                shape = RoundedCornerShape(10.dp),
                color = DirectSwitchTheme.blue.copy(alpha = 0.10f),
                modifier = Modifier.clickable { refreshTick++ }
            ) {
                Row(
                    modifier = Modifier.padding(horizontal = 8.dp, vertical = 6.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(4.dp)
                ) {
                    Icon(
                        imageVector = Icons.Filled.Refresh,
                        contentDescription = DirectSwitchL10n.tr("Aggiorna"),
                        tint = DirectSwitchTheme.blue,
                        modifier = Modifier.size(16.dp)
                    )
                }
            }
        }

        pendingApps.firstOrNull()?.let { nextApp ->
            DirectSwitchPrimaryButton(
                text = DirectSwitchL10n.tr("Installa prossima app (1/${pendingApps.size}): ${nextApp.appName}", en = "Install next app (1/${pendingApps.size}): ${nextApp.appName}", fr = "Installer l'app suivante (1/${pendingApps.size}) : ${nextApp.appName}"),
                onClick = { InstalledAppsScanner.openAppOnPlayStore(context, nextApp, peerPlatform) }
            )
        }

        if (pendingApps.isNotEmpty()) {
            HorizontalDivider()
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                pendingApps.forEach { app ->
                    val target = InstalledAppsScanner.resolvePlayStoreTarget(app, peerPlatform)
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .clickable { InstalledAppsScanner.openAppOnPlayStore(context, app, peerPlatform) }
                            .padding(vertical = 4.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.SpaceBetween
                    ) {
                        Column(modifier = Modifier.weight(1f)) {
                            Text(
                                text = app.appName,
                                fontSize = 14.sp,
                                fontWeight = FontWeight.SemiBold,
                                color = DirectSwitchTheme.textPrimary
                            )
                            val targetLabel = when (target) {
                                is InstalledAppsScanner.PlayStoreTarget.ExactPackage -> target.packageName
                                is InstalledAppsScanner.PlayStoreTarget.SearchByName -> "Ricerca guidata su Play Store"
                            }
                            val sourceNote = app.detectionSource?.takeIf { it.isNotBlank() }
                            Text(
                                text = if (sourceNote != null) "$sourceNote • $targetLabel" else targetLabel,
                                fontSize = 11.sp,
                                color = DirectSwitchTheme.textMuted
                            )
                        }
                        Surface(
                            shape = RoundedCornerShape(8.dp),
                            color = DirectSwitchTheme.blue.copy(alpha = 0.12f)
                        ) {
                            Row(
                                modifier = Modifier.padding(horizontal = 10.dp, vertical = 5.dp),
                                verticalAlignment = Alignment.CenterVertically,
                                horizontalArrangement = Arrangement.spacedBy(4.dp)
                            ) {
                                Text(
                                    text = "Play Store",
                                    fontSize = 12.sp,
                                    fontWeight = FontWeight.SemiBold,
                                    color = DirectSwitchTheme.blue
                                )
                                Icon(
                                    imageVector = Icons.AutoMirrored.Filled.KeyboardArrowRight,
                                    contentDescription = null,
                                    tint = DirectSwitchTheme.blue,
                                    modifier = Modifier.size(16.dp)
                                )
                            }
                        }
                    }
                }
            }
        }

        if (installedApps.isNotEmpty()) {
            HorizontalDivider()
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .clickable { showAlreadyInstalled = !showAlreadyInstalled }
                    .padding(vertical = 4.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.SpaceBetween
            ) {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(6.dp)
                ) {
                    Icon(
                        imageVector = Icons.Filled.CheckCircle,
                        contentDescription = null,
                        tint = DirectSwitchTheme.green,
                        modifier = Modifier.size(18.dp)
                    )
                    Text(
                        text = "${installedApps.size} app già presenti sul telefono (nascoste)",
                        fontSize = 13.sp,
                        fontWeight = FontWeight.SemiBold,
                        color = DirectSwitchTheme.green
                    )
                }
                Text(
                    text = if (showAlreadyInstalled) "Nascondi" else "Mostra tutte",
                    fontSize = 12.sp,
                    fontWeight = FontWeight.SemiBold,
                    color = DirectSwitchTheme.blue
                )
            }
            if (showAlreadyInstalled) {
                Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    installedApps.forEach { app ->
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.SpaceBetween
                        ) {
                            Text(
                                text = app.appName,
                                fontSize = 13.sp,
                                color = DirectSwitchTheme.textSecondary,
                                modifier = Modifier.weight(1f)
                            )
                            Text(
                                text = "Installata",
                                fontSize = 12.sp,
                                fontWeight = FontWeight.SemiBold,
                                color = DirectSwitchTheme.green
                            )
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Schermate sincronizzate (Collegato + Preparazione con conteggio rapido -> 0%)

@Composable
private fun ReceiverConnectedWizardView(
    peerDeviceName: String,
    onCancel: () -> Unit
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(top = 12.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(10.dp)
    ) {
        Box(
            modifier = Modifier
                .size(68.dp)
                .clip(CircleShape)
                .background(DirectSwitchTheme.green.copy(alpha = 0.16f)),
            contentAlignment = Alignment.Center
        ) {
            Icon(
                imageVector = Icons.Filled.CheckCircle,
                contentDescription = null,
                tint = DirectSwitchTheme.green,
                modifier = Modifier.size(40.dp)
            )
        }
        Text(
            text = DirectSwitchL10n.tr("Collegato!"),
            fontSize = 24.sp,
            fontWeight = FontWeight.Bold,
            color = DirectSwitchTheme.textPrimary
        )
        Text(
            text = DirectSwitchL10n.tr("Prosegui sull'altro telefono"),
            fontSize = 16.sp,
            fontWeight = FontWeight.SemiBold,
            color = DirectSwitchTheme.blue
        )
    }

    DirectSwitchCard(selected = true) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            AppleSettingsIcon(icon = Icons.AutoMirrored.Filled.ArrowForward, color = DirectSwitchTheme.blue)
            Column(verticalArrangement = Arrangement.spacedBy(3.dp), modifier = Modifier.weight(1f)) {
                Text(
                    text = peerDeviceName.ifBlank { DirectSwitchL10n.tr("Altro telefono collegato", en = "Other phone connected", fr = "Autre téléphone connecté") },
                    fontSize = 16.sp,
                    fontWeight = FontWeight.Bold,
                    color = DirectSwitchTheme.textPrimary
                )
                Text(
                    text = DirectSwitchL10n.tr(
                        "Scegli sull'altro telefono le categorie da copiare e tocca «Copia le voci selezionate».",
                        en = "Choose what to copy on the other phone and tap 'Copy selected items'.",
                        fr = "Choisissez les catégories sur l'autre téléphone puis touchez « Copier les éléments sélectionnés »."
                    ),
                    fontSize = 13.sp,
                    color = DirectSwitchTheme.textSecondary
                )
            }
        }
        HorizontalDivider(color = DirectSwitchTheme.hairline)
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.Center,
            verticalAlignment = Alignment.CenterVertically
        ) {
            CircularProgressIndicator(
                modifier = Modifier.size(16.dp),
                strokeWidth = 2.dp,
                color = DirectSwitchTheme.blue
            )
            Spacer(modifier = Modifier.size(10.dp))
            Text(
                text = DirectSwitchL10n.tr("In attesa della conferma sull'altro telefono...", en = "Waiting for confirmation on the other phone...", fr = "En attente de confirmation sur l'autre téléphone..."),
                fontSize = 13.sp,
                color = DirectSwitchTheme.textSecondary
            )
        }
    }

    DirectSwitchNeutralOutlinedButton(
        text = DirectSwitchL10n.tr("Annulla"),
        onClick = onCancel
    )
}

@Composable
private fun TransferPreparationWizardView(
    progress: LiveTransferProgress,
    isReceiver: Boolean,
    onPreparationCompleted: () -> Unit,
    onCancel: () -> Unit
) {
    val itemIdsKey = remember(progress.preparationItems) {
        progress.preparationItems.map { it.id }
    }
    val animatedCounts = remember(itemIdsKey) { mutableStateMapOf<String, Int>() }
    var didNotifyCompletion by remember(itemIdsKey) { mutableStateOf(false) }

    LaunchedEffect(progress.preparationItems, progress.arePreparationItemsReady, isReceiver) {
        if (isReceiver || progress.preparationItems.isEmpty()) return@LaunchedEffect
        while (true) {
            var allReached = true
            for (item in progress.preparationItems) {
                val current = animatedCounts[item.id] ?: 0
                if (current < item.targetCount) {
                    val remaining = item.targetCount - current
                    val stepDelta = maxOf(1, (remaining + 4) / 5)
                    animatedCounts[item.id] = minOf(item.targetCount, current + stepDelta)
                    allReached = false
                } else if (!item.isReady) {
                    allReached = false
                }
            }
            if (allReached && progress.arePreparationItemsReady) {
                if (!didNotifyCompletion) {
                    didNotifyCompletion = true
                    delay(180L)
                    onPreparationCompleted()
                }
                break
            }
            delay(22L)
        }
    }

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(top = 8.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        DirectSwitchAppleEmblem(size = 62.dp)
        Text(
            text = if (isReceiver) DirectSwitchL10n.tr("Sto preparando la ricezione…") else DirectSwitchL10n.tr("Sto preparando il trasferimento…"),
            fontSize = 22.sp,
            fontWeight = FontWeight.Bold,
            color = DirectSwitchTheme.textPrimary,
            textAlign = TextAlign.Center
        )
        Text(
            text = if (isReceiver) {
                DirectSwitchL10n.tr(
                    "L'altro telefono sta preparando e verificando i dati selezionati prima di iniziare da 0%.",
                    en = "The other phone is preparing and checking selected data before starting at 0%.",
                    fr = "L'autre téléphone prépare et vérifie les données avant de démarrer à 0%."
                )
            } else {
                DirectSwitchL10n.tr("Preparazione rapida e conteggio delle voci selezionate prima di partire dallo 0%.")
            },
            fontSize = 13.5.sp,
            color = DirectSwitchTheme.textSecondary,
            textAlign = TextAlign.Center
        )
    }

    DirectSwitchCard(padding = 0.dp, spacing = 0.dp) {
        if (progress.preparationItems.isEmpty()) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 16.dp, vertical = 18.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.Center
            ) {
                CircularProgressIndicator(modifier = Modifier.size(18.dp), strokeWidth = 2.dp, color = DirectSwitchTheme.blue)
                Spacer(modifier = Modifier.size(10.dp))
                Text(
                    text = DirectSwitchL10n.tr("Preparazione in corso..."),
                    fontSize = 14.sp,
                    color = DirectSwitchTheme.textSecondary
                )
            }
        } else {
            progress.preparationItems.forEachIndexed { index, item ->
                if (index > 0) {
                    HorizontalDivider(modifier = Modifier.padding(start = 56.dp), color = DirectSwitchTheme.hairline)
                }
                val (icon, iconColor) = preparationCategoryStyle(item.id)
                val shownCount = if (isReceiver) {
                    item.targetCount
                } else {
                    animatedCounts[item.id] ?: 0
                }
                val rowDone = if (isReceiver) {
                    progress.arePreparationItemsReady
                } else {
                    item.isReady && shownCount >= item.targetCount
                }
                val locUnit = if (shownCount == 1) DirectSwitchL10n.tr(item.unitSingular) else DirectSwitchL10n.tr(item.unitPlural)
                val statusLabel = when {
                    isReceiver && !progress.arePreparationItemsReady && item.targetCount == 0 -> DirectSwitchL10n.tr("In preparazione...", en = "Preparing...", fr = "Préparation...")
                    !isReceiver && !item.isReady && shownCount == 0 -> DirectSwitchL10n.tr("Analisi...", en = "Scanning...", fr = "Analyse...")
                    else -> "$shownCount $locUnit"
                }

                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 14.dp, vertical = 12.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.SpaceBetween
                ) {
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(12.dp),
                        modifier = Modifier.weight(1f)
                    ) {
                        AppleSettingsIcon(icon = icon, color = iconColor)
                        Text(
                            text = DirectSwitchL10n.tr(item.title),
                            fontSize = 15.sp,
                            fontWeight = FontWeight.Medium,
                            color = DirectSwitchTheme.textPrimary
                        )
                    }
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        Text(
                            text = statusLabel,
                            fontSize = 14.sp,
                            fontWeight = FontWeight.SemiBold,
                            color = if (rowDone) DirectSwitchTheme.green else DirectSwitchTheme.blue
                        )
                        if (rowDone) {
                            Icon(
                                imageVector = Icons.Filled.CheckCircle,
                                contentDescription = null,
                                tint = DirectSwitchTheme.green,
                                modifier = Modifier.size(17.dp)
                            )
                        } else {
                            CircularProgressIndicator(
                                modifier = Modifier.size(15.dp),
                                strokeWidth = 2.dp,
                                color = DirectSwitchTheme.blue
                            )
                        }
                    }
                }
            }
        }
    }

    DirectSwitchNeutralOutlinedButton(
        text = DirectSwitchL10n.tr("Annulla"),
        onClick = onCancel
    )
}

private fun preparationCategoryStyle(id: String): Pair<ImageVector, Color> = when (id) {
    "contacts" -> Icons.Filled.Contacts to DirectSwitchTheme.blue
    "photos" -> Icons.Filled.Image to DirectSwitchTheme.orange
    "videos" -> Icons.Filled.Videocam to DirectSwitchTheme.red
    "calendars" -> Icons.Filled.CalendarMonth to DirectSwitchTheme.indigo
    "sms" -> Icons.Filled.Sms to DirectSwitchTheme.green
    "documents" -> Icons.Filled.Description to DirectSwitchTheme.teal
    "apps" -> Icons.Filled.Apps to DirectSwitchTheme.blue
    else -> Icons.Filled.Folder to DirectSwitchTheme.slate
}

// MARK: - Scanner QR CameraX

@Composable
private fun QrCameraPreviewBox(onQrScanned: (String) -> Unit) {
    val context = LocalContext.current
    val lifecycleOwner = LocalLifecycleOwner.current
    val analyzerExecutor = remember { Executors.newSingleThreadExecutor() }
    val emittedOnce = remember { AtomicBoolean(false) }
    val mainExecutor = remember(context) { ContextCompat.getMainExecutor(context) }

    DisposableEffect(Unit) {
        onDispose { analyzerExecutor.shutdown() }
    }

    AndroidView(
        modifier = Modifier
            .fillMaxWidth()
            .height(220.dp)
            .clip(RoundedCornerShape(14.dp)),
        factory = { ctx ->
            val previewView = PreviewView(ctx).apply {
                layoutParams = ViewGroup.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT,
                    ViewGroup.LayoutParams.MATCH_PARENT
                )
            }
            val cameraProviderFuture = ProcessCameraProvider.getInstance(ctx)
            cameraProviderFuture.addListener({
                val provider = cameraProviderFuture.get()
                val preview = Preview.Builder().build().also {
                    it.setSurfaceProvider(previewView.surfaceProvider)
                }
                val analysis = ImageAnalysis.Builder()
                    .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
                    .build()
                    .also { imgAnalysis ->
                        imgAnalysis.setAnalyzer(analyzerExecutor) { imageProxy ->
                            decodeQrFromFrame(imageProxy) { decodedText ->
                                if (emittedOnce.compareAndSet(false, true)) {
                                    mainExecutor.execute { onQrScanned(decodedText) }
                                }
                            }
                        }
                    }
                runCatching {
                    provider.unbindAll()
                    provider.bindToLifecycle(
                        lifecycleOwner,
                        CameraSelector.DEFAULT_BACK_CAMERA,
                        preview,
                        analysis
                    )
                }.onFailure { t ->
                    DirectSwitchLog.warn("Bind CameraX fallito", t)
                }
            }, mainExecutor)
            previewView
        }
    )
}

private val qrDecodeHints = mapOf(
    DecodeHintType.POSSIBLE_FORMATS to listOf(BarcodeFormat.QR_CODE),
    DecodeHintType.TRY_HARDER to true,
    DecodeHintType.CHARACTER_SET to "UTF-8"
)

private fun decodeQrFromFrame(imageProxy: ImageProxy, onQrScanned: (String) -> Unit) {
    try {
        val plane = imageProxy.planes.firstOrNull() ?: return
        val width = imageProxy.width
        val height = imageProxy.height
        if (width <= 0 || height <= 0) return

        val buffer = plane.buffer
        val rowStride = plane.rowStride
        val pixelStride = plane.pixelStride
        val yBytes = ByteArray(width * height)

        buffer.rewind()
        if (pixelStride == 1 && rowStride == width && buffer.remaining() >= width * height) {
            buffer.get(yBytes, 0, width * height)
        } else {
            val rowBuf = ByteArray(rowStride)
            for (row in 0 until height) {
                val rowOffset = row * rowStride
                if (rowOffset >= buffer.limit()) break
                buffer.position(rowOffset)
                val toRead = minOf(rowStride, buffer.remaining())
                buffer.get(rowBuf, 0, toRead)
                if (pixelStride == 1) {
                    System.arraycopy(rowBuf, 0, yBytes, row * width, minOf(width, toRead))
                } else {
                    for (col in 0 until width) {
                        val srcIdx = col * pixelStride
                        if (srcIdx < toRead) {
                            yBytes[row * width + col] = rowBuf[srcIdx]
                        }
                    }
                }
            }
        }

        val source = PlanarYUVLuminanceSource(
            yBytes,
            width,
            height,
            0,
            0,
            width,
            height,
            false
        )
        val binaryBitmap = BinaryBitmap(HybridBinarizer(source))
        val result = QRCodeReader().decode(binaryBitmap, qrDecodeHints)
        if (!result.text.isNullOrBlank()) {
            onQrScanned(result.text)
        }
    } catch (_: ReaderException) {
        // Normale sui frame privi di codice QR
    } catch (t: Throwable) {
        DirectSwitchLog.warn("Errore imprevisto analisi frame fotocamera", t)
    } finally {
        imageProxy.close()
    }
}

private fun formatMb(bytes: Long): String = TransferDisplayFormatting.formatBytes(bytes)
