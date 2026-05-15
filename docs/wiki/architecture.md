# StockWatch — 아키텍처 개요

> 최종 업데이트: Phase 4 완료 기준 (2026-05-15)

---

## 전체 구조

```
AppDelegate (@MainActor, NSApplicationDelegate)
│
├── UI 계층
│   ├── MenuBarPopoverView    — 메뉴바 팝오버 (SwiftUI)
│   └── SettingsView          — 설정 창 (SwiftUI, 6개 탭)
│
├── 코어 계층
│   ├── QuoteManager          — 시세 폴링·WebSocket 허브 (@MainActor)
│   ├── AlertEvaluator        — 알림 조건 평가 (@MainActor)
│   ├── DARTManager           — DART 공시 폴링 (@MainActor)
│   └── SnapshotManager       — 포트폴리오 스냅샷 수집 (@MainActor)
│
├── 어댑터 계층
│   ├── KISAdapter            — 한국투자증권 REST/WebSocket (actor)
│   ├── KiwoomAdapter         — 키움증권 REST (actor)
│   └── MockBrokerAdapter     — 오프라인 개발용 더미
│
├── 데이터 계층
│   └── DatabaseManager       — GRDB SQLite, Migration v1~v8
│
└── 인프라
    ├── AccountManager        — Keychain 기반 계정 ID 관리
    ├── NotificationManager   — UNUserNotificationCenter 래퍼
    ├── KeychainHelper        — Security framework 래퍼
    └── BackupManager         — JSON 백업/복원
```

---

## 계층별 역할

### AppDelegate

앱의 진입점. `@MainActor`로 격리.

- 메뉴바 아이콘(`NSStatusItem`) 및 팝오버(`NSPopover`) 생성·관리
- 설정 창(`settingsWindow`), 온보딩 창(`onboardingWindow`) 생성·표시
- 앱 시작 시 `setupAdapter()` → 각 브로커 어댑터 초기화
- 앱 시작 시 `startPollingFromDB()` → DB에 저장된 종목으로 즉시 폴링 시작 (팝오버를 열지 않아도 알림 동작)
- `QuoteManager.$connectionState` 구독 → 메뉴바 아이콘 상태 반영

### QuoteManager

시세 데이터의 단일 진입점. `@MainActor, ObservableObject`.

- `adapters: [String: any BrokerAdapter]` — 멀티 브로커 딕셔너리 (키: accountId)
- 3초 간격 폴링: `fetchAll()` → 등록된 모든 어댑터 병렬 실행 (`withTaskGroup`)
- 연속 2회 실패 → `connectionState = .error` + 단절 알림 (1회)
- 복구 → `connectionState = .connected` + 재연결 알림
- WebSocket 실시간 시세: `startRealtime(credentials:isMock:)` → `RealtimeQuoteManager`에 위임

### AlertEvaluator

`QuoteManager.fetchAll()` 완료 후 매번 호출. 조건 평가 → 알림 발송.

- 종목별 조건: `isTriggered(condition:quote:)` 평가
- 포트폴리오 조건: `evaluatePortfolio()` — 총평가액/손익률 기준 4종
- 쿨다운: `lastTriggeredAt` + `cooldownMinutes`로 중복 알림 방지
- 장 시간 제한: `marketHoursOnly` 설정 시 09:00~15:30 외 알림 차단

### BrokerAdapter (protocol)

모든 브로커 어댑터가 구현해야 하는 인터페이스. `Sendable`.

```swift
protocol BrokerAdapter: Sendable {
    var brokerName: String { get }
    func connect(credentials: BrokerCredentials) async throws
    func disconnect() async
    func fetchQuote(symbol: String) async throws -> StockQuote
    func fetchPortfolio() async throws -> [PortfolioItem]
    func fetchNews(symbol: String) async throws -> [NewsItem]
    func fetchDailyVolumes(symbol: String, days: Int) async throws -> [Int]
}
```

구현체는 모두 `actor`로 선언 — 토큰 캐시 등 mutable state의 thread safety 보장.

