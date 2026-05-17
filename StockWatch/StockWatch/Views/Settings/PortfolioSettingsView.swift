import SwiftUI

enum ImportSyncMode { case replaceAll, addNew }

struct PortfolioSettingsView: View {
    @State private var items: [PortfolioItem] = []
    @State private var isLoggedIn: Bool = true
    @State private var symbol = ""
    @State private var name = ""
    @State private var averagePriceText = ""
    @State private var quantityText = ""

    @State private var isImporting = false
    @State private var importedItems: [PortfolioItem] = []
    @State private var showImportSheet = false
    @State private var importError: String? = nil

    @State private var selectedBrokerIds: Set<String> = []
    @State private var showImportBrokerAlert = false
    @AppStorage("Popover.showPortfolioDetail") private var showPopoverDetail = false

    private var connectedBrokerIds: [String] { AccountManager.connectedAccountIds }
    private var isMultiBroker: Bool { connectedBrokerIds.count > 1 }

    private var filteredItems: [PortfolioItem] {
        guard isMultiBroker, !selectedBrokerIds.isEmpty,
              selectedBrokerIds.count < connectedBrokerIds.count else { return items }
        return items.filter { selectedBrokerIds.contains($0.accountId) }
    }

    private var filterLabel: String {
        if selectedBrokerIds.count == connectedBrokerIds.count || selectedBrokerIds.isEmpty { return "전체 브로커" }
        return selectedBrokerIds.map { AccountManager.displayName(for:$0) }.joined(separator: ", ")
    }

    private var isShowingAllBrokers: Bool {
        isMultiBroker && (selectedBrokerIds.isEmpty || selectedBrokerIds.count == connectedBrokerIds.count)
    }

    var body: some View {
        SettingsTabContainer(title: "포트폴리오") {
            if !isLoggedIn {
                accountRequiredView
            } else {
                portfolioContentView
            }
        }
        .onAppear { loadItems() }
        .sheet(isPresented: $showImportSheet) {
            PortfolioImportSheetView(items: importedItems) { mode in
                applyImport(mode: mode)
            }
        }
        .confirmationDialog("어느 계좌에서 가져올까요?", isPresented: $showImportBrokerAlert, titleVisibility: .visible) {
            ForEach(connectedBrokerIds, id: \.self) { id in
                Button(AccountManager.displayName(for:id)) { performImport(for: id) }
            }
            Button("취소", role: .cancel) {}
        }
    }

    private var accountRequiredView: some View {
        AccountRequiredView(description: "계좌 연결 탭에서 API 키를 입력하면\n포트폴리오를 관리할 수 있습니다.")
    }

