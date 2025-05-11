//
//  Calculation.swift
//  BLERoomPositioning
//
//  Created by Siim Turban on 01.04.2025.
//

import Foundation
import CoreGraphics
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
    static func rssiToDistance(rssi: Int,
                               txPower: Int,  // Your measured RSSI at 1m
                               pathLossExponent: Double) -> Double {
        let ratio = Double(txPower - rssi)
        return pow(10.0, ratio / (10.0 * pathLossExponent))
    }

    /// Interpolates a point between two beacons using inverse‑distance weighting:
    ///   p = (d₂·p₁ + d₁·p₂) / (d₁ + d₂)
    /// so the estimate slides toward the stronger (smaller‑d) beacon.
    static func inverseDistancePoint(p1: CGPoint, d1: Double,
                                     p2: CGPoint, d2: Double) -> CGPoint {
        let x = (d2 * Double(p1.x) + d1 * Double(p2.x)) / (d1 + d2)
        let y = (d2 * Double(p1.y) + d1 * Double(p2.y)) / (d1 + d2)
        return CGPoint(x: x, y: y)
    }
}

extension PositionCalculator {
    // MARK: - Internal multilateration helper (≥3 beacons)
    /// Weighted least‑squares trilateration. Returns `nil` if the matrix is singular.
    private static func multilaterate(_ devices: [BLEDevice], txPower: Int, pathLossExponent: Double) -> CGPoint? {
        guard devices.count >= 3 else { return nil }

        // Distances (dᵢ) and weights (wᵢ = RSSI strength in [0,1])
        let distances = devices.map { PositionMath.rssiToDistance(rssi: $0.rssi, txPower: txPower, pathLossExponent: pathLossExponent) }
        var devDistances = ""
        for i in 0..<devices.count {
            devDistances += "\(devices[i].name): \((distances[i]*1000).rounded()/1000) | "
        }
        /// This whole line to just cut off 3 last characters of a string is Swift ¯\_(ツ)_/¯
        log.debug("\(devDistances[devDistances.startIndex..<devDistances.index(devDistances.endIndex, offsetBy: -3)])")
        
        let weights   = devices.map { d -> Double in
            let norm = (Double(d.rssi) + 100) / 70.0
            return max(0.1, min(1.0, norm))
        }
        
        log.debug("Weights: \(weights)")
        
        // Use the first beacon as the reference
        let ref = devices[0]
        let x0 = Double(ref.position.x), y0 = Double(ref.position.y), d0 = distances[0]

        // Build weighted normal equations  Σ w·aᵀa · x = Σ w·aᵀb
        var S00 = 0.0, S01 = 0.0, S11 = 0.0
        var T0  = 0.0, T1  = 0.0

        for i in 1..<devices.count {
            let xi = Double(devices[i].position.x)
            let yi = Double(devices[i].position.y)
            let di = distances[i]
            let w  = weights[i]

            let a0 = 2 * (xi - x0)
            let a1 = 2 * (yi - y0)
            let bi = d0*d0 - di*di + (xi*xi - x0*x0) + (yi*yi - y0*y0)

            S00 += w * a0 * a0
            S01 += w * a0 * a1
            S11 += w * a1 * a1
            T0  += w * a0 * bi
            T1  += w * a1 * bi
        }

        let det = S00 * S11 - S01 * S01
        guard det != 0 else { return nil }

        let inv00 =  S11 / det
        let inv01 = -S01 / det
        let inv11 =  S00 / det

        let x = inv00 * T0 + inv01 * T1
        let y = inv01 * T0 + inv11 * T1
        
        let pos = CGPoint(x: CGFloat(x), y: CGFloat(y))

        // Log again with fused position
        FusionLogger.shared.logFusionFrame(beacons: devices, distances: distances, fused: pos)
        
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
    static func calculate(devices: [BLEDevice], txPower: Int, pathLossExponent: Double, maxBeacons: Int? = nil) -> PositionResult? {
        guard !devices.isEmpty else { return nil }
        let confidence = devices.count            // we always report the raw visible count

        switch devices.count {
        // -----------------------------------------------------------
        case 1:
            // Single beacon → just return the beacon’s own coordinates.
            //log.info("1 beacons: \(devices[0].position.x), \(devices[0].position.y)")
            let distances: [Double] = [PositionMath.rssiToDistance(rssi: devices[0].rssi, txPower: txPower, pathLossExponent: pathLossExponent)]
            FusionLogger.shared.logFusionFrame(beacons: devices, distances: distances, fused: devices[0].position)
            
            return PositionResult(position: devices[0].position,
                                  confidence: confidence)

        // -----------------------------------------------------------
        case 2:
            // Two beacons → inverse‑distance interpolation along the line.
            let d1 = PositionMath.rssiToDistance(rssi: devices[0].rssi, txPower: txPower, pathLossExponent: pathLossExponent)
            let d2 = PositionMath.rssiToDistance(rssi: devices[1].rssi, txPower: txPower, pathLossExponent: pathLossExponent)

            let p = PositionMath.inverseDistancePoint(
                p1: devices[0].position, d1: d1,
                p2: devices[1].position, d2: d2
            )
            
            let distances: [Double] = [d1, d2]
            
            FusionLogger.shared.logFusionFrame(beacons: devices, distances: distances, fused: p)

            
            //log.info("2 beacons: \(p.x), \(p.y)")
            return PositionResult(position: p, confidence: confidence)

        // -----------------------------------------------------------
        default:
            // ≥3 beacons → weighted multilateration (next chunk).
            // – Sort by RSSI (strongest first)
            // – Optionally cap to `maxBeacons`
            // – Run least‑squares solver
            
            // ≥3 beacons → RSSI‑sorted, optional cap, then multilaterate
            var sorted = devices.sorted { $0.rssi > $1.rssi }          // strongest first
            if let max = maxBeacons, sorted.count > max {
                sorted.removeSubrange(max..<sorted.count)
            }

            if let point = multilaterate(sorted, txPower: txPower, pathLossExponent: pathLossExponent) {
                //log.info("\(confidence) beacons: \(point.x), \(point.y)")
                return PositionResult(position: point, confidence: confidence)
            } else {
                // Fallback: simple centroid if solver failed
                log.error("Failed to multilaterate beacons, falling back to centroid")
                let avgX = sorted.reduce(0.0) { $0 + Double($1.position.x) } / Double(sorted.count)
                let avgY = sorted.reduce(0.0) { $0 + Double($1.position.y) } / Double(sorted.count)
                return PositionResult(position: CGPoint(x: avgX, y: avgY), confidence: confidence)
            }
            
        }
    }
}



//struct PositionCalculator {
    /*
    /// Converts RSSI to estimated distance using the path loss model.
    static func rssiToDistance(rssi: Int, txPower: Int = -59, pathLossExponent n: Double = 2.0) -> Double {
        return pow(10.0, (Double(txPower - rssi) / (10.0 * n)))
    }*/
    /*
    /// Calculates the estimated position using a least-squares trilateration approach.
    /// Uses all available devices (requires at least 3) to solve for (x, y).
    static func calculatePosition(devices: [BLEDevice]) -> CGPoint? {
        guard devices.count >= 3 else { return nil }
        
        // Use the first device as the reference.
        let reference = devices[0]
        let x0 = reference.position.x
        let y0 = reference.position.y
        let d0 = rssiToDistance(rssi: reference.rssi)
        
        let m = devices.count - 1
        var A = [[Double]](repeating: [Double](repeating: 0.0, count: 2), count: m)
        var b = [Double](repeating: 0.0, count: m)
        
        for i in 1..<devices.count {
            let device = devices[i]
            let xi = device.position.x
            let yi = device.position.y
            let di = rssiToDistance(rssi: device.rssi)
            
            A[i - 1][0] = 2 * Double(xi - x0)
            A[i - 1][1] = 2 * Double(yi - y0)
            b[i - 1] = pow(d0, 2) - pow(di, 2) + Double(xi * xi - x0 * x0 + yi * yi - y0 * y0)
        }
        
        // Solve the normal equations: (A^T A) * [x, y]^T = A^T b
        var sumA0A0 = 0.0, sumA0A1 = 0.0, sumA1A1 = 0.0
        var sumA0b = 0.0, sumA1b = 0.0
        
        for i in 0..<m {
            sumA0A0 += A[i][0] * A[i][0]
            sumA0A1 += A[i][0] * A[i][1]
            sumA1A1 += A[i][1] * A[i][1]
            sumA0b += A[i][0] * b[i]
            sumA1b += A[i][1] * b[i]
        }
        
        let det = sumA0A0 * sumA1A1 - sumA0A1 * sumA0A1
        guard det != 0 else { return nil }
        
        let inv00 = sumA1A1 / det
        let inv01 = -sumA0A1 / det
        let inv10 = -sumA0A1 / det
        let inv11 = sumA0A0 / det
        
        let x = inv00 * sumA0b + inv01 * sumA1b
        let y = inv10 * sumA0b + inv11 * sumA1b
        
        return CGPoint(x: x, y: y)
    }
    */
    /// In Calculation.swift, replace your existing `calculatePosition` with a weighted least-squares version:
/*
    static func calculatePosition(devices: [BLEDevice]) -> CGPoint? {
        guard devices.count >= 3 else { return nil }
        
        // 1. Compute distances and weights
        //    We’ll weight each equation by signal strength: stronger RSSI → higher weight.
        let ds = devices.map { rssiToDistance(rssi: $0.rssi) }
        let ws = devices.map { device -> Double in
            // Normalize RSSI from [-100…-30] to [0…1], then square for weight
            let norm = (Double(device.rssi) + 100) / 70
            return max(0.1, min(1.0, norm))  // clamp
        }
        
        // 2. Pick reference
        let ref = devices[0]
        let x0 = ref.position.x, y0 = ref.position.y, d0 = ds[0]
        
        let m = devices.count - 1
        // Matrix A and vector b
        var A = [[Double]](repeating: [0,0], count: m)
        var b = [Double](repeating: 0, count: m)
        
        for i in 1..<devices.count {
            let dev = devices[i]
            let xi = dev.position.x, yi = dev.position.y, di = ds[i]
            
            A[i-1][0] = 2 * Double(xi - x0)
            A[i-1][1] = 2 * Double(yi - y0)
            b[i-1]    = pow(d0,2) - pow(di,2)
                      + Double(xi*xi - x0*x0 + yi*yi - y0*y0)
        }
        
        // 3. Assemble the weighted normal equations: (Aᵀ W A) x = Aᵀ W b
        var S00 = 0.0, S01 = 0.0, S11 = 0.0
        var T0  = 0.0, T1  = 0.0
        
        for i in 0..<m {
            let w = ws[i+1]  // weight for device i+1 (skip ref)
            let a0 = A[i][0], a1 = A[i][1], bi = b[i]
            S00 += w * a0 * a0
            S01 += w * a0 * a1
            S11 += w * a1 * a1
            T0  += w * a0 * bi
            T1  += w * a1 * bi
        }
        
        let det = S00 * S11 - S01 * S01
        guard det != 0 else { return nil }
        
        // 4. Solve for (x, y)
        let inv00 =  S11 / det
        let inv01 = -S01 / det
        let inv11 =  S00 / det
        
        let x = inv00 * T0 + inv01 * T1
        let y = inv01 * T0 + inv11 * T1
        
        return CGPoint(x: x, y: y)
    }

}
*/
