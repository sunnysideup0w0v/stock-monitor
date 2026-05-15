import Foundation

enum AccountManager {
    #if DEBUG
    /// 테스트 전용 accountId 오버라이드. nil이면 Keychain에서 실제 값을 읽음.
    nonisolated(unsafe) static var testAccountId: String? = nil
    #endif

    /// 현재 활성 브로커(UserDefaults "activeBroker")의 계정 ID.
    /// KIS → "KIS-" + appKey.prefix(8), 키움 → "KIWOOM-" + appKey.prefix(8), 미로그인 → ""
    static var currentAccountId: String {
        #if DEBUG
        if let override = testAccountId { return override }
        #endif
        let activeBroker = UserDefaults.standard.string(forKey: "activeBroker") ?? "kis"
        switch activeBroker {
        case "kiwoom":
            guard let appKey = KeychainHelper.load(account: "kiwoom.appKey"),
                  !appKey.isEmpty else { return "" }
            return "KIWOOM-" + String(appKey.prefix(8))
        default:
            guard let appKey = KeychainHelper.load(account: "kis.appKey"),
                  !appKey.isEmpty else { return "" }
            return "KIS-" + String(appKey.prefix(8))
        }
    }
}
