//
//  DirectSwitchNextLevelViews.kt
//  DirectSwitch-Android
//
//  Created by Nicolas Donati.
//  Copyright © 2026 Nicolas Donati. Tutti i diritti riservati.
//

package com.directswitch.android.ui

import android.content.Intent
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowForward
import androidx.compose.material.icons.filled.AddCircleOutline
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Clear
import androidx.compose.material.icons.filled.Description
import androidx.compose.material.icons.filled.ExpandLess
import androidx.compose.material.icons.filled.ExpandMore
import androidx.compose.material.icons.filled.Folder
import androidx.compose.material.icons.filled.Language
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.RadioButtonUnchecked
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.Share
import androidx.compose.material.icons.filled.Storage
import androidx.compose.material.icons.filled.Usb
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material.icons.filled.Wifi
import androidx.compose.material.icons.filled.WifiTethering
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.directswitch.android.migrators.InstalledAppCategoryGroup
import com.directswitch.android.protocol.DirectSwitchLanguage
import com.directswitch.android.protocol.InstalledAppRecord
import com.directswitch.android.protocol.MediaTransferFilterOptions
import com.directswitch.android.protocol.PostMigrationChecklistItem
import com.directswitch.android.protocol.SkippedTransferItemRecord
import com.directswitch.android.protocol.SpaceReliefActionKind
import com.directswitch.android.protocol.SpaceReliefOffer
import com.directswitch.android.protocol.TransferCheckpointRecord
import com.directswitch.android.protocol.TransferConnectionMedium
import com.directswitch.android.protocol.TransferDisplayFormatting
import com.directswitch.android.ui.theme.AppleSettingsIcon
import com.directswitch.android.ui.theme.DirectSwitchPrimaryButton
import com.directswitch.android.ui.theme.DirectSwitchSecondaryButton
import com.directswitch.android.ui.theme.DirectSwitchTheme

// MARK: - Selettore Lingua (Sistema / IT / EN / ES / FR / DE)

