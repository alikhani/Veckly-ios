import Foundation

struct AppEnvironment: Equatable {
    let apiBaseURL: URL
    let supabaseURL: URL
    let supabaseAnonKey: String

    static var current: AppEnvironment {
        AppEnvironment(
            apiBaseURL: url(envVar: "VECKLY_API_BASE_URL", fallback: "https://veckly-backend.vercel.app"),
            supabaseURL: url(envVar: "VECKLY_SUPABASE_URL", fallback: "https://ydzykuwqfslzewxisliv.supabase.co"),
            supabaseAnonKey: ProcessInfo.processInfo.environment["VECKLY_SUPABASE_ANON_KEY"] ?? "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InlkenlrdXdxZnNsemV3eGlzbGl2Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODA5MzA5MzIsImV4cCI6MjA5NjUwNjkzMn0.OFn2P6Y0Ye5nP3QA0mZkljoon_eKnd3Z_RJaZTPI8ps"
        )
    }

    // Falls back to the known-good literal instead of crashing at launch if an
    // override env var is ever set to a malformed URL string.
    private static func url(envVar: String, fallback: String) -> URL {
        if let raw = ProcessInfo.processInfo.environment[envVar], let url = URL(string: raw) {
            return url
        }
        return URL(string: fallback)!
    }
}
