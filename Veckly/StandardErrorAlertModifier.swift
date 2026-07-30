import SwiftUI

extension View {
    func standardErrorAlert(message: Binding<String?>) -> some View {
        modifier(StandardErrorAlertModifier(message: message))
    }
}

private struct StandardErrorAlertModifier: ViewModifier {
    @Binding var message: String?

    func body(content: Content) -> some View {
        content.alert(
            L10n.string("common.error"),
            isPresented: Binding(
                get: { message != nil },
                set: { if !$0 { message = nil } }
            )
        ) {
            Button("common.ok") { message = nil }
        } message: {
            Text(message ?? "")
        }
    }
}
