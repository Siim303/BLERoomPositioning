//
//  Calculation.swift
//  BLERoomPositioning
//
//  Created by Siim Turban on 01.04.2025.
//

import Foundation
import CoreGraphics

struct PositionCalculator {
    /// Converts RSSI to estimated distance using the path loss model.
    static func rssiToDistance(rssi: Int, txPower: Int = -59, pathLossExponent n: Double = 2.0) -> Double {
        return pow(10.0, (Double(txPower - rssi) / (10.0 * n)))
    }
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
