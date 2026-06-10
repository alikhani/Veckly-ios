import Foundation

struct AppEnvironment: Equatable {
    let apiBaseURL: URL
    let supabaseURL: URL
    let supabaseAnonKey: String

    static var current: AppEnvironment {
        AppEnvironment(
            apiBaseURL: URL(string: ProcessInfo.processInfo.environment["VECKLY_API_BASE_URL"] ?? "https://veckly-backend.vercel.app")!,
            supabaseURL: URL(string: ProcessInfo.processInfo.environment["VECKLY_SUPABASE_URL"] ?? "https://ydzykuwqfslzewxisliv.supabase.co")!,
            supabaseAnonKey: ProcessInfo.processInfo.environment["VECKLY_SUPABASE_ANON_KEY"] ?? "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InlkenlrdXdxZnNsemV3eGlzbGl2Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODA5MzA5MzIsImV4cCI6MjA5NjUwNjkzMn0.OFn2P6Y0Ye5nP3QA0mZkljoon_eKnd3Z_RJaZTPI8ps"
        )
    }
}
