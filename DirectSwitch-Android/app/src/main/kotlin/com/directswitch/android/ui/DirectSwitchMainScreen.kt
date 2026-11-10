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
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Chat
import androidx.compose.material.icons.filled.CalendarMonth
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Contacts
import androidx.compose.material.icons.filled.Description
import androidx.compose.material.icons.filled.Image
import androidx.compose.material.icons.filled.LockOpen
import androidx.compose.material.icons.filled.PhoneAndroid
import androidx.compose.material.icons.filled.QrCode2
import androidx.compose.material.icons.filled.QrCodeScanner
import androidx.compose.material.icons.filled.Security
import androidx.compose.material.icons.filled.Sms
import androidx.compose.material.icons.filled.SwapHoriz
import androidx.compose.material.icons.filled.Videocam
import androidx.compose.material.icons.filled.WifiTethering
import androidx.compose.material3.Checkbox
import androidx.compose.material3.CheckboxDefaults
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
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
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.core.content.ContextCompat
import androidx.lifecycle.compose.LocalLifecycleOwner
import com.directswitch.android.DirectSwitchLog
import com.directswitch.android.R
import com.directswitch.android.migrators.CloudSaveEntitlementDetector
import com.directswitch.android.migrators.DeviceDataAnalyzer
import com.directswitch.android.migrators.DirectSwitchBillingManager
import com.directswitch.android.migrators.DocumentsAndWhatsAppScanner
import com.directswitch.android.migrators.GoogleSetupBridge
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
import com.directswitch.android.ui.theme.DirectSwitchCard
import com.directswitch.android.ui.theme.DirectSwitchPrimaryButton
import com.directswitch.android.ui.theme.DirectSwitchSecondaryButton
import com.directswitch.android.ui.theme.DirectSwitchTheme
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

private enum class WizardMode {
    ROLE_SELECTION,
    RECEIVER_QR_HOST,
    SENDER_SCAN_AND_PICK,
    LIVE_TRANSFER_DASHBOARD,
    CROSS_OS_PRO_SHEET
}

private data class CategorySelectionState(
    val contacts: Boolean = true,
    val photos: Boolean = true,
    val videos: Boolean = true,
    val calendars: Boolean = true,
    val sms: Boolean = true,
    val documents: Boolean = true,
    val whatsAppVault: Boolean = true
)

private data class CategoryToggleSpec(
    val icon: ImageVector,
    val title: String,
    val subtitle: String,
    val checked: Boolean,
    val onToggle: (Boolean) -> Unit
)

