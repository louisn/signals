package com.naberconsulting.signals

import android.Manifest
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.widget.Toast
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import com.naberconsulting.signals.capture.CaptureController
import com.naberconsulting.signals.capture.CaptureService
import com.naberconsulting.signals.ui.CaptureScreen

class MainActivity : ComponentActivity() {

    private lateinit var controller: CaptureController

    private val permissionLauncher =
        registerForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) {
            // Capture starts regardless; ungranted permissions just mean the
            // corresponding capturer no-ops (guarded per-capturer).
            CaptureService.start(this)
        }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        controller = (application as SignalsApp).controller

        handleConnectLink(intent)

        setContent {
            MaterialTheme {
                Surface {
                    CaptureScreen(
                        controller = controller,
                        onToggleCapture = { shouldCapture ->
                            if (shouldCapture) requestPermissionsThenStart()
                            else CaptureService.stop(this)
                        },
                        onSyncNow = { controller.syncNow() },
                    )
                }
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleConnectLink(intent)
    }

    /** Adopts a scanned `signals://connect` credential; ignores any other intent. */
    private fun handleConnectLink(intent: Intent?) {
        val uri: Uri = intent?.data ?: return
        if (uri.scheme != "signals" || uri.host != "connect") return

        val base = uri.getQueryParameter("base")
        val deviceId = uri.getQueryParameter("device_id")
        val key = uri.getQueryParameter("key")
        if (base.isNullOrBlank() || deviceId.isNullOrBlank() || key.isNullOrBlank()) {
            Toast.makeText(this, "Invalid connection QR", Toast.LENGTH_LONG).show()
            return
        }
        controller.applyConnection(base, deviceId, key)
        Toast.makeText(this, "Device connected", Toast.LENGTH_LONG).show()
    }

    private fun requestPermissionsThenStart() {
        val permissions = buildList {
            add(Manifest.permission.ACCESS_FINE_LOCATION)
            add(Manifest.permission.ACCESS_COARSE_LOCATION)
            add(Manifest.permission.READ_PHONE_STATE)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                add(Manifest.permission.BLUETOOTH_SCAN)
                add(Manifest.permission.BLUETOOTH_CONNECT)
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                add(Manifest.permission.NEARBY_WIFI_DEVICES)
                add(Manifest.permission.POST_NOTIFICATIONS)
            }
        }
        permissionLauncher.launch(permissions.toTypedArray())
    }
}
