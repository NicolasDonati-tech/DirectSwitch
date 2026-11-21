//
//  SenderCategoryDropdownComponents.kt
//  DirectSwitch-Android
//
//  Created by Nicolas Donati.
//  Copyright © 2026 Nicolas Donati. Tutti i diritti riservati.
//

package com.directswitch.android.ui

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.util.LruCache
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.expandVertically
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.shrinkVertically
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Chat
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.AccountBalance
import androidx.compose.material.icons.filled.Apps
import androidx.compose.material.icons.filled.Badge
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Clear
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.DirectionsTransit
import androidx.compose.material.icons.filled.ExpandLess
import androidx.compose.material.icons.filled.ExpandMore
import androidx.compose.material.icons.filled.Folder
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.MusicNote
import androidx.compose.material.icons.filled.PhoneAndroid
import androidx.compose.material.icons.filled.PhotoCamera
import androidx.compose.material.icons.filled.QrCode2
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.SdCard
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.ShoppingBag
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.CircularProgressIndicator
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
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.graphics.drawable.toBitmap
import com.directswitch.android.migrators.DocumentLocationSummary
import com.directswitch.android.migrators.DocumentsAndWhatsAppScanner
import com.directswitch.android.migrators.InstalledAppCategoryGroup
import com.directswitch.android.protocol.DirectSwitchL10n
import com.directswitch.android.protocol.TransferDisplayFormatting
import com.directswitch.android.protocol.InstalledAppRecord
import com.directswitch.android.ui.theme.AppleSettingsIcon
import com.directswitch.android.ui.theme.CleanCategoryToggleRow
import com.directswitch.android.ui.theme.DirectSwitchCard
import com.directswitch.android.ui.theme.DirectSwitchSecondaryButton
import com.directswitch.android.ui.theme.DirectSwitchTheme
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.text.DateFormat
import java.util.Date
import java.util.Locale

private object AndroidAppIconBitmapCache {
    private val cache = LruCache<String, ImageBitmap>(256)

    fun get(packageName: String): ImageBitmap? = cache.get(packageName)

    fun put(packageName: String, bmp: ImageBitmap) {
        cache.put(packageName, bmp)
    }
}

@Composable
fun CategoryDropdownCard(
    icon: ImageVector,
    iconColor: Color,
    title: String,
    countBadge: String? = null,
    premiumBadge: Boolean = false,
    checked: Boolean,
    onCheckedChange: (Boolean) -> Unit,
    dropdownContent: @Composable ColumnScope.() -> Unit
) {
    DirectSwitchCard(
        selected = checked,
        padding = 0.dp,
        spacing = 0.dp
    ) {
        CleanCategoryToggleRow(
            icon = icon,
            iconColor = iconColor,
            title = title,
            subtitle = countBadge,
            premiumBadge = premiumBadge,
            checked = checked,
            onCheckedChange = onCheckedChange
        )

        AnimatedVisibility(
            visible = checked,
            enter = expandVertically() + fadeIn(),
            exit = shrinkVertically() + fadeOut()
        ) {
            Column(modifier = Modifier.fillMaxWidth()) {
                HorizontalDivider(
                    modifier = Modifier.padding(horizontal = 14.dp),
                    color = DirectSwitchTheme.hairline
                )
                Column(
                    modifier = Modifier
                        .fillMaxWidth()
                        .background(DirectSwitchTheme.inputSurface.copy(alpha = 0.45f))
                        .padding(14.dp),
                    verticalArrangement = Arrangement.spacedBy(10.dp),
                    content = dropdownContent
                )
            }
        }
    }
}

