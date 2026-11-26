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
import androidx.compose.material.icons.filled.BatteryAlert
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Clear
import androidx.compose.material.icons.filled.CloudUpload
import androidx.compose.material.icons.filled.Description
import androidx.compose.material.icons.filled.ExpandLess
import androidx.compose.material.icons.filled.ExpandMore
import androidx.compose.material.icons.filled.Folder
import androidx.compose.material.icons.filled.History
import androidx.compose.material.icons.filled.Language
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.RadioButtonUnchecked
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.SettingsBackupRestore
import androidx.compose.material.icons.filled.Share
import androidx.compose.material.icons.filled.Shield
import androidx.compose.material.icons.filled.Storage
import androidx.compose.material.icons.filled.Usb
import androidx.compose.material.icons.filled.VerifiedUser
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material.icons.filled.Wifi
import androidx.compose.material.icons.filled.WifiTethering
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
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
import com.directswitch.android.migrators.BatterySnapshot
import com.directswitch.android.migrators.InstalledAppCategoryGroup
import com.directswitch.android.protocol.CompletedMigrationRecord
import com.directswitch.android.protocol.DirectSwitchL10n
import com.directswitch.android.protocol.DirectSwitchLanguage
import com.directswitch.android.protocol.InstalledAppRecord
import com.directswitch.android.protocol.MediaTransferFilterOptions
import com.directswitch.android.protocol.NetworkDiagnosticVerdict
import com.directswitch.android.protocol.SkippedTransferItemRecord
import com.directswitch.android.protocol.SmartCleanOptions
import com.directswitch.android.protocol.SpaceReliefActionKind
import com.directswitch.android.protocol.SpaceReliefOffer
import com.directswitch.android.protocol.ThermalGuardState
import com.directswitch.android.protocol.TransferCheckpointRecord
import com.directswitch.android.protocol.TransferConnectionMedium
import com.directswitch.android.protocol.TransferDisplayFormatting
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import com.directswitch.android.ui.theme.AppleSettingsIcon
import com.directswitch.android.ui.theme.DirectSwitchPrimaryButton
import com.directswitch.android.ui.theme.DirectSwitchSecondaryButton
import com.directswitch.android.ui.theme.DirectSwitchTheme

