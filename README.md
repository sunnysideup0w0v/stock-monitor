# StockWatch

macOS 메뉴바 상주형 한국 주식 시세 모니터링 앱.  
한국투자증권(KIS) / 키움증권 API로 실시간 시세를 수신하고, 목표가·손절가·공시 등 다양한 조건에서 macOS 알림을 발송합니다.

> **개인 사용 목적으로 제작된 앱입니다.**  
> App Store 배포 및 공식 지원은 하지 않습니다.

---

## 요구 사항

| 항목 | 버전 |
|------|------|
| macOS | 14.0 (Sonoma) 이상 |
| Xcode | 15.0 이상 (App Store에서 무료 설치) |
| xcodegen | 자동 설치됨 |

---

## 설치 방법

### 1단계 — Xcode 설치

App Store에서 **Xcode**를 설치합니다.  
설치 후 터미널에서 한 번 실행하거나 아래 명령으로 활성화하세요.

```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
sudo xcodebuild -license accept
```

### 2단계 — 저장소 클론

```bash
git clone https://github.com/sunnysideup0w0v/stock-monitor.git
cd stock-monitor
```

### 3단계 — 빌드 & 설치

```bash
bash setup.sh
```

스크립트가 자동으로 다음을 처리합니다:

1. macOS 버전 확인 (14.0+)
2. Xcode 활성화 확인
3. Homebrew 미설치 시 자동 설치
4. xcodegen 미설치 시 자동 설치
5. 프로젝트 빌드 (Release)
6. `/Applications/StockWatch.app` 에 설치 및 실행

---

## 첫 실행 — API 키 설정

메뉴바 아이콘 → **설정 (⚙)** → **계좌 연결** 탭에서 키를 입력합니다.

### 필수

**한국투자증권 KIS Developers**  
<https://apiportal.koreainvestment.com>

1. 회원가입 후 앱 등록
2. App Key / App Secret 발급
3. 계좌번호 입력 (모의투자 계정도 지원)

### 선택

| 기능 | 발급처 |
|------|--------|
| DART 공시 알림 | <https://opendart.fss.or.kr> |
| KRX 시장 데이터 (PER/PBR·업종) | <https://openapi.krx.co.kr> |
| AI 종목 분석 (Claude) | <https://console.anthropic.com> |

---

## 주요 기능

- **실시간 시세** — KIS WebSocket / 3초 폴링 자동 전환
- **관심종목 관리** — 그룹별 분류, 메뉴바 팝오버 표시
- **포트폴리오** — 평균단가·수량 입력, 계좌 자동 가져오기, 수익률 실시간 계산
- **알림 조건** — 목표가, 손절가, 등락률, 거래량 급등, 포트폴리오 손익, DART 공시
- **알림 이력** — 날짜·종목·유형 필터, CSV 내보내기
- **자산 차트** — 일/주/월/연 포트폴리오 평가액 추이 (Swift Charts)
- **종목 스크리너** — 시가총액·PER·PBR·등락률 등 다중 조건, Claude AI 분석
- **로그인 시 자동 시작** 지원

---

## 업데이트

새 버전이 나오면 저장소를 pull하고 `setup.sh`를 다시 실행합니다.

```bash
git pull
bash setup.sh
```

---

## 직접 빌드하고 싶다면

```bash
cd StockWatch
xcodegen generate
xcodebuild -scheme StockWatch -configuration Debug build CODE_SIGNING_ALLOWED=NO
```

빌드 결과물 경로 확인:

```bash
xcodebuild -scheme StockWatch -configuration Debug \
  -showBuildSettings CODE_SIGNING_ALLOWED=NO 2>/dev/null \
  | grep " BUILT_PRODUCTS_DIR "
```

---

## 알려진 제한 사항

- **Gatekeeper**: App Store 배포 앱이 아니므로 처음 실행 시 "개발자를 확인할 수 없음" 경고가 뜰 수 있습니다. `setup.sh`가 자동으로 quarantine 속성을 제거합니다. 직접 설치한 경우 `xattr -cr /Applications/StockWatch.app` 를 실행하거나 Finder에서 오른쪽 클릭 → 열기를 선택하세요.
- **KIS API 사용 시간**: 장 시간(09:00~15:30) 외에는 일부 필드가 생략되어 시세가 표시되지 않을 수 있습니다.
- **모의투자**: KIS 모의투자 계정은 실전과 동일하게 지원됩니다.
