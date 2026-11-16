package com.lhht.ai_assistant

import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.lhht.ai_assistant/system_action"
    private lateinit var actionExecutor: AssistantActionExecutor

    override fun onCreate(savedInstanceState: Bundle?) {
        // Bỏ qua lỗi chứng chỉ SSL trên Android 7.1.1 cũ (Samsung Galaxy J2 Pro)
        UnsafeSslHelper.enableUnsafeSsl()

        super.onCreate(savedInstanceState)
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)

        actionExecutor = AssistantActionExecutor(applicationContext)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "openGoogleMaps" -> {
                    val destination = call.argument<String>("destination") ?: ""
                    result.success(actionExecutor.openGoogleMaps(destination))
                }
                "openYouTube" -> {
                    val query = call.argument<String>("query") ?: ""
                    result.success(actionExecutor.openYouTube(query))
                }
                "openApp" -> {
                    val appName = call.argument<String>("appName") ?: ""
                    result.success(actionExecutor.openApp(appName))
                }
                "makePhoneCall" -> {
                    val phoneNumber = call.argument<String>("phoneNumber") ?: ""
                    result.success(actionExecutor.makePhoneCall(phoneNumber))
                }
                "setVolume" -> {
                    val level = call.argument<Int>("level") ?: 50
                    result.success(actionExecutor.setVolume(level))
                }
                "adjustVolume" -> {
                    val up = call.argument<Boolean>("up") ?: true
                    result.success(actionExecutor.adjustVolume(up))
                }
                "toggleFlashlight" -> {
                    val state = call.argument<Boolean>("state") ?: false
                    result.success(actionExecutor.toggleFlashlight(state))
                }
                "openWifiSettings" -> {
                    result.success(actionExecutor.openWifiSettings())
                }
                "openBluetoothSettings" -> {
                    result.success(actionExecutor.openBluetoothSettings())
                }
                "getSystemStatus" -> {
                    result.success(actionExecutor.getSystemStatus())
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    override fun onResume() {
        super.onResume()
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
    }
}
