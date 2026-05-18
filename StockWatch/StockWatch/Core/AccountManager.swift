import Foundation
import Combine

@MainActor
final class AccountManager: ObservableObject {
    static let shared = AccountManager()
    private init() { refresh() }

    #if DEBUG
    /// 테스트 전용 accountId 오버라이드. nil이면 Keychain에서 실제 값을 읽음.
    nonisolated(unsafe) static var testAccountId: String? = nil
    #endif

    @Published private(set) var connectedAccountIds: [String] = []

    // nonisolated 컨텍스트(DatabaseManager 등)에서 안전하게 읽기 위한 미러.
    // refresh() 호출 시 항상 동기화되므로 stale 값 없음.
    nonisolated(unsafe) private static var _syncedIds: [String] = []

    /// Keychain을 읽어 connectedAccountIds를 갱신한다. login/logout 후 호출.
    func refresh() {
        #if DEBUG
        if let override = AccountManager.testAccountId {
            connectedAccountIds = [override]
            AccountManager._syncedIds = [override]
            return
        }
        #endif
        var ids: [String] = []
        if let k = KeychainHelper.load(account: KeychainKey.kisAppKey), !k.isEmpty {
            ids.append("KIS-" + String(k.prefix(8)))
        }
        if let k = KeychainHelper.load(account: KeychainKey.kiwoomAppKey), !k.isEmpty {
            ids.append("KIWOOM-" + String(k.prefix(8)))
        }
        connectedAccountIds = ids
        AccountManager._syncedIds = ids
    }

    // MARK: - 정적 포워딩 (기존 호출 코드 변경 불필요)

    /// 현재 Keychain에 자격증명이 존재하는 모든 계좌 ID 목록.
    /// nonisolated — DatabaseManager 등 비격리 컨텍스트에서도 안전하게 호출 가능.
    nonisolated static var connectedAccountIds: [String] {
        #if DEBUG
        if let override = testAccountId { return [override] }
        #endif
        return _syncedIds
    }

    /// 하나 이상의 브로커가 로그인된 상태인지.
    nonisolated static var isAnyConnected: Bool { !connectedAccountIds.isEmpty }

    /// 하위 호환 — 첫 번째 연결된 계좌 ID, 없으면 "".
    nonisolated static var currentAccountId: String {
        #if DEBUG
        if let override = testAccountId { return override }
        #endif
        return _syncedIds.first ?? ""
    }

    /// accountId 접두사로 사람이 읽을 수 있는 브로커 이름 반환.
    nonisolated static func displayName(for accountId: String) -> String {
        if accountId.hasPrefix("KIS-") { return "KIS" }
        if accountId.hasPrefix("KIWOOM-") { return "키움" }
        return accountId
    }
}
