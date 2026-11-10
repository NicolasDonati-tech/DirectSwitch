//
//  DirectSwitchTheme.kt
//  DirectSwitch-Android
//
//  Created by Nicolas Donati.
//  Copyright © 2026 Nicolas Donati. Tutti i diritti riservati.
//

package com.directswitch.android.ui.theme

import android.graphics.Bitmap
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBackIos
import androidx.compose.material.icons.filled.Info
import androidx.compose.material.icons.filled.SwapHoriz
import androidx.compose.material.icons.filled.Verified
import androidx.compose.material.icons.outlined.Info
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Surface
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.directswitch.android.DirectSwitchLog
import com.google.zxing.BarcodeFormat
import com.google.zxing.EncodeHintType
import com.google.zxing.qrcode.QRCodeWriter

/**
 * Tema grafico Apple HIG condiviso con CloudSave (base perla #F8FAFD + colori neutri senza viola).
 */
object DirectSwitchTheme {
    val canvasTop = Color(0xFFE0E7F1)
    val canvasMid = Color(0xFFE9EEF6)
    val canvasBottom = Color(0xFFDAE2EE)

    val headerBg = Color(0xF2E5EBF4)
    val cardSurface = Color(0xFFF8FAFD)
    val cardSelected = Color(0xFFEAF2FE)
    val inputSurface = Color(0xFFEAEFF6)
    val cardBorder = Color(0xFFCFD8E5)
    val hairline = Color(0xFFC7D0DE)

    val blue = Color(0xFF007AFF)
    val teal = Color(0xFF008AA8)
    val green = Color(0xFF34C759)
    val orange = Color(0xFFFF9500)
    val red = Color(0xFFFF3B30)
    val slate = Color(0xFF374151)
    val charcoal = Color(0xFF1C1E23)

    // Palette dedicata per il badge "Premium Direct" (Oro/Ambra stile funzionalità Premium)
    val premiumGold = Color(0xFFC77305)
    val premiumAmber = Color(0xFFF1960A)
    val premiumSurface = Color(0xFFFFF6DC)
    val premiumBorder = Color(0xFFEBA825)

    // Alias neutro senza viola
    val indigo = slate
    val tealPrimary = blue
    val blueAccent = blue
    val greenSuccess = green
    val amberPro = orange
    val dangerRed = red

    val textPrimary = Color(0xFF1C1C1E)
    val textSecondary = Color(0xFF636366)
    val textMuted = Color(0xFF8E8E93)

    val backgroundBrush: Brush
        get() = Brush.linearGradient(
            colors = listOf(canvasTop, canvasMid, canvasBottom),
            start = Offset.Zero,
            end = Offset(1200f, 2400f)
        )
}

@Composable
fun DirectSwitchAppleEmblem(size: Dp = 88.dp) {
    val radius = size * 0.235f
    Box(
        modifier = Modifier
            .size(size)
            .shadow(
                elevation = 8.dp,
                shape = RoundedCornerShape(radius),
                ambientColor = DirectSwitchTheme.blue.copy(alpha = 0.24f),
                spotColor = DirectSwitchTheme.blue.copy(alpha = 0.24f)
            )
            .clip(RoundedCornerShape(radius))
            .background(
                Brush.linearGradient(
                    colors = listOf(
                        Color(0xFF1284FF),
                        Color(0xFF0058D6),
                        Color(0xFF008AA8)
                    )
                )
            )
    ) {
        Canvas(modifier = Modifier.fillMaxSize()) {
            val w = this.size.width
            val h = this.size.height

            // 1. Telefono posteriore glassmorphic
            drawRoundRect(
                color = Color.White.copy(alpha = 0.37f),
                topLeft = Offset(w * 0.439f, h * 0.151f),
                size = Size(w * 0.312f, h * 0.478f),
                cornerRadius = CornerRadius(w * 0.073f, w * 0.073f)
            )
            drawRoundRect(
                color = Color.White.copy(alpha = 0.47f),
                topLeft = Offset(w * 0.439f, h * 0.151f),
                size = Size(w * 0.312f, h * 0.478f),
                cornerRadius = CornerRadius(w * 0.073f, w * 0.073f),
                style = Stroke(width = w * 0.012f)
            )

            // 2. Telefono frontale bianco-perla
            drawRoundRect(
                color = Color.White,
                topLeft = Offset(w * 0.244f, h * 0.244f),
                size = Size(w * 0.337f, h * 0.518f),
                cornerRadius = CornerRadius(w * 0.080f, w * 0.080f)
            )

            // 3. Tacca speaker
            drawRoundRect(
                color = Color(0xFF0062D6).copy(alpha = 0.26f),
                topLeft = Offset(w * 0.371f, h * 0.282f),
                size = Size(w * 0.083f, h * 0.0185f),
                cornerRadius = CornerRadius(w * 0.01f, w * 0.01f)
            )

            // 4. Doppia freccia orizzontale (Blu -> destra, Teal <- sinistra)
            val stroke = Stroke(width = w * 0.0265f, cap = StrokeCap.Round, join = StrokeJoin.Round)
            val rightPath = Path().apply {
                moveTo(w * 0.332f, h * 0.466f)
                lineTo(w * 0.493f, h * 0.466f)
                moveTo(w * 0.449f, h * 0.422f)
                lineTo(w * 0.495f, h * 0.466f)
                lineTo(w * 0.449f, h * 0.510f)
            }
            drawPath(rightPath, color = Color(0xFF0070F0), style = stroke)

            val leftPath = Path().apply {
                moveTo(w * 0.493f, h * 0.564f)
                lineTo(w * 0.332f, h * 0.564f)
                moveTo(w * 0.376f, h * 0.520f)
                lineTo(w * 0.330f, h * 0.564f)
                lineTo(w * 0.376f, h * 0.608f)
            }
            drawPath(leftPath, color = Color(0xFF008AA8), style = stroke)
        }
    }
}

