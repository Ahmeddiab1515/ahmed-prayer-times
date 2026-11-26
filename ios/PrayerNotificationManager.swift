import Foundation
import Combine
import UserNotifications

@MainActor
final class PrayerNotificationManager: ObservableObject {
    @Published private(set) var isEnabled = UserDefaults.standard.bool(forKey: "backgroundPrayerAlertsEnabled")
    @Published private(set) var status = "فعّل المفتاح لجدولة تنبيهات الصلاة"
    private var latestPayload: [String: Any]?
    private let center = UNUserNotificationCenter.current()
    private let prefix = "awqat-prayer-"

    func setBackgroundEnabled(_ enabled: Bool) {
        isEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: "backgroundPrayerAlertsEnabled")
        guard enabled else {
            Task {
                let pending = await center.pendingNotificationRequests()
                let ids = pending.map(\.identifier).filter { $0.hasPrefix(prefix) }
                center.removePendingNotificationRequests(withIdentifiers: ids)
                status = "تم إيقاف تنبيهات الخلفية"
            }
            return
        }
        Task {
            do {
                let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
                guard granted else {
                    isEnabled = false
                    UserDefaults.standard.set(false, forKey: "backgroundPrayerAlertsEnabled")
                    status = "إذن الإشعارات غير مفعّل من إعدادات الآيفون"
                    return
                }
                guard let payload = latestPayload else {
                    status = "افتح صفحة المواقيت وحدد موقعك أولًا"
                    return
                }
                await schedule(from: payload)
            } catch { status = "تعذر طلب إذن الإشعارات" }
        }
    }

    func syncFromWeb(_ payload: [String: Any]) {
        latestPayload = payload
        guard isEnabled else { return }
        Task { await schedule(from: payload) }
    }

    private func schedule(from payload: [String: Any]) async {
        guard let latitude = payload["latitude"] as? Double,
              let longitude = payload["longitude"] as? Double else {
            status = "في انتظار تحديد الموقع"
            return
        }
        let method = payload["method"] as? Int ?? 3
        let school = payload["school"] as? Int ?? 0
        let prefs = payload["enabled"] as? [String: Any] ?? [:]
        let prayers: [(key: String, title: String)] = [
            ("Fajr", "أذان الفجر"), ("Dhuhr", "أذان الظهر"), ("Asr", "أذان العصر"),
            ("Maghrib", "أذان المغرب"), ("Isha", "أذان العشاء")
        ]
        let active = prayers.filter { (prefs[$0.key] as? Bool) != false }

        do {
            let settings = await center.notificationSettings()
            if settings.authorizationStatus == .notDetermined {
                let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
                guard granted else { status = "لم يتم السماح بالإشعارات"; return }
            } else if settings.authorizationStatus == .denied {
                status = "فعّل الإشعارات من إعدادات الآيفون"; return
            }

            let now = Date()
            let calendar = Calendar.current
            let endDate = calendar.date(byAdding: .day, value: 12, to: now) ?? now
            let months = [calendar.dateComponents([.year, .month], from: now),
                          calendar.dateComponents([.year, .month], from: endDate)].sorted {
                (($0.year ?? 0) * 12 + ($0.month ?? 0)) < (($1.year ?? 0) * 12 + ($1.month ?? 0))
            }
            var entries: [[String: Any]] = []
            for month in months {
                guard let year = month.year, let monthNumber = month.month else { continue }
                var components = URLComponents(string: "https://api.aladhan.com/v1/calendar/\(year)/\(monthNumber)")!
                components.queryItems = [
                    URLQueryItem(name: "latitude", value: String(latitude)),
                    URLQueryItem(name: "longitude", value: String(longitude)),
                    URLQueryItem(name: "method", value: String(method)),
                    URLQueryItem(name: "school", value: String(school))
                ]
                let (data, _) = try await URLSession.shared.data(from: components.url!)
                let response = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                entries.append(contentsOf: response?["data"] as? [[String: Any]] ?? [])
            }

            let pending = await center.pendingNotificationRequests()
            let oldIDs = pending.map(\.identifier).filter { $0.hasPrefix(prefix) }
            center.removePendingNotificationRequests(withIdentifiers: oldIDs)

            var scheduled = 0
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = .current
            formatter.dateFormat = "dd-MM-yyyy"

            for entry in entries {
                guard let dateInfo = entry["date"] as? [String: Any],
                      let gregorian = dateInfo["gregorian"] as? [String: Any],
                      let dateText = gregorian["date"] as? String,
                      let dayDate = formatter.date(from: dateText),
                      let timings = entry["timings"] as? [String: Any] else { continue }
                guard calendar.startOfDay(for: dayDate) <= endDate else { continue }

                for prayer in active {
                    guard let raw = timings[prayer.key] as? String else { continue }
                    let timeText = String(raw.split(separator: " ").first ?? "")
                    let pieces = timeText.split(separator: ":").compactMap { Int($0) }
                    guard pieces.count >= 2 else { continue }
                    var parts = calendar.dateComponents([.year, .month, .day], from: dayDate)
                    parts.hour = pieces[0]; parts.minute = pieces[1]; parts.second = 0
                    guard let fireDate = calendar.date(from: parts), fireDate > now else { continue }

                    let content = UNMutableNotificationContent()
                    content.title = prayer.title
                    content.body = "حان الآن موعد الصلاة"
                    content.sound = Bundle.main.url(forResource: "adhan", withExtension: "caf") != nil
                        ? UNNotificationSound(named: UNNotificationSoundName("adhan.caf"))
                        : .default
                    let triggerParts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
                    let trigger = UNCalendarNotificationTrigger(dateMatching: triggerParts, repeats: false)
                    let id = prefix + String(Int(fireDate.timeIntervalSince1970))
                    try await center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
                    scheduled += 1
                    if scheduled >= 60 { break }
                }
                if scheduled >= 60 { break }
            }
            status = "تمت جدولة \(scheduled) تنبيهًا بمقطع من أذان المنشاوي للأيام الـ12 القادمة"
        } catch {
            status = "تعذر تحديث التنبيهات. افتح التطبيق وتحقق من الإنترنت"
        }
    }
}
