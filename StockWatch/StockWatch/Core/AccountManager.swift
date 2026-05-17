import Foundation

enum AccountManager {
    #if DEBUG
    /// 테스트 전용 accountId 오버라이드. nil이면 Keychain에서 실제 값을 읽음.
    nonisolated(unsafe) static var testAccountId: String? = nil
    #endif

    // 반복적인 Keychain I/O 방지 — BrokerSessionManager login/logout 시 invalidateCache() 호출
    nonisolated(unsafe) private static var _cachedConnectedIds: [String]? = nil

    static func invalidateCache() {
        _cachedConnectedIds = nil
    }

    /// 현재 Keychain에 자격증명이 존재하는 모든 계좌 ID 목록.
    static var connectedAccountIds: [String] {
        #if DEBUG
        if let override = testAccountId { return [override] }
        #endif
        if let cached = _cachedConnectedIds { return cached }
        var ids: [String] = []
        if let appKey = KeychainHelper.load(account: KeychainKey.kisAppKey), !appKey.isEmpty {
            ids.append("KIS-" + String(appKey.prefix(8)))
        }
        if let appKey = KeychainHelper.load(account: KeychainKey.kiwoomAppKey), !appKey.isEmpty {
            ids.append("KIWOOM-" + String(appKey.prefix(8)))
        }
        _cachedConnectedIds = ids
        return ids
    }

    /// 하나 이상의 브로커가 로그인된 상태인지.
    static var isAnyConnected: Bool { !connectedAccountIds.isEmpty }

    /// accountId 접두사로 사람이 읽을 수 있는 브로커 이름 반환.
    static func displayName(for accountId: String) -> String {
        if accountId.hasPrefix("KIS-") { return "KIS" }
        if accountId.hasPrefix("KIWOOM-") { return "키움" }
        return accountId
    }

    /// 하위 호환 — 첫 번째 연결된 계좌 ID, 없으면 "".
    static var currentAccountId: String {
        #if DEBUG
        if let override = testAccountId { return override }
        #endif
        return connectedAccountIds.first ?? ""
    }
}
