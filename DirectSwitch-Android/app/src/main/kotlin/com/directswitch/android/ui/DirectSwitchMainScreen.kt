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
import androidx.compose.material.icons.filled.Image
import androidx.compose.material.icons.filled.LockOpen
import androidx.compose.material.icons.filled.PhoneAndroid
import androidx.compose.material.icons.filled.PhoneIphone
import androidx.compose.material.icons.filled.QrCode2
import androidx.compose.material.icons.filled.QrCodeScanner
import androidx.compose.material.icons.filled.Sms
import androidx.compose.material.icons.filled.SwapHoriz
import androidx.compose.material.icons.filled.Videocam
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material.icons.filled.Wifi
import androidx.compose.material.icons.filled.WifiTethering
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
import androidx.lifecycle.compose.LocalLifecycleOwner
import com.directswitch.android.DirectSwitchLog
import com.directswitch.android.migrators.CloudSaveEntitlementDetector
import com.directswitch.android.migrators.DeviceDataAnalyzer
import com.directswitch.android.migrators.DirectSwitchBillingManager
import com.directswitch.android.migrators.DocumentsAndWhatsAppScanner
import com.directswitch.android.migrators.GoogleSetupBridge
import com.directswitch.android.migrators.InstalledAppsScanner
import com.directswitch.android.migrators.LocalDeviceScanSummary
import com.directswitch.android.migrators.SmsSystemScanner
import com.directswitch.android.migrators.findHostActivity
import com.directswitch.android.protocol.DevicePlatform
import com.directswitch.android.protocol.DiscoveryBeaconPayload
import com.directswitch.android.protocol.QrPairingPayload
import com.directswitch.android.protocol.SessionLicenseTier
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
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.util.Locale
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

private enum class WizardStep {
    HOME,
    RECEIVER_WAIT_CODE,
    SENDER_CONNECT,
    SENDER_SELECT_CATEGORIES,
    TRANSFER_PROGRESS,
    QUICK_PORTAL
}