@Composable
fun DirectSwitchMainScreen(
    externalVaultNote: String? = null,
    externalVaultTrigger: Int = 0
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()

    var mode by remember { mutableStateOf(WizardMode.ROLE_SELECTION) }
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

    var googleBridgeNote by remember { mutableStateOf<String?>(null) }
    var bootstrapPortalUrl by remember { mutableStateOf<String?>(null) }
    var bootstrapWifiQrString by remember { mutableStateOf<String?>(null) }
    var vaultStatusNote by remember { mutableStateOf<String?>(null) }

    var activeQrPayload by remember { mutableStateOf<QrPairingPayload?>(null) }
    var hotspotStatusNote by remember { mutableStateOf<String?>(null) }
    var useOffline5GhzHotspot by remember { mutableStateOf(false) }

    var selectedBeaconForPin by remember { mutableStateOf<DiscoveryBeaconPayload?>(null) }
    var pinInput by remember { mutableStateOf("") }
    var pinErrorNote by remember { mutableStateOf<String?>(null) }
    var isPinPairingBusy by remember { mutableStateOf(false) }

    var scannedReceiverPayload by remember { mutableStateOf<QrPairingPayload?>(null) }
    var manualQrInput by remember { mutableStateOf("") }
    var manualQrErrorNote by remember { mutableStateOf<String?>(null) }
    var showCameraScanner by remember { mutableStateOf(false) }

    var categories by remember { mutableStateOf(CategorySelectionState()) }
    var isReceiverFlow by remember { mutableStateOf(false) }
    var billingStatusNote by remember { mutableStateOf<String?>(null) }
    var pendingPermissionContinuation by remember { mutableStateOf<(() -> Unit)?>(null) }

    val billingManager = remember {
        DirectSwitchBillingManager(context) { unlocked, message ->
            if (unlocked) isProUnlocked = true
            billingStatusNote = message
        }
    }

    val serverProgress by server.progress.collectAsState()
    val clientProgress by client.progress.collectAsState()

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
                vaultStatusNote = if (added > 0) {
                    "$added file aggiunti al Vault DirectSwitch."
                } else {
                    "Nessun file valido selezionato."
                }
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

    LaunchedEffect(Unit) {
        billingManager.connectAndRestorePurchases()
        scanSummary = withContext(Dispatchers.IO) { DeviceDataAnalyzer.scanSummary(context) }
    }

    LaunchedEffect(externalVaultTrigger) {
        if (externalVaultTrigger > 0 && !externalVaultNote.isNullOrBlank()) {
            vaultStatusNote = externalVaultNote
            scanSummary = withContext(Dispatchers.IO) { DeviceDataAnalyzer.scanSummary(context) }
            if (mode == WizardMode.ROLE_SELECTION) {
                isReceiverFlow = false
                autoDiscovery.startScanningForNewDevices()
                mode = WizardMode.SENDER_SCAN_AND_PICK
            }
        }
    }

    LaunchedEffect(serverProgress.peerDeviceName) {
        if (mode == WizardMode.RECEIVER_QR_HOST && serverProgress.peerDeviceName.isNotEmpty()) {
            isReceiverFlow = true
            mode = WizardMode.LIVE_TRANSFER_DASHBOARD
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

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(DirectSwitchTheme.backgroundBrush)
            .statusBarsPadding()
    ) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 18.dp, vertical = 14.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp)
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.SpaceBetween
            ) {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(10.dp)
                ) {
                    Surface(
                        shape = RoundedCornerShape(12.dp),
                        color = DirectSwitchTheme.tealPrimary
                    ) {
                        Icon(
                            imageVector = Icons.Default.SwapHoriz,
                            contentDescription = null,
                            tint = Color.White,
                            modifier = Modifier
                                .padding(8.dp)
                                .size(24.dp)
                        )
                    }
                    Column {
                        Text(
                            text = stringResource(R.string.app_name),
                            fontSize = 22.sp,
                            fontWeight = FontWeight.Bold,
                            color = DirectSwitchTheme.textPrimary
                        )
                        Text(
                            text = stringResource(R.string.app_subtitle),
                            fontSize = 12.sp,
                            color = DirectSwitchTheme.textSecondary
                        )
                    }
                }

                Surface(
                    shape = RoundedCornerShape(20.dp),
                    color = if (isProUnlocked) {
                        DirectSwitchTheme.tealPrimary.copy(alpha = 0.15f)
                    } else {
                        DirectSwitchTheme.amberPro.copy(alpha = 0.16f)
                    },
                    modifier = Modifier.clickable { mode = WizardMode.CROSS_OS_PRO_SHEET }
                ) {
                    Text(
                        text = if (isProUnlocked) {
                            stringResource(R.string.pro_active_badge)
                        } else {
                            stringResource(R.string.ios_bridge_badge)
                        },
                        fontSize = 11.sp,
                        fontWeight = FontWeight.Bold,
                        color = if (isProUnlocked) {
                            DirectSwitchTheme.tealPrimary
                        } else {
                            DirectSwitchTheme.amberPro
                        },
                        modifier = Modifier.padding(horizontal = 10.dp, vertical = 5.dp)
                    )
                }
            }

            when (mode) {
                WizardMode.ROLE_SELECTION -> {
                    val bridgeCapabilities = remember(googleBridgeNote, useOffline5GhzHotspot) {
                        GoogleSetupBridge.inspectDeviceCapabilities(context)
                    }
                    RoleSelectionStep(
                        summary = scanSummary,
                        isProUnlocked = isProUnlocked,
                        bridgeCapabilities = bridgeCapabilities,
                        stabilizeWifiHotspot = useOffline5GhzHotspot,
                        hotspotNote = hotspotStatusNote,
                        googleBridgeNote = googleBridgeNote,
                        onToggleStabilizeWifi = { enabled ->
                            if (enabled) {
                                requestPermissionsThen {
                                    useOffline5GhzHotspot = true
                                    hotspotController.startHotspot { ssid, pass, err ->
                                        if (err != null) {
                                            useOffline5GhzHotspot = false
                                            hotspotStatusNote = err
                                        } else {
                                            hotspotStatusNote = "Rete locale 5GHz attiva ($ssid • Pass: $pass)"
                                        }
                                    }
                                }
                            } else {
                                useOffline5GhzHotspot = false
                                hotspotController.stopHotspot()
                                hotspotStatusNote = null
                            }
                        },
                        onGrantPermissions = { requestPermissionsThen() },
                        onSelectSender = {
                            requestPermissionsThen {
                                isReceiverFlow = false
                                autoDiscovery.startScanningForNewDevices()
                                mode = WizardMode.SENDER_SCAN_AND_PICK
                            }
                        },
                        onSelectReceiver = {
                            requestPermissionsThen {
                                isReceiverFlow = true
                                val payload = server.startReceiverSession()
                                activeQrPayload = payload
                                autoDiscovery.startAdvertisingReceiver(payload)
                                mode = WizardMode.RECEIVER_QR_HOST
                            }
                        },
                        onLaunchGoogleOldPhone = {
                            val (_, msg) = GoogleSetupBridge.launchOldPhoneGoogleNearbySetup(context)
                            googleBridgeNote = msg
                        },
                        onLaunchGoogleNewPhone = {
                            val (_, msg) = GoogleSetupBridge.launchNewPhonePostSetupRestore(context)
                            googleBridgeNote = msg
                        },
                        onLaunchGoogleIphoneToAndroid = {
                            val (_, msg) = GoogleSetupBridge.launchIphoneToAndroidGoogleRestore(context)
                            googleBridgeNote = msg
                        },
                        onOpenProSheet = { mode = WizardMode.CROSS_OS_PRO_SHEET }
                    )
                }

                WizardMode.RECEIVER_QR_HOST -> {
                    ReceiverQrHostStep(
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
                                        hotspotStatusNote = "Hotspot 5GHz attivo: $ssid"
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
                        onBack = {
                            autoDiscovery.stopAdvertising()
                            server.stop()
                            hotspotController.stopHotspot()
                            mode = WizardMode.ROLE_SELECTION
                        }
                    )
                }

                WizardMode.SENDER_SCAN_AND_PICK -> {
                    SenderScanAndPickStep(
                        summary = scanSummary,
                        discoveredDevices = discoveredDevices,
                        selectedBeacon = selectedBeaconForPin,
                        pinInput = pinInput,
                        pinErrorNote = pinErrorNote,
                        isPinPairingBusy = isPinPairingBusy,
                        scannedPayload = scannedReceiverPayload,
                        bootstrapPortalUrl = bootstrapPortalUrl,
                        bootstrapWifiQrString = bootstrapWifiQrString,
                        vaultStatusNote = vaultStatusNote,
                        manualQrInput = manualQrInput,
                        manualQrErrorNote = manualQrErrorNote,
                        showCameraScanner = showCameraScanner,
                        isLocalPro = isProUnlocked,
                        categories = categories,
                        onSelectDiscoveredBeacon = { beacon ->
                            selectedBeaconForPin = beacon
                            pinInput = ""
                            pinErrorNote = null
                            showCameraScanner = false
                        },
                        onPinInputChange = { raw ->
                            pinInput = raw.filter { it.isDigit() }.take(6)
                            pinErrorNote = null
                        },
                        onConfirmPinPairing = {
                            val beacon = selectedBeaconForPin ?: return@SenderScanAndPickStep
                            isPinPairingBusy = true
                            pinErrorNote = null
                            scope.launch {
                                val res = client.pairWithBeaconUsingPin(beacon, pinInput)
                                isPinPairingBusy = false
                                res.onSuccess { pairedPayload ->
                                    scannedReceiverPayload = pairedPayload
                                    selectedBeaconForPin = null
                                }.onFailure { err ->
                                    pinErrorNote = err.localizedMessage ?: "PIN errato o scaduto"
                                }
                            }
                        },
                        onToggleBootstrapPortal = {
                            if (bootstrapPortalUrl == null) {
                                if (LocalNetworkAddresses.listPrivateIpv4Addresses().isNotEmpty()) {
                                    bootstrapWifiQrString = null
                                    bootstrapPortalUrl = server.startBootstrapPortalSession()
                                } else {
                                    // Nessuna Wi-Fi presente: attiva in automatico l'Hotspot 5GHz Offline sul vecchio telefono
                                    hotspotController.startHotspot { ssid, pass, _ ->
                                        if (!ssid.isNullOrBlank() && !pass.isNullOrBlank()) {
                                            val escSsid = ssid.replace("\\", "\\\\").replace(";", "\\;").replace(",", "\\,").replace(":", "\\:")
                                            val escPass = pass.replace("\\", "\\\\").replace(";", "\\;").replace(",", "\\,").replace(":", "\\:")
                                            bootstrapWifiQrString = "WIFI:T:WPA;S:$escSsid;P:$escPass;;"
                                        } else {
                                            bootstrapWifiQrString = null
                                        }
                                        bootstrapPortalUrl = server.startBootstrapPortalSession()
                                    }
                                }
                            } else {
                                server.stop()
                                if (bootstrapWifiQrString != null) {
                                    hotspotController.stopHotspot()
                                }
                                bootstrapWifiQrString = null
                                bootstrapPortalUrl = null
                            }
                        },
                        onPickDocumentsOrWhatsApp = {
                            documentPickerLauncher.launch(arrayOf("*/*"))
                        },
                        onToggleCamera = { showCameraScanner = !showCameraScanner },
                        onQrDetected = { raw ->
                            runCatching { QrPairingPayload.fromJson(raw) }.onSuccess {
                                scannedReceiverPayload = it
                                selectedBeaconForPin = null
                                manualQrErrorNote = null
                                showCameraScanner = false
                            }
                        },
                        onManualInputChange = {
                            manualQrInput = it
                            manualQrErrorNote = null
                        },
                        onApplyManualQr = {
                            runCatching { QrPairingPayload.fromJson(manualQrInput) }
                                .onSuccess {
                                    scannedReceiverPayload = it
                                    manualQrErrorNote = null
                                }
                                .onFailure {
                                    manualQrErrorNote = "Formato codice QR non valido."
                                }
                        },
                        onUpdateCategories = { categories = it },
                        onOpenProUnlock = { mode = WizardMode.CROSS_OS_PRO_SHEET },
                        onStartTransfer = {
                            val target = scannedReceiverPayload ?: return@SenderScanAndPickStep
                            autoDiscovery.stopScanning()
                            if (bootstrapPortalUrl != null) {
                                server.stop()
                                if (bootstrapWifiQrString != null) {
                                    hotspotController.stopHotspot()
                                }
                                bootstrapWifiQrString = null
                                bootstrapPortalUrl = null
                            }
                            isReceiverFlow = false
                            mode = WizardMode.LIVE_TRANSFER_DASHBOARD
                            scope.launch {
                                client.executeTransfer(
                                    qrPayload = target,
                                    includeContacts = categories.contacts,
                                    includePhotos = categories.photos,
                                    includeVideos = categories.videos,
                                    includeCalendars = categories.calendars,
                                    includeSms = categories.sms,
                                    includeDocuments = categories.documents,
                                    includeWhatsAppVault = categories.whatsAppVault
                                )
                            }
                        },
                        onBack = {
                            autoDiscovery.stopScanning()
                            if (bootstrapPortalUrl != null) {
                                server.stop()
                                if (bootstrapWifiQrString != null) {
                                    hotspotController.stopHotspot()
                                }
                                bootstrapWifiQrString = null
                                bootstrapPortalUrl = null
                            }
                            mode = WizardMode.ROLE_SELECTION
                        }
                    )
                }

                WizardMode.LIVE_TRANSFER_DASHBOARD -> {
                    LiveTransferDashboardStep(
                        progress = if (isReceiverFlow) serverProgress else clientProgress,
                        isReceiver = isReceiverFlow,
                        onFinishAndBack = {
                            server.stop()
                            hotspotController.stopHotspot()
                            mode = WizardMode.ROLE_SELECTION
                        }
                    )
                }

                WizardMode.CROSS_OS_PRO_SHEET -> {
                    CrossOsProPassSheet(
                        isUnlocked = isProUnlocked,
                        hasCloudSave = hasCloudSaveInstalled,
                        billingNote = billingStatusNote,
                        onPurchasePass = {
                            billingManager.launchCrossOsPassPurchase(context.findHostActivity())
                        },
                        onRestorePurchases = {
                            billingManager.restoreExistingPurchases(userInitiated = true)
                        },
                        onClose = { mode = WizardMode.ROLE_SELECTION }
                    )
                }
            }
        }
    }
}

