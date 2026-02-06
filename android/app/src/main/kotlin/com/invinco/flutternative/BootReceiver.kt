package com.invinco.flutternative

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

/**
 * 부팅 완료 시 BLE 포그라운드 서비스를 자동 시작하는 리시버
 *
 * BOOT_COMPLETED 브로드캐스트를 수신하여
 * BleForegroundService를 시작합니다.
 * 서비스 내에서 헤드리스 FlutterEngine이 생성되어
 * Dart BLE 로직이 백그라운드에서 실행됩니다.
 */
class BootReceiver : BroadcastReceiver() {

    companion object {
        private const val TAG = "BootReceiver"
    }

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == Intent.ACTION_BOOT_COMPLETED) {
            Log.i(TAG, "부팅 완료 감지 - BLE 포그라운드 서비스 시작")
            BleForegroundService.start(context)
        }
    }
}
