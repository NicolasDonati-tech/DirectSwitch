//
//  DirectSwitchTheme.kt
//  DirectSwitch-Android
//
//  Created by Nicolas Donati.
//  Copyright © 2026 Nicolas Donati. Tutti i diritti riservati.
//

package com.directswitch.android.ui.theme

import com.directswitch.android.DirectSwitchLog
import android.graphics.Bitmap
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.google.zxing.BarcodeFormat
import com.google.zxing.EncodeHintType
import com.google.zxing.qrcode.QRCodeWriter

/**
 * Design System gemello di CloudSave (stile perla Apple HIG),
 * caratterizzato dall'accento Teal/Smeraldo Diretto (#008F7A / #007AFF) distintivo di DirectSwitch.
 */
object DirectSwitchTheme {
    val canvasTop = Color(0xFFDEEAF0)
    val canvasMid = Color(0xFFE8F0F5)
    val canvasBottom = Color(0xFFD6E4EC)

    val cardSurface = Color(0xFFF8FAFC)
    val cardSelected = Color(0xFFE6F6F3)
    val cardBorder = Color(0xFFCBD8E3)

    val tealPrimary = Color(0xFF008F7A)
    val blueAccent = Color(0xFF007AFF)
    val greenSuccess = Color(0xFF28A745)
    val amberPro = Color(0xFFD97706)
    val dangerRed = Color(0xFFDC2626)

    val textPrimary = Color(0xFF0F172A)
    val textSecondary = Color(0xFF475569)
    val textMuted = Color(0xFF64748B)

    val backgroundBrush = Brush.verticalGradient(
        colors = listOf(canvasTop, canvasMid, canvasBottom)
    )
}

@Composable
fun DirectSwitchCard(
    modifier: Modifier = Modifier,
    selected: Boolean = false,
    content: @Composable ColumnScope.() -> Unit
) {
    Surface(
        modifier = modifier.fillMaxWidth(),
        shape = RoundedCornerShape(18.dp),
        color = if (selected) DirectSwitchTheme.cardSelected else DirectSwitchTheme.cardSurface,
        border = BorderStroke(
            width = if (selected) 1.6.dp else 1.dp,
            color = if (selected) DirectSwitchTheme.tealPrimary else DirectSwitchTheme.cardBorder
        ),
        shadowElevation = 2.dp
    ) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp),
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
    containerColor: Color = DirectSwitchTheme.tealPrimary
) {
    Button(
        onClick = onClick,
        enabled = enabled,
        modifier = modifier
            .fillMaxWidth()
            .height(52.dp),
        shape = RoundedCornerShape(14.dp),
        colors = ButtonDefaults.buttonColors(
            containerColor = containerColor,
            contentColor = Color.White
        ),
        contentPadding = PaddingValues(horizontal = 18.dp)
    ) {
        Text(
            text = text,
            fontSize = 16.sp,
            fontWeight = FontWeight.SemiBold
        )
    }
}

@Composable
fun DirectSwitchSecondaryButton(
    text: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier
) {
    OutlinedButton(
        onClick = onClick,
        modifier = modifier
            .fillMaxWidth()
            .height(48.dp),
        shape = RoundedCornerShape(14.dp),
        border = BorderStroke(1.2.dp, DirectSwitchTheme.tealPrimary)
    ) {
        Text(
            text = text,
            fontSize = 15.sp,
            fontWeight = FontWeight.SemiBold,
            color = DirectSwitchTheme.tealPrimary
        )
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
            val dark = 0xFF0F172A.toInt()
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
