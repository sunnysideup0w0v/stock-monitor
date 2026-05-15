import Foundation

enum CrashLogger {
    static func install() {
        NSSetUncaughtExceptionHandler { exception in
            CrashLogger.write(exception: exception)
        }
    }

    private static func write(exception: NSException) {
        let logsDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/StockWatch")
        try? FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)

        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        let fileURL = logsDir.appendingPathComponent("crash-\(fmt.string(from: Date())).log")

        fmt.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let entry = """
        [\(fmt.string(from: Date()))]
        Name:   \(exception.name.rawValue)
        Reason: \(exception.reason ?? "Unknown")
        \(exception.callStackSymbols.joined(separator: "\n"))
        """

        let separator = "\n\n---\n\n"
        if let existing = try? String(contentsOf: fileURL, encoding: .utf8) {
            try? (existing + separator + entry).write(to: fileURL, atomically: true, encoding: .utf8)
        } else {
            try? entry.write(to: fileURL, atomically: true, encoding: .utf8)
        }
    }
}
