import Foundation

enum AppEnvironmentName: String, Equatable {
    case production
    case staging
}

struct AppEnvironment: Equatable {
    let name: AppEnvironmentName
    let apiBaseURL: URL
    let supabaseURL: URL
    let supabaseAnonKey: String
    let enableDevLogin: Bool

    static var current: AppEnvironment {
        let processEnvironment = ProcessInfo.processInfo.environment
        let bundle = Bundle.main

        let rawEnvironment = configuredValue(
            key: "VECKLY_ENVIRONMENT",
            processEnvironment: processEnvironment,
            bundle: bundle
        ) ?? AppEnvironmentName.production.rawValue
        let name = AppEnvironmentName(rawValue: rawEnvironment) ?? .production

        guard
            let apiBaseURLString = configuredValue(
                key: "VECKLY_API_BASE_URL",
                processEnvironment: processEnvironment,
                bundle: bundle
            ),
            let apiBaseURL = URL(string: apiBaseURLString),
            let supabaseURLString = configuredValue(
                key: "VECKLY_SUPABASE_URL",
                processEnvironment: processEnvironment,
                bundle: bundle
            ),
            let supabaseURL = URL(string: supabaseURLString),
            let supabaseAnonKey = configuredValue(
                key: "VECKLY_SUPABASE_ANON_KEY",
                processEnvironment: processEnvironment,
                bundle: bundle
            )
        else {
            fatalError("Veckly environment is not configured. Check the active xcconfig or launchEnvironment overrides.")
        }

        return AppEnvironment(
            name: name,
            apiBaseURL: apiBaseURL,
            supabaseURL: supabaseURL,
            supabaseAnonKey: supabaseAnonKey,
            enableDevLogin: boolValue(
                key: "VECKLY_ENABLE_DEV_LOGIN",
                processEnvironment: processEnvironment,
                bundle: bundle
            )
        )
    }

    private static func configuredValue(
        key: String,
        processEnvironment: [String: String],
        bundle: Bundle
    ) -> String? {
        if let envValue = processEnvironment[key], !envValue.isEmpty {
            return envValue
        }
        return bundle.object(forInfoDictionaryKey: key) as? String
    }

    private static func boolValue(
        key: String,
        processEnvironment: [String: String],
        bundle: Bundle
    ) -> Bool {
        guard let rawValue = configuredValue(key: key, processEnvironment: processEnvironment, bundle: bundle) else {
            return false
        }
        return ["1", "true", "yes"].contains(rawValue.lowercased())
    }
}
