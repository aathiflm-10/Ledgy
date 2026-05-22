package com.example.ledgy

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.telephony.SmsMessage
import android.util.Log

class SmsReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context?, intent: Intent?) {
        if (intent?.action == "android.provider.Telephony.SMS_RECEIVED") {
            val bundle = intent.extras
            if (bundle != null) {
                try {
                    val pdus = bundle.get("pdus") as Array<*>?
                    if (pdus != null) {
                        for (pdu in pdus) {
                            val format = bundle.getString("format")
                            val smsMessage = SmsMessage.createFromPdu(pdu as ByteArray, format)
                            val sender = smsMessage.originatingAddress ?: ""
                            val body = smsMessage.messageBody ?: ""
                            val timestamp = smsMessage.timestampMillis

                            Log.d("SmsReceiver", "SMS received from: $sender, body: $body")

                            // Forward to MainActivity for MethodChannel execution
                            MainActivity.handleIncomingSms(sender, body, timestamp)
                        }
                    }
                } catch (e: Exception) {
                    Log.e("SmsReceiver", "Error parsing SMS: ${e.message}")
                }
            }
        }
    }
}