@Composable
fun ProgressivePreloadDropdownBody(
    hasPermission: Boolean,
    permissionTitle: String,
    onRequestPermission: () -> Unit,
    isLoading: Boolean,
    loadedCount: Int,
    totalCount: Int,
    loadingLabel: String,
    readyLabel: String,
    detailLabel: String,
    accentColor: Color,
    onReload: () -> Unit
) {
    val context = LocalContext.current
    if (!hasPermission) {
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(6.dp)
            ) {
                Icon(
                    imageVector = Icons.Filled.Warning,
                    contentDescription = null,
                    tint = DirectSwitchTheme.orange,
                    modifier = Modifier.size(16.dp)
                )
                Text(
                    text = permissionTitle,
                    fontSize = 12.5.sp,
                    fontWeight = FontWeight.SemiBold,
                    color = DirectSwitchTheme.textPrimary
                )
            }
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                DirectSwitchSecondaryButton(
                    text = DirectSwitchL10n.tr("Concedi permesso", en = "Grant permission", fr = "Autoriser"),
                    onClick = onRequestPermission,
                    tint = DirectSwitchTheme.orange,
                    modifier = Modifier.weight(1f)
                )
                DirectSwitchSecondaryButton(
                    text = DirectSwitchL10n.tr("Impostazioni", en = "Settings", fr = "Réglages"),
                    onClick = {
                        val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                            data = Uri.fromParts("package", context.packageName, null)
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        }
                        runCatching { context.startActivity(intent) }
                    },
                    tint = DirectSwitchTheme.textSecondary,
                    modifier = Modifier.weight(1f)
                )
            }
        }
        return
    }

    val safeTotal = maxOf(1, totalCount)
    val progressRatio = if (!isLoading) {
        1f
    } else {
        (loadedCount.toFloat() / safeTotal.toFloat()).coerceIn(0f, 1f)
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
            if (isLoading) {
                CircularProgressIndicator(
                    modifier = Modifier.size(16.dp),
                    strokeWidth = 2.dp,
                    color = accentColor
                )
            } else {
                Icon(
                    imageVector = Icons.Filled.CheckCircle,
                    contentDescription = null,
                    tint = DirectSwitchTheme.green,
                    modifier = Modifier.size(17.dp)
                )
            }
            Text(
                text = if (isLoading) loadingLabel else readyLabel,
                fontSize = 13.5.sp,
                fontWeight = FontWeight.Bold,
                color = DirectSwitchTheme.textPrimary
            )
        }
        if (!isLoading) {
            Text(
                text = DirectSwitchL10n.tr("Ricarica"),
                fontSize = 12.sp,
                fontWeight = FontWeight.SemiBold,
                color = DirectSwitchTheme.blue,
                modifier = Modifier.clickable(onClick = onReload)
            )
        }
    }

    if (isLoading || totalCount > 0) {
        LinearProgressIndicator(
            progress = { progressRatio },
            modifier = Modifier
                .fillMaxWidth()
                .height(6.dp)
                .clip(RoundedCornerShape(4.dp)),
            color = if (isLoading) accentColor else DirectSwitchTheme.green,
            trackColor = DirectSwitchTheme.cardSurface
        )
    }

    Text(
        text = detailLabel,
        fontSize = 12.sp,
        color = DirectSwitchTheme.textSecondary
    )
}

@Composable
fun DateSyncDropdownBody(
    hasPermission: Boolean,
    permissionTitle: String,
    onRequestPermission: () -> Unit,
    isLoading: Boolean,
    lastUpdatedEpochMillis: Long?,
    activeCount: Int,
    unitLabel: String,
    upToTodayOnly: Boolean,
    onToggleUpToToday: (Boolean) -> Unit,
    onRefresh: () -> Unit
) {
    if (!hasPermission) {
        ProgressivePreloadDropdownBody(
            hasPermission = false,
            permissionTitle = permissionTitle,
            onRequestPermission = onRequestPermission,
            isLoading = false,
            loadedCount = 0,
            totalCount = 0,
            loadingLabel = "",
            readyLabel = "",
            detailLabel = "",
            accentColor = DirectSwitchTheme.blue,
            onReload = onRefresh
        )
        return
    }

    val activeLocale = remember(DirectSwitchL10n.activeLanguage) {
        when (DirectSwitchL10n.effectiveCode()) {
            "en" -> Locale.ENGLISH
            "fr" -> Locale.FRENCH
            else -> Locale.ITALY
        }
    }
    val shortToday = remember(activeLocale) {
        DateFormat.getDateInstance(DateFormat.MEDIUM, activeLocale).format(Date())
    }
    val formattedUpdated = remember(lastUpdatedEpochMillis, activeLocale) {
        DateFormat.getDateTimeInstance(DateFormat.MEDIUM, DateFormat.SHORT, activeLocale)
            .format(Date(lastUpdatedEpochMillis ?: System.currentTimeMillis()))
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
            if (isLoading) {
                CircularProgressIndicator(
                    modifier = Modifier.size(16.dp),
                    strokeWidth = 2.dp,
                    color = DirectSwitchTheme.blue
                )
            } else {
                Icon(
                    imageVector = Icons.Filled.CheckCircle,
                    contentDescription = null,
                    tint = DirectSwitchTheme.green,
                    modifier = Modifier.size(17.dp)
                )
            }
            Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text(
                    text = if (isLoading) {
                        DirectSwitchL10n.tr("Aggiornamento alla data odierna in corso...", en = "Updating to today's date...", fr = "Mise à jour à la date du jour...")
                    } else {
                        DirectSwitchL10n.tr("Aggiornato al $formattedUpdated", en = "Updated on $formattedUpdated", fr = "Mis à jour le $formattedUpdated")
                    },
                    fontSize = 13.sp,
                    fontWeight = FontWeight.Bold,
                    color = DirectSwitchTheme.textPrimary
                )
                Text(
                    text = DirectSwitchL10n.tr(
                        "$activeCount $unitLabel pronti al passaggio",
                        en = "$activeCount ${DirectSwitchL10n.tr(unitLabel)} ready to copy",
                        fr = "$activeCount ${DirectSwitchL10n.tr(unitLabel)} prêts à copier"
                    ),
                    fontSize = 12.sp,
                    color = DirectSwitchTheme.textSecondary
                )
            }
        }
        if (!isLoading) {
            Text(
                text = DirectSwitchL10n.tr("Aggiorna"),
                fontSize = 12.sp,
                fontWeight = FontWeight.SemiBold,
                color = DirectSwitchTheme.blue,
                modifier = Modifier.clickable(onClick = onRefresh)
            )
        }
    }

    Row(
        modifier = Modifier.fillMaxWidth(),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.SpaceBetween
    ) {
        Column(modifier = Modifier.weight(1f).padding(end = 8.dp)) {
            Text(
                text = DirectSwitchL10n.tr(
                    "Trasferisci solo fino ad oggi ($shortToday)",
                    en = "Transfer only up to today ($shortToday)",
                    fr = "Transférer uniquement jusqu'à aujourd'hui ($shortToday)"
                ),
                fontSize = 12.5.sp,
                fontWeight = FontWeight.SemiBold,
                color = DirectSwitchTheme.textPrimary
            )
            Text(
                text = DirectSwitchL10n.tr(
                    "Se spento copia sia lo storico sia eventuali voci future.",
                    en = "When off, copies both past and future items.",
                    fr = "Si désactivé, copie l'historique et les éléments futurs."
                ),
                fontSize = 11.sp,
                color = DirectSwitchTheme.textSecondary
            )
        }
        Switch(
            checked = upToTodayOnly,
            onCheckedChange = onToggleUpToToday,
            colors = SwitchDefaults.colors(
                checkedThumbColor = Color.White,
                checkedTrackColor = DirectSwitchTheme.green,
                uncheckedThumbColor = Color.White,
                uncheckedTrackColor = DirectSwitchTheme.cardSurface,
                uncheckedBorderColor = DirectSwitchTheme.cardBorder
            )
        )
    }
}

