import SwiftUI

struct SettingsView: View {
    private var versionString: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        return "v\(version)"
    }

    var body: some View {
        VStack(spacing: 0) {
            TabView {
                AccountSettingsView()
                    .tabItem { Label("계좌 연결", systemImage: "key.fill") }
                WatchlistSettingsView()
                    .tabItem { Label("관심종목", systemImage: "list.star") }
                PortfolioSettingsView()
                    .tabItem { Label("포트폴리오", systemImage: "chart.pie") }
                AlertSettingsView()
                    .tabItem { Label("알림설정", systemImage: "bell") }
                AlertHistoryView()
                    .tabItem { Label("알림 이력", systemImage: "clock.arrow.circlepath") }
                AssetChartView()
                    .tabItem { Label("자산 차트", systemImage: "chart.xyaxis.line") }
                ScreenerView()
                    .tabItem { Label("종목 검색", systemImage: "wand.and.stars") }
            }

            Text(versionString)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
        }
        .frame(width: 720, height: 680)
        .padding()
    }
}
