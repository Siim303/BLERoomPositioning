//
//  Calculation.swift
//  BLERoomPositioning
//
//  Created by Siim Turban on 01.04.2025.
//

import CoreGraphics
import Foundation
import os.log

private let log = Logger(subsystem: "Calculation", category: "core")

// MARK: - Utility math helpers
struct PositionMath {
    /// Convert an RSSI value (dBm) to an estimated distance (metres) using a log‑distance path‑loss model.
    /// - `txPower`: This is the expected RSSI value (in dBm) at a reference distance of 1 meter.
    ///   It represents the baseline signal strength and depends on the specific beacon's hardware and transmission power.
    ///   A higher (less negative) `txPower` means the device is expected to be stronger at 1m, making other RSSI values appear further away.
    ///
    /// - `pathLossExponent` (n): This determines how quickly the signal attenuates with distance.
    ///   - In free space, `n ≈ 2.0`
    ///   - Indoors with walls and obstructions, `n` is typically between 2.2 and 4.0
    ///   A higher `n` means signal strength decreases faster with distance, resulting in shorter estimated ranges for the same RSSI.
    ///
    /// - **Return value**: The result is an estimated distance in **meters** from the receiver to the beacon.
    ///   This is a theoretical value based on signal strength and can vary due to environmental noise, reflections, or interference.
    ///   The estimate tends to be less reliable at distances >5 meters or when the RSSI fluctuates rapidly.
    ///
    /// Note: The formula assumes signal loss follows a logarithmic curve, which is an approximation.
    /// For best results, calibrate `txPower` and `n` based on empirical measurements in your environment.
    static func rssiToDistance(
        rssi: Int,
        txPower: Int,
        pathLossExponent: Double
    ) -> Double {
        let ratio = Double(txPower - rssi)
        return pow(10.0, ratio / (10.0 * pathLossExponent))
    }

    /// Interpolates a point between two beacons using inverse‑distance weighting:
    ///   p = (d₂·p₁ + d₁·p₂) / (d₁ + d₂)
    /// so the estimate slides toward the stronger (smaller‑d) beacon.
    static func inverseDistancePoint(
        p1: CGPoint, d1: Double,
        p2: CGPoint, d2: Double
    ) -> CGPoint {
        let x = (d2 * Double(p1.x) + d1 * Double(p2.x)) / (d1 + d2)
        let y = (d2 * Double(p1.y) + d1 * Double(p2.y)) / (d1 + d2)
        return CGPoint(x: x, y: y)
    }
}

extension PositionCalculator {
    // MARK: - Internal multilateration helper (≥3 beacons)
    /// Weighted least‑squares trilateration. Returns `nil` if the matrix is singular.
    private static func multilaterate(
        _ devices: [BLEDevice], txPower: Int, pathLossExponent: Double
    ) -> CGPoint? {
        guard devices.count >= 3 else { return nil }

        var filtered = devices

        // Only filter weak beacons if we have more than 3 to choose from
        if devices.count > 3 {
            filtered = devices.filter { $0.rssi > -90 }
        }
        //print(devices)
        // Still need at least 3 after filtering
        //guard filtered.count >= 3 else { return nil }
        
        //let devices = filtered
        
        /// Distances (dᵢ) and weights (wᵢ = RSSI strength in [0,1])
        let distances = devices.map {
            PositionMath.rssiToDistance(
                rssi: $0.rssi, txPower: txPower,
                pathLossExponent: pathLossExponent)  * 30
        }
        var devDistances = ""
        for i in 0..<devices.count {
            devDistances +=
                "\(devices[i].name): \((distances[i]*1000).rounded()/1000) | "
        }
        /// This whole line to just cut off 3 last characters of a string is Swift ¯\_(ツ)_/¯
        log.debug("\(devDistances[devDistances.startIndex..<devDistances.index(devDistances.endIndex, offsetBy: -3)])")

        // TODO: Maybe to remove?
        let weights = devices.map { d -> Double in
            let norm = (Double(d.rssi) + 100) / 70.0
            return max(0.1, min(1.0, norm))
        }
        //log.debug("Weights: \(weights)")

        /// Use the first beacon as the reference
        let ref = devices[0]
        let x0 = Double(ref.position.x)
        let y0 = Double(ref.position.y)
        let d0 = distances[0]

        /// Build weighted normal equations  Σ w·aᵀa · x = Σ w·aᵀb
        var S00 = 0.0
        var S01 = 0.0
        var S11 = 0.0
        var T0 = 0.0
        var T1 = 0.0

        for i in 1..<devices.count {
            let xi = Double(devices[i].position.x)
            let yi = Double(devices[i].position.y)
            let di = distances[i]
            let w =  1.0 // weights[i] // 1.0

            let a0 = 2 * (xi - x0)
            let a1 = 2 * (yi - y0)
            let bi =
                d0 * d0 - di * di + (xi * xi - x0 * x0) + (yi * yi - y0 * y0)

            S00 += w * a0 * a0
            S01 += w * a0 * a1
            S11 += w * a1 * a1
            T0 += w * a0 * bi
            T1 += w * a1 * bi
        }

        let det = S00 * S11 - S01 * S01
        guard det != 0 else { return nil }

        let inv00 = S11 / det
        let inv01 = -S01 / det
        let inv11 = S00 / det

        let x = inv00 * T0 + inv01 * T1
        let y = inv01 * T0 + inv11 * T1

        let pos = CGPoint(x: CGFloat(x), y: CGFloat(y))

        if y < 50 || y > 4000 || x > 3000 || x < 0{
            return nil
        }
        
        /// Log with BLE position
        FusionLogger.shared.logBLEFrame(
            beacons: devices, distances: distances, fused: pos)

        return pos
    }
}

