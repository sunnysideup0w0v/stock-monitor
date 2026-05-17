# StockWatch 리팩토링 체크리스트

> 작성: 2026-05-17 | 대상: Phase 0~5 누적 코드
> 기능 추가 없이 코드 품질·구조 개선에만 집중한다.

---

## 작업 규칙

### 테스트 사이클 (매 항목 완료 후 필수)

각 R 항목의 마지막 체크박스를 완료한 직후 아래 명령을 실행한다.

```bash
xcodebuild test -scheme StockWatch -destination 'platform=macOS' \
  -only-testing:StockWatchTests CODE_SIGNING_ALLOWED=NO 2>&1 \
  | grep -E "(error:|PASSED|FAILED|Executed [0-9])"
```

- **통과 시**: 해당 항목 완료로 간주하고 다음 R 항목으로 이동한다.
- **실패 시**: 아래 루프를 테스트가 전부 통과할 때까지 반복한다.
  1. 실패 로그에서 오류 원인 파악 (`error:` / `XCTFail` 메시지 분석)
  2. 원인에 해당하는 소스 파일 수정
  3. 다시 테스트 실행
  4. 85개(기준선) 이상 통과 + 0 failures 확인 → 완료

> **절대 실패한 채로 다음 항목으로 넘어가지 않는다.**  
> 테스트를 삭제하거나 skip 처리해서 통과시키는 것은 허용하지 않는다.  
> 리팩토링 중 테스트 자체가 잘못됐다고 판단될 경우, 수정 근거를 커밋 메시지에 명시한다.

---

## R1 — SettingsView.swift 파일 분리 (1818줄 God File)

현재 SettingsView.swift에 12개 View struct가 모두 들어 있다.  
각 View를 `Views/Settings/` 하위 파일로 분리한다.

- [x] `Views/Settings/` 디렉토리 생성
- [x] `SettingsView.swift` → 탭 컨테이너 역할만 남기고 400줄 이하로 축소
- [x] `WatchlistSettingsView.swift` 분리
- [x] `PortfolioSettingsView.swift` + `PortfolioImportSheetView.swift` 분리
- [x] `AlertSettingsView.swift` 분리
- [x] `AlertHistoryView.swift` + `AlertHistoryRowView.swift` 분리
- [x] `SnapshotSettingsSection.swift` 분리
- [x] `AccountSettingsView.swift` 분리
- [x] `DARTSettingsView.swift` 분리
- [x] `KRXSettingsView.swift` 분리
- [x] `ClaudeSettingsView.swift` 분리
- [x] `SettingsComponents.swift` — `SettingsTabContainer`, `SettingsFormSection` 공용 컴포넌트
- [x] `NumberFormatter+Decimal.swift` — `NumberFormatter.decimal` extension 공용 파일로 이동
- [x] 분리 후 `xcodegen generate` → 빌드 성공 확인

---

## R2 — AccountSettingsView 비즈니스 로직 분리

현재 `login()`, `logout()`, `kiwoomLogin()`, `kiwoomLogout()` 메서드 안에  
Keychain 쓰기 · 어댑터 생성 · QuoteManager 호출이 뒤섞여 있다.

- [x] `BrokerSessionManager.swift` (또는 `@MainActor final class`) 신규 작성
  - `loginKIS(appKey:appSecret:accountNumber:isMock:)` — Keychain 저장, 어댑터 생성, addAdapter, BrokerRegistry 등록
  - `logoutKIS()` — Keychain 삭제, removeAdapter, BrokerRegistry 해제
  - `loginKiwoom(appKey:appSecret:accountNumber:)` / `logoutKiwoom()`
  - `testConnectionKIS(...)` / `testConnectionKiwoom(...)`
- [x] `AppDelegate.setupAdapter()` → `BrokerSessionManager.restoreAllSessions()` 위임으로 교체
  - 두 파일에 중복된 어댑터 초기화 로직을 단일 진실 공급원으로 통합
- [x] `AccountSettingsView`는 `BrokerSessionManager`를 ObservableObject로 관찰, UI 상태만 보유
- [x] 기존 `login()` / `kiwoomLogin()` 로직 완전히 제거하고 위임 호출로 교체
- [x] 빌드 + 유닛 테스트 통과 확인

---

