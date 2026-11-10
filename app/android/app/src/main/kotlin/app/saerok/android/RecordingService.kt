package app.saerok.android

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.util.Log

// 면회 녹음을 하는 동안 띄우는 마이크 포그라운드 서비스(`lib/features/visit/recording_service.dart`).
//
// 녹음은 `record` 플러그인이 하고, 이 서비스는 알림 하나를 띄워 두기만 한다. 서비스가
// 떠 있으면 화면을 끄거나 다른 앱으로 옮겨도 안드로이드가 마이크를 막지 않고 앱
// 프로세스를 정리하지 않는다. 안드로이드 14 이상은 매니페스트의
// `foregroundServiceType="microphone"`, `FOREGROUND_SERVICE_MICROPHONE` 권한과 이미 받은
// `RECORD_AUDIO` 가 있어야 띄울 수 있고, 앱이 앞에 있을 때만 띄울 수 있다. 그래서
// 녹음 버튼을 누른 직후에 띄운다.
//
// 알림 문구는 Dart 가 정해 넘긴다. 다시 띄우지 않으므로(`START_NOT_STICKY`) 앱이 죽으면
// 알림도 함께 사라진다.
class RecordingService : Service() {
    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val notification = buildNotification(
            this,
            title = intent?.getStringExtra(EXTRA_TITLE) ?: DEFAULT_TITLE,
            text = intent?.getStringExtra(EXTRA_TEXT) ?: "",
        )
        try {
            // 마이크 유형은 안드로이드 11(API 30)에 생겼다. 그 아래는 매니페스트의 유형을 쓴다.
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                startForeground(
                    NOTIFICATION_ID,
                    notification,
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE,
                )
            } else {
                startForeground(NOTIFICATION_ID, notification)
            }
            running = true
        } catch (e: Exception) {
            // 안드로이드 12 이상에서 뒤에 있을 때 띄우려 했거나(ForegroundServiceStartNotAllowedException),
            // 14 이상에서 마이크 권한이 없을 때(SecurityException)다. 녹음은 앱이 앞에 있는 동안
            // 그대로 이어진다.
            Log.w(TAG, "녹음 알림 서비스를 띄우지 못했다", e)
            running = false
            stopSelf()
        }
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        running = false
        super.onDestroy()
    }

    companion object {
        private const val TAG = "RecordingService"
        private const val CHANNEL_ID = "visit_recording"
        private const val NOTIFICATION_ID = 7301
        private const val EXTRA_TITLE = "title"
        private const val EXTRA_TEXT = "text"
        private const val DEFAULT_TITLE = "면회를 녹음하고 있어요"

        // 서비스가 알림을 띄운 채 떠 있는지. 떠 있으면 알림 문구만 바꾼다.
        @Volatile
        private var running = false

        // 서비스를 띄운다. 이미 떠 있으면 알림 문구만 바꾼다. 띄우기를 요청하지
        // 못했으면 `false` 다.
        fun show(context: Context, title: String, text: String): Boolean {
            createChannel(context)
            if (running) {
                // 알림 문구를 바꿀 때는 서비스를 다시 시작하지 않고 같은 번호로 다시 올린다.
                context.getSystemService(NotificationManager::class.java)
                    .notify(NOTIFICATION_ID, buildNotification(context, title, text))
                return true
            }
            val intent = Intent(context, RecordingService::class.java)
                .putExtra(EXTRA_TITLE, title)
                .putExtra(EXTRA_TEXT, text)
            return try {
                context.startForegroundService(intent)
                true
            } catch (e: Exception) {
                Log.w(TAG, "녹음 알림 서비스를 시작하지 못했다", e)
                false
            }
        }

        // 서비스와 알림을 내린다. 떠 있지 않으면 아무 일도 하지 않는다.
        fun hide(context: Context) {
            running = false
            context.stopService(Intent(context, RecordingService::class.java))
        }

        // 녹음하는 동안 소리나 진동이 나면 그 소리가 녹음에 남는다. 그래서 소리 없는
        // 낮은 중요도로 만든다. 이미 있으면 그대로 둔다. minSdk 26 이라 버전을 확인하지 않는다.
        private fun createChannel(context: Context) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "면회 녹음",
                NotificationManager.IMPORTANCE_LOW,
            ).apply {
                description = "면회를 녹음하는 동안 보여요"
                setShowBadge(false)
            }
            context.getSystemService(NotificationManager::class.java)
                .createNotificationChannel(channel)
        }

        private fun buildNotification(
            context: Context,
            title: String,
            text: String,
        ): Notification {
            // 알림을 누르면 런처 아이콘을 누른 것처럼 녹음 화면이 있는 앱으로 돌아간다.
            val launch = context.packageManager.getLaunchIntentForPackage(context.packageName)
                ?: Intent(context, MainActivity::class.java)
            val open = PendingIntent.getActivity(
                context,
                0,
                launch,
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
            )
            val builder = Notification.Builder(context, CHANNEL_ID)
                .setSmallIcon(R.drawable.ic_recording_notification)
                .setContentTitle(title)
                .setContentIntent(open)
                .setCategory(Notification.CATEGORY_SERVICE)
                .setOngoing(true)
                .setOnlyAlertOnce(true)
                .setShowWhen(false)
            if (text.isNotEmpty()) builder.setContentText(text)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                // 안드로이드 12 이상은 포그라운드 서비스 알림을 최대 10초 늦게 보일 수 있다.
                // 녹음 중이라는 것은 바로 보여야 한다.
                builder.setForegroundServiceBehavior(Notification.FOREGROUND_SERVICE_IMMEDIATE)
            }
            return builder.build()
        }
    }
}