private data class CategorySelectionState(
    val contacts: Boolean = true,
    val photos: Boolean = true,
    val videos: Boolean = true,
    val calendars: Boolean = true,
    val sms: Boolean = true,
    val documents: Boolean = true,
    val whatsAppVault: Boolean = true,
    val installedApps: Boolean = true
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
    var isProUnlocked by remember {
        mutableStateOf(
            CloudSaveEntitlementDetector.isLocalProUnlocked(context) ||
                CloudSaveEntitlementDetector.hasVerifiedCloudSaveProEntitlement(context)
        )
    }
    val hasCloudSaveInstalled = remember { CloudSaveEntitlementDetector.isCloudSaveInstalled(context) }

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

    var categories by remember { mutableStateOf(CategorySelectionState()) }
    var isReceiverFlow by remember { mutableStateOf(false) }

    var showProSheet by remember { mutableStateOf(false) }
    var showGoogleBridgeSheet by remember { mutableStateOf(false) }
    var googleBridgeNote by remember { mutableStateOf<String?>(null) }
    var billingStatusNote by remember { mutableStateOf<String?>(null) }
    var pendingPermissionContinuation by remember { mutableStateOf<(() -> Unit)?>(null) }

    val billingManager = remember {
        DirectSwitchBillingManager(context) { unlocked, message ->
            if (unlocked) isProUnlocked = true
            billingStatusNote = message
        }
    }

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

    val documentPickerLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.OpenMultipleDocuments()
    ) { uris ->
        if (uris.isNotEmpty()) {
            scope.launch {
                val added = withContext(Dispatchers.IO) {
                    DocumentsAndWhatsAppScanner.importSharedUrisIntoVault(context, uris)
                }
                scanSummary = withContext(Dispatchers.IO) { DeviceDataAnalyzer.scanSummary(context) }
                vaultStatusNote = if (added > 0) "$added file pronti per la copia" else null
            }
        }
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
        step = WizardStep.HOME
    }

    fun handleBack() {
        when (step) {
            WizardStep.HOME -> Unit
            WizardStep.RECEIVER_WAIT_CODE, WizardStep.QUICK_PORTAL, WizardStep.TRANSFER_PROGRESS -> resetAndGoHome()
            WizardStep.SENDER_CONNECT -> {
                showCameraScanner = false
                autoDiscovery.stopScanning()
                step = WizardStep.HOME
            }
            WizardStep.SENDER_SELECT_CATEGORIES -> {
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
        billingManager.connectAndRestorePurchases()
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

    LaunchedEffect(serverProgress.peerDeviceName) {
        if (step == WizardStep.RECEIVER_WAIT_CODE && serverProgress.peerDeviceName.isNotEmpty()) {
            isReceiverFlow = true
            step = WizardStep.TRANSFER_PROGRESS
        }
    }

    DisposableEffect(Unit) {
        onDispose {
            billingManager.endConnection()
            autoDiscovery.stopAdvertising()
            autoDiscovery.stopScanning()
            server.stop()
            hotspotController.stopHotspot()
        }
    }

    val topTitle = when (step) {
        WizardStep.HOME -> "DirectSwitch"
        WizardStep.RECEIVER_WAIT_CODE -> "Ricevi dati"
        WizardStep.SENDER_CONNECT -> "Collega telefono"
        WizardStep.SENDER_SELECT_CATEGORIES -> "Cosa copiare"
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
            isProUnlocked = isProUnlocked,
            onBack = { handleBack() },
            onTapPassBadge = { showProSheet = true }
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
                            isLocalPro = isProUnlocked,
                            categories = categories,
                            onUpdateCategories = { categories = it },
                            onPickDocumentsOrWhatsApp = { documentPickerLauncher.launch(arrayOf("*/*")) },
                            onOpenProSheet = { showProSheet = true },
                            onChangeDevice = {
                                pairedTargetPayload = null
                                pinInput = ""
                                autoDiscovery.startScanningForNewDevices()
                                step = WizardStep.SENDER_CONNECT
                            },
                            onStartTransfer = {
                                isReceiverFlow = false
                                vaultStatusNote = null
                                step = WizardStep.TRANSFER_PROGRESS
                                scope.launch {
                                    client.executeTransfer(
                                        qrPayload = target,
                                        includeContacts = categories.contacts,
                                        includePhotos = categories.photos,
                                        includeVideos = categories.videos,
                                        includeCalendars = categories.calendars,
                                        includeSms = categories.sms,
                                        includeDocuments = categories.documents,
                                        includeWhatsAppVault = categories.whatsAppVault,
                                        includeInstalledApps = categories.installedApps
                                    )
                                }
                            }
                        )
                    }
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

    if (showProSheet) {
        val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
        ModalBottomSheet(
            onDismissRequest = { showProSheet = false },
            sheetState = sheetState,
            containerColor = DirectSwitchTheme.canvasMid
        ) {
            CrossOsProPassSheetContent(
                isUnlocked = isProUnlocked,
                hasCloudSave = hasCloudSaveInstalled,
                billingNote = billingStatusNote,
                onPurchasePass = { billingManager.launchCrossOsPassPurchase(context.findHostActivity()) },
                onRestorePurchases = { billingManager.restoreExistingPurchases(userInitiated = true) },
                onLockForTest = {
                    CloudSaveEntitlementDetector.setLocalProUnlocked(context, false)
                    isProUnlocked = false
                    billingStatusNote = "Modalità Anteprima attivata (rubrica + 25 foto) per test."
                },
                onClose = { showProSheet = false }
            )
        }
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
                text = "In attesa dell'altro telefono...",
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

// MARK: - 3B. Passo 2 Mittente: Scegli cosa copiare (stile "Android Switch" + "CloudSave")

@Composable
private fun SenderCategoriesWizardView(
    pairedPayload: QrPairingPayload,
    summary: LocalDeviceScanSummary?,
    isLocalPro: Boolean,
    categories: CategorySelectionState,
    onUpdateCategories: (CategorySelectionState) -> Unit,
    onPickDocumentsOrWhatsApp: () -> Unit,
    onOpenProSheet: () -> Unit,
    onChangeDevice: () -> Unit,
    onStartTransfer: () -> Unit
) {
    val allSelected = categories.contacts && categories.photos && categories.videos &&
        categories.calendars && categories.sms && categories.documents &&
        categories.whatsAppVault && categories.installedApps
    val anySelected = categories.contacts || categories.photos || categories.videos ||
        categories.calendars || categories.sms || categories.documents ||
        categories.whatsAppVault || categories.installedApps

    val isCrossOs = pairedPayload.receiverPlatform == DevicePlatform.IOS
    val isFullUnlocked = !isCrossOs || isLocalPro || pairedPayload.receiverHasPro

    Row(
        modifier = Modifier.fillMaxWidth(),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.SpaceBetween
    ) {
        Text("Passo 2 di 3", fontSize = 13.sp, fontWeight = FontWeight.SemiBold, color = DirectSwitchTheme.blue)
        Text(
            text = if (allSelected) "Deseleziona" else "Seleziona tutto",
            fontSize = 14.sp,
            fontWeight = FontWeight.SemiBold,
            color = DirectSwitchTheme.blue,
            modifier = Modifier.clickable {
                val next = !allSelected
                onUpdateCategories(
                    CategorySelectionState(next, next, next, next, next, next, next, next)
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
                        message = if (!isCrossOs) {
                            "Collegamento diretto attivo e pronto al trasferimento completo dei dati selezionati."
                        } else if (isFullUnlocked) {
                            "Premium Direct attivo: trasferimento completo Android ↔ iPhone sbloccato senza limiti."
                        } else {
                            "Con Premium Direct sblocchi il trasferimento illimitato di foto originali, video 4K, calendari, messaggi e chat verso iPhone senza formattare."
                        }
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

        if (isCrossOs && !isFullUnlocked) {
            Surface(
                onClick = onOpenProSheet,
                shape = RoundedCornerShape(10.dp),
                color = DirectSwitchTheme.premiumSurface,
                border = androidx.compose.foundation.BorderStroke(1.dp, DirectSwitchTheme.premiumBorder.copy(alpha = 0.65f)),
                modifier = Modifier.fillMaxWidth()
            ) {
                Row(
                    modifier = Modifier.padding(horizontal = 12.dp, vertical = 9.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.SpaceBetween
                ) {
                    Text("Sblocca trasferimento completo con Premium Direct", fontSize = 13.sp, fontWeight = FontWeight.Bold, color = DirectSwitchTheme.premiumGold)
                    Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, contentDescription = null, tint = DirectSwitchTheme.premiumGold)
                }
            }
        }
    }

    Text("Scegli cosa copiare", fontSize = 20.sp, fontWeight = FontWeight.Bold, color = DirectSwitchTheme.textPrimary)

    DirectSwitchCard(padding = 0.dp, spacing = 0.dp) {
        CleanCategoryToggleRow(
            icon = Icons.Filled.Contacts,
            iconColor = DirectSwitchTheme.blue,
            title = "Rubrica contatti",
            subtitle = summary?.let { "${it.contactsCount} contatti" },
            checked = categories.contacts,
            onCheckedChange = { onUpdateCategories(categories.copy(contacts = it)) }
        )
        HorizontalDivider(modifier = Modifier.padding(start = 58.dp), color = DirectSwitchTheme.hairline)

        CleanCategoryToggleRow(
            icon = Icons.Filled.Image,
            iconColor = DirectSwitchTheme.orange,
            title = "Foto e Album",
            subtitle = summary?.let { "${it.photosCount} foto • ${formatMb(it.photosBytes)}" },
            checked = categories.photos,
            onCheckedChange = { onUpdateCategories(categories.copy(photos = it)) }
        )
        HorizontalDivider(modifier = Modifier.padding(start = 58.dp), color = DirectSwitchTheme.hairline)

        CleanCategoryToggleRow(
            icon = Icons.Filled.Videocam,
            iconColor = DirectSwitchTheme.red,
            title = "Video originali",
            subtitle = summary?.let { "${it.videosCount} video • ${formatMb(it.videosBytes)}" },
            checked = categories.videos,
            onCheckedChange = { onUpdateCategories(categories.copy(videos = it)) }
        )
        HorizontalDivider(modifier = Modifier.padding(start = 58.dp), color = DirectSwitchTheme.hairline)

        CleanCategoryToggleRow(
            icon = Icons.Filled.CalendarMonth,
            iconColor = DirectSwitchTheme.indigo,
            title = "Calendari",
            subtitle = summary?.let { "${it.calendarEventsCount} eventi" },
            checked = categories.calendars,
            onCheckedChange = { onUpdateCategories(categories.copy(calendars = it)) }
        )
        HorizontalDivider(modifier = Modifier.padding(start = 58.dp), color = DirectSwitchTheme.hairline)

        CleanCategoryToggleRow(
            icon = Icons.Filled.Sms,
            iconColor = DirectSwitchTheme.green,
            title = "Messaggi SMS",
            subtitle = summary?.let { "${it.smsCount} messaggi" },
            checked = categories.sms,
            onCheckedChange = { onUpdateCategories(categories.copy(sms = it)) }
        )
        HorizontalDivider(modifier = Modifier.padding(start = 58.dp), color = DirectSwitchTheme.hairline)

        CleanCategoryToggleRow(
            icon = Icons.Filled.Description,
            iconColor = DirectSwitchTheme.teal,
            title = "Documenti e File",
            subtitle = summary?.let { "${it.documentsCount} documenti" },
            checked = categories.documents,
            onCheckedChange = { onUpdateCategories(categories.copy(documents = it)) }
        )
        HorizontalDivider(modifier = Modifier.padding(start = 58.dp), color = DirectSwitchTheme.hairline)

        val waArchives = summary?.whatsappArchivesCount ?: 0
        CleanCategoryToggleRow(
            icon = Icons.AutoMirrored.Filled.Chat,
            iconColor = DirectSwitchTheme.green,
            title = "Chat WhatsApp",
            subtitle = if (waArchives > 0) "Cronologia QR + $waArchives .zip" else "Cronologia diretta via QR",
            checked = categories.whatsAppVault,
            onCheckedChange = { onUpdateCategories(categories.copy(whatsAppVault = it)) }
        )
        HorizontalDivider(modifier = Modifier.padding(start = 58.dp), color = DirectSwitchTheme.hairline)

        CleanCategoryToggleRow(
            icon = Icons.Filled.Apps,
            iconColor = DirectSwitchTheme.blue,
            title = "App installate (catalogo Store)",
            subtitle = summary?.let { "${it.installedAppsCount} app rilevabili" },
            checked = categories.installedApps,
            onCheckedChange = { onUpdateCategories(categories.copy(installedApps = it)) }
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

    DirectSwitchSecondaryButton(
        text = "Aggiungi altri file o .zip WhatsApp",
        onClick = onPickDocumentsOrWhatsApp
    )

    DirectSwitchPrimaryButton(
        text = "Copia i dati",
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
    var whatsAppBridgeNote by remember(progress.isCompleted, progress.pendingNativeWhatsAppMigration) {
        mutableStateOf<String?>(null)
    }
    var autoLaunchedAndroidSwitch by remember { mutableStateOf(false) }

    LaunchedEffect(progress.isCompleted, progress.pendingNativeWhatsAppMigration, isReceiver, progress.peerPlatform) {
        if (isReceiver &&
            progress.isCompleted &&
            progress.pendingNativeWhatsAppMigration &&
            progress.peerPlatform == DevicePlatform.IOS &&
            !autoLaunchedAndroidSwitch
        ) {
            autoLaunchedAndroidSwitch = true
            val (_, msg) = GoogleSetupBridge.launchIphoneToAndroidGoogleRestore(
                context = context,
                preferWirelessQr = true
            )
            whatsAppBridgeNote = msg
        }
    }
    val restoreSmsLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.StartActivityForResult()
    ) {
        stillDefaultSms = SmsSystemScanner.isDefaultSmsApp(context)
    }

    val ratio = when {
        progress.isCompleted -> 1f
        progress.transferredBytes == 0L && progress.completedItems == 0 -> 0f
        progress.totalBytes > 0L -> (progress.transferredBytes.toFloat() / progress.totalBytes.toFloat()).coerceIn(0f, 1f)
        progress.totalItems > 0 -> (progress.completedItems.toFloat() / progress.totalItems.toFloat()).coerceIn(0f, 1f)
        else -> 0f
    }
    val pct = (ratio * 100f).toInt()

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
                    AppleSettingsIcon(icon = Icons.Filled.Apps, color = DirectSwitchTheme.blue)
                    Text(
                        text = "App dal vecchio telefono (${progress.receivedInstalledApps.size})",
                        fontSize = 15.sp,
                        fontWeight = FontWeight.Bold,
                        color = DirectSwitchTheme.textPrimary
                    )
                }
                InfoCircleButton(
                    title = "Reinstallazione rapida App",
                    message = "Tocca 'Play Store' accanto a ciascuna app trasferita per scaricare subito la versione ufficiale compatibile con questo Android."
                )
            }
            for (app in progress.receivedInstalledApps.take(15)) {
                HorizontalDivider(color = DirectSwitchTheme.hairline)
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.SpaceBetween
                ) {
                    Text(
                        text = app.appName,
                        fontSize = 14.sp,
                        fontWeight = FontWeight.Medium,
                        color = DirectSwitchTheme.textPrimary,
                        modifier = Modifier.weight(1f)
                    )
                    TextButton(
                        onClick = {
                            InstalledAppsScanner.openAppOnPlayStore(context, app)
                        }
                    ) {
                        Text("Play Store", fontSize = 13.sp, fontWeight = FontWeight.SemiBold, color = DirectSwitchTheme.blue)
                    }
                }
            }
        }
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

    if (progress.isCompleted && progress.pendingNativeWhatsAppMigration) {
        val isFromIphone = isReceiver && progress.peerPlatform == DevicePlatform.IOS
        val cardTitle = when {
            isFromIphone -> "Passaggio Chat WhatsApp senza cavo"
            isReceiver -> "Ricevi Chat WhatsApp su Android"
            progress.peerPlatform == DevicePlatform.IOS -> "Chat WhatsApp → iPhone"
            else -> "Chat WhatsApp → Nuovo Android"
        }
        val shortHint = when {
            isFromIphone ->
                "Modulo Android Switch avviato per mostrare il codice QR senza cavo: inquadralo da WhatsApp sull'iPhone, poi apri WhatsApp qui sotto."
            isReceiver ->
                "Apri WhatsApp su questo telefono, inserisci il tuo numero e mostra il codice QR da inquadrare con il vecchio Android."
            progress.peerPlatform == DevicePlatform.IOS ->
                "Apri WhatsApp per avviare il passaggio guidato in Wi-Fi locale verso il nuovo iPhone."
            else ->
                "Inserisci il tuo numero in WhatsApp sul nuovo Android, poi tocca qui sotto per inquadrare il codice QR."
        }
        val infoSteps = when {
            isFromIphone ->
                "1. DirectSwitch avvia automaticamente il modulo nativo Google 'Android Switch' in modalità senza cavo (puoi riaprirlo in ogni momento col pulsante verde).\n2. Scegli 'Senza cavo / Wi-Fi' fino a visualizzare il codice QR su questo Android.\n3. Sull'iPhone apri WhatsApp → Impostazioni → Chat → Trasferisci chat su Android e inquadra il codice QR.\n4. Terminata la ricezione su Android Switch, tocca '2. Apri WhatsApp per attivare le chat' e verifica il tuo numero: ritroverai tutte le conversazioni, foto e vocali senza alcun cavo!"
            isReceiver ->
                "Passaggio diretto Android → Android senza usare Google Drive:\n1. Tocca il pulsante verde per aprire WhatsApp e inserisci il tuo numero.\n2. Scegli 'Trasferisci la cronologia chat dal telefono precedente' per mostrare il codice QR.\n3. Sul vecchio Android apri WhatsApp → Impostazioni → Chat → Trasferisci chat e inquadra il QR."
            progress.peerPlatform == DevicePlatform.IOS ->
                "1. Eventuali archivi .zip sono già stati copiati nella cartella DirectSwitch dell'iPhone.\n2. Per l'intera cronologia nativa, apri WhatsApp e segui la connessione Wi-Fi locale con l'iPhone."
            else ->
                "1. Sul nuovo Android apri WhatsApp, inserisci il tuo numero e mostra il codice QR di trasferimento chat.\n2. Su questo Android tocca il pulsante verde qui sotto (Impostazioni → Chat → Trasferisci chat → Inizia) e inquadra il codice QR."
        }

        Surface(
            modifier = Modifier.fillMaxWidth(),
            shape = RoundedCornerShape(16.dp),
            color = DirectSwitchTheme.cardSurface,
            border = androidx.compose.foundation.BorderStroke(1.2.dp, DirectSwitchTheme.green.copy(alpha = 0.50f)),
            shadowElevation = 2.dp
        ) {
            Column(
                modifier = Modifier.padding(14.dp),
                verticalArrangement = Arrangement.spacedBy(11.dp)
            ) {
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
                        AppleSettingsIcon(icon = Icons.AutoMirrored.Filled.Chat, color = DirectSwitchTheme.green)
                        Text(
                            text = cardTitle,
                            fontSize = 16.sp,
                            fontWeight = FontWeight.Bold,
                            color = DirectSwitchTheme.textPrimary
                        )
                    }
                    InfoCircleButton(
                        title = cardTitle,
                        message = infoSteps
                    )
                }

                Text(
                    text = shortHint,
                    fontSize = 13.sp,
                    lineHeight = 18.sp,
                    color = DirectSwitchTheme.textSecondary
                )

                if (isFromIphone) {
                    DirectSwitchPrimaryButton(
                        text = "1. Modulo Android Switch (QR senza cavo)",
                        containerColor = DirectSwitchTheme.green,
                        onClick = {
                            val (_, msg) = GoogleSetupBridge.launchIphoneToAndroidGoogleRestore(
                                context = context,
                                preferWirelessQr = true
                            )
                            whatsAppBridgeNote = msg
                        }
                    )
                    DirectSwitchSecondaryButton(
                        text = "2. Apri WhatsApp per attivare le chat",
                        tint = DirectSwitchTheme.green,
                        onClick = {
                            val (_, msg) = GoogleSetupBridge.launchWhatsAppOrPlayStore(context)
                            whatsAppBridgeNote = msg
                        }
                    )
                } else {
                    DirectSwitchPrimaryButton(
                        text = if (isReceiver) "Apri WhatsApp e mostra QR" else "Apri WhatsApp e inquadra QR",
                        containerColor = DirectSwitchTheme.green,
                        onClick = {
                            val (_, msg) = GoogleSetupBridge.launchWhatsAppOrPlayStore(context)
                            whatsAppBridgeNote = msg
                        }
                    )
                }

                if (!whatsAppBridgeNote.isNullOrBlank()) {
                    Text(
                        text = whatsAppBridgeNote ?: "",
                        fontSize = 12.sp,
                        fontWeight = FontWeight.Medium,
                        color = DirectSwitchTheme.blue
                    )
                }
            }
        }
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

// MARK: - Bottom Sheet Premium Direct (Passaggio completo iPhone <-> Android)

@Composable
private fun CrossOsProPassSheetContent(
    isUnlocked: Boolean,
    hasCloudSave: Boolean,
    billingNote: String?,
    onPurchasePass: () -> Unit,
    onRestorePurchases: () -> Unit,
    onLockForTest: () -> Unit = {},
    onClose: () -> Unit
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .background(DirectSwitchTheme.backgroundBrush)
            .padding(horizontal = 20.dp, vertical = 12.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        Surface(
            shape = RoundedCornerShape(20.dp),
            color = DirectSwitchTheme.premiumSurface,
            border = androidx.compose.foundation.BorderStroke(1.dp, DirectSwitchTheme.premiumBorder.copy(alpha = 0.65f))
        ) {
            Text(
                text = "PASSAGGIO DIRETTO iPHONE ↔ ANDROID",
                fontSize = 11.sp,
                fontWeight = FontWeight.Bold,
                color = DirectSwitchTheme.premiumGold,
                modifier = Modifier.padding(horizontal = 12.dp, vertical = 5.dp)
            )
        }

        DirectSwitchAppleEmblem(size = 64.dp)

        Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(6.dp)
            ) {
                Text("Premium Direct", fontSize = 23.sp, fontWeight = FontWeight.Bold, color = DirectSwitchTheme.textPrimary)
                InfoCircleButton(
                    title = "Perché scegliere Premium Direct",
                    message = "Le app tradizionali ti costringono a formattare il telefono ai dati di fabbrica o a comprare abbonamenti Cloud mensili per spostare i tuoi GB tra iPhone e Android.\n\nCon Premium Direct sposti tutto in Wi-Fi o Hotspot 5GHz diretto tra telefoni già in uso, senza perdere alcun dato già presente."
                )
            }
            Text(
                "Trasferisci tutto tra iPhone e Android senza resettare",
                fontSize = 14.sp,
                fontWeight = FontWeight.SemiBold,
                color = DirectSwitchTheme.premiumGold,
                textAlign = TextAlign.Center
            )
        }

        DirectSwitchCard {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                AppleSettingsIcon(icon = Icons.Filled.SwapHoriz, color = DirectSwitchTheme.premiumAmber, size = 28.dp)
                Text("Da iPhone ad Android (e viceversa) senza cavi", fontSize = 14.sp, fontWeight = FontWeight.SemiBold, color = DirectSwitchTheme.textPrimary)
            }
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                AppleSettingsIcon(icon = Icons.Filled.PhoneIphone, color = DirectSwitchTheme.blue, size = 28.dp)
                Text("Zero formattazione: funziona su telefoni già in uso", fontSize = 14.sp, fontWeight = FontWeight.SemiBold, color = DirectSwitchTheme.textPrimary)
            }
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                AppleSettingsIcon(icon = Icons.Filled.Image, color = DirectSwitchTheme.orange, size = 28.dp)
                Text("Foto originali, Video 4K, Contatti e Chat WhatsApp", fontSize = 14.sp, fontWeight = FontWeight.SemiBold, color = DirectSwitchTheme.textPrimary)
            }
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                AppleSettingsIcon(icon = Icons.Filled.CheckCircle, color = DirectSwitchTheme.teal, size = 28.dp)
                Text("Un solo acquisto sblocca entrambi i telefoni", fontSize = 14.sp, fontWeight = FontWeight.SemiBold, color = DirectSwitchTheme.textPrimary)
            }
        }

        Text(
            "Pagamento unico • Nessun abbonamento mensile",
            fontSize = 12.sp,
            fontWeight = FontWeight.SemiBold,
            color = DirectSwitchTheme.textSecondary
        )

        if (hasCloudSave && !isUnlocked) {
            Text("App CloudSave rilevata sul dispositivo", fontSize = 12.sp, color = DirectSwitchTheme.blue)
        }
        if (!billingNote.isNullOrBlank()) {
            Text(billingNote, fontSize = 13.sp, fontWeight = FontWeight.Medium, color = DirectSwitchTheme.blue)
        }

        DirectSwitchPrimaryButton(
            text = if (isUnlocked) "Premium Direct Attivo" else "Sblocca Premium Direct — 9,99 €",
            onClick = onPurchasePass,
            enabled = !isUnlocked,
            containerColor = if (isUnlocked) DirectSwitchTheme.green else DirectSwitchTheme.premiumGold
        )

        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            TextButton(onClick = onRestorePurchases) {
                Text("Ripristina acquisti", color = DirectSwitchTheme.blue, fontWeight = FontWeight.SemiBold)
            }
            if (isUnlocked) {
                TextButton(onClick = onLockForTest) {
                    Text("Blocca (Test)", color = DirectSwitchTheme.orange, fontWeight = FontWeight.SemiBold)
                }
            }
            TextButton(onClick = onClose) {
                Text("Chiudi", color = DirectSwitchTheme.textSecondary, fontWeight = FontWeight.SemiBold)
            }
        }
        Spacer(modifier = Modifier.height(8.dp))
    }
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
        DirectSwitchPrimaryButton(text = "Modulo Android Switch da iPhone (QR senza cavo)", onClick = onLaunchIphoneToAndroidCable)
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

private fun formatMb(bytes: Long): String {
    val mb = bytes / (1024.0 * 1024.0)
    return if (mb >= 1024.0) {
        String.format(Locale.ITALY, "%.2f GB", mb / 1024.0)
    } else {
        String.format(Locale.ITALY, "%.1f MB", mb)
    }
}
