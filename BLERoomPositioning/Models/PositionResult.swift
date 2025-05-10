//
//  PositionResult.swift
//  BLERoomPositioning
//
//  Created by Siim Turban on 08.04.2025.
//
import Foundation

struct PositionResult {
    let position: CGPoint   // The computed room coordinates (x, y)
    let confidence: Int  // A confidence score between 0.0 (low) and 1.0 (high) or now 1, 2, 3 … = number of beacons visible
}
