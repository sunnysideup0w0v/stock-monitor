import Foundation
import UserNotifications
import AppKit
import SwiftUI

final class NotificationManager: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    static let shared = NotificationManager()
    private override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, error in
            if let error { print("알림 권한 요청 실패: \(error)") }
        }
    }

    func send(title: String, body: String, symbol: String, urlString: String? = nil) {
        DispatchQueue.main.async {
            NSSound(named: "Glass")?.play()
        }

        DispatchQueue.main.async {
            ToastWindowManager.shared.show(title: title, body: body)
        }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        var userInfo: [String: Any] = ["symbol": symbol]
        if let urlString { userInfo["url"] = urlString }
        content.userInfo = userInfo

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.list])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        let userInfo = response.notification.request.content.userInfo
        if let urlStr = userInfo["url"] as? String, let url = URL(string: urlStr) {
            // DART 공시 등 URL이 있는 알림 → 브라우저에서 직접 오픈
            DispatchQueue.main.async { NSWorkspace.shared.open(url) }
        } else {
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .openPopover, object: nil)
            }
        }
        completionHandler()
    }
}
