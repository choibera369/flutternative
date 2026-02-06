package com.invinco.flutternative

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

/**
 * 부팅 완료 시 앱을 자동 시작하는 리시버
 *
 * 1. BLE 포그라운드 서비스 시작 (백그라운드 BLE 스캔)
 * 2. MainActivity 실행 (키오스크 모드 UI)
 */
class BootReceiver : BroadcastReceiver() {

    companion object {
        private const val TAG = "BootReceiver"
    }

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == Intent.ACTION_BOOT_COMPLETED) {
            Log.i(TAG, "부팅 완료 감지 - 앱 자동 시작")

            // 1. BLE 포그라운드 서비스 시작
            BleForegroundService.start(context)

            // 2. MainActivity (키오스크 UI) 실행
            val launchIntent = Intent(context, MainActivity::class.java).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP)
            }
            context.startActivity(launchIntent)
            Log.i(TAG, "MainActivity 실행됨")
        }
    }
}
