package com.lhht.ai_assistant

import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.hardware.camera2.CameraManager
import android.media.AudioManager
import android.net.Uri
import android.os.BatteryManager
import android.os.Build
import android.provider.Settings
import android.util.Log
import java.text.Normalizer
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.regex.Pattern

class AssistantActionExecutor(private val context: Context) {

    companion object {
        private const val TAG = "AssistantActionExecutor"
    }

    private fun safeStartActivity(intent: Intent): Boolean {
        return try {
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            context.startActivity(intent)
            true
        } catch (e: Exception) {
            Log.e(TAG, "Error starting activity for intent: $intent", e)
            false
        }
    }

    /**
     * 1. Chỉ đường / Tìm địa điểm trên Google Maps (OPEN_MAP)
     */
    fun openGoogleMaps(destination: String): Map<String, Any> {
        val cleanDest = destination.trim()
        if (cleanDest.isEmpty()) {
            return mapOf("success" to false, "message" to "Địa điểm trống")
        }

        try {
            // Cách 1: Chỉ đường trực tiếp qua Google Maps Navigation
            val navUri = Uri.parse("google.navigation:q=" + Uri.encode(cleanDest))
            val mapIntent = Intent(Intent.ACTION_VIEW, navUri).apply {
                setPackage("com.google.android.apps.maps")
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            if (safeStartActivity(mapIntent)) {
                return mapOf("success" to true, "action" to "OPEN_MAP", "target" to cleanDest)
            }
        } catch (e: Exception) {
            Log.w(TAG, "Cannot launch google.navigation, trying geo search", e)
        }

        try {
            // Cách 2: Geo search
            val geoUri = Uri.parse("geo:0,0?q=" + Uri.encode(cleanDest))
            val geoIntent = Intent(Intent.ACTION_VIEW, geoUri).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            if (safeStartActivity(geoIntent)) {
                return mapOf("success" to true, "action" to "OPEN_MAP", "target" to cleanDest)
            }
        } catch (e: Exception) {
            Log.w(TAG, "Cannot launch geo intent, trying browser", e)
        }

        // Cách 3: Fallback mở trình duyệt web
        try {
            val webUri = Uri.parse("https://www.google.com/maps/search/?api=1&query=" + Uri.encode(cleanDest))
            val webIntent = Intent(Intent.ACTION_VIEW, webUri).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            if (safeStartActivity(webIntent)) {
                return mapOf("success" to true, "action" to "OPEN_MAP_WEB", "target" to cleanDest)
            }
        } catch (e: Exception) {
            Log.e(TAG, "All map intents failed", e)
        }

        return mapOf("success" to false, "message" to "Không thể mở Google Maps hoặc trình duyệt")
    }

    /**
     * 2. Tìm và phát video/nhạc trên YouTube (OPEN_YOUTUBE)
     */
    fun openYouTube(query: String): Map<String, Any> {
        val cleanQuery = query.trim()
        if (cleanQuery.isEmpty()) {
            return mapOf("success" to false, "message" to "Từ khóa tìm kiếm YouTube trống")
        }

        try {
            // Cách 1: Intent ACTION_SEARCH đến com.google.android.youtube
            val intent = Intent(Intent.ACTION_SEARCH).apply {
                setPackage("com.google.android.youtube")
                putExtra("query", cleanQuery)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            if (safeStartActivity(intent)) {
                return mapOf("success" to true, "action" to "OPEN_YOUTUBE", "target" to cleanQuery)
            }
        } catch (e: Exception) {
            Log.w(TAG, "Cannot open YouTube app search, trying web URL", e)
        }

        // Cách 2: Fallback URL web YouTube (app YouTube cũng có thể bắt URL này hoặc mở bằng browser)
        try {
            val ytUri = Uri.parse("https://www.youtube.com/results?search_query=" + Uri.encode(cleanQuery))
            val ytIntent = Intent(Intent.ACTION_VIEW, ytUri).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            if (safeStartActivity(ytIntent)) {
                return mapOf("success" to true, "action" to "OPEN_YOUTUBE_WEB", "target" to cleanQuery)
            }
        } catch (e: Exception) {
            Log.e(TAG, "YouTube intent failed", e)
        }

        return mapOf("success" to false, "message" to "Không thể mở YouTube")
    }

    private fun normalizeString(input: String): String {
        val nfd = Normalizer.normalize(input, Normalizer.Form.NFD)
        val pattern = Pattern.compile("\\p{InCombiningDiacriticalMarks}+")
        return pattern.matcher(nfd).replaceAll("").lowercase(Locale.ROOT).replace("đ", "d")
    }

    /**
     * 3. Mở bất kỳ ứng dụng nào trong máy (OPEN_APP)
     */
    fun openApp(appName: String): Map<String, Any> {
        val cleanName = appName.trim()
        if (cleanName.isEmpty()) {
            return mapOf("success" to false, "message" to "Tên ứng dụng trống")
        }

        val normTarget = normalizeString(cleanName)
        val pm = context.packageManager

        // Các alias phổ biến tiếng Việt / tiếng Anh
        val knownAliases = mapOf(
            "zalo" to "com.zing.zalo",
            "chrome" to "com.android.chrome",
            "google chrome" to "com.android.chrome",
            "facebook" to "com.facebook.katana",
            "fb" to "com.facebook.katana",
            "messenger" to "com.facebook.orca",
            "youtube" to "com.google.android.youtube",
            "maps" to "com.google.android.apps.maps",
            "ban do" to "com.google.android.apps.maps",
            "google maps" to "com.google.android.apps.maps",
            "tiktok" to "com.zhiliaoapp.musically",
            "cai dat" to "com.android.settings",
            "settings" to "com.android.settings",
            "camera" to null, // sẽ tìm kiếm package camera
            "may anh" to null,
            "tin nhan" to null,
            "danh ba" to null,
            "dien thoai" to null
        )

        val directPkg = knownAliases[normTarget]
        if (directPkg != null) {
            val launchIntent = pm.getLaunchIntentForPackage(directPkg)
            if (launchIntent != null && safeStartActivity(launchIntent)) {
                return mapOf("success" to true, "action" to "OPEN_APP", "package" to directPkg)
            }
        }

        // Quét toàn bộ apps đã cài
        try {
            val installedApps = pm.getInstalledApplications(PackageManager.GET_META_DATA)
            var bestMatchPkg: String? = null

            for (app in installedApps) {
                // Bỏ qua nếu không có launch intent
                if (pm.getLaunchIntentForPackage(app.packageName) == null) continue

                val label = pm.getApplicationLabel(app).toString()
                val normLabel = normalizeString(label)
                val pkgName = app.packageName.lowercase(Locale.ROOT)

                if (normLabel == normTarget || pkgName.contains(normTarget)) {
                    bestMatchPkg = app.packageName
                    break
                }
                if (normLabel.contains(normTarget) || normTarget.contains(normLabel)) {
                    bestMatchPkg = app.packageName
                }
            }

            if (bestMatchPkg != null) {
                val launchIntent = pm.getLaunchIntentForPackage(bestMatchPkg)
                if (launchIntent != null && safeStartActivity(launchIntent)) {
                    return mapOf("success" to true, "action" to "OPEN_APP", "package" to bestMatchPkg)
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error scanning installed apps", e)
        }

        return mapOf("success" to false, "message" to "Không tìm thấy ứng dụng '$appName' trên thiết bị")
    }

    /**
     * 4. Gọi điện thoại (MAKE_CALL)
     */
    fun makePhoneCall(phoneNumber: String): Map<String, Any> {
        val cleanNumber = phoneNumber.trim().replace(" ", "").replace("-", "")
        if (cleanNumber.isEmpty()) {
            return mapOf("success" to false, "message" to "Số điện thoại trống")
        }

        try {
            // Ưu tiên quay số ACTION_DIAL (an toàn, không bắt buộc người dùng cấp runtime permission khắt khe)
            val dialIntent = Intent(Intent.ACTION_DIAL, Uri.parse("tel:$cleanNumber")).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            if (safeStartActivity(dialIntent)) {
                return mapOf("success" to true, "action" to "MAKE_CALL", "number" to cleanNumber)
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error dial phone", e)
        }

        return mapOf("success" to false, "message" to "Không thể gọi số $cleanNumber")
    }

    /**
     * 5. Điều khiển phần cứng & Hệ thống (SYSTEM_CONTROL)
     */
    fun setVolume(level: Int): Map<String, Any> {
        return try {
            val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
            val maxVol = audioManager.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
            // level có thể là 0..100 hoặc mức index trực tiếp
            val targetVol = if (level in 0..maxVol) {
                level
            } else {
                ((level.coerceIn(0, 100) / 100.0) * maxVol).toInt()
            }
            audioManager.setStreamVolume(AudioManager.STREAM_MUSIC, targetVol, AudioManager.FLAG_SHOW_UI)
            mapOf("success" to true, "action" to "SET_VOLUME", "level" to targetVol, "max" to maxVol)
        } catch (e: Exception) {
            Log.e(TAG, "Error setting volume", e)
            mapOf("success" to false, "message" to e.message.toString())
        }
    }

    fun adjustVolume(up: Boolean): Map<String, Any> {
        return try {
            val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
            val direction = if (up) AudioManager.ADJUST_RAISE else AudioManager.ADJUST_LOWER
            audioManager.adjustStreamVolume(AudioManager.STREAM_MUSIC, direction, AudioManager.FLAG_SHOW_UI)
            val currentVol = audioManager.getStreamVolume(AudioManager.STREAM_MUSIC)
            val maxVol = audioManager.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
            mapOf("success" to true, "action" to "ADJUST_VOLUME", "current" to currentVol, "max" to maxVol)
        } catch (e: Exception) {
            Log.e(TAG, "Error adjusting volume", e)
            mapOf("success" to false, "message" to e.message.toString())
        }
    }

    fun toggleFlashlight(state: Boolean): Map<String, Any> {
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                val cameraManager = context.getSystemService(Context.CAMERA_SERVICE) as CameraManager
                val cameraId = cameraManager.cameraIdList.firstOrNull()
                if (cameraId != null) {
                    cameraManager.setTorchMode(cameraId, state)
                    mapOf("success" to true, "action" to "TOGGLE_FLASHLIGHT", "state" to state)
                } else {
                    mapOf("success" to false, "message" to "Không tìm thấy camera trên máy")
                }
            } else {
                mapOf("success" to false, "message" to "Android version quá cũ không hỗ trợ CameraManager")
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error toggling flashlight", e)
            mapOf("success" to false, "message" to e.message.toString())
        }
    }

    fun openWifiSettings(): Map<String, Any> {
        val intent = Intent(Settings.ACTION_WIFI_SETTINGS).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        val success = safeStartActivity(intent)
        return mapOf("success" to success, "action" to "OPEN_WIFI_SETTINGS")
    }

    fun openBluetoothSettings(): Map<String, Any> {
        val intent = Intent(Settings.ACTION_BLUETOOTH_SETTINGS).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        val success = safeStartActivity(intent)
        return mapOf("success" to success, "action" to "OPEN_BLUETOOTH_SETTINGS")
    }

    fun getSystemStatus(): Map<String, Any> {
        return try {
            val batteryFilter = IntentFilter(Intent.ACTION_BATTERY_CHANGED)
            val batteryIntent = context.registerReceiver(null, batteryFilter)
            val level = batteryIntent?.getIntExtra(BatteryManager.EXTRA_LEVEL, -1) ?: -1
            val scale = batteryIntent?.getIntExtra(BatteryManager.EXTRA_SCALE, -1) ?: -1
            val batteryPct = if (level >= 0 && scale > 0) (level * 100 / scale) else -1

            val timeFormat = SimpleDateFormat("HH:mm, 'ngày' dd/MM/yyyy", Locale("vi", "VN"))
            val currentTime = timeFormat.format(Date())

            mapOf(
                "success" to true,
                "action" to "SYSTEM_STATUS",
                "battery" to batteryPct,
                "time" to currentTime
            )
        } catch (e: Exception) {
            Log.e(TAG, "Error getting system status", e)
            mapOf("success" to false, "message" to e.message.toString())
        }
    }
}