### DatabaseManager

GRDB `DatabaseQueue` 기반 싱글턴. `@unchecked Sendable`.

- DB 파일 위치: `~/Library/Application Support/StockWatch/db.sqlite`
- Migration 방식으로 스키마 관리 (기존 Migration은 절대 수정 금지)
- 현재 최신 버전: v8

---

## 데이터 흐름

```
[브로커 API]
     │  fetchQuote (3초 폴링 또는 WebSocket)
     ▼
QuoteManager.quotes: [String: StockQuote]
     │
     ├──▶ MenuBarPopoverView (.onChange(of: quotes)) — UI 업데이트
     │
     └──▶ AlertEvaluator.evaluate()
              │
              ├── DB AlertCondition 비교
              ├── 포트폴리오 손익 계산
              └── NotificationManager.send() → macOS 알림
```

```
[DART Open API]  5분마다
     │
     ▼
DARTManager
     └──▶ NotificationManager.send() + AlertHistory DB 저장
```

```
[SnapshotManager]  1분마다 (장 시간 중)
     └──▶ portfolio_snapshots DB 저장
               └──▶ AssetChartView (설정 창 자산 차트 탭)
```

---

## Concurrency 설계 원칙

| 레이어 | Concurrency 모델 | 이유 |
|--------|-----------------|------|
| AppDelegate, QuoteManager, AlertEvaluator, DARTManager, SnapshotManager | `@MainActor` | UI 상태 변경, SwiftUI 바인딩 접근 |
| KISAdapter, KiwoomAdapter | `actor` | 토큰 캐시 등 mutable state 보호 |
| DatabaseManager | `@unchecked Sendable` | GRDB DatabaseQueue 자체가 thread-safe |
| MockBrokerAdapter | `struct` (Sendable) | 무상태(stateless) |

Swift 6 strict concurrency 활성화 상태. `@unchecked Sendable`은 최후 수단으로만 사용.

---

## 알림 흐름

```
조건 충족
    │
    ├── AlertEvaluator.fire()
    │       ├── NotificationManager.send(title:body:symbol:urlString:)
    │       └── DatabaseManager.insert(AlertHistory)
    │
    └── DARTManager (공시)
            ├── NotificationManager.send(urlString: dart.fss.or.kr URL)
            └── DatabaseManager.insert(AlertHistory, metadata: rcept_no)

알림 클릭
    ├── urlString 있음 → NSWorkspace.shared.open(url)
    └── urlString 없음 → NotificationCenter.post(.openPopover)
```

---

## 컴포넌트 간 통신

SwiftUI 바인딩 / Combine 외에 `NSNotificationCenter` 기반 이벤트를 사용하는 경우:

| 이름 | 발신처 | 수신처 | 동작 |
|------|--------|--------|------|
| `.openSettings` | 팝오버 하단 "설정" 버튼 | AppDelegate | 설정 창 열기 |
| `.openPopover` | 알림 클릭 핸들러 | AppDelegate | 팝오버 열기 |
| `.popoverWillShow` | NSPopoverDelegate | MenuBarPopoverView | 데이터 리로드 |

모든 이름은 `AppDelegate.swift`의 `NSNotification.Name` extension에 정의.

---

## 새 브로커 어댑터 추가 절차

1. `actor`로 `BrokerAdapter` 프로토콜 구현
2. `nonisolated let brokerName` 선언
3. `connect()` 에서 토큰/세션 초기화, 만료 전 자동 갱신 로직 포함
4. `fetchQuote()` 응답 필드는 모두 `String?`으로 받아 파싱 (장 시간 외 일부 필드 생략 대응)
5. `AppDelegate.setupAdapter()` 에서 자격증명 확인 후 `QuoteManager.addAdapter(id:adapter:)` 호출
6. `AccountSettingsView` 에 로그인/로그아웃 UI 추가
7. `AccountManager.connectedAccountIds` 에 Keychain 키 추가
