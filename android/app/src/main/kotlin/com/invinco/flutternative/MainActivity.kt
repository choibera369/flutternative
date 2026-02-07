package com.invinco.flutternative

import android.app.admin.DevicePolicyManager
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.PowerManager
import android.provider.Settings
import android.util.Log
import android.view.View
import android.view.WindowInsets
import android.view.WindowInsetsController
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.reactivex.exceptions.UndeliverableException
import io.reactivex.plugins.RxJavaPlugins

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.invinco.flutternative/bluetooth"
    private val BACKGROUND_CHANNEL = "com.invinco.flutternative/background_ble"

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // 키오스크 모드 시작
        enableKioskMode()

        // 배터리 최적화 면제 요청 (MIUI/Android Doze 방지 - 핵심!)
        requestBatteryOptimizationExemption()
    }

    override fun onResume() {
        super.onResume()
        // 앱으로 돌아올 때마다 몰입 모드 재적용
        hideSystemUI()
    }

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
                "isIgnoringBatteryOptimizations" -> {
                    val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
                    result.success(pm.isIgnoringBatteryOptimizations(packageName))
                }
                "requestBatteryOptimizationExemption" -> {
                    requestBatteryOptimizationExemption()
                    result.success(true)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    /**
     * 배터리 최적화 면제 요청
     *
     * Android Doze 모드 + MIUI 공격적 배터리 관리 대응
     * 이 설정 없으면 2시간 후 BLE 서비스가 중단됨
     */
    private fun requestBatteryOptimizationExemption() {
        try {
            val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
            if (!pm.isIgnoringBatteryOptimizations(packageName)) {
                Log.i("Battery", "배터리 최적화 면제 요청 중...")
                val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                    data = Uri.parse("package:$packageName")
                }
                startActivity(intent)
            } else {
                Log.i("Battery", "이미 배터리 최적화 면제됨")
            }
        } catch (e: Exception) {
            Log.e("Battery", "배터리 최적화 면제 요청 실패: ${e.message}", e)
        }
    }

    /**
     * 키오스크 모드 활성화
     * Device Owner로 설정된 경우 Lock Task Mode로 진입하여
     * 홈/뒤로/최근앱 버튼 모두 차단
     */
    private fun enableKioskMode() {
        val dpm = getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager
        val adminComponent = ComponentName(this, KioskDeviceAdmin::class.java)

        if (dpm.isDeviceOwnerApp(packageName)) {
            // Device Owner → Lock Task 허용 패키지 등록
            dpm.setLockTaskPackages(adminComponent, arrayOf(packageName))
            Log.i("Kiosk", "Lock Task Mode 시작")
            startLockTask()
        } else {
            Log.w("Kiosk", "Device Owner 아님 - Lock Task 불가. ADB 명령 필요:")
            Log.w("Kiosk", "adb shell dpm set-device-owner com.invinco.flutternative/.KioskDeviceAdmin")
        }

        // 화면 항상 켜짐
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
    }

    /**
     * 시스템 UI 숨기기 (상태바, 내비게이션 바)
     */
    private fun hideSystemUI() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            window.insetsController?.let {
                it.hide(WindowInsets.Type.statusBars() or WindowInsets.Type.navigationBars())
                it.systemBarsBehavior = WindowInsetsController.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
            }
        } else {
            @Suppress("DEPRECATION")
            window.decorView.systemUiVisibility = (
                View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY
                    or View.SYSTEM_UI_FLAG_FULLSCREEN
                    or View.SYSTEM_UI_FLAG_HIDE_NAVIGATION
                    or View.SYSTEM_UI_FLAG_LAYOUT_STABLE
                    or View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION
                    or View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN
            )
        }
    }

    /**
     * 뒤로 가기 버튼 차단
     */
    @Suppress("OVERRIDE_DEPRECATION")
    override fun onBackPressed() {
        // 키오스크 모드에서는 뒤로 가기 차단
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
