import SwiftUI
import AppKit

extension View {
    func dismissFocusOnTap() -> some View {
        contentShape(Rectangle())
            .onTapGesture { NSApp.keyWindow?.makeFirstResponder(nil) }
    }
}

struct SettingsTabContainer<Content: View>: View {
    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.title2).bold()
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding([.horizontal, .bottom], 8)
        .dismissFocusOnTap()
    }
}

struct SettingsFormSection<Content: View>: View {
    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
            Text(title).font(.headline)
            content
        }
    }
}
