package com.example.mobile

import android.annotation.SuppressLint
import android.os.Build
import android.telephony.SubscriptionManager
import android.telephony.TelephonyManager
import android.content.Context
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.example.mobile/sim"

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler {
            call, result ->
            if (call.method == "getSimCards") {
                val simCards = getSimCards()
                result.success(simCards)
            } else {
                result.notImplemented()
            }
        }
    }

    @SuppressLint("HardwareIds", "MissingPermission")
    private fun getSimCards(): List<Map<String, String>> {
        val list = mutableListOf<Map<String, String>>()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP_MR1) {
            val subscriptionManager = getSystemService(Context.TELEPHONY_SUBSCRIPTION_SERVICE) as SubscriptionManager
            try {
                val activeSubscriptionInfoList = subscriptionManager.activeSubscriptionInfoList
                if (activeSubscriptionInfoList != null && activeSubscriptionInfoList.isNotEmpty()) {
                    for (info in activeSubscriptionInfoList) {
                        val map = mutableMapOf<String, String>()
                        map["carrierName"] = info.carrierName?.toString() ?: "Unknown"
                        map["displayName"] = info.displayName?.toString() ?: "Unknown"
                        map["slotIndex"] = info.simSlotIndex.toString()
                        map["subscriptionId"] = info.subscriptionId.toString()

                        var number = ""
                        try {
                            number = info.number ?: ""
                        } catch (e: Exception) { /* ignore */ }

                        // Fallback: try TelephonyManager per-slot for older devices
                        if (number.isEmpty()) {
                            try {
                                val telephonyManager = getSystemService(Context.TELEPHONY_SERVICE) as TelephonyManager
                                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                                    val slotTm = telephonyManager.createForSubscriptionId(info.subscriptionId)
                                    number = slotTm.line1Number ?: ""
                                } else {
                                    @Suppress("DEPRECATION")
                                    number = telephonyManager.line1Number ?: ""
                                }
                            } catch (e: Exception) { /* ignore */ }
                        }

                        map["number"] = number
                        list.add(map)
                    }
                } else {
                    // Last resort: single TelephonyManager for very old devices with no SubscriptionManager support
                    try {
                        val telephonyManager = getSystemService(Context.TELEPHONY_SERVICE) as TelephonyManager
                        val number = telephonyManager.line1Number ?: ""
                        val map = mutableMapOf<String, String>()
                        map["carrierName"] = telephonyManager.networkOperatorName ?: "Unknown"
                        map["displayName"] = "SIM 1"
                        map["slotIndex"] = "0"
                        map["subscriptionId"] = "0"
                        map["number"] = number
                        list.add(map)
                    } catch (e: Exception) { /* ignore */ }
                }
            } catch (e: SecurityException) {
                // Permission was not granted — try basic TelephonyManager
                try {
                    val telephonyManager = getSystemService(Context.TELEPHONY_SERVICE) as TelephonyManager
                    val number = telephonyManager.line1Number ?: ""
                    val map = mutableMapOf<String, String>()
                    map["carrierName"] = telephonyManager.networkOperatorName ?: "Unknown"
                    map["displayName"] = "SIM 1"
                    map["slotIndex"] = "0"
                    map["subscriptionId"] = "0"
                    map["number"] = number
                    list.add(map)
                } catch (e2: Exception) { /* ignore */ }
            }
        } else {
            // Very old Android (<5.1): single SIM via TelephonyManager only
            try {
                val telephonyManager = getSystemService(Context.TELEPHONY_SERVICE) as TelephonyManager
                @Suppress("DEPRECATION")
                val number = telephonyManager.line1Number ?: ""
                val map = mutableMapOf<String, String>()
                map["carrierName"] = telephonyManager.networkOperatorName ?: "Unknown"
                map["displayName"] = "SIM 1"
                map["slotIndex"] = "0"
                map["subscriptionId"] = "0"
                map["number"] = number
                list.add(map)
            } catch (e: Exception) { /* ignore */ }
        }
        return list
    }
}

