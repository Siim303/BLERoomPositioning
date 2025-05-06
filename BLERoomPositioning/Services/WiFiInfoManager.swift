//
//  WiFiInfoManager.swift
//  BLERoomPositioning
//
//  Created by Siim Turban on 12.04.2025.
//

import UIKit
import CoreLocation
import SystemConfiguration.CaptiveNetwork
import NetworkExtension


class WiFiInfoManager: NSObject, CLLocationManagerDelegate {
    let locationManager = CLLocationManager()
    
    override init() {
        super.init()
        print("init WiFi manager")
        fetchWifiMethod()
        locationManager.delegate = self
        // Request location permission; required for accessing Wi-Fi info on iOS 13+
        locationManager.requestWhenInUseAuthorization()
    }
    
    func getCurrentWiFiInfo() -> (ssid: String?, bssid: String?) {
        guard let interfaceNames = CNCopySupportedInterfaces() as? [String],
              let interfaceName = interfaceNames.first,
              let networkInfo = CNCopyCurrentNetworkInfo(interfaceName as CFString) as? [String: Any] else {
                  print("Could not retrieve Wi-Fi info. Check if device is connected to Wi-Fi.")
                  return (nil, nil)
              }
        
        let ssid = networkInfo[kCNNetworkInfoKeySSID as String] as? String
        let bssid = networkInfo[kCNNetworkInfoKeyBSSID as String] as? String
        
        return (ssid, bssid)
    }
    
    // CLLocationManagerDelegate method
    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        switch status {
        case .authorizedWhenInUse, .authorizedAlways:
            let info = getCurrentWiFiInfo()
            print("SSID: \(info.ssid ?? "Unknown"), BSSID: \(info.bssid ?? "Unknown")")
        default:
            print("Location access denied or restricted.")
        }
    }
    
    func fetchWifiMethod() {
        NEHotspotNetwork.fetchCurrent { network in
            guard let network = network else {
                print("No Wi-Fi network information available. Ensure you meet one of the requirements and have the 'com.apple.developer.networking.wifi-info' capability enabled.")
                return
            }
            print("SSID: \(network.ssid)")
            print("BSSID: \(network.bssid)")
        }
    }
}
