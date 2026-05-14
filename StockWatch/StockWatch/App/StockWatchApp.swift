import SwiftUI

@main
struct StockWatchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // 메뉴바 앱은 WindowGroup 없이 AppDelegate에서 UI를 직접 관리
        Settings {
            EmptyView()
        }
    }
}
