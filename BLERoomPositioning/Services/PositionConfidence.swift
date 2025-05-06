//
//  PositionConfidence.swift
//  BLERoomPositioning
//
//  Created by Siim Turban on 08.04.2025.
//
import Foundation
import CoreGraphics


struct PositionConfidence {
    
    /// Calculates the estimated position with an associated confidence score.
    /// The position is computed using the PositionCalculator's trilateration method.
    /// Confidence is derived from the average residual error between the expected and
    /// actual distances (based on RSSI) and from the number of BLE devices used.
    ///
    /// - Parameter devices: Array of BLEDevice objects containing signal and position data.
    /// - Returns: A PositionResult combining the computed position and its confidence,
    ///            or nil if not enough devices are provided.
    static func calculatePositionWithConfidence(devices: [BLEDevice]) -> PositionResult? {
        // Get the base position using trilateration from PositionCalculator.
        guard let position = PositionCalculator.calculatePosition(devices: devices) else { return nil }
        
        // Compute the total residual error across all devices.
        var totalError = 0.0
        for device in devices {
            let estimatedDistance = PositionCalculator.rssiToDistance(rssi: device.rssi)
            let actualDistance = hypot(position.x - device.position.x, position.y - device.position.y)
            totalError += abs(estimatedDistance - actualDistance)
        }
        
        let avgError = totalError / Double(devices.count)
        // Use an error threshold (tunable based on real-world calibration) to derive error confidence.
        let errorThreshold = 5.0
        let errorConfidence = max(0.0, 1.0 - avgError / errorThreshold)
        
        // Improve confidence with more beacon data; assume 5 devices yield full confidence.
        let countConfidence = min(1.0, Double(devices.count) / 5.0)
        
        // Combine both metrics (error accuracy and beacon quantity) into a single confidence score.
        let combinedConfidence = (errorConfidence + countConfidence) / 2.0
        
        return PositionResult(position: position, confidence: combinedConfidence)
    }
}
