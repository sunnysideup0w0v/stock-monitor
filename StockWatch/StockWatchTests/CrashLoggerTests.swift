import XCTest
@testable import StockWatch

final class CrashLoggerTests: XCTestCase {

    private var createdFileURL: URL?

    override func tearDown() async throws {
        // 테스트에서 생성된 로그 파일 삭제
        if let url = createdFileURL {
            try? FileManager.default.removeItem(at: url)
        }
        try await super.tearDown()
    }

    // MARK: - write()

    func test_write_createsLogFileInCorrectDirectory() {
        let logsDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/StockWatch")

        let exception = NSException(name: .genericException, reason: "test crash", userInfo: nil)
        CrashLogger.write(exception: exception)

        // 디렉터리가 생성됐는지 확인
        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: logsDir.path, isDirectory: &isDir)
        XCTAssertTrue(exists && isDir.boolValue, "~/Library/Logs/StockWatch 디렉터리가 생성되어야 함")

        // 오늘 날짜의 로그 파일이 존재하는지 확인
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        let logURL = logsDir.appendingPathComponent("crash-\(fmt.string(from: Date())).log")
        createdFileURL = logURL
        XCTAssertTrue(FileManager.default.fileExists(atPath: logURL.path), "오늘 날짜 로그 파일이 생성되어야 함")
    }

    func test_write_logFileContainsExceptionDetails() throws {
        let exception = NSException(name: NSExceptionName("TestException"), reason: "테스트 이유", userInfo: nil)
        CrashLogger.write(exception: exception)

        let logsDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/StockWatch")
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        let logURL = logsDir.appendingPathComponent("crash-\(fmt.string(from: Date())).log")
        createdFileURL = logURL

        let content = try String(contentsOf: logURL, encoding: .utf8)
        XCTAssertTrue(content.contains("TestException"), "예외 이름이 로그에 포함되어야 함")
        XCTAssertTrue(content.contains("테스트 이유"), "예외 이유가 로그에 포함되어야 함")
    }

    func test_write_appendsToExistingFile() throws {
        let exception1 = NSException(name: NSExceptionName("First"), reason: "first", userInfo: nil)
        let exception2 = NSException(name: NSExceptionName("Second"), reason: "second", userInfo: nil)

        CrashLogger.write(exception: exception1)
        CrashLogger.write(exception: exception2)

        let logsDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/StockWatch")
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        let logURL = logsDir.appendingPathComponent("crash-\(fmt.string(from: Date())).log")
        createdFileURL = logURL

        let content = try String(contentsOf: logURL, encoding: .utf8)
        XCTAssertTrue(content.contains("First"), "첫 번째 예외가 로그에 있어야 함")
        XCTAssertTrue(content.contains("Second"), "두 번째 예외가 로그에 추가되어야 함")
    }
}
