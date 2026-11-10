//
//  DirectSwitchBillingManager.kt
//  DirectSwitch-Android
//
//  Created by Nicolas Donati.
//  Copyright © 2026 Nicolas Donati. Tutti i diritti riservati.
//

package com.directswitch.android.migrators

import android.app.Activity
import android.content.Context
import android.content.ContextWrapper
import com.android.billingclient.api.AcknowledgePurchaseParams
import com.android.billingclient.api.BillingClient
import com.android.billingclient.api.BillingClientStateListener
import com.android.billingclient.api.BillingFlowParams
import com.android.billingclient.api.BillingResult
import com.android.billingclient.api.PendingPurchasesParams
import com.android.billingclient.api.Purchase
import com.android.billingclient.api.PurchasesUpdatedListener
import com.android.billingclient.api.QueryProductDetailsParams
import com.android.billingclient.api.QueryPurchasesParams
import com.directswitch.android.BuildConfig

/**
 * Estrae l'[Activity] ospitante anche quando il [Context] di Compose è avvolto in uno o più [ContextWrapper].
 */
fun Context.findHostActivity(): Activity? {
    var cur: Context? = this
    while (cur is ContextWrapper) {
        if (cur is Activity) return cur
        cur = cur.baseContext
    }
    return null
}

/**
 * Gestore acquisti in-app Google Play Billing (v7) per lo sblocco "Single-Side" del Pass Cross-OS
 * (`com.directswitch.android.cross_os_pass`).
 *
 * Sicurezza di produzione:
 * - Nelle build `release` (`BuildConfig.DEBUG == false`), lo sblocco avviene ESCLUSIVAMENTE a fronte
 *   di una transazione Google Play verificata (`Purchase.PurchaseState.PURCHASED`). Nessun errore di rete
 *   o assenza del Play Store può mai sbloccare gratuitamente il Pass.
 * - Solo nelle build `debug` (`BuildConfig.DEBUG == true`) è consentito il fallback locale per il collaudo
 *   prima della pubblicazione dello SKU sulla Play Console.
 */
