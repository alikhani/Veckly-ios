//
//  VecklyApp.swift
//  Veckly
//
//  Created by Nima on 2026-06-09.
//

import SwiftUI

@main
struct VecklyApp: App {
    init() {
        #if DEBUG
        if CommandLine.arguments.contains("-UIReset") {
            AuthSessionStore.resetStoredSessionForUITests()
        }
        if let arg = CommandLine.arguments.first(where: { $0.hasPrefix("-UITestUserId=") }),
           let userID = arg.components(separatedBy: "=").last,
           !userID.isEmpty {
            UserDefaults.standard.set(userID, forKey: "ui_test_dev_user_id")
        } else {
            UserDefaults.standard.removeObject(forKey: "ui_test_dev_user_id")
        }
        #endif
    }

    @State private var appModel = AppModel(environment: .current)

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appModel)
        }
    }
}
