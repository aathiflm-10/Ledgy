package com.example.ledgy

import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel
import java.lang.ref.WeakReference

class MainActivity : FlutterActivity() {
    companion object {
        private const val CHANNEL = "com.ledgy.financetracker/sms"
        private var instance: WeakReference<MainActivity>? = null
        private var channel: MethodChannel? = null

        fun handleIncomingSms(sender: String, body: String, timestamp: Long) {
            val activity = instance?.get()
            if (activity != null && channel != null) {
                activity.runOnUiThread {
                    val arguments = HashMap<String, Any>()
                    arguments["sender"] = sender
                    arguments["body"] = body
                    arguments["timestamp"] = timestamp
                    channel?.invokeMethod("onSmsReceived", arguments)
                }
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        instance = WeakReference(this)

        val flutterEngine = flutterEngine
        if (flutterEngine != null) {
            channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        }
    }

    override fun onDestroy() {
        if (instance?.get() == this) {
            instance = null
            channel = null
        }
        super.onDestroy()
    }
}