class DirectSwitchBillingManager(
    private val context: Context,
    private val onEntitlementChanged: (Boolean, String) -> Unit
) : PurchasesUpdatedListener {

    companion object {
        const val PRODUCT_ID_CROSS_OS_PASS = "com.directswitch.android.cross_os_pass"
    }

    private val billingClient: BillingClient = BillingClient.newBuilder(context.applicationContext)
        .setListener(this)
        .enablePendingPurchases(
            PendingPurchasesParams.newBuilder()
                .enableOneTimeProducts()
                .build()
        )
        .build()

    fun connectAndRestorePurchases() {
        if (billingClient.isReady) {
            restoreExistingPurchases(userInitiated = false)
            return
        }
        billingClient.startConnection(object : BillingClientStateListener {
            override fun onBillingSetupFinished(result: BillingResult) {
                if (result.responseCode == BillingClient.BillingResponseCode.OK) {
                    restoreExistingPurchases(userInitiated = false)
                }
            }

            override fun onBillingServiceDisconnected() {
                // Riconnessione automatica al prossimo tentativo di acquisto o ripristino
            }
        })
    }

    fun restoreExistingPurchases(userInitiated: Boolean = false) {
        if (!billingClient.isReady) {
            if (userInitiated) {
                billingClient.startConnection(object : BillingClientStateListener {
                    override fun onBillingSetupFinished(result: BillingResult) {
                        if (result.responseCode == BillingClient.BillingResponseCode.OK) {
                            queryPurchasesInternal(userInitiated = true)
                        } else {
                            onEntitlementChanged(false, "Google Play Store non raggiungibile. Verifica la connessione.")
                        }
                    }

                    override fun onBillingServiceDisconnected() {}
                })
            }
            return
        }
        queryPurchasesInternal(userInitiated)
    }

    private fun queryPurchasesInternal(userInitiated: Boolean) {
        val params = QueryPurchasesParams.newBuilder()
            .setProductType(BillingClient.ProductType.INAPP)
            .build()
        billingClient.queryPurchasesAsync(params) { result, purchases ->
            if (result.responseCode == BillingClient.BillingResponseCode.OK) {
                var foundValidPass = false
                for (purchase in purchases) {
                    if (handlePurchase(purchase)) {
                        foundValidPass = true
                    }
                }
                if (userInitiated && !foundValidPass) {
                    onEntitlementChanged(
                        CloudSaveEntitlementDetector.isLocalProUnlocked(context),
                        "Nessun acquisto precedente trovato su questo account Google Play."
                    )
                }
            } else if (userInitiated) {
                onEntitlementChanged(false, "Impossibile verificare gli acquisti (${result.debugMessage}).")
            }
        }
    }

    fun launchCrossOsPassPurchase(
        activity: Activity?,
        allowTestFallbackIfSkuNotLive: Boolean = BuildConfig.DEBUG
    ) {
        val canUseDebugFallback = allowTestFallbackIfSkuNotLive && BuildConfig.DEBUG
        val resolvedActivity = activity ?: context.findHostActivity()
        if (resolvedActivity == null) {
            if (canUseDebugFallback) {
                CloudSaveEntitlementDetector.setLocalProUnlocked(context, true)
                onEntitlementChanged(true, "Pass Cross-OS attivato (Modalità Debug Locale).")
            } else {
                onEntitlementChanged(false, "Impossibile avviare la schermata di acquisto Google Play.")
            }
            return
        }

        if (!billingClient.isReady) {
            billingClient.startConnection(object : BillingClientStateListener {
                override fun onBillingSetupFinished(result: BillingResult) {
                    if (result.responseCode == BillingClient.BillingResponseCode.OK) {
                        queryAndLaunchFlow(resolvedActivity, canUseDebugFallback)
                    } else if (canUseDebugFallback) {
                        CloudSaveEntitlementDetector.setLocalProUnlocked(context, true)
                        onEntitlementChanged(true, "Pass Cross-OS sbloccato (Solo Debug — Play Store offline).")
                    } else {
                        onEntitlementChanged(false, "Google Play Store non disponibile. Connettiti a Internet e riprova.")
                    }
                }

                override fun onBillingServiceDisconnected() {}
            })
        } else {
            queryAndLaunchFlow(resolvedActivity, canUseDebugFallback)
        }
    }

    private fun queryAndLaunchFlow(activity: Activity, canUseDebugFallback: Boolean) {
        val productList = listOf(
            QueryProductDetailsParams.Product.newBuilder()
                .setProductId(PRODUCT_ID_CROSS_OS_PASS)
                .setProductType(BillingClient.ProductType.INAPP)
                .build()
        )
        val params = QueryProductDetailsParams.newBuilder()
            .setProductList(productList)
            .build()

        billingClient.queryProductDetailsAsync(params) { result, productDetailsList ->
            val details = productDetailsList.firstOrNull()
            if (result.responseCode == BillingClient.BillingResponseCode.OK && details != null) {
                val flowParams = BillingFlowParams.newBuilder()
                    .setProductDetailsParamsList(
                        listOf(
                            BillingFlowParams.ProductDetailsParams.newBuilder()
                                .setProductDetails(details)
                                .build()
                        )
                    )
                    .build()
                billingClient.launchBillingFlow(activity, flowParams)
            } else if (canUseDebugFallback) {
                CloudSaveEntitlementDetector.setLocalProUnlocked(context, true)
                onEntitlementChanged(true, "Pass Cross-OS attivato (Solo Debug — SKU pre-lancio).")
            } else {
                onEntitlementChanged(false, "Prodotto non disponibile sul Google Play Store (${result.debugMessage}).")
            }
        }
    }

    override fun onPurchasesUpdated(result: BillingResult, purchases: MutableList<Purchase>?) {
        if (result.responseCode == BillingClient.BillingResponseCode.OK && purchases != null) {
            for (purchase in purchases) {
                handlePurchase(purchase)
            }
        } else if (result.responseCode == BillingClient.BillingResponseCode.ITEM_ALREADY_OWNED) {
            restoreExistingPurchases(userInitiated = true)
        } else if (result.responseCode != BillingClient.BillingResponseCode.USER_CANCELED) {
            onEntitlementChanged(false, "Acquisto non completato: ${result.debugMessage}")
        }
    }

    private fun handlePurchase(purchase: Purchase): Boolean {
        if (purchase.purchaseState == Purchase.PurchaseState.PURCHASED &&
            purchase.products.contains(PRODUCT_ID_CROSS_OS_PASS)
        ) {
            CloudSaveEntitlementDetector.setLocalProUnlocked(context, true)
            if (!purchase.isAcknowledged) {
                val ackParams = AcknowledgePurchaseParams.newBuilder()
                    .setPurchaseToken(purchase.purchaseToken)
                    .build()
                billingClient.acknowledgePurchase(ackParams) {}
            }
            onEntitlementChanged(true, "Pass Cross-OS Google Play verificato e attivato!")
            return true
        }
        return false
    }

    fun endConnection() {
        if (billingClient.isReady) {
            billingClient.endConnection()
        }
    }
}
