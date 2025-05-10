//
//  PositionFusionManager.swift
//  BLERoomPositioning
//
//  Created by Siim Turban on 09.05.2025.
//

import Combine
import CoreGraphics
import Foundation
import os.log

struct BeaconKey: Hashable {
    let uuid: String
    let name: String
}

/// Combines BLE and PDR data into a single fused position using prediction + correction logic.
/// This class runs on a timer to regularly predict position using PDR, and corrects using BLE when available.
final class PositionFusionManager: ObservableObject {

    // MARK: - Published Outputs

    /// The current best-estimate of the user's position, updated in real-time.
    @Published private(set) var fusedPosition: CGPoint = .zero

    // MARK: - Dependencies

    private let settings: SettingsViewModel  // Provides toggles for DR, BLE, confidence, etc.

    // MARK: - State
    
    private let log = Logger(subsystem: "FusedPosition", category: "core")

    private var lastBLEPosition: CGPoint?  // Last known good BLE fix
    private var lastPDRPosition: CGPoint = .zero  // Most recent step-estimated position
    private var lastUpdateTime: Date = Date()  // For calculating prediction delta time
    private var lastFusedPositionUpdateTime: Date = Date()  // For calculating prediction delta time
    private var lastBLEConfidence: Int = 0  //
    private var bleDevices: [BLEDevice] = []  // Most recent BLE scan results
    private var knownBLEDevices: [BeaconKey: BLEDevice] = [:]  // Recent beacons with latest data (Meaning that var: bleDevices updates this variable)

    private var cancellables = Set<AnyCancellable>()  // For Combine subscriptions
    
    private var bleTimeout: Double = 2.0 // We only use beacons that have had a signal in the past x time

    // MARK: - Timer

    /// Timer that triggers PDR predictions periodically (e.g. 10x/sec)
    private var predictionTimer: AnyCancellable?

    // MARK: - Initialization

    /// Creates the fusion manager and starts observing settings.
    init(settings: SettingsViewModel) {
        self.settings = settings
        observeSettings()
        startPredictionLoop()
    }

    // MARK: - Public Input Methods

    /// Called by ViewModel when new BLE devices are discovered.
    //  Store and prepare to update BLE position estimate
    func updateBLEDevices(_ devices: [BLEDevice]) {
        // Store for later use (e.g. in confidence or correction logic)
        self.bleDevices = devices
        //print(devices)
        for device in devices { //TODO: Test if this actually updates the known beacons correctly
            let key = BeaconKey(uuid: device.uuid, name: device.name)
            if device.rssi == 0 {
                continue
            }
            knownBLEDevices[key] = device  // updates rssi, lastSeen, etc.
        }
        //log.debug("List of known BLE devices:\(self.knownBLEDevices)")
        /* TODO: Delete this as we don't want to strain app with constant calculations
        // Try to compute a position from these devices
        guard settings.isBLEPositioningEnabled else { return }

        if let result = PositionCalculator.calculate(devices: devices) {
            let blePosition = result.position
            let confidence = result.confidence  // store if you plan to use confidence weighting later

            // Store for correction/prediction comparison
            self.lastBLEPosition = blePosition

            // Optionally apply immediately (if not doing time-loop-based fusion)
            // fusedPosition = blePosition  // ← skip this for now, we'll let updateFusedPosition() handle it
        }*/
    }
    /// This returns only BLE devices that have been seen in the past x time
    private func recentBLEDevices() -> [BLEDevice] {
        let now = Date()
        return knownBLEDevices.values.filter { device in
            guard let seen = device.lastSeen else { return false }
            return now.timeIntervalSince(seen) <= bleTimeout
        }
    }

    /// Called when a new position is estimated via dead reckoning.
    func updatePDRPosition(_ position: CGPoint) {
        // Update PDR-based estimate used for prediction
    }

    // MARK: - Private Fusion Logic

    /// Observes toggles from SettingsViewModel (e.g. DR/BLE/Confidence).
    private func observeSettings() {
        settings.$positionUpdateFrequency
            .removeDuplicates()
            .sink { [weak self] newInterval in
                self?.restartPredictionLoop(with: newInterval)
            }
            .store(in: &cancellables)
    }
    
    private func restartPredictionLoop(with interval: TimeInterval) {
        predictionTimer?.cancel()

        predictionTimer =
            Timer.publish(every: interval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.updateFusedPosition()
            }
    }

