//
//  BLEDevice.swift
//  BLERoomPositioning
//
//  Created by Siim Turban on 08.04.2025.
//
import Foundation
import CoreBluetooth

struct BLEDevice: Identifiable {
    let id = UUID()          // Unique identifier for SwiftUI view updates
    let uuid: String         // Unique hardware or advertisement identifier from the beacon
    let name: String         // The advertised name, e.g., "BLEpos01", which can imply location
    let rssi: Int            // Received Signal Strength Indicator (RSSI) in dBm, used to estimate distance
    let position: CGPoint    // Pre-configured physical coordinates of the beacon in your environment
    let lastSeen: Date?      // Timestamp when the beacon was last detected, useful for filtering outdated data
}
