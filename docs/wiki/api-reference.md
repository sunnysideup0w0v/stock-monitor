# StockWatch — 외부 API 레퍼런스

> 연동된 외부 API와 실구현 상의 주의사항을 정리한다.

---

## 한국투자증권 (KIS) REST API

### Base URL

| 환경 | Base URL |
|------|----------|
| 실전투자 | `https://openapi.koreainvestment.com:9443` |
| 모의투자 | `https://openapivts.koreainvestment.com:29443` |

### 토큰 발급

```
POST /oauth2/tokenP
Content-Type: application/json

{
  "grant_type": "client_credentials",
  "appkey": "...",
  "appsecret": "..."
}
```

- 유효기간: 24시간
- 만료 5분 전 자동 갱신 (KISAdapter 내부 처리)
- 403 오류: 발급 직후 일시적으로 발생할 수 있음 — 잠시 후 재시도로 해결된 사례 있음

### 현재가 조회

```
GET /uapi/domestic-stock/v1/quotations/inquire-price
tr_id: FHKST01010100 (실전) / VHKST01010100 (모의)
custtype: P
FID_COND_MRKT_DIV_CODE: J
FID_INPUT_ISCD: {종목코드}
```

**주의사항**:
- `prdy_vrss_sign` 부호 코드: `2`=상승, `3`=보합, `4`=하락 — 등락폭 앞에 수동으로 부호 붙여야 함
- 장 시간 외에는 일부 필드가 생략되거나 빈 문자열로 옴 → 모든 응답 필드는 `String?`으로 옵셔널 파싱

### 잔고조회 (보유 종목)

```
GET /uapi/domestic-stock/v1/trading/inquire-balance
tr_id: TTTC8434R (실전) / VTTC8434R (모의)
CANO: {계좌번호 앞 8자리}
ACNT_PRDT_CD: {계좌번호 뒤 2자리}
AFHR_FLPR_YN: N
OFL_YN: ""
INQR_DVSN: 02
UNPR_DVSN: 01
FUND_STTL_ICLD_YN: N
FNCG_AMT_AUTO_RDPT_YN: N
PRCS_DVSN: 01
CTX_AREA_FK100: ""
CTX_AREA_NK100: ""
```

계좌번호 파싱: 사용자 입력 `"50123456-01"` → `-` 제거 → `CANO = "50123456"`, `ACNT_PRDT_CD = "01"`. 10자리 미만이면 `ACNT_PRDT_CD = "01"` 기본값.

응답 `output1` 배열에서 `hldg_qty > 0`인 항목만 사용. `pchs_avg_pric`은 소수점 포함 문자열(`"85200.00"`) → `Double` → `Int` 변환.

### WebSocket 실시간 시세

| 환경 | WebSocket URL |
|------|--------------|
| 실전투자 | `ws://ops.koreainvestment.com:21000` |
| 모의투자 | `ws://ops.koreainvestment.com:31000` |

비TLS(`ws://`) 사용 → `Info.plist` ATS 예외 도메인 추가 필요.

**승인키 발급**: `POST /oauth2/Approval` — REST 토큰과 별개. 필드명 `secretkey` (REST는 `appsecret`)에 주의.

**구독 메시지**:
```json
{
  "header": { "approval_key": "...", "custtype": "P", "tr_type": "1", "content-type": "utf-8" },
  "body": { "input": { "tr_id": "H0STCNT0", "tr_key": "005930" } }
}
```
`tr_type: "1"` = 구독, `"2"` = 해제.

**수신 메시지 파싱**:
```
{encrypt}|{tr_id}|{count}|{field1}^{field2}^...
```

| 인덱스 | 필드 |
|--------|------|
| [0] | 종목코드 |
| [2] | 현재가 |
| [3] | 부호 (`"2"`=상승, `"4"`=하락) |
| [4] | 전일대비 변동폭 |
| [5] | 등락률 |
| [13] | 거래량 |

암호화 메시지(`parts[0] == "1"`)는 현재 처리하지 않고 스킵.

---

## 키움증권 REST API

### Base URL

`https://api.kiwoom.com`

### 토큰 발급

```
POST /oauth2/token
Content-Type: application/json

{
  "grant_type": "client_credentials",
  "appkey": "...",
  "secretkey": "..."
}
```

