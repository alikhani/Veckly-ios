import SwiftUI

/// "Updates available": a calm note that fresher data has arrived, with one
/// button to bring it onto the screen. It is meant to be shown as an overlay —
/// it must never push the content the user is reading or tapping.
struct UpdateAvailableBanner: View {
    let onShow: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text(L10n.string("update.available.title"))
                .font(.subheadline)
                .foregroundStyle(VecklyDesign.Colors.inkDeep)
            Spacer(minLength: 8)
            Button(L10n.string("update.available.action"), action: onShow)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(VecklyDesign.Colors.hearthOrangeText)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
                .accessibilityIdentifier("updateAvailableShow")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 2)
        .background(VecklyDesign.Colors.surfaceStrong)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: .black.opacity(0.10), radius: 8, y: 2)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("updateAvailableBanner")
    }
}
