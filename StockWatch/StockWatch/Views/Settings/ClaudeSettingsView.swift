import SwiftUI

struct ClaudeSettingsView: View {
    @AppStorage(UserDefaultsKey.screenerClaudeEnabled) private var claudeEnabled = false
    @State private var apiKeyInput = ""
    @State private var isConfigured = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider()
            HStack {
                Text("AI 종목 분석").font(.headline)
                Spacer()
                Toggle("", isOn: $claudeEnabled).labelsHidden()
            }

            if claudeEnabled {
                if isConfigured {
                    HStack(spacing: 8) {
                        Circle().fill(.green).frame(width: 8, height: 8)
                        Text("Anthropic API 키 저장됨")
                            .font(.subheadline).foregroundStyle(.secondary)
                        Spacer()
                        Button("삭제", role: .destructive) {
                            KeychainHelper.delete(account: KeychainKey.anthropicApiKey)
                            isConfigured = false
                        }
                        .buttonStyle(.borderless).foregroundStyle(.red).font(.caption)
                    }
                    .padding(10)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                } else {
                    HStack(spacing: 8) {
                        SecureField("Anthropic API 키", text: $apiKeyInput)
                        Button("저장") {
                            let key = apiKeyInput.trimmingCharacters(in: .whitespaces)
                            guard !key.isEmpty else { return }
                            KeychainHelper.save(key, account: KeychainKey.anthropicApiKey)
                            isConfigured = true
                            apiKeyInput = ""
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(apiKeyInput.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
                Text("스크리닝 결과를 Claude AI로 분석합니다. claude.ai/settings에서 API 키를 발급하세요.")
                    .font(.caption2).foregroundStyle(.tertiary)
            } else {
                Text("활성화하면 종목 스크리닝 결과를 Claude AI로 분석할 수 있습니다.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .onAppear {
            isConfigured = !(KeychainHelper.load(account: KeychainKey.anthropicApiKey) ?? "").isEmpty
        }
    }
}
