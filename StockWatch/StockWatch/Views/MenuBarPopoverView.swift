import SwiftUI

struct MenuBarPopoverView: View {
    @ObservedObject private var quoteManager = QuoteManager.shared
    @State private var watchlist: [WatchlistItem] = []
    @State private var portfolioHoldings: [PortfolioItem] = []
    @State private var totalGain: Int = 0
    @State private var hasPortfolio = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            stockList
            Divider()
            portfolioSection
            Divider()
            bottomBar
        }
        .frame(width: 300)
        .onAppear(perform: reload)
        .onReceive(NotificationCenter.default.publisher(for: .popoverWillShow)) { _ in reload() }
        .onChange(of: quoteManager.quotes) { _, _ in calculatePortfolio() }
    }

    private var header: some View {
        HStack {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .foregroundStyle(.blue)
            Text("StockWatch")
                .font(.headline)
            Spacer()
            Circle()
                .fill(quoteManager.connectionState == .connected ? Color.green : quoteManager.connectionState == .error ? Color.red : Color.gray)
                .frame(width: 8, height: 8)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var stockList: some View {
        Group {
            if watchlist.isEmpty {
                Text("설정에서 관심종목을 추가해주세요")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
            } else {
                ForEach(watchlist, id: \.id) { item in
                    if let quote = quoteManager.quotes[item.symbol] {
                        StockRowView(
                            name: item.alias ?? item.name,
                            price: quote.formattedPrice,
                            change: quote.formattedChange,
                            isUp: quote.isUp
                        )
                    } else {
                        StockRowView(name: item.alias ?? item.name, price: "---", change: "---", isUp: true)
                    }
                }
            }
        }
    }

    private var portfolioSection: some View {
        VStack(spacing: 0) {

            // 포트폴리오 요약
            HStack {
                Text("포트폴리오")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if hasPortfolio {
                    Text((totalGain >= 0 ? "+" : "") + (NumberFormatter.decimal.string(from: NSNumber(value: totalGain)) ?? "") + "원")
                        .font(.caption)
                        .foregroundStyle(totalGain >= 0 ? .green : .red)
                } else {
                    Text("--")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            // 선택된 보유 종목 현재가
            ForEach(portfolioHoldings, id: \.id) { item in
                PortfolioHoldingRowView(
                    item: item,
                    quote: quoteManager.quotes[item.symbol]
                )
            }
        }
        .padding(.bottom, portfolioHoldings.isEmpty ? 0 : 6)
    }

    private var bottomBar: some View {
        HStack(spacing: 8) {
            Button("설정") {
                NotificationCenter.default.post(name: .openSettings, object: nil)
            }
            .buttonStyle(.borderless)
            .font(.caption)
            Spacer()
            Button("종료") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.borderless)
            .font(.caption)
            .foregroundStyle(.red)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private func reload() {
        watchlist = (try? DatabaseManager.shared.fetchWatchlist()) ?? []
        portfolioHoldings = (try? DatabaseManager.shared.fetchPortfolio())?.filter { $0.showInPopover } ?? []

        var symbols = watchlist.map { $0.symbol }
        for symbol in portfolioHoldings.map({ $0.symbol }) where !symbols.contains(symbol) {
            symbols.append(symbol)
        }
        QuoteManager.shared.startPolling(symbols: symbols)
        DARTManager.shared.start(symbols: watchlist.map { $0.symbol })
        calculatePortfolio()
    }

    private func calculatePortfolio() {
        guard let portfolio = try? DatabaseManager.shared.fetchPortfolio(), !portfolio.isEmpty else {
            hasPortfolio = false
            totalGain = 0
            return
        }
        hasPortfolio = true
        totalGain = portfolio.reduce(0) { sum, item in
            guard let quote = quoteManager.quotes[item.symbol] else { return sum }
            return sum + item.evaluatedGain(currentPrice: quote.price)
        }
    }
}

struct PortfolioHoldingRowView: View {
    let item: PortfolioItem
    let quote: StockQuote?

    var body: some View {
        HStack(spacing: 6) {
            Text(item.name)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()
            if let quote {
                let gainRate = item.gainRate(currentPrice: quote.price)
                Text(quote.formattedPrice)
                    .font(.system(size: 12, design: .monospaced))
                Text(String(format: "%+.1f%%", gainRate))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(gainRate >= 0 ? .green : .red)
            } else {
                Text("---")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.leading, 24)
        .padding(.trailing, 16)
        .padding(.vertical, 4)
    }
}

struct StockRowView: View {
    let name: String
    let price: String
    let change: String
    let isUp: Bool

    var body: some View {
        HStack {
            Text(name)
                .font(.system(size: 13))
            Spacer()
            Text(price)
                .font(.system(size: 13, design: .monospaced))
            Text(change)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(isUp ? .green : .red)
            Image(systemName: isUp ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill")
                .font(.system(size: 8))
                .foregroundStyle(isUp ? .green : .red)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }
}

private extension NumberFormatter {
    static let decimal: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        return f
    }()
}
