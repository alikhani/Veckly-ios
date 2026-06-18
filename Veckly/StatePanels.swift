import SwiftUI

struct LoadingPanel: View {
    let title: String

    var body: some View {
        VecklyCard {
            HStack(spacing: 12) {
                ProgressView()
                    .tint(VecklyDesign.Colors.hearthOrange)
                Text(title)
                    .foregroundStyle(VecklyDesign.Colors.inkMid)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct ErrorPanel: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        VecklyCard {
            VStack(alignment: .leading, spacing: 12) {
                Text(message)
                    .foregroundStyle(.red)
                Button("common.tryAgain", action: retry)
                    .buttonStyle(VecklyPrimaryButtonStyle())
            }
        }
    }
}

struct EmptyPanel: View {
    let title: String
    let message: String

    var body: some View {
        VecklyCard {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.headline)
                Text(message)
                    .foregroundStyle(VecklyDesign.Colors.inkMid)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
