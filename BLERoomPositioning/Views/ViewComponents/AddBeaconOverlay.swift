//
//  AddBeaconOverlay.swift
//  BLERoomPositioning
//
//  Created by Siim Turban on 06.05.2025.
//

// AddBeaconOverlay.swift
// A self‑contained UI component that lets the user add a beacon by:
//   1. tapping the “+” button (bottom‑left) → a red pin appears locked to screen‑centre
//   2. panning/zooming the map until the spot is under the pin
//   3. tapping the check‑mark → sheet asks for Beacon ID, shows picked X,Y
//   4. “Save” writes to BeaconPositions.json and posts .beaconPositionsDidChange

import SwiftUI
import CoreGraphics
import Combine

extension Notification.Name {
    static let beaconPositionsDidChange = Notification.Name("beaconPositionsDidChange")
}

struct AddBeaconOverlay: View {
    // bindings from RoomView
    @Binding var contentOffset: CGPoint
    @Binding var zoomScale: CGFloat
    let baseScale: CGFloat
    let designSize: CGSize

    // local UI state
    @State private var placing = false
    @State private var pickedPos: CGPoint = .zero
    @State private var beaconID = ""
    @State private var showSheet = false
    @State private var showHint = true                // first‑time helper text

    var body: some View {
        ZStack {
            // fixed pin while placing
            if placing {
                Image(systemName: "mappin")
                    .font(.largeTitle)
                    .foregroundColor(.red)
                    //.color(.purple)
                    .transition(.scale)
            }

            // bottom‑left control buttons
            VStack {
                Spacer()
                HStack {
                    VStack(spacing: 10) {
                        Button(action: mainButtonTapped) {
                            Image(systemName: placing ? "checkmark.circle.fill"
                                                      : "plus.circle")
                                .font(.title)
                                .padding(8)
                                .background(Color.white.opacity(0.85))
                                .clipShape(Circle())
                        }

                        if placing {                               // cancel button
                            Button("Cancel") { placing = false }
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.white.opacity(0.85))
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                    }
                    .padding()
                    Spacer()
                }
            }

            // one‑time hint
            if placing && showHint {
                VStack {
                    Text("Drag map to move pin, then press ✓")
                        .font(.caption)
                        .padding(6)
                        .background(Color.black.opacity(0.75))
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .padding(.top, 10)           // stick near the top edge
                    Spacer()                         // push everything else down
                }
                .transition(.opacity)
                .onTapGesture { showHint = false }
            }
        }
        // sheet to enter ID & confirm
        .sheet(isPresented: $showSheet) {
            NavigationView {
                Form {
                    Section("Picked coordinates") {
                        HStack { Text("x"); Spacer(); Text("\(Int(pickedPos.x))") }
                        HStack { Text("y"); Spacer(); Text("\(Int(pickedPos.y))") }
                    }
                    Section("Beacon ID") {
                        TextField("Enter number", text: $beaconID)
                            .keyboardType(.numberPad)
                    }
                }
                .navigationTitle("New Beacon")
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") { saveBeacon() }
                            .disabled(Int(beaconID) == nil)
                    }
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { showSheet = false }
                    }
                }
            }
        }
    }

    // MARK: – Actions

    private func mainButtonTapped() {
        if placing {
            let originShiftX = designSize.width
            let originShiftY = designSize.height
            // convert centre‑of‑screen to design coords
            let viewCenter = CGPoint(x: UIScreen.main.bounds.width / 2,
                                     y: UIScreen.main.bounds.height / 2)
            let designX = round((viewCenter.x + contentOffset.x - originShiftX) / (baseScale * zoomScale)*100.0)/100.0
            let designY = round((viewCenter.y + contentOffset.y - originShiftY) / (baseScale * zoomScale)*100.0)/100.0
            pickedPos = CGPoint(x: designX, y: designY)
            showSheet = true
        }
        placing.toggle()
    }

    private func saveBeacon() {
        guard let idInt = Int(beaconID) else { return }

        // 1. load existing json (if any)
        var dict = BeaconPositionsManager.loadPositions()   // [String: CGPoint]
        // 2. add / overwrite
        dict[String(idInt)] = pickedPos
        // 3. save back
        BeaconPositionsManager.savePositions(dict)
        // 4. notify listeners
        NotificationCenter.default.post(name: .beaconPositionsDidChange, object: nil)

        // reset UI
        beaconID = ""
        placing = false
        showSheet = false
    }
}
