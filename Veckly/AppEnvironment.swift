import Foundation

struct AppEnvironment: Equatable {
    let apiBaseURL: URL
    let supabaseURL: URL
    let supabaseAnonKey: String

    static var current: AppEnvironment {
        AppEnvironment(
            apiBaseURL: URL(string: ProcessInfo.processInfo.environment["VECKLY_API_BASE_URL"] ?? "http://127.0.0.1:3001")!,
            supabaseURL: URL(string: ProcessInfo.processInfo.environment["VECKLY_SUPABASE_URL"] ?? "https://example.supabase.co")!,
            supabaseAnonKey: ProcessInfo.processInfo.environment["VECKLY_SUPABASE_ANON_KEY"] ?? "replace-me"
        )
    }
}