// MARK: - Selettore Lingua (Sistema / IT / EN / FR)

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
                    contentDescription = DirectSwitchL10n.tr("Lingua", en = "Language", fr = "Langue"),
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
                        text = DirectSwitchL10n.tr(
                            "Trasferimento interrotto (${checkpoint.completionPercent()}%)",
                            en = "Interrupted transfer (${checkpoint.completionPercent()}%)",
                            fr = "Transfert interrompu (${checkpoint.completionPercent()}%)"
                        ),
                        fontSize = 15.sp,
                        fontWeight = FontWeight.Bold,
                        color = DirectSwitchTheme.textPrimary
                    )
                    Text(
                        text = DirectSwitchL10n.tr(
                            "Verso ${checkpoint.receiverName} • ${checkpoint.completedItemIds.size}/${maxOf(checkpoint.totalItems, checkpoint.completedItemIds.size)} file già salvati",
                            en = "To ${checkpoint.receiverName} • ${checkpoint.completedItemIds.size}/${maxOf(checkpoint.totalItems, checkpoint.completedItemIds.size)} files already saved",
                            fr = "Vers ${checkpoint.receiverName} • ${checkpoint.completedItemIds.size}/${maxOf(checkpoint.totalItems, checkpoint.completedItemIds.size)} fichiers déjà enregistrés"
                        ),
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
                        Text(DirectSwitchL10n.tr("Riprendi ora"), fontSize = 13.5.sp, fontWeight = FontWeight.Bold, color = Color.White)
                    }
                }

                Surface(
                    onClick = onDismiss,
                    shape = RoundedCornerShape(11.dp),
                    color = DirectSwitchTheme.inputSurface
                ) {
                    Text(
                        text = DirectSwitchL10n.tr("Ignora"),
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
                text = DirectSwitchL10n.tr(medium.badgeLabel()),
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
            text = DirectSwitchL10n.tr("Filtri rapidi Foto"),
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
                label = DirectSwitchL10n.tr("Tutte le foto"),
                selected = !filters.photosLastYearOnly && filters.selectedPhotoAlbums.isEmpty(),
                accentColor = DirectSwitchTheme.blue
            ) {
                onFiltersChange(filters.copy(photosLastYearOnly = false, selectedPhotoAlbums = emptyList()))
            }
            FilterPillChip(
                label = DirectSwitchL10n.tr("Solo ultimo anno"),
                selected = filters.photosLastYearOnly,
                accentColor = DirectSwitchTheme.blue
            ) {
                onFiltersChange(filters.copy(photosLastYearOnly = !filters.photosLastYearOnly))
            }
            if (availableAlbums.isNotEmpty()) {
                FilterPillChip(
                    label = if (filters.selectedPhotoAlbums.isEmpty()) {
                        DirectSwitchL10n.tr("Scegli Album (${availableAlbums.size})", en = "Choose Albums (${availableAlbums.size})", fr = "Choisir albums (${availableAlbums.size})")
                    } else {
                        DirectSwitchL10n.tr("Album: ${filters.selectedPhotoAlbums.size} scelti", en = "Albums: ${filters.selectedPhotoAlbums.size} picked", fr = "Albums : ${filters.selectedPhotoAlbums.size} choisis")
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
            text = DirectSwitchL10n.tr("Filtri rapidi Video", en = "Quick Video Filters", fr = "Filtres rapides Vidéo"),
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
                label = DirectSwitchL10n.tr("Tutti i video"),
                selected = !filters.videosLastYearOnly && filters.maxVideoBytes == 0L,
                accentColor = DirectSwitchTheme.red
            ) {
                onFiltersChange(filters.copy(videosLastYearOnly = false, maxVideoBytes = 0L))
            }
            FilterPillChip(
                label = DirectSwitchL10n.tr("Solo ultimo anno"),
                selected = filters.videosLastYearOnly,
                accentColor = DirectSwitchTheme.red
            ) {
                onFiltersChange(filters.copy(videosLastYearOnly = !filters.videosLastYearOnly))
            }
            FilterPillChip(
                label = DirectSwitchL10n.tr("Solo ≤ 500 MB"),
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
                            DirectSwitchL10n.tr(
                                "Password CSV pronto ($stagedCsvCount file) • Auto-cancellazione sicura",
                                en = "Password CSV ready ($stagedCsvCount file) • Secure auto-wipe",
                                fr = "CSV Mots de passe prêt ($stagedCsvCount) • Effacement sécurisé"
                            )
                        } else {
                            DirectSwitchL10n.tr(
                                "Trasferisci Password (Chrome / Gestore Password CSV)",
                                en = "Transfer Passwords (Chrome / Password Manager CSV)",
                                fr = "Transférer les mots de passe (CSV Chrome / Gestionnaire)"
                            )
                        },
                        fontSize = 13.sp,
                        fontWeight = FontWeight.Bold,
                        color = DirectSwitchTheme.textPrimary
                    )
                    Text(
                        text = DirectSwitchL10n.tr(
                            "Esporta il file .csv dal gestore password e allegalo qui: viaggia cifrato AES-256-GCM e la copia temporanea viene sovrascritta a zeri a fine trasferimento.",
                            en = "Export your .csv file from your password manager and attach it here: sent with AES-256-GCM encryption and zero-wiped afterwards.",
                            fr = "Exportez le fichier .csv depuis votre gestionnaire de mots de passe : chiffré AES-256-GCM et effacé à zéro après transfert."
                        ),
                        fontSize = 11.5.sp,
                        color = DirectSwitchTheme.textSecondary
                    )
                }
            }
            DirectSwitchSecondaryButton(
                text = if (stagedCsvCount > 0) DirectSwitchL10n.tr("Aggiungi altro file .csv Password", en = "Add another Password .csv", fr = "Ajouter un autre CSV") else DirectSwitchL10n.tr("Seleziona file .csv Password", en = "Select Password .csv file", fr = "Sélectionner un fichier .csv"),
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
                text = DirectSwitchL10n.tr("Aggiungi altre app dal Catalogo Esteso", en = "Add more apps from Extended Catalog", fr = "Ajouter des apps du catalogue étendu"),
                fontSize = 13.5.sp,
                fontWeight = FontWeight.Bold,
                color = DirectSwitchTheme.textPrimary
            )
            Text(
                text = DirectSwitchL10n.tr("$totalCatalogCount app", en = "$totalCatalogCount apps", fr = "$totalCatalogCount apps"),
                fontSize = 11.5.sp,
                fontWeight = FontWeight.SemiBold,
                color = DirectSwitchTheme.blue
            )
        }

        OutlinedTextField(
            value = searchQuery,
            onValueChange = { searchQuery = it },
            placeholder = { Text(DirectSwitchL10n.tr("Cerca banche, social, streaming, AI, giochi...", en = "Search banks, social, streaming, AI, games...", fr = "Rechercher banques, social, streaming, jeux..."), fontSize = 12.5.sp) },
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
                                text = if (chosenInCat > 0) DirectSwitchL10n.tr("$chosenInCat aggiunte • ${cat.apps.size} disponibili", en = "$chosenInCat added • ${cat.apps.size} available", fr = "$chosenInCat ajoutées • ${cat.apps.size} disponibles") else DirectSwitchL10n.tr("${cat.apps.size} app pronte da aggiungere", en = "${cat.apps.size} apps ready to add", fr = "${cat.apps.size} apps prêtes à ajouter"),
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
                        text = DirectSwitchL10n.tr("Assistente Salva-Spazio"),
                        fontSize = 16.sp,
                        fontWeight = FontWeight.Bold,
                        color = DirectSwitchTheme.textPrimary
                    )
                    Text(
                        text = DirectSwitchL10n.tr(
                            "Su ${offer.receiverName} mancano circa ${TransferDisplayFormatting.formatBytes(offer.shortfallBytes)} per copiare tutto.",
                            en = "${offer.receiverName} needs about ${TransferDisplayFormatting.formatBytes(offer.shortfallBytes)} more free space to copy everything.",
                            fr = "Il manque environ ${TransferDisplayFormatting.formatBytes(offer.shortfallBytes)} sur ${offer.receiverName} pour tout copier."
                        ),
                        fontSize = 12.5.sp,
                        color = DirectSwitchTheme.textSecondary
                    )
                }
            }

            Text(
                text = DirectSwitchL10n.tr("Scegli una soluzione rapida con 1 tocco per ripartire subito:", en = "Pick a 1-tap quick option to restart right away:", fr = "Choisissez une solution rapide en 1 geste pour repartir :"),
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
                                    text = DirectSwitchL10n.tr(opt.title),
                                    fontSize = 13.5.sp,
                                    fontWeight = FontWeight.Bold,
                                    color = DirectSwitchTheme.textPrimary
                                )
                                if (opt.fitsAvailableSpace) {
                                    Text(
                                        text = DirectSwitchL10n.tr("Rientra ✓", en = "Fits ✓", fr = "Compatible ✓"),
                                        fontSize = 10.5.sp,
                                        fontWeight = FontWeight.Bold,
                                        color = DirectSwitchTheme.green
                                    )
                                }
                            }
                            Text(
                                text = DirectSwitchL10n.tr(opt.subtitle),
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
                            text = if (items.size == 1) DirectSwitchL10n.tr("1 file saltato", en = "1 skipped file", fr = "1 fichier ignoré") else DirectSwitchL10n.tr("${items.size} file saltati", en = "${items.size} skipped files", fr = "${items.size} fichiers ignorés"),
                            fontSize = 15.sp,
                            fontWeight = FontWeight.Bold,
                            color = DirectSwitchTheme.textPrimary
                        )
                        Text(
                            text = DirectSwitchL10n.tr("Tocca per vedere i dettagli e riprovare solo i mancanti", en = "Tap to inspect details and retry only missing items", fr = "Touchez pour voir les détails et réessayer les manquants"),
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
                            text = DirectSwitchL10n.tr("…e altri ${items.size - 25} elementi", en = "…and ${items.size - 25} more items", fr = "…et ${items.size - 25} autres éléments"),
                            fontSize = 11.5.sp,
                            color = DirectSwitchTheme.textSecondary
                        )
                    }
                }
            }

            if (canRetry) {
                DirectSwitchSecondaryButton(
                    text = DirectSwitchL10n.tr("Riprova solo questi ${items.size} file", en = "Retry only these ${items.size} files", fr = "Réessayer ces ${items.size} fichiers"),
                    onClick = onRetrySkippedOnly,
                    tint = DirectSwitchTheme.orange
                )
            }
        }
    }
}

