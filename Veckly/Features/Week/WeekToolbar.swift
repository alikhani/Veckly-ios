import SwiftUI

/// The Week tab's trailing toolbar.
///
/// Beslut: "Planera resten" lives as the CTA inside
/// `WeekPlanningStatusCard`'s content card. "Gör om veckan"
/// (Fas C) moved here, into a menu — it's a rare, destructive
/// action that doesn't belong as a second always-visible CTA next
/// to the status card's primary button. A lone `ToolbarItem`
/// still covers the common case (refresh only) to avoid the
/// ambiguous empty-looking Liquid Glass pill a single-control
/// `ToolbarItemGroup` renders as on iOS 26.
struct WeekToolbar: ToolbarContent {
    enum Mode {
        /// The viewed week is being generated right now.
        case generating
        /// A fully planned (non-last) week: "Regenerate" menu + refresh.
        case regenerateAndRefresh
        /// Any other non-last week: refresh only.
        case refresh
        /// Last week is view-only: no toolbar items at all.
        case none
    }

    let mode: Mode
    let onRegenerate: () -> Void
    let onRefresh: () -> Void

    var body: some ToolbarContent {
        if mode == .generating {
            ToolbarItem(placement: .topBarTrailing) {
                ProgressView()
            }
        } else if mode == .regenerateAndRefresh {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Menu {
                    Button(role: .destructive) {
                        onRegenerate()
                    } label: {
                        Label("week.regenerate", systemImage: "arrow.triangle.2.circlepath")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel(L10n.string("week.moreOptions"))
                .accessibilityIdentifier("weekMoreOptionsMenu")

                Button {
                    // An explicit tap always forces a real reload —
                    // this is the Week tab's pull-to-refresh equivalent
                    // (it has no `.refreshable`, since the whole
                    // ScrollView already scrolls the hero/status cards
                    // along with the list).
                    onRefresh()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .accessibilityLabel(L10n.string("common.refresh"))
            }
        } else if mode == .refresh {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    onRefresh()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .accessibilityLabel(L10n.string("common.refresh"))
            }
        }
    }
}
