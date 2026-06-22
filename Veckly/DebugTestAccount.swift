import Foundation

// Real credentials live in DebugTestAccount.Local.swift, which is gitignored.
// Copy DebugTestAccount.Local.swift.example to create your own local override.
#if DEBUG
struct DebugTestAccount {
    let email: String
    let password: String
}
#endif
