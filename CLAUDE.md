# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 프로젝트 개요

**StockWatch** — macOS 메뉴바 상주형 주식 시세 모니터링 앱 (개인 사용 목적).  
한국투자증권(KIS) REST/WebSocket API로 국내 주식 시세를 수신하고, DART 공시 감지·포트폴리오 수익률 도달 등 다양한 조건 충족 시 macOS 네이티브 알림을 발송한다.

## 프로젝트 문서

새 세션을 시작할 때 아래 파일들을 읽어 현재 상태를 파악한다.

| 파일 | 설명 |
|------|------|
| `TODO.md` | 전체 Phase 계획 및 진행 상황. 완료된 항목은 `[x]`, 미완료는 `[ ]`. **현재 어디까지 됐는지 파악하려면 반드시 읽을 것** |
| `docs/PRD.md` | 제품 요구사항 정의서. 기능 목록, Phase별 로드맵, 화면 구성 |
| `docs/일지/YYYY-MM-DD.md` | 날짜별 개발 일지. 당일 작업 내역, 설계 결정, 파일 변경 목록 기록 |

> 작업 맥락이 필요하면 `TODO.md` → 최신 일지(`docs/일지/`) → `docs/PRD.md` 순으로 읽는다.

## 기술 스택

- **언어**: Swift 6.0 (strict concurrency 활성화)
- **UI**: SwiftUI (macOS 14.0+), AppKit (메뉴바·팝오버·윈도우 관리)
- **DB**: GRDB.swift 6.x — SQLite, Migration 방식으로 스키마 관리
- **프로젝트 생성**: xcodegen (`StockWatch/project.yml`)
- **외부 API**: 한국투자증권 KIS Developers REST API
- **인증 저장**: macOS Keychain (Security framework)
- **코드 서명**: Manual / ad-hoc (로컬 개발 전용, 공증 없음)

## 빌드 및 실행

```bash
# 프로젝트 디렉토리
cd StockWatch/

# 새 Swift 파일 추가 후 반드시 실행 (project.yml이 소스를 자동 포함)
xcodegen generate

# 빌드
xcodebuild -scheme StockWatch -configuration Debug build CODE_SIGNING_ALLOWED=NO

# 빌드 후 실행
APP_PATH=$(xcodebuild -scheme StockWatch -configuration Debug \
  -showBuildSettings CODE_SIGNING_ALLOWED=NO 2>/dev/null \
  | grep " BUILT_PRODUCTS_DIR " | awk '{print $3}')
open "$APP_PATH/StockWatch.app"

# 실행 중인 앱 종료
pkill -x StockWatch
```

## 테스트 실행

```bash
# 유닛 테스트 (CLI에서 실행 가능)
xcodebuild test -scheme StockWatch -destination 'platform=macOS' \
  -only-testing:StockWatchTests CODE_SIGNING_ALLOWED=NO

# UI 테스트 — macOS XCUITest는 유효한 코드 서명이 필요하므로 Xcode에서 Cmd+U로 실행
# CLI 실행 시 StockWatchUITests 타겟은 SIGKILL로 종료됨 (ad-hoc 서명 한계)
```

**테스트 파일 위치**

| 파일 | 대상 | 케이스 수 |
|------|------|-----------|
| `StockWatchTests/AlertEvaluatorTests.swift` | 쿨다운, isTriggered, 장 시간 경계 | 17 |
| `StockWatchTests/PortfolioItemTests.swift` | totalCost, evaluatedGain, gainRate | 8 |
| `StockWatchTests/StockQuoteTests.swift` | formattedPrice, formattedChange, isUp | 8 |
| `StockWatchTests/SnapshotManagerTests.swift` | isActiveTime 장 시간·커스텀 범위 | 9 |
| `StockWatchUITests/SettingsWindowUITests.swift` | 설정 창 오픈, 포트폴리오 추가 흐름 | 2 |

> **중요**: Swift 파일을 추가·삭제할 때마다 `xcodegen generate`를 실행해야 Xcode 프로젝트에 반영된다. `project.yml`의 `sources.path: StockWatch`가 디렉토리 전체를 자동 포함하므로 파일 경로만 올바르면 된다.

## 아키텍처

