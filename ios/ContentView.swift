import SwiftUI
import WebKit

struct ContentView: View {
    @ObservedObject var notifications: PrayerNotificationManager
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("أوقات الصلاة").font(.headline).foregroundStyle(Color(red: 0.94, green: 0.78, blue: 0.39))
                    Text(notifications.status).font(.caption2).foregroundStyle(.white.opacity(0.72)).lineLimit(2)
                }
                Spacer(minLength: 4)
                Toggle("الخلفية", isOn: Binding(get: { notifications.isEnabled },
                    set: { notifications.setBackgroundEnabled($0) }))
                    .labelsHidden().tint(Color(red: 0.82, green: 0.66, blue: 0.28))
                    .accessibilityLabel("تشغيل تنبيهات الصلاة بالخلفية")
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            .background(Color(red: 0.06, green: 0.16, blue: 0.12))
            PrayerWebView(notifications: notifications).ignoresSafeArea(edges: .bottom)
        }.background(Color(red: 0.06, green: 0.16, blue: 0.12))
    }
}

private struct PrayerWebView: UIViewRepresentable {
    let notifications: PrayerNotificationManager
    func makeCoordinator() -> Coordinator { Coordinator(notifications: notifications) }
    func makeUIView(context: Context) -> WKWebView {
        let controller = WKUserContentController()
        controller.add(context.coordinator, name: "prayerSchedule")
        let configuration = WKWebViewConfiguration()
        configuration.userContentController = controller
        configuration.allowsInlineMediaPlayback = true
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.backgroundColor = UIColor(red: 0.06, green: 0.16, blue: 0.12, alpha: 1)
        webView.isOpaque = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.load(URLRequest(url: URL(string: "https://ahmeddiab1515.github.io/ahmed-prayer-times/?native=1")!))
        return webView
    }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
    final class Coordinator: NSObject, WKScriptMessageHandler {
        let notifications: PrayerNotificationManager
        init(notifications: PrayerNotificationManager) { self.notifications = notifications }
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "prayerSchedule", let payload = message.body as? [String: Any] else { return }
            notifications.syncFromWeb(payload)
        }
    }
}
