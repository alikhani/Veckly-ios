import SwiftUI

extension View {
    func skipDayConfirmation(
        isPresented: Binding<Bool>,
        onConfirm: @escaping () -> Void
    ) -> some View {
        modifier(SkipDayConfirmationModifier(isPresented: isPresented, onConfirm: onConfirm))
    }

    func removeDishConfirmation(
        isPresented: Binding<Bool>,
        onConfirm: @escaping () -> Void
    ) -> some View {
        modifier(RemoveDishConfirmationModifier(isPresented: isPresented, onConfirm: onConfirm))
    }
}

private struct SkipDayConfirmationModifier: ViewModifier {
    @Binding var isPresented: Bool
    let onConfirm: () -> Void

    func body(content: Content) -> some View {
        content.confirmationDialog(
            L10n.string("meal.skipConfirmation"),
            isPresented: $isPresented,
            titleVisibility: .visible
        ) {
            Button("meal.skip", role: .destructive, action: onConfirm)
            Button("common.cancel", role: .cancel) {}
        } message: {
            Text("meal.skipExplanation")
        }
    }
}

private struct RemoveDishConfirmationModifier: ViewModifier {
    @Binding var isPresented: Bool
    let onConfirm: () -> Void

    func body(content: Content) -> some View {
        content.confirmationDialog(
            L10n.string("meal.removeConfirmation"),
            isPresented: $isPresented,
            titleVisibility: .visible
        ) {
            Button("meal.clear", role: .destructive, action: onConfirm)
            Button("common.cancel", role: .cancel) {}
        } message: {
            Text("meal.removeExplanation")
        }
    }
}
