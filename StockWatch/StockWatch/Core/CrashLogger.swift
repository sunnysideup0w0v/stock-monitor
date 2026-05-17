import Foundation

enum CrashLogger {
    static func install() {
        NSSetUncaughtExceptionHandler { exception in
            CrashLogger.write(exception: exception)
        }

        // Swift 크래시(fatal error, 강제 언래핑 등)는 signal로 전달됨
        for sig in [SIGABRT, SIGILL, SIGSEGV, SIGFPE, SIGBUS, SIGTRAP] {
            signal(sig) { caught in
                let name: String
                switch caught {
                case SIGABRT:  name = "SIGABRT"
                case SIGILL:   name = "SIGILL"
                case SIGSEGV:  name = "SIGSEGV"
                case SIGFPE:   name = "SIGFPE"
                case SIGBUS:   name = "SIGBUS"
                case SIGTRAP:  name = "SIGTRAP"
                default:       name = "SIG\(caught)"
                }
                CrashLogger.writeSignal(name)
                // 기본 핸들러로 복원 후 재발생 → 시스템 크래시 리포트도 생성됨
                signal(caught, SIG_DFL)
                raise(caught)
            }
        }
    }

    static func write(exception: NSException) {
        let entry = """
        [NSException]
        Name:   \(exception.name.rawValue)
        Reason: \(exception.reason ?? "Unknown")
        \(exception.callStackSymbols.joined(separator: "\n"))
        """
        append(entry)
    }

    // signal 핸들러 내부: Foundation 동적 할당 최소화, 최대한 단순하게
    static func writeSignal(_ name: String) {
        var symbols = [String]()
        var bt = [UnsafeMutableRawPointer?](repeating: nil, count: 32)
        let count = backtrace(&bt, 32)
        if let syms = backtrace_symbols(&bt, count) {
            for i in 0..<Int(count) {
                if let s = syms[i] { symbols.append(String(cString: s)) }
            }
            free(syms)
        }
        let entry = """
        [Signal: \(name)]
        \(symbols.joined(separator: "\n"))
        """
        append(entry)
    }

    private static func append(_ entry: String) {
        let logsDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/StockWatch")
        try? FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)

        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        let fileURL = logsDir.appendingPathComponent("crash-\(fmt.string(from: Date())).log")

        fmt.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let timestamped = "[\(fmt.string(from: Date()))]\n" + entry
        let separator = "\n\n---\n\n"

        if let existing = try? String(contentsOf: fileURL, encoding: .utf8) {
            try? (existing + separator + timestamped).write(to: fileURL, atomically: true, encoding: .utf8)
        } else {
            try? timestamped.write(to: fileURL, atomically: true, encoding: .utf8)
        }
    }
}
