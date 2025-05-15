//
//  BLEScanner.swift
//  BLERoomPositioning
//
//  Created by Siim Turban on 27.02.2025.
//

import Combine
import CoreGraphics
import CoreLocation
import Foundation
import os.log

class BLEScanner: NSObject, ObservableObject, CLLocationManagerDelegate {
    // MARK: - Published Properties
    @Published var rangedBeacons: [CLBeacon] = []  // Beacons detected via CoreLocation
    @Published var discoveredDevices: [BLEDevice] = []  // Mapped BLEDevice objects

    // MARK: - Configuration
    private let locationManager = CLLocationManager()
    private let beaconUUID = UUID(
        uuidString: "0888BB14-D8C5-4CEF-A3BC-F188427BA5BC")!
    private lazy var beaconConstraint = CLBeaconIdentityConstraint(
        uuid: beaconUUID)
    var beaconPositions: [String: CGPoint] = [:]  // minor string → position

    private let log = Logger(subsystem: "BLEScanner", category: "core")

    private var cancellable: AnyCancellable?  // NEW

    // MARK: - Timer for Simulation
    private var timer: Timer?

    // MARK: - Initialization
    override init() {
        super.init()
        /// Load beacon positions from JSON
        beaconPositions = BeaconPositionsManager.loadPositions()
        log.debug("beaconPositions: \(self.beaconPositions)")

        /// CoreLocation setup
        locationManager.delegate = self
        locationManager.requestWhenInUseAuthorization()

        /// 1.  React to beacon‑file updates posted by AddBeaconOverlay
        cancellable = NotificationCenter.default
            .publisher(for: .beaconPositionsDidChange)
            .sink { [weak self] _ in
                guard let self else { return }
                self.beaconPositions = BeaconPositionsManager.loadPositions()
                log.info("Reloaded beaconPositions: \(self.beaconPositions)")
            }
    }

    // MARK: - Public Scan Controls (legacy-compatible names)
    /// Starts iBeacon ranging (alias for startScanning)
    func startScanning() {
        locationManager.startRangingBeacons(satisfying: beaconConstraint)
    }

    /// Stops iBeacon ranging (alias for stopScanning)
    func stopScanning() {
        locationManager.stopRangingBeacons(satisfying: beaconConstraint)
    }

    // MARK: - CLLocationManagerDelegate
    func locationManager(
        _ manager: CLLocationManager,
        didChangeAuthorization status: CLAuthorizationStatus
    ) {
        if status == .authorizedWhenInUse || status == .authorizedAlways {
            startScanning()
        }
    }

    func locationManager(
        _ manager: CLLocationManager,
        didRange beacons: [CLBeacon],
        satisfying constraint: CLBeaconIdentityConstraint
    ) {
        DispatchQueue.main.async {
            self.rangedBeacons = beacons
            /// Map CLBeacons to BLEDevice for positional usage
            self.discoveredDevices = beacons.compactMap { beacon in
                let minorKey = String(beacon.minor.intValue)
                guard let position = self.beaconPositions[minorKey] else {
                    return nil
                }
                return BLEDevice(
                    uuid: beacon.uuid.uuidString,
                    name: minorKey,
                    rssi: beacon.rssi,
                    position: position,
                    lastSeen: Date()
                )
            }.sorted { $0.rssi > $1.rssi }
        }
    }

    // MARK: - Legacy Simulation
    func simulateBeaconData() {
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            var fakeBeacons: [BLEDevice] = []
            for (id, position) in self.beaconPositions {
                let oldRSSI = self.discoveredDevices.first(where: {
                    $0.uuid == id
                })?.rssi
                let newRSSI =
                    (oldRSSI ?? Int.random(in: -80 ... -40))
                    + Int.random(in: -2...2)
                let boundedRSSI = max(min(newRSSI, -40), -80)
                let fakeBeacon = BLEDevice(
                    uuid: id,
                    name: id,
                    rssi: boundedRSSI,
                    position: position,
                    lastSeen: Date()
                )
                fakeBeacons.append(fakeBeacon)
            }
            DispatchQueue.main.async {
                self.discoveredDevices = fakeBeacons.sorted {
                    $0.rssi > $1.rssi
                }
            }
        }

    }
    func stopSimulation() {
        if let timer = timer {
            timer.invalidate()
        }
    }
}
