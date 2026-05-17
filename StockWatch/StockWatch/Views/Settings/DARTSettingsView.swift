import SwiftUI

struct DARTDisclosureTypeOption: Identifiable {
    let code: String
    let name: String
    var id: String { code }

    static let all: [DARTDisclosureTypeOption] = [
        .init(code: "A", name: "정기공시"),
        .init(code: "B", name: "주요사항"),
        .init(code: "C", name: "발행공시"),
        .init(code: "D", name: "지분공시"),
        .init(code: "E", name: "기타공시"),
        .init(code: "I", name: "거래소공시"),
    ]
}

struct DARTSettingsView: View {
    @State private var isConfigured = false
    @State private var apiKeyInput = ""
    @State private var isSaving = false
    @State private var enabledTypes: Set<String> = []

    private static let allCodes = Set(DARTDisclosureTypeOption.all.map(\.code))

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider()
            Text("DART 공시 알림").font(.headline)

            if isConfigured {
                dartConfiguredView
            } else {
                dartSetupView
            }
        }
        .onAppear {
            isConfigured = DARTManager.shared.isConfigured
            loadFilterTypes()
        }
    }

    private var dartConfiguredView: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Circle().fill(.green).frame(width: 8, height: 8)
                Text("공시 알림 활성화됨").font(.subheadline).foregroundStyle(.secondary)
                Spacer()
                Button("삭제", role: .destructive) {
                    KeychainHelper.delete(account: KeychainKey.dartApiKey)
                    DARTManager.shared.stop()
                    isConfigured = false
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.red)
                .font(.caption)
            }
            .padding(10)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))

            Text("알림 받을 공시 종류").font(.subheadline)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())],
                      alignment: .leading, spacing: 6) {
                ForEach(DARTDisclosureTypeOption.all) { type in
                    Toggle(type.name, isOn: Binding(
                        get: { enabledTypes.contains(type.code) },
                        set: { isOn in
                            if isOn { enabledTypes.insert(type.code) }
                            else { enabledTypes.remove(type.code) }
                            saveFilterTypes()
                        }
                    ))
                    .toggleStyle(.checkbox)
                    .font(.caption)
                }
            }
            Text("선택하지 않으면 모든 종류를 알림으로 받습니다.")
                .font(.caption2).foregroundStyle(.tertiary)
        }
    }

    private var dartSetupView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("DART Open API 키를 입력하면 관심종목의 공시를 5분마다 확인합니다.")
                .font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 8) {
                SecureField("API 키 입력", text: $apiKeyInput)
                Button("저장") { saveKey() }
                    .buttonStyle(.borderedProminent)
                    .disabled(apiKeyInput.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
            }
        }
    }

    private func saveKey() {
        let key = apiKeyInput.trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty else { return }
        isSaving = true
        KeychainHelper.save(key, account: KeychainKey.dartApiKey)
        let symbols = (try? DatabaseManager.shared.fetchWatchlist().map { $0.symbol }) ?? []
        DARTManager.shared.start(symbols: symbols)
        apiKeyInput = ""
        isConfigured = true
        isSaving = false
    }

    private func loadFilterTypes() {
        let saved = UserDefaults.standard.stringArray(forKey: UserDefaultsKey.dartFilterTypes) ?? []
        enabledTypes = saved.isEmpty ? Self.allCodes : Set(saved)
    }

    private func saveFilterTypes() {
        if enabledTypes == Self.allCodes {
            UserDefaults.standard.removeObject(forKey: UserDefaultsKey.dartFilterTypes)
        } else {
            UserDefaults.standard.set(Array(enabledTypes), forKey: UserDefaultsKey.dartFilterTypes)
        }
    }
}
