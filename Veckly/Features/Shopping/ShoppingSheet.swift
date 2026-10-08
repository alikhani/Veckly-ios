import Foundation

/// Every sheet the Shopping tab can present. One optional value (owned by
/// `ShoppingScreenModel`) instead of one `Bool` per sheet, so at most one
/// sheet can be requested at a time.
enum ShoppingSheet: String, Identifiable {
    case customItem
    case categoryOrder

    var id: String { rawValue }
}
