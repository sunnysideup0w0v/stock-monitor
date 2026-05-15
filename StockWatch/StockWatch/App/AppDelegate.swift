import AppKit
import SwiftUI
import Combine

extension NSNotification.Name {
    static let openSettings    = NSNotification.Name("com.personal.StockWatch.openSettings")
    static let popoverWillShow = NSNotification.Name("com.personal.StockWatch.popoverWillShow")
    static let openPopover     = NSNotification.Name("com.personal.StockWatch.openPopover")
}

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var settingsWindow: NSWindow?
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusBar()
        NotificationManager.shared.requestAuthorization()
        setupAdapter()
        startPollingFromDB()

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
        if let appKey = KeychainHelper.load(account: "kis.appKey"),
           let appSecret = KeychainHelper.load(account: "kis.appSecret"),
           !appKey.isEmpty, !appSecret.isEmpty {
            let isMock = UserDefaults.standard.bool(forKey: "KIS.isMock")
            let accountNumber = KeychainHelper.load(account: "kis.accountNumber")
            let creds = BrokerCredentials(appKey: appKey, appSecret: appSecret, accountNumber: accountNumber)
            let adapter = KISAdapter(isMock: isMock)
            QuoteManager.shared.setAdapter(adapter)
            Task { try? await adapter.connect(credentials: creds) }
            QuoteManager.shared.startRealtime(credentials: creds, isMock: isMock)
        } else {
            QuoteManager.shared.setAdapter(MockBrokerAdapter())
        }
    }

    // 앱 시작 시 DB의 관심종목 + 팝오버 표시 보유 종목으로 폴링 시작 (팝업을 열지 않아도 알림이 동작)
    private func startPollingFromDB() {
        let watchlistSymbols = (try? DatabaseManager.shared.fetchWatchlist().map { $0.symbol }) ?? []
        let holdingSymbols   = ((try? DatabaseManager.shared.fetchPortfolio()) ?? [])
            .filter { $0.showInPopover }
            .map { $0.symbol }

        var allSymbols = watchlistSymbols
        for symbol in holdingSymbols where !allSymbols.contains(symbol) {
            allSymbols.append(symbol)
        }

        if !allSymbols.isEmpty {
            QuoteManager.shared.startPolling(symbols: allSymbols)
        }
        DARTManager.shared.start(symbols: watchlistSymbols)
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
            popover.performClose(nil)
        } else {
            popover?.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    func openSettings() {
        popover?.performClose(nil)

        if settingsWindow == nil {
            let controller = NSHostingController(rootView: SettingsView())
            let window = NSWindow(contentViewController: controller)
            window.title = "StockWatch 설정"
            window.styleMask = [.titled, .closable, .resizable, .miniaturizable]
            window.setContentSize(NSSize(width: 720, height: 600))
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
}
