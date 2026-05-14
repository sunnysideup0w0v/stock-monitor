import Foundation

// Phase 1에서 구현 예정: 시세 조회 및 폴링 관리
final class QuoteManager: @unchecked Sendable {
    nonisolated(unsafe) static let shared = QuoteManager()
    private init() {}
}
