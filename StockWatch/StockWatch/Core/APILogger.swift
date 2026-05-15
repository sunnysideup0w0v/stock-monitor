import Foundation

/// 개발용 API 요청/응답 파일 로거.
/// ~/Documents/study/stock-monitor/logs/api-YYYY-MM-DD.log 에 기록.
enum APILogger {

    private static let logsDir: URL = {
        let path = ("~/Documents/study/stock-monitor/logs" as NSString).expandingTildeInPath
        let url = URL(fileURLWithPath: path)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    static func log(_ message: String, tag: String = "API") {
        let now = Date()

        let dateFmt = DateFormatter()
        dateFmt.dateFormat = "yyyy-MM-dd"
        dateFmt.locale = Locale(identifier: "en_US_POSIX")

        let timeFmt = DateFormatter()
        timeFmt.dateFormat = "HH:mm:ss.SSS"
        timeFmt.locale = Locale(identifier: "en_US_POSIX")

        let line = "[\(timeFmt.string(from: now))] [\(tag)] \(message)\n"
        let fileURL = logsDir.appendingPathComponent("api-\(dateFmt.string(from: now)).log")

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

    static func logRequest(tag: String, url: String, headers: [String: String] = [:], body: String = "") {
        var lines = ["→ \(url)"]
        if !headers.isEmpty {
            lines.append("  headers: \(headers.filter { $0.key != "authorization" })")
        }
        if !body.isEmpty { lines.append("  body: \(body)") }
        log(lines.joined(separator: "\n"), tag: tag)
    }

    static func logResponse(tag: String, status: Int, body: String) {
        log("← HTTP \(status)\n  \(body.prefix(800))", tag: tag)
    }
}