// MARK: - Recupero Delta 14-30 Giorni ("Copia solo le novità")

@Composable
fun DeltaCatchUpCard(
    record: CompletedMigrationRecord,
    onStartDeltaSync: () -> Unit,
    onDismiss: () -> Unit
) {
    val activeLocale = remember(DirectSwitchL10n.activeLanguage) {
        when (DirectSwitchL10n.effectiveCode()) {
            "en" -> Locale.ENGLISH
            "fr" -> Locale.FRENCH
            else -> Locale.ITALY
        }
    }
    val dateStr = remember(record.completedAtEpochMillis, activeLocale) {
        SimpleDateFormat("dd/MM HH:mm", activeLocale).format(Date(record.completedAtEpochMillis))
    }
    val daysAgo = record.daysSinceCompleted()
    Surface(
        shape = RoundedCornerShape(16.dp),
        color = DirectSwitchTheme.cardSurface,
        border = BorderStroke(1.1.dp, DirectSwitchTheme.teal.copy(alpha = 0.45f)),
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
                AppleSettingsIcon(icon = Icons.Filled.History, color = DirectSwitchTheme.teal)
                Column(modifier = Modifier.weight(1f)) {
                    Text(
                        text = DirectSwitchL10n.tr("Recupero Delta — Solo novità dal $dateStr", en = "Delta Catch-Up — New items since $dateStr", fr = "Rattrapage Delta — Nouveautés depuis $dateStr"),
                        fontSize = 14.5.sp,
                        fontWeight = FontWeight.Bold,
                        color = DirectSwitchTheme.textPrimary
                    )
                    Text(
                        text = if (daysAgo == 0) {
                            DirectSwitchL10n.tr("Già migrato verso ${record.peerName} (oggi). Copia solo foto, SMS, chiamate e file nuovi.", en = "Already migrated to ${record.peerName} (today). Copy only new photos, SMS, calls and files.", fr = "Déjà migré vers ${record.peerName} (aujourd'hui). Copiez uniquement les nouveautés.")
                        } else {
                            DirectSwitchL10n.tr("Già migrato verso ${record.peerName} ($daysAgo gg fa). Copia solo foto, SMS, chiamate e file nuovi.", en = "Already migrated to ${record.peerName} (${daysAgo}d ago). Copy only new photos, SMS, calls and files.", fr = "Déjà migré vers ${record.peerName} (il y a $daysAgo j). Copiez uniquement les nouveautés.")
                        },
                        fontSize = 12.sp,
                        color = DirectSwitchTheme.textSecondary
                    )
                }
            }
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(10.dp)
            ) {
                Surface(
                    onClick = onStartDeltaSync,
                    shape = RoundedCornerShape(11.dp),
                    color = DirectSwitchTheme.teal,
                    modifier = Modifier.weight(1f)
                ) {
                    Row(
                        modifier = Modifier.padding(vertical = 10.dp),
                        horizontalArrangement = Arrangement.Center,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Icon(Icons.Filled.PlayArrow, contentDescription = null, tint = Color.White, modifier = Modifier.size(16.dp))
                        Spacer(modifier = Modifier.size(4.dp))
                        Text(DirectSwitchL10n.tr("Copia solo novità"), fontSize = 13.5.sp, fontWeight = FontWeight.Bold, color = Color.White)
                    }
                }
                Surface(
                    onClick = onDismiss,
                    shape = RoundedCornerShape(11.dp),
                    color = DirectSwitchTheme.inputSurface
                ) {
                    Text(
                        text = DirectSwitchL10n.tr("Chiudi"),
                        fontSize = 13.sp,
                        fontWeight = FontWeight.SemiBold,
                        color = DirectSwitchTheme.textSecondary,
                        modifier = Modifier.padding(horizontal = 14.dp, vertical = 10.dp)
                    )
                }
            }
        }
    }
}

