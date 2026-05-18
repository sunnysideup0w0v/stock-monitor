import XCTest
@testable import StockWatch

/// BrokerSessionManager의 로그인/로그아웃 계약을 검증한다.
/// R2(BrokerSessionManager 추출), R8(AccountManager 캐싱)의 안전망.
@MainActor
final class BrokerSessionManagerTests: XCTestCase {

    private let testAppKey    = "TESTKEY1"
    private let testAppSecret = "TESTSECRET1"
    private let testAccount   = "12345678-01"

    // 테스트 전 실제 자격증명 보존용
    private var savedKisAppKey: String?
    private var savedKisAppSecret: String?
    private var savedKisAccountNumber: String?
    private var savedKiwoomAppKey: String?
    private var savedKiwoomAppSecret: String?
    private var savedKiwoomAccountNumber: String?

    override func setUp() async throws {
        try await super.setUp()
        // 실제 자격증명 저장 후 테스트용 슬레이트 초기화
        savedKisAppKey         = KeychainHelper.load(account: KeychainKey.kisAppKey)
        savedKisAppSecret      = KeychainHelper.load(account: KeychainKey.kisAppSecret)
        savedKisAccountNumber  = KeychainHelper.load(account: KeychainKey.kisAccountNumber)
        savedKiwoomAppKey      = KeychainHelper.load(account: KeychainKey.kiwoomAppKey)
        savedKiwoomAppSecret   = KeychainHelper.load(account: KeychainKey.kiwoomAppSecret)
        savedKiwoomAccountNumber = KeychainHelper.load(account: KeychainKey.kiwoomAccountNumber)
        cleanupKeychain()
    }

    override func tearDown() async throws {
        // 테스트 자격증명 제거
        cleanupKeychain()
        BrokerSessionManager.shared.logoutKIS()
        BrokerSessionManager.shared.logoutKiwoom()
        // 실제 자격증명 복원
        if let v = savedKisAppKey        { KeychainHelper.save(v, account: KeychainKey.kisAppKey) }
        if let v = savedKisAppSecret     { KeychainHelper.save(v, account: KeychainKey.kisAppSecret) }
        if let v = savedKisAccountNumber { KeychainHelper.save(v, account: KeychainKey.kisAccountNumber) }
        if let v = savedKiwoomAppKey        { KeychainHelper.save(v, account: KeychainKey.kiwoomAppKey) }
        if let v = savedKiwoomAppSecret     { KeychainHelper.save(v, account: KeychainKey.kiwoomAppSecret) }
        if let v = savedKiwoomAccountNumber { KeychainHelper.save(v, account: KeychainKey.kiwoomAccountNumber) }
        AccountManager.shared.refresh()
        try await super.tearDown()
    }

    // MARK: - KIS 로그인

    func test_loginKIS_setsIsKISConnected() {
        XCTAssertFalse(BrokerSessionManager.shared.isKISConnected)
        BrokerSessionManager.shared.loginKIS(
            appKey: testAppKey, appSecret: testAppSecret,
            accountNumber: testAccount, isMock: true
        )
        XCTAssertTrue(BrokerSessionManager.shared.isKISConnected)
    }

    func test_loginKIS_savesCredentialsToKeychain() {
        BrokerSessionManager.shared.loginKIS(
            appKey: testAppKey, appSecret: testAppSecret,
            accountNumber: testAccount, isMock: false
        )
        XCTAssertEqual(KeychainHelper.load(account: KeychainKey.kisAppKey), testAppKey)
        XCTAssertEqual(KeychainHelper.load(account: KeychainKey.kisAppSecret), testAppSecret)
        XCTAssertEqual(KeychainHelper.load(account: KeychainKey.kisAccountNumber), testAccount)
    }

    func test_loginKIS_invalidatesAccountManagerCache() {
        // 로그인 전 캐시 강제 채우기
        _ = AccountManager.connectedAccountIds

        BrokerSessionManager.shared.loginKIS(
            appKey: testAppKey, appSecret: testAppSecret,
            accountNumber: testAccount, isMock: true
        )
        // 로그인 후 새로 읽으면 방금 저장한 appKey가 반영돼야 함
        let expectedId = "KIS-" + String(testAppKey.prefix(8))
        XCTAssertTrue(AccountManager.connectedAccountIds.contains(expectedId),
                      "loginKIS 후 connectedAccountIds에 새 계정이 포함돼야 함")
    }

    // MARK: - KIS 로그아웃

    func test_logoutKIS_clearsIsKISConnected() {
        BrokerSessionManager.shared.loginKIS(
            appKey: testAppKey, appSecret: testAppSecret,
            accountNumber: testAccount, isMock: true
        )
        XCTAssertTrue(BrokerSessionManager.shared.isKISConnected)

        BrokerSessionManager.shared.logoutKIS()
        XCTAssertFalse(BrokerSessionManager.shared.isKISConnected)
    }

    func test_logoutKIS_deletesKeychainCredentials() {
        BrokerSessionManager.shared.loginKIS(
            appKey: testAppKey, appSecret: testAppSecret,
            accountNumber: testAccount, isMock: true
        )
        BrokerSessionManager.shared.logoutKIS()

        XCTAssertNil(KeychainHelper.load(account: KeychainKey.kisAppKey))
        XCTAssertNil(KeychainHelper.load(account: KeychainKey.kisAppSecret))
        XCTAssertNil(KeychainHelper.load(account: KeychainKey.kisAccountNumber))
    }

    func test_logoutKIS_invalidatesAccountManagerCache() {
        BrokerSessionManager.shared.loginKIS(
            appKey: testAppKey, appSecret: testAppSecret,
            accountNumber: testAccount, isMock: true
        )
        let expectedId = "KIS-" + String(testAppKey.prefix(8))
        XCTAssertTrue(AccountManager.connectedAccountIds.contains(expectedId))

        BrokerSessionManager.shared.logoutKIS()
        XCTAssertFalse(AccountManager.connectedAccountIds.contains(expectedId),
                       "logoutKIS 후 connectedAccountIds에서 해당 계정이 제거돼야 함")
    }

    // MARK: - AccountManager 캐시 일관성

    func test_accountManagerCache_freshAfterDoubleLogin() {
        BrokerSessionManager.shared.loginKIS(
            appKey: testAppKey, appSecret: testAppSecret,
            accountNumber: testAccount, isMock: true
        )
        let first = AccountManager.connectedAccountIds

        BrokerSessionManager.shared.logoutKIS()
        BrokerSessionManager.shared.loginKIS(
            appKey: "NEWKEY12", appSecret: testAppSecret,
            accountNumber: testAccount, isMock: true
        )
        let second = AccountManager.connectedAccountIds

        XCTAssertNotEqual(first, second,
                          "appKey가 바뀌면 캐시가 무효화돼 다른 계정 ID가 반환돼야 함")

        // 정리
        BrokerSessionManager.shared.logoutKIS()
        KeychainHelper.delete(account: KeychainKey.kisAppKey)
    }

    // MARK: - 헬퍼

    private func cleanupKeychain() {
        KeychainHelper.delete(account: KeychainKey.kisAppKey)
        KeychainHelper.delete(account: KeychainKey.kisAppSecret)
        KeychainHelper.delete(account: KeychainKey.kisAccountNumber)
        KeychainHelper.delete(account: KeychainKey.kiwoomAppKey)
        KeychainHelper.delete(account: KeychainKey.kiwoomAppSecret)
        KeychainHelper.delete(account: KeychainKey.kiwoomAccountNumber)
        AccountManager.shared.refresh()
    }
}
