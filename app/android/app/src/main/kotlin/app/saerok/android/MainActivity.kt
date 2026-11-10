package app.saerok.android

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.ActivityNotFoundException
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var screenAwakeChannel: MethodChannel? = null
    private var recordingServiceChannel: MethodChannel? = null

    // 알림 권한 창의 답을 기다리는 요청들. 창은 한 번만 띄우고 답을 모두에게 준다.
    private val notificationPermissionResults = mutableListOf<MethodChannel.Result>()
    private var micSettingsChannel: MethodChannel? = null

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

        // 새 엔진에는 녹음 중인 면회가 없다. 앞 엔진이 남긴 녹음 알림을 내린다.
        RecordingService.hide(this)
        recordingServiceChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            RECORDING_SERVICE_CHANNEL,
        ).also { channel ->
            channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    SHOW_RECORDING -> {
                        val title = call.argument<String>("title")
                        val text = call.argument<String>("text")
                        // 녹음이 멈췄을 때만 소리와 진동이 나는 알림으로 올린다.
                        val alert = call.argument<Boolean>("alert") ?: false
                        if (title == null || text == null) {
                            result.error("BAD_ARGUMENT", "title 이나 text 값이 없다", null)
                        } else {
                            result.success(RecordingService.show(this, title, text, alert))
                        }
                    }
                    HIDE_RECORDING -> {
                        RecordingService.hide(this)
                        result.success(null)
                    }
                    REQUEST_NOTIFICATION_PERMISSION -> requestNotificationPermission(result)
                    else -> result.notImplemented()
                }
            }
        }
        micSettingsChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            MIC_SETTINGS_CHANNEL,
        ).also { channel ->
            channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    OPEN_APP_SETTINGS -> result.success(openAppSettings())
                    IS_MIC_PERMANENTLY_DENIED ->
                        result.success(isMicPermanentlyDenied())
                    else -> result.notImplemented()
                }
            }
        }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        // 앱이 엔진을 놓으면 녹음 화면도 없다. 화면을 기기 설정으로 되돌린다.
        screenAwakeChannel?.setMethodCallHandler(null)
        screenAwakeChannel = null
        micSettingsChannel?.setMethodCallHandler(null)
        micSettingsChannel = null
        setKeepScreenOn(false)
        // 엔진과 함께 녹음도 멈춘다. 녹음 알림이 남지 않게 내린다.
        recordingServiceChannel?.setMethodCallHandler(null)
        recordingServiceChannel = null
        RecordingService.hide(this)
        finishNotificationPermission(false)
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

    // 녹음 알림이 보이도록 알림 권한을 묻는다(`lib/features/visit/recording_service.dart`).
    // 안드로이드 12 이하는 권한 없이 보이고, 이미 받았으면 묻지 않는다. 거절해도 녹음과
    // 서비스는 그대로이며 알림만 알림창에 보이지 않는다.
    private fun requestNotificationPermission(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED
        ) {
            result.success(true)
            return
        }
        notificationPermissionResults.add(result)
        if (notificationPermissionResults.size > 1) return
        requestPermissions(
            arrayOf(Manifest.permission.POST_NOTIFICATIONS),
            NOTIFICATION_PERMISSION_REQUEST,
        )
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<String>,
        grantResults: IntArray,
    ) {
        // 다른 플러그인(마이크, 푸시)의 권한 창 답은 FlutterActivity 가 넘겨준다.
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != NOTIFICATION_PERMISSION_REQUEST) return
        finishNotificationPermission(
            grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED,
        )
    }

    private fun finishNotificationPermission(granted: Boolean) {
        val waiting = notificationPermissionResults.toList()
        notificationPermissionResults.clear()
        waiting.forEach { it.success(granted) }
    }

    // 휴대전화 설정의 새록 앱 정보 화면을 연다(`lib/app/mic_settings.dart`).
    // 보호자는 여기서 권한을 눌러 마이크를 켠다. 열 화면이 없으면 false 다.
    private fun openAppSettings(): Boolean {
        val intent = Intent(
            Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
            Uri.fromParts("package", packageName, null),
        )
        return try {
            startActivity(intent)
            true
        } catch (e: ActivityNotFoundException) {
            false
        }
    }

    // 마이크 권한이 없고 안드로이드가 권한 창을 더 띄우지 않는 상태인지.
    // 거부된 뒤에 안내가 필요 없다고(shouldShowRequestPermissionRationale 가
    // false) 하면 다시 물어도 창 없이 바로 거부된다. 한 번도 묻지 않았을 때도
    // false 이므로 `record` 가 권한을 물어 거부된 뒤에만 부른다.
    private fun isMicPermanentlyDenied(): Boolean {
        val granted = checkSelfPermission(Manifest.permission.RECORD_AUDIO) ==
            PackageManager.PERMISSION_GRANTED
        return !granted &&
            !shouldShowRequestPermissionRationale(Manifest.permission.RECORD_AUDIO)
    }

    private companion object {
        // Dart 의 `MethodChannelScreenAwake.channel`, `.method` 와 같아야 한다.
        const val SCREEN_AWAKE_CHANNEL = "app.saerok.android/screen_awake"
        const val SET_KEEP_SCREEN_ON = "setKeepScreenOn"
        // Dart 의 `MethodChannelMicSettings` 의 채널과 메서드 이름과 같아야 한다.
        const val MIC_SETTINGS_CHANNEL = "app.saerok.android/mic_settings"
        const val OPEN_APP_SETTINGS = "openAppSettings"
        const val IS_MIC_PERMANENTLY_DENIED = "isMicPermanentlyDenied"
        const val REPORT_CHANNEL_ID = "report_ready"

        // Dart 의 `MethodChannelRecordingService` 와 같아야 한다.
        const val RECORDING_SERVICE_CHANNEL = "app.saerok.android/recording_service"
        const val SHOW_RECORDING = "show"
        const val HIDE_RECORDING = "hide"
        const val REQUEST_NOTIFICATION_PERMISSION = "requestNotificationPermission"

        // 다른 플러그인의 권한 요청 번호(record 1001 등)와 겹치지 않게 고른 값이다.
        const val NOTIFICATION_PERMISSION_REQUEST = 7302
    }
}
