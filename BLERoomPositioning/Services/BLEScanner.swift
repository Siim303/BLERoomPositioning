//
//  BLEScanner.swift
//  BLERoomPositioning
//
//  Created by Siim Turban on 27.02.2025.
//

import Foundation
import CoreLocation
import CoreGraphics
import Combine

class BLEScanner: NSObject, ObservableObject, CLLocationManagerDelegate {
    // MARK: - Published Properties
    @Published var rangedBeacons: [CLBeacon] = []            // Beacons detected via CoreLocation
    @Published var discoveredDevices: [BLEDevice] = []       // Mapped BLEDevice objects

    // MARK: - Configuration
    private let locationManager = CLLocationManager()
    private let beaconUUID = UUID(uuidString: "0888BB14-D8C5-4CEF-A3BC-F188427BA5BC")!
    private lazy var beaconConstraint = CLBeaconIdentityConstraint(uuid: beaconUUID)
    var beaconPositions: [String: CGPoint] = [:]              // minor string → position
    
    private var cancellable: AnyCancellable?        // NEW


    // MARK: - Timer for Simulation
    private var timer: Timer?

    // MARK: - Initialization
    override init() {
        super.init()
        // Load beacon positions from JSON
        beaconPositions = BeaconPositionsManager.loadPositions()
        print("beaconPositions: \(beaconPositions)")
        
        // CoreLocation setup
        locationManager.delegate = self
        locationManager.requestWhenInUseAuthorization()
        
        // 🔔 1.  React to beacon‑file updates posted by AddBeaconOverlay
        cancellable = NotificationCenter.default
            .publisher(for: .beaconPositionsDidChange)
            .sink { [weak self] _ in
                guard let self else { return }
                self.beaconPositions = BeaconPositionsManager.loadPositions()
                print("🔄 reloaded positions: \(self.beaconPositions)")
                // if your UI relies on discoveredDevices, rebuild them here too
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
    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        if status == .authorizedWhenInUse || status == .authorizedAlways {
            startScanning()
        }
    }

    func locationManager(_ manager: CLLocationManager,
                         didRange beacons: [CLBeacon],
                         satisfying constraint: CLBeaconIdentityConstraint) {
        DispatchQueue.main.async {
            self.rangedBeacons = beacons
            //print(beacons)
            // Map CLBeacons to BLEDevice for positional usage
            self.discoveredDevices = beacons.compactMap { beacon in
                let minorKey = String(beacon.minor.intValue)
                //print(minorKey)
                guard let position = self.beaconPositions[minorKey] else { return nil }
                //print(self.beaconPositions)
                return BLEDevice(
                    uuid: beacon.uuid.uuidString,
                    name: minorKey,
                    rssi: beacon.rssi,
                    position: position,
                    lastSeen: Date()
                )
            }.sorted { $0.rssi > $1.rssi }
            //print("discoveredDevices:", self.discoveredDevices)

        }
        //print(discoveredDevices)
    }

    // MARK: - Legacy Simulation
    func simulateBeaconData() {
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            var fakeBeacons: [BLEDevice] = []
            for (id, position) in self.beaconPositions {
                let oldRSSI = self.discoveredDevices.first(where: { $0.uuid == id })?.rssi
                let newRSSI = (oldRSSI ?? Int.random(in: -80 ... -40)) + Int.random(in: -2...2)
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
                self.discoveredDevices = fakeBeacons.sorted { $0.rssi > $1.rssi }
            }
        }
    }
}



