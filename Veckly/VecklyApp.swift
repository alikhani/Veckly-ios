//
//  VecklyApp.swift
//  Veckly
//
//  Created by Nima on 2026-06-09.
//

import SwiftUI

@main
struct VecklyApp: App {
    @State private var appModel = AppModel(environment: .current)

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appModel)
        }
    }
}