@Composable
fun AppleSettingsIcon(
    icon: ImageVector,
    color: Color,
    size: Dp = 30.dp
) {
    Box(
        modifier = Modifier
            .size(size)
            .clip(RoundedCornerShape(8.dp))
            .background(color),
        contentAlignment = Alignment.Center
    ) {
        Icon(
            imageVector = icon,
            contentDescription = null,
            tint = Color.White,
            modifier = Modifier.size(size * 0.55f)
        )
    }
}

@Composable
fun AppleTopNavigationBar(
    title: String,
    showBackButton: Boolean,
    isProUnlocked: Boolean,
    onBack: () -> Unit,
    onTapPassBadge: () -> Unit
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .background(DirectSwitchTheme.headerBg)
            .statusBarsPadding()
    ) {
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .height(50.dp)
                .padding(horizontal = 16.dp),
            contentAlignment = Alignment.Center
        ) {
            if (showBackButton) {
                Text(
                    text = title,
                    fontSize = 17.sp,
                    fontWeight = FontWeight.SemiBold,
                    color = DirectSwitchTheme.textPrimary,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
            }

            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.SpaceBetween
            ) {
                if (showBackButton) {
                    Row(
                        modifier = Modifier
                            .clip(RoundedCornerShape(8.dp))
                            .clickable(onClick = onBack)
                            .padding(vertical = 4.dp, horizontal = 2.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Icon(
                            imageVector = Icons.AutoMirrored.Filled.ArrowBackIos,
                            contentDescription = "Indietro",
                            tint = DirectSwitchTheme.blue,
                            modifier = Modifier.size(16.dp)
                        )
                        Text(
                            text = "Indietro",
                            fontSize = 16.sp,
                            color = DirectSwitchTheme.blue
                        )
                    }
                } else {
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        DirectSwitchAppleEmblem(size = 26.dp)
                        Text(
                            text = "DirectSwitch",
                            fontSize = 17.sp,
                            fontWeight = FontWeight.Bold,
                            color = DirectSwitchTheme.textPrimary
                        )
                    }
                }

                Surface(
                    onClick = onTapPassBadge,
                    shape = RoundedCornerShape(20.dp),
                    color = DirectSwitchTheme.premiumSurface,
                    border = BorderStroke(1.dp, DirectSwitchTheme.premiumBorder.copy(alpha = 0.65f))
                ) {
                    Row(
                        modifier = Modifier.padding(horizontal = 11.dp, vertical = 5.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(5.dp)
                    ) {
                        Icon(
                            imageVector = Icons.Filled.Verified,
                            contentDescription = null,
                            tint = DirectSwitchTheme.premiumAmber,
                            modifier = Modifier.size(13.dp)
                        )
                        Text(
                            text = if (isProUnlocked) "Premium Attivo" else "Premium Direct",
                            fontSize = 12.sp,
                            fontWeight = FontWeight.Bold,
                            color = DirectSwitchTheme.premiumGold
                        )
                    }
                }
            }
        }

        Box(
            modifier = Modifier
                .fillMaxWidth()
                .height(0.6.dp)
                .background(DirectSwitchTheme.hairline)
        )
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun InfoCircleButton(
    title: String,
    message: String
) {
    var isPresented by remember { mutableStateOf(false) }

    Box(
        modifier = Modifier
            .size(28.dp)
            .clip(CircleShape)
            .clickable(
                interactionSource = remember { MutableInteractionSource() },
                indication = null
            ) { isPresented = true },
        contentAlignment = Alignment.Center
    ) {
        Icon(
            imageVector = Icons.Outlined.Info,
            contentDescription = title,
            tint = DirectSwitchTheme.blue,
            modifier = Modifier.size(19.dp)
        )
    }

    if (isPresented) {
        val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
        ModalBottomSheet(
            onDismissRequest = { isPresented = false },
            sheetState = sheetState,
            containerColor = DirectSwitchTheme.canvasMid
        ) {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .background(DirectSwitchTheme.backgroundBrush)
                    .padding(horizontal = 20.dp, vertical = 12.dp),
                verticalArrangement = Arrangement.spacedBy(14.dp)
            ) {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(10.dp)
                ) {
                    Icon(
                        imageVector = Icons.Filled.Info,
                        contentDescription = null,
                        tint = DirectSwitchTheme.blue,
                        modifier = Modifier.size(24.dp)
                    )
                    Text(
                        text = title,
                        fontSize = 18.sp,
                        fontWeight = FontWeight.SemiBold,
                        color = DirectSwitchTheme.textPrimary
                    )
                }

                Text(
                    text = message,
                    fontSize = 15.sp,
                    lineHeight = 21.sp,
                    color = DirectSwitchTheme.textSecondary
                )

                Spacer(modifier = Modifier.height(4.dp))

                Button(
                    onClick = { isPresented = false },
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(45.dp),
                    shape = RoundedCornerShape(12.dp),
                    colors = ButtonDefaults.buttonColors(
                        containerColor = DirectSwitchTheme.blue,
                        contentColor = Color.White
                    )
                ) {
                    Text(
                        text = "Chiudi",
                        fontSize = 16.sp,
                        fontWeight = FontWeight.SemiBold
                    )
                }

                Spacer(modifier = Modifier.height(12.dp))
            }
        }
    }
}

