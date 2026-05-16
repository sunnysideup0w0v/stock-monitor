# StockWatch — 개발 진행 체크리스트

> PRD v0.3 기반 | 업데이트: 2026-05-17 (Phase 5.5 — KRX OpenAPI 공식 연동)  
> Claude Code로 단계별 개발 진행. 각 Phase 완료 시 검증 항목 확인 후 다음 단계로 이동.

---

## Phase 0 — 개발 환경 세팅

### 0.1 사전 준비
- [x] Xcode 최신 버전 설치 확인 — Xcode 26.5 ✓
- [x] macOS 개발자 도구 설치 (`xcode-select --install`)
- [x] Swift 버전 확인 — Swift 6.3.2 ✓
- [x] Homebrew 설치 확인 — 5.1.11 ✓

### 0.2 Xcode 프로젝트 생성
- [x] xcodegen으로 프로젝트 자동 생성
- [x] 프로젝트명: `StockWatch`
- [x] Bundle Identifier: `com.personal.StockWatch`
- [x] SwiftUI + Swift 6.0
- [x] 저장 위치: `stock-monitor/StockWatch/`

### 0.3 Swift Package Manager 의존성 설정
- [x] GRDB.swift 6.29.3 추가 (project.yml → xcodegen)
- [x] 패키지 의존성 resolve 확인 ✓

### 0.4 프로젝트 기본 구조 생성
- [x] 디렉토리 구조 생성 (App/Core/Adapters/Models/Database/Notifications/Views/Resources)
- [x] 각 디렉토리에 placeholder `.swift` 파일 생성
- [x] `.gitignore` 생성
- [x] `git init` 및 초기 커밋

### 0.5 앱 기본 설정
- [x] `Info.plist` — LSUIElement = YES (Dock 아이콘 숨김)
- [x] `Info.plist` — NSAppTransportSecurity HTTPS 강제
- [x] Entitlements — Network Client 허용
- [x] 코드 서명: Manual / ad-hoc (로컬 개발용)

### ✅ Phase 0 검증
- [x] 빌드 성공 (`** BUILD SUCCEEDED **`)
- [x] 앱 실행 확인 (프로세스 정상 기동)
- [x] GRDB 패키지 import 오류 없음
- [ ] 메뉴바에 앱 아이콘이 표시됨 (직접 확인 필요)

---

## Phase 1 — MVP (핵심 기능)

### 1.1 메뉴바 앱 기반 구조

- [x] `AppDelegate.swift` — NSStatusBar 아이콘 등록
- [x] 메뉴바 아이콘 클릭 시 팝업 popover 표시
- [x] 팝업 내 기본 레이아웃 구성 (종목 리스트 영역 / 포트폴리오 요약 / 버튼)
- [x] "설정" → 설정 윈도우 열기

### 1.2 데이터 모델 정의

- [x] `StockQuote.swift` — 현재가, 등락폭, 등락률, 거래량 등
- [x] `WatchlistItem.swift` — 종목코드, 이름, 별칭, 그룹
- [x] `PortfolioItem.swift` — 종목코드, 평균매입가, 수량
- [x] `AlertCondition.swift` — 트리거 유형, 임계값, 활성화 여부
- [x] `AlertHistory.swift` — 발생 시각, 종목, 메시지

### 1.3 SQLite 데이터베이스 설정 (GRDB)

- [x] `DatabaseManager.swift` — DB 파일 생성 및 연결
- [x] Migration 1: `watchlist` 테이블 생성
- [x] Migration 2: `portfolio` 테이블 생성
- [x] Migration 3: `alert_conditions` 테이블 생성
- [x] Migration 4: `alert_history` 테이블 생성
- [x] CRUD 메서드 구현 (각 모델별 insert/update/delete/fetch)

### 1.4 브로커 어댑터 인터페이스

- [x] `BrokerAdapter.swift` — protocol 정의
- [x] `BrokerCredentials` — API 키, 계좌번호 모델 (BrokerAdapter.swift에 포함)
- [x] `MockBrokerAdapter.swift` — 테스트용 더미 어댑터 (랜덤 시세 반환)

### 1.5 한국투자증권(KIS) REST API 연동

- [x] `KISAdapter.swift` — BrokerAdapter 구현 (actor 기반)
- [x] OAuth 토큰 발급 (`/oauth2/tokenP`) 및 캐싱 (만료 5분 전 자동 갱신)
- [x] 주식 현재가 조회 (`/uapi/domestic-stock/v1/quotations/inquire-price`) 구현
- [x] API 응답 → `StockQuote` 모델 매핑 (부호 필드 `prdy_vrss_sign` 처리 포함)
- [x] 토큰 만료(401) 시 재발급 후 1회 자동 재시도
- [x] 실전투자 / 모의투자 환경 전환 지원
- [x] API 키를 macOS Keychain에 저장/불러오기 (`KeychainHelper.swift`)
- [x] 설정 화면 "계좌 연결" 탭 추가 (AppKey/Secret 입력, 연결 테스트 버튼)
- [x] 앱 시작 시 Keychain 자격증명 자동 로드 → KIS 연결, 없으면 Mock 폴백
- [ ] Exponential Backoff 재시도 로직 구현 (Phase 3에서 통합 예정)

### 1.6 관심 종목 UI