- 응답 `token_type`이 `"bearer"`(소문자)임에 주의 — 대소문자 비교 시 소문자로 통일
- Authorization 헤더: `Bearer {access_token}`

### 현재가 조회

```
POST /api/dostk/quot
Content-Type: application/json
Authorization: Bearer {token}
appkey: {appKey}
tr_cd: STCA

{
  "stk_cd": "005930"
}
```

응답 필드 (플랫 구조, `output` 중첩 없음):

| 필드 | 내용 |
|------|------|
| `stck_prpr` | 현재가 |
| `prdy_vrss` | 전일대비 |
| `prdy_ctrt` | 등락률 |
| `acml_vol` | 누적거래량 |
| `prdy_vrss_sign` | 부호 코드 (KIS와 동일: `2`=상승, `3`=보합, `4`=하락) |

### 잔고조회 (보유 종목)

```
POST /api/dostk/acnt
tr_cd: kt00018

{
  "accn_no": "1234567890",   // 계좌번호 (- 제거, 10자리)
  "prdt_cd": "01"            // 상품코드 (계좌번호 뒤 2자리 또는 기본 "01")
}
```

---

## DART Open API

### Base URL

`https://opendart.fss.or.kr`

### corp_code 조회

```
GET /api/corpCode.xml
crtfc_key: {dart.apiKey}
```

ZIP 파일 응답 → 압축 해제 후 XML 파싱. `stock_code` 필드로 종목코드 매핑. 결과는 인메모리 캐싱.

### 공시 목록 조회

```
GET /api/list.json
crtfc_key: {dart.apiKey}
corp_code: {corp_code}
bgn_de: {YYYYMMDD}    // 오늘 날짜
page_count: 10
```

- 5분마다 폴링
- `rcept_no` 기준 중복 제거 (`UserDefaults "DART.seenRceptNos"` 집합)
- `UserDefaults "DART.filterTypes"`: 공시 종류 코드 필터 (빈 배열 = 전체)

**공시 종류 코드**:

| 코드 | 종류 |
|------|------|
| A | 정기공시 |
| B | 주요사항 |
| C | 발행공시 |
| D | 지분공시 |
| E | 기타공시 |
| I | 거래소공시 |

**공시 상세 URL**: `https://dart.fss.or.kr/dsaf001/main.do?rcpNo={rcept_no}`

---

## Keychain 저장 키

| account 키 | 내용 |
|-----------|------|
| `kis.appKey` | KIS App Key |
| `kis.appSecret` | KIS App Secret |
| `kis.accountNumber` | KIS 계좌번호 |
| `kiwoom.appKey` | 키움 App Key |
| `kiwoom.appSecret` | 키움 App Secret |
| `kiwoom.accountNumber` | 키움 계좌번호 |
| `dart.apiKey` | DART Open API 키 |

## UserDefaults 키

| 키 | 타입 | 기본값 | 내용 |
|----|------|--------|------|
| `KIS.isMock` | Bool | false | 모의투자 모드 |
| `KIS.loginDate` | Date | — | KIS 로그인 시각 |
| `Kiwoom.loginDate` | Date | — | 키움 로그인 시각 |
| `DART.filterTypes` | [String] | [] | 공시 종류 필터 (빈 배열 = 전체) |
| `DART.seenRceptNos` | [String] | [] | 이미 알림 발송한 공시 번호 |
| `QuoteManager.disconnectAlert` | Bool | true | 단절/복구 알림 발송 여부 |
| `AlertEvaluator.marketHoursOnly` | Bool | true | 장 시간(09~15:30)에만 알림 |
| `SnapshotManager.marketHoursOnly` | Bool | true | 장 시간에만 스냅샷 수집 |
| `SnapshotManager.customRanges` | Data (JSON) | [] | 추가 수집 시간대 |
| `SnapshotManager.keepDays` | Int | 0 | 스냅샷 보존 기간 (0 = 365일) |
| `Popover.showWatchlistDetail` | Bool | false | 팝오버 관심종목 종목코드·그룹 표시 |
| `Popover.showPortfolioDetail` | Bool | false | 팝오버 포트폴리오 매입/현재/수량 표시 |
| `Onboarding.completed` | Bool | false | 온보딩 완료 여부 |
| `DB.v8AccountIdMigrated` | Bool | false | v8 accountId 마이그레이션 완료 여부 |
