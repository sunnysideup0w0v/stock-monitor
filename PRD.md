# PRD — StockWatch

> 버전: v0.3 | 업데이트: 2026-05-15  
> 개인 사용 목적의 macOS 메뉴바 주식 모니터링 앱

---

## 제품 개요

macOS 메뉴바에 상주하며, 연결된 증권사 계좌의 관심종목 시세와 포트폴리오 손익을 실시간으로 모니터링한다. 조건 충족 시 macOS 네이티브 알림을 발송하고, DART 공시도 감지한다.

---

## 사용자 목표

| # | 목표 | 우선순위 |
|---|------|---------|
| 1 | 메뉴바에서 주요 종목 시세를 바로 확인 | 필수 |
| 2 | 특정 가격·수익률 도달 시 알림 수신 | 필수 |
| 3 | 포트폴리오 손익을 실시간으로 추적 | 필수 |
| 4 | DART 공시 감지 및 알림 수신 | 필수 |
| 5 | KIS·키움 두 계좌를 동시에 모니터링 | 중요 |
| 6 | 포트폴리오 자산 변화 추이 차트 | 보통 |

---

## Phase별 기능 정의

### Phase 1 — MVP (완료)
- 메뉴바 팝오버: 관심종목 시세 (현재가·등락폭·등락률)
- KIS REST API 연동 (OAuth 토큰, 현재가 조회, 잔고 조회)
- SQLite DB (관심종목·포트폴리오·알림조건·알림이력)
- 알림 트리거 ①②: 목표가·등락률 도달
- 팝오버 포트폴리오 요약 (총 평가손익)

### Phase 2 — 알림 고도화 & 차트 (완료)
- KIS WebSocket 실시간 시세
- 알림 트리거 ③: 거래량 급증 감지
- 알림 트리거 ④: DART 공시 감지
- 알림 트리거 ⑤: 포트폴리오 수익률 도달
- 알림 이력 화면 (필터·CSV 내보내기)
- 포트폴리오 스냅샷 수집 + 자산 변화 차트 (Swift Charts)

### Phase 3 — 안정화 (완료)
- 네트워크 단절 감지·재연결·알림
- 크래시 로그, 설정 백업/복원
- macOS 로그인 시 자동 시작
- 온보딩 가이드 (5단계)

### Phase 4 — 멀티 브로커 확장 (진행 중)

#### 4.4 키움증권 REST API 연동 (완료)
- KIS와 키움 중 하나를 선택하여 활성화하는 단일 브로커 모드
- 키움 토큰 발급, 현재가(ka10001), 잔고(kt00018) 구현
- API 디버그 로그 (`~/Documents/study/stock-monitor/logs/`)

#### 4.7 멀티 브로커 동시 모니터링 (신규)

**목표**: KIS와 키움을 동시에 연결하고, 각 계좌 데이터를 통합 또는 선택하여 조회

---

## Phase 4.7 상세 기능 정의

### 계좌 연결 탭

**변경 없음**: 기존 세그먼트 탭(KIS / 키움 / 미래에셋) UI 유지.  
단, 세그먼트는 "어느 폼을 보여줄지" 선택일 뿐 — 두 브로커 모두 로그인 상태를 동시에 유지할 수 있도록 내부 로직만 변경.

- 탭 전환 시 다른 브로커 로그인 상태에 영향 없음
- 각 탭 헤더에 로그인 상태 배지 표시 (예: "키움증권 ✓")

### 메뉴바 팝오버

**변경 없음**: 팝오버에 별도 필터 없음.  
설정 > 포트폴리오 탭에서 각 종목의 "팝오버에 표시" 토글로 제어 (기존 `showInPopover` 그대로 활용).  
두 브로커에 걸쳐 `showInPopover = true`인 종목이 모두 표시됨.

**관심종목 영역**: 두 브로커 모두의 종목 통합 표시 (중복 종목은 하나만)

### 설정 > 포트폴리오 탭

**브로커 필터**: 체크 드롭다운 (멀티 셀렉트)
```
  [브로커 필터 ▾]  ← 버튼 클릭 시 드롭다운 메뉴 표시
    ✓ KIS
    ✓ 키움증권
```
- 기본값: 연결된 모든 브로커 선택 (전체 표시)
- 특정 브로커 체크 해제 시 해당 브로커 종목 목록에서 숨김
- 단일 브로커만 연결 시 드롭다운 미표시 (기존 동작 유지)

**계좌에서 가져오기**:
- 두 브로커 모두 로그인 시 → 어느 브로커에서 가져올지 ActionSheet 선택
- 단일 브로커 연결 시 → 기존 동작 유지

### 알림 설정

- 포트폴리오 기준 알림: 기본은 **합산** 기준
- 추후 브로커별 분리 알림 필요 시 검토

---

## 기술 설계

### QuoteManager

```
현재:  adapter: (any BrokerAdapter)?

변경:  adapters: [String: any BrokerAdapter]   // key = accountId
       connectionStates: [String: ConnectionState]
       
       addAdapter(id: String, adapter: any BrokerAdapter)
       removeAdapter(id: String)
       fetchAll(): 모든 어댑터 병렬 호출, 동일 종목은 최신 timestamp 우선
       fetchBalance(for accountId: String): 특정 어댑터 잔고 조회
```

- 하나의 어댑터 실패 → 해당 어댑터만 `.error` 상태, 나머지 정상 동작
- 메뉴바 아이콘: 어댑터 중 하나라도 오류 → 경고 표시

### AccountManager

```
현재:  currentAccountId: String (단일)

변경:  connectedAccountIds: [String]  // 로그인된 모든 계좌 ID 목록
       isConnected(accountId: String): Bool
```

- `activeBroker` UserDefaults 폐기 → Keychain 자격증명 존재 여부로 로그인 판단

### DatabaseManager

- 스키마 변경 없음 (`portfolio.accountId`로 브로커 구분 이미 가능)
- `fetchPortfolio()`: `connectedAccountIds` 전체 조회 (현재는 단일 ID만)
- `fetchPortfolio(for accountId:)`: 특정 브로커 조회 (포트폴리오 탭 필터용)

### PortfolioItem (UI)

- `brokerDisplayName`: `accountId` 접두사로 "KIS" / "키움" 표시 (DB 저장 불필요)
- `PortfolioItem.brokerName: String { accountId.hasPrefix("KIS") ? "KIS" : "키움" }`
- 포트폴리오 탭에서 브로커 구분 컬럼(또는 섹션 헤더)으로 활용

### SnapshotManager

- 합산 총평가액으로 스냅샷 저장 (기존 동작 유지 — 두 어댑터 합산)

---

## 제약 사항

- 키움은 WebSocket 실시간 시세 미지원 → REST 폴링만 사용 (3초 간격 유지)
- KIS는 WebSocket 실시간 시세 지원 → 키움 종목은 REST 폴링으로 보완
- 같은 종목을 두 브로커에서 모두 구독 시 → REST 폴링 결과는 동일하므로 중복 호출 방지 검토

---

## 비기능 요구사항

- 두 브로커 동시 연결 시에도 폴링 주기 3초 유지 (병렬 처리)
- 기존 단일 브로커 설정 사용자도 아무 설정 변경 없이 그대로 동작

---

## 향후 검토 (v0.4 이후)

- 미래에셋 어댑터 추가
- 브로커별 독립 알림 조건 설정
- 포트폴리오 브로커별 수익 차트 비교