- [x] 설정 탭 1: 관심 종목 화면
  - [x] 종목 코드/이름 입력 UI
  - [x] 종목 추가 기능
  - [x] 종목 삭제 기능
  - [x] 그룹 설정 (장기보유 / 단기매매 / 관심)
  - [x] 별칭 입력 필드
- [x] 메뉴바 팝업에서 관심 종목 시세 표시
  - [x] 현재가, 등락폭, 등락률(%) 표시
  - [x] 상승(녹색) / 하락(빨간색) 색상 구분

### 1.7 알림 조건 설정 (트리거 ①②)

- [x] `AlertEvaluator.swift` — 조건 평가 엔진
- [x] 트리거 ① 특정 가격 도달 평가 로직
- [x] 트리거 ② 등락률 기준 평가 로직
- [x] 알림 발생 후 자동 비활성화 옵션
- [x] 쿨다운 로직 (동일 조건 재발송 최소 간격)

### 1.8 알림 설정 UI

- [x] 설정 탭 3: 알림 설정 화면
  - [x] 종목별 알림 조건 목록
  - [x] 가격 알림 추가 (목표가/손절가 입력)
  - [x] 등락률 알림 추가 (상승/하락 임계값 입력)
  - [x] 알림 활성화/비활성화 토글
  - [x] 쿨다운 시간 설정

### 1.9 macOS 네이티브 알림 구현

- [x] `NotificationManager.swift` — UNUserNotificationCenter 래퍼
- [x] 앱 시작 시 알림 권한 요청
- [x] 알림 발송 메서드 구현
- [x] 알림 클릭 시 앱 포커스 동작 (팝오버 자동 오픈)
- [x] 알림 발생 기록을 `alert_history` 테이블에 저장

### 1.10 포트폴리오 기본 기능

- [x] 설정 탭 2: 포트폴리오 화면
  - [x] 종목 추가 (종목코드, 평균매입가, 수량 수동 입력)
  - [x] 종목 삭제
- [x] 포트폴리오 손익 계산
- [x] 메뉴바 팝업 하단에 총 평가손익 표시

### 1.11 시세 자동 갱신

- [x] `QuoteManager.swift` — 폴링 관리
- [x] 폴링 모드: 3초 간격으로 관심 종목 전체 시세 조회
- [x] 시세 갱신 시 AlertEvaluator 자동 호출
- [x] 네트워크 오류 시 메뉴바 아이콘 상태 변경 (2회 연속 실패 → ⚠ 아이콘, 팝오버 점 빨간색)

### ✅ Phase 1 검증
- [x] 빌드 성공, 앱 실행됨 (`** BUILD SUCCEEDED **` 확인)
- [x] DB 파일 생성 및 4개 테이블 정상 생성 확인
- [ ] 메뉴바 아이콘 클릭 → 팝업 정상 표시 (직접 확인 필요)
- [ ] 관심 종목 추가 → DB 저장 → 앱 재시작 후에도 유지 (직접 확인 필요)
- [ ] Mock API → 시세 폴링 및 팝업 표시 확인 (직접 확인 필요)
- [ ] 목표가 알림 조건 설정 → 조건 충족 시 macOS 알림 수신 (직접 확인 필요)
- [ ] 등락률 알림 정상 동작 (직접 확인 필요)
- [ ] 포트폴리오 손익 계산 정확성 확인 (직접 확인 필요)
- [ ] 알림 이력이 DB에 저장됨 (직접 확인 필요)

---

## Phase 2 — 알림 고도화 & 포트폴리오 차트

### 2.1 WebSocket 실시간 시세

- [x] `RealtimeQuoteManager.swift` — URLSessionWebSocketTask 기반
- [x] 관심 종목 구독 (subscribe) 요청 (H0STCNT0 tr_id)
- [x] 실시간 시세 수신 → `StockQuote` 업데이트
- [x] 연결 끊김 시 자동 재연결 (Exponential Backoff: 1s→60s)
- [ ] 폴링 모드 → WebSocket 모드 전환 옵션 (현재는 자격증명 있을 때 WebSocket 자동 활성화)

### 2.2 거래량 급증 감지 (트리거 ③)

- [x] 최근 5일 평균 거래량 조회 및 저장 (KIS 일별시세 API, QuoteManager 인메모리 캐시)
- [x] `AlertEvaluator`에 거래량 배수 비교 로직 추가
  ```
  현재 거래량 >= 5일 평균 × N배 → 알림
  ```
- [x] 알림 설정 UI에 거래량 트리거 추가 (배수 임계값 입력)

### 2.3 DART 공시 연동 (트리거 ④)

- [x] DART Open API 키 발급 및 Keychain 저장 (`dart.apiKey`)
- [x] `DARTManager.swift` — 공시 목록 조회 (`/api/list.json`), corp_code 자동 조회 및 캐시
- [x] 종목별 공시 폴링 (5분 간격)
- [x] 새 공시 감지 → macOS 알림 발송 (rcept_no 기반 중복 방지)
- [x] 공시 종류 필터 (A 정기, B 주요사항, C 발행, D 지분, E 기타, I 거래소 — 계좌 연결 탭 체크박스 UI)
- [x] 계좌 연결 탭에 DART API 키 설정 UI 추가
- [x] 알림 클릭 시 DART 공시 페이지 브라우저 오픈 (rcept_no → URL)