    private var portfolioContentView: some View {
        Group {
            HStack(spacing: 8) {
                if isMultiBroker {
                    Menu {
                        ForEach(connectedBrokerIds, id: \.self) { id in
                            Button {
                                if selectedBrokerIds.contains(id) { selectedBrokerIds.remove(id) }
                                else { selectedBrokerIds.insert(id) }
                            } label: {
                                Label(AccountManager.displayName(for:id),
                                      systemImage: selectedBrokerIds.contains(id) ? "checkmark" : "")
                            }
                        }
                    } label: {
                        Label(filterLabel, systemImage: "line.3.horizontal.decrease.circle")
                            .font(.caption)
                    }
                    .menuStyle(.borderlessButton)
                    .frame(maxWidth: 130, alignment: .leading)
                }

                if let error = importError {
                    Text(error).font(.caption).foregroundStyle(.red)
                } else if !isMultiBroker {
                    Text(importInfoText).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    startImport()
                } label: {
                    if isImporting {
                        HStack(spacing: 4) {
                            ProgressView().scaleEffect(0.7).frame(width: 14, height: 14)
                            Text("불러오는 중…").font(.caption)
                        }
                    } else {
                        Label("계좌에서 가져오기", systemImage: "arrow.down.circle")
                            .font(.caption)
                    }
                }
                .buttonStyle(.borderless)
                .disabled(isImporting)
            }

            List {
                if isShowingAllBrokers {
                    ForEach(connectedBrokerIds, id: \.self) { brokerId in
                        Section(AccountManager.displayName(for:brokerId)) {
                            ForEach(items.filter { $0.accountId == brokerId }, id: \.id) { item in
                                portfolioRow(item)
                            }
                        }
                    }
                } else {
                    ForEach(filteredItems, id: \.id) { item in
                        portfolioRow(item)
                    }
                }
            }
            .listStyle(.bordered)

            SettingsFormSection(title: "종목 추가") {
                Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 8) {
                    GridRow {
                        Text("종목코드").gridColumnAlignment(.trailing)
                        TextField("예: 005930", text: $symbol).frame(width: 120)
                            .accessibilityIdentifier("portfolio.field.symbol")
                        Text("종목명").gridColumnAlignment(.trailing)
                        TextField("예: 삼성전자", text: $name).frame(width: 120)
                            .accessibilityIdentifier("portfolio.field.name")
                    }
                    GridRow {
                        Text("평균매입가").gridColumnAlignment(.trailing)
                        TextField("원", text: $averagePriceText).frame(width: 120)
                            .accessibilityIdentifier("portfolio.field.averagePrice")
                        Text("수량").gridColumnAlignment(.trailing)
                        TextField("주", text: $quantityText).frame(width: 120)
                            .accessibilityIdentifier("portfolio.field.quantity")
                    }
                }

                Button("추가") { addItem() }
                    .disabled(!isFormValid)
                    .accessibilityIdentifier("portfolio.button.add")
            }

            SettingsFormSection(title: "팝오버 표시") {
                Toggle("매입단가·현재단가·수량 표시", isOn: $showPopoverDetail)
            }

            SnapshotSettingsSection()
        }
    }

    @ViewBuilder
    private func portfolioRow(_ item: PortfolioItem) -> some View {
        HStack(spacing: 10) {
            Button {
                togglePopoverVisibility(item)
            } label: {
                Image(systemName: item.showInPopover ? "eye.fill" : "eye.slash")
                    .foregroundStyle(item.showInPopover ? .blue : .secondary)
                    .frame(width: 16)
            }
            .buttonStyle(.borderless)
            .help(item.showInPopover ? "메뉴바 팝오버에서 숨기기" : "메뉴바 팝오버에 표시")

            VStack(alignment: .leading, spacing: 2) {
                Text(item.name).font(.body)
                Text(item.symbol).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("평균 \(NumberFormatter.decimal.string(from: NSNumber(value: item.averagePrice)) ?? "")원")
                    .font(.caption)
                Text("\(item.quantity)주")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Button {
                deleteItem(item)
            } label: {
                Image(systemName: "trash").foregroundStyle(.red)
            }
            .buttonStyle(.borderless)
        }
    }

    private var isFormValid: Bool {
        !symbol.trimmingCharacters(in: .whitespaces).isEmpty &&
        !name.trimmingCharacters(in: .whitespaces).isEmpty &&
        Int(averagePriceText) != nil &&
        Int(quantityText) != nil
    }

    private var importInfoText: String {
        let ids = connectedBrokerIds
        if ids.first?.hasPrefix("KIWOOM-") == true && ids.count == 1 {
            return "키움증권 계좌에서 보유 종목을 가져올 수 있습니다"
        }
        return "KIS 계좌 연결 시 보유 종목을 자동으로 가져올 수 있습니다"
    }

    private func loadItems() {
        isLoggedIn = AccountManager.isAnyConnected
        items = (try? DatabaseManager.shared.fetchPortfolio()) ?? []
        let connected = Set(connectedBrokerIds)
        selectedBrokerIds = selectedBrokerIds.intersection(connected)
        if selectedBrokerIds.isEmpty { selectedBrokerIds = connected }
    }

    private func addItem() {
        guard let avg = Int(averagePriceText), let qty = Int(quantityText) else { return }
        var item = PortfolioItem(
            id: nil,
            symbol: symbol.trimmingCharacters(in: .whitespaces).uppercased(),
            name: name.trimmingCharacters(in: .whitespaces),
            averagePrice: avg,
            quantity: qty
        )
        try? DatabaseManager.shared.insert(&item)
        symbol = ""; name = ""; averagePriceText = ""; quantityText = ""
        loadItems()
    }

    private func deleteItem(_ item: PortfolioItem) {
        try? DatabaseManager.shared.delete(item)
        loadItems()
    }

    private func togglePopoverVisibility(_ item: PortfolioItem) {
        var updated = item
        updated.showInPopover = !item.showInPopover
        try? DatabaseManager.shared.update(updated)
        loadItems()
    }

    private func startImport() {
        if isMultiBroker {
            showImportBrokerAlert = true
        } else {
            performImport(for: connectedBrokerIds.first)
        }
    }

    private func performImport(for accountId: String?) {
        isImporting = true
        importError = nil
        Task {
            do {
                let fetched = try await QuoteManager.shared.fetchBalance(for: accountId)
                if fetched.isEmpty {
                    importError = "계좌에 보유 종목이 없습니다"
                } else {
                    importedItems = fetched
                    showImportSheet = true
                }
            } catch {
                importError = error.localizedDescription
            }
            isImporting = false
        }
    }

    private func applyImport(mode: ImportSyncMode) {
        switch mode {
        case .replaceAll:
            let existing = (try? DatabaseManager.shared.fetchPortfolio()) ?? []
            for item in existing { try? DatabaseManager.shared.delete(item) }
            for var item in importedItems { try? DatabaseManager.shared.insert(&item) }
        case .addNew:
            let existing = (try? DatabaseManager.shared.fetchPortfolio()) ?? []
            let existingSymbols = Set(existing.map { $0.symbol })
            for var item in importedItems where !existingSymbols.contains(item.symbol) {
                try? DatabaseManager.shared.insert(&item)
            }
        }
        loadItems()
    }
}