## R3 — 매직 스트링 중앙화

UserDefaults 키와 Keychain 계정 이름이 SettingsView · AppDelegate · AccountManager · DatabaseManager 등 여러 파일에 흩어져 있다.

- [x] `KeychainKey.swift` 신규 작성
- [x] `UserDefaultsKey.swift` 신규 작성
  - 실제 코드의 키 값 사용 (`"Snapshot.*"`, `"Screener.savedConditions"` 등 — TODO의 값과 일부 상이)
  - per-symbol 동적 키(`DART.seen.*`, `DART.lastCheck.*`)는 static func로 추가
- [x] 모든 파일의 문자열 리터럴을 위 상수로 교체 (AppDelegate, AccountSettingsView, AccountManager, DatabaseManager, DARTManager/DARTSettingsView, SnapshotManager, AlertEvaluator, QuoteManager, KRXManager/KRXSettingsView, ClaudeAnalyzer/ClaudeSettingsView, ScreenerView, OnboardingView, BrokerSessionManager)
- [x] 컴파일 오류 없음 확인

---

## R4 — 중복 UI 컴포넌트 제거

- [x] `WatchlistSettingsView.accountRequiredView`와 `PortfolioSettingsView.accountRequiredView`가 거의 동일
  → `AccountRequiredView(description:)` 공용 View로 추출 (`SettingsComponents.swift`)
- [x] `brokerDisplayName(_ accountId: String)` 로직이 `PortfolioSettingsView`, `MenuBarPopoverView`에 각각 구현됨
  → `AccountManager.displayName(for:) -> String` 정적 메서드로 통합
- [x] `maskedKey(_ key:)` 함수가 `AccountSettingsView`에만 있으나 디버그 표시용으로 `KeychainHelper` 확장에 두는 것이 더 적합
  → `KeychainHelper.masked(_ value:) -> String` static 메서드로 이동
- [x] 분리 후 기존 중복 코드 삭제

---

## R5 — DB 에러 처리 일관성

현재 대부분의 DB 호출이 `try?`로 에러를 무시하고 있어 디버깅이 어렵다.

- [x] `SettingsView` 계열 View의 DB 쓰기 (insert/update/delete) 실패 시 에러 Alert 표시
  → `@State private var errorMessage: String?` + `.alert` modifier (WatchlistSettings / PortfolioSettings / AlertSettings)
- [x] `AlertEvaluator.evaluate()` — DB 조회 실패 시 `AppLogger.log` 출력 추가
- [x] `AppDelegate.startPollingFromDB()` — DB 조회 실패 시 로그 출력 추가
- [x] `DatabaseManager.fetchDistinctValues(column:table:)` SQL 인젝션 패턴 수정
  → `enum UniverseColumn: String { case sector, market }` + `fetchDistinctValues(column: UniverseColumn)`

---

## R6 — BrokerRegistry와 QuoteManager 어댑터 관리 이중화 해소

현재 `BrokerRegistry.registry` 와 `QuoteManager.adapters` 두 딕셔너리가 별도로 어댑터를 관리한다.  
연결/해제 시 두 곳을 수동으로 동기화해야 하는 위험이 있다.

- [ ] 역할 분리 명확화 (가장 보수적인 접근):
  - `BrokerRegistry` — `disconnect()` 생명주기 전담 (현 유지)
  - `QuoteManager.adapters` — 시세 조회 전담 (현 유지)
  - `BrokerSessionManager.login/logout`에서 두 곳 모두 업데이트하는 단일 진입점 확보 (R2에서 처리)
- [ ] OR 통합안 (더 과감한 접근): `QuoteManager`가 `BrokerRegistry`를 내부적으로 사용하도록 통합
  - `BrokerRegistry.unregister()` → `QuoteManager.removeAdapter()` 연동
  - 장: 이중 관리 제거 / 단: `QuoteManager` 의존성 증가
- [ ] 팀 검토 후 방향 결정 → 실행

---

## R7 — Async 패턴 일관성

`DispatchQueue.main.asyncAfter`와 `Task { await ... }` 패턴이 혼용되고 있다.

- [ ] `KRXSettingsView.fetch()` — `DispatchQueue.main.asyncAfter(deadline: .now() + 3)` 
  → `try? await Task.sleep(for: .seconds(3))` 로 교체
