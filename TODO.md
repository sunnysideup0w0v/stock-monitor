# StockWatch — 개발 진행 체크리스트

> PRD v0.2 기반 | 업데이트: 2026-05-15  
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
- [ ] 키움 REST API 연동 (1.5 구현 후)

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
- [ ] 공시 종류 필터 (실적 발표, 유상증자, 자사주 매입 등)
- [x] 계좌 연결 탭에 DART API 키 설정 UI 추가

### 2.4 포트폴리오 수익률 알림 (트리거 ⑤)

- [ ] `AlertEvaluator`에 포트폴리오 기준 평가 추가
  ```
  오늘 평가손익 >= +N만원 → 알림
  오늘 수익률 <= -N% → 알림
  ```
- [ ] 전체 포트폴리오 기준 / 종목별 기준 선택
- [ ] 금액(원) / 비율(%) 기준 선택

### 2.5 알림 이력 화면

- [ ] 설정 탭 내 알림 이력 섹션 구현
- [ ] 날짜별 / 종목별 / 트리거 종류별 필터
- [ ] 이력 목록 무한 스크롤 또는 페이지네이션
- [ ] 이력 CSV 내보내기 기능

### 2.6 포트폴리오 스냅샷 수집

- [ ] Migration 5: `portfolio_snapshots` 테이블 생성
  ```sql
  CREATE TABLE portfolio_snapshots (
    id         INTEGER PRIMARY KEY,
    timestamp  DATETIME,
    total_value INTEGER,
    total_gain  INTEGER,
    gain_pct    REAL
  )
  ```
- [ ] `SnapshotManager.swift` — 1분 간격 스냅샷 저장
- [ ] 장 시간(09:00~15:30) 중에만 스냅샷 저장 (설정 가능)
- [ ] 오래된 스냅샷 자동 정리 (기본 1년 보존)

### 2.7 포트폴리오 자산 변화 꺾은선 그래프

- [ ] Swift Charts 기반 `AssetChartView.swift` 구현
- [ ] X축: 시간, Y축: 총 평가금액(원) 또는 수익률(%)
- [ ] Y축 토글 버튼 (금액 ↔ 수익률)
- [ ] 기준선(baseline) 수평선 표시
- [ ] 그래프 상단 요약: 기준선 대비 금액 차이 및 변화율
- [ ] 데이터 공백(앱 미실행 구간) 처리 (점선 or 공백)

### 2.8 기간 선택 UI

- [ ] 상단 세그먼트 컨트롤: `일` · `주` · `월` · `연`
- [ ] 일: 날짜 피커 (어제 / 오늘 / 특정 날짜)
- [ ] 주: "n월 m째 주" 드롭다운
- [ ] 월: 월 선택 드롭다운
- [ ] 연: 연도 선택 드롭다운
- [ ] 선택 기간에 따라 X축 자동 스케일 조정

### 2.9 장 시간 외 알림 제어

- [ ] 장 시간 설정 (기본 09:00~15:30)
- [ ] "장 시간 중에만 알림" / "24시간 알림" 전환 설정
- [ ] 장 마감 후 알림 일시 중지 로직

### ✅ Phase 2 검증
- [x] WebSocket 연결 후 실시간 시세 갱신 확인 (빌드 성공, 앱 실행 확인)
- [ ] 거래량 급증 시 알림 수신
- [ ] DART 공시 새 항목 감지 → 알림 수신
- [ ] 포트폴리오 수익률 임계값 초과 시 알림 수신
- [ ] 알림 이력 화면에서 필터링 정상 동작
- [ ] 스냅샷 1분 간격으로 DB에 저장되는지 확인
- [ ] 자산 변화 그래프 일/주/월/연 단위 정상 표시
- [ ] 기준선 대비 수익 요약 수치 정확성 확인

---

## Phase 3 — 안정화 및 UX 개선

### 3.1 에러 핸들링 강화

- [ ] 네트워크 단절 감지 → 메뉴바 아이콘 상태 변경 (경고 표시)
- [ ] 단절 시 사용자에게 macOS 알림 발송
- [ ] API 오류 코드별 대응 처리
- [ ] 크래시 로그 저장 (`~/Library/Logs/StockWatch/`)
- [ ] 자동 재시작 옵션 설정