@Composable
private fun RoleSelectionStep(
    summary: LocalDeviceScanSummary?,
    isProUnlocked: Boolean,
    bridgeCapabilities: GoogleSetupBridge.BridgeAvailability,
    stabilizeWifiHotspot: Boolean,
    hotspotNote: String?,
    googleBridgeNote: String?,
    onToggleStabilizeWifi: (Boolean) -> Unit,
    onGrantPermissions: () -> Unit,
    onSelectSender: () -> Unit,
    onSelectReceiver: () -> Unit,
    onLaunchGoogleOldPhone: () -> Unit,
    onLaunchGoogleNewPhone: () -> Unit,
    onLaunchGoogleIphoneToAndroid: () -> Unit,
    onOpenProSheet: () -> Unit
) {
    DirectSwitchCard(selected = true) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Icon(Icons.Default.PhoneAndroid, contentDescription = null, tint = DirectSwitchTheme.tealPrimary)
            Column {
                Text(
                    text = "Sblocca 'Configura' Nativo di Google",
                    fontWeight = FontWeight.Bold,
                    fontSize = 17.sp,
                    color = DirectSwitchTheme.textPrimary
                )
                Text(
                    text = "Quando il nuovo telefono è già configurato o la Wi-Fi è assente/instabile",
                    fontSize = 12.sp,
                    color = DirectSwitchTheme.tealPrimary,
                    fontWeight = FontWeight.SemiBold
                )
            }
        }
        Text(
            text = "Se il telefono nuovo è già avviato o la Wi-Fi cade, Google nasconde 'Configura dispositivo'. DirectSwitch stabilizza la rete e richiama il trasferimento ufficiale Google (anche da iPhone a Android):",
            fontSize = 12.sp,
            color = DirectSwitchTheme.textSecondary
        )

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
                Icon(Icons.Default.WifiTethering, contentDescription = null, tint = DirectSwitchTheme.blueAccent)
                Column {
                    Text(
                        text = "Stabilizza Wi-Fi (Hotspot 5GHz Locale)",
                        fontWeight = FontWeight.SemiBold,
                        fontSize = 13.sp,
                        color = DirectSwitchTheme.textPrimary
                    )
                    Text(
                        text = "Attivalo se non c'è Wi-Fi o se la rete cade durante Configura",
                        fontSize = 11.sp,
                        color = DirectSwitchTheme.textSecondary
                    )
                }
            }
            Switch(
                checked = stabilizeWifiHotspot,
                onCheckedChange = onToggleStabilizeWifi,
                colors = SwitchDefaults.colors(
                    checkedThumbColor = Color.White,
                    checkedTrackColor = DirectSwitchTheme.tealPrimary
                )
            )
        }
        if (!hotspotNote.isNullOrBlank()) {
            Text(
                text = hotspotNote,
                fontSize = 12.sp,
                fontWeight = FontWeight.Medium,
                color = DirectSwitchTheme.tealPrimary
            )
        }

        val gmsStatus = if (bridgeCapabilities.hasGooglePlayServicesD2d) "Play Services D2D Pronti" else "D2D assente"
        val restoreStatus = if (bridgeCapabilities.hasAndroidSwitchRestoreTool) "Android Switch Installato" else "Restore OEM"
        val usbStatus = if (bridgeCapabilities.isUsbCableDeviceAttached) {
            " • Cavo USB Attivo (${bridgeCapabilities.attachedUsbProductName ?: "Connesso"})"
        } else {
            ""
        }
        Text(
            text = "Stato moduli nativi: $gmsStatus • $restoreStatus$usbStatus",
            fontSize = 11.sp,
            color = DirectSwitchTheme.textMuted
        )

        DirectSwitchPrimaryButton(
            text = "1. Vecchio Android: Sblocca 'Configura Dispositivo' (Invia)",
            onClick = onLaunchGoogleOldPhone
        )
        DirectSwitchPrimaryButton(
            text = "2. Nuovo Android Già Avviato: Sblocca 'Copia Dati' (Ricevi)",
            onClick = onLaunchGoogleNewPhone,
            containerColor = DirectSwitchTheme.blueAccent
        )
        DirectSwitchSecondaryButton(
            text = "3. Da iPhone → a Questo Android (Usa Configura / Android Switch Google)",
            onClick = onLaunchGoogleIphoneToAndroid
        )

        if (!googleBridgeNote.isNullOrBlank()) {
            Text(
                text = googleBridgeNote,
                fontSize = 12.sp,
                fontWeight = FontWeight.SemiBold,
                color = DirectSwitchTheme.tealPrimary
            )
        }
    }

    DirectSwitchCard {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Icon(Icons.Default.Security, contentDescription = null, tint = DirectSwitchTheme.tealPrimary)
            Text(
                text = "Motore Diretto DirectSwitch (Verso iPhone & Fallback Universale)",
                fontSize = 14.sp,
                fontWeight = FontWeight.Bold,
                color = DirectSwitchTheme.textPrimary
            )
        }
        Text(
            text = "Poiché Configura di Google non invia verso iPhone (e alcuni produttori bloccano il ripristino post-avvio), usa il motore diretto 5GHz di DirectSwitch per trasferire e unire Rubrica, Foto/Video 4K, SMS, Documenti e Calendari senza doppioni:",
            fontSize = 12.sp,
            color = DirectSwitchTheme.textSecondary
        )
        if (summary != null) {
            val freeGb = summary.freeStorageBytes / (1024.0 * 1024.0 * 1024.0)
            Text(
                text = String.format(
                    Locale.ITALY,
                    "Spazio libero rilevato: %.1f GB • %d contatti • %d foto • %d video",
                    freeGb,
                    summary.contactsCount,
                    summary.photosCount,
                    summary.videosCount
                ),
                fontSize = 12.sp,
                fontWeight = FontWeight.Medium,
                color = DirectSwitchTheme.textPrimary
            )
        }
        TextButton(onClick = onGrantPermissions) {
            Text("Autorizza lettura Contatti, Galleria, SMS e Calendario", color = DirectSwitchTheme.blueAccent)
        }

        DirectSwitchPrimaryButton(
            text = "Invia con DirectSwitch (Verso iPhone o Android)",
            onClick = onSelectSender
        )
        DirectSwitchSecondaryButton(
            text = "Ricevi con DirectSwitch su Questo Telefono",
            onClick = onSelectReceiver
        )
    }

    DirectSwitchCard {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Icon(Icons.Default.PhoneAndroid, contentDescription = null, tint = DirectSwitchTheme.greenSuccess)
            Text(
                text = "Sblocco Configura Google & Android ↔ Android: 100% Gratuito",
                fontWeight = FontWeight.Bold,
                fontSize = 14.sp,
                color = DirectSwitchTheme.textPrimary
            )
        }
        Text(
            text = "Lo sblocco di Configura (incluso iPhone → Android nativo Google) e il passaggio Android ↔ Android sono sempre gratuiti.",
            fontSize = 12.sp,
            color = DirectSwitchTheme.textSecondary
        )
        HorizontalDivider(color = DirectSwitchTheme.cardBorder)
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.SpaceBetween
        ) {
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = if (isProUnlocked) "Ponte Diretto Android ↔ iPhone: Sbloccato" else "Passaggio Diretto verso iPhone (Pro)",
                    fontWeight = FontWeight.Bold,
                    fontSize = 14.sp,
                    color = DirectSwitchTheme.textPrimary
                )
                Text(
                    text = "Necessario quando invii da Android verso un iPhone già configurato (dove Configura di Google non esiste). Sblocco valido per entrambi i telefoni.",
                    fontSize = 12.sp,
                    color = DirectSwitchTheme.textSecondary
                )
            }
            TextButton(onClick = onOpenProSheet) {
                Text(if (isProUnlocked) "Attivo" else "Scopri", fontWeight = FontWeight.Bold)
            }
        }
    }
}