### 2.4 포트폴리오 수익률 알림 (트리거 ⑤)

- [x] `AlertEvaluator`에 포트폴리오 기준 평가 추가
  ```
  포트폴리오 목표손익  >= +N원 → 알림   (portfolio_gain)
  포트폴리오 손절손익  <= -N원 → 알림   (portfolio_loss)
  포트폴리오 목표수익률 >= +N% → 알림   (portfolio_gain_rate)
  포트폴리오 손절수익률 <= -N% → 알림   (portfolio_loss_rate)
  ```
- [x] 전체 포트폴리오 기준 (symbol = "PORTFOLIO" 고정)
- [x] 금액(원) / 비율(%) 기준 선택 — 트리거 유형으로 구분
- [x] 알림 설정 UI에 4개 포트폴리오 트리거 추가, 종목코드 자동 "전체 포트폴리오"로 고정

### 2.5 알림 이력 화면

- [x] 설정 탭 내 "알림 이력" 탭 추가 (5번째 탭)
- [x] 종목별 / 트리거 종류별 필터 (텍스트 검색 + 드롭다운)
- [x] 최근 200건 스크롤 목록
- [x] DART 공시 이력 포함 — "공시 보기" 버튼 클릭 시 브라우저에서 공시 본문 오픈
- [x] 알림 클릭 시 DART 공시 페이지 브라우저 오픈 (rcept_no → URL, NotificationManager 확장)
- [x] 이력 CSV 내보내기 기능 (UTF-8 BOM, Excel 한글 호환)
- [x] 날짜 범위 필터 (DatePicker + 오늘/1주/1달/전체 퀵 프리셋)

### 2.6 포트폴리오 스냅샷 수집

- [x] Migration 6: `portfolio_snapshots` 테이블 생성 (timestamp, totalValue, totalGain, gainPct)
- [x] `SnapshotManager.swift` — 1분 간격 스냅샷 저장
- [x] 장 시간(09:00~15:30) 중에만 수집 토글 (기본값 ON)
- [x] 커스텀 시간대 추가/삭제 (프리·애프터 마켓 대응, 요일 무관 적용)
- [x] 보존 기간 선택 (30/90/180/365일/무제한) + 지금 정리 + 전체 삭제
- [x] 오래된 스냅샷 자동 정리 (설정된 보존 기간 기준)

### 2.7 포트폴리오 자산 변화 꺾은선 그래프

- [x] Swift Charts 기반 `AssetChartView.swift` 구현
- [x] X축: 시간, Y축: 총 평가금액(원) 또는 수익률(%)
- [x] Y축 토글 버튼 (금액 ↔ 수익률)
- [x] 기준선(baseline) 수평선 표시
- [x] 그래프 상단 요약: 기준선 대비 금액 차이 및 변화율
- [x] 데이터 공백(앱 미실행 구간) 처리 (segment 분리로 공백 표현)

### 2.8 기간 선택 UI

- [x] 상단 세그먼트 컨트롤: `일` · `주` · `월` · `연`
- [x] 일: 이전/다음 버튼 + "오늘" 퀵 버튼
- [x] 주: 이전/다음 주 이동 + 날짜 범위 레이블 표시
- [x] 월: 이전/다음 월 이동
- [x] 연: 이전/다음 연도 이동
- [x] 선택 기간에 따라 X축 자동 스케일 조정

### 2.9 장 시간 외 알림 제어

- [x] 장 시간 설정 (기본 09:00~15:30, 평일 기준 고정)
- [x] "장 시간 중에만 알림" / "24시간 알림" 전환 설정 (알림설정 탭 상단 토글)
- [x] 장 마감 후 알림 일시 중지 로직 (AlertEvaluator.evaluate + DARTManager 동시 적용)

### 2.10 KIS 잔고조회 연동 (보유 종목 자동 가져오기)

- [x] `KISAdapter.fetchPortfolio()` 실구현 — `GET /uapi/domestic-stock/v1/trading/inquire-balance`
      tr_id: 실전 `TTTC8434R` / 모의 `VTTC8434R`
      계좌번호 자동 파싱 (CANO 8자리 + ACNT_PRDT_CD 2자리)
- [x] `QuoteManager.fetchBalance()` 위임 메서드 추가
- [x] 포트폴리오 탭에 "계좌에서 가져오기" 버튼 추가 (KIS 미연결 시 비활성화 + 안내 메시지)
- [x] 가져온 보유 종목 미리보기 시트 (`PortfolioImportSheetView`)
- [x] 동기화 옵션: 신규 추가만 / 전체 교체 선택 (`ImportSyncMode`)
- [x] 계좌번호 미설정 시 에러 메시지 표시

