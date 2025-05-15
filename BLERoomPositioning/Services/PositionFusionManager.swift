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

    private let settings: SettingsViewModel  // Provides toggles for PDR, BLE, confidence, ..
    let pdr: PDRManager

    // MARK: - State

    private let log = Logger(subsystem: "FusedPosition", category: "core")

    //private var lastBLEPosition: CGPoint?  // Last known good BLE fix
    //private var lastPDRPosition: CGPoint = .zero  // Most recent step-estimated position
    private var lastFusedPositionUpdateTime: Date = Date()  // For calculating prediction delta time
    private var bleDevices: [BLEDevice] = []  // Most recent BLE scan results
    private var knownBLEDevices: [BeaconKey: BLEDevice] = [:]  // Recent beacons with latest data (Meaning that var: bleDevices updates this variable)

    private var recentBLEPositions: [CGPoint] = []
    private let bleHistoryLimit = 4

    private var lastAppliedStepCount: Int = 0

    private var cancellables = Set<AnyCancellable>()  // For Combine subscriptions

    private var bleTimeout: Double = 2.0  // We only use beacons that have had a signal in the past x time (sec)

    // MARK: - Timer

    /// Timer that triggers PDR predictions periodically (e.g. 10x/sec)
    private var predictionTimer: AnyCancellable?

    // MARK: - Initialization

    /// Creates the fusion manager and starts observing settings.
    init(settings: SettingsViewModel, pdrManager: PDRManager) {
        self.settings = settings
        self.pdr = pdrManager
        observeSettings()
        startPredictionLoop()
        /// For testing only, to delete
        //fusedPosition = CGPoint(x: 800, y: 800)
        //fusedPosition = CGPoint(x: 341, y: 1756)
        //lastAppliedStepCount = pdr.stepCount
    }

    // MARK: - Public Input Methods

    /// Called by ViewModel when new BLE devices are discovered.
    /// Store and prepare to update BLE position estimate
    func updateBLEDevices(_ devices: [BLEDevice]) {
        // Store for later use
        self.bleDevices = devices
        for device in devices {
            let key = BeaconKey(uuid: device.uuid, name: device.name)
            if device.rssi == 0 {
                continue
            }
            knownBLEDevices[key] = device  // updates rssi, lastSeen, etc.
        }

    }
    /// This returns only BLE devices that have been seen in the past x time
    private func recentBLEDevices() -> [BLEDevice] {
        let now = Date()
        return knownBLEDevices.values.filter { device in
            guard let seen = device.lastSeen else { return false }
            return now.timeIntervalSince(seen) <= bleTimeout
        }
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
            .publish(every: updateFrequency, on: .main, in: .common)
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
        // Collecting BLE & PDR data and Kalman-style prediction + correction logic lives here
        let now = Date()

        var predicted = fusedPosition
        var bLEPredicted = fusedPosition
        var bleConfidence: Int = 0
        var stepDelta = -1

        //debugBLEVisibility(now: now)

        // --- PDR prediction ---
        if settings.isDeadReckoningEnabled {
            // Calculate step delta for fusion logic
            let stepCount = pdr.stepCount
            stepDelta = stepCount - lastAppliedStepCount
            //log.debug("in pdr if clause, step count: \(self.pdr.stepCount)")
            if let delta = pdr.computeStepDelta(from: lastAppliedStepCount) {
                predicted.x += delta.x * settings.worldScale
                predicted.y += delta.y * settings.worldScale
                lastAppliedStepCount = pdr.stepCount

                FusionLogger.shared.logPDRFrame(fused: predicted)
                //log.debug("PDR: Step delta: \(delta.x), \(delta.y)")
            }
        }
        // Check if BLE is enabled and get recent beacons
        let recentDevices =
            settings.isBLEPositioningEnabled ? recentBLEDevices() : []

        // --- BLE correction ---
        if !recentDevices.isEmpty {

            let txPower = settings.rssiReferencePower
            let pathLoss = settings.pathLossExponent

            if let result = PositionCalculator.calculate(
                devices: recentDevices,
                txPower: txPower,
                pathLossExponent: pathLoss,
                maxBeacons: 6/// Set value between 3 and inf/nil, if set to under 3 uses centroid
            ) {
                let blePos = result.position
                let confidence = result.confidence
                //log.info("Confidence: \(confidence), Position: \(blePos.x), \(blePos.y)")
                //lastBLEPosition = blePos
                bleConfidence = confidence

                /// Check if there is no fusedPosition or if the jump is suitable
                if fusedPosition == .zero || isBLEJumpReasonable(newBLE: blePos)
                {
                    bLEPredicted = blePos
                    
                    if fusedPosition == .zero && bLEPredicted != .zero {
                        fusedPosition = bLEPredicted
                        return
                    }
                    
                    //lastFusedPositionUpdateTime = Date()
                    // This is to fix wrong positioning when standing still
                    recentBLEPositions.append(bLEPredicted)
                    if recentBLEPositions.count > bleHistoryLimit {
                        recentBLEPositions.removeFirst()
                    }
                }
            }
        }
        if settings.isConfidenceEnabled && settings.isBLEPositioningEnabled && settings.isDeadReckoningEnabled{
            // Call blending function
            fusedPosition = blendedPosition(
                predicted: predicted,
                ble: bLEPredicted,
                confidence: bleConfidence,
                stepCountDelta: stepDelta,
                fusedPrevious: fusedPosition,
                lastFusedUpdate: lastFusedPositionUpdateTime
            )
            
            lastFusedPositionUpdateTime = Date()

        } else if settings.isDeadReckoningEnabled
            && settings.isBLEPositioningEnabled
        {
            // Fallback to avg of both
            let fusedX = (predicted.x + bLEPredicted.x) / 2
            let fusedY = (predicted.y + bLEPredicted.y) / 2
            fusedPosition = CGPoint(x: fusedX, y: fusedY)
            lastFusedPositionUpdateTime = Date()

        } else {
            //log.debug("here")
            fusedPosition =
                settings.isBLEPositioningEnabled ? bLEPredicted : predicted

        }
        
        FusionLogger.shared.logFusedFrame(fused: fusedPosition)

    }

    /// Determines the best fused position using PDR and BLE, with BLE acting as a soft correction.
    /// Applies proximity and reasonability checks to avoid BLE-based jumps.
    func blendedPosition(
        predicted: CGPoint,
        ble: CGPoint,
        confidence: Int,
        stepCountDelta: Int,
        fusedPrevious: CGPoint,
        lastFusedUpdate: Date
    ) -> CGPoint {

        let maxSnapDistance = 2.0 * settings.worldScale
        let fusedDistanceFromBLE = hypot(fusedPrevious.x - ble.x, fusedPrevious.y - ble.y)

        // 🧠 CASE 1: BLE is stable AND fused position has drifted too far
        if let stableBLE = isBLEClusterStable(),
           fusedDistanceFromBLE > maxSnapDistance {

            log.debug("BLE override: Fused too far from stable BLE cluster (dist \(fusedDistanceFromBLE))")
            return stableBLE
        }

        // 🧠 CASE 2: BLE is stable — blend gently toward cluster
        if let stableBLE = isBLEClusterStable() {
            let bleWeight: CGFloat = 0.2
            let pdrWeight = 1.0 - bleWeight

            return CGPoint(
                x: predicted.x * pdrWeight + stableBLE.x * bleWeight,
                y: predicted.y * pdrWeight + stableBLE.y * bleWeight
            )
        }

        // 🧠 CASE 3: fallback blend based on distance/proximity
        var bleWeight: CGFloat = 0.25  // default pull
        if distanceBetween(predicted, ble) < maxSnapDistance {
            let proximityRatio = 1.0 - (distanceBetween(predicted, ble) / maxSnapDistance)
            bleWeight = CGFloat(calculateBLEWeight(confidence: confidence)) * proximityRatio
        }

        let pdrWeight = 1.0 - bleWeight
        let fusedX = predicted.x * pdrWeight + ble.x * bleWeight
        let fusedY = predicted.y * pdrWeight + ble.y * bleWeight
        let fused = CGPoint(x: fusedX, y: fusedY)

        // Clamp inside map bounds
        if fused.x < 0 || fused.y < 0 || fused.x > settings.worldSize.width || fused.y > settings.worldSize.height {
            return CGPoint(
                x: min(max(0, fused.x), settings.worldSize.width),
                y: min(max(0, fused.y), settings.worldSize.height)
            )
        }

        return fused
    }
    
    private func distanceBetween(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        return hypot(a.x - b.x, a.y - b.y)
    }

    private func isBLEClusterStable() -> CGPoint? {
        guard recentBLEPositions.count >= bleHistoryLimit else { return nil }

        // Compute centroid
        let avgX = recentBLEPositions.map(\.x).reduce(0, +) / CGFloat(recentBLEPositions.count)
        let avgY = recentBLEPositions.map(\.y).reduce(0, +) / CGFloat(recentBLEPositions.count)
        let centroid = CGPoint(x: avgX, y: avgY)

        // Max radius from center to consider stable (e.g. 0.8m)
        let tolerance = 0.8 * settings.worldScale
        let allWithin = recentBLEPositions.allSatisfy {
            hypot($0.x - centroid.x, $0.y - centroid.y) <= tolerance
        }

        return allWithin ? centroid : nil
    }


    func calculateBLEWeight(confidence: Int) -> Double {
        switch confidence {
        case 5...: return 0.9
        case 4: return 0.75
        case 3: return 0.6
        case 2: return 0.4
        case 1: return 0.2
        default: return 0.0
        }
    }

    /// Checks if BLE position change is physically possible, based on PDR velocity.
    private func isBLEJumpReasonable(newBLE: CGPoint) -> Bool {
        let last = fusedPosition
        let distance = hypot(newBLE.x - last.x, newBLE.y - last.y)
        let maxDistance = 12 * settings.worldScale
        let timePassed = Date().timeIntervalSince(lastFusedPositionUpdateTime)
        let updateRate = 1.0

        /// If new pos is out of the map
        if newBLE.x < 0 || newBLE.x > settings.worldSize.width || newBLE.y < 0
            || newBLE.y > settings.worldSize.height
        {
            log.error("Concluded that BLE jump is out of the map!")
            return false
        }

        // If BLE update is very old, allow large jumps
        if timePassed > (5 * updateRate) {
            print("very old")
            return true
        }

        // If moderately old, allow larger margin
        if timePassed > (2 * updateRate), distance <= maxDistance * 2 {
            return true
        }

        // For normal updates, allow only within maxDistance
        if distance > maxDistance {
            log.error(
                "Concluded that BLE jump is not reasonable: \(distance / self.settings.worldScale)m (max \(maxDistance / self.settings.worldScale)m)"
            )
            return false
        }

        return true
    }

    /// Function only for testing
    private func debugBLEVisibility(now: Date) {
        if knownBLEDevices.count > 0 {
            let sortedBeacons = knownBLEDevices.values
                .sorted {
                    ($0.lastSeen ?? .distantPast)
                        > ($1.lastSeen ?? .distantPast)
                }
            log.debug("🔍 Known beacons (most recent first):")
            for beacon in sortedBeacons {
                guard let seen = beacon.lastSeen else {
                    log.debug(
                        "⚠️ Beacon \(beacon.name) [\(beacon.uuid)] has no lastSeen timestamp."
                    )
                    continue
                }
                let age = now.timeIntervalSince(seen)
                let rssi = beacon.rssi
                let name = beacon.name
                log.debug(
                    "🛰️ \(name) | RSSI: \(rssi) dBm | Seen \(String(format: "%.2f", age))s ago"
                )
            }
        } else {
            log.debug("No visible 🛰️")
        }
    }
}
