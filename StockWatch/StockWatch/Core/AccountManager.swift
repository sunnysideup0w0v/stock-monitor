import Foundation

enum AccountManager {
    #if DEBUG
    /// 테스트 전용 accountId 오버라이드. nil이면 Keychain에서 실제 값을 읽음.
    nonisolated(unsafe) static var testAccountId: String? = nil
    #endif

    /// 현재 Keychain에 자격증명이 존재하는 모든 계좌 ID 목록.
    static var connectedAccountIds: [String] {
        var ids: [String] = []
        if let appKey = KeychainHelper.load(account: "kis.appKey"), !appKey.isEmpty {
            ids.append("KIS-" + String(appKey.prefix(8)))
        }
        if let appKey = KeychainHelper.load(account: "kiwoom.appKey"), !appKey.isEmpty {
            ids.append("KIWOOM-" + String(appKey.prefix(8)))
        }
        return ids
    }

    /// 하나 이상의 브로커가 로그인된 상태인지.
    static var isAnyConnected: Bool { !connectedAccountIds.isEmpty }

    /// 하위 호환 — 첫 번째 연결된 계좌 ID, 없으면 "".
    static var currentAccountId: String {
        #if DEBUG
        if let override = testAccountId { return override }
        #endif
        return connectedAccountIds.first ?? ""
    }
}
