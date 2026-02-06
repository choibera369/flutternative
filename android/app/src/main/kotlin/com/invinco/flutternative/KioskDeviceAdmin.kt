package com.invinco.flutternative

import android.app.admin.DeviceAdminReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

/**
 * 키오스크 모드용 Device Admin Receiver
 *
 * ADB로 Device Owner 설정 후 Lock Task Mode 활성화:
 * adb shell dpm set-device-owner com.invinco.flutternative/.KioskDeviceAdmin
 */
class KioskDeviceAdmin : DeviceAdminReceiver() {
    companion object {
        private const val TAG = "KioskDeviceAdmin"
    }

    override fun onEnabled(context: Context, intent: Intent) {
        Log.i(TAG, "Device Admin 활성화됨")
    }

    override fun onDisabled(context: Context, intent: Intent) {
        Log.i(TAG, "Device Admin 비활성화됨")
    }
}
