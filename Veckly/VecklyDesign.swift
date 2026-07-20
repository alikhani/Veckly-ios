import SwiftUI
import UIKit

private extension Color {
    init(light: Color, dark: Color) {
        self.init(UIColor { $0.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light) })
    }
}

enum VecklyDesign {
    enum Colors {
        // MARK: - Hearth Orange (Fas 8: fill vs. text split)
        //
        // The single flat `hearthOrange` used indiscriminately for fills,
        // icons, tints, AND small foreground text. Verified against WCAG 2.1
        // AA (4.5:1 for normal text, 3:1 for large text/non-text graphics):
        //   - vs. light canvas (0.969/0.973/0.980): 3.47:1
        //   - vs. white surface:                     3.69:1
        //   - vs. dark canvas (0.110/0.118/0.141):    4.53:1 (barely passes)
        //   - vs. dark surface (0.161/0.173/0.208):   3.79:1 (fails)
        // It clears the 3:1 non-text/large-text bar everywhere, but fails
        // AA normal-text contrast in every case except (barely) dark canvas.
        // Split into three tokens below; see each token's doc comment for
        // its verified numbers.

        /// Large text, icons, tab tints, and non-text fills — the original
        /// brand orange, unchanged, in both light and dark mode. Only needs
        /// to clear 3:1 (large text / non-text graphics), which it does
        /// against every surface in this file. Never pair with small
        /// foreground text or use as a button fill under white text — see
        /// `hearthOrangeText` and `hearthOrangePrimaryFill`.
        static let hearthOrangeFill = Color(red: 0.894, green: 0.341, blue: 0.180)

        /// Small foreground text on a light canvas/surface. Same hue family
        /// as `hearthOrangeFill` but darker — this is DESIGN.md's existing
        /// `hearth-orange-active` (#b94322), not a new invented color.
        /// Verified: 5.09:1 vs. light canvas, 5.40:1 vs. white surface.
        static let hearthOrangeTextLight = Color(red: 0.7255, green: 0.2627, blue: 0.1333)

        /// Small foreground text on a dark canvas/surface. DESIGN.md's
        /// existing `hearth-orange-dark` (#ff6b45) — the dark-mode variant
        /// the design system already defines for exactly this reason
        /// (`hearthOrangeFill` only reaches 4.53:1 against dark canvas and
        /// 3.79:1 against dark surface, i.e. it fails on cards). Verified:
        /// 5.90:1 vs. dark canvas, 4.93:1 vs. dark surface.
        static let hearthOrangeTextDark = Color(red: 1.0, green: 0.4196, blue: 0.2706)

        /// Adaptive small-foreground-text orange — resolves to
        /// `hearthOrangeTextLight`/`hearthOrangeTextDark` per color scheme.
        /// Use this at any call site coloring body/caption/footnote/
        /// subheadline-sized text (captions, hints, badges, secondary button
        /// labels) that sits on `canvas` or `surface`. Do NOT use behind a
        /// fixed-scheme surface (e.g. the always-dark toast banners, which
        /// use `hearthOrangeTextDark` directly) or on `surfaceStrong` in
        /// dark mode (elevated enough — 0.0373 luminance — that even
        /// `hearthOrangeTextDark` falls short at 4.26:1; avoid pairing
        /// orange text with a `surfaceStrong` background in dark mode).
        static let hearthOrangeText = Color(light: hearthOrangeTextLight, dark: hearthOrangeTextDark)

        /// Primary-button-style fill: hearthOrangeFill + white label text is
        /// only 3.68:1, which fails AA normal text. Same value as
        /// `hearthOrangeTextLight` (#b94322) — verified 5.40:1 against white
        /// text, comfortably over 4.5:1, and mode-independent (a button
        /// fill's contrast against its own white label doesn't depend on
        /// the ambient canvas/surface color scheme, unlike `hearthOrangeText`).
        /// Kept as its own name since the use (button/chip fill vs. small
        /// foreground text) is semantically distinct even though the value
        /// is shared.
        static let hearthOrangePrimaryFill = hearthOrangeTextLight

        /// Fixed dark slab for transient toast/undo banners (regenerate
        /// undo, shopping "items cleared" undo). These are deliberately
        /// NOT adaptive to color scheme — always a dark surface with white
        /// text, a standard toast convention. Using the adaptive `inkDeep`
        /// token here was a real bug found during the Fas 8 audit: inkDeep's
        /// dark-mode value is near-white, which left the toasts'
        /// `.foregroundStyle(.white)` text at ~1:1 contrast in dark mode.
        /// Same value as inkDeep's light variant, so light mode is visually
        /// unchanged.
        static let toastSurface = Color(red: 0.059, green: 0.090, blue: 0.165)

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

    enum Typography {
        static func displayHeading(size: CGFloat) -> Font {
            .custom("Georgia-Bold", size: size, relativeTo: .largeTitle)
        }
    }
}

struct VecklyPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            // Fas 8: was a fixed `height: 48`, which clipped the label at
            // accessibility Dynamic Type sizes once it wrapped to two lines.
            // `minHeight` + vertical padding lets the capsule grow with the
            // label instead.
            .padding(.vertical, VecklyDesign.Spacing.small)
            .frame(minHeight: 48)
            .background(VecklyDesign.Colors.hearthOrangePrimaryFill.opacity(configuration.isPressed ? 0.86 : 1))
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
