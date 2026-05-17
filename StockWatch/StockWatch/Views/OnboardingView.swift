import SwiftUI

struct OnboardingView: View {
    @Binding var isPresented: Bool
    @State private var step = 0

    private let steps: [(title: String, icon: String, description: String)] = [
        (
            title: "StockWatch에 오신 걸 환영합니다",
            icon: "chart.line.uptrend.xyaxis",
            description: "메뉴바에서 실시간으로 주식 시세를 확인하고,\n조건 충족 시 즉시 알림을 받을 수 있습니다."
        ),
        (
            title: "1단계: 계좌 연결",
            icon: "key.fill",
            description: "설정 → 계좌 연결 탭에서\n한국투자증권(KIS) API 키와 계좌번호를 입력하세요.\n\nKIS Developers(apiportal.koreainvestment.com)에서\nAPI 키를 발급받을 수 있습니다."
        ),
        (
            title: "2단계: 관심종목 추가",
            icon: "list.star",
            description: "설정 → 관심종목 탭에서\n모니터링할 종목 코드와 이름을 추가하세요.\n\n예) 005930 / 삼성전자"
        ),
        (
            title: "3단계: 알림 조건 설정",
            icon: "bell.badge",
            description: "설정 → 알림설정 탭에서\n목표가 도달, 손절가, 등락률, 거래량 급증 등\n다양한 조건으로 알림을 설정할 수 있습니다."
        ),
        (
            title: "준비 완료!",
            icon: "checkmark.circle.fill",
            description: "이제 메뉴바 아이콘을 클릭하면\n실시간 시세와 포트폴리오 손익을 확인할 수 있습니다.\n\n언제든지 설정에서 변경할 수 있습니다."
        )
    ]

    var body: some View {
        VStack(spacing: 0) {
            // 진행 표시
            HStack(spacing: 6) {
                ForEach(0..<steps.count, id: \.self) { i in
                    Capsule()
                        .fill(i <= step ? Color.accentColor : Color.secondary.opacity(0.3))
                        .frame(width: i == step ? 20 : 8, height: 6)
                        .animation(.spring(duration: 0.3), value: step)
                }
            }
            .padding(.top, 24)

            Spacer()

            // 아이콘
            Image(systemName: steps[step].icon)
                .font(.system(size: 56))
                .foregroundStyle(.blue)
                .padding(.bottom, 20)
                .animation(.spring(duration: 0.4), value: step)

            // 제목
            Text(steps[step].title)
                .font(.title2).bold()
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            // 설명
            Text(steps[step].description)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .padding(.horizontal, 32)
                .padding(.top, 12)

            Spacer()

            // 하단 버튼
            HStack {
                if step > 0 {
                    Button("이전") { step -= 1 }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("건너뛰기") { finish() }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .opacity(step < steps.count - 1 ? 1 : 0)
                    .disabled(step == steps.count - 1)

                if step < steps.count - 1 {
                    Button("다음") { step += 1 }
                        .buttonStyle(.borderedProminent)
                } else {
                    Button("시작하기") { finish() }
                        .buttonStyle(.borderedProminent)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .frame(width: 420, height: 360)
    }

    private func finish() {
        UserDefaults.standard.set(true, forKey: UserDefaultsKey.onboardingCompleted)
        isPresented = false
    }
}
