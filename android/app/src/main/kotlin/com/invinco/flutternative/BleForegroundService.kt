package com.invinco.flutternative

import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import android.os.SystemClock
import android.util.Log
import androidx.core.app.NotificationCompat
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugins.GeneratedPluginRegistrant

/**
 * BLE 백그라운드 스캔을 위한 포그라운드 서비스
 *
 * Android 8.0 이상에서 백그라운드 BLE 스캔을 유지하려면
 * 포그라운드 서비스가 필요합니다.
 *
 * 부팅 시 BootReceiver에 의해 시작되면 헤드리스 FlutterEngine을
 * 생성하여 Dart backgroundMain() 엔트리포인트를 실행합니다.
 * UI 없이 BLE 로직만 백그라운드에서 동작합니다.
 *
 * 2시간 후 BLE 끊김 방지:
 * - PARTIAL_WAKE_LOCK: CPU가 깊은 절전 모드 진입 방지
 * - AlarmManager: 30분마다 서비스 재시작 (안전망)
 * - Doze 모드 대응: 배터리 최적화 면제 요청
 */
class BleForegroundService : Service() {

    companion object {
        private const val TAG = "BleForegroundService"
        private const val CHANNEL_ID = "ble_foreground_channel"
        private const val NOTIFICATION_ID = 1001
        private const val CHANNEL_NAME = "건강 기기 연결"
        private const val BACKGROUND_CHANNEL_NAME = "com.invinco.flutternative/background_ble"
        private const val RESTART_ALARM_REQUEST_CODE = 2001
        private const val RESTART_INTERVAL_MS = 30 * 60 * 1000L // 30분

        fun start(context: Context) {
            val intent = Intent(context, BleForegroundService::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun stop(context: Context) {
            val intent = Intent(context, BleForegroundService::class.java)
            context.stopService(intent)
        }
    }

    private var flutterEngine: FlutterEngine? = null
    private var wakeLock: PowerManager.WakeLock? = null

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
        acquireWakeLock()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val notification = createNotification()
        startForeground(NOTIFICATION_ID, notification)

        // 헤드리스 FlutterEngine이 아직 없으면 생성
        if (flutterEngine == null) {
            startHeadlessFlutterEngine()
        }

        // AlarmManager로 주기적 재시작 예약 (안전망)
        scheduleRestart()

        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? {
        return null
    }

    override fun onDestroy() {
        Log.i(TAG, "서비스 종료 - FlutterEngine 정리")
        cancelRestart()
        releaseWakeLock()
        flutterEngine?.destroy()
        flutterEngine = null
        super.onDestroy()
    }

    /**
     * PARTIAL_WAKE_LOCK 획득 - CPU가 깊은 절전 모드 진입 방지
     * Doze 모드에서도 BLE 스캔이 계속되도록 보장
     */
    private fun acquireWakeLock() {
        try {
            val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
            wakeLock = pm.newWakeLock(
                PowerManager.PARTIAL_WAKE_LOCK,
                "flutternative:ble_scan_lock"
            ).apply {
                acquire()  // 서비스 종료 시 release
            }
            Log.i(TAG, "WakeLock 획득 완료")
        } catch (e: Exception) {
            Log.e(TAG, "WakeLock 획득 실패: ${e.message}", e)
        }
    }

    /**
     * Wake Lock 해제
     */
    private fun releaseWakeLock() {
        try {
            wakeLock?.let {
                if (it.isHeld) {
                    it.release()
                    Log.i(TAG, "WakeLock 해제 완료")
                }
            }
            wakeLock = null
        } catch (e: Exception) {
            Log.e(TAG, "WakeLock 해제 실패: ${e.message}", e)
        }
    }

    /**
     * AlarmManager로 30분마다 서비스 재시작 예약 (안전망)
     * Android가 서비스를 죽여도 AlarmManager가 다시 깨움
     */
    private fun scheduleRestart() {
        try {
            val alarmManager = getSystemService(Context.ALARM_SERVICE) as AlarmManager
            val restartIntent = Intent(this, BleForegroundService::class.java)
            val pendingIntent = PendingIntent.getService(
                this,
                RESTART_ALARM_REQUEST_CODE,
                restartIntent,
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
            )

            // setInexactRepeating → Doze 모드에서도 비교적 잘 동작
            alarmManager.setInexactRepeating(
                AlarmManager.ELAPSED_REALTIME_WAKEUP,
                SystemClock.elapsedRealtime() + RESTART_INTERVAL_MS,
                RESTART_INTERVAL_MS,
                pendingIntent
            )
            Log.i(TAG, "AlarmManager 재시작 예약 완료 (30분 간격)")
        } catch (e: Exception) {
            Log.e(TAG, "AlarmManager 예약 실패: ${e.message}", e)
        }
    }

    /**
     * AlarmManager 예약 취소
     */
    private fun cancelRestart() {
        try {
            val alarmManager = getSystemService(Context.ALARM_SERVICE) as AlarmManager
            val restartIntent = Intent(this, BleForegroundService::class.java)
            val pendingIntent = PendingIntent.getService(
                this,
                RESTART_ALARM_REQUEST_CODE,
                restartIntent,
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
            )
            alarmManager.cancel(pendingIntent)
            Log.i(TAG, "AlarmManager 재시작 예약 취소")
        } catch (e: Exception) {
            Log.e(TAG, "AlarmManager 취소 실패: ${e.message}", e)
        }
    }

    /**
     * 헤드리스 FlutterEngine 생성 및 backgroundMain Dart 엔트리포인트 실행
     *
     * UI 없이 Dart BLE 로직만 실행합니다.
     * flutter_reactive_ble 등 플러그인이 등록되어 BLE 통신이 가능합니다.
     */
    private fun startHeadlessFlutterEngine() {
        try {
            Log.i(TAG, "헤드리스 FlutterEngine 생성 시작")

            val engine = FlutterEngine(this)

            // 플러그인 등록 (flutter_reactive_ble, permission_handler 등)
            GeneratedPluginRegistrant.registerWith(engine)

            // background_ble MethodChannel 설정 (getBondedDevices 등)
            setupMethodChannel(engine)

            // backgroundMain Dart 엔트리포인트 실행
            val appBundlePath = FlutterInjector.instance().flutterLoader().findAppBundlePath()
            engine.dartExecutor.executeDartEntrypoint(
                DartExecutor.DartEntrypoint(appBundlePath, "backgroundMain")
            )

            flutterEngine = engine
            Log.i(TAG, "헤드리스 FlutterEngine 시작 완료 - backgroundMain 실행됨")
        } catch (e: Exception) {
            Log.e(TAG, "헤드리스 FlutterEngine 생성 실패: ${e.message}", e)
        }
    }

    /**
     * 헤드리스 FlutterEngine용 MethodChannel 설정
     *
     * Dart 측 BackgroundBleService가 사용하는 플랫폼 채널을 등록합니다.
     * - getBondedDevices: 페어링된 블루투스 기기 목록 반환
     * - startForegroundService / stopForegroundService: 서비스 제어
     * - isIgnoringBatteryOptimizations: 배터리 최적화 면제 확인
     */
    private fun setupMethodChannel(engine: FlutterEngine) {
        MethodChannel(engine.dartExecutor.binaryMessenger, BACKGROUND_CHANNEL_NAME)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getBondedDevices" -> {
                        try {
                            val bondedDevices = getBondedDevices()
                            result.success(bondedDevices)
                        } catch (e: Exception) {
                            result.error("BLUETOOTH_ERROR", e.message, null)
                        }
                    }
                    "startForegroundService" -> {
                        // 이미 실행 중이므로 성공 반환
                        result.success(true)
                    }
                    "stopForegroundService" -> {
                        try {
                            stopSelf()
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("SERVICE_ERROR", e.message, null)
                        }
                    }
                    "isIgnoringBatteryOptimizations" -> {
                        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
                        result.success(pm.isIgnoringBatteryOptimizations(packageName))
                    }
                    else -> {
                        result.notImplemented()
                    }
                }
            }
    }

    /**
     * 페어링된 블루투스 기기 목록 반환
     */
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
            Log.w(TAG, "블루투스 권한 부족: ${e.message}")
            emptyList()
        }
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                CHANNEL_NAME,
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "건강 기기 자동 연결 서비스"
                setShowBadge(false)
            }

            val notificationManager = getSystemService(NotificationManager::class.java)
            notificationManager.createNotificationChannel(channel)
        }
    }

    private fun createNotification(): Notification {
        // 앱을 열기 위한 PendingIntent
        val pendingIntent = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_SINGLE_TOP
            },
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("건강 기기 연결 대기 중")
            .setContentText("혈압계 측정 결과를 자동으로 수신합니다")
            .setSmallIcon(android.R.drawable.stat_sys_data_bluetooth)
            .setOngoing(true)
            .setContentIntent(pendingIntent)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .build()
    }
}
