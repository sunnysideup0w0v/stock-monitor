import LocalAuthentication
import Foundation
import Security

/// Touch ID / Face ID 를 사용해 자격증명을 Keychain에 안전하게 저장하고 자동 입력하는 유틸리티.
///
/// 보안 설계:
/// - `kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly`: 기기 패스코드 필수, iCloud 미동기, 타 기기 이전 불가
/// - `.biometryAny`: 생체 인증만 허용 (암호 폴백 없음)
/// - `kSecUseAuthenticationContext`: 평가된 LAContext를 키체인 읽기에 재사용해 이중 인증 방지
/// - `kSecUseAuthenticationUIFail`: 존재 여부 확인 시 UI를 표시하지 않음
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
            case .authCancelled:         return nil   // 취소는 메시지 불필요
            case .authFailed:            return "인증에 실패했습니다"
            case .readFailed:            return "저장된 정보를 불러오는 데 실패했습니다"
            }
        }
    }

    // MARK: - 키체인

    private static let keychainService = "com.personal.StockWatch.biometric"

    /// Touch ID 보호 Keychain에 자격증명 저장.
    /// 기기 패스코드 미설정 등으로 접근 제어 생성에 실패하면 조용히 무시한다.
    static func saveCredentials(_ creds: Credentials, keyPrefix: String) {
        guard isAvailable else { return }

        var cfError: Unmanaged<CFError>?
        guard let access = SecAccessControlCreateWithFlags(
            kCFAllocatorDefault,
            kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly,
            .biometryAny,
            &cfError
        ) else { return }

        let pairs: [(String, String)] = [
            (keyPrefix + ".appKey",        creds.appKey),
            (keyPrefix + ".appSecret",     creds.appSecret),
            (keyPrefix + ".accountNumber", creds.accountNumber),
        ]
        for (key, value) in pairs {
            deleteKeychainItem(key: key)
            guard let data = value.data(using: .utf8) else { continue }
            let attrs: [String: Any] = [
                kSecClass as String:             kSecClassGenericPassword,
                kSecAttrService as String:       keychainService,
                kSecAttrAccount as String:       key,
                kSecValueData as String:         data,
                kSecAttrAccessControl as String: access,
            ]
            SecItemAdd(attrs as CFDictionary, nil)
        }
    }

    /// Touch ID 인증 후 자격증명 반환.
    /// LAContext 평가 → 동일 컨텍스트로 Keychain 읽기 (단일 Touch ID 프롬프트).
    static func loadCredentials(keyPrefix: String, reason: String) async throws -> Credentials {
        guard isAvailable else { throw CredentialError.biometricsUnavailable }
        guard hasStoredCredentials(keyPrefix: keyPrefix) else { throw CredentialError.noStoredCredentials }

        let ctx = LAContext()
        // keychainService를 지역 상수로 캡처 (String은 Sendable)
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

    /// 인증 없이 저장 여부만 확인 (UI 미표시).
    static func hasStoredCredentials(keyPrefix: String) -> Bool {
        let ctx = LAContext()
        ctx.interactionNotAllowed = true  // Touch ID UI 없이 존재 여부만 확인
        let query: [String: Any] = [
            kSecClass as String:                   kSecClassGenericPassword,
            kSecAttrService as String:             keychainService,
            kSecAttrAccount as String:             keyPrefix + ".appKey",
            kSecReturnAttributes as String:        true,
            kSecUseAuthenticationContext as String: ctx,
        ]
        let status = SecItemCopyMatching(query as CFDictionary, nil)
        // errSecSuccess: 직접 접근 가능, errSecInteractionNotAllowed: 존재하나 인증 필요
        return status == errSecSuccess || status == errSecInteractionNotAllowed
    }

    /// 저장된 자격증명 전체 삭제.
    static func deleteCredentials(keyPrefix: String) {
        for suffix in ["appKey", "appSecret", "accountNumber"] {
            deleteKeychainItem(key: keyPrefix + "." + suffix)
        }
    }

    private static func deleteKeychainItem(key: String) {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
