import XCTest
@testable import StockWatch

final class KeychainHelperTests: XCTestCase {

    // 실제 앱 키와 절대 겹치지 않는 테스트 전용 계정 이름
    private let keyA = "test.refactor.keychainA"
    private let keyB = "test.refactor.keychainB"

    override func setUp() {
        super.setUp()
        KeychainHelper.delete(account: keyA)
        KeychainHelper.delete(account: keyB)
    }

    override func tearDown() {
        KeychainHelper.delete(account: keyA)
        KeychainHelper.delete(account: keyB)
        super.tearDown()
    }

    // MARK: - load

    func test_load_nonExistentKey_returnsNil() {
        XCTAssertNil(KeychainHelper.load(account: keyA))
    }

    // MARK: - save / load 라운드트립

    func test_saveAndLoad_returnsSameASCIIValue() {
        KeychainHelper.save("hello-world-123", account: keyA)
        XCTAssertEqual(KeychainHelper.load(account: keyA), "hello-world-123")
    }

    func test_saveAndLoad_koreanString_roundtrips() {
        KeychainHelper.save("한국투자증권-테스트키-값", account: keyA)
        XCTAssertEqual(KeychainHelper.load(account: keyA), "한국투자증권-테스트키-값")
    }

    func test_save_overwritesExistingValue() {
        KeychainHelper.save("first-value", account: keyA)
        KeychainHelper.save("second-value", account: keyA)
        XCTAssertEqual(KeychainHelper.load(account: keyA), "second-value")
    }

    // MARK: - delete

    func test_delete_thenLoad_returnsNil() {
        KeychainHelper.save("some-value", account: keyA)
        KeychainHelper.delete(account: keyA)
        XCTAssertNil(KeychainHelper.load(account: keyA))
    }

    func test_delete_nonExistentKey_doesNotCrash() {
        KeychainHelper.delete(account: keyA)
        XCTAssertNil(KeychainHelper.load(account: keyA))
    }

    // MARK: - 키 독립성

    func test_multipleDistinctKeys_areIndependent() {
        KeychainHelper.save("value-a", account: keyA)
        KeychainHelper.save("value-b", account: keyB)
        XCTAssertEqual(KeychainHelper.load(account: keyA), "value-a")
        XCTAssertEqual(KeychainHelper.load(account: keyB), "value-b")
    }

    func test_deleteOneKey_doesNotAffectAnother() {
        KeychainHelper.save("value-a", account: keyA)
        KeychainHelper.save("value-b", account: keyB)
        KeychainHelper.delete(account: keyA)
        XCTAssertNil(KeychainHelper.load(account: keyA))
        XCTAssertEqual(KeychainHelper.load(account: keyB), "value-b")
    }
}
