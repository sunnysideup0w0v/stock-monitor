import Foundation

enum AccountManager {
    #if DEBUG
    /// 테스트 전용 accountId 오버라이드. nil이면 Keychain에서 실제 값을 읽음.
    nonisolated(unsafe) static var testAccountId: String? = nil
    #endif

    /// 현재 로그인된 계정 ID. KIS appKey 앞 8자리를 prefix로 사용.
    /// 미로그인 시 "" 반환.
    static var currentAccountId: String {
        #if DEBUG
        if let override = testAccountId { return override }
        #endif
        guard let appKey = KeychainHelper.load(account: "kis.appKey"),
              !appKey.isEmpty else { return "" }
        return "KIS-" + String(appKey.prefix(8))
    }
}