// MARK: - Triage Batteria Critica

@Composable
fun BatteryTriageToggleCard(
    battery: BatterySnapshot,
    enabled: Boolean,
    onToggle: (Boolean) -> Unit
) {
    val accent = if (battery.recommendsAutoTriage || enabled) DirectSwitchTheme.orange else DirectSwitchTheme.blue
    Surface(
        shape = RoundedCornerShape(14.dp),
        color = DirectSwitchTheme.cardSurface,
        border = BorderStroke(0.9.dp, accent.copy(alpha = if (enabled || battery.recommendsAutoTriage) 0.5f else 0.25f)),
        modifier = Modifier.fillMaxWidth()
    ) {
        Row(
            modifier = Modifier.padding(horizontal = 12.dp, vertical = 10.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            Icon(
                imageVector = Icons.Filled.BatteryAlert,
                contentDescription = null,
                tint = accent,
                modifier = Modifier.size(22.dp)
            )
            Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text(
                    text = if (battery.recommendsAutoTriage) {
                        DirectSwitchL10n.tr("Triage Batteria Critica attivo (${battery.percent}%)", en = "Critical Battery Triage active (${battery.percent}%)", fr = "Triage Batterie Critique actif (${battery.percent}%)")
                    } else {
                        DirectSwitchL10n.tr("Modalità Triage Batteria (${battery.percent}%)", en = "Battery Triage Mode (${battery.percent}%)", fr = "Mode Triage Batterie (${battery.percent}%)")
                    },
                    fontSize = 13.5.sp,
                    fontWeight = FontWeight.Bold,
                    color = DirectSwitchTheme.textPrimary
                )
                Text(
                    text = DirectSwitchL10n.tr(
                        "Priorità automatica a password CSV, documenti, preferiti e ricordi recenti se il telefono sta per spegnersi.",
                        en = "Prioritizes password CSVs, documents, favorites and recent photos first if battery is running low.",
                        fr = "Priorise automatiquement les CSV, documents, favoris et souvenirs récents si la batterie est faible."
                    ),
                    fontSize = 11.5.sp,
                    color = DirectSwitchTheme.textSecondary
                )
            }
            Switch(
                checked = enabled || battery.recommendsAutoTriage,
                onCheckedChange = onToggle,
                colors = SwitchDefaults.colors(checkedTrackColor = DirectSwitchTheme.orange)
            )
        }
    }
}

