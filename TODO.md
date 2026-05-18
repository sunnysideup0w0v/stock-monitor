# StockWatch — 개발 진행 체크리스트

> 업데이트: 2026-05-19  
> Phase 0~5 완료 기준으로 재작성. 이후 개발 방향을 Phase 6~9로 구성.

---

## ✅ 완료된 Phase 요약

| Phase | 내용 | 테스트 |
|-------|------|--------|
| Phase 0 | 개발 환경, 프로젝트 셋업, GRDB 의존성 | — |
| Phase 1 | KIS REST API, 관심종목, 알림(목표가·등락률), 포트폴리오, 시세 폴링 | ✓ |
| Phase 2 | WebSocket 실시간 시세, 거래량·DART·포트폴리오 알림, 자산 차트, 스냅샷 | ✓ |
| Phase 3 | 에러 핸들링, 자동 재연결, 백업/복원, 다크 모드, 자동 시작, 온보딩 | ✓ |
| Phase 4 | 키움 REST API, 멀티 브로커 동시 연결, 계정 종속 데이터, 관심종목 USER 통합 | ✓ |
| Phase 5 | KRX 전종목 스크리너, Claude AI 분석, KRX OpenAPI 연동 | ✓ |

**현재 테스트 현황:** 197개 유닛 테스트 전체 통과 (2026-05-19)
- `AssetChartHelpersTests` (25개): fmtShort Y축 레이블 포맷터 + niceStep 단계 계산
- `SnapshotBackfillManagerTests` (7개): findGapDays 공백 탐지 로직

---

## Phase 6 — UX 고도화

> 현재 동작하는 기능들의 편의성·사용성을 개선한다. 새 API/DB 마이그레이션 없이 구현 가능한 항목 중심.

### 6.1 관심종목 드래그 재정렬

- [ ] `WatchlistSettingsView`에 `.onMove` 수정자 추가 — List 항목 드래그 순서 변경
- [ ] `WatchlistItem`에 `sortOrder: Int` 컬럼 추가 (Migration v14)
- [ ] `fetchWatchlist()` ORDER BY sortOrder
- [ ] 메뉴바 팝오버에도 동일 순서 적용

### 6.2 팝오버 관심종목 정렬

- [ ] 팝오버 헤더에 정렬 메뉴 추가 (기본순 / 등락률 높은 순 / 등락률 낮은 순 / 가나다순)
- [ ] 정렬 선택값 `UserDefaults`에 저장

### 6.3 알림 조건 복사

- [ ] `AlertSettingsView`에 조건 행 컨텍스트 메뉴 추가 → "복사"
- [ ] 복사 시 임계값·쿨다운 동일, id nil로 새 항목 삽입

### 6.4 관심종목 추가 시 stock_universe 자동완성

- [ ] `WatchlistSettingsView` 종목코드 입력 필드에 자동완성 드롭다운 추가
- [ ] `stock_universe` 테이블에서 symbol/name prefix 검색 (LIKE 쿼리)
- [ ] 자동완성 선택 시 name 자동 채움 (수동 입력 불필요)
- [ ] `stock_universe`가 비어있을 때는 자동완성 미표시, 수동 입력 유지

### 6.5 스크리너 조건 프리셋 저장

- [ ] 현재 조건 목록을 이름 붙여 저장 ("고PBR 성장주", "저PER 배당주" 등)
- [ ] `UserDefaults`에 `[String: [ScreenerCondition]]` 형태로 JSON 저장
- [ ] 스크리너 상단에 프리셋 선택 Picker 추가
- [ ] 현재 조건 "다른 이름으로 저장" / 프리셋 삭제

### 6.6 스크리너 결과 정렬 옵션

- [ ] 현재 시가총액 내림차순 고정 → 정렬 기준 선택 가능하게 변경
- [ ] 지원 정렬: 시가총액, 등락률, 거래량, PER, PBR, 현재가
- [ ] 오름차순 / 내림차순 토글

### 6.7 메뉴바 아이콘 수익률 표시

- [ ] 메뉴바 아이콘 옆 텍스트에 포트폴리오 당일 수익률 표시 (예: `+2.1%`)
- [ ] 수익률 색상 반영 (양수 = 녹색, 음수 = 적색 — NSStatusItem 타이틀 어트리뷰트)
- [ ] 계좌 미연결 or 포트폴리오 없으면 텍스트 숨김
- [ ] 설정 탭에서 표시 여부 토글 (`UserDefaults`)

### ✅ Phase 6 검증
- [ ] 관심종목 순서 변경 → 팝오버에도 동일 순서로 반영
- [ ] 자동완성 드롭다운: 삼성(005930) 입력 시 후보 목록 표시
- [ ] 스크리너 프리셋 저장 후 앱 재시작 → 프리셋 목록 유지
- [ ] 메뉴바 아이콘에 수익률 텍스트 표시 및 색상 변경 확인

---

