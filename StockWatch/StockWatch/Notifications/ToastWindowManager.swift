import AppKit
import SwiftUI

@Observable
private class ToastState {
    var appeared = false
}

@MainActor
final class ToastWindowManager {
    static let shared = ToastWindowManager()
    private var window: NSWindow?
    private var dismissTask: Task<Void, Never>?

    private init() {}

    func show(title: String, body: String) {
        dismissTask?.cancel()
        window?.orderOut(nil)
        window = nil

        guard let screen = NSScreen.main else { return }

        let width: CGFloat = 340
        let height: CGFloat = 88
        let margin: CGFloat = 12
        let x = screen.visibleFrame.maxX - width - margin
        let y = screen.visibleFrame.maxY - height - margin

        let state = ToastState()
        let hosting = NSHostingController(rootView: ToastView(title: title, message: body, state: state))

        let win = NSWindow(
            contentRect: NSRect(x: x, y: y, width: width, height: height),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        win.level = .floating
        win.isOpaque = false
        win.backgroundColor = .clear
        win.hasShadow = false
        win.ignoresMouseEvents = false
        win.contentViewController = hosting
        win.orderFrontRegardless()
        self.window = win

        dismissTask = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }

            // 오른쪽으로 슬라이드 아웃
            withAnimation(.spring(duration: 0.35)) {
                state.appeared = false
            }

            try? await Task.sleep(for: .milliseconds(380))
            guard !Task.isCancelled else { return }

            win.orderOut(nil)
            self.window = nil
        }
    }
}

private struct ToastView: View {
    let title: String
    let message: String
    let state: ToastState

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.blue)
                .frame(width: 36, height: 36)
                .background(Color(nsColor: .windowBackgroundColor).opacity(0.6), in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 3) {
                Text("STOCKWATCH")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .kerning(0.3)

                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(message)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(width: 340)
        .background {
            RoundedRectangle(cornerRadius: 14)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.18), radius: 16, x: 0, y: 6)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
        }
        .padding(8)
        .opacity(state.appeared ? 1 : 0)
        .offset(x: state.appeared ? 0 : 50)
        .onAppear {
            withAnimation(.spring(duration: 0.35, bounce: 0.2)) {
                state.appeared = true
            }
        }
    }
}
