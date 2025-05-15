//
//  BeaconPositionsManager.swift
//  BLERoomPositioning
//
//  Created by Siim Turban on 08.04.2025.
//
// Merged loading & saving of beacon positions from and into json this one class
import CoreGraphics
import Foundation

struct BeaconCoordinate: Codable {
    let x: CGFloat
    let y: CGFloat
}

class BeaconPositionsManager {
    private static let filename = "BeaconPositions.json"

    // URL in Documents directory for user‐added beacon data
    private static var documentsURL: URL? {
        FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent(filename)
    }

    /// Loads beacon positions—first from Documents (if present), otherwise from the app bundle.
    static func loadPositions() -> [String: CGPoint] {
        // Try user‐saved file
        if let docURL = documentsURL,
            FileManager.default.fileExists(atPath: docURL.path),
            let data = try? Data(contentsOf: docURL),
            let decoded = try? JSONDecoder().decode(
                [String: BeaconCoordinate].self, from: data)
        {
            return decoded.mapValues { CGPoint(x: $0.x, y: $0.y) }
        }

        // Fallback to bundle resource
        guard
            let bundleURL = Bundle.main.url(
                forResource: "BeaconPositions", withExtension: "json"),
            let data = try? Data(contentsOf: bundleURL),
            let decoded = try? JSONDecoder().decode(
                [String: BeaconCoordinate].self, from: data)
        else {
            print("BeaconPositions.json not found or invalid")
            return [:]
        }

        return decoded.mapValues { CGPoint(x: $0.x, y: $0.y) }
    }

    /// Saves updated beacon positions to the Documents directory.
    static func savePositions(_ positions: [String: CGPoint]) {
        let encodable = positions.mapValues {
            BeaconCoordinate(x: $0.x, y: $0.y)
        }
        guard let data = try? JSONEncoder().encode(encodable),
            let docURL = documentsURL
        else {
            print("Failed to encode beacon positions or locate Documents URL")
            return
        }

        do {
            try data.write(to: docURL, options: .atomic)
        } catch {
            print("Error writing BeaconPositions.json to Documents: \(error)")
        }
    }
}