@Composable
fun LanguageSelectorChip(
    currentLanguage: DirectSwitchLanguage,
    onSelectLanguage: (DirectSwitchLanguage) -> Unit
) {
    var expanded by remember { mutableStateOf(false) }

    Box {
        Surface(
            onClick = { expanded = true },
            shape = RoundedCornerShape(50),
            color = DirectSwitchTheme.cardSurface,
            border = BorderStroke(0.9.dp, DirectSwitchTheme.cardBorder)
        ) {
            Row(
                modifier = Modifier.padding(horizontal = 10.dp, vertical = 5.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(5.dp)
            ) {
                Icon(
                    imageVector = Icons.Filled.Language,
                    contentDescription = "Lingua",
                    tint = DirectSwitchTheme.blue,
                    modifier = Modifier.size(14.dp)
                )
                Text(
                    text = currentLanguage.shortCode,
                    fontSize = 12.sp,
                    fontWeight = FontWeight.Bold,
                    color = DirectSwitchTheme.blue
                )
            }
        }

        DropdownMenu(
            expanded = expanded,
            onDismissRequest = { expanded = false },
            containerColor = DirectSwitchTheme.cardSurface
        ) {
            DirectSwitchLanguage.entries.forEach { lang ->
                DropdownMenuItem(
                    text = {
                        Row(
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(8.dp)
                        ) {
                            Text(
                                text = lang.displayName,
                                fontWeight = if (lang == currentLanguage) FontWeight.Bold else FontWeight.Normal,
                                color = DirectSwitchTheme.textPrimary
                            )
                            if (lang == currentLanguage) {
                                Icon(
                                    imageVector = Icons.Filled.Check,
                                    contentDescription = null,
                                    tint = DirectSwitchTheme.blue,
                                    modifier = Modifier.size(16.dp)
                                )
                            }
                        }
                    },
                    onClick = {
                        expanded = false
                        onSelectLanguage(lang)
                    }
                )
            }
        }
    }
}

// MARK: - Card Ripresa Trasferimento Interrotto (Checkpoint su disco)

@Composable
fun ResumableCheckpointCard(
    checkpoint: TransferCheckpointRecord,
    onResume: () -> Unit,
    onDismiss: () -> Unit
) {
    Surface(
        shape = RoundedCornerShape(16.dp),
        color = DirectSwitchTheme.cardSurface,
        border = BorderStroke(1.1.dp, DirectSwitchTheme.orange.copy(alpha = 0.45f)),
        modifier = Modifier.fillMaxWidth()
    ) {
        Column(
            modifier = Modifier.padding(14.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(10.dp)
            ) {
                AppleSettingsIcon(icon = Icons.Filled.Refresh, color = DirectSwitchTheme.orange)
                Column(modifier = Modifier.weight(1f)) {
                    Text(
                        text = "Trasferimento interrotto (${checkpoint.completionPercent()}%)",
                        fontSize = 15.sp,
                        fontWeight = FontWeight.Bold,
                        color = DirectSwitchTheme.textPrimary
                    )
                    Text(
                        text = "Verso ${checkpoint.receiverName} • ${checkpoint.completedItemIds.size}/${maxOf(checkpoint.totalItems, checkpoint.completedItemIds.size)} file già salvati",
                        fontSize = 12.5.sp,
                        color = DirectSwitchTheme.textSecondary,
                        maxLines = 2,
                        overflow = TextOverflow.Ellipsis
                    )
                }
            }

            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(10.dp)
            ) {
                Surface(
                    onClick = onResume,
                    shape = RoundedCornerShape(11.dp),
                    color = DirectSwitchTheme.blue,
                    modifier = Modifier.weight(1f)
                ) {
                    Row(
                        modifier = Modifier.padding(vertical = 10.dp),
                        horizontalArrangement = Arrangement.Center,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Icon(Icons.Filled.PlayArrow, contentDescription = null, tint = Color.White, modifier = Modifier.size(16.dp))
                        Spacer(modifier = Modifier.size(4.dp))
                        Text("Riprendi ora", fontSize = 13.5.sp, fontWeight = FontWeight.Bold, color = Color.White)
                    }
                }

                Surface(
                    onClick = onDismiss,
                    shape = RoundedCornerShape(11.dp),
                    color = DirectSwitchTheme.inputSurface
                ) {
                    Text(
                        text = "Ignora",
                        fontSize = 13.5.sp,
                        fontWeight = FontWeight.SemiBold,
                        color = DirectSwitchTheme.textSecondary,
                        modifier = Modifier.padding(horizontal = 16.dp, vertical = 10.dp)
                    )
                }
            }
        }
    }
}

// MARK: - Pill Canale Connessione (USB-C / Wi-Fi P2P / Wi-Fi Locale)

