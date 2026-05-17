import OSLog

/// 앱 이벤트 구조화 로거.
/// Console.app (subsystem: com.personal.StockWatch) + 파일(~/Library/Logs/StockWatch/app-YYYY-MM-DD.log) 이중 기록.
enum AppLogger {
    static let screener = Logger(subsystem: "com.personal.StockWatch", category: "Screener")
    static let app      = Logger(subsystem: "com.personal.StockWatch", category: "App")

    private static let logsDir: URL = {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/StockWatch")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    static func log(_ message: String, level: OSLogType = .default, category: String = "App") {
        let logger = Logger(subsystem: "com.personal.StockWatch", category: category)
        switch level {
        case .error:  logger.error("\(message, privacy: .public)")
        case .fault:  logger.fault("\(message, privacy: .public)")
        case .debug:  logger.debug("\(message, privacy: .public)")
        default:      logger.log("\(message, privacy: .public)")
        }
        writeToFile(message, level: level, category: category)
    }

    private static func writeToFile(_ message: String, level: OSLogType, category: String) {
        let now = Date()
        let dateFmt = DateFormatter()
        dateFmt.dateFormat = "yyyy-MM-dd"
        dateFmt.locale = Locale(identifier: "en_US_POSIX")

        let timeFmt = DateFormatter()
        timeFmt.dateFormat = "HH:mm:ss.SSS"
        timeFmt.locale = Locale(identifier: "en_US_POSIX")

        let levelStr: String
        switch level {
        case .error: levelStr = "ERROR"
        case .fault: levelStr = "FAULT"
        case .debug: levelStr = "DEBUG"
        default:     levelStr = "INFO"
        }

        let line = "[\(timeFmt.string(from: now))] [\(levelStr)] [\(category)] \(message)\n"
        let fileURL = logsDir.appendingPathComponent("app-\(dateFmt.string(from: now)).log")

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
}