@Composable
fun DocumentsPositionsDropdownBody(
    locationSummaries: List<DocumentLocationSummary>,
    hasAllFiles: Boolean,
    vaultStatusNote: String?,
    onToggleLocationSelection: (String, Boolean) -> Unit,
    onRemoveSafLocation: (String) -> Unit,
    onRefreshDocumentCheck: () -> Unit,
    onPickFolderTree: () -> Unit,
    onClearPickedDocuments: () -> Unit,
    hasPickedLocations: Boolean
) {
    val context = LocalContext.current
    val visibleLocations = remember(locationSummaries) {
        locationSummaries.filter { it.isRemovableSaf || it.fileCount > 0 || it.locationId.startsWith("vol:") }
    }

    Row(
        modifier = Modifier.fillMaxWidth(),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.SpaceBetween
    ) {
        Column(modifier = Modifier.weight(1f)) {
            Text(
                text = DirectSwitchL10n.tr("Aggiungi e spunta le posizioni"),
                fontSize = 13.5.sp,
                fontWeight = FontWeight.Bold,
                color = DirectSwitchTheme.textPrimary
            )
            val selectedCount = visibleLocations.count { it.isSelected }
            Text(
                text = if (selectedCount > 0) {
                    DirectSwitchL10n.tr("$selectedCount posizioni selezionate", en = "$selectedCount locations selected", fr = "$selectedCount emplacements sélectionnés")
                } else {
                    DirectSwitchL10n.tr("Spunta una o più posizioni da copiare", en = "Check one or more locations to copy", fr = "Cochez un ou plusieurs emplacements à copier")
                },
                fontSize = 12.sp,
                color = DirectSwitchTheme.textSecondary
            )
        }
        TextButton(onClick = onRefreshDocumentCheck) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(4.dp)
            ) {
                Icon(
                    imageVector = Icons.Filled.Refresh,
                    contentDescription = DirectSwitchL10n.tr("Ricontrolla"),
                    tint = DirectSwitchTheme.blue,
                    modifier = Modifier.size(16.dp)
                )
                Text(
                    text = DirectSwitchL10n.tr("Ricontrolla"),
                    fontSize = 12.sp,
                    fontWeight = FontWeight.SemiBold,
                    color = DirectSwitchTheme.blue
                )
            }
        }
    }

    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R && !hasAllFiles) {
        Surface(
            modifier = Modifier
                .fillMaxWidth()
                .clickable { DocumentsAndWhatsAppScanner.openAllFilesAccessSettings(context) },
            shape = RoundedCornerShape(12.dp),
            color = DirectSwitchTheme.orange.copy(alpha = 0.12f),
            border = BorderStroke(1.dp, DirectSwitchTheme.orange.copy(alpha = 0.45f))
        ) {
            Row(
                modifier = Modifier.padding(10.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                Icon(
                    imageVector = Icons.Filled.Warning,
                    contentDescription = null,
                    tint = DirectSwitchTheme.orange,
                    modifier = Modifier.size(18.dp)
                )
                Text(
                    text = DirectSwitchL10n.tr(
                        "Attiva «Accesso a tutti i file» per preparare tutte le cartelle della Memoria interna, Download e Documenti.",
                        en = "Enable 'All files access' to prepare all folders in Internal storage, Downloads and Documents.",
                        fr = "Activez « Accès à tous les fichiers » pour préparer Stockage interne, Téléchargements et Documents."
                    ),
                    fontSize = 12.sp,
                    lineHeight = 16.sp,
                    color = DirectSwitchTheme.textPrimary,
                    modifier = Modifier.weight(1f)
                )
                Icon(
                    imageVector = Icons.AutoMirrored.Filled.KeyboardArrowRight,
                    contentDescription = null,
                    tint = DirectSwitchTheme.orange
                )
            }
        }
    }

    Column(verticalArrangement = Arrangement.spacedBy(7.dp)) {
        visibleLocations.forEach { loc ->
            val iconVec = when {
                loc.locationId == "vol:primary" -> Icons.Filled.PhoneAndroid
                loc.locationName.contains("SD", ignoreCase = true) ||
                    loc.locationName.contains("USB", ignoreCase = true) -> Icons.Filled.SdCard
                else -> Icons.Filled.Folder
            }
            val cleanTitle = if (loc.locationId == "vol:primary") DirectSwitchL10n.tr("Memoria interna", en = "Internal storage", fr = "Stockage interne") else loc.locationName
            val foldersCount = maxOf(loc.folderCount, if (loc.fileCount > 0) 1 else 0)
            val foldersLabel = if (foldersCount == 1) {
                DirectSwitchL10n.tr("1 cartella preparata", en = "1 folder ready", fr = "1 dossier prêt")
            } else {
                DirectSwitchL10n.tr("$foldersCount cartelle preparate", en = "$foldersCount folders ready", fr = "$foldersCount dossiers prêts")
            }
            val subtitleText = if (loc.fileCount > 0) {
                "$foldersLabel • ${loc.fileCount} ${DirectSwitchL10n.tr("file", en = "files", fr = "fichiers")} • ${formatBytesHuman(loc.totalBytes)}"
            } else {
                foldersLabel
            }

            Surface(
                modifier = Modifier
                    .fillMaxWidth()
                    .clickable(enabled = loc.locationId.isNotBlank()) {
                        onToggleLocationSelection(loc.locationId, !loc.isSelected)
                    },
                shape = RoundedCornerShape(11.dp),
                color = if (loc.isSelected) DirectSwitchTheme.cardSurface else DirectSwitchTheme.cardSurface.copy(alpha = 0.6f),
                border = BorderStroke(
                    1.dp,
                    if (loc.isSelected) DirectSwitchTheme.blue.copy(alpha = 0.35f) else DirectSwitchTheme.cardBorder
                )
            ) {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 10.dp, vertical = 9.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(10.dp)
                ) {
                    if (loc.isSelected) {
                        Icon(
                            imageVector = Icons.Filled.CheckCircle,
                            contentDescription = "Selezionata",
                            tint = DirectSwitchTheme.blue,
                            modifier = Modifier.size(20.dp)
                        )
                    } else {
                        Box(
                            modifier = Modifier
                                .size(19.dp)
                                .border(1.6.dp, DirectSwitchTheme.textSecondary.copy(alpha = 0.5f), CircleShape)
                        )
                    }
                    Icon(
                        imageVector = iconVec,
                        contentDescription = null,
                        tint = if (loc.isSelected) DirectSwitchTheme.teal else DirectSwitchTheme.textSecondary,
                        modifier = Modifier.size(20.dp)
                    )
                    Column(modifier = Modifier.weight(1f)) {
                        Text(
                            text = cleanTitle,
                            fontSize = 13.5.sp,
                            fontWeight = FontWeight.Bold,
                            color = if (loc.isSelected) DirectSwitchTheme.textPrimary else DirectSwitchTheme.textSecondary,
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis
                        )
                        Text(
                            text = subtitleText,
                            fontSize = 12.sp,
                            color = if (loc.isSelected) DirectSwitchTheme.green else DirectSwitchTheme.textSecondary
                        )
                    }
                    if (loc.isRemovableSaf && loc.locationId.isNotBlank()) {
                        Icon(
                            imageVector = Icons.Filled.Close,
                            contentDescription = "Rimuovi posizione",
                            tint = DirectSwitchTheme.textSecondary,
                            modifier = Modifier
                                .size(18.dp)
                                .clickable { onRemoveSafLocation(loc.locationId) }
                        )
                    }
                }
            }
        }
    }

    if (!vaultStatusNote.isNullOrBlank()) {
        Text(
            text = vaultStatusNote,
            fontSize = 12.sp,
            fontWeight = FontWeight.Medium,
            color = DirectSwitchTheme.blue
        )
    }

    DirectSwitchSecondaryButton(
        text = DirectSwitchL10n.tr("Aggiungi altra posizione (Drive / SD / USB / Cartella)", en = "Add another location (Drive / SD / USB / Folder)", fr = "Ajouter un emplacement (Drive / SD / USB / Dossier)"),
        onClick = onPickFolderTree
    )

    if (hasPickedLocations) {
        TextButton(
            onClick = onClearPickedDocuments,
            modifier = Modifier.fillMaxWidth()
        ) {
            Text(
                text = DirectSwitchL10n.tr("Rimuovi posizioni aggiunte"),
                fontSize = 12.sp,
                fontWeight = FontWeight.SemiBold,
                color = DirectSwitchTheme.red
            )
        }
    }
}