- [ ] `AppDelegate.applicationDidFinishLaunching()` — `DispatchQueue.main.asyncAfter` 2개
  → `Task { try? await Task.sleep(for: ...) }` 로 교체
- [ ] `AlertEvaluator.makePortfolioMessage()` 내 `NumberFormatter()` 매 호출 생성
  → static let으로 캐싱
- [ ] `AlertEvaluator.makeMessage()` 내 `NumberFormatter()` 동일 문제
  → static let으로 캐싱

---

## R8 — AccountManager Keychain 캐싱 개선

`AccountManager.connectedAccountIds`가 호출될 때마다 Keychain I/O가 발생한다.  
DB 쿼리(`fetchWatchlist`, `fetchPortfolio`), View의 `onAppear`, 필터 계산 등에서 자주 호출된다.

- [ ] `AccountManager`를 `enum` → `@MainActor final class` (ObservableObject)로 전환 검토
  - `@Published var connectedAccountIds: [String]` — 로그인/로그아웃 시 업데이트
  - 캐싱으로 반복 Keychain 읽기 제거
  - **단점**: singleton 참조 패턴 변경 필요, SwiftUI 환경 주입 필요
- [ ] OR 경량 접근: `connectedAccountIds` 계산 결과를 메모리에 캐시 + `BrokerSessionManager` 로그인/아웃 시 무효화

---

## R9 — 미구현 Stub 코드 정리

- [ ] `MiraeAssetAdapter.swift` — 모든 메서드가 에러 throw만 하는 stub
  - `AccountSettingsView.BrokerSelection.miraeAsset` 케이스도 "준비 중" UI만 표시
  - 파일은 유지하되 `#warning("미래에셋 어댑터 미구현")` 추가, UI 케이스도 동일
  - 구현 계획이 없으면 파일 자체 삭제 검토
- [ ] `BrokerAdapter.fetchNews(symbol:)` — KIS, Kiwoom 모두 `[]` 반환하는 stub
  - 사용처가 없으면 프로토콜에서 제거
- [ ] `ClaudeAnalyzer.swift` — `claude-sonnet-4-5` 모델명 하드코딩
  → `Constants.claudeModel = "claude-sonnet-4-6"` 상수로 추출 (현재 최신 버전으로 업데이트)

---

## R10 — 테스트 커버리지 보강 (리팩토링 안전망)

리팩토링 전 현재 동작을 테스트로 고정한다.

- [ ] `AccountSettingsView` 로그인/로그아웃 로직 → `BrokerSessionManager` 추출 후 단위 테스트
- [ ] `DatabaseManager.fetchDistinctValues` 허용 목록 검증 테스트
- [ ] `AccountManager.connectedAccountIds` — Mock Keychain 기반 테스트 (현재 테스트 없음)
- [ ] `QuoteManager.fetchAll` 어댑터 폴백 로직 테스트 (현재 QuoteManagerTests에 일부 있으나 fetchAll 자체는 미테스트)

---

## 우선순위 순서 (권장)

| 순위 | 항목 | 이유 |
|------|------|------|
| 1 | R1 — SettingsView 분리 | 가장 임팩트 큰 구조 개선, 이후 작업 기반 |
| 2 | R3 — 매직 스트링 중앙화 | 컴파일 타임 안전성, 전체 파일 영향 |
| 3 | R4 — 중복 UI 제거 | R1 이후 자연스럽게 따라오는 작업 |
| 4 | R2 — BrokerSessionManager 추출 | 가장 복잡, R1·R3 완료 후 작업 |
| 5 | R5 — DB 에러 처리 | 사용자 경험 영향, 비교적 안전한 변경 |
| 6 | R7 — Async 패턴 | 버그 위험 낮음, 코드 일관성 |
| 7 | R9 — Stub 정리 | 노이즈 제거, 리스크 낮음 |
| 8 | R8 — AccountManager 캐싱 | 성능 개선, 설계 결정 필요 |
| 9 | R6 — BrokerRegistry 통합 | 설계 변경 크고 위험, 충분한 검토 필요 |
| 10 | R10 — 테스트 보강 | 지속적으로 병행 |

---

*리팩토링 완료 기준: 빌드 성공 + 유닛 테스트 62개 전체 통과 + 앱 실행 정상*
