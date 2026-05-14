import SwiftUI

struct MenuBarPopoverView: View {
    var body: some View {
        VStack(spacing: 0) {
            // 헤더
            HStack {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .foregroundStyle(.blue)
                Text("StockWatch")
                    .font(.headline)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            // 종목 리스트 (placeholder)
            VStack(spacing: 0) {
                StockRowView(name: "삼성전자", price: "85,200", change: "+2.1%", isUp: true)
                StockRowView(name: "SK하이닉스", price: "165,500", change: "-0.8%", isUp: false)
                StockRowView(name: "NAVER", price: "180,000", change: "+0.3%", isUp: true)
            }

            Divider()

            // 포트폴리오 요약 (placeholder)
            HStack {
                Text("포트폴리오")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("총 +1,250,000원")
                    .font(.caption)
                    .foregroundStyle(.green)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            Divider()

            // 하단 버튼
            HStack(spacing: 8) {
                Button("대시보드") { }
                    .buttonStyle(.borderless)
                    .font(.caption)
                Spacer()
                Button("설정") { }
                    .buttonStyle(.borderless)
                    .font(.caption)
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
        .frame(width: 300)
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
