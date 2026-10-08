import Foundation

/// Why a load was started, which decides whether its answer may change the
/// screen right away.
enum LoadOrigin {
    /// Cold launch, returning to the foreground, a tab or week appearing: the
    /// user didn't ask for new data and may be reading or checking things off.
    case background
    /// A pull-to-refresh, a retry, or the follow-up to the user's own change:
    /// the answer is what the user is waiting for.
    case userInitiated
}

enum UpdateDecision: Equatable {
    case applyNow
    case ignore
    case deferBehindBanner
}

/// A fresh server response that differs from what is on screen and is waiting
/// for the user to ask for it (the "updates available" banner). `scope`
/// names the view it belongs to (a week) so it can be dropped when the user
/// moves elsewhere.
struct PendingUpdate<Value: Equatable>: Equatable {
    let value: Value
    let scope: String

    /// `displayed` is the last server state the screen was built from, nil
    /// when nothing cached was shown.
    static func decide(displayed: Value?, fetched: Value, origin: LoadOrigin) -> UpdateDecision {
        if origin == .userInitiated { return .applyNow }
        guard let displayed else { return .applyNow }
        return displayed == fetched ? .ignore : .deferBehindBanner
    }
}
