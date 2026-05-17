#!/usr/bin/env bash
# StockWatch 빌드 & 설치 스크립트
# 사용법: bash setup.sh

set -euo pipefail

# ──────────────────────────────────────────────
# 색상 출력 헬퍼
# ──────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

info()    { echo -e "${CYAN}[INFO]${RESET}  $*"; }
success() { echo -e "${GREEN}[OK]${RESET}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
error()   { echo -e "${RED}[ERROR]${RESET} $*" >&2; }
header()  { echo -e "\n${BOLD}$*${RESET}"; }

# ──────────────────────────────────────────────
# 1. macOS 버전 확인 (14.0 Sonoma 이상 필요)
# ──────────────────────────────────────────────
header "1/5  macOS 버전 확인"

MACOS_MAJOR=$(sw_vers -productVersion | cut -d. -f1)
MACOS_MINOR=$(sw_vers -productVersion | cut -d. -f2)

if [ "$MACOS_MAJOR" -lt 14 ]; then
  error "macOS 14.0 (Sonoma) 이상이 필요합니다. 현재: $(sw_vers -productVersion)"
  exit 1
fi
success "macOS $(sw_vers -productVersion)"

# ──────────────────────────────────────────────
# 2. Xcode 설치 확인
#    SwiftUI + AppKit 빌드에는 전체 Xcode가 필요합니다.
#    Command Line Tools만으로는 macOS SDK가 불완전합니다.
# ──────────────────────────────────────────────
header "2/5  Xcode 확인"

XCODE_PATH=$(xcode-select -p 2>/dev/null || true)

# /Library/Developer/CommandLineTools 가 아닌 Xcode.app 경로여야 함
if [[ "$XCODE_PATH" != *"Xcode"* ]] || ! command -v xcodebuild &>/dev/null; then
  error "Xcode가 설치되어 있지 않거나 활성화되지 않았습니다."
  echo
  echo "  1) App Store에서 Xcode를 설치하세요:"
  echo "     https://apps.apple.com/app/xcode/id497799835"
  echo
  echo "  2) 설치 후 아래 명령으로 활성화하세요:"
  echo "     sudo xcode-select -s /Applications/Xcode.app/Contents/Developer"
  echo
  echo "  3) 라이선스 동의:"
  echo "     sudo xcodebuild -license accept"
  echo
  exit 1
fi

XCODE_VERSION=$(xcodebuild -version 2>/dev/null | head -1)
success "$XCODE_VERSION  ($XCODE_PATH)"

# ──────────────────────────────────────────────
# 3. Homebrew + xcodegen 설치
# ──────────────────────────────────────────────
header "3/5  Homebrew / xcodegen 확인"

if ! command -v brew &>/dev/null; then
  info "Homebrew를 설치합니다..."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

  # Apple Silicon의 경우 PATH 추가
  if [[ "$(uname -m)" == "arm64" ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  fi
fi
success "Homebrew $(brew --version | head -1)"

if ! command -v xcodegen &>/dev/null; then
  info "xcodegen을 설치합니다..."
  brew install xcodegen
fi
success "xcodegen $(xcodegen --version 2>/dev/null || echo '설치됨')"

# ──────────────────────────────────────────────
# 4. 프로젝트 생성 & 빌드
# ──────────────────────────────────────────────
header "4/5  프로젝트 빌드"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$SCRIPT_DIR/StockWatch"

if [ ! -f "$PROJECT_DIR/project.yml" ]; then
  error "project.yml을 찾을 수 없습니다: $PROJECT_DIR/project.yml"
  error "이 스크립트는 저장소 루트에서 실행해야 합니다."
  exit 1
fi

cd "$PROJECT_DIR"

info "xcodegen generate..."
xcodegen generate --quiet

info "빌드 중... (첫 빌드는 수 분이 걸릴 수 있습니다)"
xcodebuild -scheme StockWatch \
           -configuration Release \
           build \
           CODE_SIGNING_ALLOWED=NO \
           -quiet 2>&1 | grep -E "(error:|warning: 'StockWatch'|BUILD)" || true

# 빌드 결과 경로 추출
BUILT_PRODUCTS_DIR=$(xcodebuild -scheme StockWatch \
  -configuration Release \
  -showBuildSettings CODE_SIGNING_ALLOWED=NO 2>/dev/null \
  | grep " BUILT_PRODUCTS_DIR " | awk '{print $3}')

APP_PATH="$BUILT_PRODUCTS_DIR/StockWatch.app"

if [ ! -d "$APP_PATH" ]; then
  error "빌드 결과물을 찾을 수 없습니다: $APP_PATH"
  error "위 빌드 로그를 확인하세요."
  exit 1
fi
success "빌드 완료: $APP_PATH"

# ──────────────────────────────────────────────
# 5. Applications 폴더에 설치
# ──────────────────────────────────────────────
header "5/5  설치"

DEST="/Applications/StockWatch.app"

if [ -d "$DEST" ]; then
  warn "기존 설치본을 덮어씁니다: $DEST"
  rm -rf "$DEST"
fi

cp -R "$APP_PATH" "$DEST"
success "설치 완료: $DEST"

# Gatekeeper quarantine 해제 (서명 없는 앱 실행 허용)
xattr -cr "$DEST" 2>/dev/null || true

# ──────────────────────────────────────────────
# 완료 안내
# ──────────────────────────────────────────────
echo
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo -e "${BOLD}  StockWatch 설치가 완료되었습니다!${RESET}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo
echo "  실행 방법:"
echo "    • Launchpad 또는 Spotlight에서 'StockWatch' 검색"
echo "    • 또는: open /Applications/StockWatch.app"
echo
echo "  첫 실행 후 메뉴바 아이콘 → 설정(⚙) → 계좌 연결 탭에서"
echo "  아래 API 키를 입력하세요:"
echo
echo "  ┌─ 필수 ────────────────────────────────────────────┐"
echo "  │  한국투자증권 KIS Developers                      │"
echo "  │  https://apiportal.koreainvestment.com            │"
echo "  │  → App Key / App Secret / 계좌번호 입력           │"
echo "  └────────────────────────────────────────────────────┘"
echo
echo "  ┌─ 선택 ────────────────────────────────────────────┐"
echo "  │  DART 공시 알림:  https://opendart.fss.or.kr      │"
echo "  │  KRX 시장 데이터: https://openapi.krx.co.kr       │"
echo "  │  AI 종목 분석:    https://console.anthropic.com   │"
echo "  └────────────────────────────────────────────────────┘"
echo
open "$DEST" 2>/dev/null || true