struct PortfolioImportSheetView: View {
    let items: [PortfolioItem]
    let onApply: (ImportSyncMode) -> Void

    @State private var mode: ImportSyncMode = .addNew
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("보유 종목 가져오기").font(.title2).bold()
            VStack(alignment: .leading, spacing: 2) {
                Text("계좌에서 \(items.count)개 종목을 불러왔습니다.")
                    .font(.subheadline).foregroundStyle(.secondary)
                Text(items.map { $0.name }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.tertiary)
            }

            VStack(spacing: 0) {
                Divider()
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(items.enumerated()), id: \.element.symbol) { idx, item in
                            HStack(alignment: .center, spacing: 12) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(item.name).font(.body).fontWeight(.medium)
                                    Text(item.symbol)
                                        .font(.caption).fontDesign(.monospaced)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 3) {
                                    Text("평균 \(NumberFormatter.decimal.string(from: NSNumber(value: item.averagePrice)) ?? "")원")
                                        .font(.caption)
                                    HStack(spacing: 6) {
                                        Text("\(item.quantity)주")
                                            .font(.caption).foregroundStyle(.secondary)
                                        Text("·").font(.caption).foregroundStyle(.tertiary)
                                        Text("총 \(NumberFormatter.decimal.string(from: NSNumber(value: item.totalCost)) ?? "")원")
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .padding(.vertical, 8)
                            if idx < items.count - 1 {
                                Divider()
                            }
                        }
                    }
                    .padding(.horizontal, 2)
                }
                .frame(maxHeight: 280)
                Divider()
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("동기화 방식").font(.headline)
                Picker("", selection: $mode) {
                    Text("신규 추가만 — 이미 있는 종목 유지").tag(ImportSyncMode.addNew)
                    Text("전체 교체 — 기존 항목 삭제 후 덮어쓰기").tag(ImportSyncMode.replaceAll)
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()
            }

            HStack {
                Spacer()
                Button("취소") { dismiss() }
                    .keyboardShortcut(.escape)
                Button("가져오기") {
                    onApply(mode)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return)
            }
        }
        .padding(24)
        .frame(width: 500)
    }
}
