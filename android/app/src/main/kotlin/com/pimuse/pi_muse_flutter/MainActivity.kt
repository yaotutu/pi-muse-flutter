package com.pimuse.pi_muse_flutter

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private var attachmentPicker: AttachmentPicker? = null
    private var smsSync: SmsSyncChannel? = null
    private var appUpdate: AppUpdateChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        attachmentPicker = AttachmentPicker(this, messenger)
        smsSync = SmsSyncChannel(this, messenger)
        appUpdate = AppUpdateChannel(this, messenger)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        attachmentPicker?.close()
        attachmentPicker = null
        smsSync?.close()
        smsSync = null
        appUpdate?.close()
        appUpdate = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    override fun onResume() {
        super.onResume()
        smsSync?.onResume()
    }

    override fun onPause() {
        smsSync?.onPause()
        super.onPause()
    }

    @Suppress("DEPRECATION", "OVERRIDE_DEPRECATION")
    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        when (requestCode) {
            SMS_PERMISSION_REQUEST -> smsSync?.onPermissionResult()
            SMS_HISTORY_PERMISSION_REQUEST -> smsSync?.onHistoryPermissionResult()
        }
    }

    @Suppress("DEPRECATION", "OVERRIDE_DEPRECATION")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode == ATTACHMENT_PICK_REQUEST_CODE) {
            attachmentPicker?.onActivityResult(resultCode, data)
            return
        }
        super.onActivityResult(requestCode, resultCode, data)
    }
}
