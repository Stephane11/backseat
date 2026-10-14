package com.backseat.backseat

import android.content.Context
import android.os.BatteryManager
import android.os.Build
import android.os.PowerManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Battery and thermal state for the live screen's warnings (brief §7).
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "backseat/device")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "status" -> {
                        val battery = getSystemService(Context.BATTERY_SERVICE) as BatteryManager
                        val thermal = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                            (getSystemService(Context.POWER_SERVICE) as PowerManager)
                                .currentThermalStatus
                        } else {
                            0
                        }
                        result.success(
                            mapOf(
                                "battery" to battery.getIntProperty(
                                    BatteryManager.BATTERY_PROPERTY_CAPACITY
                                ),
                                "charging" to battery.isCharging,
                                "thermal" to thermal,
                            )
                        )
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
