import SwiftUI
import UIKit

private extension Color {
    init(light: Color, dark: Color) {
        self.init(UIColor { $0.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light) })
    }
}

enum VecklyDesign {
    enum Colors {
        static let hearthOrange = Color(red: 0.894, green: 0.341, blue: 0.180)

        static let canvas = Color(
            light: Color(red: 0.969, green: 0.973, blue: 0.980),
            dark:  Color(red: 0.110, green: 0.118, blue: 0.141)
        )
        static let surface = Color(
            light: .white,
            dark:  Color(red: 0.161, green: 0.173, blue: 0.208)
        )
        static let surfaceStrong = Color(
            light: Color(red: 0.933, green: 0.945, blue: 0.965),
            dark:  Color(red: 0.200, green: 0.212, blue: 0.255)
        )
        static let inkDeep = Color(
            light: Color(red: 0.059, green: 0.090, blue: 0.165),
            dark:  Color(red: 0.929, green: 0.941, blue: 0.969)
        )
        static let inkMid = Color(
            light: Color(red: 0.278, green: 0.333, blue: 0.412),
            dark:  Color(red: 0.671, green: 0.718, blue: 0.792)
        )
        static let inkFaint = Color(
            light: Color(red: 0.392, green: 0.455, blue: 0.545),
            dark:  Color(red: 0.502, green: 0.565, blue: 0.643)
        )
        static let edgeLight = Color(
            light: Color(red: 0.863, green: 0.890, blue: 0.929),
            dark:  Color(red: 0.239, green: 0.259, blue: 0.318)
        )
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