```
AppDelegate (NSApplicationDelegate, @MainActor)
│  메뉴바 아이콘·팝오버·설정 윈도우(720×600) 생성
│  QuoteManager.$connectionState 구독 → 아이콘 상태 반영
│  앱 시작 시 DB 관심종목 + showInPopover 보유 종목으로 폴링·DART·스냅샷 자동 시작
│  --uitesting 실행 인자: 설정 창 자동 오픈 (XCUITest 전용)
│
├── QuoteManager (@MainActor, ObservableObject)  ← 시세 폴링 허브
│    3초 간격 폴링 | 연속 2회 실패 → connectionState = .error
│    any BrokerAdapter 교체 가능 (KISAdapter / MockBrokerAdapter)
│    WebSocket 실시간 시세도 지원 (자격증명 있을 때 자동 활성화)
│
├── BrokerAdapter (protocol, Sendable)
│    KISAdapter (actor)  — KIS REST/WebSocket API, OAuth 토큰 캐싱, 실전/모의 전환
│    MockBrokerAdapter   — 오프라인 개발용 랜덤 시세
│
├── AlertEvaluator (@MainActor)
│    QuoteManager.fetchAll() 완료마다 호출
│    종목별: DB AlertCondition vs 현재가 비교 (isPortfolioLevel=false 항목만)
│    포트폴리오: evaluatePortfolio() — 총평가액/손익률 기준 4가지 트리거
│    fire() : NotificationManager.send() + AlertHistory 저장 + 쿨다운 갱신
│
├── DARTManager (@MainActor, singleton)
│    5분 간격 공시 폴링 (DART Open API /api/list.json)
│    corp_code 자동 조회 및 인메모리 캐시
│    새 공시 감지 → 알림 발송 + AlertHistory 저장 (metadata = rcept_no)
│    UserDefaults "DART.filterTypes"로 공시 종류 필터
│
├── SnapshotManager (@MainActor, singleton)
│    1분 간격 포트폴리오 스냅샷 저장 (portfolio_snapshots 테이블)
│    marketHoursOnly(기본 ON): 평일 09:00~15:30 중에만 수집
│    customRanges: 추가 시간대(JSON) — 프리/애프터 마켓 대응
│    keepDays: 보존 기간 (UserDefaults 0 저장 = 365일 적용, UI -1 태그 = 무제한 = 0 저장)
│
├── DatabaseManager (@unchecked Sendable, singleton)
│    GRDB DatabaseQueue, Migration v1~v9 (현재)
│    테이블: watchlist / portfolio / alert_conditions / alert_history / portfolio_snapshots / stock_universe
│
├── NotificationManager (UNUserNotificationCenterDelegate)
│    send(title:body:symbol:urlString:) — urlString이 있으면 userInfo["url"]에 저장
│    알림 클릭: url 있으면 NSWorkspace.open(url), 없으면 .openPopover 포스트
│
└── KeychainHelper (enum, static)
     KIS: kis.appKey / kis.appSecret / kis.accountNumber
     DART: dart.apiKey
     KRX: krx.apiKey (openapi.krx.co.kr 발급, 미설정 시 네이버 증권 API 폴백)
     Screener: anthropic.apiKey (Claude AI 분석용, 선택)
     UserDefaults: KIS.isMock, KIS.loginDate, DART.filterTypes, DART.seenRceptNos
                   SnapshotManager.marketHoursOnly, SnapshotManager.customRanges,
                   SnapshotManager.keepDays
```

**SettingsView 탭 구성** (현재 7개):
1. 계좌 연결 (KIS API 키 + DART API 키 + 공시 종류 필터 + KRX OpenAPI 키 + Claude AI 토글)
2. 관심종목
3. 포트폴리오
4. 알림설정
5. 알림 이력 (날짜 범위 필터 + 타입 필터 + CSV 내보내기)
6. 자산 차트 (AssetChartView — Swift Charts 기반)
7. 종목 추천 (ScreenerView — 조건 스크리너 + Claude AI 분석)

## 커밋 규칙

작업 중 아래 시점에 맞춰 자동으로 `git commit`을 남긴다. 별도 요청 없이도 해당 시점이 되면 커밋한다.

**커밋 시점**
- TODO.md의 Phase 항목 하나가 완료됐을 때
- 독립적인 기능 단위(파일 신규 생성, 기존 기능 수정 완료 등)가 마무리됐을 때
- 다른 작업 영역으로 전환하기 직전

**커밋 메시지 형식**
```
Phase N: 작업 내용 요약 (한국어)

예시:
Phase 1: KIS REST API 어댑터 구현
Phase 1: 계좌 연결 UI 로그인/로그아웃 개념으로 재설계
Phase 2: WebSocket 실시간 시세 구현
```

- 제목은 한국어로 간결하게, 무엇을 했는지 중심으로 작성
- 본문은 생략해도 무방하나, 설계 결정이나 트레이드오프가 있었다면 기록

