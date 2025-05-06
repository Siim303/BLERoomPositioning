//
//  RoomPositioningViewModel.swift
//  BLERoomPositioning
//
//  Created by Siim Turban on 08.04.2025.
//
import SwiftUI
import Combine
import CoreGraphics

class RoomPositioningViewModel: ObservableObject {
    // Published properties for UI binding
    @Published var fusedPosition: CGPoint? = nil
    @Published var discoveredDevices: [BLEDevice] = []
    @Published var showingSettings: Bool = false
    @Published var centerOffset: CGSize = .zero
    
    // Service dependencies
    private var bleScanner: BLEScanner = BLEScanner()
    private var deadReckoningManager: DeadReckoningManager = DeadReckoningManager()
    
    // Injected settings (via updateSettings)
    private var settings: SettingsViewModel?
    
    // Combine cancellables for subscriptions
    private var cancellables = Set<AnyCancellable>()
    
    private var lastPos: CGPoint = CGPoint.zero
    
    // Minimal initializer
    init() {
        setupBindings()
        startServices()
    }
    
    func toggleSettingsView() {
        showingSettings.toggle()
    }
    
    // This method is used to inject the shared SettingsViewModel instance.
    func updateSettings(with settings: SettingsViewModel) {
        self.settings = settings
        // Subscribe to settings changes
        settings.$isDeadReckoningEnabled
            .sink { [weak self] _ in self?.updateFusedPosition() }
            .store(in: &cancellables)
        
        settings.$isConfidenceEnabled
            .sink { [weak self] _ in self?.updateFusedPosition() }
            .store(in: &cancellables)
        
        // Subscribe to the simulation toggle.
        settings.$isBeaconSimulationEnabled
            .sink { [weak self] newValue in
                guard let self = self else { return }
                print("Beacon simulation toggled: \(newValue)")
                if newValue {
                    self.bleScanner.simulateBeaconData()
                } else {
                    //self.bleScanner.stopSimulation()  // Make sure this method stops your timer
                    self.bleScanner.startScanning()
                }
            }
            .store(in: &cancellables)
    }
    
    // Sample binding setup for BLE data and sensor data updates.
    private func setupBindings() {
        bleScanner.$discoveredDevices
            .sink { [weak self] devices in
                self?.discoveredDevices = devices
                self?.updateFusedPosition()
            }
            .store(in: &cancellables)
        
        deadReckoningManager.$currentPosition
            .sink { [weak self] _ in
                self?.updateFusedPosition()
            }
            .store(in: &cancellables)
    }
    
    private func startServices() {
        bleScanner.startScanning()
        deadReckoningManager.startUpdates()
    }
    
    // Minimal fusion logic using the injected settings.
    func updateFusedPosition() {
        guard let settings = settings else { return }
        
        if settings.isConfidenceEnabled,
           let bleResult = PositionConfidence.calculatePositionWithConfidence(devices: discoveredDevices) {
            let blePosition = bleResult.position
            let confidence = bleResult.confidence
            let drPosition = settings.isDeadReckoningEnabled ? deadReckoningManager.currentPosition : CGPoint.zero
            let fusedX = blePosition.x * confidence + drPosition.x * (1.0 - confidence)
            let fusedY = blePosition.y * confidence + drPosition.y * (1.0 - confidence)
            fusedPosition = CGPoint(x: fusedX, y: fusedY)
            //print("Fused position: \(fusedPosition ?? CGPoint.zero)")
            //print("Debug info: \(settings.isDebugLoggingEnabled)")
            
            
        } else if let blePosition = PositionCalculator.calculatePosition(devices: discoveredDevices) {
            fusedPosition = blePosition
            
        } else if settings.isDeadReckoningEnabled {
            fusedPosition = deadReckoningManager.currentPosition
            
        } else {
            fusedPosition = nil
        }
        
        // If autoCenter is enabled and there is a new position, call the callback immediately.
        // Later, in your update function:
        if let newPosition = fusedPosition, newPosition != lastPos {
            lastPos = newPosition
            //print("Fused position: \(newPosition), NanoTime: \(Date().timeIntervalSince1970 * 1000)")
        }
        
    }
   
}
