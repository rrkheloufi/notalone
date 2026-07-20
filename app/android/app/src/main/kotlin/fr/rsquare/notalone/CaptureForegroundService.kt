package fr.rsquare.notalone

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder

/**
 * Foreground service de type `microphone`. Il ne capte rien lui-même : sans un
 * service de ce type, Android retire simplement le micro à l'app dès qu'elle
 * passe en arrière-plan (cf. cowork/02-architecture.md §8). La capture continue
 * de tourner dans l'isolate Dart principal ; ce service ne fait que donner au
 * processus le statut « premier plan » aux yeux du système.
 */
class CaptureForegroundService : Service() {

    companion object {
        const val CHANNEL_ID = "notalone_capture"
        const val NOTIFICATION_ID = 1001
        const val EXTRA_TITLE = "title"
        const val EXTRA_TEXT = "text"
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val title = intent?.getStringExtra(EXTRA_TITLE).orEmpty()
        val text = intent?.getStringExtra(EXTRA_TEXT).orEmpty()
        createChannel(title)
        val notification = buildNotification(title, text)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE,
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }

        // Rien à relancer sans l'app : la capture vit dans l'isolate Dart, un
        // service ressuscité seul ne capterait rien.
        return START_NOT_STICKY
    }

    private fun createChannel(title: String) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val channel = NotificationChannel(
            CHANNEL_ID,
            title.ifEmpty { getString(applicationInfo.labelRes) },
            // Discrète : elle informe que le micro est actif, elle ne réclame
            // pas d'attention pendant le repas.
            NotificationManager.IMPORTANCE_LOW,
        )
        channel.setShowBadge(false)
        getSystemService(NotificationManager::class.java)
            ?.createNotificationChannel(channel)
    }

    private fun buildNotification(title: String, text: String): Notification {
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        return builder
            .setContentTitle(title)
            .setContentText(text)
            .setSmallIcon(android.R.drawable.ic_btn_speak_now)
            .setOngoing(true)
            .build()
    }
}
