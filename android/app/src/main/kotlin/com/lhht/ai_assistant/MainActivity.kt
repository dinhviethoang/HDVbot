package com.lhht.ai_assistant

import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    // Giữ màn hình luôn sáng suốt thời gian mở app (robot để bàn).
    // Cờ này chỉ có hiệu lực khi app đang hiển thị; thoát app thì máy tắt màn hình bình thường.
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
    }

    override fun onResume() {
        super.onResume()
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
    }
}