@Composable
fun InstalledAppsDropdownBody(
    allApps: List<InstalledAppRecord>,
    groupedCategories: List<InstalledAppCategoryGroup>,
    deselectedPackages: Set<String>,
    isLoadingApps: Boolean,
    onToggleApp: (InstalledAppRecord) -> Unit,
    onToggleCategoryAll: (InstalledAppCategoryGroup, Boolean) -> Unit,
    onToggleAllDetected: (Boolean) -> Unit,
    onRefreshApps: () -> Unit,
    extraCuratedCategories: List<InstalledAppCategoryGroup> = emptyList(),
    selectedExtraPackages: Set<String> = emptySet(),
    onToggleExtraApp: (InstalledAppRecord) -> Unit = {}
) {
    var searchQuery by remember { mutableStateOf("") }
    var expandedCategoryIds by remember(groupedCategories) {
        mutableStateOf(
            groupedCategories.take(2).map { it.id }.toSet()
        )
    }
    var showAllDetectedGrid by remember { mutableStateOf(true) }

    val selectedCount = allApps.count { it.packageName !in deselectedPackages }
    val allSelected = allApps.isNotEmpty() && selectedCount == allApps.size
    val queryTrimmed = searchQuery.trim().lowercase()
    val filteredApps = remember(allApps, queryTrimmed) {
        if (queryTrimmed.isEmpty()) allApps
        else allApps.filter {
            it.appName.lowercase().contains(queryTrimmed) ||
                it.packageName.lowercase().contains(queryTrimmed)
        }
    }

    // Blocco 1: Tutte le app rilevate automaticamente sul telefono
    Surface(
        shape = RoundedCornerShape(13.dp),
        color = DirectSwitchTheme.cardSurface,
        modifier = Modifier.fillMaxWidth()
    ) {
        Column(
            modifier = Modifier.padding(12.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp)
        ) {
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
                    if (isLoadingApps) {
                        CircularProgressIndicator(
                            modifier = Modifier.size(16.dp),
                            strokeWidth = 2.dp,
                            color = DirectSwitchTheme.blue
                        )
                    } else {
                        Icon(
                            imageVector = Icons.Filled.CheckCircle,
                            contentDescription = null,
                            tint = DirectSwitchTheme.green,
                            modifier = Modifier.size(18.dp)
                        )
                    }
                    Column {
                        Text(
                            text = DirectSwitchL10n.tr("App verificate su questo telefono ($selectedCount)", en = "Verified apps on this phone ($selectedCount)", fr = "Apps vérifiées sur ce téléphone ($selectedCount)"),
                            fontSize = 14.sp,
                            fontWeight = FontWeight.Bold,
                            color = DirectSwitchTheme.textPrimary
                        )
                        Text(
                            text = DirectSwitchL10n.tr("${allApps.size} app rilevate con icona e nome pronte al trasferimento", en = "${allApps.size} apps detected with icon and name ready to copy", fr = "${allApps.size} apps détectées prêtes à transférer"),
                            fontSize = 11.5.sp,
                            color = DirectSwitchTheme.textSecondary
                        )
                    }
                }
                Text(
                    text = DirectSwitchL10n.tr("Aggiorna"),
                    fontSize = 12.sp,
                    fontWeight = FontWeight.SemiBold,
                    color = DirectSwitchTheme.blue,
                    modifier = Modifier.clickable(enabled = !isLoadingApps, onClick = onRefreshApps)
                )
            }

            OutlinedTextField(
                value = searchQuery,
                onValueChange = { searchQuery = it },
                placeholder = { Text(DirectSwitchL10n.tr("Cerca tra le app installate...", en = "Search installed apps...", fr = "Rechercher dans les apps installées..."), fontSize = 13.sp) },
                leadingIcon = {
                    Icon(Icons.Filled.Search, contentDescription = null, tint = DirectSwitchTheme.textSecondary, modifier = Modifier.size(18.dp))
                },
                trailingIcon = {
                    if (searchQuery.isNotEmpty()) {
                        Icon(
                            Icons.Filled.Clear,
                            contentDescription = DirectSwitchL10n.tr("Cancella", en = "Clear", fr = "Effacer"),
                            tint = DirectSwitchTheme.textSecondary,
                            modifier = Modifier.size(18.dp).clickable { searchQuery = "" }
                        )
                    }
                },
                singleLine = true,
                shape = RoundedCornerShape(11.dp),
                modifier = Modifier.fillMaxWidth()
            )

            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.SpaceBetween
            ) {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(4.dp),
                    modifier = Modifier.clickable { showAllDetectedGrid = !showAllDetectedGrid }
                ) {
                    Text(
                        text = if (queryTrimmed.isNotEmpty()) DirectSwitchL10n.tr("Risultati (${filteredApps.size})", en = "Results (${filteredApps.size})", fr = "Résultats (${filteredApps.size})") else DirectSwitchL10n.tr("Tutte le app (${allApps.size})", en = "All apps (${allApps.size})", fr = "Toutes les apps (${allApps.size})"),
                        fontSize = 12.5.sp,
                        fontWeight = FontWeight.SemiBold,
                        color = DirectSwitchTheme.textPrimary
                    )
                    Icon(
                        imageVector = if (showAllDetectedGrid) Icons.Filled.ExpandLess else Icons.Filled.ExpandMore,
                        contentDescription = null,
                        tint = DirectSwitchTheme.textSecondary,
                        modifier = Modifier.size(18.dp)
                    )
                }

                if (allApps.isNotEmpty()) {
                    Surface(
                        onClick = { onToggleAllDetected(allSelected) },
                        shape = RoundedCornerShape(50),
                        color = DirectSwitchTheme.inputSurface,
                        border = BorderStroke(0.8.dp, DirectSwitchTheme.cardBorder)
                    ) {
                        Text(
                            text = if (allSelected) DirectSwitchL10n.tr("Deseleziona", en = "Deselect", fr = "Désélectionner") else DirectSwitchL10n.tr("Seleziona tutte", en = "Select all", fr = "Tout sélectionner"),
                            fontSize = 11.5.sp,
                            fontWeight = FontWeight.SemiBold,
                            color = if (allSelected) DirectSwitchTheme.orange else DirectSwitchTheme.textPrimary,
                            modifier = Modifier.padding(horizontal = 10.dp, vertical = 5.dp)
                        )
                    }
                }
            }

            if (showAllDetectedGrid || queryTrimmed.isNotEmpty()) {
                if (filteredApps.isEmpty()) {
                    Text(
                        text = if (isLoadingApps) DirectSwitchL10n.tr("Caricamento elenco app in corso...", en = "Loading app list...", fr = "Chargement des apps...") else DirectSwitchL10n.tr("Nessuna app corrispondente alla ricerca.", en = "No matching apps found.", fr = "Aucune app correspondante."),
                        fontSize = 12.sp,
                        color = DirectSwitchTheme.textSecondary
                    )
                } else {
                    AndroidAppFourColumnGrid(
                        apps = filteredApps,
                        deselectedPackages = deselectedPackages,
                        onToggleApp = onToggleApp
                    )
                }
            }
        }
    }

    // Blocco 2: Categorie estese in stile iPhone (icona + nome per ogni app, zero "+" blu)
    if (queryTrimmed.isEmpty() && groupedCategories.isNotEmpty()) {
        Text(
            text = DirectSwitchL10n.tr("Categorie estese stile iPhone", en = "Extended App Categories", fr = "Catégories d'apps étendues"),
            fontSize = 14.sp,
            fontWeight = FontWeight.Bold,
            color = DirectSwitchTheme.textPrimary
        )

        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            groupedCategories.forEach { category ->
                val isExpanded = category.id in expandedCategoryIds
                val catSelectedCount = category.apps.count { it.packageName !in deselectedPackages }
                val catAllSelected = category.apps.isNotEmpty() && catSelectedCount == category.apps.size

                Surface(
                    shape = RoundedCornerShape(14.dp),
                    color = DirectSwitchTheme.cardSurface,
                    border = BorderStroke(0.8.dp, DirectSwitchTheme.cardBorder),
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Column(
                        modifier = Modifier.padding(12.dp),
                        verticalArrangement = Arrangement.spacedBy(10.dp)
                    ) {
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(8.dp)
                        ) {
                            Row(
                                verticalAlignment = Alignment.CenterVertically,
                                horizontalArrangement = Arrangement.spacedBy(10.dp),
                                modifier = Modifier
                                    .weight(1f)
                                    .clickable {
                                        expandedCategoryIds = if (isExpanded) {
                                            expandedCategoryIds - category.id
                                        } else {
                                            expandedCategoryIds + category.id
                                        }
                                    }
                            ) {
                                AppleSettingsIcon(
                                    icon = categoryIconForId(category.id),
                                    color = DirectSwitchTheme.blue,
                                    size = 30.dp
                                )
                                Column(modifier = Modifier.weight(1f)) {
                                    Text(
                                        text = category.title,
                                        fontSize = 14.sp,
                                        fontWeight = FontWeight.Bold,
                                        color = DirectSwitchTheme.textPrimary,
                                        maxLines = 1,
                                        overflow = TextOverflow.Ellipsis
                                    )
                                    Text(
                                        text = if (catSelectedCount > 0) {
                                            DirectSwitchL10n.tr("$catSelectedCount di ${category.apps.size} selezionate", en = "$catSelectedCount of ${category.apps.size} selected", fr = "$catSelectedCount sur ${category.apps.size} sélectionnées")
                                        } else {
                                            DirectSwitchL10n.tr("${category.apps.size} app disponibili", en = "${category.apps.size} apps available", fr = "${category.apps.size} apps disponibles")
                                        },
                                        fontSize = 11.5.sp,
                                        color = if (catSelectedCount > 0) DirectSwitchTheme.green else DirectSwitchTheme.textSecondary
                                    )
                                }
                                Icon(
                                    imageVector = if (isExpanded) Icons.Filled.ExpandLess else Icons.Filled.ExpandMore,
                                    contentDescription = null,
                                    tint = DirectSwitchTheme.textSecondary,
                                    modifier = Modifier.size(18.dp)
                                )
                            }

                            Surface(
                                onClick = { onToggleCategoryAll(category, catAllSelected) },
                                shape = RoundedCornerShape(50),
                                color = if (catAllSelected) DirectSwitchTheme.orange.copy(alpha = 0.14f) else DirectSwitchTheme.inputSurface,
                                border = BorderStroke(
                                    0.8.dp,
                                    if (catAllSelected) DirectSwitchTheme.orange.copy(alpha = 0.35f) else DirectSwitchTheme.cardBorder
                                )
                            ) {
                                Text(
                                    text = if (catAllSelected) DirectSwitchL10n.tr("Togli", en = "Clear", fr = "Retirer") else DirectSwitchL10n.tr("Tutte", en = "All", fr = "Toutes"),
                                    fontSize = 12.sp,
                                    fontWeight = FontWeight.SemiBold,
                                    color = if (catAllSelected) DirectSwitchTheme.orange else DirectSwitchTheme.textPrimary,
                                    modifier = Modifier.padding(horizontal = 11.dp, vertical = 5.dp)
                                )
                            }
                        }

                        if (isExpanded) {
                            AndroidAppFourColumnGrid(
                                apps = category.apps,
                                deselectedPackages = deselectedPackages,
                                onToggleApp = onToggleApp
                            )
                        }
                    }
                }
            }
        }
    }

    if (extraCuratedCategories.isNotEmpty()) {
        val installedPkgs = remember(allApps) { allApps.map { it.packageName }.toSet() }
        ExtraCuratedAppsBrowser(
            curatedCategories = extraCuratedCategories,
            alreadyInCatalogPackages = installedPkgs,
            selectedExtraPackages = selectedExtraPackages,
            onToggleExtraApp = onToggleExtraApp
        )
    }
}

