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
import androidx.compose.material.icons.filled.CalendarMonth
import androidx.compose.material.icons.filled.CheckCircle
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
import com.directswitch.android.migrators.CalendarMigrator
import com.directswitch.android.migrators.ContactsPreloadState
import com.directswitch.android.migrators.ContactsSmartMerger
import com.directswitch.android.migrators.DateSyncPreloadState
import com.directswitch.android.migrators.DeviceDataAnalyzer
import com.directswitch.android.migrators.DocumentPrecheckReport
import com.directswitch.android.migrators.DocumentsAndWhatsAppScanner
import com.directswitch.android.migrators.GoogleSetupBridge
import com.directswitch.android.migrators.InstalledAppCategoryGroup
import com.directswitch.android.migrators.InstalledAppsScanner
import com.directswitch.android.migrators.LocalDeviceScanSummary
import com.directswitch.android.migrators.MediaExifScannerAndImporter
import com.directswitch.android.migrators.PhotosPreloadState
import com.directswitch.android.protocol.TransferDisplayFormatting
import com.directswitch.android.migrators.SmsSystemScanner
import com.directswitch.android.migrators.VideosPreloadState
import com.directswitch.android.protocol.DevicePlatform
import com.directswitch.android.protocol.DiscoveryBeaconPayload
import com.directswitch.android.protocol.InstalledAppRecord
import com.directswitch.android.protocol.QrPairingPayload
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
    TRANSFER_PROGRESS,
    QUICK_PORTAL
}