## 앱 재실행 규칙

아래 시점에는 반드시 앱을 종료 후 재실행한다. 별도 요청 없이도 자동으로 수행한다.

```bash
pkill -x StockWatch 2>/dev/null; sleep 0.5 && open "$(find ~/Library/Developer/Xcode/DerivedData -name 'StockWatch.app' -path '*/Debug/*' | head -1)"
```

**재실행 시점**
- Phase 구현이 완료되고 커밋한 직후
- 버그 수정(fix 커밋) 후
- UI 변경이 포함된 작업 완료 후

## TODO.md 관리 규칙

`TODO.md`는 프로젝트 진행 상황의 단일 진실 공급원이다. 아래 규칙을 반드시 따른다.

- **작업 완료 즉시** 해당 항목을 `- [x]`로 체크한다 — 커밋 전에 반영할 것
- Phase 전체가 완료되면 `### ✅ Phase N 검증` 항목도 해당되는 것은 체크한다
- 새 기능을 추가하거나 설계가 변경되면 TODO.md에도 새 항목을 추가/수정한다
- 날짜 업데이트: 파일 상단 `업데이트: YYYY-MM-DD`를 작업한 날짜로 갱신한다

## 주요 패턴 및 규칙

**Concurrency**
- 브로커 어댑터는 반드시 `actor`로 구현 — 토큰 캐시 등 mutable state의 thread safety 보장
- UI·폴링 로직은 `@MainActor`
- `@unchecked Sendable`은 최후 수단으로만 사용

**BrokerAdapter 추가 시**
1. `actor`로 `BrokerAdapter` 프로토콜 구현
2. `nonisolated let brokerName` 선언
3. `connect()` 에서 토큰/세션 초기화
4. `fetchQuote()` 응답 필드는 모두 `String?` (옵셔널)로 받아 파싱 — KIS API는 장 시간 외에 일부 필드를 생략함

**DB 스키마 변경 시**
- `DatabaseManager.swift`에 새 `migrator.registerMigration("vN_...")` 추가
- 기존 Migration은 절대 수정하지 않는다
- 현재 최신: v10 (`stock_universe.isEtf` 컬럼 추가). 다음 마이그레이션은 v11부터

**AlertCondition.TriggerType 추가 시**
`TriggerType`은 여러 곳에서 exhaustive switch로 사용된다. 새 케이스 추가 시 아래 모두 업데이트 필요:
- `AlertEvaluator`: `isTriggered()`, `makeMessage()`, `evaluatePortfolio()` 내 switch
- `SettingsView`: `formatThreshold()`, 알림 추가 폼의 트리거 타입 선택
- `AlertHistoryView`: 필터 Picker의 타입 목록
현재 케이스: `targetPrice`, `stopLoss`, `rateUp`, `rateDown`, `volumeSpike`, `portfolioGain`, `portfolioLoss`, `portfolioGainRate`, `portfolioLossRate`, `dartDisclosure`
- `.dartDisclosure`와 portfolio 계열은 종목별 `isTriggered()`에서 `false` 반환 (별도 경로로 평가)

**ScreenerCondition.ConditionType 추가 시**
새 케이스 추가 시 아래 모두 업데이트 필요:
- `ScreenerEngine.apply(_:to:)`: 새 케이스에 대한 필터 로직 추가
- `ClaudeAnalyzer.describeCondition(_:)`: 프롬프트 출력용 설명 추가
- `ConditionType.usesStringValue`: 문자열 값 사용 여부 (`sectorFilter`, `marketFilter`, `instrumentType`만 `true`)
- `ConditionType.supportsMin/supportsMax`: 숫자 입력 지원 여부
- 문자열 다중 선택 조건(`usesStringValue = true`)은 `stringValue`에 콤마 구분 저장 → `ScreenerEngine.multiValues(_:)`로 파싱 → GRDB `Collection.contains(Column)` 으로 `IN` 쿼리 생성

**계정 종속 데이터 (관심종목 · 포트폴리오)**
- `AccountManager.currentAccountId` — `"KIS-" + appKey.prefix(8)`, 미로그인 시 `""`
- `fetchWatchlist()` / `fetchPortfolio()` — `currentAccountId == ""` 이면 빈 배열 반환 (로그아웃 상태에서 항목 미노출)
- `insert(WatchlistItem/PortfolioItem)` — 저장 전 `accountId = AccountManager.currentAccountId` 자동 설정
- Migration v8: `watchlist.accountId`, `portfolio.accountId` 컬럼 추가 (DEFAULT `''`)
- 기존 행 일회성 마이그레이션: `AppDelegate.setupAdapter()` + `SettingsView.login()` 에서 `DatabaseManager.assignAccountIdToOrphanedItems()` 동기 호출. UserDefaults `"DB.v8AccountIdMigrated"` 플래그로 중복 방지
- 백업/복원 시 `insert()` 경로를 타므로 현재 계정에 자동 귀속됨

