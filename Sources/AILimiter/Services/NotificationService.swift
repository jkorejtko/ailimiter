import Foundation
import UserNotifications

public final class NotificationService: @unchecked Sendable {
    public static let shared = NotificationService()

    private init() {
        requestAuthorization()
    }

    public func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    public func sendWarningNotification(provider: AIProvider, usagePercent: Double) {
        let content = UNMutableNotificationContent()
        content.title = "⚠️ Varování limitu: \(provider.displayName)"
        content.body = "Využití limitu dosáhlo \(Int(usagePercent))%. Zbývá jen málo zpráv nebo kvóty."
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(identifier: "warn_\(provider.id)_\(Date().timeIntervalSince1970)", content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    public func sendExhaustedNotification(provider: AIProvider, detail: String, resetInString: String?) {
        let content = UNMutableNotificationContent()
        content.title = "🔴 Limit vyčerpán: \(provider.displayName)"
        if let resetIn = resetInString {
            content.body = "\(detail). \(resetIn)."
        } else {
            content.body = detail
        }
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(identifier: "exhausted_\(provider.id)_\(Date().timeIntervalSince1970)", content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    public func sendRestoredNotification(provider: AIProvider) {
        let content = UNMutableNotificationContent()
        content.title = "✅ Limit obnoven: \(provider.displayName)"
        content.body = "Váš limit zpráv byl resetován. Můžete opět naplno používat službu."
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(identifier: "restored_\(provider.id)_\(Date().timeIntervalSince1970)", content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }
}