@Composable
fun BatteryTriageActivePill() {
    Surface(
        shape = RoundedCornerShape(50),
        color = DirectSwitchTheme.orange.copy(alpha = 0.14f)
    ) {
        Row(
            modifier = Modifier.padding(horizontal = 10.dp, vertical = 4.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(5.dp)
        ) {
            Icon(Icons.Filled.BatteryAlert, contentDescription = null, tint = DirectSwitchTheme.orange, modifier = Modifier.size(13.dp))
            Text(
                text = DirectSwitchL10n.tr("Triage Batteria Critica"),
                fontSize = 11.5.sp,
                fontWeight = FontWeight.SemiBold,
                color = DirectSwitchTheme.orange
            )
        }
    }
}

// MARK: - 11. Componenti Practical Pro (#1–#5): Termica, Smart Clean, HEIC, Riconciliazione, AP Isolation

@Composable
fun ThermalGuardBannerPill(
    state: ThermalGuardState,
    bannerText: String?
) {
    if (state == ThermalGuardState.NORMAL) return
    val isCritical = state == ThermalGuardState.CRITICAL_COOLDOWN
    val color = if (isCritical) DirectSwitchTheme.red else DirectSwitchTheme.orange
    val rawLabel = bannerText?.takeIf { it.isNotBlank() } ?: if (isCritical) {
        "Raffreddamento termico (45s)"
    } else {
        "Limite termico (1 flusso)"
    }
    val label = DirectSwitchL10n.tr(rawLabel)
    Surface(
        shape = RoundedCornerShape(20.dp),
        color = color.copy(alpha = 0.14f),
        border = BorderStroke(1.dp, color.copy(alpha = 0.45f))
    ) {
        Row(
            modifier = Modifier.padding(horizontal = 10.dp, vertical = 6.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(6.dp)
        ) {
            Icon(
                imageVector = Icons.Filled.Warning,
                contentDescription = null,
                tint = color,
                modifier = Modifier.size(15.dp)
            )
            Text(
                text = label,
                fontSize = 11.5.sp,
                fontWeight = FontWeight.SemiBold,
                color = color,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis
            )
        }
    }
}

@Composable
fun NetworkIsolationHotspotCard(
    verdict: NetworkDiagnosticVerdict,
    onRetryConnect: () -> Unit,
    showRetryButton: Boolean = true
) {
    val accent = if (verdict.likelyApClientIsolation) DirectSwitchTheme.orange else DirectSwitchTheme.blue
    Surface(
        shape = RoundedCornerShape(16.dp),
        color = accent.copy(alpha = 0.08f),
        border = BorderStroke(1.2.dp, accent.copy(alpha = 0.45f)),
        modifier = Modifier.fillMaxWidth()
    ) {
        Column(
            modifier = Modifier.padding(14.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(10.dp)
            ) {
                AppleSettingsIcon(icon = Icons.Filled.WifiTethering, color = accent)
                Column(modifier = Modifier.weight(1f)) {
                    Text(
                        text = verdict.title,
                        fontSize = 14.5.sp,
                        fontWeight = FontWeight.Bold,
                        color = DirectSwitchTheme.textPrimary
                    )
                    Text(
                        text = verdict.description,
                        fontSize = 12.sp,
                        color = DirectSwitchTheme.textSecondary
                    )
                }
            }
            for (stepLine in verdict.guidanceSteps) {
                Text(
                    text = stepLine,
                    fontSize = 12.sp,
                    color = DirectSwitchTheme.textPrimary,
                    modifier = Modifier.padding(start = 4.dp)
                )
            }
            if (showRetryButton) {
                DirectSwitchSecondaryButton(
                    text = DirectSwitchL10n.tr("Ho attivato l'Hotspot • Riprova collegamento"),
                    onClick = onRetryConnect
                )
            }
        }
    }
}

@Composable
fun SmartCleanAndCompatCard(
    smartClean: SmartCleanOptions,
    convertHeicToJpeg: Boolean,
    showHeicOption: Boolean,
    onSmartCleanChange: (SmartCleanOptions) -> Unit,
    onToggleConvertHeic: (Boolean) -> Unit
) {
    var expanded by remember { mutableStateOf(false) }
    val activeCount = listOf(
        smartClean.mergeDuplicateContacts,
        smartClean.skipExactDuplicatePhotosSha256,
        smartClean.skipOldScreenshotsOlderThanMonths > 0,
        showHeicOption && convertHeicToJpeg
    ).count { it }

    Surface(
        shape = RoundedCornerShape(16.dp),
        color = DirectSwitchTheme.cardSurface,
        border = BorderStroke(1.dp, DirectSwitchTheme.hairline),
        modifier = Modifier.fillMaxWidth()
    ) {
        Column(
            modifier = Modifier.padding(12.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)
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
                    AppleSettingsIcon(icon = Icons.Filled.Shield, color = DirectSwitchTheme.teal, size = 28.dp)
                    Column {
                        Text(
                            text = DirectSwitchL10n.tr("Smart Clean & Compatibilità Pro"),
                            fontSize = 14.5.sp,
                            fontWeight = FontWeight.SemiBold,
                            color = DirectSwitchTheme.textPrimary
                        )
                        Text(
                            text = DirectSwitchL10n.tr(
                                "$activeCount protezioni attive prima dell'invio",
                                en = "$activeCount active protections before sending",
                                fr = "$activeCount protections actives avant l'envoi"
                            ),
                            fontSize = 11.5.sp,
                            color = DirectSwitchTheme.textSecondary
                        )
                    }
                }
                Icon(
                    imageVector = if (expanded) Icons.Filled.ExpandLess else Icons.Filled.ExpandMore,
                    contentDescription = null,
                    tint = DirectSwitchTheme.textSecondary
                )
            }

            if (expanded) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.SpaceBetween
                ) {
                    Column(modifier = Modifier.weight(1f).padding(end = 8.dp)) {
                        Text(DirectSwitchL10n.tr("Unisci contatti duplicati (+39)"), fontSize = 13.sp, fontWeight = FontWeight.Medium, color = DirectSwitchTheme.textPrimary)
                        Text(DirectSwitchL10n.tr("Fonde numeri e note in memoria senza toccare il vecchio telefono"), fontSize = 11.sp, color = DirectSwitchTheme.textSecondary)
                    }
                    Switch(
                        checked = smartClean.mergeDuplicateContacts,
                        onCheckedChange = { onSmartCleanChange(smartClean.copy(mergeDuplicateContacts = it)) },
                        colors = SwitchDefaults.colors(checkedThumbColor = Color.White, checkedTrackColor = DirectSwitchTheme.teal)
                    )
                }

                Row(
                    modifier = Modifier.fillMaxWidth(),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.SpaceBetween
                ) {
                    Column(modifier = Modifier.weight(1f).padding(end = 8.dp)) {
                        Text(DirectSwitchL10n.tr("Salta foto duplicate esatte (SHA-256)"), fontSize = 13.sp, fontWeight = FontWeight.Medium, color = DirectSwitchTheme.textPrimary)
                        Text(DirectSwitchL10n.tr("Evita di copiare file identici pixel-per-pixel"), fontSize = 11.sp, color = DirectSwitchTheme.textSecondary)
                    }
                    Switch(
                        checked = smartClean.skipExactDuplicatePhotosSha256,
                        onCheckedChange = { onSmartCleanChange(smartClean.copy(skipExactDuplicatePhotosSha256 = it)) },
                        colors = SwitchDefaults.colors(checkedThumbColor = Color.White, checkedTrackColor = DirectSwitchTheme.teal)
                    )
                }

                Row(
                    modifier = Modifier.fillMaxWidth(),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.SpaceBetween
                ) {
                    Column(modifier = Modifier.weight(1f).padding(end = 8.dp)) {
                        Text(DirectSwitchL10n.tr("Escludi vecchi screenshot (> 12 mesi)"), fontSize = 13.sp, fontWeight = FontWeight.Medium, color = DirectSwitchTheme.textPrimary)
                        Text(DirectSwitchL10n.tr("Libera spazio evitando schermate datate"), fontSize = 11.sp, color = DirectSwitchTheme.textSecondary)
                    }
                    Switch(
                        checked = smartClean.skipOldScreenshotsOlderThanMonths > 0,
                        onCheckedChange = { onSmartCleanChange(smartClean.copy(skipOldScreenshotsOlderThanMonths = if (it) 12 else 0)) },
                        colors = SwitchDefaults.colors(checkedThumbColor = Color.White, checkedTrackColor = DirectSwitchTheme.teal)
                    )
                }

                if (showHeicOption) {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.SpaceBetween
                    ) {
                        Column(modifier = Modifier.weight(1f).padding(end = 8.dp)) {
                            Text(DirectSwitchL10n.tr("Massima compatibilità HEIC → JPEG"), fontSize = 13.sp, fontWeight = FontWeight.Medium, color = DirectSwitchTheme.textPrimary)
                            Text(DirectSwitchL10n.tr("Converte foto HEIC mantenendo data scatto, rotazione e GPS"), fontSize = 11.sp, color = DirectSwitchTheme.textSecondary)
                        }
                        Switch(
                            checked = convertHeicToJpeg,
                            onCheckedChange = onToggleConvertHeic,
                            colors = SwitchDefaults.colors(checkedThumbColor = Color.White, checkedTrackColor = DirectSwitchTheme.teal)
                        )
                    }
                }
            }
        }
    }
}