### 3.2 자동 재연결

- [ ] WebSocket 재연결 Exponential Backoff (1s → 2s → 4s → ... → 60s)
- [ ] REST API 재시도 로직 통합
- [ ] 재연결 성공 시 상태 복구 (구독 목록 재등록)

### 3.3 macOS 로그인 시 자동 시작

- [ ] `SMLoginItemSetEnabled` 또는 `LaunchAgent` plist 방식 구현
- [ ] 설정 화면에 "로그인 시 자동 시작" 토글 추가

### 3.4 설정 백업/복원

- [ ] 설정 JSON 내보내기 (관심 종목, 포트폴리오, 알림 조건)
- [ ] JSON 파일로 설정 가져오기
- [ ] 백업 파일 형식 문서화

### 3.5 다크 모드 / 라이트 모드 대응

- [ ] 모든 SwiftUI View `colorScheme` 환경변수 대응 확인
- [ ] 커스텀 색상 Asset에 다크/라이트 변형 추가
- [ ] 시스템 설정 변경 시 실시간 반영 확인

### 3.6 알림 소리 및 UX 설정

- [ ] 알림 소리: macOS 시스템 사운드 선택 목록 제공
- [ ] 무음 옵션
- [ ] 알림 클릭 시 해당 종목 상세 페이지 오픈

### 3.7 온보딩 가이드

- [ ] 최초 실행 감지 (`UserDefaults` 플래그)
- [ ] 온보딩 화면: 계좌 연결 → 종목 추가 → 알림 설정 순서 안내
- [ ] 각 단계 설명 및 "건너뛰기" 옵션

### ✅ Phase 3 검증
- [ ] 네트워크 Wi-Fi 끄기 → 앱 경고 표시 → 재연결 시 정상 복구
- [ ] 로그인 시 자동 시작 설정 후 재부팅 → 자동 실행 확인
- [ ] 설정 내보내기 → 파일 생성 → 가져오기 → 데이터 복원 확인
- [ ] 다크 모드/라이트 모드 전환 시 UI 정상 렌더링
- [ ] 첫 실행 시 온보딩 화면 표시, 두 번째 실행 시 표시 안됨
- [ ] 알림 소리 변경 적용 확인

---

## Phase 4 — 멀티 브로커 확장

### 4.1 BrokerAdapter 프로토콜 정비

- [ ] `BrokerAdapter` 프로토콜 최종 확정 및 문서화
- [ ] `BrokerRegistry.swift` — 등록된 어댑터 관리
- [ ] KiwoomAdapter 리팩토링 (프로토콜 완전 준수)

### 4.2 한국투자증권(KIS) 어댑터

- [x] `KISAdapter.swift` — BrokerAdapter 구현 (Phase 1.5에서 구현 완료)
- [x] 토큰 발급, 현재가 조회 구현
- [x] Keychain에 KIS API 키 저장
- [ ] 포트폴리오 조회 구현 (`/uapi/domestic-stock/v1/trading/inquire-balance`)

### 4.3 계좌 연결 UI 개선

- [ ] 설정 탭 1: 계좌 연결 화면 개선
  - [ ] 브로커 선택 드롭다운 (키움 / KIS / 추가 예정)
  - [ ] 선택한 브로커에 맞는 API 키 입력 필드
  - [ ] "연결 테스트" 버튼 → 실시간 응답 확인

### 4.4 복수 계좌 동시 모니터링

- [ ] 복수 BrokerAdapter 인스턴스 관리
- [ ] 종목별로 어느 브로커 데이터를 사용할지 설정
- [ ] 포트폴리오 통합 집계 (복수 브로커 합산)

### ✅ Phase 4 검증
- [ ] KIS API 연결 → 현재가 조회 성공
- [ ] 키움 + KIS 동시 연결 → 각각의 종목 시세 정상 수신
- [ ] 두 브로커의 포트폴리오 합산 손익 정확성 확인
- [ ] 브로커 하나 연결 실패 시 나머지 정상 동작 확인

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

*각 Phase 검증 항목을 모두 체크한 후 다음 단계로 진행할 것.*