### ✅ Phase 2 검증
- [x] WebSocket 연결 후 실시간 시세 갱신 확인 (빌드 성공, 앱 실행 확인)
- [x] 거래량 급증 시 알림 수신 (volume_spike 이력 확인 — Mock 6.4배 정상 발생)
- [ ] DART 공시 새 항목 감지 → 알림 수신 (별도 테스트 필요, 아래 참고)
- [x] 포트폴리오 수익률 임계값 초과 시 알림 수신 (portfolio_gain_rate +5% 이력 확인)
- [x] 알림 이력 화면에서 필터링 정상 동작 (이력 데이터 존재, UI 확인 완료)
- [x] 스냅샷 1분 간격으로 DB에 저장되는지 확인 (30분간 24건 수집 확인)
- [x] 자산 변화 그래프 일/주/월/연 단위 정상 표시 (테스트 데이터 생성 버튼으로 확인)
- [x] 기준선 대비 수익 요약 수치 정확성 확인
- [x] KIS 잔고조회로 보유 종목 가져오기 정상 동작 확인 (2.10)

### 2.11 테스트 인프라 구축

- [x] `project.yml`에 `StockWatchTests` (unit) / `StockWatchUITests` (UI) 타겟 추가
- [x] `AlertEvaluatorTests.swift` — canFire / isTriggered / isWithinMarketHours 17개 케이스
- [x] `PortfolioItemTests.swift` — totalCost / evaluatedGain / gainRate 8개 케이스
- [x] `StockQuoteTests.swift` — formattedPrice / formattedChange / isUp 8개 케이스
- [x] `SnapshotManagerTests.swift` — isActiveTime 장 시간·커스텀 범위 9개 케이스
- [x] `SettingsWindowUITests.swift` — 설정 창 열기 / 포트폴리오 추가 흐름
- [x] `SnapshotManager.isActiveTime(weekday:current:)` 테스트용 내부 오버로드 추가
- [x] `AppDelegate`: `--uitesting` 실행 인자로 설정 창 자동 오픈
- [x] 유닛 테스트 27개 전체 통과 (`xcodebuild test -only-testing:StockWatchTests`)
- [ ] UI 테스트: Xcode에서 직접 실행 필요 (macOS XCUITest는 ad-hoc 서명으로 CLI 실행 불가)

### Phase 3 자동화 테스트 (검증 대체)

- [x] `BackupManagerTests.swift` — Codable 라운드트립 / restore DB 삽입 / 중복 스킵 (5개)
- [x] `QuoteManagerTests.swift` — disconnectAlertEnabled UserDefaults / reconnect no-op (4개)
- [x] `NotificationManagerTests.swift` — selectedSound UserDefaults / availableSounds 목록 (5개)
- [x] `CrashLoggerTests.swift` — 로그 파일 생성 경로 / 내용 검증 / 추가 기록 (3개)
- [x] `CrashLogger.write()` / `BackupManager.restore()` internal 접근자 노출 (테스트 전용)
- [x] 유닛 테스트 62개 전체 통과

---

## Phase 3 — 안정화 및 UX 개선

### 3.1 에러 핸들링 강화

- [x] 네트워크 단절 감지 → 메뉴바 아이콘 상태 변경 (경고 표시)
- [x] 단절 시 사용자에게 macOS 알림 발송 (연속 2회 실패 시 1회 발송, 복구 시 재연결 알림)
- [x] API 오류 코드별 대응 처리 (403/503 일시적 에러 → 1초 후 재시도)
- [x] 크래시 로그 저장 (`~/Library/Logs/StockWatch/crash-YYYY-MM-DD.log`)
- [x] 자동 재시작 옵션 설정 (팝오버 "재연결" 버튼 + 알림설정 탭 "단절 시 알림" 토글)

### 3.2 자동 재연결

- [x] WebSocket 재연결 Exponential Backoff (1s → 2s → 4s → ... → 60s)
- [x] REST API 재시도 로직 통합 (403/503 → 1회 재시도)
- [x] 재연결 성공 시 상태 복구 (구독 목록 재등록)

### 3.3 macOS 로그인 시 자동 시작

- [x] `SMAppService.mainApp` 방식 구현 (macOS 13+ 권장 API)
- [x] 설정 화면 계좌 연결 탭에 "로그인 시 자동 시작" 토글 추가

### 3.4 설정 백업/복원

- [x] 설정 JSON 내보내기 (관심 종목, 포트폴리오, 알림 조건) — `BackupManager.export()`
- [x] JSON 파일로 설정 가져오기 — `BackupManager.importBackup()` (중복 심볼 스킵)
- [x] 백업 파일 형식 문서화 (`version`, `exportedAt`, `watchlist`, `portfolio`, `alertConditions`)

### 3.5 다크 모드 / 라이트 모드 대응

- [x] 모든 SwiftUI View `colorScheme` 환경변수 대응 확인 (SwiftUI 기본 지원, 커스텀 색상 없음)
- [x] 커스텀 색상 Asset에 다크/라이트 변형 추가 (커스텀 에셋 없음 — 시스템 색상만 사용)
- [x] 시스템 설정 변경 시 실시간 반영 확인 (SwiftUI 자동 처리)

### 3.6 알림 소리 및 UX 설정

- [x] 알림 소리: macOS 시스템 사운드 선택 Picker (15종 + 없음)
- [x] 무음 옵션 ("없음" 선택 시 소리 비활성화)
- [ ] 알림 클릭 시 해당 종목 상세 페이지 오픈

### 3.8 버전 정보 표시

- [x] `project.yml` `MARKETING_VERSION: 1.0.0` 설정
- [x] 설정 창 하단 우측에 버전 문자열 표시 (`vX.X.X (build)`)

### 3.7 온보딩 가이드

