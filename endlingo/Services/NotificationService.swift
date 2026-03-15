import UserNotifications

@MainActor
final class NotificationService {
    static let shared = NotificationService()

    private let center = UNUserNotificationCenter.current()
    private let notificationID = "daily-reminder"

    private var isKorean: Bool {
        Locale.preferredLanguages.first?.hasPrefix("ko") == true
    }

    private init() {}

    // MARK: - Permission

    func requestPermission() async -> Bool {
        do {
            return try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            print("Notification permission error: \(error)")
            return false
        }
    }

    // MARK: - Schedule

    func scheduleDailyNotification(hour: Int, minute: Int) {
        center.removePendingNotificationRequests(withIdentifiers: [notificationID])

        let content = UNMutableNotificationContent()
        content.title = String(localized: "오늘의 영어 레슨")
        content.body = String(localized: "새로운 문장이 준비되었어요. 지금 학습을 시작해보세요!")
        content.sound = .default

        var dateComponents = DateComponents()
        dateComponents.hour = hour
        dateComponents.minute = minute

        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
        let request = UNNotificationRequest(identifier: notificationID, content: content, trigger: trigger)

        center.add(request) { error in
            if let error {
                print("Schedule notification error: \(error)")
            }
        }
    }

    func cancelAll() {
        center.removePendingNotificationRequests(withIdentifiers: [notificationID])
    }
}