private data class CategorySelectionState(
    val contacts: Boolean = false,
    val photos: Boolean = false,
    val videos: Boolean = false,
    val calendars: Boolean = false,
    val sms: Boolean = false,
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
    val context = LocalContext.current
    val scope = rememberCoroutineScope()

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

    var bootstrapPortalUrl by remember { mutableStateOf<String?>(null) }
    var bootstrapWifiQrString by remember { mutableStateOf<String?>(null) }
    var vaultStatusNote by remember { mutableStateOf<String?>(null) }
    var pendingDocPrecheckReport by remember { mutableStateOf<DocumentPrecheckReport?>(null) }

    var categories by remember { mutableStateOf(CategorySelectionState()) }
    var calendarsUpToTodayOnly by remember { mutableStateOf(false) }
    var smsUpToTodayOnly by remember { mutableStateOf(false) }
    var contactsPreload by remember { mutableStateOf(ContactsPreloadState()) }
    var photosPreload by remember { mutableStateOf(PhotosPreloadState()) }
    var videosPreload by remember { mutableStateOf(VideosPreloadState()) }
    var calendarsSync by remember { mutableStateOf(DateSyncPreloadState()) }
    var smsSync by remember { mutableStateOf(DateSyncPreloadState()) }
    var detectedAppsCatalog by remember { mutableStateOf<List<InstalledAppRecord>>(emptyList()) }
    var groupedAppCategories by remember { mutableStateOf<List<InstalledAppCategoryGroup>>(emptyList()) }
    var deselectedAppPackages by remember { mutableStateOf<Set<String>>(emptySet()) }
    var isLoadingAppsCatalog by remember { mutableStateOf(false) }
    var isReceiverFlow by remember { mutableStateOf(false) }

    var showGoogleBridgeSheet by remember { mutableStateOf(false) }
    var googleBridgeNote by remember { mutableStateOf<String?>(null) }
    var pendingPermissionContinuation by remember { mutableStateOf<(() -> Unit)?>(null) }

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

    fun buildRequiredPermissions(): List<String> {
        val perms = mutableListOf(
            Manifest.permission.READ_CONTACTS,
            Manifest.permission.WRITE_CONTACTS,
            Manifest.permission.READ_CALENDAR,
            Manifest.permission.WRITE_CALENDAR,
            Manifest.permission.READ_SMS,
            Manifest.permission.CAMERA
        )
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            perms.add(Manifest.permission.READ_MEDIA_IMAGES)
            perms.add(Manifest.permission.READ_MEDIA_VIDEO)
            perms.add(Manifest.permission.NEARBY_WIFI_DEVICES)
            perms.add(Manifest.permission.POST_NOTIFICATIONS)
        } else {
            perms.add(Manifest.permission.READ_EXTERNAL_STORAGE)
            perms.add(Manifest.permission.ACCESS_FINE_LOCATION)
        }
        return perms
    }

    fun requestPermissionsThen(actionAfter: (() -> Unit)? = null) {
        val missing = buildRequiredPermissions().filter { perm ->
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
        if (!prev.photos && next.photos) {
            val photoPerm = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) Manifest.permission.READ_MEDIA_IMAGES else Manifest.permission.READ_EXTERNAL_STORAGE
            schedule(MediaExifScannerAndImporter.hasPhotoPermission(context), listOf(photoPerm)) { startPhotosPreload() }
        }
        if (!prev.videos && next.videos) {
            val videoPerm = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) Manifest.permission.READ_MEDIA_VIDEO else Manifest.permission.READ_EXTERNAL_STORAGE
            schedule(MediaExifScannerAndImporter.hasVideoPermission(context), listOf(videoPerm)) { startVideosPreload() }
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
        contactsPreload = ContactsPreloadState()
        photosPreload = PhotosPreloadState()
        videosPreload = VideosPreloadState()
        calendarsSync = DateSyncPreloadState()
        smsSync = DateSyncPreloadState()
        deselectedAppPackages = emptySet()
    }

    fun resetAndGoHome() {
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
        bootstrapPortalUrl = null
        bootstrapWifiQrString = null
        resetCategorySelectionsAndPreloads()
        step = WizardStep.HOME
    }

    fun handleBack() {
        when (step) {
            WizardStep.HOME -> Unit
            WizardStep.RECEIVER_WAIT_CODE,
            WizardStep.RECEIVER_CONNECTED,
            WizardStep.TRANSFER_PREPARING,
            WizardStep.QUICK_PORTAL,
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

    fun launchSenderTransfer(targetPayload: QrPairingPayload) {
        pendingDocPrecheckReport = null
        isReceiverFlow = false
        vaultStatusNote = null
        val appsOverride = if (categories.installedApps && detectedAppsCatalog.isNotEmpty()) {
            detectedAppsCatalog.filter { it.packageName !in deselectedAppPackages }
        } else null
        val isWhatsAppOnly = targetPayload.receiverPlatform != DevicePlatform.IOS &&
            categories.whatsAppVault &&
            !categories.contacts && !categories.photos && !categories.videos &&
            !categories.calendars && !categories.sms && !categories.documents &&
            !categories.installedApps
        step = if (isWhatsAppOnly) WizardStep.TRANSFER_PROGRESS else WizardStep.TRANSFER_PREPARING
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
                installedAppsOverride = appsOverride
            )
        }
    }

    val topTitle = when (step) {
        WizardStep.HOME -> "DirectSwitch"
        WizardStep.RECEIVER_WAIT_CODE -> "Ricevi dati"
        WizardStep.RECEIVER_CONNECTED -> "Collegato"
        WizardStep.SENDER_CONNECT -> "Collega telefono"
        WizardStep.SENDER_SELECT_CATEGORIES -> "Cosa copiare"
        WizardStep.TRANSFER_PREPARING -> "Preparazione"
        WizardStep.TRANSFER_PROGRESS -> {
            val done = if (isReceiverFlow) serverProgress.isCompleted else clientProgress.isCompleted
            if (done) "Completato" else "Copia dati"
        }
        WizardStep.QUICK_PORTAL -> "QR Rapido"
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
                        onStartReceive = {
                            requestPermissionsThen {
                                isReceiverFlow = true
                                val payload = server.startReceiverSession()
                                activeQrPayload = payload
                                autoDiscovery.startAdvertisingReceiver(payload)
                                step = WizardStep.RECEIVER_WAIT_CODE
                            }
                        },
                        onStartSend = {
                            requestPermissionsThen {
                                isReceiverFlow = false
                                pairedTargetPayload = null
                                selectedBeaconForPin = null
                                pinInput = ""
                                pinErrorNote = null
                                resetCategorySelectionsAndPreloads()
                                autoDiscovery.startScanningForNewDevices()
                                step = WizardStep.SENDER_CONNECT
                            }
                        },
                        onOpenGoogleBridge = {
                            googleBridgeNote = null
                            showGoogleBridgeSheet = true
                        },
                        onOpenQuickPortal = {
                            requestPermissionsThen {
                                if (LocalNetworkAddresses.listPrivateIpv4Addresses().isNotEmpty()) {
                                    bootstrapWifiQrString = null
                                    bootstrapPortalUrl = server.startBootstrapPortalSession()
                                    step = WizardStep.QUICK_PORTAL
                                } else {
                                    hotspotController.startHotspot { ssid, pass, _ ->
                                        if (!ssid.isNullOrBlank() && !pass.isNullOrBlank()) {
                                            val escSsid = ssid.replace("\\", "\\\\").replace(";", "\\;").replace(",", "\\,").replace(":", "\\:")
                                            val escPass = pass.replace("\\", "\\\\").replace(";", "\\;").replace(",", "\\,").replace(":", "\\:")
                                            bootstrapWifiQrString = "WIFI:T:WPA;S:$escSsid;P:$escPass;;"
                                        } else {
                                            bootstrapWifiQrString = null
                                        }
                                        bootstrapPortalUrl = server.startBootstrapPortalSession()
                                        step = WizardStep.QUICK_PORTAL
                                    }
                                }
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
                        onToggleCamera = { showCameraScanner = !showCameraScanner },
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
                            contactsPreload = contactsPreload,
                            photosPreload = photosPreload,
                            videosPreload = videosPreload,
                            calendarsSync = calendarsSync,
                            smsSync = smsSync,
                            detectedAppsCatalog = detectedAppsCatalog,
                            groupedAppCategories = groupedAppCategories,
                            deselectedAppPackages = deselectedAppPackages,
                            isLoadingApps = isLoadingAppsCatalog,
                            vaultStatusNote = vaultStatusNote,
                            onUpdateCategories = { updateCategoriesAndTriggerPreloads(it) },
                            onToggleCalendarsUpToToday = { calendarsUpToTodayOnly = it },
                            onToggleSmsUpToToday = { smsUpToTodayOnly = it },
                            onRequestContactsPermission = {
                                requestSpecificPermissionsThen(listOf(Manifest.permission.READ_CONTACTS, Manifest.permission.WRITE_CONTACTS)) { startContactsPreload() }
                            },
                            onRequestPhotosPermission = {
                                val photoPerm = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) Manifest.permission.READ_MEDIA_IMAGES else Manifest.permission.READ_EXTERNAL_STORAGE
                                requestSpecificPermissionsThen(listOf(photoPerm)) { startPhotosPreload() }
                            },
                            onRequestVideosPermission = {
                                val videoPerm = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) Manifest.permission.READ_MEDIA_VIDEO else Manifest.permission.READ_EXTERNAL_STORAGE
                                requestSpecificPermissionsThen(listOf(videoPerm)) { startVideosPreload() }
                            },
                            onRequestCalendarsPermission = {
                                requestSpecificPermissionsThen(listOf(Manifest.permission.READ_CALENDAR, Manifest.permission.WRITE_CALENDAR)) { refreshCalendarsSync() }
                            },
                            onRequestSmsPermission = {
                                requestSpecificPermissionsThen(listOf(Manifest.permission.READ_SMS)) { refreshSmsSync() }
                            },
                            onReloadContacts = { startContactsPreload() },
                            onReloadPhotos = { startPhotosPreload() },
                            onReloadVideos = { startVideosPreload() },
                            onRefreshCalendars = { refreshCalendarsSync() },
                            onRefreshSms = { refreshSmsSync() },
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
                            onStartTransfer = {
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
                        onFinish = { resetAndGoHome() }
                    )
                }

                WizardStep.QUICK_PORTAL -> {
                    QuickPortalWizardView(
                        wifiQrString = bootstrapWifiQrString,
                        portalUrl = bootstrapPortalUrl,
                        onClose = { resetAndGoHome() }
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
                    text = "Controllo posizioni sul telefono",
                    fontWeight = FontWeight.Bold,
                    color = DirectSwitchTheme.textPrimary
                )
            },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text(
                        text = when {
                            noneSelected ->
                                "Nessuna posizione è selezionata con la spunta. Seleziona almeno una posizione da trasferire nell'elenco oppure aggiungine un'altra."
                            missingAllFiles ->
                                "Per leggere e copiare le posizioni intere del telefono (Memoria interna, Download, Documenti, Scheda SD) ricreandole identiche sul nuovo telefono, attiva «Accesso a tutti i file»."
                            activePrecheck.totalFiles == 0 ->
                                "Nessun documento o file rilevato nelle posizioni selezionate al momento. Puoi aggiungere un'altra posizione (es. SD, USB o Drive) oppure continuare comunque."
                            else ->
                                "Pronte ${maxOf(1, accessibleLocations.size)} posizioni selezionate (${activePrecheck.totalFiles} file in ${activePrecheck.folderSummaries.size} cartelle)."
                        },
                        fontSize = 13.sp,
                        color = DirectSwitchTheme.textSecondary
                    )
                    if (activePrecheck.locationSummaries.isNotEmpty()) {
                        Text(
                            text = "Posizioni: " +
                                activePrecheck.locationSummaries.joinToString(" • ") {
                                    val prefix = if (it.isSelected) "✓ " else "○ "
                                    if (it.isAccessible) "$prefix${it.locationName} (${it.fileCount} file)"
                                    else "$prefix${it.locationName} (accesso richiesto)"
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
                        Text("Autorizza accesso completo", fontWeight = FontWeight.Bold, color = DirectSwitchTheme.blue)
                    }
                } else {
                    TextButton(
                        onClick = {
                            pendingDocPrecheckReport = null
                            folderTreePickerLauncher.launch(null)
                        }
                    ) {
                        Text("Autorizza posizione", fontWeight = FontWeight.Bold, color = DirectSwitchTheme.blue)
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
                            Text("Autorizza posizione", color = DirectSwitchTheme.blue)
                        }
                    }
                    TextButton(
                        onClick = { launchSenderTransfer(activePrecheckTarget) }
                    ) {
                        Text("Continua lo stesso", color = DirectSwitchTheme.textSecondary)
                    }
                }
            }
        )
    }

    if (showGoogleBridgeSheet) {
        val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
        ModalBottomSheet(
            onDismissRequest = { showGoogleBridgeSheet = false },
            sheetState = sheetState,
            containerColor = DirectSwitchTheme.canvasMid
        ) {
            GoogleSetupBridgeSheetContent(
                note = googleBridgeNote,
                onLaunchNewAndroidRestore = {
                    val (_, msg) = GoogleSetupBridge.launchNewPhonePostSetupRestore(context)
                    googleBridgeNote = msg
                },
                onLaunchIphoneToAndroidCable = {
                    val (_, msg) = GoogleSetupBridge.launchIphoneToAndroidGoogleRestore(context, preferWirelessQr = true)
                    googleBridgeNote = msg
                },
                onLaunchOldAndroidSend = {
                    val (_, msg) = GoogleSetupBridge.launchOldPhoneGoogleNearbySetup(context)
                    googleBridgeNote = msg
                },
                onClose = { showGoogleBridgeSheet = false }
            )
        }
    }
}

