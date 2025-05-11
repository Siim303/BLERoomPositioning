//
//  PDRView.swift
//  BLERoomPositioning
//
//  Created by Siim Turban on 05.05.2025.
//
//  PDRView.swift – small tweaks for clarity
import SwiftUI

//struct PDRView: View {
    /*
    @StateObject private var pdr = PDRManager()

    var body: some View {
        VStack(spacing: 12) {
            Text("PDR demo").font(.title2).bold()

            metric("x", pdr.position.x)
            metric("y", pdr.position.y)
            metric("θ°", pdr.headingDeg)
            metric("steps", Double(pdr.stepCount))
            metric("L m", pdr.stepLength)
            //  PHONE — PDRView.swift (unchanged except show current sensor)
            Text("src: \(pdr.source == .watch ? "Watch" : "iPhone")")   // 1 = watch, 0 = phone


            Image(systemName: "arrow.up")           // heading pointer
                .rotationEffect(.degrees(pdr.headingDeg))
                .animation(.easeInOut, value: pdr.headingDeg)
                .padding(.top, 20)
        }
        .padding(30)
        .onAppear { pdr.start() }                   // don’t forget Info.plist key
        .onDisappear { pdr.stop() }
    }

    private func metric(_ label: String, _ value: Double) -> some View {
        HStack {
            Text(label).frame(width: 48, alignment: .leading)
            Spacer()
            Text(String(format: "%.2f", value)).monospacedDigit()
        }
    }
     */
//}
