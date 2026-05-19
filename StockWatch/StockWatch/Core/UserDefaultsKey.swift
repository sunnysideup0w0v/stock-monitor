import Foundation

enum UserDefaultsKey {
    static let kisMock               = "KIS.isMock"
    static let kisLoginDate          = "KIS.loginDate"
    static let kiwoomLoginDate       = "Kiwoom.loginDate"
    static let dartFilterTypes       = "DART.filterTypes"
    static let dbV8Migrated          = "DB.v8AccountIdMigrated"
    static let onboardingCompleted   = "Onboarding.completed"
    static let disconnectAlert       = "QuoteManager.disconnectAlert"
    static let alertMarketHours      = "Alert.marketHoursOnly"
    static let snapshotMarketHours   = "Snapshot.marketHoursOnly"
    static let snapshotCustomRanges  = "Snapshot.customRanges"
    static let snapshotKeepDays      = "Snapshot.keepDays"
    static let screenerClaudeEnabled = "Screener.claudeEnabled"
    static let screenerKeepOnReopen  = "Screener.keepOnReopen"
    static let screenerSavedConditions = "Screener.savedConditions"

    // per-symbol 동적 키
    static func dartSeen(_ symbol: String) -> String { "DART.seen.\(symbol)" }
    static func dartLastCheck(_ symbol: String) -> String { "DART.lastCheck.\(symbol)" }
}
