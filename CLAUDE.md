# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 프로젝트 개요

**StockWatch** — macOS 메뉴바 상주형 주식 시세 모니터링 앱 (개인 사용 목적).  
한국투자증권(KIS) REST API로 국내 주식 시세를 폴링하고, 조건 충족 시 macOS 네이티브 알림을 발송한다.

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

> **중요**: Swift 파일을 추가·삭제할 때마다 `xcodegen generate`를 실행해야 Xcode 프로젝트에 반영된다. `project.yml`의 `sources.path: StockWatch`가 디렉토리 전체를 자동 포함하므로 파일 경로만 올바르면 된다.

## 아키텍처

```
AppDelegate (NSApplicationDelegate, @MainActor)
│  메뉴바 아이콘·팝오버·설정 윈도우 생성
│  QuoteManager.$connectionState 구독 → 아이콘 상태 반영
│
├── QuoteManager (@MainActor, ObservableObject)  ← 시세 폴링 허브
│    3초 간격 폴링 | 연속 2회 실패 → connectionState = .error
│    any BrokerAdapter 교체 가능 (KISAdapter / MockBrokerAdapter)
│
├── BrokerAdapter (protocol, Sendable)
│    KISAdapter (actor)  — KIS REST API, OAuth 토큰 캐싱, 실전/모의 전환
│    MockBrokerAdapter   — 오프라인 개발용 랜덤 시세
│
├── AlertEvaluator (@MainActor)
│    QuoteManager.fetchAll() 완료마다 호출
│    DB의 AlertCondition 목록과 현재가 비교 → 조건 충족 시 fire()
│    fire() : NotificationManager.send() + AlertHistory 저장 + 쿨다운 갱신
│
├── DatabaseManager (@unchecked Sendable, singleton)
│    GRDB DatabaseQueue, Migration v1~v4
│    테이블: watchlist / portfolio / alert_conditions / alert_history
│
├── NotificationManager (UNUserNotificationCenterDelegate)
│    알림 클릭 → .openPopover 포스트 → AppDelegate가 팝오버 오픈
│
└── KeychainHelper (enum, static)
     account 키 prefix: "kis." (kis.appKey / kis.appSecret / kis.accountNumber)
     UserDefaults 키: KIS.isMock, KIS.loginDate
```

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

**NSNotification 기반 컴포넌트 간 통신**
- `AppDelegate.swift`의 `NSNotification.Name` extension에 이름 정의
- 현재 정의된 이름: `.openSettings`, `.openPopover`, `.popoverWillShow`

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
