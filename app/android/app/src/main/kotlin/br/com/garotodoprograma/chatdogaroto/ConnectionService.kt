package br.com.garotodoprograma.chatdogaroto

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder

/**
 * Keeps the app process (and the Go core's WhatsApp connection inside it)
 * alive while the user is in other apps, for example while typing the
 * pairing code in WhatsApp on the same phone.
 *
 * When Android restarts it after ending the process, or the phone boots, it
 * connects the Go core itself, without the app on screen. Without a paired account it stops.
 *
 * The notification never shows message content or account data.
 */
class ConnectionService : Service() {
    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val notification = buildNotification()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_REMOTE_MESSAGING,
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
        // Started by the app: the Dart side already opened the session.
        // Restarted by Android (no intent) or at boot: connect from here.
        val source = if (intent == null) SOURCE_SYSTEM else intent.getStringExtra(EXTRA_SOURCE)
        if (source != null) {
            Thread {
                if (!CoreNative.resumePaired(this, source)) {
                    stopForeground(STOP_FOREGROUND_REMOVE)
                    stopSelf()
                }
            }.start()
        }
        return START_STICKY
    }

    private fun buildNotification(): Notification {
        val openApp = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_IMMUTABLE,
        )
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val manager = getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(
                NotificationChannel(CHANNEL_ID, "Conexão", NotificationManager.IMPORTANCE_LOW),
            )
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        return builder
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle("Chat do Garoto conectado")
            .setContentIntent(openApp)
            .setOngoing(true)
            .build()
    }

    companion object {
        const val EXTRA_SOURCE = "source"
        const val SOURCE_SYSTEM = "system"
        const val SOURCE_BOOT = "boot"
        private const val CHANNEL_ID = "connection"
        private const val NOTIFICATION_ID = 1
    }
}
