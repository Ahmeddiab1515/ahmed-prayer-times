package com.ahmed.awqatalsalah;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;

public class BootReceiver extends BroadcastReceiver {
    @Override public void onReceive(Context context, Intent intent) {
        // The app refreshes the schedule on its next launch; alarms are not silently recreated without a fresh location and calculation method.
    }
}