    /// Starts a repeating timer to update fused position using PDR prediction.
    private func startPredictionLoop() {
        // Runs every 0.1s or so;
        // Cancel any existing timer first
        predictionTimer?.cancel()
        
        let updateFrequency = settings.positionUpdateFrequency

        // Use a Combine timer that fires on the main thread
        predictionTimer =
            Timer
            .publish(every: updateFrequency, on: .main, in: .common)  // 0.1s = 10 Hz
            .autoconnect()
            .sink { [weak self] _ in
                self?.updateFusedPosition()
            }
    }

    // Cleanup method for loop
    func stopPredictionLoop() {
        predictionTimer?.cancel()
        predictionTimer = nil
    }

    /// Recalculates the fused position based on BLE and/or PDR updates.
    private func updateFusedPosition() {
        // Kalman-style prediction + correction logic lives here
        // as a start for testing purposes print out each known beacon sorted by last seen first, (also print beacon time since seen and rssi and name ofc)
        let now = Date()
        let dt = now.timeIntervalSince(lastUpdateTime)
        lastUpdateTime = now
        
        var predicted = fusedPosition
        
        //debugBLEVisibility(now: now)
        
        // --- PDR prediction ---
        if settings.isDeadReckoningEnabled {
            //if let pdrUpdate = pdrManager.computeDeadReckoningUpdate(from: fusedPosition) {
            //    predicted = pdrUpdate.position
            //}
        }
        
        // --- BLE correction ---
        if settings.isBLEPositioningEnabled {
            let recentDevices = recentBLEDevices()
            
            let txPower = settings.rssiReferencePower
            let pathLoss = settings.pathLossExponent

            if let result = PositionCalculator.calculate(devices: recentDevices, txPower: txPower, pathLossExponent: pathLoss) {
                let blePos = result.position
                let confidence = result.confidence
                log.info("Confidence: \(confidence), Position: \(blePos.x), \(blePos.y)")
                // Save for optional debugging
                lastBLEPosition = blePos
                lastBLEConfidence = confidence
                
                if isBLEJumpReasonable(newBLE: blePos) || (Date().timeIntervalSince(lastFusedPositionUpdateTime) > 3) {
                    if settings.isConfidenceEnabled && false {
                        //let x = blePos.x * confidence + predicted.x * (1 - confidence)
                        //let y = blePos.y * confidence + predicted.y * (1 - confidence)
                        //fusedPosition = CGPoint(x: x, y: y)
                    } else {
                        //log.debug("Position changed by BLE, old x: \(Double(predicted.x)), y: \(Double(predicted.y)), new x: \(Double(blePos.x)), y: \(Double(blePos.y))")
                        fusedPosition = blePos
                        lastFusedPositionUpdateTime = Date()
                        //print("⚠️ ViewModel fusedPosition = \(fusedPosition)")  // Inside RoomPositioningViewModel
                    }
                    return
                } else {
                    //log.debug("🚫 BLE jump rejected: too far from predicted position.")
                }
            }
        }

        // --- Fallback to prediction only ---
        fusedPosition = predicted
        
    }
    

    /// Checks if BLE position change is physically possible, based on PDR velocity.
    private func isBLEJumpReasonable(newBLE: CGPoint) -> Bool {
        // Optional helper to reject BLE outliers
        guard let last = fusedPosition as CGPoint? else { return true }
            
        let distance = hypot(newBLE.x - last.x, newBLE.y - last.y)
        let maxDistance: CGFloat = 10
        if distance > maxDistance {
            //log.error("Concluded that BLE jump is not reasonable: \(distance)m")
        }
        
        // Example: allow max 2.5m movement per BLE update
        return distance <= maxDistance
    }
    
    /// Function only for testing
    private func debugBLEVisibility(now: Date) {
        if knownBLEDevices.count > 0 {
            let sortedBeacons = knownBLEDevices.values
                .sorted { ($0.lastSeen ?? .distantPast) > ($1.lastSeen ?? .distantPast) }
            
            log.debug("🔍 Known beacons (most recent first):")
            
            for beacon in sortedBeacons {
                guard let seen = beacon.lastSeen else {
                    log.debug("⚠️ Beacon \(beacon.name) [\(beacon.uuid)] has no lastSeen timestamp.")
                    continue
                }
                
                let age = now.timeIntervalSince(seen)
                let rssi = beacon.rssi
                let name = beacon.name
                
                log.debug("🛰️ \(name) | RSSI: \(rssi) dBm | Seen \(String(format: "%.2f", age))s ago")
            }
        } else {
            log.debug("No visible 🛰️")
        }
    }
}
