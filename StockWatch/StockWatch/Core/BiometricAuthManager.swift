import LocalAuthentication
import Foundation
import Security

/// Touch ID / Face ID 를 사용해 자격증명을 Keychain에 안전하게 저장하고 자동 입력하는 유틸리티.
///
/// 보안 설계:
/// - `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`: iCloud 미동기, 타 기기 이전 불가
/// - `.biometryAny`: 생체 인증만 허용 (암호 폴백 없음)
/// - `kSecUseAuthenticationContext`: 평가된 LAContext를 키체인 읽기에 재사용해 Touch ID 프롬프트 1회만 표시
/// - 저장 여부는 UserDefaults 플래그로 관리 (macOS biometric Keychain 쿼리의 불안정성 회피)
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

    private static let keychainService = "com.personal.StockWatch.biometric"
    private static func savedKey(_ prefix: String) -> String { "biometric.\(prefix).saved" }

    /// Touch ID 보호 Keychain에 자격증명 저장.
    /// - Returns: 저장 성공 여부. 실패 시 AppLogger에 원인 기록.
    @discardableResult
    static func saveCredentials(_ creds: Credentials, keyPrefix: String) -> Bool {
        guard isAvailable else {
            AppLogger.log("BiometricKeychain: Touch ID 사용 불가", level: .error, category: "App")
            return false
        }

        var cfError: Unmanaged<CFError>?
        // kSecAttrAccessibleWhenUnlockedThisDeviceOnly: 로그인 암호 없는 Mac에서도 동작
        // (kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly는 암호 필수라 저장 실패 가능)
        guard let access = SecAccessControlCreateWithFlags(
            kCFAllocatorDefault,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            .biometryAny,
            &cfError
        ) else {
            let desc = cfError?.takeRetainedValue().localizedDescription ?? "unknown"
            AppLogger.log("BiometricKeychain: SecAccessControl 생성 실패 — \(desc)", level: .error, category: "App")
            return false
        }

        let pairs: [(String, String)] = [
            (keyPrefix + ".appKey",        creds.appKey),
            (keyPrefix + ".appSecret",     creds.appSecret),
            (keyPrefix + ".accountNumber", creds.accountNumber),
        ]
        for (key, value) in pairs {
            deleteKeychainItem(key: key)
            guard let data = value.data(using: .utf8) else { continue }
            let status = SecItemAdd([
                kSecClass as String:             kSecClassGenericPassword,
                kSecAttrService as String:       keychainService,
                kSecAttrAccount as String:       key,
                kSecValueData as String:         data,
                kSecAttrAccessControl as String: access,
            ] as CFDictionary, nil)
            if status != errSecSuccess {
                AppLogger.log("BiometricKeychain: SecItemAdd 실패 — key=\(key), status=\(status)", level: .error, category: "App")
                return false
            }
        }

        UserDefaults.standard.set(true, forKey: savedKey(keyPrefix))
        AppLogger.log("BiometricKeychain: 저장 완료 — prefix=\(keyPrefix)", level: .info, category: "App")
        return true
    }

    /// Touch ID 인증 후 자격증명 반환.
    /// LAContext 평가 → 동일 컨텍스트로 Keychain 읽기 (단일 Touch ID 프롬프트).
    static func loadCredentials(keyPrefix: String, reason: String) async throws -> Credentials {
        guard isAvailable else { throw CredentialError.biometricsUnavailable }
        guard hasStoredCredentials(keyPrefix: keyPrefix) else { throw CredentialError.noStoredCredentials }

        let ctx = LAContext()
        let svc = keychainService
        let pfx = keyPrefix

        return try await withCheckedThrowingContinuation { continuation in
            ctx.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason) { success, error in
                guard success else {
                    let laCode = (error as? LAError)?.code
                    let cancelled = laCode == .userCancel || laCode == .systemCancel || laCode == .appCancel
                    continuation.resume(throwing: cancelled ? CredentialError.authCancelled : CredentialError.authFailed)
                    return
                }

                // 중첩 함수 대신 인라인 — Swift 6 isolated local function 제약 회피
                var r1: AnyObject?, r2: AnyObject?, r3: AnyObject?
                let ok1 = SecItemCopyMatching([
                    kSecClass as String: kSecClassGenericPassword,
                    kSecAttrService as String: svc,
                    kSecAttrAccount as String: pfx + ".appKey",
                    kSecReturnData as String: true,
                    kSecMatchLimit as String: kSecMatchLimitOne,
                    kSecUseAuthenticationContext as String: ctx,
                ] as CFDictionary, &r1) == errSecSuccess
                let ok2 = SecItemCopyMatching([
                    kSecClass as String: kSecClassGenericPassword,
                    kSecAttrService as String: svc,
                    kSecAttrAccount as String: pfx + ".appSecret",
                    kSecReturnData as String: true,
                    kSecMatchLimit as String: kSecMatchLimitOne,
                    kSecUseAuthenticationContext as String: ctx,
                ] as CFDictionary, &r2) == errSecSuccess
                let ok3 = SecItemCopyMatching([
                    kSecClass as String: kSecClassGenericPassword,
                    kSecAttrService as String: svc,
                    kSecAttrAccount as String: pfx + ".accountNumber",
                    kSecReturnData as String: true,
                    kSecMatchLimit as String: kSecMatchLimitOne,
                    kSecUseAuthenticationContext as String: ctx,
                ] as CFDictionary, &r3) == errSecSuccess

                guard ok1, let d1 = r1 as? Data, let appKey = String(data: d1, encoding: .utf8),
                      ok2, let d2 = r2 as? Data, let appSecret = String(data: d2, encoding: .utf8),
                      ok3, let d3 = r3 as? Data, let accountNumber = String(data: d3, encoding: .utf8) else {
                    continuation.resume(throwing: CredentialError.readFailed)
                    return
                }
                continuation.resume(returning: Credentials(
                    appKey: appKey, appSecret: appSecret, accountNumber: accountNumber
                ))
            }
        }
    }

    /// 저장 여부 확인 (UserDefaults 기반, Keychain 쿼리 불필요).
    static func hasStoredCredentials(keyPrefix: String) -> Bool {
        UserDefaults.standard.bool(forKey: savedKey(keyPrefix))
    }

    /// 저장된 자격증명 전체 삭제.
    static func deleteCredentials(keyPrefix: String) {
        for suffix in ["appKey", "appSecret", "accountNumber"] {
            deleteKeychainItem(key: keyPrefix + "." + suffix)
        }
        UserDefaults.standard.removeObject(forKey: savedKey(keyPrefix))
    }

    private static func deleteKeychainItem(key: String) {
        SecItemDelete([
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: key,
        ] as CFDictionary)
    }
}
