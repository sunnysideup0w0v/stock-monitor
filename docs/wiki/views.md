# StockWatch — 뷰 용어 정의

> 이 문서는 StockWatch 앱의 주요 UI 구성 요소에 대한 공식 명칭과 역할을 정의한다.
> 코드 주석, PR 설명, 이슈 제목 등 모든 곳에서 이 용어를 일관되게 사용한다.

---

## 팝오버 (Popover)

**정의**: 메뉴바 아이콘을 클릭했을 때 아이콘 바로 아래에 나타나는 소형 패널.

**공식 명칭 근거**: macOS AppKit의 `NSPopover` 클래스를 그대로 사용하며, 코드 전체에서 `popover`, `MenuBarPopoverView`, `popoverWillShow` 등의 이름으로 일관되게 쓰인다.

**구현 파일**: `MenuBarPopoverView.swift`

**역할 및 구성**:
- 상단 헤더: 앱 이름 + 연결 상태 표시 (초록/빨간/회색 점)
- 관심종목 목록: 현재가 · 등락폭 · 등락률 실시간 표시
- 포트폴리오 요약: 총 평가손익 (원)
- 보유 종목 현재가: `showInPopover = true`인 포트폴리오 항목의 현재가 + 수익률
- 하단 바: 설정 열기 / 앱 종료

**표시 조건**: 팝오버는 클릭 외부 영역을 누르면 자동으로 닫힌다 (`NSEvent` 글로벌 이벤트 모니터).

**팝오버 포트폴리오 행 구성**:
- 좌측: 종목명 + (설정 시) 매입단가·현재단가·수량 보조 텍스트
- 우측: 현재 평가금액 (`price × quantity`) + 평가손익 (±원, 초록/빨강)
- 멀티 브로커 연결 시: `KIS ────` / `키움 ────` 소헤더로 브로커 구분

**팝오버 표시 설정** (`@AppStorage`로 영속):
- 관심종목 탭 → "팝오버 표시" → "종목코드·그룹 표시" 토글
- 포트폴리오 탭 → "팝오버 표시" → "매입단가·현재단가·수량 표시" 토글

---

## 설정 창 (Settings Window)

**정의**: 메뉴바 팝오버 하단 "설정" 버튼을 누르면 열리는 독립 창.

**구현 파일**: `SettingsView.swift`

**크기**: 720 × 600 pt (고정)

**탭 구성**:

| 탭 | 역할 |
|----|------|
| 계좌 연결 | KIS·키움 API 키 입력·로그인/로그아웃, DART·KRX·Claude AI 키 설정 |
| 관심종목 | 종목 추가 · 삭제 · 그룹 · 별칭 설정 |
| 포트폴리오 | 보유 종목 수동 입력 · 계좌에서 가져오기 · 팝오버 표시 선택 · 팝오버 부가정보 토글 · 스냅샷 수집 설정 |
| 알림설정 | 알림 조건 추가 · 장 시간 알림 제어 |
| 알림 이력 | 날짜/종류 필터 · CSV 내보내기 |
| 자산 차트 | 포트폴리오 평가액 시계열 그래프 (일·주·월·연) |
| 종목 추천 | 조건 스크리너 (ScreenerView) + Claude AI 분석 |

---

## 보유 종목 가져오기 시트 (Portfolio Import Sheet)

**정의**: 포트폴리오 탭에서 "계좌에서 가져오기" 버튼을 누르면 나타나는 모달 시트.

**구현 파일**: `SettingsView.swift` — `PortfolioImportSheetView`

**역할**: KIS 잔고조회 API로 가져온 보유 종목 미리보기 + 동기화 방식 선택 (신규 추가만 / 전체 교체).

---

## 종목 스크리너 (ScreenerView)

**정의**: 설정 창 "종목 추천" 탭. KRX/네이버에서 수집한 전종목 유니버스(`stock_universe`)를 조건으로 필터링하여 종목을 추천한다.

**구현 파일**: `ScreenerView.swift`

**구성**:
- **왼쪽 패널 (290pt)**: 조건 목록 카드 + 실행 버튼
  - 조건이 8개 초과 시 `ScrollView`로 스크롤
  - "조건 유지" 토글: 카드 바깥 하단 (`Screener.keepOnReopen` UserDefaults)
- **오른쪽 패널**: 스크리닝 결과 테이블 + AI 분석 버튼

**조건 타입 (`ScreenerCondition.ConditionType`)**:

| 타입 | 입력 방식 | 설명 |
|------|-----------|------|
| `priceRange` | 숫자 범위 | 현재가 (원) |
| `volumeMin` | 숫자 최솟값 | 최소 거래량 |
| `changeRateRange` | 숫자 범위 | 등락률 (%) |
| `perRange` | 숫자 범위 | PER (배) |
| `pbrRange` | 숫자 범위 | PBR (배) |
| `marketCapRange` | 숫자 범위 | 시가총액 (억원) |
| `marketFilter` | 체크박스 다중 | KOSPI / KOSDAQ |
| `sectorFilter` | 체크박스 다중 | 업종 (KRX API 키 필요) |
| `instrumentType` | 체크박스 다중 | 주식 / ETF |

**다중 선택 저장 방식**: `stringValue`에 콤마 구분 (`"KOSPI,KOSDAQ"`) → `ScreenerEngine.multiValues()` 로 파싱 → GRDB `Collection.contains(Column)` → `WHERE col IN (...)` SQL

**생명주기**:
- `onAppear`: `hasRun = false` 리셋 → `loadState()` → `cleanEmptyConditions()`
- `onDisappear`: `hasRun == true`면 빈 조건 제거 후 저장, `false`면 마지막 저장값으로 복원
- `runScreener()`: 빈 조건 정리 → `ScreenerEngine.run()` → `hasRun = true`

---

## AI 분석 시트 (AnalysisSheetView)

**정의**: 스크리너 결과에서 "AI 분석" 버튼 클릭 시 나타나는 모달 시트.

**구현 파일**: `ScreenerView.swift` 내 `AnalysisSheetView`

**상태별 UI**:
- 에러: 헤더 숨김 + 경고 아이콘 + 메시지 + 닫기 버튼 중앙 배치
- 분석 중(`isAnalyzing`): 로딩 스피너 + "AI가 종목을 분석하고 있습니다..."
- 완료: `Markdown(text).markdownTheme(.analysis)` 렌더링 + 복사 버튼

**MarkdownUI 커스텀 테마 (`.analysis`)**:
- `Theme.gitHub` 기반 (헤딩 스타일 상속)
- 기본 폰트 12.5pt, `**bold**` → 주황색, `> blockquote` → 파란 사이드바, `` `code` `` → 회색 배경
- 복사 피드백: 복사 후 2초간 체크마크/"복사됨"(초록) 표시

---

## 용어 대조표

| 화면에서 보이는 표현 | 코드 내 명칭 | 이 문서의 공식 명칭 |
|---------------------|-------------|-------------------|
| 메뉴바 아이콘 클릭 시 나타나는 창 | `NSPopover`, `MenuBarPopoverView` | **팝오버** |
| "설정" 버튼으로 여는 창 | `SettingsView`, `settingsWindow` | **설정 창** |
| "계좌에서 가져오기" 누르면 뜨는 창 | `PortfolioImportSheetView` | **보유 종목 가져오기 시트** |