@Composable
fun DirectSwitchCard(
    modifier: Modifier = Modifier,
    selected: Boolean = false,
    padding: Dp = 16.dp,
    spacing: Dp = 12.dp,
    content: @Composable ColumnScope.() -> Unit
) {
    Surface(
        modifier = modifier.fillMaxWidth(),
        shape = RoundedCornerShape(16.dp),
        color = if (selected) DirectSwitchTheme.cardSelected else DirectSwitchTheme.cardSurface,
        border = BorderStroke(
            width = if (selected) 1.1.dp else 0.8.dp,
            color = if (selected) DirectSwitchTheme.blue.copy(alpha = 0.45f) else DirectSwitchTheme.cardBorder
        ),
        shadowElevation = 2.dp
    ) {
        Column(
            modifier = Modifier.padding(padding),
            verticalArrangement = Arrangement.spacedBy(spacing),
            content = content
        )
    }
}

@Composable
fun DirectSwitchPrimaryButton(
    text: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    containerColor: Color = DirectSwitchTheme.blue
) {
    Button(
        onClick = onClick,
        enabled = enabled,
        modifier = modifier
            .fillMaxWidth()
            .height(48.dp),
        shape = RoundedCornerShape(13.dp),
        colors = ButtonDefaults.buttonColors(
            containerColor = containerColor,
            contentColor = Color.White,
            disabledContainerColor = containerColor.copy(alpha = 0.48f),
            disabledContentColor = Color.White.copy(alpha = 0.9f)
        ),
        contentPadding = PaddingValues(horizontal = 16.dp)
    ) {
        Text(
            text = text,
            fontSize = 16.sp,
            fontWeight = FontWeight.SemiBold
        )
    }
}

