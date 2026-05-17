import SwiftUI

struct WatchlistSettingsView: View {
    @State private var items: [WatchlistItem] = []
    @State private var isLoggedIn: Bool = true
    @State private var symbol = ""
    @State private var name = ""
    @State private var alias = ""
    @State private var group: WatchlistGroup = .watchlist
    @AppStorage("Popover.showWatchlistDetail") private var showPopoverDetail = false
    @State private var errorMessage: String?

    var body: some View {
        SettingsTabContainer(title: "관심종목") {
            if !isLoggedIn {
                accountRequiredView
            } else {
                List {
                    ForEach(items, id: \.id) { item in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.alias ?? item.name).font(.body)
                                Text(item.symbol).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(item.group.displayName)
                                .font(.caption)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(.quaternary, in: Capsule())
                            Button {
                                deleteItem(item)
                            } label: {
                                Image(systemName: "trash").foregroundStyle(.red)
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }
                .listStyle(.bordered)

                SettingsFormSection(title: "종목 추가") {
                    Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 8) {
                        GridRow {
                            Text("종목코드").gridColumnAlignment(.trailing)
                            TextField("예: 005930", text: $symbol).frame(width: 120)
                            Text("종목명").gridColumnAlignment(.trailing)
                            TextField("예: 삼성전자", text: $name).frame(width: 120)
                        }
                        GridRow {
                            Text("별칭").gridColumnAlignment(.trailing)
                            TextField("선택사항", text: $alias).frame(width: 120)
                            Text("그룹").gridColumnAlignment(.trailing)
                            Picker("", selection: $group) {
                                ForEach([WatchlistGroup.watchlist, .longTerm, .shortTerm], id: \.self) {
                                    Text($0.displayName).tag($0)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 120)
                        }
                    }

                    Button("추가") { addItem() }
                        .disabled(symbol.trimmingCharacters(in: .whitespaces).isEmpty ||
                                  name.trimmingCharacters(in: .whitespaces).isEmpty)
                }

                SettingsFormSection(title: "팝오버 표시") {
                    Toggle("종목코드·그룹 표시", isOn: $showPopoverDetail)
                }
            }
        }
        .onAppear { loadItems() }
        .alert("저장 오류", isPresented: .init(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("확인") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var accountRequiredView: some View {
        AccountRequiredView(description: "계좌 연결 탭에서 API 키를 입력하면\n관심종목을 관리할 수 있습니다.")
    }

    private func loadItems() {
        isLoggedIn = AccountManager.isAnyConnected
        items = (try? DatabaseManager.shared.fetchWatchlist()) ?? []
    }

    private func addItem() {
        var item = WatchlistItem(
            id: nil,
            symbol: symbol.trimmingCharacters(in: .whitespaces).uppercased(),
            name: name.trimmingCharacters(in: .whitespaces),
            alias: alias.trimmingCharacters(in: .whitespaces).isEmpty ? nil : alias.trimmingCharacters(in: .whitespaces),
            group: group
        )
        do {
            try DatabaseManager.shared.insert(&item)
            symbol = ""; name = ""; alias = ""
            loadItems()
            QuoteManager.shared.startPolling(symbols: items.map { $0.symbol })
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteItem(_ item: WatchlistItem) {
        do {
            try DatabaseManager.shared.delete(item)
            loadItems()
            QuoteManager.shared.startPolling(symbols: items.map { $0.symbol })
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