@Composable
fun ConnectionMediumPill(medium: TransferConnectionMedium) {
    val (tint, icon) = when (medium) {
        TransferConnectionMedium.USB_CABLE -> DirectSwitchTheme.green to Icons.Filled.Usb
        TransferConnectionMedium.PEER_TO_PEER_WIFI -> DirectSwitchTheme.teal to Icons.Filled.WifiTethering
        TransferConnectionMedium.LOCAL_WIFI -> DirectSwitchTheme.blue to Icons.Filled.Wifi
    }
    Surface(
        shape = RoundedCornerShape(50),
        color = tint.copy(alpha = 0.12f)
    ) {
        Row(
            modifier = Modifier.padding(horizontal = 10.dp, vertical = 4.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(6.dp)
        ) {
            Icon(imageVector = icon, contentDescription = null, tint = tint, modifier = Modifier.size(14.dp))
            Text(
                text = medium.badgeLabel(),
                fontSize = 11.5.sp,
                fontWeight = FontWeight.SemiBold,
                color = tint
            )
        }
    }
}

// MARK: - Filtri Rapidi Foto e Video

@Composable
fun PhotoFilterChipsBar(
    filters: MediaTransferFilterOptions,
    availableAlbums: List<String>,
    onFiltersChange: (MediaTransferFilterOptions) -> Unit
) {
    var showAlbums by remember { mutableStateOf(false) }

    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text(
            text = "Filtri rapidi Foto",
            fontSize = 12.sp,
            fontWeight = FontWeight.Bold,
            color = DirectSwitchTheme.textSecondary
        )
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .horizontalScroll(rememberScrollState()),
            horizontalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            FilterPillChip(
                label = "Tutte le foto",
                selected = !filters.photosLastYearOnly && filters.selectedPhotoAlbums.isEmpty(),
                accentColor = DirectSwitchTheme.blue
            ) {
                onFiltersChange(filters.copy(photosLastYearOnly = false, selectedPhotoAlbums = emptyList()))
            }
            FilterPillChip(
                label = "Solo ultimo anno",
                selected = filters.photosLastYearOnly,
                accentColor = DirectSwitchTheme.blue
            ) {
                onFiltersChange(filters.copy(photosLastYearOnly = !filters.photosLastYearOnly))
            }
            if (availableAlbums.isNotEmpty()) {
                FilterPillChip(
                    label = if (filters.selectedPhotoAlbums.isEmpty()) {
                        "Scegli Album (${availableAlbums.size})"
                    } else {
                        "Album: ${filters.selectedPhotoAlbums.size} scelti"
                    },
                    selected = filters.selectedPhotoAlbums.isNotEmpty() || showAlbums,
                    accentColor = DirectSwitchTheme.orange
                ) {
                    showAlbums = !showAlbums
                }
            }
        }

        if (showAlbums && availableAlbums.isNotEmpty()) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .horizontalScroll(rememberScrollState()),
                horizontalArrangement = Arrangement.spacedBy(6.dp)
            ) {
                availableAlbums.forEach { album ->
                    val chosen = album in filters.selectedPhotoAlbums
                    Surface(
                        onClick = {
                            val next = if (chosen) {
                                filters.selectedPhotoAlbums - album
                            } else {
                                filters.selectedPhotoAlbums + album
                            }
                            onFiltersChange(filters.copy(selectedPhotoAlbums = next))
                        },
                        shape = RoundedCornerShape(50),
                        color = if (chosen) DirectSwitchTheme.orange else DirectSwitchTheme.cardSurface,
                        border = BorderStroke(0.8.dp, if (chosen) DirectSwitchTheme.orange else DirectSwitchTheme.cardBorder)
                    ) {
                        Row(
                            modifier = Modifier.padding(horizontal = 10.dp, vertical = 5.dp),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(4.dp)
                        ) {
                            Icon(
                                imageVector = if (chosen) Icons.Filled.CheckCircle else Icons.Filled.Folder,
                                contentDescription = null,
                                tint = if (chosen) Color.White else DirectSwitchTheme.textSecondary,
                                modifier = Modifier.size(13.dp)
                            )
                            Text(
                                text = album,
                                fontSize = 11.5.sp,
                                fontWeight = FontWeight.SemiBold,
                                color = if (chosen) Color.White else DirectSwitchTheme.textPrimary
                            )
                        }
                    }
                }
            }
        }
    }
}

@Composable
fun VideoFilterChipsBar(
    filters: MediaTransferFilterOptions,
    onFiltersChange: (MediaTransferFilterOptions) -> Unit
) {
    val halfGbBytes = 500L * 1024L * 1024L
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text(
            text = "Filtri rapidi Video",
            fontSize = 12.sp,
            fontWeight = FontWeight.Bold,
            color = DirectSwitchTheme.textSecondary
        )
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .horizontalScroll(rememberScrollState()),
            horizontalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            FilterPillChip(
                label = "Tutti i video",
                selected = !filters.videosLastYearOnly && filters.maxVideoBytes == 0L,
                accentColor = DirectSwitchTheme.red
            ) {
                onFiltersChange(filters.copy(videosLastYearOnly = false, maxVideoBytes = 0L))
            }
            FilterPillChip(
                label = "Solo ultimo anno",
                selected = filters.videosLastYearOnly,
                accentColor = DirectSwitchTheme.red
            ) {
                onFiltersChange(filters.copy(videosLastYearOnly = !filters.videosLastYearOnly))
            }
            FilterPillChip(
                label = "Solo ≤ 500 MB",
                selected = filters.maxVideoBytes == halfGbBytes,
                accentColor = DirectSwitchTheme.red
            ) {
                val nextLimit = if (filters.maxVideoBytes == halfGbBytes) 0L else halfGbBytes
                onFiltersChange(filters.copy(maxVideoBytes = nextLimit))
            }
        }
    }
}