@Composable
fun DirectSwitchNeutralOutlinedButton(
    text: String,
    onClick: () -> Unit
) {
    Surface(
        onClick = onClick,
        modifier = Modifier
            .fillMaxWidth()
            .height(48.dp),
        shape = RoundedCornerShape(13.dp),
        color = DirectSwitchTheme.inputSurface,
        border = BorderStroke(1.0.dp, DirectSwitchTheme.cardBorder)
    ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.Center,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Icon(
                imageVector = Icons.Filled.SwapHoriz,
                contentDescription = null,
                tint = DirectSwitchTheme.slate,
                modifier = Modifier.size(18.dp)
            )
            Spacer(modifier = Modifier.width(8.dp))
            Text(
                text = text,
                fontSize = 16.sp,
                fontWeight = FontWeight.SemiBold,
                color = DirectSwitchTheme.textPrimary
            )
        }
    }
}

@Composable
fun DirectSwitchSecondaryButton(
    text: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    tint: Color = DirectSwitchTheme.blue
) {
    Surface(
        onClick = onClick,
        modifier = modifier
            .fillMaxWidth()
            .height(45.dp),
        shape = RoundedCornerShape(12.dp),
        color = DirectSwitchTheme.inputSurface
    ) {
        Box(contentAlignment = Alignment.Center) {
            Text(
                text = text,
                fontSize = 15.sp,
                fontWeight = FontWeight.SemiBold,
                color = tint
            )
        }
    }
}

@Composable
fun CleanCategoryToggleRow(
    icon: ImageVector,
    iconColor: Color,
    title: String,
    subtitle: String? = null,
    checked: Boolean,
    onCheckedChange: (Boolean) -> Unit
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable { onCheckedChange(!checked) }
            .padding(horizontal = 14.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.SpaceBetween
    ) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(14.dp),
            modifier = Modifier.weight(1f)
        ) {
            AppleSettingsIcon(icon = icon, color = iconColor)
            Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text(
                    text = title,
                    fontSize = 16.sp,
                    fontWeight = FontWeight.Medium,
                    color = DirectSwitchTheme.textPrimary
                )
                if (!subtitle.isNullOrBlank()) {
                    Text(
                        text = subtitle,
                        fontSize = 12.sp,
                        color = DirectSwitchTheme.textSecondary
                    )
                }
            }
        }
        Switch(
            checked = checked,
            onCheckedChange = onCheckedChange,
            colors = SwitchDefaults.colors(
                checkedThumbColor = Color.White,
                checkedTrackColor = DirectSwitchTheme.green,
                uncheckedThumbColor = Color.White,
                uncheckedTrackColor = DirectSwitchTheme.inputSurface,
                uncheckedBorderColor = DirectSwitchTheme.cardBorder
            )
        )
    }
}

@Composable
fun PassaAiOSCodeBoxes(code: String) {
    val digits = code.filter { it.isDigit() }.take(6)
    Row(
        horizontalArrangement = Arrangement.spacedBy(6.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        for (idx in 0 until 6) {
            val ch = if (idx < digits.length) digits[idx].toString() else "•"
            Box(
                modifier = Modifier
                    .width(42.dp)
                    .height(54.dp)
                    .clip(RoundedCornerShape(12.dp))
                    .background(DirectSwitchTheme.inputSurface)
                    .border(0.9.dp, DirectSwitchTheme.cardBorder, RoundedCornerShape(12.dp)),
                contentAlignment = Alignment.Center
            ) {
                Text(
                    text = ch,
                    fontSize = 24.sp,
                    fontWeight = FontWeight.Bold,
                    color = DirectSwitchTheme.textPrimary
                )
            }
            if (idx == 2) {
                Spacer(modifier = Modifier.width(4.dp))
            }
        }
    }
}

object QrBitmapGenerator {
    fun generate(content: String, sizePx: Int = 640): Bitmap? {
        return try {
            val hints = mapOf(
                EncodeHintType.CHARACTER_SET to "UTF-8",
                EncodeHintType.MARGIN to 1
            )
            val matrix = QRCodeWriter().encode(content, BarcodeFormat.QR_CODE, sizePx, sizePx, hints)
            val pixels = IntArray(sizePx * sizePx)
            val dark = 0xFF1C1C1E.toInt()
            val light = 0xFFFFFFFF.toInt()
            for (y in 0 until sizePx) {
                val offset = y * sizePx
                for (x in 0 until sizePx) {
                    pixels[offset + x] = if (matrix.get(x, y)) dark else light
                }
            }
            Bitmap.createBitmap(sizePx, sizePx, Bitmap.Config.ARGB_8888).apply {
                setPixels(pixels, 0, sizePx, 0, 0, sizePx, sizePx)
            }
        } catch (t: Throwable) {
            DirectSwitchLog.warn("Creazione bitmap QR fallita", t)
            null
        }
    }
}
