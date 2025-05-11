//
//  SettingsView.swift
//  BLERoomPositioning
//
//  Created by Siim Turban on 08.04.2025.
//
import SwiftUI

struct IdentifiableURL: Identifiable {
    let id = UUID()
    let url: URL
}

struct SettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel

    @State private var showExporter = false
    @State private var logFile: IdentifiableURL? = nil

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Positioning Options")) {
                    Toggle(
                        "Dead Reckoning",
                        isOn: $viewModel.isDeadReckoningEnabled)
                    Toggle("Confidence", isOn: $viewModel.isConfidenceEnabled)
                    Toggle(
                        "Beacon Simulation",
                        isOn: $viewModel.isBeaconSimulationEnabled)
                    Toggle(
                        "BLE Positioning",
                        isOn: $viewModel.isBLEPositioningEnabled)

                }

                Section(header: Text("Calibration")) {
                    VStack(alignment: .leading) {
                        Text(
                            "Accelerometer Sensitivity: \(String(format: "%.1f", viewModel.accelerometerSensitivity))"
                        )
                        Slider(
                            value: $viewModel.accelerometerSensitivity,
                            in: 10...100, step: 1)
                    }
                    VStack(alignment: .leading) {
                        Text(
                            "Path Loss Exponent: \(String(format: "%.1f", viewModel.pathLossExponent))"
                        )
                        Slider(
                            value: $viewModel.pathLossExponent, in: 1.0...4.0,
                            step: 0.1)
                    }
                    VStack(alignment: .leading) {
                        Text(
                            "Position Update Frequency (sec): \(String(format: "%.1f", viewModel.positionUpdateFrequency))"
                        )
                        Slider(
                            value: $viewModel.positionUpdateFrequency,
                            in: 0.1...5.0, step: 0.1)
                    }
                    VStack(alignment: .leading) {
                        Text(
                            "RSSI Reference Power (dBm): \(viewModel.rssiReferencePower)"
                        )
                        Slider(
                            value: Binding(
                                get: { Double(viewModel.rssiReferencePower) },
                                set: { viewModel.rssiReferencePower = Int($0) }
                            ), in: -90 ... -50, step: 1)
                    }
                }

                Section(header: Text("Debugging")) {
                    Toggle(
                        "Debug Logging", isOn: $viewModel.isDebugLoggingEnabled)
                }
                Button("Export Log File") {
                    FusionLogger.shared.setLogging(enabled: false)
                    if let url = FusionLogger.shared.prepareForExport(),
                       FileManager.default.fileExists(atPath: url.path) {
                        DispatchQueue.main.async {
                            self.logFile = IdentifiableURL(url: url)
                        }
                    }
                }.fullScreenCover(item: $logFile) { item in
                    LogExporter(fileURL: item.url)
                }

            }
            .navigationBarTitle("Settings", displayMode: .inline)
        }
    }
}
