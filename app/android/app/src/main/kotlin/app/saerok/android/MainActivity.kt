package app.saerok.android

import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var screenAwakeChannel: MethodChannel? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        createReportChannel()
    }

    // 리포트 완료 푸시가 쓰는 알림 채널. AndroidManifest.xml 의
    // `default_notification_channel_id` 와 같은 ID 다. 이미 있으면 그대로 둔다.
    // minSdk 26 이라 버전을 따로 확인하지 않는다.
    private fun createReportChannel() {
        val channel = NotificationChannel(
            REPORT_CHANNEL_ID,
            "리포트 알림",
            NotificationManager.IMPORTANCE_DEFAULT,
        ).apply { description = "면회 리포트가 준비되면 알려요" }
        getSystemService(NotificationManager::class.java)
            .createNotificationChannel(channel)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // 새 엔진에는 화면을 켜 두라고 한 곳이 없다. 앞 엔진이 남긴 표시를 지운다.
        setKeepScreenOn(false)
        screenAwakeChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            SCREEN_AWAKE_CHANNEL,
        ).also { channel ->
            channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    SET_KEEP_SCREEN_ON -> {
                        val on = call.argument<Boolean>("on")
                        if (on == null) {
                            result.error("BAD_ARGUMENT", "on 값이 없다", null)
                        } else {
                            setKeepScreenOn(on)
                            result.success(null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        // 앱이 엔진을 놓으면 녹음 화면도 없다. 화면을 기기 설정으로 되돌린다.
        screenAwakeChannel?.setMethodCallHandler(null)
        screenAwakeChannel = null
        setKeepScreenOn(false)
        super.cleanUpFlutterEngine(flutterEngine)
    }

    // 녹음하는 동안 화면이 저절로 꺼지지 않게 한다(`lib/app/screen_awake.dart`).
    // 창 표시만 바꾸므로 WAKE_LOCK 권한이 필요 없고, 창이 사라지면 함께 사라진다.
    private fun setKeepScreenOn(on: Boolean) {
        if (on) {
            window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        } else {
            window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        }
    }

    private companion object {
        // Dart 의 `MethodChannelScreenAwake.channel`, `.method` 와 같아야 한다.
        const val SCREEN_AWAKE_CHANNEL = "app.saerok.android/screen_awake"
        const val SET_KEEP_SCREEN_ON = "setKeepScreenOn"
        const val REPORT_CHANNEL_ID = "report_ready"
    }
}