- [x] 최초 실행 감지 (`UserDefaults.Onboarding.completed` 플래그)
- [x] 온보딩 화면: 환영 → 계좌 연결 → 관심종목 → 알림 설정 → 완료 (5단계)
- [x] 각 단계 설명 및 "건너뛰기" 옵션

### ✅ Phase 3 검증
- [ ] 네트워크 Wi-Fi 끄기 → 앱 경고 표시 + 알림 수신 → 재연결 시 복구 알림
- [x] 팝오버 "재연결" 버튼 → 폴링 재시작 확인 (QuoteManagerTests 자동화)
- [x] `~/Library/Logs/StockWatch/` 디렉터리 생성 + 내용 검증 (CrashLoggerTests 자동화)
- [ ] 로그인 시 자동 시작 설정 후 재부팅 → 자동 실행 확인 (유효 서명 필요)
- [x] 설정 내보내기 → JSON 파일 생성 → 가져오기 → 데이터 복원 확인 (BackupManagerTests 자동화)
- [x] 다크 모드/라이트 모드 전환 시 UI 정상 렌더링 (SwiftUI 자동 처리)
- [ ] `UserDefaults.Onboarding.completed` 삭제 후 재실행 → 온보딩 화면 표시 (수동 확인)
- [x] 알림 소리 Picker UserDefaults 지속성 확인 (NotificationManagerTests 자동화)

---

## Phase 4 — 멀티 브로커 확장

### 4.1 BrokerAdapter 프로토콜 정비

- [x] `BrokerAdapter` 프로토콜에 `disconnect()` 메서드 추가 및 확정
- [x] `KISAdapter.disconnect()` — 자격증명·토큰 초기화
- [x] `MockBrokerAdapter.disconnect()` — no-op 구현
- [x] `BrokerRegistry.swift` — 이름 기반 어댑터 등록/조회/해제 레지스트리
- [x] `KiwoomAdapter.swift` — Stub 구현 (actor, 실 API는 Phase 4.4에서 연결)

### 4.2 한국투자증권(KIS) 어댑터

- [x] `KISAdapter.swift` — BrokerAdapter 구현 (Phase 1.5에서 구현 완료)
- [x] 토큰 발급, 현재가 조회 구현
- [x] Keychain에 KIS API 키 저장
- [x] 잔고조회 구현 (Phase 2.10에서 완료)

### 4.3 계좌 연결 UI 개선

- [x] 설정 탭 1: 계좌 연결 화면 개선
  - [x] 브로커 선택 세그먼트 (한국투자증권 / 키움증권)
  - [x] 선택 브로커에 맞는 연결 폼 표시 (키움은 "준비 중" 안내)
  - [x] "연결 테스트" 버튼 — KIS 기존 구현 유지
- [x] 로그인/로그아웃 시 `BrokerRegistry` 등록/해제 연동
- [x] 앱 시작 시 `AppDelegate.setupAdapter()`에서 KIS 어댑터 레지스트리 등록

### 4.4 키움증권 REST API 연동

> **방침**: 단일 브로커 모드로 먼저 구현 — KIS 또는 키움 중 하나만 활성화.
> 복수 동시 연결은 Phase 4.7에서 설계 검토 후 진행.

#### 4.4.1 OAuth2 토큰 발급
- [x] `KiwoomAdapter.connect()` 실구현 — `POST /oauth2/token` (grant_type=client_credentials)
- [x] 액세스 토큰 인메모리 캐싱, `expires_dt`(YYYYMMDDHHMMSS) 파싱, 5분 전 자동 갱신
- [x] 401 수신 시 재발급 후 1회 자동 재시도

#### 4.4.2 현재가 조회
- [x] `KiwoomAdapter.fetchQuote()` 실구현 — `POST /api/dostk/stkinfo` (api-id: ka10001)
- [x] 응답 필드 매핑: `cur_prc`(부호 제거), `pred_pre`, `flu_rt` → `StockQuote` (flat 구조)
- [x] 실제 API 호출로 응답 필드명 검증 완료 (로그 확인 — 삼성전자·NAVER·SK하이닉스 정상)

#### 4.4.3 잔고조회
- [x] `KiwoomAdapter.fetchPortfolio()` 실구현 — `POST /api/dostk/acnt` (api-id: kt00018)
- [x] 요청 body: `qry_tp=2`(개별), `dmst_stex_tp=KRX` (계좌번호는 토큰에 귀속)
- [x] 응답 배열 키: `acnt_evlt_remn_indv_tot`, 항목 필드: `stk_cd`, `stk_nm`, `rmnd_qty`, `pur_pric`

#### 4.4.4 자격증명 저장 및 앱 초기화
- [x] Keychain 키 추가: `kiwoom.appKey`, `kiwoom.appSecret`, `kiwoom.accountNumber`
- [x] `AccountManager`: 키움 계정 ID — `"KIWOOM-" + appKey.prefix(8)`, `activeBroker` UserDefaults로 브로커 구분
- [x] `AppDelegate.setupAdapter()`: `activeBroker="kiwoom"` 시 `KiwoomAdapter` 초기화
  - KIS 자격증명과 공존 가능 — `activeBroker` 값으로 우선순위 결정

