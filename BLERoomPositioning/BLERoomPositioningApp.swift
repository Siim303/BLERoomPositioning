//
//  BLERoomPositioningApp.swift
//  BLERoomPositioning
//
//  Created by Siim Turban on 27.02.2025.
//

import SwiftUI
import SwiftData

@main
struct BLERoomPositioningApp: App {
    @StateObject var settings = SettingsViewModel()


    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(settings)  // Now any view can access it via @EnvironmentObject
        }
    }
}