// MARK: - Core calculator (1‑ & 2‑beacon cases done)
struct PositionCalculator {

    /// Estimate a position from visible BLE beacons.
    /// - Parameters:
    ///   - devices:      Array of BLEDevice (must contain `position: CGPoint` and `rssi: Int`).
    ///   - maxBeacons:   If non‑nil, limit the ≥3‑beacon solver to the strongest N beacons.
    /// - Returns: `PositionResult` when at least one beacon is visible, else `nil`.
    static func calculate(
        devices: [BLEDevice], txPower: Int, pathLossExponent: Double,
        maxBeacons: Int? = nil
    ) -> PositionResult? {
        guard !devices.isEmpty else { return nil }
        let confidence = devices.count  // we always report the raw visible count

        switch devices.count {
        /// -----------------------------------------------------------
        case 1:
            /// Single beacon → just return the beacon’s own coordinates.
            //log.info("1 beacons: \(devices[0].position.x), \(devices[0].position.y)")
            let distances: [Double] = [
                PositionMath.rssiToDistance(
                    rssi: devices[0].rssi, txPower: txPower,
                    pathLossExponent: pathLossExponent)
            ]
            FusionLogger.shared.logBLEFrame(
                beacons: devices, distances: distances,
                fused: devices[0].position)

            return PositionResult(
                position: devices[0].position,
                confidence: confidence)

        /// -----------------------------------------------------------
        case 2:
            /// Two beacons → inverse‑distance interpolation along the line.
            let d1 = PositionMath.rssiToDistance(
                rssi: devices[0].rssi, txPower: txPower,
                pathLossExponent: pathLossExponent)
            let d2 = PositionMath.rssiToDistance(
                rssi: devices[1].rssi, txPower: txPower,
                pathLossExponent: pathLossExponent)

            let p = PositionMath.inverseDistancePoint(
                p1: devices[0].position, d1: d1,
                p2: devices[1].position, d2: d2
            )

            let distances: [Double] = [d1, d2]

            FusionLogger.shared.logBLEFrame(
                beacons: devices, distances: distances, fused: p)

            //log.info("2 beacons: \(p.x), \(p.y)")
            return PositionResult(position: p, confidence: confidence)

        /// -----------------------------------------------------------
        default:
            /// ≥3 beacons → weighted multilateration (next chunk).
            /// – Sort by RSSI (strongest first)
            /// – Optionally cap to `maxBeacons`
            /// – Run least‑squares solver

            /// ≥3 beacons → RSSI‑sorted, optional cap, then multilaterate
            var sorted = devices.sorted { $0.rssi > $1.rssi }  // strongest first
            if let max = maxBeacons, sorted.count > max {
                sorted.removeSubrange(max..<sorted.count)
            }
            /*
            let weighted = devices.map { device in
                let d = PositionMath.rssiToDistance(rssi: device.rssi, txPower: txPower, pathLossExponent: pathLossExponent)
                let w = 1.0 / max(d, 1.0)
                return (point: device.position, weight: w)
            }
            
            let totalWeight = weighted.reduce(0.0) { $0 + $1.weight }
            let avgX = weighted.reduce(0.0) { $0 + Double($1.point.x) * $1.weight } / totalWeight
            let avgY = weighted.reduce(0.0) { $0 + Double($1.point.y) * $1.weight } / totalWeight

            return PositionResult(
                position: CGPoint(x: avgX, y: avgY), confidence: confidence)
             */
            
            if let point = multilaterate(
                sorted, txPower: txPower, pathLossExponent: pathLossExponent)
            {
                //log.info("\(confidence) beacons: \(point.x), \(point.y)")
                return PositionResult(position: point, confidence: confidence)
            } else {
                /// Fallback: simple centroid if solver failed
                log.error(
                    "Failed to multilaterate beacons, falling back to centroid")
                let avgX =
                    sorted.reduce(0.0) { $0 + Double($1.position.x) }
                    / Double(sorted.count)
                let avgY =
                    sorted.reduce(0.0) { $0 + Double($1.position.y) }
                    / Double(sorted.count)
                return PositionResult(
                    position: CGPoint(x: avgX, y: avgY), confidence: confidence)
            }

        }
    }
}
