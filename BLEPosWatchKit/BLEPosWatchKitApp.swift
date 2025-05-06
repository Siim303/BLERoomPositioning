//
//  BLEPosWatchKitApp.swift
//  BLERoomPositioning
//
//  Created by Siim Turban on 05.05.2025.
//
//  BLEPosWatchKitApp.swift         (put this in the *WatchKit Extension* target)
import SwiftUI
import WatchKit

@main
struct BLEPosWatchKitApp: App {
    // launches our head‑less sensor delegate
    @WKExtensionDelegateAdaptor(WatchDelegate.self) var delegate

    var body: some Scene {               // no UI – empty scene is fine
        WindowGroup { EmptyView() }
    }
}

final class WatchDelegate: NSObject, WKExtensionDelegate {
    private let pdr = PDRWatchManager()

    func applicationDidFinishLaunching() { pdr.start() }
    func applicationWillResignActive()   { pdr.stop()  }
    func applicationDidBecomeActive()    { pdr.start() }
}
