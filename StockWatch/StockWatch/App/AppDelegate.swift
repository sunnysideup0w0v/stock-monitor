import AppKit
import SwiftUI
import Combine

extension NSNotification.Name {
    static let openSettings    = NSNotification.Name("com.personal.StockWatch.openSettings")
    static let popoverWillShow = NSNotification.Name("com.personal.StockWatch.popoverWillShow")
    static let openPopover     = NSNotification.Name("com.personal.StockWatch.openPopover")
    static let krxDataUpdated  = NSNotification.Name("com.personal.StockWatch.krxDataUpdated")
}

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var settingsWindow: NSWindow?
    private var onboardingWindow: NSWindow?
    private var cancellables = Set<AnyCancellable>()
    private var eventMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        CrashLogger.install()
        setupStatusBar()
        NotificationManager.shared.requestAuthorization()
        setupAdapter()
        startPollingFromDB()
        KRXManager.shared.start()

        if CommandLine.arguments.contains("--uitesting") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.openSettings() }
        } else if !UserDefaults.standard.bool(forKey: "Onboarding.completed") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self.openOnboarding() }
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleOpenSettings),
            name: .openSettings,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleOpenPopover),
            name: .openPopover,
            object: nil
        )

        QuoteManager.shared.$connectionState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in self?.updateStatusBarIcon(state) }
            .store(in: &cancellables)
    }

    private func setupAdapter() {
        var hasRealAdapter = false

        if let appKey = KeychainHelper.load(account: "kis.appKey"),
           let appSecret = KeychainHelper.load(account: "kis.appSecret"),
           !appKey.isEmpty, !appSecret.isEmpty {
            let isMock = UserDefaults.standard.bool(forKey: "KIS.isMock")
            let accountNumber = KeychainHelper.load(account: "kis.accountNumber")
            let creds = BrokerCredentials(appKey: appKey, appSecret: appSecret, accountNumber: accountNumber)
            let adapter = KISAdapter(isMock: isMock)
            let accountId = "KIS-" + String(appKey.prefix(8))
            QuoteManager.shared.addAdapter(id: accountId, adapter: adapter)
            try? DatabaseManager.shared.assignAccountIdToOrphanedItems(accountId: accountId)
            Task {
                try? await adapter.connect(credentials: creds)
                await MainActor.run { BrokerRegistry.shared.register(adapter) }
            }
            QuoteManager.shared.startRealtime(credentials: creds, isMock: isMock)
            hasRealAdapter = true
        }

        if let appKey = KeychainHelper.load(account: "kiwoom.appKey"),
           let appSecret = KeychainHelper.load(account: "kiwoom.appSecret"),
           !appKey.isEmpty, !appSecret.isEmpty {
            let accountNumber = KeychainHelper.load(account: "kiwoom.accountNumber")
            let creds = BrokerCredentials(appKey: appKey, appSecret: appSecret, accountNumber: accountNumber)
            let adapter = KiwoomAdapter()
            let accountId = "KIWOOM-" + String(appKey.prefix(8))
            QuoteManager.shared.addAdapter(id: accountId, adapter: adapter)
            try? DatabaseManager.shared.assignAccountIdToOrphanedItems(accountId: accountId)
            Task {
                try? await adapter.connect(credentials: creds)
                await MainActor.run { BrokerRegistry.shared.register(adapter) }
            }
            // Kiwoom은 WebSocket 미지원 — REST 폴링만 사용
            hasRealAdapter = true
        }

        if !hasRealAdapter {
            QuoteManager.shared.setAdapter(MockBrokerAdapter())
        }
    }

    // 앱 시작 시 DB의 관심종목 + 포트폴리오 종목으로 폴링·DART 시작 (팝업을 열지 않아도 알림이 동작)
    private func startPollingFromDB() {
        let watchlistSymbols = (try? DatabaseManager.shared.fetchWatchlist().map { $0.symbol }) ?? []
        let portfolioSymbols = ((try? DatabaseManager.shared.fetchPortfolio()) ?? []).map { $0.symbol }

        // 시세 폴링: 관심종목 + 포트폴리오 전체 (팝오버 표시 여부 무관)
        var allSymbols = watchlistSymbols
        for symbol in portfolioSymbols where !allSymbols.contains(symbol) {
            allSymbols.append(symbol)
        }

        if !allSymbols.isEmpty {
            QuoteManager.shared.startPolling(symbols: allSymbols)
        }
        // DART: 관심종목 + 포트폴리오 합산 (중복 제거됨)
        DARTManager.shared.start(symbols: allSymbols)
        SnapshotManager.shared.start()
    }

    @objc private func handleOpenSettings() {
        openSettings()
    }

    @objc private func handleOpenPopover() {
        guard let button = statusItem?.button else { return }
        NSApp.activate(ignoringOtherApps: true)
        if let popover, !popover.isShown {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            startEventMonitor()
        }
    }

    private func updateStatusBarIcon(_ state: QuoteManager.ConnectionState) {
        let name: String
        switch state {
        case .connected:    name = "chart.line.uptrend.xyaxis"
        case .disconnected: name = "chart.line.uptrend.xyaxis"
        case .error:        name = "exclamationmark.triangle"
        }
        statusItem?.button?.image = NSImage(systemSymbolName: name, accessibilityDescription: "StockWatch")
    }

    private func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "chart.line.uptrend.xyaxis", accessibilityDescription: "StockWatch")
            button.action = #selector(togglePopover)
            button.target = self
        }

        let popover = NSPopover()
        popover.contentSize = NSSize(width: 300, height: 320)
        popover.behavior = .transient
        popover.delegate = self
        popover.contentViewController = NSHostingController(rootView: MenuBarPopoverView())
        self.popover = popover
    }

    @objc private func togglePopover() {
        guard let button = statusItem?.button else { return }

        if let popover, popover.isShown {
            closePopover()
        } else {
            popover?.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            startEventMonitor()
        }
    }

    private func closePopover() {
        popover?.performClose(nil)
        stopEventMonitor()
    }

    private func startEventMonitor() {
        guard eventMonitor == nil else { return }
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.closePopover()
        }
    }

    private func stopEventMonitor() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }

    func openOnboarding() {
        if onboardingWindow == nil {
            var isPresented = true
            let controller = NSHostingController(rootView: OnboardingView(isPresented: .init(
                get: { isPresented },
                set: { isPresented = $0
                    if !$0 { self.onboardingWindow?.close() }
                }
            )))
            let window = NSWindow(contentViewController: controller)
            window.title = "StockWatch 시작하기"
            window.styleMask = [.titled, .closable]
            window.setContentSize(NSSize(width: 420, height: 360))
            window.isReleasedWhenClosed = false
            window.center()
            onboardingWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        onboardingWindow?.makeKeyAndOrderFront(nil)
    }

    func openSettings() {
        popover?.performClose(nil)

        if settingsWindow == nil {
            let controller = NSHostingController(rootView: SettingsView())
            let window = NSWindow(contentViewController: controller)
            window.title = "StockWatch 설정"
            window.styleMask = [.titled, .closable, .resizable, .miniaturizable]
            window.setContentSize(NSSize(width: 720, height: 680))
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }

        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
        settingsWindow?.orderFrontRegardless()
    }
}

extension AppDelegate: NSPopoverDelegate {
    func popoverWillShow(_ notification: Notification) {
        NotificationCenter.default.post(name: .popoverWillShow, object: nil)
    }

    func popoverDidClose(_ notification: Notification) {
        stopEventMonitor()
    }
}
