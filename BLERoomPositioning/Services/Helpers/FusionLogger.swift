//
//  FusionLogger.swift
//  BLERoomPositioning
//
//  Created by Siim Turban on 10.05.2025.
//

import Foundation
class FusionLogger {
    static let shared = FusionLogger()

    private let filename = "fusion_log.csv"
    private var fileHandle: FileHandle?
    
    private var loggingEnabled = true


    func setLogging(enabled: Bool) {
            loggingEnabled = enabled
        }
    
    private var fileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            .appendingPathComponent(filename)
    }

    private init() {
        deleteOldLogFile()
        openFile()
    }

    private func openFile() {
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            try? "source,timestamp,pred_x,pred_y,beacon_count,b1_name,b1_rssi,b1_dist,...\n".write(to: fileURL, atomically: true, encoding: .utf8)
        }
        fileHandle = try? FileHandle(forWritingTo: fileURL)
        fileHandle?.seekToEndOfFile()
    }
    
    private func deleteOldLogFile() {
        let manager = FileManager.default
        if manager.fileExists(atPath: fileURL.path) {
            do {
                try manager.removeItem(at: fileURL)
                print("🗑️ Old log file deleted")
            } catch {
                print("❌ Failed to delete old log file: \(error.localizedDescription)")
            }
        }
    }

    func logBLEFrame(beacons: [BLEDevice], distances: [Double], fused: CGPoint) {
        guard loggingEnabled else { return }

        let timestamp = ISO8601DateFormatter().string(from: Date())
        var row = "BLE,\(timestamp),\(fused.x),\(fused.y),\(beacons.count)"

        for (index, beacon) in beacons.enumerated() {
            let dist = distances[index]
            row += ",\(beacon.name),\(beacon.rssi),\(String(format: "%.2f", dist))"
        }

        row += "\n"

        if let data = row.data(using: .utf8) {
            fileHandle?.write(data)
        }
    }
    
    func logPDRFrame(fused: CGPoint) {
        guard loggingEnabled else { return }

        let timestamp = ISO8601DateFormatter().string(from: Date())
        let row = "PDR,\(timestamp),\(fused.x),\(fused.y),0\n"

        if let data = row.data(using: .utf8) {
            fileHandle?.write(data)
        }
    }
    
    func logFusedFrame(fused: CGPoint) {
        guard loggingEnabled else { return }
        
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let row = "Fused,\(timestamp),\(fused.x),\(fused.y),0\n"

        if let data = row.data(using: .utf8) {
            fileHandle?.write(data)
        }
    }
    


    /// Flush + close file for export, then reopen so logging can continue
    func prepareForExport() -> URL? {
        fileHandle?.synchronizeFile()
        fileHandle?.closeFile()
        fileHandle = nil

        openFile()

        return fileURL.standardizedFileURL
    }
}
