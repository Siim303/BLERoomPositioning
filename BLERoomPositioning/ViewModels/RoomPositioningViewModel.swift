//
//  RoomPositioningViewModel.swift
//  BLERoomPositioning
//
//  Created by Siim Turban on 08.04.2025.
//
import SwiftUI
import Combine
import CoreGraphics
import os.log

class RoomPositioningViewModel: ObservableObject {
    // Published properties for UI binding
    @Published var fusedPosition: CGPoint = .zero
    @Published var headingDeg: Double = 0  // 👈 expose heading
    @Published var discoveredDevices: [BLEDevice] = []
    @Published var showingSettings: Bool = false
    @Published var centerOffset: CGSize = .zero
    
    // @Published var fusedPositionSetTime: Date? = nil
    
    // Service dependencies
    private var bleScanner: BLEScanner = BLEScanner()
    //private var deadReckoningManager: DeadReckoningManager = DeadReckoningManager() Legacy
    private var pdrManager: PDRManager = PDRManager()
    private var fusionManager: PositionFusionManager!

    private let log = Logger(subsystem: "PosViewModel", category: "core")
    
    // Injected settings (via updateSettings)
    private var settings: SettingsViewModel?
    
    // Combine cancellables for subscriptions
    private var cancellables = Set<AnyCancellable>()
    
    private var lastPos: CGPoint = CGPoint.zero
    
    // Minimal initializer
    init() {
        // Observe heading
        pdrManager.$headingDeg
            .receive(on: RunLoop.main)
            .assign(to: \.headingDeg, on: self)
            .store(in: &cancellables)
        updateSettings(with: SettingsViewModel())
        setupBindings()
        startServices()
    }
    
    deinit {
        pdrManager.stop()
        bleScanner.stopScanning()
    }

    
    func toggleSettingsView() {
        showingSettings.toggle()
    }
    
    // This method is used to inject the shared SettingsViewModel instance.
    func updateSettings(with settings: SettingsViewModel) {
        self.settings = settings
        // Subscribe to settings changes
        // Create fusionManager when settings become available
        fusionManager = PositionFusionManager(settings: settings, pdrManager: pdrManager)
        
        // This basically retrives position value from fusion class and publishes it
        fusionManager.$fusedPosition
            .assign(to: &$fusedPosition)
        /*
        fusionManager.$fusedPosition
            .sink { newPos in
                print("📡 Fusion updated: \(newPos)")
                self.fusedPosition = newPos
            }
            .store(in: &cancellables)
        */
        // Subscribe to the simulation toggle.
        settings.$isBeaconSimulationEnabled
            .sink { [weak self] newValue in
                guard let self = self else { return }
                log.info("Beacon simulation toggled: \(newValue)")
                if newValue { //this starts the simulating but also doesn't stop the scanning in the background
                    self.bleScanner.simulateBeaconData()
                } else {
                    self.bleScanner.stopSimulation()  // Make sure this method stops your timer
                    self.bleScanner.startScanning()
                }
            }
            .store(in: &cancellables)
        settings.$isBLEPositioningEnabled
            .sink { [weak self] newValue in
                guard let self = self else { return }
                log.info("BLE positioning toggled: \(newValue)")
                if newValue {
                    self.bleScanner.startScanning()
                } else {
                    self.bleScanner.stopScanning()
                    //print(fusedPosition?.x, fusedPosition?.y)
                }
            }
            .store(in: &cancellables)
    }
    
    // Sample binding setup for BLE data and sensor data updates.
    private func setupBindings() {
        // Send BLE updates to fusion class
        bleScanner.$discoveredDevices
            .sink { [weak self] devices in
                self?.discoveredDevices = devices
                self?.fusionManager.updateBLEDevices(devices)
            }
            .store(in: &cancellables)
        
        // Send PDR updates to fusion class
        // TODO: change from deadReckoning class to PDR class or connect them?
        /*
        deadReckoningManager.$currentPosition
            .sink { [weak self] position in
                self?.fusionManager.updatePDRPosition(position)
            }
            .store(in: &cancellables)
         */
        
        
    }
    
    private func startServices() {
        bleScanner.startScanning()
        pdrManager.start()
        //deadReckoningManager.startUpdates()
        //pdrManager = PDRManager()  // or however you're actually injecting it
    }
    
    // Minimal fusion logic using the injected settings.
    
    // MARK: This whole thing moved to PositionFusionManager class, to be removed from here
    //func updateFusedPosition() {
        //guard let settings = settings else { return }
        
        /*
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
            
            
        } else*/
        // MARK:  Thoughts about improvement
        // maybe update only once per 1 second so it looks smoother and not jumpy/indecisive
        //
        //
        //let fusedPos = fusedPosition ?? CGPoint.zero
        //print(pdrManager.computeDeadReckoningUpdate(from: fusedPos))
        //
        
        /* moving to PositionFusionManager class
        if settings.isBLEPositioningEnabled, let calculationResult = PositionCalculator.calculate(devices: discoveredDevices) {
            let blePosition = calculationResult.position
            let confidence = calculationResult.confidence
            
            //adjust position if needed
            // check for pdr info
            // check for previos position and decide if the change in position is possible on foot or if the pdr caught the travel
            
            fusedPosition = blePosition
            
        } else if settings.isDeadReckoningEnabled, let fusedPos = fusedPosition,
                  let pdrUpdate = pdrManager.computeDeadReckoningUpdate(from: fusedPos) {
            print("\(fusedPos.x), \(fusedPos.y) -> \(pdrUpdate.position.x), \(pdrUpdate.position.y)")
            fusedPosition = pdrUpdate.position
            
            
        }
        
        else {
            //...
        }*/
        
        /*else if settings.isDeadReckoningEnabled {
            fusedPosition = deadReckoningManager.currentPosition
            
        } else {
            fusedPosition = nil
        }*/
        
        // If autoCenter is enabled and there is a new position, call the callback immediately.
        // Later, in your update function:
        /* This block also seems pointless TODO: To be removed
        if let newPosition = fusedPosition, newPosition != lastPos {
            lastPos = newPosition
            //print("Fused position: \(newPosition), NanoTime: \(Date().timeIntervalSince1970 * 1000)")
        }*/
        
    //}
   
}