@Composable
fun PostTransferReconciliationCard(
    verifiedCount: Int,
    missingIds: List<String>,
    failedCount: Int = 0,
    heicConvertedCount: Int,
    smartCleanMergedContacts: Int,
    smartCleanSkippedDuplicates: Int,
    smartCleanSkippedScreenshots: Int,
    onRepairMissing: (List<String>) -> Unit
) {
    val allClean = missingIds.isEmpty()
    val accent = if (allClean) DirectSwitchTheme.green else DirectSwitchTheme.orange
    Surface(
        shape = RoundedCornerShape(16.dp),
        color = accent.copy(alpha = 0.08f),
        border = BorderStroke(1.2.dp, accent.copy(alpha = 0.4f)),
        modifier = Modifier.fillMaxWidth()
    ) {
        Column(
            modifier = Modifier.padding(14.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(10.dp)
            ) {
                AppleSettingsIcon(
                    icon = if (allClean) Icons.Filled.VerifiedUser else Icons.Filled.Warning,
                    color = accent
                )
                Column(modifier = Modifier.weight(1f)) {
                    Text(
                        text = when {
                            allClean && failedCount == 0 -> DirectSwitchL10n.tr("Verifica SHA-256 Post-Migrazione: 100% Integro")
                            allClean -> DirectSwitchL10n.tr(
                                "Verifica SHA-256: $verifiedCount file ricevuti integri",
                                en = "SHA-256 Check: $verifiedCount received files verified",
                                fr = "Vérification SHA-256 : $verifiedCount fichiers reçus intègres"
                            )
                            else -> DirectSwitchL10n.tr(
                                "Rilevati ${missingIds.size} file mancanti o alterati",
                                en = "${missingIds.size} missing or altered files detected",
                                fr = "${missingIds.size} fichiers manquants ou altérés détectés"
                            )
                        },
                        fontSize = 14.5.sp,
                        fontWeight = FontWeight.Bold,
                        color = DirectSwitchTheme.textPrimary
                    )
                    Text(
                        text = DirectSwitchL10n.tr(
                            "$verifiedCount file verificati con impronta crittografica end-to-end.",
                            en = "$verifiedCount files verified with end-to-end cryptographic hash.",
                            fr = "$verifiedCount fichiers vérifiés par empreinte cryptographique de bout en bout."
                        ),
                        fontSize = 12.sp,
                        color = DirectSwitchTheme.textSecondary
                    )
                }
            }

            if (smartCleanMergedContacts > 0 || smartCleanSkippedDuplicates > 0 || smartCleanSkippedScreenshots > 0 || heicConvertedCount > 0) {
                val statsParts = buildList {
                    if (smartCleanMergedContacts > 0) add(
                        DirectSwitchL10n.tr(
                            "$smartCleanMergedContacts contatti uniti",
                            en = "$smartCleanMergedContacts contacts merged",
                            fr = "$smartCleanMergedContacts contacts fusionnés"
                        )
                    )
                    if (smartCleanSkippedDuplicates > 0) add(
                        DirectSwitchL10n.tr(
                            "$smartCleanSkippedDuplicates foto duplicate saltate",
                            en = "$smartCleanSkippedDuplicates duplicate photos skipped",
                            fr = "$smartCleanSkippedDuplicates photos en double ignorées"
                        )
                    )
                    if (smartCleanSkippedScreenshots > 0) add(
                        DirectSwitchL10n.tr(
                            "$smartCleanSkippedScreenshots vecchi screenshot esclusi",
                            en = "$smartCleanSkippedScreenshots old screenshots excluded",
                            fr = "$smartCleanSkippedScreenshots anciennes captures exclues"
                        )
                    )
                    if (heicConvertedCount > 0) add("$heicConvertedCount HEIC→JPEG")
                }
                Text(
                    text = "Smart Clean: ${statsParts.joinToString(" • ")}",
                    fontSize = 11.5.sp,
                    color = DirectSwitchTheme.teal,
                    fontWeight = FontWeight.SemiBold
                )
            }

            if (missingIds.isNotEmpty()) {
                DirectSwitchPrimaryButton(
                    text = DirectSwitchL10n.tr(
                        "Ripara ${missingIds.size} file mancanti (1 tocco)",
                        en = "Repair ${missingIds.size} missing files (1 tap)",
                        fr = "Réparer ${missingIds.size} fichiers manquants (1 geste)"
                    ),
                    onClick = { onRepairMissing(missingIds) }
                )
            }
        }
    }
}
