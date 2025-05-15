//
//  LogExporter.swift
//  BLERoomPositioning
//
//  Created by Siim Turban on 10.05.2025.
//
import SwiftUI
import UIKit

struct LogExporter: UIViewControllerRepresentable {
    let fileURL: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        print("📤 Attempting to export file at: \(fileURL.path)")
        let fileExists = FileManager.default.fileExists(atPath: fileURL.path)
        let readable = FileManager.default.isReadableFile(atPath: fileURL.path)
        print("🧾 File exists: \(fileExists), readable: \(readable)")

        if let fileData = try? Data(contentsOf: fileURL) {
            print("✅ Able to read file data, size: \(fileData.count) bytes")
        } else {
            print("❌ Failed to read file data")
        }
        let activityVC = UIActivityViewController(
            activityItems: [fileURL], applicationActivities: nil)
        return activityVC
    }

    func updateUIViewController(
        _ uiViewController: UIActivityViewController, context: Context
    ) {}
}