@Composable
private fun AndroidAppFourColumnGrid(
    apps: List<InstalledAppRecord>,
    deselectedPackages: Set<String>,
    onToggleApp: (InstalledAppRecord) -> Unit
) {
    val rows = remember(apps) { apps.chunked(4) }
    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        rows.forEach { rowApps ->
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                rowApps.forEach { app ->
                    val isSelected = app.packageName !in deselectedPackages
                    NativeAndroidAppGridTile(
                        app = app,
                        isSelected = isSelected,
                        onTap = { onToggleApp(app) },
                        modifier = Modifier.weight(1f)
                    )
                }
                repeat(4 - rowApps.size) {
                    Spacer(modifier = Modifier.weight(1f))
                }
            }
        }
    }
}

@Composable
private fun NativeAndroidAppGridTile(
    app: InstalledAppRecord,
    isSelected: Boolean,
    onTap: () -> Unit,
    modifier: Modifier = Modifier
) {
    Column(
        modifier = modifier
            .clip(RoundedCornerShape(12.dp))
            .clickable(onClick = onTap)
            .padding(vertical = 4.dp, horizontal = 2.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(6.dp)
    ) {
        Box(contentAlignment = Alignment.TopEnd) {
            AndroidAppIconView(
                packageName = app.packageName,
                size = 50.dp,
                isSelected = isSelected
            )
            if (isSelected) {
                Box(
                    modifier = Modifier
                        .offset(x = 4.dp, y = (-4).dp)
                        .size(18.dp)
                        .clip(CircleShape)
                        .background(Color.White),
                    contentAlignment = Alignment.Center
                ) {
                    Icon(
                        imageVector = Icons.Filled.CheckCircle,
                        contentDescription = "Selezionata",
                        tint = DirectSwitchTheme.green,
                        modifier = Modifier.size(16.dp)
                    )
                }
            }
        }
        Text(
            text = app.appName,
            fontSize = 11.sp,
            lineHeight = 13.sp,
            fontWeight = if (isSelected) FontWeight.SemiBold else FontWeight.Medium,
            color = DirectSwitchTheme.textPrimary,
            textAlign = TextAlign.Center,
            maxLines = 2,
            overflow = TextOverflow.Ellipsis,
            modifier = Modifier.fillMaxWidth()
        )
    }
}

@Composable
private fun AndroidAppIconView(
    packageName: String,
    size: Dp,
    isSelected: Boolean
) {
    val context = LocalContext.current
    var bitmap by remember(packageName) {
        mutableStateOf(AndroidAppIconBitmapCache.get(packageName))
    }

    LaunchedEffect(packageName) {
        if (bitmap == null) {
            val loaded = withContext(Dispatchers.IO) {
                runCatching {
                    context.packageManager.getApplicationIcon(packageName)
                        .toBitmap(width = 128, height = 128)
                        .asImageBitmap()
                }.getOrNull()
            }
            if (loaded != null) {
                AndroidAppIconBitmapCache.put(packageName, loaded)
                bitmap = loaded
            }
        }
    }

    val shape = RoundedCornerShape(12.dp)
    val borderColor = if (isSelected) DirectSwitchTheme.blue else DirectSwitchTheme.cardBorder
    val borderWidth = if (isSelected) 2.dp else 0.7.dp

    val img = bitmap
    if (img != null) {
        Image(
            bitmap = img,
            contentDescription = null,
            modifier = Modifier
                .size(size)
                .clip(shape)
                .border(borderWidth, borderColor, shape)
        )
    } else {
        Box(
            modifier = Modifier
                .size(size)
                .clip(shape)
                .background(DirectSwitchTheme.cardSelected)
                .border(borderWidth, borderColor, shape),
            contentAlignment = Alignment.Center
        ) {
            Icon(
                imageVector = Icons.Filled.Apps,
                contentDescription = null,
                tint = DirectSwitchTheme.blue,
                modifier = Modifier.size(size * 0.46f)
            )
        }
    }
}

@Composable
fun WhatsAppDropdownBody(isCrossOs: Boolean) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        Icon(
            imageVector = Icons.Filled.QrCode2,
            contentDescription = null,
            tint = DirectSwitchTheme.green,
            modifier = Modifier.size(18.dp)
        )
        Text(
            text = DirectSwitchL10n.tr("Passaggio guidato gratuito tramite Codice QR", en = "Free guided transfer via QR Code", fr = "Transfert guidé gratuit par Code QR"),
            fontSize = 13.sp,
            fontWeight = FontWeight.Bold,
            color = DirectSwitchTheme.textPrimary
        )
    }
    Text(
        text = if (isCrossOs) {
            DirectSwitchL10n.tr("Trasferisce cronologia chat, foto, video e messaggi vocali direttamente dentro WhatsApp verso iPhone senza formattare.", en = "Transfers chat history, photos, videos and voice notes inside WhatsApp to iPhone without resetting.", fr = "Transfère l'historique des chats, photos, vidéos et vocaux dans WhatsApp vers iPhone sans réinitialiser.")
        } else {
            DirectSwitchL10n.tr("Trasferisce tutta la cronologia chat, allegati e vocali direttamente tra due Android dentro WhatsApp tramite Codice QR.", en = "Transfers full chat history, attachments and voice notes directly between Android phones inside WhatsApp via QR Code.", fr = "Transfère tout l'historique des chats, pièces jointes et vocaux entre Android dans WhatsApp par Code QR.")
        },
        fontSize = 12.sp,
        color = DirectSwitchTheme.textSecondary
    )
}

private fun categoryIconForId(categoryId: String): ImageVector = when (categoryId) {
    "social_messaging" -> Icons.AutoMirrored.Filled.Chat
    "banks_payments" -> Icons.Filled.AccountBalance
    "spid_office", "work_cloud_mail" -> Icons.Filled.Badge
    "transport_travel" -> Icons.Filled.DirectionsTransit
    "shopping_food" -> Icons.Filled.ShoppingBag
    "music_streaming", "streaming_tv" -> Icons.Filled.MusicNote
    "photo_video_sport", "health_fitness" -> Icons.Filled.PhotoCamera
    "games_entertainment", "news_books", "utilities_security" -> Icons.Filled.Apps
    else -> Icons.Filled.Home
}

private fun formatBytesHuman(bytes: Long): String = TransferDisplayFormatting.formatBytes(bytes)
