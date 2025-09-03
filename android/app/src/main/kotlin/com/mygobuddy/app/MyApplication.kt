package com.mygobuddy.app

import android.app.Application
import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Build

class MyApplication: Application() {
    override fun onCreate() {
        super.onCreate()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                "my_gobuddy_trip_channel", // This ID must match the one in main.dart
                "MyGoBuddy Trips",
                NotificationManager.IMPORTANCE_LOW
            )
            // The icon is set here implicitly by Android, but we provide a default in the manifest
            val manager = getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(channel)
        }
    }
}
