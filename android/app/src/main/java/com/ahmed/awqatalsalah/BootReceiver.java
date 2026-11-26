package com.ahmed.awqatalsalah;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;

public class BootReceiver extends BroadcastReceiver {
    @Override public void onReceive(Context context, Intent intent) {
        String saved = context.getSharedPreferences("awqat_android_prayers", 0).getString("last_payload", null);
        if (saved != null) PrayerScheduler.schedule(context, saved);
    }
}
