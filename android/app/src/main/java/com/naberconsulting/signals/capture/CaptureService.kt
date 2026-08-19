package com.naberconsulting.signals.capture

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import com.naberconsulting.signals.SignalsApp

/**
 * Foreground service that keeps the capture pipeline alive while the app is
 * backgrounded -- the Android analogue to the iOS background-capture upgrade.
 * A persistent notification is mandatory for a location foreground service.
 */
class CaptureService : Service() {

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        startInForeground()
        SignalsApp.controllerOf(application).start()
        return START_STICKY
    }

    override fun onDestroy() {
        SignalsApp.controllerOf(application).stop()
        super.onDestroy()
    }

    private fun startInForeground() {
        val channelId = ensureChannel()
        val notification: Notification = Notification.Builder(this, channelId)
            .setContentTitle("Signals")
            .setContentText("Capturing location and radio signals")
            .setSmallIcon(android.R.drawable.ic_menu_mylocation)
            .setOngoing(true)
            .build()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION)
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    private fun ensureChannel(): String {
        val manager = getSystemService(NotificationManager::class.java)
        val channel = NotificationChannel(
            CHANNEL_ID, "Capture", NotificationManager.IMPORTANCE_LOW
        )
        manager.createNotificationChannel(channel)
        return CHANNEL_ID
    }

    companion object {
        private const val CHANNEL_ID = "capture"
        private const val NOTIFICATION_ID = 1

        fun start(context: Context) {
            val intent = Intent(context, CaptureService::class.java)
            context.startForegroundService(intent)
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, CaptureService::class.java))
        }
    }
}
