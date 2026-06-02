import Foundation
import UserNotifications

/// Schedules a nightly bedtime wind-down reminder at a user-configured time.
/// Uses a calendar-based repeating trigger so it fires every night automatically.
/// Cancelled when the user disables it in Settings.
enum BedtimeNudge {
    static let id = "bedtime-nudge"
    static let hourKey  = "com.openwhoop.bedtimeNudge.hour"
    static let minuteKey = "com.openwhoop.bedtimeNudge.minute"
    static let enabledKey = "com.openwhoop.bedtimeNudge.enabled"

    static func requestAuthorization() {
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// Schedule a nightly repeating nudge at `hour`:`minute` (local time).
    static func schedule(hour: Int, minute: Int) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [id])

        let content = UNMutableNotificationContent()
        content.title = "Time to wind down"
        content.body  = "Consistent bedtimes improve your recovery score."
        content.sound = .default

        var components = DateComponents()
        components.hour   = hour
        components.minute = minute
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))

        UserDefaults.standard.set(true,   forKey: enabledKey)
        UserDefaults.standard.set(hour,   forKey: hourKey)
        UserDefaults.standard.set(minute, forKey: minuteKey)
    }

    static func cancel() {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [id])
        UserDefaults.standard.set(false, forKey: enabledKey)
    }
}