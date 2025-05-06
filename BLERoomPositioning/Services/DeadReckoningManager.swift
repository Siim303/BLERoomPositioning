//
//  DeadReckoningManager.swift
//  BLERoomPositioning
//
//  Created by Siim Turban on 07.04.2025.
//
import CoreMotion
import SwiftUI
import CoreGraphics

class DeadReckoningManager: ObservableObject {
    private let motionManager = CMMotionManager()
    @Published var currentPosition: CGPoint = .zero
    private var lastUpdate: Date?
    private var velocity: CGVector = .zero
    // Adjust this factor to control how sensitive the integration is
    let accelerationScale: CGFloat = 50.0

    func startUpdates() {
        lastUpdate = Date()
        if motionManager.isAccelerometerAvailable {
            motionManager.accelerometerUpdateInterval = 0.1
            motionManager.startAccelerometerUpdates(to: OperationQueue.current ?? OperationQueue.main) { [weak self] data, error in
                guard let self = self, let data = data, error == nil else { return }
                self.handleAccelerometerData(data)
            }
        }
    }
    
    func stopUpdates() {
        motionManager.stopAccelerometerUpdates()
    }
    
    private func handleAccelerometerData(_ data: CMAccelerometerData) {
        guard let lastUpdate = self.lastUpdate else {
            self.lastUpdate = Date()
            return
        }
        let currentTime = Date()
        let dt = CGFloat(currentTime.timeIntervalSince(lastUpdate))
        self.lastUpdate = currentTime
        
        // Use x and y acceleration (adjust axis mapping as needed)
        let ax = CGFloat(data.acceleration.x)
        let ay = CGFloat(data.acceleration.y)
        
        // Update velocity using basic integration
        velocity.dx += ax * dt
        velocity.dy += ay * dt
        
        // Compute displacement with simple physics integration
        let dx = velocity.dx * dt + 0.5 * ax * dt * dt
        let dy = velocity.dy * dt + 0.5 * ay * dt * dt
        
        // Update current position with a scaling factor
        currentPosition = CGPoint(
            x: currentPosition.x + dx * accelerationScale,
            y: currentPosition.y + dy * accelerationScale)
    }
}

