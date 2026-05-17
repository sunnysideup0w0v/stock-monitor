import Foundation

/// HTTP 에러(4xx/5xx) 전용 파일 로거.
/// ~/Documents/study/stock-monitor/logs/error-YYYY-MM-DD.log 에 기록.
enum APILogger {

    private static let logsDir: URL = {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/StockWatch")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    static func logError(_ message: String, tag: String = "API") {
        let now = Date()

        let dateFmt = DateFormatter()
        dateFmt.dateFormat = "yyyy-MM-dd"
        dateFmt.locale = Locale(identifier: "en_US_POSIX")

        let timeFmt = DateFormatter()
        timeFmt.dateFormat = "HH:mm:ss.SSS"
        timeFmt.locale = Locale(identifier: "en_US_POSIX")

        let line = "[\(timeFmt.string(from: now))] [\(tag)] \(message)\n"
        let fileURL = logsDir.appendingPathComponent("error-\(dateFmt.string(from: now)).log")

        guard let data = line.data(using: .utf8) else { return }

        if FileManager.default.fileExists(atPath: fileURL.path),
           let handle = try? FileHandle(forWritingTo: fileURL) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    /// status >= 400 일 때만 파일에 기록한다.
    static func logResponse(tag: String, status: Int, body: String) {
        guard status >= 400 else { return }
        logError("← HTTP \(status)\n  \(body.prefix(800))", tag: tag)
    }
}