**NSNotification 기반 컴포넌트 간 통신**
- `AppDelegate.swift`의 `NSNotification.Name` extension에 이름 정의
- 현재 정의된 이름: `.openSettings`, `.openPopover`, `.popoverWillShow`, `.krxDataUpdated`

**KRX 시장 데이터 (`KRXManager`)**
- API 키 있음 → `http://data-dbg.krx.co.kr/svc/apis/sto/stk_bydd_trd` (KOSPI) / `/ksq_bydd_trd` (KOSDAQ), `AUTH_KEY` 헤더, `basDd=YYYYMMDD`
- API 키 없음 → 네이버 증권 `m.stock.naver.com/api/stocks/marketValue/{market}` 폴백 (PER/PBR·업종 없음)
- 응답: `{"OutBlock_1": [...]}` — 모든 숫자 필드가 콤마 포함 문자열, `MKTCAP`은 원 단위 (÷ 1,000,000 → 백만원)
- `open` 컬럼 = 전일 종가 (= `TDD_CLSPRC - CMPPREVDD_PRC`) — `ScreenerEngine.changeRateRange` SQL 수식이 이 규약에 의존
- Keychain: `krx.apiKey` (openapi.krx.co.kr에서 서비스별 신청 후 발급)

**로깅 (`AppLogger` / `CrashLogger`)**
- `AppLogger.log(_:level:category:)` — `os.Logger` + 파일 이중 기록. Console.app에서 `subsystem:com.personal.StockWatch` 필터로 조회
  - 파일 경로: `~/Library/Logs/StockWatch/app-YYYY-MM-DD.log`
  - 카테고리별 정적 인스턴스: `AppLogger.screener`, `AppLogger.app`
- `CrashLogger` — ObjC 예외(`NSSetUncaughtExceptionHandler`) + Swift 시그널(`SIGABRT`, `SIGILL`, `SIGSEGV`, `SIGFPE`, `SIGBUS`, `SIGTRAP`) 양쪽 포착
  - 파일 경로: `~/Library/Logs/StockWatch/crash-YYYY-MM-DD.log`
  - 시그널 핸들러는 반드시 `signal(caught, SIG_DFL); raise(caught)` 로 재발생시켜 시스템 크래시 리포트도 생성

**MarkdownUI (`AnalysisSheetView`) 패턴**
- 패키지: `gonzalezreal/swift-markdown-ui` 2.4.0 (`project.yml` 등록)
- **Swift 6 주의**: `markdownTextStyle { }` 블록 클로저는 nonisolated 컨텍스트 — `@MainActor`인 `markdownTextStyle(textStyle:)` 를 직접 호출하면 컴파일 오류 발생
  - 해결: `Theme.gitHub`를 base로 사용하고 `.strong { }`, `.code { }`, `.blockquote { }` 등 블록 클로저에서는 `markdownTextStyle` 대신 표준 SwiftUI 모디파이어만 사용
- 스트리밍 중 실시간 렌더링 금지 — 부분 파싱으로 레이아웃 깨짐. 로딩 스피너 표시 → 완료 후 전체 렌더링
- 커스텀 테마는 `extension MarkdownUI.Theme { static var analysis: Theme { ... } }` 패턴으로 정의

**Swift Charts (`AssetChartView`) 패턴**
- 중첩 `ForEach` + `LineMark` 조합은 컴파일러 타입 체크 타임아웃 유발 → `chartBody` computed property와 `@ChartContentBuilder` 메서드로 분리
- 세그먼트 분리(데이터 공백 처리): `series: .value("s", idx)` 로 시리즈를 달리 지정
- `PortfolioSnapshot`은 `Identifiable` 미구현 → `ForEach(seg, id: \.timestamp)` 사용
- SourceKit이 "Cannot find type in scope", "No such module 'MarkdownUI'" 등 오류를 표시해도 실제 `xcodebuild` 는 성공하는 경우가 많음 — **빌드 결과로만 판단할 것**. GRDB 커스텀 타입, MarkdownUI, 외부 패키지 전반에서 재현됨

