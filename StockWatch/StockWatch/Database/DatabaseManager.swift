import Foundation
import GRDB

// Phase 1에서 구현 예정: SQLite DB 연결 및 마이그레이션
final class DatabaseManager: @unchecked Sendable {
    nonisolated(unsafe) static let shared = DatabaseManager()
    private init() {}
}
