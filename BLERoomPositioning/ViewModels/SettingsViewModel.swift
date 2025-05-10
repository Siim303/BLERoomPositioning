
//
//  SettingsViewModel.swift
//  BLERoomPositioning
//
//  Created by Siim Turban on 08.04.2025.
//
import SwiftUI

class SettingsViewModel: ObservableObject {
    // Positioning toggles
    @Published var isDeadReckoningEnabled: Bool = false
    @Published var isConfidenceEnabled: Bool = false
    @Published var isBeaconSimulationEnabled: Bool = false
    @Published var isBLEPositioningEnabled: Bool = true
    
    // Calibration parameters
    @Published var accelerometerSensitivity: Double = 50.0  // Multiplier for sensor integration
    @Published var pathLossExponent: Double = 2.0           // Used in RSSI-to-distance conversion
    @Published var positionUpdateFrequency: Double = 1.0    // Position update interval in seconds
    @Published var rssiReferencePower: Int = -75
    
    // Debugging
    @Published var isDebugLoggingEnabled: Bool = false
}