@Composable
private fun ReceiverQrHostStep(
    qrPayload: QrPairingPayload?,
    pairingPin: String,
    useHotspot: Boolean,
    hotspotNote: String?,
    onToggleHotspot: (Boolean) -> Unit,
    onBack: () -> Unit
) {
    val context = LocalContext.current
    var isDefaultSms by remember { mutableStateOf(SmsSystemScanner.isDefaultSmsApp(context)) }
    val smsRoleLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.StartActivityForResult()
    ) {
        isDefaultSms = SmsSystemScanner.isDefaultSmsApp(context)
    }

    DirectSwitchCard(selected = true) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Icon(Icons.Default.QrCode2, contentDescription = null, tint = DirectSwitchTheme.tealPrimary)
            Text(
                text = "Pronto a Ricevere (Senza Formattare)",
                fontSize = 17.sp,
                fontWeight = FontWeight.Bold,
                color = DirectSwitchTheme.textPrimary
            )
        }
        Text(
            text = "Apri DirectSwitch sul vecchio Android o iPhone, tocca 'Invia Dati' e inquadra questo QR (oppure seleziona il telefono rilevato e inserisci il PIN a 6 cifre):",
            fontSize = 13.sp,
            color = DirectSwitchTheme.textSecondary
        )

        if (qrPayload != null) {
            val compactJson = remember(qrPayload) { qrPayload.toCompactJson() }
            val qrBitmap = remember(compactJson) { QrBitmapGenerator.generate(compactJson, 620) }
            if (qrBitmap != null) {
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(vertical = 6.dp),
                    contentAlignment = Alignment.Center
                ) {
                    Image(
                        bitmap = qrBitmap.asImageBitmap(),
                        contentDescription = "QR Pairing DirectSwitch",
                        modifier = Modifier
                            .size(230.dp)
                            .clip(RoundedCornerShape(16.dp))
                            .background(Color.White)
                            .padding(10.dp)
                    )
                }
            }
            if (pairingPin.length == 6) {
                val formattedPin = "${pairingPin.substring(0, 3)} ${pairingPin.substring(3, 6)}"
                Text(
                    text = "PIN Auto-Discovery: $formattedPin",
                    fontSize = 18.sp,
                    fontWeight = FontWeight.Bold,
                    color = DirectSwitchTheme.tealPrimary,
                    modifier = Modifier.fillMaxWidth(),
                    textAlign = TextAlign.Center
                )
            }
            Text(
                text = "Canali IP locali: ${qrPayload.ips.joinToString(", ")} : ${qrPayload.port}",
                fontSize = 12.sp,
                color = DirectSwitchTheme.textMuted,
                modifier = Modifier.fillMaxWidth(),
                textAlign = TextAlign.Center
            )
        }

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
                Icon(Icons.Default.WifiTethering, contentDescription = null, tint = DirectSwitchTheme.blueAccent)
                Column {
                    Text("Hotspot Diretto 5GHz (Senza Router)", fontWeight = FontWeight.SemiBold, fontSize = 13.sp)
                    Text("L'iPhone si aggancia da solo inquadrando il QR", fontSize = 11.sp, color = DirectSwitchTheme.textSecondary)
                }
            }
            Switch(
                checked = useHotspot,
                onCheckedChange = onToggleHotspot,
                colors = SwitchDefaults.colors(checkedThumbColor = Color.White, checkedTrackColor = DirectSwitchTheme.tealPrimary)
            )
        }

        if (!hotspotNote.isNullOrBlank()) {
            Text(text = hotspotNote, fontSize = 12.sp, color = DirectSwitchTheme.tealPrimary, fontWeight = FontWeight.Medium)
        }

        HorizontalDivider(color = DirectSwitchTheme.cardBorder)
        if (!isDefaultSms) {
            TextButton(
                onClick = {
                    SmsSystemScanner.createDefaultSmsRoleIntent(context)?.let { smsRoleLauncher.launch(it) }
                }
            ) {
                Text(
                    "Vuoi inserire gli SMS direttamente nell'app Messaggi? Abilita Ruolo SMS temporaneo",
                    fontSize = 12.sp,
                    color = DirectSwitchTheme.blueAccent
                )
            }
        } else {
            Text(
                text = "Ruolo SMS attivo: gli SMS ricevuti verranno scritti direttamente nell'app Messaggi di sistema (potrai ripristinare l'app predefinita a fine trasferimento).",
                fontSize = 12.sp,
                color = DirectSwitchTheme.greenSuccess
            )
        }
    }

    DirectSwitchSecondaryButton(text = stringResource(R.string.back_button), onClick = onBack)
}