@Composable
private fun FilterPillChip(
    label: String,
    selected: Boolean,
    accentColor: Color,
    onClick: () -> Unit
) {
    Surface(
        onClick = onClick,
        shape = RoundedCornerShape(50),
        color = if (selected) accentColor else DirectSwitchTheme.cardSurface,
        border = BorderStroke(0.8.dp, if (selected) accentColor else DirectSwitchTheme.cardBorder)
    ) {
        Text(
            text = label,
            fontSize = 12.sp,
            fontWeight = FontWeight.SemiBold,
            color = if (selected) Color.White else DirectSwitchTheme.textPrimary,
            modifier = Modifier.padding(horizontal = 11.dp, vertical = 6.dp)
        )
    }
}

// MARK: - Password CSV Guidato (con auto-distruzione sicura a zeri)

@Composable
fun GuidedPasswordsCard(
    stagedCsvCount: Int,
    onPickPasswordCsv: () -> Unit
) {
    Surface(
        shape = RoundedCornerShape(12.dp),
        color = DirectSwitchTheme.cardSurface,
        border = BorderStroke(0.9.dp, DirectSwitchTheme.orange.copy(alpha = 0.38f)),
        modifier = Modifier.fillMaxWidth()
    ) {
        Column(
            modifier = Modifier.padding(11.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Row(
                verticalAlignment = Alignment.Top,
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                Icon(
                    imageVector = Icons.Filled.Lock,
                    contentDescription = null,
                    tint = DirectSwitchTheme.orange,
                    modifier = Modifier.size(18.dp)
                )
                Column(modifier = Modifier.weight(1f)) {
                    Text(
                        text = if (stagedCsvCount > 0) {
                            "Password CSV pronto ($stagedCsvCount file) • Auto-cancellazione sicura"
                        } else {
                            "Trasferisci Password (Chrome / Gestore Password CSV)"
                        },
                        fontSize = 13.sp,
                        fontWeight = FontWeight.Bold,
                        color = DirectSwitchTheme.textPrimary
                    )
                    Text(
                        text = "Esporta il file .csv dal gestore password e allegalo qui: viaggia cifrato AES-256-GCM e la copia temporanea viene sovrascritta a zeri a fine trasferimento.",
                        fontSize = 11.5.sp,
                        color = DirectSwitchTheme.textSecondary
                    )
                }
            }
            DirectSwitchSecondaryButton(
                text = if (stagedCsvCount > 0) "Aggiungi altro file .csv Password" else "Seleziona file .csv Password",
                onClick = onPickPasswordCsv,
                tint = DirectSwitchTheme.orange
            )
        }
    }
}

// MARK: - Catalogo Extra App Popolari (oltre alle app installate rilevate)

@Composable
fun ExtraCuratedAppsBrowser(
    curatedCategories: List<InstalledAppCategoryGroup>,
    alreadyInCatalogPackages: Set<String>,
    selectedExtraPackages: Set<String>,
    onToggleExtraApp: (InstalledAppRecord) -> Unit
) {
    var searchQuery by remember { mutableStateOf("") }
    var expandedIds by remember { mutableStateOf(setOf<String>()) }
    val cleanQuery = searchQuery.trim().lowercase()

    val filteredCategories = remember(curatedCategories, cleanQuery, alreadyInCatalogPackages) {
        curatedCategories.mapNotNull { cat ->
            val available = cat.apps.filter { app ->
                app.packageName !in alreadyInCatalogPackages &&
                    (cleanQuery.isEmpty() ||
                        cat.title.lowercase().contains(cleanQuery) ||
                        app.appName.lowercase().contains(cleanQuery) ||
                        app.packageName.lowercase().contains(cleanQuery))
            }
            if (available.isEmpty()) null else cat.copy(apps = available)
        }
    }

    val totalCatalogCount = remember(curatedCategories) { curatedCategories.sumOf { it.apps.size } }

    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text(
                text = "Aggiungi altre app dal Catalogo Esteso",
                fontSize = 13.5.sp,
                fontWeight = FontWeight.Bold,
                color = DirectSwitchTheme.textPrimary
            )
            Text(
                text = "$totalCatalogCount app",
                fontSize = 11.5.sp,
                fontWeight = FontWeight.SemiBold,
                color = DirectSwitchTheme.blue
            )
        }

        OutlinedTextField(
            value = searchQuery,
            onValueChange = { searchQuery = it },
            placeholder = { Text("Cerca banche, social, streaming, AI, giochi...", fontSize = 12.5.sp) },
            leadingIcon = {
                Icon(Icons.Filled.Search, contentDescription = null, tint = DirectSwitchTheme.textSecondary, modifier = Modifier.size(18.dp))
            },
            trailingIcon = {
                if (searchQuery.isNotEmpty()) {
                    Icon(
                        Icons.Filled.Clear,
                        contentDescription = "Cancella",
                        tint = DirectSwitchTheme.textSecondary,
                        modifier = Modifier.size(18.dp).clickable { searchQuery = "" }
                    )
                }
            },
            singleLine = true,
            shape = RoundedCornerShape(11.dp),
            modifier = Modifier.fillMaxWidth()
        )

        filteredCategories.forEach { cat ->
            val isExpanded = cleanQuery.isNotEmpty() || cat.id in expandedIds
            val chosenInCat = cat.apps.count { it.packageName in selectedExtraPackages }
            Surface(
                shape = RoundedCornerShape(12.dp),
                color = DirectSwitchTheme.cardSurface,
                border = BorderStroke(0.8.dp, DirectSwitchTheme.cardBorder),
                modifier = Modifier.fillMaxWidth()
            ) {
                Column(modifier = Modifier.padding(10.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .clickable {
                                expandedIds = if (cat.id in expandedIds) expandedIds - cat.id else expandedIds + cat.id
                            },
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.SpaceBetween
                    ) {
                        Column(modifier = Modifier.weight(1f)) {
                            Text(
                                text = cat.title,
                                fontSize = 13.sp,
                                fontWeight = FontWeight.Bold,
                                color = DirectSwitchTheme.textPrimary
                            )
                            Text(
                                text = if (chosenInCat > 0) "$chosenInCat aggiunte • ${cat.apps.size} disponibili" else "${cat.apps.size} app pronte da aggiungere",
                                fontSize = 11.5.sp,
                                color = if (chosenInCat > 0) DirectSwitchTheme.green else DirectSwitchTheme.textSecondary
                            )
                        }
                        Icon(
                            imageVector = if (isExpanded) Icons.Filled.ExpandLess else Icons.Filled.ExpandMore,
                            contentDescription = null,
                            tint = DirectSwitchTheme.textSecondary,
                            modifier = Modifier.size(18.dp)
                        )
                    }

                    if (isExpanded) {
                        Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                            cat.apps.chunked(2).forEach { pair ->
                                Row(
                                    modifier = Modifier.fillMaxWidth(),
                                    horizontalArrangement = Arrangement.spacedBy(6.dp)
                                ) {
                                    pair.forEach { app ->
                                        val selected = app.packageName in selectedExtraPackages
                                        Surface(
                                            onClick = { onToggleExtraApp(app) },
                                            shape = RoundedCornerShape(10.dp),
                                            color = if (selected) DirectSwitchTheme.cardSelected else DirectSwitchTheme.inputSurface.copy(alpha = 0.7f),
                                            border = BorderStroke(0.8.dp, if (selected) DirectSwitchTheme.blue else DirectSwitchTheme.cardBorder),
                                            modifier = Modifier.weight(1f)
                                        ) {
                                            Row(
                                                modifier = Modifier.padding(horizontal = 9.dp, vertical = 8.dp),
                                                verticalAlignment = Alignment.CenterVertically,
                                                horizontalArrangement = Arrangement.spacedBy(6.dp)
                                            ) {
                                                Icon(
                                                    imageVector = if (selected) Icons.Filled.CheckCircle else Icons.Filled.AddCircleOutline,
                                                    contentDescription = null,
                                                    tint = if (selected) DirectSwitchTheme.green else DirectSwitchTheme.blue,
                                                    modifier = Modifier.size(16.dp)
                                                )
                                                Text(
                                                    text = app.appName,
                                                    fontSize = 12.sp,
                                                    fontWeight = if (selected) FontWeight.Bold else FontWeight.Medium,
                                                    color = DirectSwitchTheme.textPrimary,
                                                    maxLines = 1,
                                                    overflow = TextOverflow.Ellipsis,
                                                    modifier = Modifier.weight(1f)
                                                )
                                            }
                                        }
                                    }
                                    if (pair.size == 1) {
                                        Spacer(modifier = Modifier.weight(1f))
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Assistente Salva-Spazio

@Composable
fun SpaceReliefAssistantCard(
    offer: SpaceReliefOffer,
    onSelectAction: (SpaceReliefActionKind) -> Unit
) {
    Surface(
        shape = RoundedCornerShape(16.dp),
        color = DirectSwitchTheme.cardSurface,
        border = BorderStroke(1.2.dp, DirectSwitchTheme.orange.copy(alpha = 0.5f)),
        modifier = Modifier.fillMaxWidth()
    ) {
        Column(
            modifier = Modifier.padding(14.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(10.dp)
            ) {
                AppleSettingsIcon(icon = Icons.Filled.Storage, color = DirectSwitchTheme.orange)
                Column(modifier = Modifier.weight(1f)) {
                    Text(
                        text = "Assistente Salva-Spazio",
                        fontSize = 16.sp,
                        fontWeight = FontWeight.Bold,
                        color = DirectSwitchTheme.textPrimary
                    )
                    Text(
                        text = "Su ${offer.receiverName} mancano circa ${TransferDisplayFormatting.formatBytes(offer.shortfallBytes)} per copiare tutto.",
                        fontSize = 12.5.sp,
                        color = DirectSwitchTheme.textSecondary
                    )
                }
            }

            Text(
                text = "Scegli una soluzione rapida con 1 tocco per ripartire subito:",
                fontSize = 12.5.sp,
                fontWeight = FontWeight.SemiBold,
                color = DirectSwitchTheme.textPrimary
            )

            offer.options.forEach { opt ->
                Surface(
                    onClick = { onSelectAction(opt.kind) },
                    shape = RoundedCornerShape(12.dp),
                    color = DirectSwitchTheme.inputSurface,
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Row(
                        modifier = Modifier.padding(12.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.SpaceBetween
                    ) {
                        Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                            Row(
                                verticalAlignment = Alignment.CenterVertically,
                                horizontalArrangement = Arrangement.spacedBy(6.dp)
                            ) {
                                Text(
                                    text = opt.title,
                                    fontSize = 13.5.sp,
                                    fontWeight = FontWeight.Bold,
                                    color = DirectSwitchTheme.textPrimary
                                )
                                if (opt.fitsAvailableSpace) {
                                    Text(
                                        text = "Rientra ✓",
                                        fontSize = 10.5.sp,
                                        fontWeight = FontWeight.Bold,
                                        color = DirectSwitchTheme.green
                                    )
                                }
                            }
                            Text(
                                text = opt.subtitle,
                                fontSize = 12.sp,
                                color = DirectSwitchTheme.textSecondary
                            )
                        }
                        Icon(
                            imageVector = Icons.AutoMirrored.Filled.ArrowForward,
                            contentDescription = null,
                            tint = DirectSwitchTheme.blue,
                            modifier = Modifier.size(18.dp)
                        )
                    }
                }
            }
        }
    }
}

// MARK: - Report Interattivo Elementi Saltati + "Riprova solo i mancanti"

@Composable
fun SkippedItemsReportCard(
    items: List<SkippedTransferItemRecord>,
    canRetry: Boolean,
    onRetrySkippedOnly: () -> Unit
) {
    var expanded by remember { mutableStateOf(false) }

    Surface(
        shape = RoundedCornerShape(16.dp),
        color = DirectSwitchTheme.cardSurface,
        border = BorderStroke(1.dp, DirectSwitchTheme.orange.copy(alpha = 0.45f)),
        modifier = Modifier.fillMaxWidth()
    ) {
        Column(
            modifier = Modifier.padding(14.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .clickable { expanded = !expanded },
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.SpaceBetween
            ) {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(10.dp),
                    modifier = Modifier.weight(1f)
                ) {
                    AppleSettingsIcon(icon = Icons.Filled.Warning, color = DirectSwitchTheme.orange)
                    Column {
                        Text(
                            text = "${items.size} ${if (items.size == 1) "file saltato" else "file saltati"}",
                            fontSize = 15.sp,
                            fontWeight = FontWeight.Bold,
                            color = DirectSwitchTheme.textPrimary
                        )
                        Text(
                            text = "Tocca per vedere i dettagli e riprovare solo i mancanti",
                            fontSize = 12.sp,
                            color = DirectSwitchTheme.textSecondary
                        )
                    }
                }
                Icon(
                    imageVector = if (expanded) Icons.Filled.ExpandLess else Icons.Filled.ExpandMore,
                    contentDescription = null,
                    tint = DirectSwitchTheme.textMuted
                )
            }

            if (expanded) {
                Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    items.take(25).forEach { rec ->
                        Column(
                            modifier = Modifier
                                .fillMaxWidth()
                                .clip(RoundedCornerShape(8.dp))
                                .background(DirectSwitchTheme.inputSurface)
                                .padding(8.dp),
                            verticalArrangement = Arrangement.spacedBy(2.dp)
                        ) {
                            Row(
                                modifier = Modifier.fillMaxWidth(),
                                horizontalArrangement = Arrangement.SpaceBetween
                            ) {
                                Text(
                                    text = rec.fileName,
                                    fontSize = 12.5.sp,
                                    fontWeight = FontWeight.SemiBold,
                                    color = DirectSwitchTheme.textPrimary,
                                    maxLines = 1,
                                    overflow = TextOverflow.Ellipsis,
                                    modifier = Modifier.weight(1f)
                                )
                                if (rec.sizeBytes > 0L) {
                                    Text(
                                        text = TransferDisplayFormatting.formatBytes(rec.sizeBytes),
                                        fontSize = 11.sp,
                                        color = DirectSwitchTheme.textMuted
                                    )
                                }
                            }
                            Text(
                                text = rec.reason,
                                fontSize = 11.5.sp,
                                color = DirectSwitchTheme.orange
                            )
                        }
                    }
                    if (items.size > 25) {
                        Text(
                            text = "…e altri ${items.size - 25} elementi",
                            fontSize = 11.5.sp,
                            color = DirectSwitchTheme.textSecondary
                        )
                    }
                }
            }

            if (canRetry) {
                DirectSwitchSecondaryButton(
                    text = "Riprova solo questi ${items.size} file",
                    onClick = onRetrySkippedOnly,
                    tint = DirectSwitchTheme.orange
                )
            }
        }
    }
}

// MARK: - Checklist Post-Migrazione + Ricevuta Condivisibile

@Composable
fun PostMigrationChecklistCard(
    items: List<PostMigrationChecklistItem>,
    receiptText: String
) {
    val context = LocalContext.current
    var checkedIds by remember { mutableStateOf(setOf<String>()) }
    var expanded by remember { mutableStateOf(true) }

    Surface(
        shape = RoundedCornerShape(16.dp),
        color = DirectSwitchTheme.cardSurface,
        border = BorderStroke(0.9.dp, DirectSwitchTheme.cardBorder),
        modifier = Modifier.fillMaxWidth()
    ) {
        Column(
            modifier = Modifier.padding(14.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .clickable { expanded = !expanded },
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.SpaceBetween
            ) {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(10.dp),
                    modifier = Modifier.weight(1f)
                ) {
                    AppleSettingsIcon(icon = Icons.Filled.Description, color = DirectSwitchTheme.green)
                    Column {
                        Text(
                            text = "Checklist finale prima di chiudere",
                            fontSize = 15.sp,
                            fontWeight = FontWeight.Bold,
                            color = DirectSwitchTheme.textPrimary
                        )
                        Text(
                            text = "${checkedIds.size}/${items.size} passaggi verificati",
                            fontSize = 12.sp,
                            color = DirectSwitchTheme.textSecondary
                        )
                    }
                }
                Icon(
                    imageVector = if (expanded) Icons.Filled.ExpandLess else Icons.Filled.ExpandMore,
                    contentDescription = null,
                    tint = DirectSwitchTheme.textMuted
                )
            }

            if (expanded) {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    items.forEach { item ->
                        val checked = item.id in checkedIds
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .clip(RoundedCornerShape(11.dp))
                                .background(DirectSwitchTheme.inputSurface.copy(alpha = if (checked) 0.45f else 0.85f))
                                .clickable {
                                    checkedIds = if (checked) checkedIds - item.id else checkedIds + item.id
                                }
                                .padding(10.dp),
                            verticalAlignment = Alignment.Top,
                            horizontalArrangement = Arrangement.spacedBy(10.dp)
                        ) {
                            Icon(
                                imageVector = if (checked) Icons.Filled.CheckCircle else Icons.Filled.RadioButtonUnchecked,
                                contentDescription = null,
                                tint = if (checked) DirectSwitchTheme.green else DirectSwitchTheme.textMuted,
                                modifier = Modifier.size(20.dp)
                            )
                            Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                                Text(
                                    text = item.title,
                                    fontSize = 13.5.sp,
                                    fontWeight = FontWeight.SemiBold,
                                    color = if (checked) DirectSwitchTheme.textSecondary else DirectSwitchTheme.textPrimary,
                                    textDecoration = if (checked) TextDecoration.LineThrough else TextDecoration.None
                                )
                                Text(
                                    text = item.subtitle,
                                    fontSize = 11.5.sp,
                                    color = DirectSwitchTheme.textSecondary
                                )
                            }
                        }
                    }
                }
            }

            Surface(
                onClick = {
                    val shareIntent = Intent(Intent.ACTION_SEND).apply {
                        type = "text/plain"
                        putExtra(Intent.EXTRA_SUBJECT, "DirectSwitch — Ricevuta di Migrazione")
                        putExtra(Intent.EXTRA_TEXT, receiptText)
                    }
                    runCatching {
                        context.startActivity(Intent.createChooser(shareIntent, "Condividi ricevuta migrazione"))
                    }
                },
                shape = RoundedCornerShape(12.dp),
                color = DirectSwitchTheme.blue.copy(alpha = 0.12f),
                modifier = Modifier.fillMaxWidth()
            ) {
                Row(
                    modifier = Modifier.padding(vertical = 12.dp),
                    horizontalArrangement = Arrangement.Center,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Icon(Icons.Filled.Share, contentDescription = null, tint = DirectSwitchTheme.blue, modifier = Modifier.size(16.dp))
                    Spacer(modifier = Modifier.size(8.dp))
                    Text(
                        text = "Condividi ricevuta migrazione",
                        fontSize = 14.sp,
                        fontWeight = FontWeight.SemiBold,
                        color = DirectSwitchTheme.blue
                    )
                }
            }
        }
    }
}
