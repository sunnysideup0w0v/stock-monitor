import LocalAuthentication
import Foundation
import Security

/// Touch ID / Face ID 자동 입력 유틸리티.
///
/// 보안 설계:
/// - 자격증명은 별도 Keychain 서비스에 일반 항목으로 저장 (로그아웃 후에도 유지)
/// - 읽기 전에 반드시 LAContext.evaluatePolicy로 Touch ID 인증 수행 (앱 레이어 보호)
/// - Ad-hoc 서명 환경에서 SecAccessControl biometric flag가 동작하지 않는 문제 회피
/// - 저장 여부는 UserDefaults 플래그로 관리
enum BiometricAuthManager {

    // MARK: - 기기 능력

    static var isAvailable: Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
    }

    static var methodName: String {
        let ctx = LAContext()
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil) else { return "암호" }
        switch ctx.biometryType {
        case .faceID:  return "Face ID"
        case .touchID: return "Touch ID"
        default:       return "생체 인증"
        }
    }

    static var methodIcon: String {
        let ctx = LAContext()
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil) else { return "lock.fill" }
        switch ctx.biometryType {
        case .faceID:  return "faceid"
        case .touchID: return "touchid"
        default:       return "person.badge.key.fill"
        }
    }

    // MARK: - 타입

    struct Credentials: Sendable {
        let appKey: String
        let appSecret: String
        let accountNumber: String
    }

    enum CredentialError: LocalizedError {
        case biometricsUnavailable
        case noStoredCredentials
        case authCancelled
        case authFailed
        case readFailed

        var errorDescription: String? {
            switch self {
            case .biometricsUnavailable: return "Touch ID가 등록되어 있지 않습니다"
            case .noStoredCredentials:   return "저장된 자격증명이 없습니다. 먼저 수동으로 로그인해 주세요"
            case .authCancelled:         return nil
            case .authFailed:            return "인증에 실패했습니다"
            case .readFailed:            return "저장된 정보를 불러오는 데 실패했습니다"
            }
        }
    }

    // MARK: - Keychain

    private static let keychainService = "com.personal.StockWatch.autofill"
    private static func savedFlagKey(_ prefix: String) -> String { "biometric.\(prefix).saved" }

    /// 자격증명을 별도 Keychain 서비스에 저장 (access control 없음).
    /// - Returns: 저장 성공 여부
    @discardableResult
    static func saveCredentials(_ creds: Credentials, keyPrefix: String) -> Bool {
        let pairs: [(String, String)] = [
            (keyPrefix + ".appKey",        creds.appKey),
            (keyPrefix + ".appSecret",     creds.appSecret),
            (keyPrefix + ".accountNumber", creds.accountNumber),
        ]
        for (account, value) in pairs {
            // 기존 항목 삭제 후 추가
            SecItemDelete([
                kSecClass as String:       kSecClassGenericPassword,
                kSecAttrService as String: keychainService,
                kSecAttrAccount as String: account,
            ] as CFDictionary)

            guard let data = value.data(using: .utf8) else { return false }
            let status = SecItemAdd([
                kSecClass as String:       kSecClassGenericPassword,
                kSecAttrService as String: keychainService,
                kSecAttrAccount as String: account,
                kSecValueData as String:   data,
            ] as CFDictionary, nil)

            if status != errSecSuccess {
                AppLogger.log("BiometricAutofill: 저장 실패 — account=\(account), OSStatus=\(status)", level: .error, category: "App")
                return false
            }
        }
        UserDefaults.standard.set(true, forKey: savedFlagKey(keyPrefix))
        return true
    }

    /// Touch ID 인증 후 자격증명 반환.
    /// 인증 성공 → 일반 Keychain에서 읽기.
    static func loadCredentials(keyPrefix: String, reason: String) async throws -> Credentials {
        guard isAvailable else { throw CredentialError.biometricsUnavailable }
        guard hasStoredCredentials(keyPrefix: keyPrefix) else { throw CredentialError.noStoredCredentials }

        try await evaluateBiometrics(reason: reason)

        guard let appKey        = readItem(keyPrefix + ".appKey"),
              let appSecret     = readItem(keyPrefix + ".appSecret"),
              let accountNumber = readItem(keyPrefix + ".accountNumber") else {
            throw CredentialError.readFailed
        }
        return Credentials(appKey: appKey, appSecret: appSecret, accountNumber: accountNumber)
    }

    /// 저장 여부 확인 (UserDefaults).
    static func hasStoredCredentials(keyPrefix: String) -> Bool {
        UserDefaults.standard.bool(forKey: savedFlagKey(keyPrefix))
    }

    /// 저장된 자격증명 삭제.
    static func deleteCredentials(keyPrefix: String) {
        for suffix in ["appKey", "appSecret", "accountNumber"] {
            SecItemDelete([
                kSecClass as String:       kSecClassGenericPassword,
                kSecAttrService as String: keychainService,
                kSecAttrAccount as String: keyPrefix + "." + suffix,
            ] as CFDictionary)
        }
        UserDefaults.standard.removeObject(forKey: savedFlagKey(keyPrefix))
    }

    // MARK: - Private

    private static func evaluateBiometrics(reason: String) async throws {
        let ctx = LAContext()
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            ctx.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason) { success, error in
                if success {
                    continuation.resume()
                } else {
                    let code = (error as? LAError)?.code
                    let cancelled = code == .userCancel || code == .systemCancel || code == .appCancel
                    continuation.resume(throwing: cancelled ? CredentialError.authCancelled : CredentialError.authFailed)
                }
            }
        }
    }

    private static func readItem(_ account: String) -> String? {
        var result: AnyObject?
        let status = SecItemCopyMatching([
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: account,
            kSecReturnData as String:  true,
            kSecMatchLimit as String:  kSecMatchLimitOne,
        ] as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
