package com.example.creditpilot_mobile

import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                "cashflow_alerts",
                "Cashflow alerts",
                NotificationManager.IMPORTANCE_DEFAULT,
            ).apply {
                description = "Daily warnings when upcoming bills may exceed checking funds"
            }
            getSystemService(NotificationManager::class.java)
                .createNotificationChannel(channel)
            val emergencyChannel = NotificationChannel(
                "emergency_alerts",
                "Emergency simulations",
                NotificationManager.IMPORTANCE_DEFAULT,
            ).apply {
                description = "Opt-in simulated emergency budget alerts"
            }
            getSystemService(NotificationManager::class.java)
                .createNotificationChannel(emergencyChannel)
        }
    }
}