// MARK: - 1. Home pulita (solo Invia sopra e Ricevi sotto, sottotitoli dentro ⓘ)

@Composable
private fun AndroidHomeView(
    onStartReceive: () -> Unit,
    onStartSend: () -> Unit,
    onOpenGoogleBridge: () -> Unit,
    onOpenQuickPortal: () -> Unit
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(top = 20.dp, bottom = 12.dp),
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
                message = "Copia i tuoi dati senza formattare: trasferisce rubrica, foto, video 4K, calendari, SMS, documenti e chat WhatsApp direttamente tra due telefoni già configurati, senza passare dal cloud."
            )
        }
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
                    text = "Invia",
                    fontSize = 19.sp,
                    fontWeight = FontWeight.Bold,
                    color = DirectSwitchTheme.textPrimary
                )
            }
            InfoCircleButton(
                title = "Invia",
                message = "Invia i dati da questo telefono direttamente senza cavo all'altro telefono (Android o iPhone) dove hai aperto 'Ricevi'."
            )
        }

        DirectSwitchPrimaryButton(
            text = "Invia",
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
                    text = "Ricevi",
                    fontSize = 19.sp,
                    fontWeight = FontWeight.Bold,
                    color = DirectSwitchTheme.textPrimary
                )
            }
            InfoCircleButton(
                title = "Ricevi",
                message = "Mostra il codice monouso a 6 cifre (come 'Passa a iOS') o il codice QR per ricevere i dati dal tuo altro telefono senza cancellare nulla."
            )
        }

        DirectSwitchPrimaryButton(
            text = "Ricevi",
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
            text = "Passo 1 di 2",
            fontSize = 13.sp,
            fontWeight = FontWeight.SemiBold,
            color = DirectSwitchTheme.blue
        )
        InfoCircleButton(
            title = "Come collegare i telefoni",
            message = "Apri DirectSwitch sul vecchio telefono, tocca 'Invia al nuovo telefono' e digita il codice a 6 cifre mostrato qui sotto, oppure passa a 'Codice QR' per inquadrarlo (anche senza rete Wi-Fi attivando l'Hotspot 5GHz)."
        )
    }

    Column(
        modifier = Modifier.fillMaxWidth(),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(6.dp)
    ) {
        Text(
            text = if (selectedTab == 0) "Inserisci il codice monouso" else "Inquadra il codice QR",
            fontSize = 22.sp,
            fontWeight = FontWeight.Bold,
            color = DirectSwitchTheme.textPrimary,
            textAlign = TextAlign.Center
        )
        Text(
            text = "Apri DirectSwitch sul vecchio telefono e tocca Invia",
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
            listOf("Codice a 6 cifre", "Codice QR").forEachIndexed { idx, label ->
                val active = selectedTab == idx
                Box(
                    modifier = Modifier
                        .weight(1f)
                        .clip(RoundedCornerShape(8.dp))
                        .background(if (active) Color.White else Color.Transparent)
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
                        text = "Visibile come ${qrPayload.receiverName}",
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
                        text = "Codice: $pairingPin",
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
                text = "In attesa di collegamento...",
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
                    Text("Hotspot diretto 5GHz", fontSize = 15.sp, fontWeight = FontWeight.Medium, color = DirectSwitchTheme.textPrimary)
                    Text(hotspotNote ?: "Usa senza rete Wi-Fi di casa", fontSize = 12.sp, color = DirectSwitchTheme.textSecondary)
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
                        Text("Salva SMS nell'app Messaggi", fontSize = 15.sp, fontWeight = FontWeight.Medium, color = DirectSwitchTheme.textPrimary)
                        Text("Tocca per abilitare l'importazione nativa", fontSize = 12.sp, color = DirectSwitchTheme.blue)
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
                                "Ricrea posizioni e cartelle originali",
                                fontSize = 15.sp,
                                fontWeight = FontWeight.Medium,
                                color = DirectSwitchTheme.textPrimary
                            )
                            Text(
                                "Autorizza «Accesso a tutti i file» per salvare intere posizioni nelle identiche cartelle di origine",
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
        text = "Annulla",
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
    showCameraScanner: Boolean,
    manualQrInput: String,
    onSelectBeacon: (DiscoveryBeaconPayload) -> Unit,
    onPinChange: (String) -> Unit,
    onConfirmPin: () -> Unit,
    onToggleCamera: () -> Unit,
    onQrScanned: (String) -> Unit,
    onManualInputChange: (String) -> Unit,
    onApplyManualCode: () -> Unit
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
        Text("Passo 1 di 3", fontSize = 13.sp, fontWeight = FontWeight.SemiBold, color = DirectSwitchTheme.blue)
        InfoCircleButton(
            title = "Come collegare il nuovo telefono",
            message = "Sul nuovo iPhone o Android apri DirectSwitch e tocca 'Ricevi'. Selezionalo qui sotto e inserisci il codice a 6 cifre, oppure usa 'Inquadra codice QR'."
        )
    }

    Column(
        modifier = Modifier.fillMaxWidth(),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(4.dp)
    ) {
        Text("Collega il nuovo telefono", fontSize = 22.sp, fontWeight = FontWeight.Bold, color = DirectSwitchTheme.textPrimary)
        Text("Seleziona il telefono rilevato o inquadra il codice QR", fontSize = 14.sp, color = DirectSwitchTheme.textSecondary)
    }

    DirectSwitchCard {
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.SpaceBetween
        ) {
            Text("Telefoni vicini", fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = DirectSwitchTheme.textPrimary)
            if (discoveredDevices.isEmpty()) {
                CircularProgressIndicator(modifier = Modifier.size(16.dp), strokeWidth = 2.dp, color = DirectSwitchTheme.blue)
            } else {
                val countLabel = if (discoveredDevices.size == 1) "1 trovato" else "${discoveredDevices.size} trovati"
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
                    Text("Ricerca sulla rete Wi-Fi...", fontSize = 14.sp, fontWeight = FontWeight.Medium, color = DirectSwitchTheme.textPrimary)
                    Text("Assicurati che 'Ricevi' sia aperto sull'altro telefono", fontSize = 12.sp, color = DirectSwitchTheme.textSecondary)
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
                                    if (beacon.receiverPlatform == DevicePlatform.IOS) "iPhone pronto a ricevere" else "Android pronto a ricevere",
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
                text = "Inserisci il codice a 6 cifre mostrato su ${selectedBeacon.receiverName}",
                fontSize = 13.sp,
                color = DirectSwitchTheme.textSecondary,
                modifier = Modifier.fillMaxWidth(),
                textAlign = TextAlign.Center
            )
            OutlinedTextField(
                value = pinInput,
                onValueChange = onPinChange,
                placeholder = { Text("Codice a 6 cifre") },
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.NumberPassword),
                modifier = Modifier.fillMaxWidth(),
                singleLine = true,
                shape = RoundedCornerShape(12.dp)
            )
            DirectSwitchPrimaryButton(
                text = if (isPinPairingBusy) "Collegamento in corso..." else "Continua",
                onClick = onConfirmPin,
                enabled = pinInput.length == 6 && !isPinPairingBusy
            )
        }
    }

    DirectSwitchCard {
        Text("Oppure usa la fotocamera", fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = DirectSwitchTheme.textPrimary)
        DirectSwitchSecondaryButton(
            text = if (showCameraScanner) "Chiudi fotocamera" else "Inquadra codice QR",
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
                text = if (showManualInput) "Nascondi inserimento manuale" else "Incolla codice di collegamento",
                fontSize = 13.sp,
                color = DirectSwitchTheme.textSecondary
            )
        }
        if (showManualInput) {
            OutlinedTextField(
                value = manualQrInput,
                onValueChange = onManualInputChange,
                placeholder = { Text("Incolla qui il codice") },
                modifier = Modifier.fillMaxWidth(),
                singleLine = true,
                shape = RoundedCornerShape(12.dp)
            )
            if (manualQrInput.isNotBlank()) {
                DirectSwitchPrimaryButton(text = "Collega", onClick = onApplyManualCode)
            }
        }
    }

    if (!errorNote.isNullOrBlank()) {
        DirectSwitchCard(padding = 14.dp) {
            Text(errorNote, fontSize = 13.sp, fontWeight = FontWeight.Medium, color = DirectSwitchTheme.red)
        }
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
    contactsPreload: ContactsPreloadState,
    photosPreload: PhotosPreloadState,
    videosPreload: VideosPreloadState,
    calendarsSync: DateSyncPreloadState,
    smsSync: DateSyncPreloadState,
    detectedAppsCatalog: List<InstalledAppRecord>,
    groupedAppCategories: List<InstalledAppCategoryGroup>,
    deselectedAppPackages: Set<String>,
    isLoadingApps: Boolean,
    vaultStatusNote: String?,
    onUpdateCategories: (CategorySelectionState) -> Unit,
    onToggleCalendarsUpToToday: (Boolean) -> Unit,
    onToggleSmsUpToToday: (Boolean) -> Unit,
    onRequestContactsPermission: () -> Unit,
    onRequestPhotosPermission: () -> Unit,
    onRequestVideosPermission: () -> Unit,
    onRequestCalendarsPermission: () -> Unit,
    onRequestSmsPermission: () -> Unit,
    onReloadContacts: () -> Unit,
    onReloadPhotos: () -> Unit,
    onReloadVideos: () -> Unit,
    onRefreshCalendars: () -> Unit,
    onRefreshSms: () -> Unit,
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
    onStartTransfer: () -> Unit
) {
    val wizardContext = LocalContext.current
    val isCrossOs = pairedPayload.receiverPlatform == DevicePlatform.IOS
    val allSelected = categories.contacts && categories.photos && categories.videos &&
        categories.calendars && categories.sms && categories.documents &&
        (isCrossOs || categories.whatsAppVault) && categories.installedApps
    val anySelected = categories.contacts || categories.photos || categories.videos ||
        categories.calendars || categories.sms || categories.documents ||
        (!isCrossOs && categories.whatsAppVault) || categories.installedApps

    Row(
        modifier = Modifier.fillMaxWidth(),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.SpaceBetween
    ) {
        Text("Passo 2 di 3", fontSize = 13.sp, fontWeight = FontWeight.SemiBold, color = DirectSwitchTheme.blue)
        Text(
            text = if (allSelected) "Deseleziona tutto" else "Seleziona tutto",
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
                        "Collegato a ${pairedPayload.receiverName}",
                        fontSize = 15.sp,
                        fontWeight = FontWeight.SemiBold,
                        color = DirectSwitchTheme.textPrimary
                    )
                    InfoCircleButton(
                        title = "Stato collegamento",
                        message = "Collegamento diretto attivo e pronto al trasferimento completo dei dati selezionati senza resettare il telefono."
                    )
                }
            }
            Text(
                text = "Cambia",
                fontSize = 13.sp,
                fontWeight = FontWeight.SemiBold,
                color = DirectSwitchTheme.blue,
                modifier = Modifier.clickable(onClick = onChangeDevice)
            )
        }
    }

    Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
        Text("Cosa inviare", fontSize = 20.sp, fontWeight = FontWeight.Bold, color = DirectSwitchTheme.textPrimary)
        Text(
            text = "Spunta ogni voce per aprire la configurazione del passaggio al nuovo telefono.",
            fontSize = 12.5.sp,
            color = DirectSwitchTheme.textSecondary
        )
    }

    val contactsTotal = maxOf(contactsPreload.totalCount, summary?.contactsCount ?: 0)
    val contactsLoaded = if (contactsPreload.isCompleted) contactsTotal else contactsPreload.loadedCount
    CategoryDropdownCard(
        icon = Icons.Filled.Contacts,
        iconColor = DirectSwitchTheme.blue,
        title = "Rubrica contatti",
        countBadge = if (contactsTotal > 0) "$contactsTotal contatti" else null,
        checked = categories.contacts,
        onCheckedChange = { onUpdateCategories(categories.copy(contacts = it)) }
    ) {
        ProgressivePreloadDropdownBody(
            hasPermission = ContactsSmartMerger.hasReadPermission(wizardContext),
            permissionTitle = "Permesso Contatti richiesto per preparare la rubrica.",
            onRequestPermission = onRequestContactsPermission,
            isLoading = contactsPreload.isLoading,
            loadedCount = contactsLoaded,
            totalCount = contactsTotal,
            loadingLabel = "Precaricamento rubrica: $contactsLoaded / ${maxOf(contactsLoaded, contactsTotal)} contatti",
            readyLabel = "$contactsTotal contatti totali preparati",
            detailLabel = "Include numeri con etichette, foto profilo, email, indirizzi e compleanni con unione duplicati.",
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
        title = "Foto e Album",
        countBadge = if (photosTotal > 0) "$photosTotal foto • ${formatMb(photosBytes)}" else null,
        checked = categories.photos,
        onCheckedChange = { onUpdateCategories(categories.copy(photos = it)) }
    ) {
        ProgressivePreloadDropdownBody(
            hasPermission = MediaExifScannerAndImporter.hasPhotoPermission(wizardContext),
            permissionTitle = "Permesso Foto richiesto per preparare immagini e album.",
            onRequestPermission = onRequestPhotosPermission,
            isLoading = photosPreload.isLoading,
            loadedCount = photosLoaded,
            totalCount = photosTotal,
            loadingLabel = "Precaricamento immagini: $photosLoaded / ${maxOf(photosLoaded, photosTotal)} foto",
            readyLabel = "$photosTotal foto totali preparate",
            detailLabel = "$photosAlbums album rilevati • ${formatMb(photosBytes)} in qualità originale.",
            accentColor = DirectSwitchTheme.orange,
            onReload = onReloadPhotos
        )
    }

    val videosTotal = maxOf(videosPreload.totalCount, summary?.videosCount ?: 0)
    val videosLoaded = if (videosPreload.isCompleted) videosTotal else videosPreload.loadedCount
    val videosBytes = maxOf(videosPreload.estimatedBytes, summary?.videosBytes ?: 0L)
    CategoryDropdownCard(
        icon = Icons.Filled.Videocam,
        iconColor = DirectSwitchTheme.red,
        title = "Video originali",
        countBadge = if (videosTotal > 0) "$videosTotal video • ${formatMb(videosBytes)}" else null,
        checked = categories.videos,
        onCheckedChange = { onUpdateCategories(categories.copy(videos = it)) }
    ) {
        ProgressivePreloadDropdownBody(
            hasPermission = MediaExifScannerAndImporter.hasVideoPermission(wizardContext),
            permissionTitle = "Permesso Video richiesto per preparare i filmati originali.",
            onRequestPermission = onRequestVideosPermission,
            isLoading = videosPreload.isLoading,
            loadedCount = videosLoaded,
            totalCount = videosTotal,
            loadingLabel = "Precaricamento video: $videosLoaded / ${maxOf(videosLoaded, videosTotal)} video",
            readyLabel = "$videosTotal video originali preparati",
            detailLabel = "Qualità 4K e Slow-Motion preservata • ${formatMb(videosBytes)}.",
            accentColor = DirectSwitchTheme.red,
            onReload = onReloadVideos
        )
    }

    val activeCalCount = if (calendarsUpToTodayOnly) {
        calendarsSync.totalUpToTodayCount
    } else {
        maxOf(calendarsSync.totalAllCount, summary?.calendarEventsCount ?: 0)
    }
    CategoryDropdownCard(
        icon = Icons.Filled.CalendarMonth,
        iconColor = DirectSwitchTheme.indigo,
        title = "Calendari",
        countBadge = if (activeCalCount > 0) "$activeCalCount eventi" else null,
        checked = categories.calendars,
        onCheckedChange = { onUpdateCategories(categories.copy(calendars = it)) }
    ) {
        DateSyncDropdownBody(
            hasPermission = CalendarMigrator.hasReadPermission(wizardContext),
            permissionTitle = "Permesso Calendario richiesto per leggere gli eventi.",
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
        title = "Messaggi SMS",
        countBadge = if (activeSmsCount > 0) "$activeSmsCount messaggi" else null,
        checked = categories.sms,
        onCheckedChange = { onUpdateCategories(categories.copy(sms = it)) }
    ) {
        DateSyncDropdownBody(
            hasPermission = SmsSystemScanner.hasReadPermission(wizardContext),
            permissionTitle = "Permesso SMS richiesto per preparare i messaggi.",
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

    val locationSummaries = summary?.documentLocationSummaries.orEmpty()
    val hasAllFiles = summary?.hasAllFilesAccess ?: DocumentsAndWhatsAppScanner.hasAllFilesAccess(wizardContext)
    val hasPickedLocations = !vaultStatusNote.isNullOrBlank() ||
        remember(summary) { DocumentsAndWhatsAppScanner.getPersistedFolderTreeUris(wizardContext).isNotEmpty() }
    val docsBadge = summary?.let {
        if (it.documentsCount > 0) "${maxOf(1, it.documentFoldersCount)} cartelle • ${it.documentsCount} file"
        else "Memoria interna, Drive, SD"
    }
    CategoryDropdownCard(
        icon = Icons.Filled.Description,
        iconColor = DirectSwitchTheme.teal,
        title = "Documenti e Posizioni File",
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
    }

    if (!isCrossOs) {
        CategoryDropdownCard(
            icon = Icons.AutoMirrored.Filled.Chat,
            iconColor = DirectSwitchTheme.green,
            title = "Chat WhatsApp",
            countBadge = "Gratuito • Codice QR",
            checked = categories.whatsAppVault,
            onCheckedChange = { onUpdateCategories(categories.copy(whatsAppVault = it)) }
        ) {
            WhatsAppDropdownBody(isCrossOs = false)
        }
    }

    val effectiveAppsCatalog = detectedAppsCatalog
    val selectedAppsCount = if (effectiveAppsCatalog.isNotEmpty()) {
        effectiveAppsCatalog.count { it.packageName !in deselectedAppPackages }
    } else {
        summary?.installedAppsCount ?: 0
    }
    CategoryDropdownCard(
        icon = Icons.Filled.Apps,
        iconColor = DirectSwitchTheme.blue,
        title = "App scaricate",
        countBadge = if (selectedAppsCount > 0) "$selectedAppsCount app pronte" else null,
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
            onRefreshApps = onRefreshApps
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
                    text = "App, Account Mail e Impostazioni",
                    fontSize = 14.sp,
                    fontWeight = FontWeight.SemiBold,
                    color = DirectSwitchTheme.textPrimary
                )
            }
            InfoCircleButton(
                title = "Confronto con Passa a Android / Passa a iOS",
                message = "• App installate: DirectSwitch trasferisce l'elenco completo delle tue app per riscaricarle con 1 tocco da App Store o Play Store sul telefono ricevente.\n• Account Mail (Gmail, iCloud, Outlook): per sicurezza Apple/Google le password non viaggiano mai in chiaro; a fine copia trovi il pulsante rapido per collegare il tuo account e riavere tutte le email.\n• Impostazioni di sistema: non vengono sovrascritte, così il telefono ricevente non viene né formattato né alterato."
            )
        }
    }

    val isOnlyWhatsAppSelected = !isCrossOs && categories.whatsAppVault &&
        !categories.contacts && !categories.photos && !categories.videos &&
        !categories.calendars && !categories.sms && !categories.documents &&
        !categories.installedApps

    DirectSwitchPrimaryButton(
        text = if (isOnlyWhatsAppSelected) "Vai al passaggio Chat WhatsApp" else "Copia le voci selezionate",
        onClick = onStartTransfer,
        enabled = anySelected
    )
}