## Phase 7 — 알림 & 스크리너 고도화

### 7.1 알림 이력 숨기기 해제 (복원)

- [ ] `AlertHistoryView` 숨긴 항목 보기 토글 추가
- [ ] `DatabaseManager`에 `fetchAllAlertHistory(limit:)` 추가 (isHidden 관계없이 전체)
- [ ] 숨긴 항목 행에 "복원" 버튼 추가 → `UPDATE isHidden = 0`
- [ ] `DatabaseManager.unhideAlertHistory(id:)` 메서드 추가

### 7.2 알림 무음 시간대 (Quiet Hours)

- [ ] 알림설정 탭에 "무음 시간대" 섹션 추가
- [ ] 시작 시각 / 종료 시각 입력 (TimePicker)
- [ ] `AlertEvaluator.evaluate()` 및 `DARTManager` 발화 전 무음 시간대 체크
- [ ] `UserDefaults`에 저장 (`alertQuietHoursEnabled`, `alertQuietStart`, `alertQuietEnd`)

### 7.3 키움 거래량 스파이크 지원

- [ ] `KiwoomAdapter.fetchDailyVolumes()` 실구현 — 일별시세 TR 코드 확인 후 구현
  - 키움 `/api/dostk/chart` 또는 해당 TR API 호출
  - 응답 파싱 → `[Int]` (최근 `days`일 거래량)
- [ ] `QuoteManager.avgVolumes` 키움 연결 시에도 정상 채워지는지 확인
- [ ] 거래량 스파이크 알림 키움 연결 시 정상 발화 검증

### 7.4 스크리너 조건 타입 확장

- [ ] `ConditionType` 에 `roeRange` (ROE %) 추가
  - `stock_universe`에 `roe` 컬럼 추가 (Migration v14 또는 v15)
  - KRX OpenAPI / 네이버 응답에서 ROE 파싱
- [ ] `dividendYield` (배당수익률 %) 조건 추가 (같은 마이그레이션)
- [ ] `ScreenerEngine.apply()` 새 케이스 추가
- [ ] `ClaudeAnalyzer.describeCondition()` 새 케이스 설명 추가

### 7.5 스크리너 결과에 실시간 시세 보강

- [ ] 스크리너 결과 종목들을 `QuoteManager`에 일시 등록 → 실시간 등락률 갱신
- [ ] 결과 리스트 행에 현재가 / 등락률 컬럼 추가 (KRX 정적 데이터 대비)
- [ ] 결과 탭 닫힐 때 임시 등록 해제 (폴링 목록 복원)

### 7.6 알림 조건 일괄 관리

- [ ] `AlertSettingsView`에 전체 선택/해제 토글 추가
- [ ] 선택한 조건 일괄 활성화 / 일괄 비활성화 / 일괄 삭제
- [ ] 조건 목록 종목별 그룹핑 섹션 헤더 표시

### ✅ Phase 7 검증
- [ ] 무음 시간대 설정 → 해당 시간대에 조건 충족해도 알림 미발송
- [ ] 키움 연결 상태에서 거래량 급증 알림 발화 확인
- [ ] ROE 조건으로 스크리닝 결과 정상 필터링
- [ ] 스크리너 결과 행 등락률 실시간 갱신 확인

---

## Phase 8 — 포트폴리오 & 차트 고도화

### 8.1 스냅샷 수집 주기 설정

- [ ] `SnapshotSettingsSection`에 수집 주기 Picker 추가 (1분 / 5분 / 10분 / 30분)
- [ ] `SnapshotManager`에 `intervalMinutes: Int` 프로퍼티 추가
- [ ] `UserDefaults` 키 `snapshotIntervalMinutes` 저장
- [ ] 타이머 interval 동적 변경 지원

### 8.2 종목별 개별 자산 추이 차트

- [ ] `portfolio_snapshots` 테이블에 종목별 스냅샷 저장 방식 결계
  - 옵션 A: 현재 테이블에 `symbol` 컬럼 추가 (NULL = 전체 포트폴리오)
  - 옵션 B: 별도 `portfolio_item_snapshots` 테이블
- [ ] `AssetChartView`에 종목 선택 Picker 추가 (전체 / 개별 종목)
- [ ] 선택 종목의 평가금액 추이 차트 표시

### 8.3 포트폴리오 구성 비율 차트

- [ ] `PortfolioSettingsView` 또는 별도 탭에 파이/도넛 차트 추가
- [ ] 종목별 평가금액 비율 시각화 (Swift Charts `SectorMark`)
- [ ] 시가총액·평균 매입가 대비 현재가 막대 차트

### 8.4 자산 차트 기간 비교선

- [ ] 차트에 비교 기준 시점 선택 기능 추가 (특정 날짜 클릭 → 해당 일 값을 baseline으로)
- [ ] 현재 "기간 시작점 = baseline" 외에 사용자 지정 baseline 지원
- [ ] 기준선 레이블에 실제 금액/날짜 표시

