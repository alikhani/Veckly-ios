import SwiftUI

enum VecklyDesign {
    enum Colors {
        static let hearthOrange = Color(red: 0.894, green: 0.341, blue: 0.180)
        static let canvas = Color(red: 0.969, green: 0.973, blue: 0.980)
        static let surface = Color.white
        static let surfaceStrong = Color(red: 0.933, green: 0.945, blue: 0.965)
        static let inkDeep = Color(red: 0.059, green: 0.090, blue: 0.165)
        static let inkMid = Color(red: 0.278, green: 0.333, blue: 0.412)
        static let inkFaint = Color(red: 0.392, green: 0.455, blue: 0.545)
        static let edgeLight = Color(red: 0.863, green: 0.890, blue: 0.929)
    }

    enum Spacing {
        static let small: CGFloat = 8
        static let medium: CGFloat = 14
        static let large: CGFloat = 20
    }
}

struct VecklyPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(VecklyDesign.Colors.hearthOrange.opacity(configuration.isPressed ? 0.86 : 1))
            .clipShape(Capsule())
    }
}

struct VecklyCard<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(VecklyDesign.Spacing.medium)
            .background(VecklyDesign.Colors.surface)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(VecklyDesign.Colors.edgeLight)
            }
    }
}