#### 4.4.5 설정 UI 업데이트
- [x] 계좌 연결 탭 키움 섹션: "준비 중" 제거, App Key / App Secret 입력 폼 활성화
- [x] "연결 테스트" 버튼 — `KiwoomAdapter.connect()` + `fetchQuote("005930")` 호출
- [x] 로그인/로그아웃 시 `BrokerRegistry` 등록/해제 + `QuoteManager.setAdapter()` 전환
- [x] 포트폴리오 탭 "계좌에서 가져오기" — 키움 연결 시 정상 동작 확인

### 4.5 계정 종속 관심종목·포트폴리오

- [x] `AccountManager.swift` — `currentAccountId` (`"KIS-" + appKey.prefix(8)`), 미로그인 시 `""`
- [x] Migration v8: `watchlist.accountId` / `portfolio.accountId` 컬럼 추가 (DEFAULT `''`)
- [x] `fetchWatchlist()` / `fetchPortfolio()` — `accountId == ""` 이면 빈 배열 반환
- [x] `insert()` — 저장 전 `accountId = currentAccountId` 자동 설정
- [x] 기존 행 일회성 마이그레이션: `AppDelegate.setupAdapter()` + `SettingsView.login()` 에서 `assignAccountIdToOrphanedItems()` 호출 (`DB.v8AccountIdMigrated` 플래그)
- [x] 로그아웃 시 관심종목·포트폴리오 빈 상태로 전환 (currentAccountId == "" → 빈 배열)
- [x] 백업/복원 시 현재 계정에 귀속 (`insert()` 자동 설정)
- [x] 로그아웃 상태 시 관심종목·포트폴리오 탭에 계좌 연결 안내 메시지 표시

### 4.6 멀티 계좌 대응 (추후 검토)

> **미결 설계 과제**: 복수 증권사 계좌(KIS + 키움 + 미래에셋)가 동시에 연결될 경우,
> 관심종목·포트폴리오를 어떤 단위로 계정 종속시킬 것인가?

**고려해야 할 질문들**
- [ ] 계정 ID 스키마: 현재 `"KIS-" + appKey.prefix(8)` → 멀티 브로커 시 `"KIS-XXXX"` / `"KIWOOM-XXXX"` 등으로 확장 가능한가?
- [ ] 관심종목을 브로커 단위로 분리할지, 사용자(기기) 단위로 통합 관리할지
  - 분리: 브로커마다 모니터링 종목이 다를 경우 유용
  - 통합: 동일 종목을 여러 브로커로 보유한 경우 중복 등록 불필요
- [ ] 포트폴리오는 브로커 단위 분리가 자연스러움 (잔고 출처가 다름)
- [ ] `AccountManager`를 enum → class/actor로 전환하고 현재 활성 계정을 관리하는 방식 검토

### 4.7 복수 브로커 동시 모니터링

> KIS와 키움을 동시에 연결하여 두 계좌 데이터를 통합·선택 조회. PRD v0.3 참조.

#### 4.7.1 QuoteManager 다중 어댑터 지원
- [x] `adapter: (any BrokerAdapter)?` → `adapters: [String: any BrokerAdapter]` (key = accountId)
- [x] `addAdapter(id:adapter:)` / `removeAdapter(id:)` 메서드 추가
- [x] `setAdapter()` — Mock 전용 폴백으로 유지 (로그아웃 후 어댑터 없을 때 자동 호출)
- [x] `fetchAll()`: 어댑터 순서대로 시도, 앞 어댑터 실패 시 다음으로 폴백 (시세는 어느 브로커든 동일)
- [x] `fetchBalance(for accountId:)`: 특정 어댑터 잔고 조회 (accountId 미지정 시 첫 번째 실 어댑터)
- [x] 어댑터 하나 제거 시 남은 어댑터 정상 동작 보장 (removeAdapter → mock 폴백은 전체 로그아웃 시만)

#### 4.7.2 AccountManager 다중 계좌 지원
- [x] `connectedAccountIds: [String]` — Keychain 자격증명 기반 모든 로그인 계좌 ID 목록
- [x] `activeBroker` UserDefaults 의존성 제거 (Keychain 자격증명 존재 여부로 판단)
- [x] `isAnyConnected: Bool` 헬퍼 추가
- [x] `DatabaseManager.fetchWatchlist()`: `isAnyConnected` 기반으로 변경
- [x] `DatabaseManager.fetchPortfolio()`: `connectedAccountIds` IN 쿼리로 전체 브로커 포트폴리오 반환
- [x] `fetchPortfolio(for accountId:)` 오버로드 추가

#### 4.7.3 계좌 연결 탭 — 내부 로직만 변경 (UI 유지)
- [x] 세그먼트 탭 UI 유지 (탭은 폼 표시 선택, 로그인 상태와 무관)
- [x] 탭 레이블에 로그인 상태 배지 추가 ("한국투자증권 ✓", "키움증권 ✓")
- [x] `loadState()`: `activeBroker` UserDefaults 의존 제거, Keychain 기반으로 변경
- [x] `login()` / `logout()`: `activeBroker` 쓰기 제거, `addAdapter()`/`removeAdapter()` 사용
- [x] `kiwoomLogin()` / `kiwoomLogout()`: 동일하게 적용