@Composable
private fun SenderScanAndPickStep(
    summary: LocalDeviceScanSummary?,
    discoveredDevices: List<DiscoveryBeaconPayload>,
    selectedBeacon: DiscoveryBeaconPayload?,
    pinInput: String,
    pinErrorNote: String?,
    isPinPairingBusy: Boolean,
    scannedPayload: QrPairingPayload?,
    bootstrapPortalUrl: String?,
    bootstrapWifiQrString: String?,
    vaultStatusNote: String?,
    manualQrInput: String,
    manualQrErrorNote: String?,
    showCameraScanner: Boolean,
    isLocalPro: Boolean,
    categories: CategorySelectionState,
    onSelectDiscoveredBeacon: (DiscoveryBeaconPayload) -> Unit,
    onPinInputChange: (String) -> Unit,
    onConfirmPinPairing: () -> Unit,
    onToggleBootstrapPortal: () -> Unit,
    onPickDocumentsOrWhatsApp: () -> Unit,
    onToggleCamera: () -> Unit,
    onQrDetected: (String) -> Unit,
    onManualInputChange: (String) -> Unit,
    onApplyManualQr: () -> Unit,
    onUpdateCategories: (CategorySelectionState) -> Unit,
    onOpenProUnlock: () -> Unit,
    onStartTransfer: () -> Unit,
    onBack: () -> Unit
) {
    DirectSwitchCard(selected = discoveredDevices.isNotEmpty() || scannedPayload != null) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Icon(Icons.Default.WifiTethering, contentDescription = null, tint = DirectSwitchTheme.tealPrimary)
            Text(
                text = when {
                    scannedPayload != null -> "Collegato in modo cifrato a ${scannedPayload.receiverName}"
                    discoveredDevices.isNotEmpty() -> "Dispositivo Nuovo Rilevato sulla Rete Locale!"
                    else -> "Ricerca automatica del nuovo telefono nelle vicinanze..."
                },
                fontWeight = FontWeight.Bold,
                fontSize = 16.sp,
                color = DirectSwitchTheme.textPrimary
            )
        }

        if (scannedPayload == null && discoveredDevices.isNotEmpty()) {
            for (found in discoveredDevices) {
                DirectSwitchPrimaryButton(
                    text = "Collega a ${found.receiverName} (${found.receiverPlatform})",
                    onClick = { onSelectDiscoveredBeacon(found) }
                )
            }
            if (selectedBeacon != null) {
                OutlinedTextField(
                    value = pinInput,
                    onValueChange = onPinInputChange,
                    label = { Text("Inserisci PIN a 6 cifre mostrato su ${selectedBeacon.receiverName}") },
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.NumberPassword),
                    modifier = Modifier.fillMaxWidth(),
                    singleLine = true
                )
                if (!pinErrorNote.isNullOrBlank()) {
                    Text(pinErrorNote, fontSize = 12.sp, color = DirectSwitchTheme.dangerRed, fontWeight = FontWeight.SemiBold)
                }
                DirectSwitchPrimaryButton(
                    text = if (isPinPairingBusy) "Verifica PIN crittografico..." else "Conferma PIN e Accoppia",
                    onClick = onConfirmPinPairing,
                    enabled = pinInput.length == 6 && !isPinPairingBusy,
                    containerColor = DirectSwitchTheme.blueAccent
                )
            }
        } else if (scannedPayload == null) {
            Text(
                text = "Se hai aperto 'Ricevi' sul nuovo Android o iPhone sotto la stessa Wi-Fi, comparirà qui da solo in 2 secondi.",
                fontSize = 12.sp,
                color = DirectSwitchTheme.textSecondary
            )
        }
    }

    if (scannedPayload == null) {
        DirectSwitchCard {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Icon(Icons.Default.QrCode2, contentDescription = null, tint = DirectSwitchTheme.blueAccent)
                Text(
                    text = "Non hai ancora l'app sul Telefono Nuovo?",
                    fontWeight = FontWeight.Bold,
                    fontSize = 15.sp,
                    color = DirectSwitchTheme.textPrimary
                )
            }
            Text(
                text = "Inquadra questo QR protetto con la normale Fotocamera del telefono nuovo: scaricherà l'app guidata via Wi-Fi locale (zero internet) o importerà subito la Rubrica su iPhone!",
                fontSize = 12.sp,
                color = DirectSwitchTheme.textSecondary
            )
            DirectSwitchSecondaryButton(
                text = if (bootstrapPortalUrl == null) "Mostra QR di Installazione Guidata per il Nuovo Telefono" else "Nascondi QR di Installazione Guidata",
                onClick = onToggleBootstrapPortal
            )
            if (bootstrapPortalUrl != null) {
                if (bootstrapWifiQrString != null) {
                    Text(
                        text = "Passo 1 (Senza Wi-Fi): inquadra con la Fotocamera del telefono nuovo per agganciare l'Hotspot 5GHz Offline",
                        fontSize = 12.sp,
                        fontWeight = FontWeight.SemiBold,
                        color = DirectSwitchTheme.tealPrimary,
                        modifier = Modifier.fillMaxWidth(),
                        textAlign = TextAlign.Center
                    )
                    val wifiQr = remember(bootstrapWifiQrString) { QrBitmapGenerator.generate(bootstrapWifiQrString, 520) }
                    if (wifiQr != null) {
                        Box(modifier = Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
                            Image(
                                bitmap = wifiQr.asImageBitmap(),
                                contentDescription = "QR Hotspot Offline",
                                modifier = Modifier
                                    .size(190.dp)
                                    .clip(RoundedCornerShape(14.dp))
                                    .background(Color.White)
                                    .padding(8.dp)
                            )
                        }
                    }
                    Text(
                        text = "Passo 2: inquadra per scaricare DirectSwitch (.APK) o la Rubrica senza internet",
                        fontSize = 12.sp,
                        fontWeight = FontWeight.SemiBold,
                        color = DirectSwitchTheme.blueAccent,
                        modifier = Modifier.fillMaxWidth(),
                        textAlign = TextAlign.Center
                    )
                }
                val bootQr = remember(bootstrapPortalUrl) { QrBitmapGenerator.generate(bootstrapPortalUrl, 560) }
                if (bootQr != null) {
                    Box(modifier = Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
                        Image(
                            bitmap = bootQr.asImageBitmap(),
                            contentDescription = "QR Bootstrap Nuovo Telefono",
                            modifier = Modifier
                                .size(210.dp)
                                .clip(RoundedCornerShape(14.dp))
                                .background(Color.White)
                                .padding(8.dp)
                        )
                    }
                }
                Text(
                    text = "Sessione protetta da token monouso attiva sulla rete locale",
                    fontSize = 12.sp,
                    color = DirectSwitchTheme.blueAccent,
                    modifier = Modifier.fillMaxWidth(),
                    textAlign = TextAlign.Center
                )
            }
        }
    }

    DirectSwitchCard(selected = scannedPayload != null) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Icon(Icons.Default.QrCodeScanner, contentDescription = null, tint = DirectSwitchTheme.tealPrimary)
            Text(
                text = if (scannedPayload == null) "Oppure Inquadra il QR del Ricevente" else "Sessione attiva con ${scannedPayload.receiverName}",
                fontWeight = FontWeight.Bold,
                fontSize = 16.sp,
                color = DirectSwitchTheme.textPrimary
            )
        }

        if (scannedPayload == null) {
            DirectSwitchPrimaryButton(
                text = if (showCameraScanner) "Chiudi Fotocamera" else "Inquadra Codice QR del Ricevente",
                onClick = onToggleCamera
            )
            if (showCameraScanner) {
                QrCameraPreviewBox(onQrScanned = onQrDetected)
            }
            OutlinedTextField(
                value = manualQrInput,
                onValueChange = onManualInputChange,
                label = { Text("Oppure incolla stringa QR di test") },
                modifier = Modifier.fillMaxWidth(),
                singleLine = true
            )
            if (!manualQrErrorNote.isNullOrBlank()) {
                Text(manualQrErrorNote, fontSize = 12.sp, color = DirectSwitchTheme.dangerRed)
            }
            if (manualQrInput.isNotBlank()) {
                TextButton(onClick = onApplyManualQr) {
                    Text("Collega manualmente")
                }
            }
        } else {
            val isCrossOs = scannedPayload.receiverPlatform == DevicePlatform.IOS
            val sessionUnlocked = !isCrossOs || isLocalPro || scannedPayload.receiverHasPro
            Text(
                text = if (!isCrossOs) {
                    "Modalità Android → Android rilevata: Trasferimento 100% Gratuito Illimitato!"
                } else if (sessionUnlocked) {
                    "Ponte Android → iPhone Pro Sbloccato (Single-Side Unlock attivo)!"
                } else {
                    "Modalità Prova Android → iPhone: Contatti completi + 25 foto gratis. Sblocca Pro per trasferire tutti i GB."
                },
                fontSize = 13.sp,
                fontWeight = FontWeight.SemiBold,
                color = if (sessionUnlocked) DirectSwitchTheme.greenSuccess else DirectSwitchTheme.amberPro
            )
            if (isCrossOs && !sessionUnlocked) {
                TextButton(onClick = onOpenProUnlock) {
                    Text("Sblocca Pass Completo Android ↔ iPhone")
                }
            }
        }
    }

    val toggleSpecs = listOf(
        CategoryToggleSpec(
            icon = Icons.Default.Contacts,
            title = "Rubrica Contatti (Smart Merge E.164)",
            subtitle = "${summary?.contactsCount ?: 0} contatti trovati",
            checked = categories.contacts,
            onToggle = { onUpdateCategories(categories.copy(contacts = it)) }
        ),
        CategoryToggleSpec(
            icon = Icons.Default.Image,
            title = "Foto & Album Originali (EXIF + GPS)",
            subtitle = "${summary?.photosCount ?: 0} foto (${formatMb(summary?.photosBytes ?: 0L)})",
            checked = categories.photos,
            onToggle = { onUpdateCategories(categories.copy(photos = it)) }
        ),
        CategoryToggleSpec(
            icon = Icons.Default.Videocam,
            title = "Video HD / 4K Streaming Cifrato",
            subtitle = "${summary?.videosCount ?: 0} video (${formatMb(summary?.videosBytes ?: 0L)})",
            checked = categories.videos,
            onToggle = { onUpdateCategories(categories.copy(videos = it)) }
        ),
        CategoryToggleSpec(
            icon = Icons.Default.CalendarMonth,
            title = "Calendari ed Eventi",
            subtitle = "${summary?.calendarEventsCount ?: 0} eventi",
            checked = categories.calendars,
            onToggle = { onUpdateCategories(categories.copy(calendars = it)) }
        ),
        CategoryToggleSpec(
            icon = Icons.Default.Sms,
            title = "SMS & Messaggi di Sistema",
            subtitle = "${summary?.smsCount ?: 0} messaggi rilevati",
            checked = categories.sms,
            onToggle = { onUpdateCategories(categories.copy(sms = it)) }
        ),
        CategoryToggleSpec(
            icon = Icons.Default.Description,
            title = "Documenti, PDF & File",
            subtitle = "${summary?.documentsCount ?: 0} documenti pronti",
            checked = categories.documents,
            onToggle = { onUpdateCategories(categories.copy(documents = it)) }
        ),
        CategoryToggleSpec(
            icon = Icons.AutoMirrored.Filled.Chat,
            title = "Vault Archivio Chat WhatsApp (.zip)",
            subtitle = "${summary?.whatsappArchivesCount ?: 0} esportazioni WhatsApp pronte",
            checked = categories.whatsAppVault,
            onToggle = { onUpdateCategories(categories.copy(whatsAppVault = it)) }
        )
    )

    DirectSwitchCard {
        Text(
            text = "Passo 2: Scegli cosa unire sul nuovo telefono (Zero Duplicati)",
            fontWeight = FontWeight.Bold,
            fontSize = 15.sp,
            color = DirectSwitchTheme.textPrimary
        )

        for (spec in toggleSpecs) {
            CategoryCheckRow(
                icon = spec.icon,
                title = spec.title,
                subtitle = spec.subtitle,
                checked = spec.checked,
                onCheckedChange = spec.onToggle
            )
        }

        DirectSwitchSecondaryButton(
            text = stringResource(R.string.add_docs_or_whatsapp_button),
            onClick = onPickDocumentsOrWhatsApp
        )
        if (!vaultStatusNote.isNullOrBlank()) {
            Text(vaultStatusNote, fontSize = 12.sp, color = DirectSwitchTheme.tealPrimary, fontWeight = FontWeight.SemiBold)
        }

        DirectSwitchPrimaryButton(
            text = stringResource(R.string.start_encrypted_transfer),
            onClick = onStartTransfer,
            enabled = scannedPayload != null
        )
    }

    DirectSwitchSecondaryButton(text = stringResource(R.string.back_button), onClick = onBack)
}