### ✅ Phase 8 검증
- [ ] 5분 주기로 변경 후 5분 간격으로 스냅샷 저장되는지 확인
- [ ] 종목 선택 → 해당 종목 평가금액 추이 차트 정상 표시
- [ ] 파이 차트에서 각 종목 비율 합산 100% 확인

---

## Phase 9 — 인프라 & 보안 강화

### 9.1 DB 암호화 (SQLCipher)

- [ ] `project.yml`에 SQLCipher 패키지 추가 (`GRDB/SQLCipher` 또는 `sqlcipher/sqlcipher`)
- [ ] `DatabaseManager.setup()`: `var config = Configuration(); config.passphrase = ...`
- [ ] 암호화 키 macOS Keychain에 저장 (`KeychainKey.dbPassphrase`)
- [ ] 기존 평문 DB → 암호화 DB 마이그레이션 로직 작성 (SQLCipher `ATTACH` / `sqlcipher_export`)
- [ ] 암호화 활성화 토글 (설정 탭, 기본값 OFF)

### 9.2 백업 범위 확장

- [ ] `BackupManager.export()` 에 알림 이력(`alertHistory`) 포함 옵션 추가
- [ ] 내보내기 시 포함 항목 체크박스 UI (관심종목 / 포트폴리오 / 알림조건 / 알림이력)
- [ ] 복원 시 알림 이력 중복 처리 (triggeredAt + symbol 기준)

### 9.3 인앱 로그 뷰어

- [ ] 설정 창에 "개발자 로그" 탭 또는 시트 추가 (Debug 빌드 전용)
- [ ] `~/Library/Logs/StockWatch/app-*.log` 최근 N줄 읽어 표시
- [ ] 카테고리 필터 (Screener / Alert / DART / KRX / KIS / Kiwoom)
- [ ] 로그 복사 버튼

### 9.4 미래에셋 어댑터 구현

> `MiraeAssetAdapter.swift` 현재 stub — 공식 포털 확인 후 구현.

- [ ] 미래에셋 Open API 포털에서 서비스별 신청 및 키 발급
- [ ] `MiraeAssetAdapter`: OAuth 토큰 발급, 현재가 조회, 잔고조회 실구현
- [ ] `BrokerSessionManager.loginMiraeAsset()` / `logoutMiraeAsset()` 추가
- [ ] `AccountSettingsView` 미래에셋 연결 폼 활성화 ("준비 중" 제거)
- [ ] `KeychainKey`: `miraeAppKey`, `miraeAppSecret`, `miraeAccountNumber` 추가
- [ ] DB Migration: `accountId = "MIRAE-" + appKey.prefix(8)` 패턴 적용

### 9.5 키움 WebSocket 실시간 시세

- [ ] `KiwoomAdapter` WebSocket 연결 구현 (`wss://api.kiwoom.com:10000`)
- [ ] 구독 타입 `0B` (주식체결) 메시지 파싱 → `StockQuote` 변환
- [ ] `RealtimeQuoteManager`에 키움 WebSocket 경로 추가 (KIS와 분리 또는 통합)
- [ ] 키움 연결 시 WebSocket 자동 활성화

### ✅ Phase 9 검증
- [ ] DB 암호화 ON → 앱 재시작 후 데이터 정상 로드
- [ ] 암호화된 DB 파일을 DB 브라우저로 직접 열기 시도 → 실패 확인
- [ ] 미래에셋 연결 → 현재가 조회 및 잔고조회 성공
- [ ] 키움 WebSocket 연결 → 실시간 시세 수신 확인

---

## 상시 관리 항목

### 테스트

- [ ] Phase 6~9 구현 시마다 관련 유닛 테스트 추가
- [ ] `DatabaseManagerCRUDTests` — Migration v14+ 추가 시 새 마이그레이션 테스트 추가
- [ ] 현재 테스트 커버리지: 165개 통과 (2026-05-18 기준)

### DB 마이그레이션 로드맵

| 버전 | 내용 | Phase |
|------|------|-------|
| v14 | `watchlist.sortOrder` 컬럼 추가 | 6.1 |
| v15 | `stock_universe.roe`, `dividendYield` 컬럼 추가 | 7.4 |
| v16 | 스냅샷 종목별 컬럼 추가 (8.2 설계 결정 후) | 8.2 |

> 다음 마이그레이션은 v14부터. 기존 Migration은 절대 수정 금지.

### 보안 체크리스트

- [x] API 키 → macOS Keychain 저장
- [x] 네트워크 통신 TLS 1.2+ 강제
- [ ] 로컬 DB 암호화 (Phase 9.1)

---

*Phase 완료 시 버전 규칙: Phase 6 완료 → `1.6.0`, Phase 7 → `1.7.0` ...*  
*각 Phase 검증 항목을 모두 체크한 후 다음 단계로 이동.*
