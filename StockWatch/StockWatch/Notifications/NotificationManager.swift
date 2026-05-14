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

    func send(title: String, body: String, symbol: String) {
        // 소리: NSSound로 직접 재생 (UNUserNotificationCenter 소리가 막히는 경우 대비)
        DispatchQueue.main.async {
            NSSound(named: "Glass")?.play()
        }

        // 화면 배너: 커스텀 오버레이 윈도우
        DispatchQueue.main.async {
            ToastWindowManager.shared.show(title: title, body: body)
        }

        // 알림 센터 등록 (NC에도 기록)
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.userInfo = ["symbol": symbol]

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
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .openPopover, object: nil)
        }
        completionHandler()
    }
}
