package com.lhht.ai_assistant

import android.annotation.SuppressLint
import java.security.SecureRandom
import java.security.cert.X509Certificate
import javax.net.ssl.*

object UnsafeSslHelper {
    private var isEnabled = false

    @SuppressLint("TrustAllX509TrustManager", "BadHostnameVerifier")
    fun enableUnsafeSsl() {
        if (isEnabled) return
        try {
            val trustAllCerts = arrayOf<TrustManager>(object : X509TrustManager {
                override fun checkClientTrusted(chain: Array<out X509Certificate>?, authType: String?) {}
                override fun checkServerTrusted(chain: Array<out X509Certificate>?, authType: String?) {}
                override fun getAcceptedIssuers(): Array<X509Certificate> = arrayOf()
            })

            val sslContext = SSLContext.getInstance("TLS")
            sslContext.init(null, trustAllCerts, SecureRandom())
            HttpsURLConnection.setDefaultSSLSocketFactory(sslContext.socketFactory)
            HttpsURLConnection.setDefaultHostnameVerifier { _, _ -> true }

            isEnabled = true
            android.util.Log.i("UnsafeSslHelper", "Unsafe SSL successfully enabled for Android 7.1.1")
        } catch (e: Exception) {
            android.util.Log.e("UnsafeSslHelper", "Failed to enable unsafe SSL", e)
        }
    }
}