// MARK: - 4. Avanzamento & Completamento (stile "Passa a iOS" / "Android Switch")

@Composable
private fun TransferProgressWizardView(
    progress: LiveTransferProgress,
    isReceiver: Boolean,
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
                text = "Chat WhatsApp",
                fontSize = 23.sp,
                fontWeight = FontWeight.Bold,
                color = DirectSwitchTheme.textPrimary
            )
            Text(
                text = "Segui i passaggi qui sotto per caricare le chat dentro WhatsApp (gratuito)",
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
            text = "Fine",
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
            Text("Trasferimento completato", fontSize = 23.sp, fontWeight = FontWeight.Bold, color = DirectSwitchTheme.textPrimary)
            Text(
                text = if (isReceiver) "I tuoi dati sono pronti su questo telefono" else "Tutti i dati selezionati sono stati copiati",
                fontSize = 14.sp,
                color = DirectSwitchTheme.textSecondary,
                textAlign = TextAlign.Center
            )
        } else {
            DirectSwitchAppleEmblem(size = 60.dp)
            Text(
                text = if (isReceiver) "Copia su questo telefono..." else "Copia dei dati in corso...",
                fontSize = 22.sp,
                fontWeight = FontWeight.Bold,
                color = DirectSwitchTheme.textPrimary
            )
            Text("Tieni entrambi i telefoni vicini fino al termine", fontSize = 14.sp, color = DirectSwitchTheme.textSecondary)
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
                text = progress.currentFileName.ifEmpty { progress.phaseLabel },
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
                    text = progress.etaLabel,
                    fontSize = 15.sp,
                    fontWeight = FontWeight.SemiBold,
                    color = DirectSwitchTheme.blue
                )
            }
        }
    }

    DirectSwitchCard(padding = 0.dp, spacing = 0.dp) {
        val contactsValue = if (progress.mergedContacts == 0 && progress.contactsAlreadyPresent > 0) {
            "0 (${progress.contactsAlreadyPresent} già presenti)"
        } else {
            "${progress.mergedContacts}"
        }
        SummaryItemRow(Icons.Filled.Contacts, DirectSwitchTheme.blue, "Contatti uniti", contactsValue)
        HorizontalDivider(modifier = Modifier.padding(start = 56.dp), color = DirectSwitchTheme.hairline)
        SummaryItemRow(
            Icons.Filled.Image,
            DirectSwitchTheme.orange,
            "Foto, Video e File",
            if (progress.totalItems > 0) "${progress.completedItems} / ${progress.totalItems}" else "${progress.completedItems}"
        )
        HorizontalDivider(modifier = Modifier.padding(start = 56.dp), color = DirectSwitchTheme.hairline)
        SummaryItemRow(Icons.Filled.CalendarMonth, DirectSwitchTheme.indigo, "Calendari importati", "${progress.importedCalendars}")
        if (progress.importedSms > 0) {
            HorizontalDivider(modifier = Modifier.padding(start = 56.dp), color = DirectSwitchTheme.hairline)
            SummaryItemRow(Icons.Filled.Sms, DirectSwitchTheme.green, "Messaggi salvati", "${progress.importedSms}")
        }
        if (progress.skippedDuplicates > 0) {
            HorizontalDivider(modifier = Modifier.padding(start = 56.dp), color = DirectSwitchTheme.hairline)
            SummaryItemRow(Icons.Filled.CheckCircle, DirectSwitchTheme.teal, "Doppioni ignorati", "${progress.skippedDuplicates}")
        }
        if (progress.failedItemsCount > 0) {
            HorizontalDivider(modifier = Modifier.padding(start = 56.dp), color = DirectSwitchTheme.hairline)
            SummaryItemRow(Icons.Filled.Warning, DirectSwitchTheme.orange, "File non disponibili saltati", "${progress.failedItemsCount}")
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
                        text = "Account Mail e Cloud",
                        fontSize = 15.sp,
                        fontWeight = FontWeight.Bold,
                        color = DirectSwitchTheme.textPrimary
                    )
                }
                InfoCircleButton(
                    title = "Sincronizza Email e Account",
                    message = "Come su Android Switch, per motivi di sicurezza le password delle caselle email non viaggiano tra dispositivi. Accedi qui al tuo account Google, iCloud o Outlook per sincronizzare istantaneamente tutte le email."
                )
            }
            DirectSwitchSecondaryButton(
                text = "Aggiungi account Mail / Google",
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
                            text = "Cartelle ricreate su questo telefono",
                            fontSize = 15.sp,
                            fontWeight = FontWeight.Bold,
                            color = DirectSwitchTheme.textPrimary
                        )
                        Text(
                            text = "$totalReceivedFiles file in ${sortedFolders.size} cartelle originali",
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
                            text = "$count file",
                            fontSize = 12.sp,
                            color = DirectSwitchTheme.textSecondary
                        )
                    }
                }
                if (sortedFolders.size > 8) {
                    Text(
                        text = "e altre ${sortedFolders.size - 8} cartelle salvate nella memoria del telefono.",
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

    if (progress.errorMessage != null) {
        DirectSwitchCard(padding = 14.dp) {
            Text(progress.errorMessage, fontSize = 13.sp, fontWeight = FontWeight.Medium, color = DirectSwitchTheme.red)
        }
    }

    if (isReceiver && stillDefaultSms && (progress.isCompleted || progress.errorMessage != null)) {
        DirectSwitchCard(padding = 14.dp) {
            Text("Ripristina la tua app Messaggi predefinita", fontSize = 14.sp, fontWeight = FontWeight.SemiBold, color = DirectSwitchTheme.textPrimary)
            DirectSwitchSecondaryButton(
                text = "Ripristina app Messaggi",
                onClick = {
                    runCatching { restoreSmsLauncher.launch(SmsSystemScanner.createRestorePreviousSmsAppIntent(context)) }
                }
            )
        }
    }

    if (progress.isCompleted || progress.errorMessage != null) {
        DirectSwitchPrimaryButton(
            text = if (progress.isCompleted) "Fine" else "Torna alla Home",
            onClick = onFinish
        )
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

// MARK: - Portale QR Rapido (Rubrica .vcf / APK senza internet)

@Composable
private fun QuickPortalWizardView(
    wifiQrString: String?,
    portalUrl: String?,
    onClose: () -> Unit
) {
    Column(
        modifier = Modifier.fillMaxWidth(),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(6.dp)
    ) {
        Text("Inquadra con la Fotocamera", fontSize = 22.sp, fontWeight = FontWeight.Bold, color = DirectSwitchTheme.textPrimary)
        Text("Scarica subito la Rubrica su iPhone o l'app DirectSwitch senza internet", fontSize = 14.sp, color = DirectSwitchTheme.textSecondary, textAlign = TextAlign.Center)
    }

    DirectSwitchCard {
        if (wifiQrString != null) {
            Text("1. Inquadra per collegarti all'Hotspot 5GHz", fontSize = 13.sp, fontWeight = FontWeight.SemiBold, color = DirectSwitchTheme.blue)
            val wifiBmp = remember(wifiQrString) { QrBitmapGenerator.generate(wifiQrString, 520) }
            if (wifiBmp != null) {
                Box(modifier = Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
                    Image(
                        bitmap = wifiBmp.asImageBitmap(),
                        contentDescription = "QR Wi-Fi",
                        modifier = Modifier
                            .size(185.dp)
                            .clip(RoundedCornerShape(14.dp))
                            .background(Color.White)
                            .padding(8.dp)
                    )
                }
            }
            Text("2. Poi inquadra per aprire il portale", fontSize = 13.sp, fontWeight = FontWeight.SemiBold, color = DirectSwitchTheme.blue)
        }

        if (portalUrl != null) {
            val portalBmp = remember(portalUrl) { QrBitmapGenerator.generate(portalUrl, 580) }
            if (portalBmp != null) {
                Box(modifier = Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
                    Image(
                        bitmap = portalBmp.asImageBitmap(),
                        contentDescription = "QR Portale",
                        modifier = Modifier
                            .size(210.dp)
                            .clip(RoundedCornerShape(16.dp))
                            .background(Color.White)
                            .padding(10.dp)
                    )
                }
            }
        }
    }

    DirectSwitchPrimaryButton(text = "Chiudi", onClick = onClose)
}

@Composable
private fun ReceiverAppsMirrorCard(
    apps: List<InstalledAppRecord>,
    peerPlatform: DevicePlatform?
) {
    val context = LocalContext.current
    val lifecycleOwner = LocalLifecycleOwner.current
    var refreshTick by remember { mutableStateOf(0) }
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
                            "Tutte le app già installate (${installedApps.size})"
                        } else {
                            "App da installare (${pendingApps.size})"
                        },
                        fontSize = 15.sp,
                        fontWeight = FontWeight.Bold,
                        color = DirectSwitchTheme.textPrimary
                    )
                    Text(
                        text = when {
                            pendingApps.isEmpty() -> "Nessuna app mancante: hai già tutte le ${apps.size} app sul telefono"
                            installedApps.isNotEmpty() -> "${installedApps.size} già presenti e nascoste automaticamente • aggiornamento al rientro"
                            else -> "Tocca un'app per installarla dal Play Store (aggiornamento automatico al rientro)"
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
                        contentDescription = "Aggiorna stato app",
                        tint = DirectSwitchTheme.blue,
                        modifier = Modifier.size(16.dp)
                    )
                }
            }
        }

        pendingApps.firstOrNull()?.let { nextApp ->
            DirectSwitchPrimaryButton(
                text = "Installa prossima app (1/${pendingApps.size}): ${nextApp.appName}",
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
            text = "Collegato!",
            fontSize = 24.sp,
            fontWeight = FontWeight.Bold,
            color = DirectSwitchTheme.textPrimary
        )
        Text(
            text = "Prosegui sull'altro telefono",
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
                    text = peerDeviceName.ifBlank { "Altro telefono collegato" },
                    fontSize = 16.sp,
                    fontWeight = FontWeight.Bold,
                    color = DirectSwitchTheme.textPrimary
                )
                Text(
                    text = "Scegli sull'altro telefono le categorie da copiare e tocca «Copia le voci selezionate».",
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
                text = "In attesa della conferma sull'altro telefono...",
                fontSize = 13.sp,
                color = DirectSwitchTheme.textSecondary
            )
        }
    }

    DirectSwitchNeutralOutlinedButton(
        text = "Annulla",
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
            text = if (isReceiver) "Sto preparando la ricezione..." else "Sto preparando il trasferimento...",
            fontSize = 22.sp,
            fontWeight = FontWeight.Bold,
            color = DirectSwitchTheme.textPrimary,
            textAlign = TextAlign.Center
        )
        Text(
            text = if (isReceiver) {
                "L'altro telefono sta preparando e verificando i dati selezionati prima di iniziare da 0%."
            } else {
                "Conteggio e verifica rapida dei dati selezionati prima di iniziare entrambi da 0%."
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
                    text = "Preparazione in corso...",
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
                val statusLabel = when {
                    isReceiver && !progress.arePreparationItemsReady && item.targetCount == 0 -> "In preparazione..."
                    !isReceiver && !item.isReady && shownCount == 0 -> "Analisi..."
                    else -> item.formattedCount(shownCount)
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
                            text = item.title,
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
        text = "Annulla",
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

@Composable
private fun GoogleSetupBridgeSheetContent(
    note: String?,
    onLaunchNewAndroidRestore: () -> Unit,
    onLaunchIphoneToAndroidCable: () -> Unit,
    onLaunchOldAndroidSend: () -> Unit,
    onClose: () -> Unit
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .background(DirectSwitchTheme.backgroundBrush)
            .padding(horizontal = 20.dp, vertical = 12.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            AppleSettingsIcon(icon = Icons.Filled.SwapHoriz, color = DirectSwitchTheme.slate)
            Text("Passa a Android / Configura", fontSize = 18.sp, fontWeight = FontWeight.Bold, color = DirectSwitchTheme.textPrimary)
        }
        Text(
            "Avvia lo strumento nativo di Google anche se il nuovo telefono è già configurato:",
            fontSize = 14.sp,
            color = DirectSwitchTheme.textSecondary
        )
        DirectSwitchPrimaryButton(text = "Trasferisci chat WhatsApp da iPhone (QR in app)", onClick = onLaunchIphoneToAndroidCable)
        DirectSwitchSecondaryButton(text = "Ricevi su questo Android già avviato", onClick = onLaunchNewAndroidRestore)
        DirectSwitchSecondaryButton(text = "Invia da questo vecchio Android", onClick = onLaunchOldAndroidSend)

        if (!note.isNullOrBlank()) {
            Text(note, fontSize = 13.sp, fontWeight = FontWeight.Medium, color = DirectSwitchTheme.blue)
        }

        TextButton(onClick = onClose, modifier = Modifier.fillMaxWidth()) {
            Text("Chiudi", color = DirectSwitchTheme.textSecondary, fontWeight = FontWeight.SemiBold)
        }
        Spacer(modifier = Modifier.height(8.dp))
    }
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