**CSV 내보내기**
- UTF-8 BOM 필수 (`Data([0xEF, 0xBB, 0xBF])`) — Excel 한글 호환
- `NSSavePanel` 기본 디렉토리: `~/Downloads`

**DART 관련**
- 공시 URL 패턴: `https://dart.fss.or.kr/dsaf001/main.do?rcpNo=\(rceptNo)`
- `AlertHistory.metadata`에 `rcept_no` 저장 → 이력 화면에서 "공시 보기" 버튼 URL 복원
- 공시 종류 코드: A=정기, B=주요사항, C=발행, D=지분, E=기타, I=거래소

## 자산 차트 테스트 데이터

`설정 → 자산 차트` 탭 하단에 **"테스트 데이터 생성"** / **"테스트 데이터 삭제"** 버튼이 있다.

- 생성: 평일 09:00~15:30, 5분 간격, 30일치 스냅샷 (~1,700건) — 랜덤 워크 기반
  - 매입원가 가정: 9,500,000원, 시작 평가액: 10,000,000원
  - 일/주/월 뷰 검증 가능 (연 뷰는 실제 데이터 축적 필요)
- 삭제: `DatabaseManager.shared.deleteAllSnapshots()` 호출 (되돌릴 수 없음)
- 데이터가 없는 기간을 선택하면 빈 화면에도 버튼이 표시됨
- 데이터가 있는 상태에서도 차트 아래에 항상 표시됨

## KIS API 참고

| 구분 | Base URL |
|------|----------|
| 실전투자 | `https://openapi.koreainvestment.com:9443` |
| 모의투자 | `https://openapivts.koreainvestment.com:29443` |

- 토큰: `POST /oauth2/tokenP` — 유효기간 24시간, 만료 5분 전 자동 갱신
- 현재가: `GET /uapi/domestic-stock/v1/quotations/inquire-price`
  - `tr_id`: 실전 `FHKST01010100` / 모의 `VHKST01010100`
  - `custtype: P` (개인)
  - `prdy_vrss_sign` 2=상승 3=보합 4=하락 — 부호를 별도 파싱해야 함
- 403 오류: 토큰 발급 시 일시적으로 발생할 수 있음 (재시도로 해결된 사례 있음)

## 키움증권 REST API 참고 (미구현 — 추후 어댑터 추가 시 참고)

> **현재 미사용.** `KiwoomAdapter`를 구현할 때 아래 정보를 참고한다.  
> Base URL·토큰 엔드포인트는 공식 가이드에서 직접 확인했으나, API ID·WebSocket URL 등 일부는 커뮤니티 래퍼(오픈소스)에서 보완한 정보다. **구현 전 공식 포털 로그인 후 재확인 필요.**
>
> - 공식 포털 (앱키·시크릿키 발급): https://openapi.kiwoom.com  
> - 공식 가이드 (로그인 필요): https://openapi.kiwoom.com/guide/apiguide  
> - 참고한 오픈소스 래퍼: https://github.com/younghwan91/kiwoom-rest-api

| 구분 | REST Base URL | WebSocket URL |
|------|---------------|----------------|
| 실전투자 | `https://api.kiwoom.com` | `wss://api.kiwoom.com:10000` |
| 모의투자 | `https://mockapi.kiwoom.com` | `wss://mockapi.kiwoom.com:10000` |

> 모의투자는 KRX(국내주식) 시장만 지원

**인증**
- 토큰 발급: `POST /oauth2/token` (API ID: `au10001`) — `appkey` + `secretkey` 전달
- 토큰 폐기: `au10002`
- 인증 헤더: `Authorization: Bearer <접근토큰>`

**주요 API ID**
- 현재가(기본정보): `ka10001` — `stk_cd` 파라미터로 종목코드 전달
- 실시간 WebSocket 구독 타입 19종: `0B`=주식체결, `0C`=주식우선호가, `0D`=주식호가잔량 등

**어댑터 구현 시 체크리스트**
1. `actor`로 `BrokerAdapter` 프로토콜 구현 (KISAdapter와 동일 패턴)
2. Keychain 키: `kiwoom.appKey` / `kiwoom.appSecret` / `kiwoom.accountNumber`
3. `KIS.isMock`에 대응하는 `Kiwoom.isMock` UserDefaults 키 추가
4. 토큰 유효기간 및 자동 갱신 로직 확인 (KIS는 24시간, 키움은 공식 문서 확인 필요)
5. 실전·모의 전환 시 Base URL 분기 처리
