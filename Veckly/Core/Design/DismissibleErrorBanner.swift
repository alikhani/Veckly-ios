import SwiftUI

/// An inline error message with a dismiss button and, optionally, a
/// "Try again" action — the Week tab's mutation-error banners.
struct DismissibleErrorBanner: View {
    let message: String
    var retry: (() -> Void)? = nil
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Text(message)
                .font(.subheadline)
                .foregroundStyle(VecklyDesign.Colors.inkDeep)
            Spacer()
            if let retry {
                Button("common.tryAgain") {
                    retry()
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(VecklyDesign.Colors.hearthOrangeText)
            }
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(VecklyDesign.Colors.inkMid)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(L10n.string("common.dismissError"))
        }
        .padding(12)
        .background(VecklyDesign.Colors.surfaceStrong)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