@Composable
private fun CategoryCheckRow(
    icon: ImageVector,
    title: String,
    subtitle: String,
    checked: Boolean,
    onCheckedChange: (Boolean) -> Unit
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable { onCheckedChange(!checked) }
            .padding(vertical = 4.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.SpaceBetween
    ) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(10.dp),
            modifier = Modifier.weight(1f)
        ) {
            Icon(icon, contentDescription = null, tint = DirectSwitchTheme.tealPrimary)
            Column {
                Text(title, fontWeight = FontWeight.SemiBold, fontSize = 14.sp, color = DirectSwitchTheme.textPrimary)
                Text(subtitle, fontSize = 12.sp, color = DirectSwitchTheme.textSecondary)
            }
        }
        Checkbox(
            checked = checked,
            onCheckedChange = onCheckedChange,
            colors = CheckboxDefaults.colors(checkedColor = DirectSwitchTheme.tealPrimary)
        )
    }
}

@Composable
private fun LiveTransferDashboardStep(
    progress: LiveTransferProgress,
    isReceiver: Boolean,
    onFinishAndBack: () -> Unit
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

    DirectSwitchCard(selected = true) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            Icon(
                imageVector = if (progress.isCompleted) Icons.Default.CheckCircle else Icons.Default.SwapHoriz,
                contentDescription = null,
                tint = if (progress.isCompleted) DirectSwitchTheme.greenSuccess else DirectSwitchTheme.tealPrimary,
                modifier = Modifier.size(30.dp)
            )
            Column {
                Text(
                    text = if (isReceiver) "Ricezione Diretta in Corso" else "Invio Diretto in Corso",
                    fontWeight = FontWeight.Bold,
                    fontSize = 18.sp,
                    color = DirectSwitchTheme.textPrimary
                )
                Text(
                    text = progress.phaseLabel,
                    fontSize = 13.sp,
                    color = DirectSwitchTheme.textSecondary
                )
            }
        }

        val ratio = if (progress.totalBytes > 0L) {
            (progress.transferredBytes.toFloat() / progress.totalBytes.toFloat()).coerceIn(0f, 1f)
        } else if (progress.isCompleted) 1f else 0f

        LinearProgressIndicator(
            progress = { ratio },
            modifier = Modifier
                .fillMaxWidth()
                .height(10.dp)
                .clip(RoundedCornerShape(6.dp)),
            color = DirectSwitchTheme.tealPrimary
        )

        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween
        ) {
            Text(
                text = String.format(Locale.ITALY, "Velocità: %.1f MB/s", progress.speedMegabytesPerSec),
                fontWeight = FontWeight.Bold,
                fontSize = 14.sp,
                color = DirectSwitchTheme.tealPrimary
            )
            Text(
                text = "${progress.completedItems} / ${progress.totalItems} file (${formatMb(progress.transferredBytes)})",
                fontSize = 13.sp,
                color = DirectSwitchTheme.textPrimary
            )
        }

        if (progress.currentFileName.isNotEmpty()) {
            Text(
                text = "Elemento: ${progress.currentFileName}",
                fontSize = 12.sp,
                color = DirectSwitchTheme.textMuted
            )
        }

        HorizontalDivider(color = DirectSwitchTheme.cardBorder)

        Text(
            text = "Contatti uniti: ${progress.mergedContacts} • Calendari: ${progress.importedCalendars} • SMS: ${progress.importedSms} • Duplicati evitati: ${progress.skippedDuplicates}",
            fontSize = 13.sp,
            fontWeight = FontWeight.Medium,
            color = DirectSwitchTheme.textPrimary
        )

        if (progress.licenseTier != null) {
            val tierText = when (progress.licenseTier) {
                SessionLicenseTier.INTRA_OS_FREE -> "Sessione Intra-OS Gratuita Illimitata"
                SessionLicenseTier.CROSS_OS_PRO_UNLOCKED -> "Sessione Cross-OS Pro Sbloccata"
                SessionLicenseTier.CROSS_OS_PREVIEW -> "Sessione Prova Cross-OS (Contatti + 25 Foto)"
            }
            Text(text = tierText, fontSize = 12.sp, color = DirectSwitchTheme.blueAccent)
        }

        if (progress.errorMessage != null) {
            Text(
                text = progress.errorMessage,
                fontSize = 13.sp,
                fontWeight = FontWeight.SemiBold,
                color = DirectSwitchTheme.dangerRed
            )
        }

        Text(
            text = "Documenti, esportazioni WhatsApp e archivio SMS sono salvati nella cartella pubblica Download/DirectSwitch.",
            fontSize = 11.sp,
            color = DirectSwitchTheme.textMuted
        )
    }

    if (isReceiver && stillDefaultSms && (progress.isCompleted || progress.errorMessage != null)) {
        DirectSwitchCard {
            Text(
                text = stringResource(R.string.restore_default_sms_prompt),
                fontSize = 13.sp,
                fontWeight = FontWeight.SemiBold,
                color = DirectSwitchTheme.amberPro
            )
            DirectSwitchPrimaryButton(
                text = stringResource(R.string.restore_default_sms_button),
                onClick = {
                    runCatching {
                        restoreSmsLauncher.launch(SmsSystemScanner.createRestorePreviousSmsAppIntent(context))
                    }
                },
                containerColor = DirectSwitchTheme.blueAccent
            )
        }
    }

    if (progress.isCompleted || progress.errorMessage != null) {
        DirectSwitchPrimaryButton(text = "Torna alla Schermata Principale", onClick = onFinishAndBack)
    }
}

