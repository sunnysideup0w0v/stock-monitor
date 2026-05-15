import Foundation

/// 등록된 BrokerAdapter 인스턴스를 이름 기반으로 관리하는 레지스트리.
/// QuoteManager가 단일 어댑터를 사용하는 현재 구조에서도,
/// Phase 4.4 복수 브로커 통합 시 QuoteManager가 이 레지스트리를 통해 어댑터를 조회한다.
@MainActor
final class BrokerRegistry {
    static let shared = BrokerRegistry()
    private init() {}

    // brokerName → adapter
    private var registry: [String: any BrokerAdapter] = [:]

    /// 등록된 모든 어댑터 (등록 순서 미보장)
    var adapters: [any BrokerAdapter] { Array(registry.values) }

    /// 어댑터 등록. 같은 이름이 이미 있으면 교체.
    func register(_ adapter: any BrokerAdapter) {
        registry[adapter.brokerName] = adapter
    }

    /// 이름으로 어댑터 제거. 제거 전 disconnect() 호출.
    func unregister(brokerName: String) {
        guard let adapter = registry[brokerName] else { return }
        Task { await adapter.disconnect() }
        registry.removeValue(forKey: brokerName)
    }

    /// 이름으로 어댑터 조회
    func adapter(named brokerName: String) -> (any BrokerAdapter)? {
        registry[brokerName]
    }

    /// 등록 여부 확인
    func isRegistered(brokerName: String) -> Bool {
        registry[brokerName] != nil
    }

    /// 모든 어댑터 해제
    func unregisterAll() {
        for adapter in registry.values {
            Task { await adapter.disconnect() }
        }
        registry.removeAll()
    }
}
