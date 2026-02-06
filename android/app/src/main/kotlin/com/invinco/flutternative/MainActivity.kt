package com.invinco.flutternative

import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothManager
import android.content.Context
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.reactivex.exceptions.UndeliverableException
import io.reactivex.plugins.RxJavaPlugins

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.invinco.flutternative/bluetooth"
    private val BACKGROUND_CHANNEL = "com.invinco.flutternative/background_ble"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // BLE 연결 해제 시 이미 dispose된 스트림에 에러 전달 시도로 인한 크래시 방지
        RxJavaPlugins.setErrorHandler { throwable ->
            val e = if (throwable is UndeliverableException) throwable.cause else throwable
            Log.w("RxJava", "Undeliverable exception (ignored): ${e?.message}")
        }

        // 블루투스 채널
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getBondedDevices" -> {
                    try {
                        val bondedDevices = getBondedDevices()
                        result.success(bondedDevices)
                    } catch (e: Exception) {
                        result.error("BLUETOOTH_ERROR", e.message, null)
                    }
                }
                else -> {
                    result.notImplemented()
                }
            }
        }

        // 백그라운드 서비스 채널
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, BACKGROUND_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "startForegroundService" -> {
                    try {
                        BleForegroundService.start(this)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("SERVICE_ERROR", e.message, null)
                    }
                }
                "stopForegroundService" -> {
                    try {
                        BleForegroundService.stop(this)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("SERVICE_ERROR", e.message, null)
                    }
                }
                "getBondedDevices" -> {
                    try {
                        val bondedDevices = getBondedDevices()
                        result.success(bondedDevices)
                    } catch (e: Exception) {
                        result.error("BLUETOOTH_ERROR", e.message, null)
                    }
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    private fun getBondedDevices(): List<Map<String, Any>> {
        val bluetoothManager = getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager
        val bluetoothAdapter = bluetoothManager.adapter ?: return emptyList()

        return try {
            bluetoothAdapter.bondedDevices.map { device ->
                mapOf(
                    "address" to device.address,
                    "name" to (device.name ?: "Unknown"),
                    "bondState" to device.bondState
                )
            }
        } catch (e: SecurityException) {
            emptyList()
        }
    }
}