/*  Legacy, I quess
class BLEScanner: NSObject, ObservableObject, CBCentralManagerDelegate {
    private var centralManager: CBCentralManager!
    @Published var discoveredDevices: [BLEDevice] = []
    private var timer: Timer?
    
    // Load beacon positions from an external JSON file via BeaconPositionsLoader.
    // Now uses iBeacon UUID strings as keys.
    // Now keyed by the beacon’s minor value (e.g. "0001" … "0017")
    var beaconPositions: [String: CGPoint] = [:]
    
    // Your shared iBeacon UUID, same on all 17 devices
    private let iBeaconUUID = "0888BB14-D8C5-4CEF-A3BC-F188427BA5BC".uppercased()
         
        
    override init() {
        super.init()
        // Load beacon coordinates from BeaconPositions.json
        beaconPositions = BeaconPositionsLoader.loadBeaconPositions() ?? [:]
                
        centralManager = CBCentralManager(delegate: self, queue: .main)
    }
    
    func simulateBeaconData() {
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            var fakeBeacons: [BLEDevice] = []
            for (id, position) in self.beaconPositions {
                let oldRSSI = self.discoveredDevices.first(where: { $0.uuid == id })?.rssi
                let newRSSI = (oldRSSI ?? Int.random(in: -80 ... -40)) + Int.random(in: -2...2)
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
                self.discoveredDevices = fakeBeacons.sorted { $0.rssi > $1.rssi }
            }
        }
    }

    func startScanning() {
        guard centralManager.state == .poweredOn else { return }
        discoveredDevices.removeAll()
        centralManager.scanForPeripherals(
            withServices: nil,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
        )
    }

    func stopScanning() {
        centralManager.stopScan()
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            startScanning()
        } else {
            print("Bluetooth is not available")
        }
    }
    
    func centralManager(_ central: CBCentralManager,
                        didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any],
                        rssi RSSI: NSNumber) {
        
        
        
        
        //print(advertisementData)
        

        // MARK: - iBeacon Detection
        guard let mfgData = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data else {
            return
        }
        
        //print("detected iBeacon advertising data (hex): \(mfgData.map { String(format: "%02X", $0) }.joined())")

        let bytes = [UInt8](mfgData)
        guard bytes.count >= 25 else { return }

        // Check Apple company ID (0x004C) and iBeacon prefix (0x02, 0x15)
        let companyId = UInt16(bytes[1]) << 8 | UInt16(bytes[0])
        //print(UInt16(bytes[1]) << 8 | UInt16(bytes[0]), bytes[2], bytes[3])
        if bytes[2] == 0x02, bytes[3] == 0x15{
            let line = bytes.enumerated()
                .map { "\($0):0x" + String(format: "%02x", $1) }
                .joined(separator: ", ")
            print(line)
        }
        
        guard companyId == 0x004C, bytes[2] == 0x02, bytes[3] == 0x15 else {
            return
        }
        

        // Extract and format the 16-byte UUID
        let uuidBytes = bytes[4..<20]
        let hex = uuidBytes.map { String(format: "%02X", $0) }.joined()
        let beaconUUID = [
            hex.prefix(8),
            hex.dropFirst(8).prefix(4),
            hex.dropFirst(12).prefix(4),
            hex.dropFirst(16).prefix(4),
            hex.dropFirst(20)
        ].joined(separator: "-")
        
        print("beaconUUID: \(beaconUUID)")
        
        // Only handle your own beacons
        guard beaconUUID.uppercased() == iBeaconUUID else {
            return
        }
        
        // Extract major & minor
        let major = (UInt16(bytes[20]) << 8) | UInt16(bytes[21])
        let minor = (UInt16(bytes[22]) << 8) | UInt16(bytes[23])
        let txPower = Int8(bitPattern: bytes[24])
        
        print("🔔 iBeacon \(beaconUUID) Major:\(major) Minor:\(minor) RSSI:\(RSSI.intValue) Tx:\(txPower)")
        
        // Use minor (0001–0017) as the key into your positions dictionary
        let minorKey = String(format: "%04d", minor)
        guard let position = beaconPositions[minorKey] else {
            print("Position not found for beacon minor \(minorKey)")
            return
        }
        
        let newDevice = BLEDevice(
            uuid: beaconUUID,
            name: minorKey,
            rssi: RSSI.intValue,
            position: position,
            lastSeen: Date()
        )
        
        // Update or append
        if let idx = discoveredDevices.firstIndex(where: { $0.uuid == newDevice.uuid && $0.name == newDevice.name }) {
            discoveredDevices[idx] = newDevice
        } else {
            discoveredDevices.append(newDevice)
        }
        
        discoveredDevices.sort { $0.rssi > $1.rssi }
    

        //=============== OLD FUNCTIONALITY (NAME-BASED) ===============
        // If you still need legacy support, uncomment below:
        //
        // guard let name = peripheral.name,
        //       name.range(of: #"^BLEpos\d{2}$"#, options: .regularExpression) != nil else { return }
        // print("🔔 Beacon \(name) (\(peripheral.identifier)) RSSI: \(RSSI.intValue)")
        // if let position = beaconPositions[name] {
        //     let device = BLEDevice(uuid: peripheral.identifier.uuidString,
        //                            name: name,
        //                            rssi: RSSI.intValue,
        //                            position: position,
        //                            lastSeen: Date())
        //     if let idx = discoveredDevices.firstIndex(where: { $0.uuid == device.uuid }) {
        //         discoveredDevices[idx] = device
        //     } else {
        //         discoveredDevices.append(device)
        //     }
        //     discoveredDevices.sort { $0.rssi > $1.rssi }
        // } else {
        //     print("Beacon position not found for \(name)")
        // }
        //===============================================================
    }
}
*/
