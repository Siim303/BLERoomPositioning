//
//  ContentView.swift
//  BLERoomPositioning
//
//  Created by Siim Turban on 27.02.2025.
//

enum MapOption: String, CaseIterable {
    case house = "House"
    case delta2ndFloor = "Delta 2nd Floor"
    case pdr = "PDR"
}

import SwiftUI

struct ContentView: View {
    // Use only the injected environment object.
    @EnvironmentObject var settings: SettingsViewModel

    // Keep your view model as a StateObject.
    @StateObject private var viewModel = RoomPositioningViewModel()
    
    @State private var selectedMap: MapOption = .house //.delta2ndFloor

       
    var body: some View {
        NavigationView {
            ZStack {
                // App title.
                if !settings.isDebugLoggingEnabled {
                    //Text("BLE Room Positioning")
                        //.font(.title)
                        //.padding()
                } else {
                    Text("Debug mode")
                }
                /*
                if settings.isDebugLoggingEnabled {
                    VStack(alignment: .leading, spacing: 8) {
                        // List discovered BLE devices and their signal strengths.
                        ForEach(viewModel.discoveredDevices, id: \.uuid) { device in
                            Text("\(device.name): \(device.rssi) dBm")
                                .font(.subheadline)
                        }
                        /*
                        // Display the estimated (fused) position.
                        if let pos = viewModel.fusedPosition {
                            Text("Estimated Position: (\(String(format: "%.2f", pos.x)), \(String(format: "%.2f", pos.y)))")
                                .font(.headline)
                                .foregroundColor(.green)
                                .padding(.top)
                        } else {
                            Text("Estimating position...")
                                .font(.headline)
                                .foregroundColor(.orange)
                                .padding(.top)
                        }*/
                    }
                    .padding()
                }*/
                // Switch the displayed view depending on the selection.
                if selectedMap == .house {
                    RoomView(position: viewModel.fusedPosition,
                             beacons: viewModel.discoveredDevices,
                             mapImageName: "Room_background",
                             designSize: CGSize(width: 1000, height: 1000),
                             worldScale: CGFloat(250),
                             headingDeg: viewModel.headingDeg
                    )// What number do you need to divide designSize by to get 1m2 in real world
                    .ignoresSafeArea()
                } else if selectedMap == .delta2ndFloor {
                    RoomView(position: viewModel.fusedPosition,
                             beacons: viewModel.discoveredDevices,
                             mapImageName: "Delta_2korrus",
                             designSize: CGSize(width: 4000, height: 4000),
                             worldScale: CGFloat(30),
                             headingDeg: viewModel.headingDeg
                    )
                } else if selectedMap == .pdr {
                    //PDRView()
                }

                //Spacer()
            }
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(
                leading: menu,
                trailing: Button(action: {
                    viewModel.toggleSettingsView()
                }, label: {
                    Image(systemName: "gear")
                })
                .sheet(isPresented: $viewModel.showingSettings) {
                    SettingsView(viewModel: settings, positioningViewModel: viewModel)
                }
            )/*
            .navigationBarItems(trailing: Button(action: {
                viewModel.toggleSettingsView()
            }, label: {
                Image(systemName: "gear")
            }))
            .sheet(isPresented: $viewModel.showingSettings) {
                SettingsView(viewModel: settings)
            }*/
        }.onAppear {
            // Inject the environment settings into your view model.
            viewModel.updateSettings(with: settings)
            // Provide the GeometryProxy via a callback if needed.
            // Alternatively, since RoomView already has an onChange,
            // you may not need to set the callback explicitly.
            
        }
    }
    // The menu appears on the top left.
    var menu: some View {
        Menu {
            Button("House") {
                selectedMap = .house
            }
            Button("Delta 2nd Floor") {
                selectedMap = .delta2ndFloor
            }
            Button("PDR") {
                selectedMap = .pdr
            }
        } label: {
            Image(systemName: "line.horizontal.3")
        }
    }
}
