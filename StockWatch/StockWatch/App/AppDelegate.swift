import AppKit
import SwiftUI
import Combine

extension NSNotification.Name {
    static let openSettings             = NSNotification.Name("com.personal.StockWatch.openSettings")
    static let popoverWillShow          = NSNotification.Name("com.personal.StockWatch.popoverWillShow")
    static let openPopover              = NSNotification.Name("com.personal.StockWatch.openPopover")
    static let krxDataUpdated           = NSNotification.Name("com.personal.StockWatch.krxDataUpdated")
    static let snapshotBackfillCompleted = NSNotification.Name("com.personal.StockWatch.snapshotBackfillCompleted")
    static let settingsWillShow          = NSNotification.Name("com.personal.StockWatch.settingsWillShow")
}

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var settingsWindow: NSWindow?
    private var onboardingWindow: NSWindow?
    private var cancellables = Set<AnyCancellable>()
    private var eventMonitor: Any?
    private var wakeObserver: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        CrashLogger.install()
        setupStatusBar()
        NotificationManager.shared.requestAuthorization()
        BrokerSessionManager.shared.restoreAllSessions()
        startPollingFromDB()
        KRXManager.shared.start()

        if CommandLine.arguments.contains("--uitesting") {
            Task { try? await Task.sleep(for: .milliseconds(500)); self.openSettings() }
        } else if !UserDefaults.standard.bool(forKey: UserDefaultsKey.onboardingCompleted) {
            Task { try? await Task.sleep(for: .milliseconds(300)); self.openOnboarding() }
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

        // 슬립 후 깨어날 때 스냅샷 공백 소급 보완
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in SnapshotBackfillManager.shared.backfillIfNeeded() }
        }

        // 앱 시작 시 소급 보완 (토큰 발급 경합 방지를 위해 3초 지연)
        Task {
            try? await Task.sleep(for: .seconds(3))
            SnapshotBackfillManager.shared.backfillIfNeeded()
        }
    }

    // 앱 시작 시 DB의 관심종목 + 포트폴리오 종목으로 폴링·DART 시작 (팝업을 열지 않아도 알림이 동작)
    private func startPollingFromDB() {
        var watchlistSymbols: [String] = []
        var portfolioSymbols: [String] = []
        do {
            watchlistSymbols = try DatabaseManager.shared.fetchWatchlist().map { $0.symbol }
            portfolioSymbols = try DatabaseManager.shared.fetchPortfolio().map { $0.symbol }
        } catch {
            AppLogger.log("startPollingFromDB: DB 조회 실패 — \(error.localizedDescription)", level: .error, category: "App")
        }

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
        NotificationCenter.default.post(name: .settingsWillShow, object: nil)
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
