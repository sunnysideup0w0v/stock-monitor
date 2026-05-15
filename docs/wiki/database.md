# StockWatch — 데이터베이스 스키마

> GRDB.swift 6.x / SQLite  
> 파일 위치: `~/Library/Application Support/StockWatch/db.sqlite`  
> 현재 최신 Migration: **v8**. 다음 추가 시 v9부터 시작.

---

## 규칙

- 기존 Migration은 **절대 수정하지 않는다** — 이미 적용된 기기에서 재실행되지 않으므로 수정해도 반영되지 않고 스키마 불일치가 생긴다.
- 컬럼 추가·테이블 변경은 항상 새 `registerMigration("vN_...")` 블록으로 추가.
- `DatabaseManager.swift`에 순서대로 등록.

---

## 테이블 목록

### `watchlist` (v1 + v8)

관심종목. 브로커 무관 — 어떤 브로커로 로그인해도 동일 목록 표시.

| 컬럼 | 타입 | 설명 |
|------|------|------|
| `id` | INTEGER PK | 자동 증가 |
| `symbol` | TEXT NOT NULL | 종목코드 (예: `"005930"`) |
| `name` | TEXT NOT NULL | 종목명 |
| `alias` | TEXT | 사용자 별칭 (없으면 name 표시) |
| `group` | TEXT NOT NULL | `"watchlist"` / `"longTerm"` / `"shortTerm"` |
| `accountId` | TEXT NOT NULL DEFAULT `''` | v8 추가. 생성 시 `AccountManager.currentAccountId` 자동 설정 |

> `fetchWatchlist()`는 accountId 필터 없이 전체 반환 (브로커 무관 정책).

---

### `portfolio` (v2 + v7 + v8)

보유 종목. 계정 종속.

| 컬럼 | 타입 | 설명 |
|------|------|------|
| `id` | INTEGER PK | 자동 증가 |
| `symbol` | TEXT NOT NULL | 종목코드 |
| `name` | TEXT NOT NULL | 종목명 |
| `averagePrice` | INTEGER NOT NULL | 평균매입가 (원) |
| `quantity` | INTEGER NOT NULL | 보유수량 (주) |
| `showInPopover` | BOOLEAN NOT NULL DEFAULT 0 | v7 추가. 팝오버에 현재가 표시 여부 |
| `accountId` | TEXT NOT NULL DEFAULT `''` | v8 추가. 계정 종속 필터 키 |

계산 프로퍼티 (Swift 모델에서):
```swift
var totalCost: Int { averagePrice * quantity }
func evaluatedGain(currentPrice: Int) -> Int { (currentPrice - averagePrice) * quantity }
func gainRate(currentPrice: Int) -> Double { Double(currentPrice - averagePrice) / Double(averagePrice) * 100 }
```

> `fetchPortfolio()`는 `WHERE accountId IN (connectedAccountIds)` 필터 적용.

---

### `alert_conditions` (v3)

알림 조건.

| 컬럼 | 타입 | 설명 |
|------|------|------|
| `id` | INTEGER PK | 자동 증가 |
| `symbol` | TEXT NOT NULL | 종목코드 또는 `"PORTFOLIO"` |
| `triggerType` | TEXT NOT NULL | TriggerType rawValue |
| `threshold` | REAL NOT NULL | 임계값 |
| `isActive` | BOOLEAN NOT NULL | 활성화 여부 |
| `disableAfterTrigger` | BOOLEAN NOT NULL | 트리거 후 자동 비활성화 여부 |
| `cooldownMinutes` | INTEGER NOT NULL | 재발송 최소 간격 (분) |
| `lastTriggeredAt` | DATETIME | 마지막 발송 시각 (쿨다운 계산용) |

**TriggerType 전체 목록**:

| 값 | 표시명 | 종목/포트폴리오 |
|----|--------|---------------|
| `targetPrice` | 목표가 도달 | 종목 |
| `stopLoss` | 손절가 도달 | 종목 |
| `rateUp` | 상승률 | 종목 |
| `rateDown` | 하락률 | 종목 |
| `volumeSpike` | 거래량 급증 | 종목 |
| `portfolioGain` | 포트폴리오 이익 (원) | 포트폴리오 |
| `portfolioLoss` | 포트폴리오 손실 (원) | 포트폴리오 |
| `portfolioGainRate` | 포트폴리오 수익률 (%) | 포트폴리오 |
| `portfolioLossRate` | 포트폴리오 손실률 (%) | 포트폴리오 |
| `dartDisclosure` | DART 공시 | — (DARTManager 별도 경로) |

> 새 TriggerType 추가 시 `AlertEvaluator`, `AlertSettingsView`, `AlertHistoryView` 내 exhaustive switch 전부 업데이트 필요.

---

### `alert_history` (v4 + v5)

발송된 알림 이력.

| 컬럼 | 타입 | 설명 |
|------|------|------|
| `id` | INTEGER PK | 자동 증가 |
| `symbol` | TEXT NOT NULL | 종목코드 또는 `"PORTFOLIO"` |
| `triggerType` | TEXT NOT NULL | TriggerType rawValue |
| `message` | TEXT NOT NULL | 알림 본문 |
| `triggeredAt` | DATETIME NOT NULL | 발송 시각 |
| `metadata` | TEXT | v5 추가. DART 공시의 경우 `rcept_no` 저장 |

> DART 공시 알림 클릭 시 `"https://dart.fss.or.kr/dsaf001/main.do?rcpNo=\(metadata)"` URL 복원.

---

### `portfolio_snapshots` (v6)

포트폴리오 평가액 시계열 데이터. 자산 차트에 사용.

| 컬럼 | 타입 | 설명 |
|------|------|------|
| `id` | INTEGER PK | 자동 증가 |
| `timestamp` | DATETIME NOT NULL | 수집 시각 |
| `totalValue` | INTEGER NOT NULL | 총 평가액 (원) |
| `totalCost` | INTEGER NOT NULL | 총 매입원가 (원) |

수집 주기: 1분 (SnapshotManager)  
수집 조건: 평일 09:00~15:30 (기본값, `marketHoursOnly` 설정으로 변경 가능)

---

## Migration 이력

| 버전 | 내용 |
|------|------|
| v1 | `watchlist` 테이블 생성 |
| v2 | `portfolio` 테이블 생성 |
| v3 | `alert_conditions` 테이블 생성 |
| v4 | `alert_history` 테이블 생성 |
| v5 | `alert_history.metadata` 컬럼 추가 |
| v6 | `portfolio_snapshots` 테이블 생성 |
| v7 | `portfolio.showInPopover` 컬럼 추가 |
| v8 | `watchlist.accountId`, `portfolio.accountId` 컬럼 추가 |

---

## 계정 ID 마이그레이션 (v8)

v8에서 `accountId` 컬럼이 `DEFAULT ''`로 추가되므로, 기존 행은 모두 `accountId = ''` 상태가 된다. 이를 현재 로그인 계좌 ID로 업데이트하는 일회성 마이그레이션이 필요하다.

호출 위치:
- `AppDelegate.setupAdapter()` — 앱 시작 시 각 어댑터 초기화 직후
- `AccountSettingsView.login()` / `kiwoomLogin()` — 새로 로그인 시

```swift
try? DatabaseManager.shared.assignAccountIdToOrphanedItems(accountId: accountId)
```

`UserDefaults "DB.v8AccountIdMigrated"` 플래그로 중복 실행 방지.
