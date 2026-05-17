import SwiftUI

struct KRXSettingsView: View {
    @State private var stockCount: Int = 0
    @State private var lastUpdated: Date? = nil
    @State private var isFetching = false
    @State private var statusMessage: String? = nil
    @State private var apiKeyInput = ""
    @State private var isApiKeyConfigured = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider()
            Text("KRX 시장 데이터").font(.headline)

            HStack(spacing: 8) {
                Circle()
                    .fill(stockCount > 0 ? Color.green : Color.gray)
                    .frame(width: 8, height: 8)
                if stockCount > 0 {
                    Text("\(stockCount)개 종목")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("(\(KRXManager.shared.lastTradingDate()) 기준)")
                        .font(.caption2).foregroundStyle(.tertiary)
                    if isApiKeyConfigured {
                        Text("· KRX OpenAPI")
                            .font(.caption2).foregroundStyle(.blue)
                    } else {
                        Text("· 네이버 증권")
                            .font(.caption2).foregroundStyle(.tertiary)
                    }
                } else {
                    Text("데이터 없음").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    fetch()
                } label: {
                    if isFetching {
                        HStack(spacing: 4) {
                            ProgressView().scaleEffect(0.7).frame(width: 14, height: 14)
                            Text("업데이트 중…").font(.caption)
                        }
                    } else {
                        Label("지금 업데이트", systemImage: "arrow.clockwise").font(.caption)
                    }
                }
                .buttonStyle(.borderless)
                .disabled(isFetching)
            }
            .padding(10)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))

            if let msg = statusMessage {
                Text(msg)
                    .font(.caption)
                    .foregroundStyle(msg.hasPrefix("✓") ? .green : .red)
            }

            Divider()
            Text("KRX OpenAPI 키").font(.subheadline).foregroundStyle(.secondary)

            if isApiKeyConfigured {
                HStack(spacing: 8) {
                    Circle().fill(.blue).frame(width: 8, height: 8)
                    Text("KRX OpenAPI 키 저장됨 — 공식 API 사용 중")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("삭제", role: .destructive) {
                        KeychainHelper.delete(account: "krx.apiKey")
                        isApiKeyConfigured = false
                    }
                    .buttonStyle(.borderless).foregroundStyle(.red).font(.caption)
                }
                .padding(10)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
            } else {
                HStack(spacing: 8) {
                    SecureField("KRX OpenAPI 인증키", text: $apiKeyInput)
                    Button("저장") {
                        let key = apiKeyInput.trimmingCharacters(in: .whitespaces)
                        guard !key.isEmpty else { return }
                        KeychainHelper.save(key, account: "krx.apiKey")
                        isApiKeyConfigured = true
                        apiKeyInput = ""
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(apiKeyInput.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            Text("openapi.krx.co.kr에서 발급. 미설정 시 네이버 증권 API로 대체 (업종 정보 미제공).")
                .font(.caption2).foregroundStyle(.tertiary)
        }
        .onAppear {
            loadStats()
            isApiKeyConfigured = !(KeychainHelper.load(account: "krx.apiKey") ?? "").isEmpty
        }
        .onReceive(NotificationCenter.default.publisher(for: .krxDataUpdated)) { _ in
            loadStats()
        }
    }

    private func fetch() {
        guard !isFetching else { return }
        isFetching = true
        statusMessage = nil
        Task {
            await KRXManager.shared.fetchAndStore()
            loadStats()
            if stockCount == 0 {
                statusMessage = "수신 실패 — 네트워크 연결을 확인하거나 잠시 후 다시 시도하세요"
            } else {
                statusMessage = "✓ 업데이트 완료"
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    if statusMessage?.hasPrefix("✓") == true { statusMessage = nil }
                }
            }
        }
    }

    private func loadStats() {
        stockCount = (try? DatabaseManager.shared.stockUniverseCount()) ?? 0
        lastUpdated = try? DatabaseManager.shared.stockUniverseLastUpdated()
        isFetching = KRXManager.shared.isFetching
        isApiKeyConfigured = !(KeychainHelper.load(account: "krx.apiKey") ?? "").isEmpty
    }
}
