package com.ahmed.awqatalsalah;

import android.app.AlarmManager;
import android.app.PendingIntent;
import android.content.Context;
import android.content.Intent;
import android.os.Build;
import org.json.JSONArray;
import org.json.JSONObject;
import java.net.HttpURLConnection;
import java.net.URL;
import java.text.SimpleDateFormat;
import java.util.Calendar;
import java.util.Date;
import java.util.Locale;
import java.util.TimeZone;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

final class PrayerScheduler {
    private static final String PREFS = "awqat_android_prayers";
    private static final String IDS = "scheduled_ids";
    private static final ExecutorService EXECUTOR = Executors.newSingleThreadExecutor();

    static void cancel(Context context) {
        String saved = context.getSharedPreferences(PREFS, 0).getString(IDS, "");
        if (saved.isEmpty()) return;
        AlarmManager manager = (AlarmManager) context.getSystemService(Context.ALARM_SERVICE);
        for (String part : saved.split(",")) {
            try {
                int id = Integer.parseInt(part);
                PendingIntent pi = PendingIntent.getBroadcast(context, id, new Intent(context, PrayerAlarmReceiver.class), PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);
                manager.cancel(pi);
                pi.cancel();
            } catch (Exception ignored) {}
        }
        context.getSharedPreferences(PREFS, 0).edit().remove(IDS).apply();
    }

    static void schedule(Context context, String json) {
        EXECUTOR.execute(() -> {
            try {
                JSONObject payload = new JSONObject(json);
                context.getSharedPreferences(PREFS, 0).edit().putString("last_payload", json).apply();
                double lat = payload.getDouble("latitude");
                double lon = payload.getDouble("longitude");
                int method = payload.optInt("method", 3);
                int school = payload.optInt("school", 0);
                JSONObject enabled = payload.optJSONObject("enabled");
                String[] keys = {"Fajr", "Dhuhr", "Asr", "Maghrib", "Isha"};
                String[] names = {"الفجر", "الظهر", "العصر", "المغرب", "العشاء"};
                Calendar now = Calendar.getInstance();
                Calendar todayStart = (Calendar) now.clone(); todayStart.set(Calendar.HOUR_OF_DAY, 0); todayStart.set(Calendar.MINUTE, 0); todayStart.set(Calendar.SECOND, 0); todayStart.set(Calendar.MILLISECOND, 0);
                Calendar end = (Calendar) now.clone(); end.add(Calendar.DAY_OF_YEAR, 12);
                SimpleDateFormat monthFmt = new SimpleDateFormat("yyyy/M", Locale.US);
                monthFmt.setTimeZone(TimeZone.getDefault());
                String currentMonth = monthFmt.format(now.getTime());
                Calendar nextMonthCal = (Calendar) now.clone(); nextMonthCal.add(Calendar.MONTH, 1);
                String nextMonth = monthFmt.format(nextMonthCal.getTime());
                JSONArray allDays = new JSONArray();
                appendDays(allDays, fetchMonth(currentMonth, lat, lon, method, school));
                if (!nextMonth.equals(currentMonth)) appendDays(allDays, fetchMonth(nextMonth, lat, lon, method, school));

                cancel(context);
                AlarmManager manager = (AlarmManager) context.getSystemService(Context.ALARM_SERVICE);
                StringBuilder ids = new StringBuilder();
                int scheduled = 0;
                SimpleDateFormat dateFmt = new SimpleDateFormat("dd-MM-yyyy", Locale.US);
                dateFmt.setTimeZone(TimeZone.getDefault());
                for (int d = 0; d < allDays.length() && scheduled < 60; d++) {
                    JSONObject day = allDays.optJSONObject(d);
                    if (day == null) continue;
                    JSONObject date = day.optJSONObject("date");
                    JSONObject greg = date == null ? null : date.optJSONObject("gregorian");
                    JSONObject timings = day.optJSONObject("timings");
                    if (greg == null || timings == null) continue;
                    Date dayDate;
                    try { dayDate = dateFmt.parse(greg.optString("date")); } catch (Exception ex) { continue; }
                    if (dayDate == null) continue;
                    Calendar dayCal = Calendar.getInstance(); dayCal.setTime(dayDate);
                    if (dayCal.before(todayStart) || dayCal.after(end)) continue;
                    for (int p = 0; p < keys.length && scheduled < 60; p++) {
                        if (enabled != null && !enabled.optBoolean(keys[p], true)) continue;
                        String raw = timings.optString(keys[p], "");
                        String time = raw.split(" ")[0];
                        String[] hm = time.split(":");
                        if (hm.length < 2) continue;
                        Calendar fire = (Calendar) dayCal.clone();
                        fire.set(Calendar.HOUR_OF_DAY, Integer.parseInt(hm[0]));
                        fire.set(Calendar.MINUTE, Integer.parseInt(hm[1]));
                        fire.set(Calendar.SECOND, 0); fire.set(Calendar.MILLISECOND, 0);
                        if (fire.getTimeInMillis() <= System.currentTimeMillis()) continue;
                        int id = (int)(fire.getTimeInMillis() / 60000L % 2000000000L);
                        Intent intent = new Intent(context, PrayerAlarmReceiver.class);
                        intent.putExtra("title", "أذان " + names[p]);
                        PendingIntent pi = PendingIntent.getBroadcast(context, id, intent, PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);
                        if (Build.VERSION.SDK_INT >= 31 && manager.canScheduleExactAlarms()) {
                            manager.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, fire.getTimeInMillis(), pi);
                        } else {
                            manager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, fire.getTimeInMillis(), pi);
                        }
                        if (ids.length() > 0) ids.append(",");
                        ids.append(id); scheduled++;
                    }
                }
                context.getSharedPreferences(PREFS, 0).edit().putString(IDS, ids.toString()).apply();
            } catch (Exception ex) { android.util.Log.e("AwqatPrayer", "Scheduling failed", ex); }
        });
    }

    private static void appendDays(JSONArray target, JSONArray source) throws Exception {
        for (int i = 0; i < source.length(); i++) target.put(source.get(i));
    }

    private static JSONArray fetchMonth(String month, double lat, double lon, int method, int school) throws Exception {
        String url = "https://api.aladhan.com/v1/calendar/" + month + "?latitude=" + lat + "&longitude=" + lon + "&method=" + method + "&school=" + school;
        HttpURLConnection connection = (HttpURLConnection) new URL(url).openConnection();
        connection.setConnectTimeout(15000); connection.setReadTimeout(15000);
        try {
            java.io.InputStream input = connection.getInputStream();
            java.io.ByteArrayOutputStream output = new java.io.ByteArrayOutputStream();
            byte[] buffer = new byte[8192]; int count;
            while ((count = input.read(buffer)) != -1) output.write(buffer, 0, count);
            JSONObject response = new JSONObject(output.toString("UTF-8"));
            return response.optJSONArray("data") == null ? new JSONArray() : response.getJSONArray("data");
        } finally { connection.disconnect(); }
    }
}
