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
    let pdr: PDRManager

    // MARK: - State

    private let log = Logger(subsystem: "FusedPosition", category: "core")

    private var lastBLEPosition: CGPoint?  // Last known good BLE fix
    private var lastPDRPosition: CGPoint = .zero  // Most recent step-estimated position
    private var lastUpdateTime: Date = Date()  // For calculating prediction delta time
    private var lastFusedPositionUpdateTime: Date = Date()  // For calculating prediction delta time
    //private var lastBLEConfidence: Int = 0  //
    private var bleDevices: [BLEDevice] = []  // Most recent BLE scan results
    private var knownBLEDevices: [BeaconKey: BLEDevice] = [:]  // Recent beacons with latest data (Meaning that var: bleDevices updates this variable)

    private var lastAppliedStepCount: Int = 0

    private var cancellables = Set<AnyCancellable>()  // For Combine subscriptions

    private var bleTimeout: Double = 2.0  // We only use beacons that have had a signal in the past x time

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
        fusedPosition = CGPoint(x: 800, y: 800)
        //lastAppliedStepCount = pdr.stepCount
    }

    // MARK: - Public Input Methods

    /// Called by ViewModel when new BLE devices are discovered.
    //  Store and prepare to update BLE position estimate
    func updateBLEDevices(_ devices: [BLEDevice]) {
        // Store for later use (e.g. in confidence or correction logic)
        self.bleDevices = devices
        //print(devices)
        for device in devices {  //TODO: Test if this actually updates the known beacons correctly
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
        //let dt = now.timeIntervalSince(lastUpdateTime)
        lastUpdateTime = now

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
            } /*
            if let delta = pdr.consumeStepDelta() {
                predicted.x += delta.x
                predicted.y += delta.y
                log.debug("PDR: Step delta: \(delta.x), \(delta.y)")
            }*/
        }

        let recentDevices =
            settings.isBLEPositioningEnabled ? recentBLEDevices() : []
        // --- BLE correction ---
        if !recentDevices.isEmpty {
            //let recentDevices = recentBLEDevices()

            let txPower = settings.rssiReferencePower
            let pathLoss = settings.pathLossExponent

            if let result = PositionCalculator.calculate(
                devices: recentDevices,
                txPower: txPower,
                pathLossExponent: pathLoss,
                maxBeacons: 4 /// Set value between 3 and inf/nil, if set to under 3 uses centroid
            ) {
                let blePos = result.position
                let confidence = result.confidence
                //log.info("Confidence: \(confidence), Position: \(blePos.x), \(blePos.y)")
                // Save for optional debugging
                lastBLEPosition = blePos
                bleConfidence = confidence

                /// Check if there is no fusedPosition or if the jump is suitable
                if fusedPosition == .zero || isBLEJumpReasonable(newBLE: blePos)
                {
                    bLEPredicted = blePos
                    lastFusedPositionUpdateTime = Date()
                }
            }
        }
        if settings.isConfidenceEnabled {
            /*let bleWeight = calculateBLEWeight(confidence: bleConfidence)
            let pdrWeight = 1.0 - bleWeight

            let fusedX = predicted.x * pdrWeight + bLEPredicted.x * bleWeight
            let fusedY = predicted.y * pdrWeight + bLEPredicted.y * bleWeight

            fusedPosition = CGPoint(x: fusedX, y: fusedY)*/
            
            fusedPosition = blendedPosition(
                predicted: predicted,
                ble: bLEPredicted,
                confidence: bleConfidence,
                stepCountDelta: stepDelta,
                fusedPrevious: fusedPosition,
                lastFusedUpdate: lastFusedPositionUpdateTime
            )

        } else if settings.isDeadReckoningEnabled
            && settings.isBLEPositioningEnabled
        {
            /// Fallback to avg of both
            let fusedX = (predicted.x + bLEPredicted.x) / 2
            let fusedY = (predicted.y + bLEPredicted.y) / 2
            fusedPosition = CGPoint(x: fusedX, y: fusedY)
        } else {
            fusedPosition =
                settings.isBLEPositioningEnabled ? bLEPredicted : predicted
        }

        FusionLogger.shared.logFusedFrame(fused: fusedPosition)

        /// Logic to decide how to update position
        // fusedPosition = predicted or fusedPosition = bLEPredicted or a mix of these
        //fusedPosition = bLEPredicted
        //fusedPosition = predicted
        //log.debug("fusedPosition: \(self.fusedPosition.x), \(self.fusedPosition.y)")
        //log.debug("BLE predicted: \(bLEPredicted.x), \(bLEPredicted.y), PDR predicted: \(predicted.x), \(predicted.y), time: \(Date())")
        // --- Fallback to prediction only ---

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
        
        if stepCountDelta == 0 {
            // No movement → suppress BLE correction
            return predicted  // which should be the same as last fusedPosition
        }

        let distance = hypot(predicted.x - ble.x, predicted.y - ble.y)
        let maxSnapDistance = 2.0 * settings.worldScale

        // Time since last BLE-based fusion
        let timePassed = Date().timeIntervalSince(lastFusedUpdate)
        let updateRate = 1.0  // assumes 1Hz fusion

        var bleWeight: Double = 0.0

        // --- BLE sanity check (same as isBLEJumpReasonable) ---
        let bleInBounds =
            ble.x >= 0 && ble.x <= settings.worldSize.width && ble.y >= 0
            && ble.y <= settings.worldSize.height

        let distanceFromLast = hypot(
            ble.x - fusedPrevious.x, ble.y - fusedPrevious.y)
        let maxJumpDistance = 5 * settings.worldScale

        let isBLEJumpReasonable: Bool = {
            if !bleInBounds { return false }
            if timePassed > (6 * updateRate) { return true }
            if timePassed > (3 * updateRate),
                distanceFromLast <= maxJumpDistance * 2
            {
                return true
            }
            return distanceFromLast <= maxJumpDistance
        }()

        // --- Weight calculation ---
        if isBLEJumpReasonable {
            if distance < maxSnapDistance {
                let proximityRatio = 1.0 - (distance / maxSnapDistance)
                bleWeight =
                    calculateBLEWeight(confidence: confidence) * proximityRatio
            } else {
                // fallback correction weight to rein in drift
                bleWeight = 0.25
            }
        }

        let pdrWeight = 1.0 - bleWeight

        let fusedX = predicted.x * pdrWeight + ble.x * bleWeight
        let fusedY = predicted.y * pdrWeight + ble.y * bleWeight

        return CGPoint(x: fusedX, y: fusedY)
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
        let maxDistance = 5 * settings.worldScale
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
        if timePassed > (6 * updateRate) {
            return true
        }

        // If moderately old, allow larger margin
        if timePassed > (3 * updateRate), distance <= maxDistance * 2 {
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
