package com.lhht.ai_assistant

import android.animation.ValueAnimator
import android.annotation.SuppressLint
import android.app.Service
import android.content.Context
import android.content.Intent
import android.graphics.*
import android.os.Build
import android.os.IBinder
import android.provider.Settings
import android.util.Log
import android.view.*
import kotlin.math.hypot
import kotlin.math.sin

/**
 * Service hiển thị bong bóng nhân vật ảo nổi (Floating Avatar Widget) trên màn hình
 * Tương thích hoàn toàn với Android 7.1.1 (Samsung Galaxy J2 Pro - API 25).
 */
class FloatingAvatarService : Service() {

    companion object {
        private const val TAG = "FloatingAvatarService"
        const val ACTION_START = "com.lhht.ai_assistant.ACTION_START"
        const val ACTION_STOP = "com.lhht.ai_assistant.ACTION_STOP"
        const val ACTION_UPDATE_STATE = "com.lhht.ai_assistant.ACTION_UPDATE_STATE"
        const val EXTRA_STATE = "extra_state"
    }

    private var windowManager: WindowManager? = null
    private var floatingView: FloatingBubbleView? = null
    private var layoutParams: WindowManager.LayoutParams? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        Log.i(TAG, "FloatingAvatarService created")

        // Kiểm tra quyền vẽ đè màn hình
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && !Settings.canDrawOverlays(this)) {
            Log.w(TAG, "Chưa được cấp quyền SYSTEM_ALERT_WINDOW (Overlay)")
            stopSelf()
            return
        }

        windowManager = getSystemService(Context.WINDOW_SERVICE) as? WindowManager
        initFloatingBubble()
    }

    @SuppressLint("ClickableViewAccessibility")
    private fun initFloatingBubble() {
        if (windowManager == null) return

        val density = resources.displayMetrics.density
        val bubbleSize = (64 * density).toInt()

        val layoutType = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        } else {
            @Suppress("DEPRECATION")
            WindowManager.LayoutParams.TYPE_PHONE
        }

        layoutParams = WindowManager.LayoutParams(
            bubbleSize,
            bubbleSize,
            layoutType,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                    WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            x = 40
            y = (200 * density).toInt()
        }

        floatingView = FloatingBubbleView(this)

        var initialX = 0
        var initialY = 0
        var initialTouchX = 0f
        var initialTouchY = 0f
        var isDragging = false
        val touchSlop = ViewConfiguration.get(this).scaledTouchSlop

        floatingView?.setOnTouchListener { _, event ->
            val params = layoutParams ?: return@setOnTouchListener false
            when (event.action) {
                MotionEvent.ACTION_DOWN -> {
                    initialX = params.x
                    initialY = params.y
                    initialTouchX = event.rawX
                    initialTouchY = event.rawY
                    isDragging = false
                    true
                }
                MotionEvent.ACTION_MOVE -> {
                    val dx = event.rawX - initialTouchX
                    val dy = event.rawY - initialTouchY
                    if (hypot(dx.toDouble(), dy.toDouble()) > touchSlop) {
                        isDragging = true
                    }
                    if (isDragging) {
                        params.x = (initialX + dx).toInt()
                        params.y = (initialY + dy).toInt()
                        try {
                            windowManager?.updateViewLayout(floatingView, params)
                        } catch (e: Exception) {
                            Log.e(TAG, "Error updating floating view position", e)
                        }
                    }
                    true
                }
                MotionEvent.ACTION_UP -> {
                    if (!isDragging) {
                        // Chạm vào bong bóng -> Mở lại app chính
                        bringAppToFront()
                    }
                    true
                }
                else -> false
            }
        }

        try {
            windowManager?.addView(floatingView, layoutParams)
            Log.i(TAG, "Bong bóng nhân vật ảo nổi đã hiển thị thành công")
        } catch (e: Exception) {
            Log.e(TAG, "Lỗi khi addView floating bubble", e)
        }
    }

    private fun bringAppToFront() {
        try {
            val launchIntent = packageManager.getLaunchIntentForPackage(packageName)?.apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or
                        Intent.FLAG_ACTIVITY_SINGLE_TOP or
                        Intent.FLAG_ACTIVITY_REORDER_TO_FRONT)
            }
            if (launchIntent != null) {
                startActivity(launchIntent)
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error bringing app to front", e)
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent == null) return START_STICKY

        when (intent.action) {
            ACTION_STOP -> {
                stopSelf()
                return START_NOT_STICKY
            }
            ACTION_UPDATE_STATE -> {
                val state = intent.getStringExtra(EXTRA_STATE) ?: "idle"
                floatingView?.updateState(state)
            }
            ACTION_START -> {
                val state = intent.getStringExtra(EXTRA_STATE) ?: "idle"
                floatingView?.updateState(state)
            }
        }

        return START_STICKY
    }

    override fun onDestroy() {
        super.onDestroy()
        Log.i(TAG, "FloatingAvatarService onDestroy")
        try {
            if (floatingView != null && floatingView?.isAttachedToWindow == true) {
                windowManager?.removeView(floatingView)
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error removing floating view on destroy", e)
        }
        floatingView?.destroy()
        floatingView = null
    }

    /**
     * View vẽ hình tròn nhân vật ảo với viền phát sáng và cử động biểu cảm
     */
    class FloatingBubbleView(context: Context) : View(context) {
        private var currentState: String = "idle" // idle, listening, speaking, thinking, error
        private var pulsePhase = 0f
        private val animator: ValueAnimator = ValueAnimator.ofFloat(0f, 1f).apply {
            duration = 1500
            repeatCount = ValueAnimator.INFINITE
            addUpdateListener {
                pulsePhase = it.animatedValue as Float
                invalidate()
            }
        }

        private val bgPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.parseColor("#0B101B")
            style = Paint.Style.FILL
        }

        private val borderPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.STROKE
            strokeWidth = 4f
        }

        private val glowPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.STROKE
            strokeWidth = 6f
        }

        private val eyePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.FILL
        }

        private val mouthPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.STROKE
            strokeWidth = 3f
            strokeCap = Paint.Cap.ROUND
        }

        init {
            animator.start()
        }

        fun updateState(state: String) {
            currentState = state
            invalidate()
        }

        fun destroy() {
            animator.cancel()
        }

        override fun onDraw(canvas: Canvas) {
            super.onDraw(canvas)
            val cx = width / 2f
            val cy = height / 2f
            val r = (width.coerceAtMost(height) / 2f) - 8f

            val baseColor = when (currentState) {
                "listening" -> Color.parseColor("#00E676") // Xanh lá sáng khi nghe
                "speaking" -> Color.parseColor("#00F0FF")  // Cyan neon khi nói
                "thinking" -> Color.parseColor("#A855F7")  // Tím neon khi suy nghĩ
                "error" -> Color.parseColor("#FF1744")     // Đỏ khi lỗi
                else -> Color.parseColor("#00F0FF")        // Cyan mặc định
            }

            val pulse = sin(pulsePhase * 2 * Math.PI).toFloat()

            // 1. Viền phát sáng bên ngoài
            glowPaint.color = baseColor
            glowPaint.alpha = when (currentState) {
                "speaking" -> (80 + 70 * Math.abs(pulse)).toInt().coerceIn(0, 255)
                "listening" -> (90 + 80 * Math.abs(pulse)).toInt().coerceIn(0, 255)
                else -> 50
            }
            canvas.drawCircle(cx, cy, r + 4f + pulse * 2f, glowPaint)

            // 2. Nền bong bóng tối
            canvas.drawCircle(cx, cy, r, bgPaint)

            // 3. Viền chính của bong bóng
            borderPaint.color = baseColor
            canvas.drawCircle(cx, cy, r, borderPaint)

            // 4. Vẽ mắt robot
            eyePaint.color = baseColor
            val eyeSpacing = r * 0.42f
            val eyeY = cy - r * 0.15f
            val eyeR = r * 0.16f

            if (currentState == "listening") {
                // Mắt to hơn khi lắng nghe
                val currentEyeR = eyeR * (1.1f + 0.2f * pulse)
                canvas.drawCircle(cx - eyeSpacing, eyeY, currentEyeR, eyePaint)
                canvas.drawCircle(cx + eyeSpacing, eyeY, currentEyeR, eyePaint)
            } else {
                canvas.drawCircle(cx - eyeSpacing, eyeY, eyeR, eyePaint)
                canvas.drawCircle(cx + eyeSpacing, eyeY, eyeR, eyePaint)
            }

            // 5. Vẽ miệng robot (mấp máy khi đang nói, mỉm cười khi idle)
            mouthPaint.color = baseColor
            val mouthY = cy + r * 0.35f
            val mouthWidth = r * 0.5f

            if (currentState == "speaking") {
                // Miệng mấp máy theo nhịp sóng âm
                val mouthOpen = Math.abs(sin(pulsePhase * 4 * Math.PI).toFloat()) * (r * 0.28f) + 3f
                val mouthRect = RectF(
                    cx - mouthWidth / 2f,
                    mouthY - mouthOpen / 2f,
                    cx + mouthWidth / 2f,
                    mouthY + mouthOpen / 2f
                )
                eyePaint.color = baseColor
                canvas.drawRoundRect(mouthRect, mouthOpen / 2f, mouthOpen / 2f, eyePaint)
            } else {
                // Miệng cười nhẹ
                val mouthPath = Path().apply {
                    moveTo(cx - mouthWidth / 2f, mouthY)
                    quadTo(cx, mouthY + r * 0.15f, cx + mouthWidth / 2f, mouthY)
                }
                canvas.drawPath(mouthPath, mouthPaint)
            }
        }
    }
}
