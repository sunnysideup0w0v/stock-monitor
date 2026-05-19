import LocalAuthentication
import Foundation

/// macOS Touch ID / 암호 인증 래퍼.
/// 앱이 샌드박스를 사용하지 않으므로 별도 entitlement 불필요.
enum BiometricAuthManager {

    /// Touch ID / 암호 인증이 가능한 기기인지 확인
    static var isAvailable: Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
    }

    /// 현재 기기에서 사용 가능한 생체 인증 방식 이름 ("Touch ID", "Face ID", "암호")
    static var methodName: String {
        let ctx = LAContext()
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil) else {
            return "암호"
        }
        switch ctx.biometryType {
        case .faceID:  return "Face ID"
        case .touchID: return "Touch ID"
        default:       return "생체 인증"
        }
    }

    /// 인증 방식에 맞는 SF Symbol 이름
    static var methodIcon: String {
        let ctx = LAContext()
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil) else {
            return "lock.fill"
        }
        switch ctx.biometryType {
        case .faceID:  return "faceid"
        case .touchID: return "touchid"
        default:       return "person.badge.key.fill"
        }
    }

    /// 인증 요청. 생체 인식 불가 시 기기 암호로 폴백.
    /// - Returns: 인증 성공 여부 (인증 수단이 없으면 true 반환해 통과)
    static func authenticate(reason: String) async -> Bool {
        let ctx = LAContext()
        let policy: LAPolicy = ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
            ? .deviceOwnerAuthenticationWithBiometrics
            : .deviceOwnerAuthentication

        guard ctx.canEvaluatePolicy(policy, error: nil) else { return true }

        return await withCheckedContinuation { continuation in
            ctx.evaluatePolicy(policy, localizedReason: reason) { success, _ in
                continuation.resume(returning: success)
            }
        }
    }
}