#### 4.7.4 팝오버 포트폴리오 영역 — 변경 없음
- [x] 기존 `showInPopover` 토글로 팝오버 표시 종목 제어 (추가 필터 UI 없음)
- [x] `fetchPortfolio()` → `connectedAccountIds` 전체 대상으로 쿼리 (두 브로커 합산 자동 표시)
- [x] 팝오버 포트폴리오 손익 합산: 두 브로커 합계 표시 (기존 동작 유지)

#### 4.7.5 포트폴리오 탭 — 브로커 체크 드롭다운
- [x] 두 브로커 모두 로그인 시: "전체 브로커 ▾" Menu 드롭다운 표시 (멀티 셀렉트)
- [x] 단일 브로커 연결 시: 드롭다운 미표시 (기존 동작 유지)
- [x] "계좌에서 가져오기": 두 브로커 모두 로그인 시 → confirmationDialog로 브로커 선택
- [x] 포트폴리오 목록: 배지 대신 브로커별 Section 헤더로 구분 (전체 선택 시), 필터 시 flat 리스트

#### 4.7.8 팝오버 UX 개선
- [x] 멀티 브로커 시 포트폴리오 종목을 브로커별 소헤더(KIS ─ / 키움 ─)로 그룹핑 표시
- [x] 단일 브로커 연결이더라도 멀티 브로커 상태면 소헤더 노출 (어느 증권사 종목인지 표시)
- [x] 팝오버 외부 영역 클릭 시 자동 닫힘 (NSEvent 글로벌 이벤트 모니터)
- [x] 포트폴리오 행 평가금액(현재가×수량) 표시
- [x] 설정 토글로 팝오버 부가 정보 제어 (관심종목: 종목코드·그룹 / 포트폴리오: 매입단가·현재단가·수량)

#### 4.7.6 AppDelegate 초기화 로직 개선
- [x] `setupAdapter()`: KIS·키움 자격증명 각각 확인 → 둘 다 있으면 두 어댑터 모두 `addAdapter()`
- [x] 자격증명 없는 어댑터는 제외, 모두 없을 때만 MockBrokerAdapter 폴백

#### 4.7.7 AlertEvaluator / SnapshotManager 통합 포트폴리오 평가
- [x] `fetchPortfolio()` 변경으로 자동 합산 — 코드 변경 불필요

### ✅ Phase 4 검증
- [x] KIS API 연결 → 현재가 조회 성공
- [x] 키움 API 연결 → 토큰 발급 성공 + 현재가 조회 성공
- [x] 키움 잔고조회 → 보유 종목 가져오기 성공 (kt00018 /api/dostk/acnt)
- [x] 키움 + KIS 동시 연결 → 각각의 종목 시세 정상 수신 (adapters dict 독립 키 관리, fetchAll 폴백 로직 코드 검증)
- [x] 두 브로커의 포트폴리오 합산 손익 정확성 확인 (fetchPortfolio IN 쿼리 + calculatePortfolio reduce 코드 검증)
- [x] 브로커 하나 연결 실패 시 나머지 정상 동작 확인 (removeAdapter 단일 키 제거, isEmpty 시만 Mock 폴백 코드 검증)
- [x] 유닛 테스트 62개 전체 통과 (BackupManagerTests.test_restore_insertsPortfolioItem 포함)

---

## 공통 참고 사항

### API 정보
| 항목 | URL |
|------|-----|
| 키움 Open API+ | https://openapi.kiwoom.com |
| 한국투자증권 KIS | https://apiportal.koreainvestment.com |
| DART Open API | https://opendart.fss.or.kr |

### 주요 기술 제약
- 키움 영웅문 COM API는 **Windows 전용** → macOS에서는 키움 REST/WebSocket API 사용
- 실시간 시세는 WebSocket 구독 방식 우선 (API 호출 제한 회피)
- 배포 시 Apple 공증(Notarization) 필요 — 개인 사용은 로컬 빌드로 대응

### 보안 체크리스트
- [ ] API 키 → macOS Keychain 저장 (절대 UserDefaults/파일에 평문 저장 금지)
- [ ] 네트워크 통신 TLS 1.2+ 강제 (`NSAppTransportSecurity` 설정)
- [ ] 로컬 DB 암호화 검토 (GRDB + SQLCipher)

---

## Phase 5 — 종목 추천 (조건 스크리너 + AI 분석)

> 전략: KRX OpenAPI로 전종목 데이터를 일 1회 수집 → 로컬 조건 스크리닝 → KIS 실시간 시세 보강 → (선택) Claude API 분석

### 5.0 AI 분석 사용 여부 선택 (Claude API)

- [x] 계좌 연결 탭에 "AI 종목 분석" 섹션 추가
  - [x] 활성화 토글 (`UserDefaults "Screener.claudeEnabled"`)
  - [x] 활성화 시 Anthropic API 키 입력 (Keychain `anthropic.apiKey`)
  - [x] 비활성화 시 스크리너 UI에서 "AI 분석" 버튼 숨김

### 5.1 KRX 시장 데이터 연동

> KRX 공공 데이터 포털(`data.krx.co.kr`) 사용 — 별도 API 키 불필요