@Composable
private fun CrossOsProPassSheet(
    isUnlocked: Boolean,
    hasCloudSave: Boolean,
    billingNote: String?,
    onPurchasePass: () -> Unit,
    onRestorePurchases: () -> Unit,
    onClose: () -> Unit
) {
    DirectSwitchCard(selected = true) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Icon(Icons.Default.LockOpen, contentDescription = null, tint = DirectSwitchTheme.tealPrimary)
            Text(
                text = "DirectSwitch Pass Cross-OS (Android ↔ iPhone)",
                fontWeight = FontWeight.Bold,
                fontSize = 18.sp,
                color = DirectSwitchTheme.textPrimary
            )
        }
        Text(
            text = "• Lo sblocco di Configura di Google (incluso iPhone → Android) e Android ↔ Android sono SEMPRE gratuiti al 100%.\n" +
                "• Per inviare da Android verso un iPhone già configurato tramite il motore DirectSwitch ti basta sbloccare il Pass su UN SOLO telefono (Single-Side Unlock).\n" +
                "• Hai già CloudSave Pro? Lo sblocco sarà incluso gratuitamente con account verificato.",
            fontSize = 13.sp,
            color = DirectSwitchTheme.textSecondary
        )

        if (hasCloudSave && !isUnlocked) {
            Text(
                text = "App CloudSave rilevata sul dispositivo.",
                fontSize = 12.sp,
                color = DirectSwitchTheme.blueAccent
            )
        }

        if (!billingNote.isNullOrBlank()) {
            Text(
                text = billingNote,
                fontSize = 12.sp,
                fontWeight = FontWeight.SemiBold,
                color = DirectSwitchTheme.tealPrimary
            )
        }

        if (isUnlocked) {
            Text(
                text = "Pass Cross-OS Pro attivo su questo dispositivo!",
                fontWeight = FontWeight.Bold,
                color = DirectSwitchTheme.greenSuccess,
                fontSize = 14.sp
            )
        } else {
            DirectSwitchPrimaryButton(
                text = "Acquista Pass Cross-OS Una Tantum (9,99 €)",
                onClick = onPurchasePass
            )
            TextButton(onClick = onRestorePurchases) {
                Text("Ripristina Acquisti Google Play", color = DirectSwitchTheme.blueAccent)
            }
        }

        Spacer(modifier = Modifier.height(4.dp))
        DirectSwitchSecondaryButton(text = stringResource(R.string.close_button), onClick = onClose)
    }
}

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

/**
 * Decodifica il piano Y (`YUV_420_888`) rispettando `rowStride` e `pixelStride` di qualsiasi sensore Camera2,
 * evitando distorsioni diagonali e ignorando silenziosamente `ReaderException` sui frame privi di QR.
 */
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
        // Normale su tutti i frame in cui non è ancora inquadrato un codice QR: nessun log.
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
