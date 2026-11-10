package com.directswitch.android

import android.util.Log

/**
 * Diagnostica non sensibile: registra solo tag, contesto e CLASSE dell'errore (mai messaggi,
 * numeri, testi SMS o percorsi che possano contenere dati personali) e solo nelle build debug.
 */
object DirectSwitchLog {
    private const val TAG = "DirectSwitch"

    fun warn(context: String, t: Throwable? = null) {
        if (!BuildConfig.DEBUG) return
        val suffix = t?.let { " (${it.javaClass.simpleName})" }.orEmpty()
        Log.w(TAG, "$context$suffix")
    }
}
