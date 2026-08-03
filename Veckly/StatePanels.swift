import SwiftUI

/// Shared cold-launch loading gate for tabs whose content depends on both
/// `HouseholdStore` bootstrap and their own store's first load (`WeekTabView`,
/// `ShoppingListTabView`).
///
/// `HouseholdStore.isLoading` only flips to `true` *inside* the unstructured
/// `Task` that `AppRefreshCoordinator.run` spawns for the household
/// bootstrap — it's `false` both before that `Task` has had a chance to run
/// its first line and, obviously, before it's even been created. On cold
/// launch, `RootView` flips `isRestoring` to `false` (mounting the tab for
/// the first time) moments *before* `AppModel.restoreSession()` goes on to
/// call `loadCoreReader()`, so there is a real — if usually brief — window
/// where SwiftUI evaluates a tab's body with `householdStore.isLoading ==
/// false`, the tab's own store `isLoading == false`, and no active household
/// yet, all at once, purely because the bootstrap `Task` hasn't been
/// scheduled yet. Without this extra check, that window renders each tab's
/// empty/error-adjacent content for a frame before the bootstrap `Task`
/// starts and flips `isLoading` back to `true` — the "loads, something
/// appears briefly, then it starts loading again" flash reported
/// 2026-08-03 (`WeekTabView`) and 2026-08-03 (`ShoppingListTabView`, which
/// had the same gap plus a third, more exposed empty-state branch since its
/// pre-fix gate didn't check the household at all).
///
/// Gating on `activeHousehold == nil` instead of on `isLoading`'s timing
/// closes that window regardless of scheduling order, since it's `nil` both
/// before and during the fetch. It's safe to treat "no active household
/// yet" as "still loading" here: `bootstrapAndLoadHouseholds` always ends
/// with either an active household or `errorMessage` set (see its `catch`),
/// so `activeHousehold == nil` with no error is only ever a transient state
/// for a signed-in user, never a legitimate steady state to render content —
/// hence the `householdErrorMessage == nil` guard, so a real bootstrap
/// failure still falls through to the caller's `ErrorPanel` branch instead
/// of spinning forever.
enum CoreLoadingGate {
    static func shouldShowLoadingPanel(
        isLoadingHouseholds: Bool,
        isLoadingContent: Bool,
        hasActiveHousehold: Bool,
        householdErrorMessage: String?
    ) -> Bool {
        if isLoadingHouseholds || isLoadingContent { return true }
        return !hasActiveHousehold && householdErrorMessage == nil
    }
}

struct LoadingPanel: View {
    let title: String

    var body: some View {
        VecklyCard {
            HStack(spacing: 12) {
                ProgressView()
                    .tint(VecklyDesign.Colors.hearthOrangeFill)
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