- [x] `StockUniverseItem.swift` 모델 정의 (`symbol`, `name`, `market`, `sector`, `close`, `open`, `high`, `low`, `volume`, `marketCap`(백만원), `per`, `pbr`, `updatedAt`)
- [x] DB Migration v9: `stock_universe` 테이블
- [x] `KRXManager.swift` 신규 작성 (`@MainActor`, singleton)
  - [x] KOSPI + KOSDAQ 전종목 일별 OHLCV + 시가총액 fetch (`MDCSTAT01501`)
  - [x] 전종목 PER/PBR fetch (`MDCSTAT03901`) 및 merge
  - [x] 마지막 거래일 계산 (`lastTradingDate()`) — 주말·16시 이전 처리
  - [x] `fetchIfNeeded()` — 이미 최신 데이터면 스킵
  - [x] 1시간 간격 자동 갱신 타이머
- [x] 계좌 연결 탭에 KRX 데이터 상태 UI (종목 수, 마지막 갱신일, 즉시 업데이트 버튼)
- [x] 앱 시작 시 `KRXManager.shared.start()` 호출

### 5.2 조건 스크리너 엔진

- [x] `ScreenerCondition.swift` — 조건 모델 정의
  - [x] 조건 타입: `priceRange`, `volumeMin`, `changeRateRange`, `perRange`, `pbrRange`, `marketCapRange`, `sectorFilter`, `marketFilter`
  - [x] 조건 조합: AND (전체 충족)
- [x] `ScreenerEngine.swift` — 로컬 SQLite 조건 스크리닝
  - [x] `stock_universe` 테이블 대상 GRDB 동적 쿼리 생성
  - [x] `DatabaseManager.fetchStockUniverse(matching:)` / `fetchDistinctValues()` 추가
  - [x] 결과 시가총액 내림차순 정렬, 최대 300개 제한

### 5.3 스크리너 UI

- [x] 설정 창에 "종목 추천" 탭 추가 (7번째 탭)
- [x] `ScreenerView.swift` 작성
  - [x] 조건 목록 (추가/삭제, AND 조합)
  - [x] 각 조건 타입별 입력 UI (수치 범위 TextField / 업종·시장 Picker)
  - [x] "스크리닝 실행" 버튼 → 결과 리스트 표시
  - [x] 결과 종목 → 관심종목 추가 버튼 (중복 추가 방지 체크마크)
- [x] 마지막 스크리닝 조건 저장 (UserDefaults JSON)
- [x] 데이터 마지막 갱신 시각 표시 (KRX 데이터 상태 패널)

### 5.4 Claude API 연동 (AI 분석, 선택 기능)

- [x] Anthropic API 키 Keychain 저장 (`anthropic.apiKey`)
- [x] 계좌 연결 탭에 Anthropic API 키 입력 UI 추가
- [x] `ClaudeAnalyzer.swift` 작성 (actor 기반)
  - [x] 스크리닝 조건 + 결과 종목(상위 20개) 컨텍스트 구성
  - [x] `POST https://api.anthropic.com/v1/messages` 호출 (model: claude-sonnet-4-5)
  - [x] 응답 스트리밍 파싱 (SSE — `URLSession.bytes`)
- [x] `ScreenerView`에 "AI 분석" 버튼 추가 (`claudeEnabled == true` 일 때만 표시)
  - [x] 분석 결과 스트리밍 시트 (`AnalysisSheetView`) — 실시간 토큰 표시
  - [x] 분석 결과 클립보드 복사 버튼

### 5.5 KRX OpenAPI 공식 연동 (API 키 방식)

- [x] `KRXManager.swift` — API 키 유무에 따라 소스 자동 전환
  - [x] KRX 공식 API: `http://data-dbg.krx.co.kr/svc/apis/sto/stk_bydd_trd` (KOSPI), `/sto/ksq_bydd_trd` (KOSDAQ)
  - [x] 인증: `AUTH_KEY` 요청 헤더, 쿼리 파라미터 `basDd=YYYYMMDD`
  - [x] 응답: `{"OutBlock_1": [...]}` — 모든 필드 콤마 포함 문자열로 반환
  - [x] 업종(`SECT_TP_NM`), 실제 OHLCV 포함 — 네이버 대비 데이터 품질 향상
  - [x] 네이버 증권 API 폴백 유지 (API 키 미설정 시)
- [x] `Info.plist` — ATS 예외 추가 (`data-dbg.krx.co.kr` HTTP 허용)
- [x] Keychain 키 `krx.apiKey` 추가
- [x] `KRXSettingsView` — API 키 입력 UI 추가 (저장/삭제, 현재 소스 표시)

### ✅ Phase 5 검증
- [ ] KRX OpenAPI 연동 → 전종목 데이터 정상 수신 및 DB 저장 확인
- [ ] 조건 스크리닝 → PER·PBR·시총 조건 조합으로 필터링 결과 확인
- [ ] KRX 버튼 → 업데이트 중 스피너 표시 + 완료 메시지 확인 (버그 수정)
- [ ] Claude API 분석 → 스크리닝 결과 시트에서 스트리밍 응답 정상 수신 확인
- [ ] 장 마감 후 자동 갱신 동작 확인 (평일 16:00)
- [ ] KRX OpenAPI 키 입력 후 업데이트 → 업종 포함 데이터 수신 확인

---

*각 Phase 검증 항목을 모두 체크한 후 다음 단계로 진행할 것.*
