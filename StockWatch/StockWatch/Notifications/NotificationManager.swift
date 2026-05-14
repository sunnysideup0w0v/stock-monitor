import Foundation
import UserNotifications

// Phase 1에서 구현 예정: macOS 네이티브 알림 관리
final class NotificationManager: @unchecked Sendable {
    nonisolated(unsafe) static let shared = NotificationManager()
    private init() {}
}
