import Network
import Foundation

/// 네트워크 경로 변화를 감지하고 재연결 시 브로커 상태를 자동 점검한다.
@MainActor
final class NetworkMonitor {
    static let shared = NetworkMonitor()

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.personal.StockWatch.netmonitor", qos: .utility)
    private var previousStatus: NWPath.Status?
    private var checkTask: Task<Void, Never>?

    private init() {}

    func start() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor [weak self] in
                self?.handlePathUpdate(path)
            }
        }
        monitor.start(queue: queue)
    }

    private func handlePathUpdate(_ path: NWPath) {
        let newStatus = path.status
        defer { previousStatus = newStatus }

        // 첫 번째 콜백은 앱 시작 시 초기 상태 기록만 (재연결로 취급하지 않음)
        guard let prev = previousStatus else { return }

        // 끊김 → 복구 전환일 때만 처리
        guard prev != .satisfied, newStatus == .satisfied else { return }

        AppLogger.log("NetworkMonitor: 네트워크 재연결 감지", level: .info, category: "App")

        // 중복 실행 방지: 이전 체크 취소 후 재시작
        checkTask?.cancel()
        checkTask = Task {
            // IP 안정화 대기
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            await BrokerSessionManager.shared.checkAllSessions()
        }
    }
}
